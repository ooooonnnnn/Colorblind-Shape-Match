class_name RawCalibration
extends RefCounted
## Measures the screen with the Shape Match Meter app (calibration/meter),
## which reads the phone camera's raw sensor data: the article's way. Raw
## data is the light itself, before the phone's tone curve, sharpening and
## color boosting, so no matching is needed: grays and each channel are shown
## at a run of levels, and the light each gives is read directly, black taken
## off. The screen's brightness curves come straight from that.
##
## Two things are not taken on trust. Every color is a disc on a white screen
## and the meter reads the white around it in the same picture, as some
## screens dim or brighten with what they show (dynamic contrast, adaptive
## brightness): the readings are scaled by that white, and the whole screen
## changes little anyway. And the meter measures white at a run of exposure
## times, light going with the time, so raw data that isn't quite linear is
## straightened.
##
## The curves are balanced on grays: each level's gray is nudged, channel by
## channel, until the camera sees it as a dimmer copy of the white, in its raw
## colors. No color matrix is needed for that, which matters: a camera's
## matrix (as in DNG files, the article's 3x3 matrix T) is made for daylight
## scenes, and on the user's screen it put white far off D65 and red, green
## and blue didn't add up to white (16% over), so the screen's white and color
## range are left as they are. The matrix is still used to compare the game's
## own colors before and after by CIEDE2000, against the screen's white.
##
## Works alongside CameraCalibration, with the same signals and calls, so the
## calibration steps can use either.

signal patch_changed(patch: Dictionary)  ## see CalibrationScreen._show_patch
signal finished(result: Dictionary)  ## a DisplayCalibration state, or {} when stopped

const SETTLE_MS := 400  # for the screen to change before the meter takes its pictures
const FRAMES := 3  # raw pictures averaged per reading
const STEPS := [0.04, 0.08, 0.12, 0.17, 0.23, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]  # codes each channel is shown at
const CHANNELS := {"r": Color.RED, "g": Color.GREEN, "b": Color.BLUE}
const CHANNEL_NAMES := {"r": "Red", "g": "Green", "b": "Blue"}
## The run's parts in order, as the meter and the screen tell them while measuring.
const STAGES := [
	{"id": "setup", "name": "White & black", "about": "The brightest and darkest this screen can show."},
	{"id": "r", "name": "Red", "about": "How bright red gets, step by step, from dim to full."},
	{"id": "g", "name": "Green", "about": "How bright green gets, step by step, from dim to full."},
	{"id": "b", "name": "Blue", "about": "How bright blue gets, step by step, from dim to full."},
	{"id": "gray", "name": "Grays", "about": "Grays from dark to light, to make each one a true gray."},
	{"id": "before", "name": "Game colors", "about": "The game's own colors, as this screen shows them now."},
	{"id": "after", "name": "Checking", "about": "The same colors with the calibration on, to see the difference."},
]
const CLIP_LIMIT := 0.001  # share of clipped pixels that makes a reading too bright
const MAX_DARKER := 10
const TRUSTED_GAMMAS := Vector2(1.6, 3.0)
const NUDGE_STEP := 0.05  # codes either side of a gray, to see how each channel moves its color
const MAX_NUDGE := 0.12  # most a channel's code is moved from the gray's to balance it; more is doubted
const D65_ILLUMINANT := 21  # the EXIF light source code cameras give their matrices for
const AIM_PATCH := {"disc": true, "color": Color.BLACK, "background": Color.WHITE, "corrected": false}  # to line the phone up with
const DIM_RAW := 0.25  # raw readings below this are taken as linear, to scale the straightening by
const MAX_BRACKET_SPREAD := 0.1  # bracket steps whose pictures disagreed more (flicker) are left out
const STRAIGHTEN_RANGE := Vector2(0.6, 2.0)  # how far straightening may move the top raw reading before the bracket is doubted
const SCREEN_DRIFT := 0.03  # how far the white around the disc may vary before the screen is said to change with its content

var progress := 0.0
var can_lock := true
var notes_source := "the camera's raw sensor data, through Shape Match Meter"
var history: Array = []  # every reading and what was on screen
var locks := {}

