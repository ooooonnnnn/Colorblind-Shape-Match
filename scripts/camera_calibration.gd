class_name CameraCalibration
extends RefCounted
## Measures the screen with a phone camera, patch by patch, and works out its
## calibration (see DisplayCalibration). The phone is only a light meter: the
## plan of what to show next lives here, answering each reading the phone
## posts (through CalibrationLink) with the next patch.
##
## A phone's browser can't give a page the camera's raw sensor data, which the
## article says true colorimetry needs: the picture has been through the
## phone's processing, whose tone curve is unknown, and many phones' browsers
## can't even fix the exposure, so it shifts from patch to patch. So the
## brightness curves are measured by matching, side by side in one picture: a
## solid circle in the middle of the screen, and around it rows of full light
## and black, too fine to be told apart, which give exactly a known share of
## full light (25%, 50%, 75%). The phone reads the middle and a ring around it
## in the same frame, so whatever the camera does to one it does to the other;
## the solid level the two read alike at is the code that gives that light (as
## in visual gamma charts, Lagom's among them). A search halves the gap
## between levels until they do. Lenses are darker toward their edges, so each
## search first shows one plain color over the whole screen to measure how
## much darker the ring reads, and takes that out.
##
## Where the phone can fix its exposure and white balance, more is measured.
## The matches also calibrate the camera itself: they say what each of its
## channels reads at a known share of white's light, which turns its readings
## into light. With that the red, green and blue primaries give the screen's
## color matrix, scaled so white stays white (white point preservation), and,
## when the white balance is fixed at daylight (6500 K), how far the screen's
## white is from D65. Last, the game's own colors are shown before and after
## the correction and compared by CIEDE2000. A camera that sees a patch
## brighter than it can record shows it as white, so these steps start by
## probing white, red, green and blue, the phone turning its exposure down until
## none clips, and start over should a later patch clip.
##
## A result that can't be right, such as matches running off their ranges or
## gammas no screen has, is marked untrusted, so it isn't put to use unseen.

signal patch_changed(patch: Dictionary)  ## see CalibrationScreen._show_patch
signal finished(result: Dictionary)  ## a DisplayCalibration state, or {} when stopped

const SETTLE_MS := 450  # for the screen to change and the camera's picture to catch up
const FRAMES := 4  # camera frames averaged per reading
const SEARCH_STEPS := 7  # halvings per match, to about 0.002 of the code range
## The level ranges the matches search: what gammas from 1.5 to 3.2 give each
## share of light at.
const GAMMAS := Vector2(1.5, 3.2)
const TRUSTED_GAMMAS := Vector2(1.6, 3.0)  # gammas real screens come to; outside, the reading is doubted
const MAX_GAMMA_SPREAD := 0.5  # most the channels' gammas may differ before the reading is doubted
const PROBES := {"white": Color.WHITE, "red": Color.RED, "green": Color.GREEN, "blue": Color.BLUE}
const TARGETS := {"gray": Color.WHITE, "r": Color.RED, "g": Color.GREEN, "b": Color.BLUE}
const SHARP_RIPPLE := 0.12  # stripe sharpness (see phone.html) past which the camera resolves them, skewing their average
const CLIP_LIMIT := 0.003  # share of the measured pixels at the camera's top before a reading counts as clipped
const MAX_DARKER := 14  # exposure steps down the phone is asked for, at most
const MAX_RESTARTS := 3  # times the measuring starts over for a clipped patch
const MAX_WHITE_SHIFT := 0.15  # largest cut to a channel to move white to D65, past which the reading is doubted
const MAX_GAMUT_CHANGE := 0.5  # largest change to the matrix from identity that is trusted

var locks := {}  # what the phone fixed: {exposure, white, white_daylight}
var progress := 0.0
## Whether the phone can fix its exposure and white balance, which the color
## steps need; set before measuring starts.
var can_lock := false
var notes_source := ""  # what the phone read: its camera's own frames, or the browser's video
var history: Array = []  # every reading and what was on screen, for looking into a bad result

