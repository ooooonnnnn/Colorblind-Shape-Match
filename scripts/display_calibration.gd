extends CanvasLayer
## Screen color calibration: corrects this device's screen so the game's
## colors come out as the sRGB colors they were picked as, which a color vision
## test depends on (see "Color calibration using a phone camera.pdf"). Phones
## and tablets don't let an app change the screen's own color profile, so the
## correction is done in the engine: a 3D lookup table (LUT), packed into a 2D
## texture, that a shader runs every pixel through on the topmost layer.
##
## The correction has three parts, measured by eye or with a phone camera on
## the Calibration tab (see CalibrationScreen):
## - curves: per channel, the code that gives 25%, 50% and 75% of the
##   channel's full light, which sets the screen's gamma and gray balance;
## - gamut: a matrix from the wanted linear sRGB to what the screen must be
##   sent, which tames oversaturated wide-gamut screens and, measured with a
##   locked camera white balance, moves the white point to D65;
## - white_gain: a tint set by eye, scaling each channel's light.
##
## It belongs to this one screen, so it's kept in user:// on every platform,
## never in the project's own files like the other settings.

const PATH := "user://display_calibration.json"
const LUT_SIZE := 32  # nodes per side of the 3D LUT, packed as LUT_SIZE slices side by side
const LEVELS := [0.25, 0.5, 0.75]  # shares of a channel's full light that curves holds the codes for
const CHANNELS := ["r", "g", "b"]
const CURVE_SAMPLES := 1024  # steps each curve is sampled in, for baking the LUT

var enabled := true:  # whether a calibration, when there is one, is used
	set(v):
		enabled = v
		_apply()
var method := ""  # "" uncalibrated, "eye" or "camera"
var date := ""  # when it was measured, as Time.get_datetime_string_from_system
var curves := default_curves()  # {channel: [code at each of LEVELS]}
var gamut := Basis.IDENTITY  # wanted linear sRGB to linear drive, white kept at (1, 1, 1) or less
var white_gain := Vector3.ONE  # each channel's share of light, set by eye
var tint := Vector2.ZERO  # the eye's warm/cool and green/magenta sliders that made white_gain, -1 to 1
var notes := {}  # what the calibration found, for the Calibration tab: gammas, checks, warnings
## Shows the screen as it is, uncorrected, while it is being measured.
var bypass := false:
	set(v):
		bypass = v
		_apply()

var _screen := ColorRect.new()
var _lut := ImageTexture.new()


func _ready() -> void:
	layer = 128  # with ColorVision, the highest; added after it, so it draws last
	# A fresh copy of the screen, color blind mode included, for the shader.
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	_screen.material = ShaderMaterial.new()
	_screen.material.shader = preload("res://shaders/display_calibration.gdshader")
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_screen)
	load_settings()


func is_calibrated() -> bool:
	return method != ""


static func default_curves() -> Dictionary:
	var codes := []
	for level in LEVELS:
		codes.append(srgb_code(level))
	return {"r": codes.duplicate(), "g": codes.duplicate(), "b": codes.duplicate()}


## The sRGB code that standard sRGB gives level of full light at.
static func srgb_code(level: float) -> float:
	return Color(level, 0, 0).linear_to_srgb().r


## Reads the calibration; without the file the screen is left as it is.
func load_settings() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if not data is Dictionary:
		data = {}
	set_state(data)


func save_settings() -> Error:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(state(), "\t", false) + "\n")
	return OK


## Everything saved, as plain data.
func state() -> Dictionary:
	var rows := []
	for i in 3:
		var row: Vector3 = gamut.transposed()[i]
		rows.append([row.x, row.y, row.z])
	return {"enabled": enabled, "method": method, "date": date, "curves": curves.duplicate(true), "gamut": rows,
			"white_gain": [white_gain.x, white_gain.y, white_gain.z], "tint": [tint.x, tint.y], "notes": notes.duplicate(true)}


## Takes on a state() (or a fresh calibration's result, which has the same
## keys), checking each part, and rebuilds the LUT.
func set_state(data: Dictionary) -> void:
	method = str(data.get("method", ""))
	date = str(data.get("date", ""))
	curves = default_curves()
	var saved = data.get("curves", {})
	if saved is Dictionary:
		for channel in CHANNELS:
			var codes = saved.get(channel)
			if codes is Array and codes.size() == LEVELS.size():
				var fixed := []
				for i in LEVELS.size():
					fixed.append(clampf(float(codes[i]), 0.01, 0.99))
				fixed.sort()  # a curve must climb
				curves[channel] = fixed
	gamut = Basis.IDENTITY
	var rows = data.get("gamut")
	if rows is Array and rows.size() == 3:
		var vectors: Array[Vector3] = []
		for row in rows:
			if row is Array and row.size() == 3:
				vectors.append(Vector3(float(row[0]), float(row[1]), float(row[2])))
		if vectors.size() == 3:
			gamut = Basis(vectors[0], vectors[1], vectors[2]).transposed()  # written as rows
	var gain = data.get("white_gain", [1, 1, 1])
	white_gain = Vector3(float(gain[0]), float(gain[1]), float(gain[2])).clamp(Vector3.ZERO, Vector3.ONE) if gain is Array and gain.size() == 3 else Vector3.ONE
	var t = data.get("tint", [0, 0])
	tint = Vector2(float(t[0]), float(t[1])) if t is Array and t.size() == 2 else Vector2.ZERO
	notes = data.get("notes", {}) if data.get("notes") is Dictionary else {}
	enabled = bool(data.get("enabled", true))
	rebuild()