var _to_xyz := Basis.IDENTITY  # camera raw to XYZ
var _has_matrix := false
var _plan: Array[Dictionary] = []
var _stage := 0
var _step := {}
var _id := 0
var _readings := {}  # {key: Vector3 of raw red, green and blue}
var _warnings: Array[String] = []
var _result := {}
var _done := false
var _locked := false
var _darker := 0
var _total_steps := 0
var _steps_taken := 0
var _check_colors: Array[Dictionary] = []
var _straight: Array = []  # per channel, [raw values climbing, light], from the bracket; empty to leave raw as it is
var _straightened := 1.0  # light over raw at the top of the bracket, for the notes
var _around := {}  # {corrected: the first white-around reading}, what the others are scaled to
var _arounds: Array[float] = []  # the white around every uncorrected reading


func _init(check_colors: Array[Dictionary], phone: Dictionary) -> void:
	_check_colors = check_colors.duplicate()
	_check_colors.push_front({"name": "white", "color": Color.WHITE})  # the reference white for the comparison
	_read_matrix(phone)


## The camera's raw to XYZ, from the matrix it gives for D65 light, or its
## second (usually daylight) one: raw = calibration x color matrix x XYZ.
func _read_matrix(phone: Dictionary) -> void:
	var which := 2 if int(phone.get("illuminant2", 0)) == D65_ILLUMINANT or int(phone.get("illuminant1", 0)) != D65_ILLUMINANT else 1
	var matrix = phone.get("color_matrix%d" % which, phone.get("color_matrix1"))
	if not (matrix is Array and matrix.size() == 9):
		return
	var to_camera := _rows_to_basis(matrix)
	var calibration = phone.get("calibration%d" % which)
	if calibration is Array and calibration.size() == 9:
		to_camera = _rows_to_basis(calibration) * to_camera
	if absf(to_camera.determinant()) < 1e-9:
		return
	_to_xyz = to_camera.inverse()
	_has_matrix = true


static func _rows_to_basis(values: Array) -> Basis:
	return Basis(Vector3(values[0], values[1], values[2]), Vector3(values[3], values[4], values[5]),
			Vector3(values[6], values[7], values[8])).transposed()


func start() -> void:
	_build_plan()


func _build_plan() -> void:
	_plan.clear()
	_readings.clear()
	_around.clear()
	_arounds.clear()
	_stage = 0
	_steps_taken = 0
	_plan.append({"key": "white", "patch": _solid(Color.WHITE), "lock": not _locked, "stage": "setup", "title": "White"})
	_plan.append({"key": "black", "patch": _solid(Color.BLACK), "stage": "setup", "title": "Black"})
	for channel in CHANNELS:
		var full: Color = CHANNELS[channel]
		for code in STEPS:
			_plan.append({"key": "%s/%s" % [channel, code], "patch": _solid(Color(full.r * code, full.g * code, full.b * code)),
					"stage": channel, "title": "%s at %d%%" % [CHANNEL_NAMES[channel], roundi(code * 100)]})
	for code in STEPS:
		_plan.append({"key": "gray/%s" % code, "patch": _solid(Color(code, code, code)), "stage": "gray", "title": "Gray at %d%%" % roundi(code * 100)})
	for check in _check_colors:
		_plan.append({"key": "before/" + check.name, "patch": _solid(check.color), "stage": "before", "title": (check.name as String).capitalize()})
	_plan.append({"kind": "solve"})
	for check in _check_colors:
		_plan.append({"key": "after/" + check.name, "patch": _solid(check.color, true), "stage": "after", "title": (check.name as String).capitalize()})
	_total_steps = _plan.size() - 1


static func _solid(color: Color, corrected := false) -> Dictionary:
	return {"disc": true, "color": color, "background": Color.WHITE, "corrected": corrected}


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


## A reading from the meter: {id, rgb, clip, cant_darken, locks}. Records it
## if it is for the patch on screen and answers with the next.
func on_reading(data: Dictionary) -> Dictionary:
	if _done:
		return {"done": true, "text": "Done. Look at the results on the screen." if not _result.is_empty() else "Stopped."}
	if _step.is_empty():
		_advance()
	var rgb = data.get("rgb")
	var darker := false
	if int(data.get("id", -1)) == _id and rgb is Array and rgb.size() == 3:
		history.append({"id": _id, "key": _step.key, "patch": CameraCalibration._describe(_step.patch), "reading": data})
		if _step.get("lock", false):
			var got = data.get("locks", {})
			locks = got if got is Dictionary else {}
			_locked = true
			_read_bracket(locks.get("bracket"))
		var clipped := float(data.get("clip", 0)) > CLIP_LIMIT
		if clipped and not bool(data.get("cant_darken", false)) and _darker < MAX_DARKER:
			darker = true
			_darker += 1
			_build_plan()
			_advance()
		else:
			if clipped:
				_warn("Some patches were too bright for the camera even at its shortest exposure, so they may read low.")
			_steps_taken += 1
			progress = clampf(float(_steps_taken) / _total_steps, 0, 1)
			_readings[_step.key] = _light(data, _step.patch.corrected)
			_advance()
	if _done:
		return {"done": true, "text": "Done. Look at the results on the screen."}
	return {"id": _id, "settle": SETTLE_MS, "frames": FRAMES, "lock": _step.get("lock", false), "darker": darker,
			"progress": progress, "text": "Too bright for the camera: turning it down and starting over…" if darker else "",
			"show": showing(), "stages": STAGES}