var _plan: Array[Dictionary] = []
var _stage := 0
var _step := {}  # the patch being measured: {key, patch, lock, probe}
var _id := 0
var _readings := {}  # {key: Vector3 of the camera's average red, green and blue light}
var _found := {}  # {target/level: code}
var _warnings: Array[String] = []
var _end_hits := 0  # matches that ran off their range
var _result := {}
var _done := false
var _locked := false  # whether the phone has fixed its camera settings yet
var _darker := 0  # exposure steps down asked for so far
var _restarts := 0
var _total_steps := 0
var _steps_taken := 0
var _check_colors: Array[Dictionary] = []  # {name, color}
var _light: Callable  # a camera reading to light, once solved
var _to_d65 := Vector3.ONE  # each channel's cut that moves white to D65, as light


func _init(check_colors: Array[Dictionary]) -> void:
	_check_colors = check_colors


## Everything to measure, with nothing measured yet. Called once can_lock is known.
func start() -> void:
	_build_plan()


func _build_plan() -> void:
	_plan.clear()
	_readings.clear()
	_found.clear()
	_warnings.clear()
	_end_hits = 0
	_stage = 0
	_steps_taken = 0
	if can_lock:
		for key in PROBES:
			_plan.append({"kind": "fixed", "key": "probe/" + key, "patch": _solid(PROBES[key], false), "probe": true,
					"lock": key == "white" and not _locked})
		for key in ["black", "white", "red", "green", "blue"]:
			var color: Color = {"black": Color.BLACK, "white": Color.WHITE, "red": Color.RED, "green": Color.GREEN, "blue": Color.BLUE}[key]
			_plan.append({"kind": "fixed", "key": key, "patch": _solid(color, false)})
	for target in TARGETS:
		for level in DisplayCalibration.LEVELS:
			var lo := pow(level, 1.0 / GAMMAS.x)
			var hi := pow(level, 1.0 / GAMMAS.y)
			_plan.append({"kind": "search", "key": "%s/%s" % [target, level], "target": target, "level": level,
					"lo": minf(lo, hi), "hi": maxf(lo, hi), "taken": 0, "below": [], "above": [], "shading": null, "rows_sum": Vector3.ZERO})
	if can_lock:
		for check in _check_colors:
			_plan.append({"kind": "fixed", "key": "before/" + check.name, "patch": _solid(check.color, false)})
	_plan.append({"kind": "solve"})
	if can_lock:
		for check in _check_colors:
			_plan.append({"kind": "fixed", "key": "after/" + check.name, "patch": _solid(check.color, true)})
	_total_steps = TARGETS.size() * DisplayCalibration.LEVELS.size() * (1 + SEARCH_STEPS)
	if can_lock:
		_total_steps += PROBES.size() + 5 + _check_colors.size() * 2


static func _solid(color: Color, corrected: bool) -> Dictionary:
	return {"split": false, "color": color, "corrected": corrected}


## A solid circle of inner in the middle, and rows giving level of color's
## light all around: 1 row in 4, every other row, or 3 in 4.
static func split(inner: Color, color: Color, level: float) -> Dictionary:
	var rows := {"color": color, "period": 4, "on": 3}
	match level:
		0.25:
			rows.on = 1
		0.5:
			rows.period = 2
			rows.on = 1
	return {"split": true, "color": inner, "rows": rows, "corrected": false}


func current_patch() -> Dictionary:
	if _step.is_empty():
		_advance()
	return _step.get("patch", {})


func stop() -> void:
	if _done:
		return
	_done = true
	_step = {}
	finished.emit({})


## A reading from the phone: {id, rgb: [r, g, b] of the middle, outer: the
## ring around it, clip, cant_darken, locks}. Records it if it is for the
## patch on screen, and answers with the patch to measure next, and darker:
## true when the camera must turn its exposure down first.
func on_reading(data: Dictionary) -> Dictionary:
	if _done:
		return {"done": true, "text": "Done. Look at the results on the screen." if not _result.is_empty() else "Stopped."}
	if _step.is_empty():
		_advance()
	var rgb = data.get("rgb")
	var outer = data.get("outer", rgb)
	var darker := false
	if int(data.get("id", -1)) == _id and rgb is Array and rgb.size() == 3 and outer is Array and outer.size() == 3:
		history.append({"id": _id, "key": _step.key, "patch": _describe(_step.patch), "reading": data})
		if _step.get("lock", false):
			var got = data.get("locks", {})
			locks = got if got is Dictionary else {}
			_locked = true
		var clipped := float(data.get("clip", 0)) > CLIP_LIMIT
		if clipped and _locked and _can_go_darker(data):
			darker = true
			_darker += 1
			if not _step.get("probe", false):
				_restarts += 1
			_build_plan()
			_advance()
		else:
			if clipped and _locked:
				_warn("Some patches were too bright for the camera even at its darkest setting, so they may read low. Lower the screen's brightness a little and calibrate again if the results look off.")
			_record(_vector(rgb), _vector(outer))
			_advance()
	if _done:
		return {"done": true, "text": "Done. Look at the results on the screen."}
	return {"id": _id, "settle": SETTLE_MS, "frames": FRAMES, "lock": _step.get("lock", false), "darker": darker,
			"progress": progress, "text": "Too bright for the camera: turning it down and starting over…" if darker else ""}