## Forgets the calibration, leaving the screen as it is.
func clear() -> void:
	set_state({})


## Bakes the LUT from curves, gamut and white_gain.
func rebuild() -> void:
	_lut = ImageTexture.create_from_image(bake_lut())
	_screen.material.set_shader_parameter("lut", _lut)
	_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	_screen.visible = enabled and is_calibrated() and not bypass


# ---------- The correction ----------

## What the screen must be sent so it shows the sRGB code color: its linear
## light through gamut and white_gain, then each channel through its curve.
func correct(color: Color) -> Color:
	var wanted := color.srgb_to_linear()
	var drive := (gamut * Vector3(wanted.r, wanted.g, wanted.b) * white_gain).clamp(Vector3.ZERO, Vector3.ONE)
	var code := Color(drive.x, drive.y, drive.z).linear_to_srgb()
	return Color(_curve(curves.r, code.r), _curve(curves.g, code.g), _curve(curves.b, code.b))


## The correction for every node of a LUT_SIZE³ cube, unwrapped into a
## (LUT_SIZE², LUT_SIZE) image: slice b side by side, red across each slice
## and green down it (as in the article, so it needs no 3D texture support).
func bake_lut() -> Image:
	# The curves, sampled finely once, rather than worked out at every node.
	var tables: Array[PackedFloat32Array] = []
	for channel in CHANNELS:
		var table := PackedFloat32Array()
		for i in CURVE_SAMPLES + 1:
			table.append(_curve(curves[channel], float(i) / CURVE_SAMPLES))
		tables.append(table)
	var n := LUT_SIZE
	var data := PackedByteArray()
	data.resize(n * n * n * 3)
	var top := float(n - 1)
	for g in n:
		for b in n:
			for r in n:
				var wanted := Color(r / top, g / top, b / top).srgb_to_linear()
				var drive := (gamut * Vector3(wanted.r, wanted.g, wanted.b) * white_gain).clamp(Vector3.ZERO, Vector3.ONE)
				var code := Color(drive.x, drive.y, drive.z).linear_to_srgb()
				var i := (g * n * n + b * n + r) * 3
				for c in 3:
					var at := clampf(code[c], 0, 1) * CURVE_SAMPLES
					var k := mini(int(at), CURVE_SAMPLES - 1)
					data[i + c] = roundi(clampf(lerpf(tables[c][k], tables[c][k + 1], at - k), 0, 1) * 255)
	return Image.create_from_data(n * n, n, false, Image.FORMAT_RGB8, data)


## A channel's curve: from the code standard sRGB would send to the code this
## screen needs for the same light, through (0, 0), the three LEVELS and
## (1, 1), smoothly and always climbing (a monotone cubic, Fritsch and Carlson,
## 1980). Uncalibrated codes give back the code they were given.
static func _curve(codes: Array, code: float) -> float:
	var xs := PackedFloat32Array([0.0])
	var ys := PackedFloat32Array([0.0])
	for i in LEVELS.size():
		xs.append(srgb_code(LEVELS[i]))
		ys.append(codes[i])
	xs.append(1.0)
	ys.append(1.0)
	return monotone(xs, ys, code)


## The monotone cubic through points (xs, ys) at x; xs must climb.
static func monotone(xs: PackedFloat32Array, ys: PackedFloat32Array, x: float) -> float:
	var n := xs.size()
	x = clampf(x, xs[0], xs[n - 1])
	var slopes := PackedFloat32Array()
	for i in n - 1:
		slopes.append((ys[i + 1] - ys[i]) / maxf(xs[i + 1] - xs[i], 1e-6))
	var tangents := PackedFloat32Array([slopes[0]])
	for i in range(1, n - 1):
		tangents.append((slopes[i - 1] + slopes[i]) / 2 if slopes[i - 1] * slopes[i] > 0 else 0.0)
	tangents.append(slopes[n - 2])
	for i in n - 1:
		if slopes[i] == 0:
			tangents[i] = 0
			tangents[i + 1] = 0
			continue
		var a := tangents[i] / slopes[i]
		var b := tangents[i + 1] / slopes[i]
		var s := a * a + b * b
		if s > 9:  # too steep a tangent would overshoot and turn back
			tangents[i] = 3 / sqrt(s) * a * slopes[i]
			tangents[i + 1] = 3 / sqrt(s) * b * slopes[i]
	var k := 0
	while k < n - 2 and x > xs[k + 1]:
		k += 1
	var h := xs[k + 1] - xs[k]
	var t := (x - xs[k]) / maxf(h, 1e-6)
	var t2 := t * t
	var t3 := t2 * t
	return (2 * t3 - 3 * t2 + 1) * ys[k] + (t3 - 2 * t2 + t) * h * tangents[k] \
			+ (-2 * t3 + 3 * t2) * ys[k + 1] + (t3 - t2) * h * tangents[k + 1]