## What is on screen now, for the meter and this screen to tell: {stage (an
## index into STAGES), title, step and steps within the stage, color}.
func showing() -> Dictionary:
	if _step.is_empty():
		return {}
	var stage := 0
	for i in STAGES.size():
		if STAGES[i].id == _step.get("stage", ""):
			stage = i
	var step := 0
	var steps := 0
	for planned in _plan:
		if planned.get("stage", "") == _step.stage:
			steps += 1
			if planned.key == _step.key:
				step = steps
	return {"stage": stage, "title": _step.title, "step": step, "steps": steps, "color": "#" + (_step.patch.color as Color).to_html(false)}


func _advance() -> void:
	while _stage < _plan.size():
		var stage: Dictionary = _plan[_stage]
		if stage.get("kind", "") == "solve":
			_solve()
			if not _result.notes.get("checked", false):
				_plan.resize(_stage + 1)
			else:
				DisplayCalibration.set_state(_result)
		elif not _readings.has(stage.key):
			_id += 1
			_step = stage
			patch_changed.emit(stage.patch)
			return
		_stage += 1
	_finish()


## The camera's response, from the bracket ([ns, red, green, blue, spread]
## per step): at the dim end, where raw data is surely linear, light per ns
## (and any offset) is fitted, and each step's raw value is paired with the
## light its time gave. Left out when the bracket is too short or uneven.
func _read_bracket(steps: Variant) -> void:
	_straight.clear()
	_straightened = 1.0
	if not steps is Array:
		return
	var usable: Array = (steps as Array).filter(func(s): return s is Array and s.size() >= 4 and (s.size() < 5 or float(s[4]) <= MAX_BRACKET_SPREAD))
	if usable.size() < 4:
		return
	var tables: Array = []
	for c in 3:
		var points: Array = usable.map(func(s): return Vector2(float(s[c + 1]), float(s[0])))
		points.sort_custom(func(a, b): return a.y < b.y)
		for i in range(1, points.size()):
			if points[i].x <= points[i - 1].x:
				return  # more time gave less light: flicker or movement
		# raw = slope * time + offset over the dim steps
		var dim: Array = points.filter(func(p): return p.x < DIM_RAW)
		if dim.size() < 2:
			return
		var mean := Vector2.ZERO
		for p in dim:
			mean += p
		mean /= dim.size()
		var spread := 0.0
		var together := 0.0
		for p in dim:
			spread += (p.y - mean.y) * (p.y - mean.y)
			together += (p.y - mean.y) * (p.x - mean.x)
		if spread <= 0 or together <= 0:
			return
		var slope := together / spread
		var offset := mean.x - slope * mean.y
		var raws := PackedFloat32Array([offset])
		var lights := PackedFloat32Array([0.0])
		for p in points:
			if p.x > raws[-1]:
				raws.append(p.x)
				lights.append(slope * p.y)
		tables.append([raws, lights])
		var ratio := lights[-1] / maxf(raws[-1] - offset, 1e-6)
		if ratio < STRAIGHTEN_RANGE.x or ratio > STRAIGHTEN_RANGE.y:
			_warn("The camera's measurements at different exposures didn't fit together, so its raw data was used as it is.")
			return
		if c == 1:
			_straightened = ratio
	_straight = tables


## Raw readings as light, through the bracket's response.
func _straighten(raw: Vector3) -> Vector3:
	if _straight.is_empty():
		return raw
	var out := Vector3.ZERO
	for c in 3:
		var raws: PackedFloat32Array = _straight[c][0]
		var lights: PackedFloat32Array = _straight[c][1]
		var i := 1
		while i < raws.size() - 1 and raw[c] > raws[i]:
			i += 1
		# Straight between neighbors, and on past the ends along the last stretch.
		out[c] = lights[i - 1] + (raw[c] - raws[i - 1]) * (lights[i] - lights[i - 1]) / maxf(raws[i] - raws[i - 1], 1e-9)
	return out