static func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


static func _describe(patch: Dictionary) -> Dictionary:
	var out := {"color": "#" + (patch.color as Color).to_html(false), "split": patch.get("split", false), "corrected": patch.get("corrected", false)}
	if patch.get("split", false):
		out.rows = {"color": "#" + (patch.rows.color as Color).to_html(false), "period": patch.rows.period, "on": patch.rows.on}
	return out


## Whether a clipped reading can be cured by turning the exposure down.
func _can_go_darker(data: Dictionary) -> bool:
	if bool(data.get("cant_darken", false)) or _darker >= MAX_DARKER:
		return false
	return _step.get("probe", false) or _restarts < MAX_RESTARTS


func _record(inner: Vector3, outer: Vector3) -> void:
	_steps_taken += 1
	progress = clampf(float(_steps_taken) / _total_steps, 0, 1)
	var stage: Dictionary = _plan[_stage]
	if stage.kind == "fixed":
		_readings[stage.key] = inner
		return
	# A search: the plain color first, for how much darker the ring reads...
	if stage.shading == null:
		stage.shading = Vector3(outer.x / maxf(inner.x, 1e-5), outer.y / maxf(inner.y, 1e-5), outer.z / maxf(inner.z, 1e-5))
		return
	# ... then levels, each one halving the range.
	var rows: Vector3 = outer / (stage.shading as Vector3).clamp(Vector3.ONE * 0.2, Vector3.ONE * 5)
	stage.rows_sum += rows
	var mid: float = (stage.lo + stage.hi) / 2
	var sample := [mid, _brightness(inner) - _brightness(rows)]
	if sample[1] > 0:
		stage.hi = mid
		stage.above = sample
	else:
		stage.lo = mid
		stage.below = sample
	stage.taken += 1


## Moves on to the next patch still to measure, solving on the way.
func _advance() -> void:
	while _stage < _plan.size():
		var stage: Dictionary = _plan[_stage]
		match stage.kind:
			"fixed":
				if not _readings.has(stage.key):
					_set_step(stage)
					return
			"search":
				var color: Color = TARGETS[stage.target]
				var mid: float = (stage.lo + stage.hi) / 2
				var solid := Color(color.r * mid, color.g * mid, color.b * mid)
				if stage.shading == null:
					_set_step({"key": stage.key + "/shading", "patch": _solid(solid, false)})
					return
				if stage.taken < SEARCH_STEPS:
					_set_step({"key": "%s/%d" % [stage.key, stage.taken], "patch": split(solid, color, stage.level)})
					return
				_found[stage.key] = _match_level(stage)
			"solve":
				_solve()
				if not _result.get("notes", {}).get("checked", false):
					_plan.resize(_stage + 1)  # nothing to check against
				else:
					DisplayCalibration.set_state(_result)
		_stage += 1
	_finish()


func _set_step(step: Dictionary) -> void:
	_id += 1
	_step = step
	patch_changed.emit(step.patch)


## The level the middle reads the same as the rows at: between the nearest
## levels found brighter and darker, in proportion to their differences. Also
## keeps the camera's average reading of the rows, as the middle would read
## them, which is its reading of exactly that share of light in each channel
## (a solid gray at the matched level has it only on the whole).
func _match_level(stage: Dictionary) -> float:
	_readings[stage.key] = stage.rows_sum / maxf(stage.taken, 1)
	if stage.below.is_empty() or stage.above.is_empty():
		_end_hits += 1
		_warn("The %s match at %d%% ran off the end of its range." % [_target_name(stage.target), roundi(stage.level * 100)])
		return stage.lo if stage.below.is_empty() else stage.hi
	var below: Array = stage.below
	var above: Array = stage.above
	var span: float = above[1] - below[1]
	var t := clampf(-below[1] / span, 0, 1) if span > 0 else 0.5
	return lerpf(below[0], above[0], t)