## The gamma a channel's curve comes to: the power that gives 50% light at
## its 50% code.
func gamma(channel: String) -> float:
	return log(0.5) / log(float(curves[channel][LEVELS.find(0.5)]))


# ---------- Color differences ----------

## CIELAB of linear sRGB light, against a D65 white.
static func lab(linear: Vector3) -> Vector3:
	var xyz := Vector3(
			0.4124564 * linear.x + 0.3575761 * linear.y + 0.1804375 * linear.z,
			0.2126729 * linear.x + 0.7151522 * linear.y + 0.0721750 * linear.z,
			0.0193339 * linear.x + 0.1191920 * linear.y + 0.9503041 * linear.z) / Vector3(0.95047, 1.0, 1.08883)
	var f := Vector3.ZERO
	for i in 3:
		f[i] = pow(xyz[i], 1.0 / 3.0) if xyz[i] > 0.008856 else 7.787 * xyz[i] + 16.0 / 116.0
	return Vector3(116.0 * f.y - 16.0, 500.0 * (f.x - f.y), 200.0 * (f.y - f.z))


## CIEDE2000 (ΔE00), the color difference the article measures calibrations
## by: under 1 can't be seen, 1-2 only when looked for (the aim for vision
## tests), 2-3 fine for everyday use, over 3 plain to see. After Sharma, Wu
## and Dalal (2005).
static func delta_e(lab1: Vector3, lab2: Vector3) -> float:
	var c_mean := (Vector2(lab1.y, lab1.z).length() + Vector2(lab2.y, lab2.z).length()) / 2
	var c7 := pow(c_mean, 7)
	var g := 0.5 * (1 - sqrt(c7 / (c7 + pow(25.0, 7))))
	var a1 := lab1.y * (1 + g)
	var a2 := lab2.y * (1 + g)
	var c1 := Vector2(a1, lab1.z).length()
	var c2 := Vector2(a2, lab2.z).length()
	var h1 := fposmod(atan2(lab1.z, a1), TAU)
	var h2 := fposmod(atan2(lab2.z, a2), TAU)
	var dh := 0.0
	if c1 * c2 != 0:
		dh = h2 - h1
		if dh > PI:
			dh -= TAU
		elif dh < -PI:
			dh += TAU
	var big_dh := 2 * sqrt(c1 * c2) * sin(dh / 2)
	var l_mean := (lab1.x + lab2.x) / 2
	var cp_mean := (c1 + c2) / 2
	var h_mean := h1 + h2
	if c1 * c2 != 0:
		if absf(h1 - h2) <= PI:
			h_mean = (h1 + h2) / 2
		elif h1 + h2 < TAU:
			h_mean = (h1 + h2 + TAU) / 2
		else:
			h_mean = (h1 + h2 - TAU) / 2
	var t := 1 - 0.17 * cos(h_mean - deg_to_rad(30)) + 0.24 * cos(2 * h_mean) \
			+ 0.32 * cos(3 * h_mean + deg_to_rad(6)) - 0.20 * cos(4 * h_mean - deg_to_rad(63))
	var d_theta := deg_to_rad(30) * exp(-pow((rad_to_deg(h_mean) - 275) / 25, 2))
	var cp7 := pow(cp_mean, 7)
	var rc := 2 * sqrt(cp7 / (cp7 + pow(25.0, 7)))
	var l50 := pow(l_mean - 50, 2)
	var sl := 1 + 0.015 * l50 / sqrt(20 + l50)
	var sc := 1 + 0.045 * cp_mean
	var sh := 1 + 0.015 * cp_mean * t
	var rt := -sin(2 * d_theta) * rc
	var dl := (lab2.x - lab1.x) / sl
	var dc := (c2 - c1) / sc
	var dhh := big_dh / sh
	return sqrt(dl * dl + dc * dc + dhh * dhh + rt * dc * dhh)


## The article's tiers for a ΔE00.
static func tier(delta: float) -> String:
	if delta < 1:
		return "can't be seen"
	if delta <= 2:
		return "only seen when looked for: good for vision tests"
	if delta <= 3:
		return "fine for everyday use, but loose for vision tests"
	return "plain to see: too far off for vision tests"