## A reading as light: straightened, and scaled by how bright the white
## around the disc came out against the first reading of its kind, so a
## screen that dims or brightens with what it shows reads as if it didn't.
func _light(data: Dictionary, corrected: bool) -> Vector3:
	var rgb: Array = data.rgb
	var middle := _straighten(Vector3(float(rgb[0]), float(rgb[1]), float(rgb[2])))
	var outer = data.get("outer")
	if not (outer is Array and outer.size() == 3):
		return middle
	var around := _sum(_straighten(Vector3(float(outer[0]), float(outer[1]), float(outer[2]))))
	if around <= 1e-6:
		return middle
	if not _around.has(corrected):
		_around[corrected] = around
	if not corrected:
		_arounds.append(around)
	return middle * (_around[corrected] / around)


func _warn(text: String) -> void:
	if not text in _warnings:
		_warnings.append(text)


static func _sum(v: Vector3) -> float:
	return v.x + v.y + v.z


## A ramp's light at code, black taken off: between its steps, eased along a
## 2.2 power as screens are, so the steps' spacing barely matters.
func _ramp(name: String, code: float) -> Vector3:
	var codes: Array = [0.0] + STEPS
	var black: Vector3 = _readings.black
	var i := 1
	while i < codes.size() - 1 and code > codes[i]:
		i += 1
	var low: Vector3 = Vector3.ZERO if i == 1 else _readings["%s/%s" % [name, codes[i - 1]]] - black
	var high: Vector3 = _readings["%s/%s" % [name, codes[i]]] - black
	var t := clampf((code - codes[i - 1]) / (codes[i] - codes[i - 1]), 0, 1)
	var out := Vector3.ZERO
	for c in 3:
		out[c] = pow(lerpf(pow(maxf(low[c], 0), 1 / 2.2), pow(maxf(high[c], 0), 1 / 2.2), t), 2.2)
	return out


## The curves, from the grays: for each level, the gray code that gives that
## share of white's light, then each channel's code nudged so the gray has
## white's own color, by how each channel's ramp changes the reading there.
## All in the camera's raw colors, which need no color matrix: a gray is
## right when the camera sees it as a dimmer copy of the white.
func _solve() -> void:
	var black: Vector3 = _readings.black
	var white: Vector3 = _readings.white - black
	var lights := PackedFloat32Array([0.0])
	var codes := PackedFloat32Array([0.0])
	var jumps := 0
	for code in STEPS:
		var light := _sum(_readings["gray/%s" % code] - black) / maxf(_sum(white), 1e-6)
		if light < lights[-1] - 0.01:
			jumps += 1
		lights.append(maxf(light, lights[-1] + 1e-5))
		codes.append(code)
	var curves := {"r": [], "g": [], "b": []}
	var names: Array = CHANNELS.keys()
	var largest := 0.0
	for level in DisplayCalibration.LEVELS:
		var base := DisplayCalibration.monotone(lights, codes, level)
		var low := maxf(base - NUDGE_STEP, 0.0)
		var high := minf(base + NUDGE_STEP, 1.0)
		var change := Basis((_ramp("r", high) - _ramp("r", low)) / (high - low),
				(_ramp("g", high) - _ramp("g", low)) / (high - low), (_ramp("b", high) - _ramp("b", low)) / (high - low))
		var nudge := Vector3.ZERO
		if absf(change.determinant()) > 1e-12:
			nudge = change.inverse() * (white * level - _ramp("gray", base))
		for c in 3:
			largest = maxf(largest, absf(nudge[c]))
			curves[names[c]].append(clampf(base + clampf(nudge[c], -MAX_NUDGE, MAX_NUDGE), 0.01, 0.99))
	var gammas := {}
	for channel in names:
		gammas[channel] = snappedf(log(0.5) / log(curves[channel][1]), 0.01)
	gammas["gray"] = snappedf(log(0.5) / log(DisplayCalibration.monotone(lights, codes, 0.5)), 0.01)
	var notes := {"gammas": gammas, "exposure_locked": true, "white_locked": true, "white_daylight": false, "raw": true,
			"gamut_used": false, "white_used": false, "checked": false, "source": notes_source, "trusted": true, "locks": locks,
			"straightened": not _straight.is_empty(), "raw_top_scale": snappedf(_straightened, 0.001), "largest_nudge": snappedf(largest, 0.001)}
	_result = {"method": "camera", "date": Time.get_datetime_string_from_system(), "curves": curves,
			"gamut": [[1, 0, 0], [0, 1, 0], [0, 0, 1]], "white_gain": [1, 1, 1], "tint": [0, 0], "notes": notes, "enabled": true}
	if not _arounds.is_empty():
		var mean := 0.0
		for a in _arounds:
			mean += a / _arounds.size()
		var drift: float = (_arounds.max() - _arounds.min()) / maxf(mean, 1e-6)
		notes.screen_drift = snappedf(drift, 0.001)
		if drift > SCREEN_DRIFT:
			_warn("This screen changes its brightness with what it shows (by %d%%), from a setting like dynamic contrast, eco mode or content adaptive brightness. The meter measured each color against the white around it to make up for it, but turning that setting off makes calibration more exact." % roundi(drift * 100))
	# For the notes: the screen's white as the camera's matrix reads it, and
	# how far red, green and blue fall from adding up to it (some screens,
	# OLED ones with a white subpixel, don't add up).
	var added := Vector3.ZERO
	for channel in names:
		added += _readings["%s/1.0" % channel] - black
	notes.additivity = snappedf(_sum(added) / maxf(_sum(white), 1e-6), 0.001)
	if _has_matrix:
		var xyz := _to_xyz * white
		notes.white_xy = [snappedf(xyz.x / _sum(xyz), 0.0001), snappedf(xyz.y / _sum(xyz), 0.0001)]
	var problems: Array[String] = []
	var lowest := minf(gammas.r, minf(gammas.g, gammas.b))
	var highest := maxf(gammas.r, maxf(gammas.g, gammas.b))
	if lowest < TRUSTED_GAMMAS.x or highest > TRUSTED_GAMMAS.y:
		problems.append("gammas from %.2f to %.2f, where screens come to about 1.8 to 2.6" % [lowest, highest])
	if jumps > 2:
		problems.append("readings that went down as the screen got brighter")
	if largest > MAX_NUDGE:
		problems.append("grays that would need a channel moved by %.2f, more than a screen's tint ever needs" % largest)
	if not problems.is_empty():
		notes.trusted = false
		notes.problem = "; ".join(problems)
		notes.causes = ["The readings jumped about, so the phone most likely moved, or light fell on the screen. Rest it on something steady, dim the room, and try again."] if jumps > 2 else []
		return
	notes.checked = not _check_colors.is_empty()