static func _brightness(reading: Vector3) -> float:
	return reading.x + reading.y + reading.z


static func _target_name(target: String) -> String:
	return {"gray": "gray", "r": "red", "g": "green", "b": "blue"}[target]


func _warn(text: String) -> void:
	if not text in _warnings:
		_warnings.append(text)


## Works out the calibration from the readings.
func _solve() -> void:
	var curves := {}
	var gammas := {}
	for channel in DisplayCalibration.CHANNELS:
		var codes := []
		for level in DisplayCalibration.LEVELS:
			codes.append(_found["%s/%s" % [channel, level]])
		curves[channel] = codes
		gammas[channel] = snappedf(log(0.5) / log(codes[1]), 0.01)
	gammas["gray"] = snappedf(log(0.5) / log(_found["gray/0.5"]), 0.01)
	var notes := {"gammas": gammas, "exposure_locked": bool(locks.get("exposure", false)),
			"white_locked": bool(locks.get("white", false)), "white_daylight": bool(locks.get("white_daylight", false)),
			"gamut_used": false, "white_used": false, "checked": false, "source": notes_source, "trusted": true}
	_result = {"method": "camera", "date": Time.get_datetime_string_from_system(), "curves": curves,
			"gamut": [[1, 0, 0], [0, 1, 0], [0, 0, 1]], "white_gain": [1, 1, 1], "tint": [0, 0], "notes": notes, "enabled": true}
	# A result no screen could give means the measuring went wrong.
	var problems: Array[String] = []
	if _end_hits > 1:
		problems.append("%d of the 12 matches ran off the end of their range" % _end_hits)
	var lowest := INF
	var highest := -INF
	for channel in ["r", "g", "b", "gray"]:
		lowest = minf(lowest, gammas[channel])
		highest = maxf(highest, gammas[channel])
	if lowest < TRUSTED_GAMMAS.x or highest > TRUSTED_GAMMAS.y:
		problems.append("gammas from %.2f to %.2f, where screens come to about 1.8 to 2.6" % [lowest, highest])
	elif highest - lowest > MAX_GAMMA_SPREAD:
		problems.append("the channels' gammas differ by %.2f, far more than screens do" % (highest - lowest))
	if not problems.is_empty():
		notes.trusted = false
		notes.problem = "; ".join(problems)
		notes.causes = _likely_causes()
		return
	if not can_lock:
		_warn("The phone's browser couldn't fix the camera's exposure and white balance, so only the brightness curves were measured. Chrome on Android usually can.")
		return
	# The camera's reading of each channel at known shares of white's light.
	var known := [0.0, 0.25, 0.5, 0.75, 1.0]
	var seen: Array[Vector3] = [_readings.black]
	for level in DisplayCalibration.LEVELS:
		seen.append(_readings["gray/%s" % level])
	seen.append(_readings.white)
	for k in 3:
		for i in range(1, seen.size()):
			if seen[i][k] <= seen[i - 1][k]:
				_warn("The camera's readings didn't climb with the light (was the phone moved?), so only the brightness curves were measured.")
				return
	# Smoothly between them, as the camera's tone curve bends.
	var curves_seen: Array[PackedFloat32Array] = []
	for k in 3:
		var xs := PackedFloat32Array()
		for reading in seen:
			xs.append(reading[k])
		curves_seen.append(xs)
	var light := func(reading: Vector3) -> Vector3:
		var out := Vector3.ZERO
		for k in 3:
			out[k] = DisplayCalibration.monotone(curves_seen[k], PackedFloat32Array(known), reading[k])
		return out
	# The primaries, as the camera sees them, scaled so they add up to white.
	var primaries := Basis(light.call(_readings.red), light.call(_readings.green), light.call(_readings.blue))
	if absf(primaries.determinant()) < 1e-4:
		_warn("The red, green and blue readings were too alike to work out the screen's colors.")
		return
	var scale := primaries.inverse() * Vector3.ONE
	if scale.x < 0.7 or scale.y < 0.7 or scale.z < 0.7 or scale.x > 1.3 or scale.y > 1.3 or scale.z > 1.3:
		_warn("Red, green and blue didn't add up to white (the screen may change its brightness with what it shows), so its colors were left as they are.")
	else:
		primaries = primaries * Basis.from_scale(scale)
		var gamut := primaries.inverse()
		var change := 0.0
		for i in 3:
			for k in 3:
				change = maxf(change, absf(gamut[i][k] - Basis.IDENTITY[i][k]))
		if change > MAX_GAMUT_CHANGE:
			_warn("The screen's colors measured too far from standard to trust the camera, so they were left as they are.")
		else:
			notes.gamut_used = true
			_result.gamut = _rows(gamut)
	# White: with the camera fixed at daylight, a D65 white reads neutral.
	var to_d65 := Vector3.ONE
	if notes.white_daylight:
		var white: Vector3 = _readings.white - _readings.black
		if white.x > 0 and white.y > 0 and white.z > 0:
			var cut := Vector3.ONE * minf(white.x, minf(white.y, white.z)) / white
			if cut.x < 1 - MAX_WHITE_SHIFT or cut.y < 1 - MAX_WHITE_SHIFT or cut.z < 1 - MAX_WHITE_SHIFT:
				_warn("The screen's white measured too far from daylight white to trust, so it was left as it is.")
			else:
				to_d65 = cut
				notes.white_used = true
				var gamut_now := _basis(_result.gamut) * Basis.from_scale(to_d65)
				_result.gamut = _rows(gamut_now)
	notes.white_cut = [to_d65.x, to_d65.y, to_d65.z]
	notes.checked = not _check_colors.is_empty()
	_light = light
	_to_d65 = to_d65


## What the readings say went wrong, in words to act on: sharp stripes, too
## much light for the camera, or the phone moving.
func _likely_causes() -> Array[String]:
	var causes: Array[String] = []
	var ripples: Array[float] = []
	var clipped := 0
	var edges: Array[float] = []
	for entry in history:
		var reading: Dictionary = entry.reading
		if entry.patch.split:
			ripples.append(float(reading.get("ripple", 0)))
			if reading.get("edge") != null:
				edges.append(float(reading.edge))
		if float(reading.get("clip", 0)) > CLIP_LIMIT:
			clipped += 1
	ripples.sort()
	if not ripples.is_empty() and ripples[ripples.size() / 2] > SHARP_RIPPLE:
		causes.append("The camera saw the stripes sharply, so it didn't average them. Bring the phone closer to the screen, so the picture is blurry.")
	if clipped > history.size() / 4:
		causes.append("Much of the picture was too bright for the camera, and turning it down didn't help. Lower the screen's brightness a little for calibrating.")
	edges.sort()
	if edges.size() > 4 and edges[edges.size() * 9 / 10] - edges[edges.size() / 10] > 0.25:
		causes.append("The circle moved around in the camera's picture, so the phone moved. Rest it on something; you can drag the circle to a spot where it can rest.")
	return causes


static func _rows(b: Basis) -> Array:
	var t := b.transposed()
	return [[t[0].x, t[0].y, t[0].z], [t[1].x, t[1].y, t[1].z], [t[2].x, t[2].y, t[2].z]]


static func _basis(rows: Array) -> Basis:
	return Basis(Vector3(rows[0][0], rows[0][1], rows[0][2]), Vector3(rows[1][0], rows[1][1], rows[1][2]),
			Vector3(rows[2][0], rows[2][1], rows[2][2])).transposed()


## Compares the check colors before and after, then ends.
func _finish() -> void:
	_done = true
	_step = {}
	var notes: Dictionary = _result.get("notes", {})
	if notes.get("checked", false):
		for when in ["before", "after"]:
			var total := 0.0
			var worst := 0.0
			var worst_name := ""
			for check in _check_colors:
				var reading: Vector3 = _light.call(_readings["%s/%s" % [when, check.name]])
				var seen_lab := DisplayCalibration.lab(reading / _to_d65)
				var wanted: Color = (check.color as Color).srgb_to_linear()
				var delta := DisplayCalibration.delta_e(DisplayCalibration.lab(Vector3(wanted.r, wanted.g, wanted.b)), seen_lab)
				total += delta
				if delta > worst:
					worst = delta
					worst_name = check.name
			notes[when] = {"mean": snappedf(total / _check_colors.size(), 0.01), "max": snappedf(worst, 0.01), "worst": worst_name}
	notes.warnings = _warnings
	_result.notes = notes
	progress = 1.0
	finished.emit(_result)