## Lab of a raw reading, against the white measured alongside it, as the eye
## takes a screen's white for white: so the camera's color matrix, made for
## daylight scenes rather than a screen's narrow colors, only has to be right
## about differences from white, not about the white itself.
func _lab(reading: Vector3, white: Vector3) -> Vector3:
	var black: Vector3 = _readings.black
	var xyz := _to_xyz * (reading - black)
	var reference := _to_xyz * (white - black)
	var f := Vector3.ZERO
	for i in 3:
		var scaled := xyz[i] / maxf(reference[i], 1e-6)
		f[i] = pow(scaled, 1.0 / 3.0) if scaled > 0.008856 else 7.787 * scaled + 16.0 / 116.0
	return Vector3(116.0 * f.y - 16.0, 500.0 * (f.x - f.y), 200.0 * (f.y - f.z))


## The game's colors compared, before and after: all of them, and the grays
## alone, which the camera judges best (they need its matrix only for small
## differences from white).
func _finish() -> void:
	_done = true
	_step = {}
	var notes: Dictionary = _result.get("notes", {})
	if notes.get("checked", false):
		for when in ["before", "after"]:
			notes[when] = _compare(when, func(name: String): return true)
			notes[when + "_grays"] = _compare(when, func(name: String): return name.begins_with("gray"))
	notes.warnings = _warnings
	_result.notes = notes
	progress = 1.0
	finished.emit(_result)


## ΔE00 of the check colors whose names pass keep, as measured when: {mean, max, worst}.
func _compare(when: String, keep: Callable) -> Dictionary:
	var white: Vector3 = _readings["%s/white" % when]
	var total := 0.0
	var worst := 0.0
	var worst_name := ""
	var count := 0
	for check in _check_colors:
		if check.name == "white" or not keep.call(check.name):
			continue
		var wanted: Color = (check.color as Color).srgb_to_linear()
		var delta := DisplayCalibration.delta_e(DisplayCalibration.lab(Vector3(wanted.r, wanted.g, wanted.b)),
				_lab(_readings["%s/%s" % [when, check.name]], white))
		total += delta
		count += 1
		if delta > worst:
			worst = delta
			worst_name = check.name
	return {"mean": snappedf(total / maxi(count, 1), 0.01), "max": snappedf(worst, 0.01), "worst": worst_name}
