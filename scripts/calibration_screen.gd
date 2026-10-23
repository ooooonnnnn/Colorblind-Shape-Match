class_name CalibrationScreen
extends CanvasLayer
## The full-screen steps of a screen calibration, opened from the Calibration
## tab: by eye, or with a phone camera (see DisplayCalibration for what is
## measured and CameraCalibration for how the camera does it).
##
## By eye, every step is a choice to tap, as anyone can say which of a few
## squares looks plainest; no sliders, no squinting. First brightness: gray
## squares at different gammas sit in a field of rows of white and black,
## which give exactly half of white's light, and the square hardest to see
## matches it. The rows are drawn in the screen's own pixels, one pixel each.
## Then gray balance at 50%, 75% and 25% light: nine grays, each tinted a
## little differently, and the plainest shows how the channels must be
## balanced there. Each round narrows around the last pick. Last, the game's
## own colors, before and after.
##
## While it is open, color blind mode is off and the screen is measured as it
## is, uncorrected, except where a step shows the correction. Closing puts
## things back; finished carries the new calibration, which the tab keeps
## until Save, or {} when stopped.

signal finished(result: Dictionary)

const ColorGroups := preload("res://scripts/color_groups.gd")
const LAYER := 120  # above the pop-ups (110), below ColorVision and DisplayCalibration (128)
const THEME := preload("res://ui_theme.tres")
const PATTERN := preload("res://shaders/calibration_pattern.gdshader")
const PAPER := Color("fffaf0")
const GO := Color("7bd88f")
const STOP := Color("ffb4a2")
const AIM_GRAY := Color(0.5, 0.5, 0.5)  # what the screen shows while the phone is pointed at it
const GAMMA_STEPS := [0.25, 0.12, 0.06]  # gamma between neighboring squares, in each round of the brightness step
const TINT_STEPS := [0.12, 0.06, 0.03]  # share a tint moves a channel's code by, in each round of a gray step
const NEUTRAL_ORDER := [1, 2, 0]  # LEVELS indices: middle gray first, then light, then dark
const CHANNEL_NAMES := {"r": "Red", "g": "Green", "b": "Blue"}
const CHANNEL_COLORS := {"r": Color.RED, "g": Color.GREEN, "b": Color.BLUE}
## [picture, caption] for each thing to set up first (see CalibrationArt).
const BEFORE_YOU_START := [
	["night_light", "Night light, eye comfort, True Tone and Night Shift off"],
	["color_mode", "Screen color mode: Natural, Standard or sRGB"],
	["brightness", "Auto-brightness off, at the brightness you play at"],
	["warm_up", "Screen on a few minutes first, seen straight on"],
	["glare", "No lamp or window shining on the screen"],
]
## [picture, caption] for each step of getting the phone measuring.
const PHONE_STEPS := [
	["scan", "1. Scan the code with the phone's camera"],
	["warning", "2. It warns: tap Advanced, then Proceed"],
	["allow", "3. Allow the camera"],
	["hold", "4. Hold it close to this screen, still"],
]
const DISC_CM := 3.0  # across, the solid circle in the middle of a split patch, to start with
const DISC_RANGE := Vector2(0.03, 0.3)  # smallest and largest radius of the circle, as shares of the screen's shorter side
const AIM_EDGE := Vector2(0.38, 0.55)  # where the phone should see the circle's edge (see phone.html), past which it is resized
const LOG_PATH := "user://calibration_log.json"  # the last camera run's readings
const LOG_DIR := "user://calibration_logs"  # every camera run's readings, by time
const PLACE_PATH := "user://calibration.cfg"  # where the circle was last put

var _root := Control.new()
var _patch := ColorRect.new()  # the calibration patch the camera measures
var _disc := _Disc.new()  # the solid middle of a split patch
var _phone_info := {}  # what the phone said it can do, see phone.html
var _page: Control  # the step's own contents
var _method := ""
var _previous := {}  # DisplayCalibration.state() before opening, put back when stopped
var _vision := ""  # ColorVision.mode before opening
var _gamma := 2.2  # by eye: the brightness picked
var _gains: Array[Vector3] = [Vector3.ONE, Vector3.ONE, Vector3.ONE]  # by eye: each channel's code factor at each of LEVELS
var _picking := false  # a tapped square is popping, so a second tap waits
var _link: CalibrationLink
var _camera  # the run: CameraCalibration with the web page, RawCalibration with the Meter app
var _phone_note: Label
var _progress_note: Label
var _ended := false


## Opens the steps for method ("eye" or "camera") over parent's scene.
static func open(parent: Node, how: String) -> CalibrationScreen:
	var screen := CalibrationScreen.new()
	screen._method = how
	parent.add_child(screen)
	return screen


func _ready() -> void:
	layer = LAYER
	_root.theme = THEME
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(black)
	_patch.material = _pattern_material(AIM_GRAY, 1, 1)
	_patch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_patch.visible = false
	_root.add_child(_patch)
	_disc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc.radius = _disc_radius()
	var place := ConfigFile.new()
	if place.load(PLACE_PATH) == OK:
		_disc.at = place.get_value("calibration", "circle", _disc.at)
		var short := minf(_root.get_viewport_rect().size.x, _root.get_viewport_rect().size.y)
		_disc.radius = clampf(place.get_value("calibration", "radius_share", _disc.radius / short), DISC_RANGE.x, DISC_RANGE.y) * short
	_disc.visible = false
	_root.add_child(_disc)
	_previous = DisplayCalibration.state()
	_vision = ColorVision.mode
	ColorVision.mode = ColorVision.NONE
	_show_intro()


func _exit_tree() -> void:
	if _camera:
		_camera.stop()
	DisplayCalibration.bypass = false


## Closes, keeping result (a calibration) or, with {}, putting the old one back.
func _end(result: Dictionary) -> void:
	if _ended:
		return
	_ended = true
	if _link:
		_link.stop()
	DisplayCalibration.bypass = false
	DisplayCalibration.set_state(result if not result.is_empty() else _previous)
	ColorVision.mode = _vision
	finished.emit(result)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_end({})


# ---------- Building blocks ----------

static func _pattern_material(color: Color, period: int, on: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PATTERN
	_set_pattern(material, color, period, on)
	return material


static func _set_pattern(material: ShaderMaterial, color: Color, period: int, on: int) -> void:
	material.set_shader_parameter("lit", color)
	material.set_shader_parameter("period", period)
	material.set_shader_parameter("on_rows", on)


## Swaps in a new page for the step.
func _new_page(page: Control) -> void:
	if is_instance_valid(_page):
		_page.queue_free()
	_page = page
	_root.add_child(page)


## A paper card in the middle of the screen, with a title, and its body to fill.
func _card_page(title: String) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_corner_radius_all(26)
	style.set_border_width_all(3)
	style.border_color = Icons.INK
	style.set_content_margin_all(28)
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size.x = minf(_root.get_viewport_rect().size.x - 48, 900)
	center.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	card.add_child(body)
	var heading := Label.new()
	heading.text = title
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", 32)
	body.add_child(heading)
	_new_page(center)
	return body


func _text(parent: Control, text: String, size := 21, color := Icons.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _buttons(parent: Control, choices: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 14)
	for choice in choices:  # [text, callable, color]
		var b := Button.new()
		b.text = choice[0]
		b.custom_minimum_size = Vector2(58 if choice[0] == "?" else 150, 58)
		b.add_theme_font_size_override("font_size", 22)
		if choice.size() > 2:
			PopupCard.tint(b, choice[2])
		b.pressed.connect(choice[1])
		row.add_child(b)
	parent.add_child(row)
	return row


func _checklist(parent: Control) -> void:
	parent.add_child(CalibrationArt.tiles(BEFORE_YOU_START, Vector2(150, 105), 16))


## A strip along the bottom of a full-screen step: what to do, and buttons.
func _bottom_bar(page: Control, text: String, choices: Array, picture: Control = null) -> void:
	var bar := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PAPER, 0.94)
	style.set_corner_radius_all(20)
	style.set_content_margin_all(16)
	bar.add_theme_stylebox_override("panel", style)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 16
	bar.offset_right = -16
	bar.offset_bottom = -16
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	bar.add_child(row)
	if picture:
		row.add_child(picture)
	var label := _text(row, text, 20)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 200
	var buttons := _buttons(row, choices)
	buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	page.add_child(bar)


func _full_page() -> Control:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_new_page(page)
	return page


# ---------- Both ----------

func _show_intro() -> void:
	DisplayCalibration.bypass = true
	_patch.visible = false
	var body := _card_page("Calibrate by eye" if _method == "eye" else "Calibrate with a phone camera")
	if _method == "eye":
		_text(body, "About two minutes, just tapping: pick the square that's hardest to see, then the grayest grays.")
		body.add_child(CalibrationArt.tiles([["hardest", "Tap the square that's hardest to see"], ["neutral", "Tap the grayest gray"]], Vector2(200, 140)))
	else:
		_text(body, "About three minutes. Another phone measures this screen with its camera, from a web page: nothing to install.")
		body.add_child(CalibrationArt.tiles([["same_wifi", "Both on the same Wi-Fi"]], Vector2(150, 105), 16))
	_text(body, "First, set the screen up", 24)
	_checklist(body)
	_buttons(body, [["Cancel", _end.bind({}), STOP], ["Start", _show_brightness.bind(0) if _method == "eye" else _show_connect, GO]])


# ---------- By eye ----------

## Brightness: gray squares in a field of gray stripes, one per gamma; the
## one hardest to see gives the stripes' light, which is half of white's.
func _show_brightness(pass_index: int) -> void:
	DisplayCalibration.bypass = true
	var step: float = GAMMA_STEPS[pass_index]
	var gammas: Array[float] = []
	for i in range(-2, 3):
		gammas.append(clampf(_gamma + i * step, 1.4, 3.4))
	gammas.shuffle()
	var page := _full_page()
	var field := ColorRect.new()
	field.material = _pattern_material(Color.WHITE, 2, 1)
	field.set_anchors_preset(Control.PRESET_FULL_RECT)
	field.offset_bottom = -170
	page.add_child(field)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 48)
	field.add_child(row)
	for g in gammas:
		var code := pow(0.5, 1.0 / g)
		row.add_child(_choice(Color(code, code, code), Vector2(150, 150), func():
			_gamma = g
			if pass_index + 1 < GAMMA_STEPS.size():
				_show_brightness(pass_index + 1)
			else:
				_show_neutral(0, 0)
		))
	_bottom_bar(page, "Step 1 of 4 (%d/%d). Tap the square that's hardest to see. If you can't choose, step back a little." % [pass_index + 1, GAMMA_STEPS.size()],
			[["Back", _show_intro if pass_index == 0 else _show_brightness.bind(pass_index - 1)]], CalibrationArt.new("hardest", Vector2(150, 105)))


## Grays: nine squares at one light level, each with a slightly different
## tint; the plainest gray tells how the screen's channels must be balanced
## there. Each pass_index tints them half as much around the last pick.
func _show_neutral(order: int, pass_index: int) -> void:
	DisplayCalibration.bypass = true
	var index: int = NEUTRAL_ORDER[order]
	var level: float = DisplayCalibration.LEVELS[index]
	var base := pow(level, 1.0 / _gamma)
	var step: float = TINT_STEPS[pass_index]
	var options: Array[Vector3] = []
	for warm in range(-1, 2):
		for green in range(-1, 2):
			options.append(_tinted(_gains[index], warm * step, green * step))
	options.shuffle()
	var page := _full_page()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 22)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -170
	center.add_child(grid)
	page.add_child(center)
	var view := _root.get_viewport_rect().size
	var side := clampf(minf((view.y - 260) / 3, (view.x - 80) / 3) - 22, 80, 220)
	for gains in options:
		var color := Color(clampf(base * gains.x, 0, 1), clampf(base * gains.y, 0, 1), clampf(base * gains.z, 0, 1))
		grid.add_child(_choice(color, Vector2(side, side), func():
			_gains[index] = gains
			if pass_index + 1 < TINT_STEPS.size():
				_show_neutral(order, pass_index + 1)
			elif order + 1 < NEUTRAL_ORDER.size():
				_show_neutral(order + 1, 0)
			else:
				_show_eye_done()
		))
	var back := _show_neutral.bind(order, pass_index - 1) if pass_index > 0 else (_show_neutral.bind(order - 1, TINT_STEPS.size() - 1) if order > 0 else _show_brightness.bind(GAMMA_STEPS.size() - 1))
	_bottom_bar(page, "Step %d of 4 (%d/%d). Tap the grayest square: the one with no color in it at all." % [order + 2, pass_index + 1, TINT_STEPS.size()],
			[["Back", back]], CalibrationArt.new("neutral", Vector2(150, 105)))


## gains moved warm (more red, less blue) and green (more green, less red
## and blue) by the given shares.
static func _tinted(gains: Vector3, warm: float, green: float) -> Vector3:
	return Vector3(gains.x * (1 + warm) * (1 - green / 2), gains.y * (1 + green), gains.z * (1 - warm) * (1 - green / 2))


## A square of color to tap: it pops, then on_pick runs.
func _choice(color: Color, side: Vector2, on_pick: Callable) -> Control:
	var square := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(12)  # no border: one would stand out in the stripes
	square.add_theme_stylebox_override("panel", style)
	square.custom_minimum_size = side
	square.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # square in a row, not stretched to it
	square.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	square.pivot_offset = side / 2
	square.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _picking:
			_picking = true
			var t := square.create_tween().set_trans(Tween.TRANS_BACK)
			t.tween_property(square, "scale", Vector2.ONE * 1.12, 0.1)
			t.tween_property(square, "scale", Vector2.ONE, 0.12)
			t.tween_callback(func():
				_picking = false
				on_pick.call())
	)
	return square


func _eye_result() -> Dictionary:
	var curves := {}
	var gammas := {}
	for c in 3:
		var codes := []
		for i in DisplayCalibration.LEVELS.size():
			codes.append(clampf(pow(DisplayCalibration.LEVELS[i], 1.0 / _gamma) * _gains[i][c], 0.01, 0.99))
		curves[DisplayCalibration.CHANNELS[c]] = codes
		gammas[DisplayCalibration.CHANNELS[c]] = snappedf(log(0.5) / log(codes[1]), 0.01)
	return {"enabled": true, "method": "eye", "date": Time.get_datetime_string_from_system(), "curves": curves,
			"gamut": [[1, 0, 0], [0, 1, 0], [0, 0, 1]], "white_gain": [1, 1, 1], "tint": [0, 0], "notes": {"gammas": gammas}}


## The result, with the game's own colors to flip between before and after.
func _show_eye_done() -> void:
	var result := _eye_result()
	_save_log("eye", {"time": Time.get_datetime_string_from_system(), "gamma": _gamma,
			"gains": _gains.map(func(g): return [g.x, g.y, g.z]), "result": result})
	DisplayCalibration.set_state(result)
	DisplayCalibration.bypass = false
	var body := _card_page("Done! See the difference")
	_text(body, "These are the game's own colors. Flip between before and after: after, they should look as they were made, like the home button pink, not orange.", 20)
	var swatches := HFlowContainer.new()
	swatches.add_theme_constant_override("h_separation", 8)
	swatches.add_theme_constant_override("v_separation", 8)
	for color in _sample_colors():
		var swatch := Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(10)
		swatch.add_theme_stylebox_override("panel", style)
		swatch.custom_minimum_size = Vector2(64, 64)
		swatches.add_child(swatch)
	body.add_child(swatches)
	var after := ToySwitch.new("After calibrating", true)
	after.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	after.toggled.connect(func(on): DisplayCalibration.bypass = not on)
	body.add_child(after)
	var g: Dictionary = result.notes.gammas
	_text(body, "Gamma: red %.2f, green %.2f, blue %.2f (standard is about 2.2). Save the settings to keep it." % [g.r, g.g, g.b], 17, Color(Icons.INK, 0.8))
	_buttons(body, [["Discard", _end.bind({}), STOP], ["Again", _restart_eye], ["Use it", _end.bind(result), GO]])


func _restart_eye() -> void:
	_gamma = 2.2
	_gains = [Vector3.ONE, Vector3.ONE, Vector3.ONE]
	_show_brightness(0)


## The menu's and the color groups' colors, for comparing.
func _sample_colors() -> Array[Color]:
	var colors: Array[Color] = [Color("ffb4a2"), Color("ffd166"), Color("7bd88f"), Color("bfe5ff"), Color(0.5, 0.5, 0.5)]
	for group in ColorGroups.active(ColorGroups.load_settings()):
		colors.append(group.background)
		for c in group.colors:
			colors.append(c)
	return colors


# ---------- With a phone camera ----------

func _show_connect() -> void:
	DisplayCalibration.bypass = true
	var body := _card_page("Scan this with the phone")
	var waiting := _text(body, "Getting ready…")
	_buttons(body, [["Cancel", _end.bind({}), STOP]])
	if not _link:
		_link = CalibrationLink.new()
		add_child(_link)
		var error := await _link.start()
		if not is_instance_valid(waiting):
			return
		if error != OK:
			waiting.text = "Couldn't start the connection for the phone (%s)." % error_string(error)
			return
	if not is_instance_valid(waiting):
		return
	var addresses := CalibrationLink.local_addresses()
	if addresses.is_empty():
		waiting.text = "This device isn't on a network. Connect it to Wi-Fi, the same one as the phone, and try again."
		return
	waiting.queue_free()
	_link.handler = _on_reading
	_link.phone_seen.connect(_on_phone_seen)
	_link.aimed.connect(_on_aimed)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var qr := QrCode.new()
	qr.custom_minimum_size = Vector2(300, 300)
	qr.text = _link.url(addresses[0])
	row.add_child(qr)
	var notes := VBoxContainer.new()
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notes.add_theme_constant_override("separation", 10)
	row.add_child(notes)
	body.add_child(row)
	body.move_child(row, 1)
	notes.add_child(CalibrationArt.tiles(PHONE_STEPS, Vector2(150, 105), 16))
	_text(notes, "No camera app? Type this into the phone's browser: " + _link.url(addresses[0]), 16, Color("1f5fa8"))
	if addresses.size() > 1:
		_text(notes, "If that doesn't open, try %s in its place." % ", ".join(addresses.slice(1)), 16, Color(Icons.INK, 0.8))
	_text(notes, "The warning is because this device made its own certificate for the page; it's safe here.", 15, Color(Icons.INK, 0.7))
	_phone_note = _text(body, "Waiting for the phone…", 22)
	body.move_child(_phone_note, 2)


func _check_colors() -> Array[Dictionary]:
	var colors: Array[Dictionary] = []
	for v in [0.3, 0.5, 0.75, 0.9]:
		colors.append({"name": "gray %d%%" % roundi(v * 100), "color": Color(v, v, v)})
	for channel in CHANNEL_COLORS:
		var c: Color = CHANNEL_COLORS[channel] * 0.8
		colors.append({"name": "%s 80%%" % CHANNEL_NAMES[channel].to_lower(), "color": Color(c.r, c.g, c.b)})
	for group in ColorGroups.active(ColorGroups.load_settings()):
		colors.append({"name": "%s background" % group.name, "color": group.background})
		var palette: Array = group.colors
		for i in ([0, palette.size() - 1] if palette.size() > 1 else [0]):
			colors.append({"name": "%s color %d" % [group.name, i + 1], "color": palette[i]})
	return colors


func _on_phone_seen(info: Dictionary) -> void:
	_phone_info = info
	if not is_instance_valid(_phone_note):
		return
	_show_aim()


## A fresh run, and the circle for the phone to line up with while it waits.
func _show_aim() -> void:
	if _phone_info.get("raw", false):
		_show_meter_aim()
		return
	_camera = CameraCalibration.new(_check_colors())
	_camera.patch_changed.connect(_show_patch)
	_camera.finished.connect(_on_camera_finished)
	_camera.can_lock = _phone_info.get("manual", false) and _phone_info.get("white", false)
	_camera.notes_source = "the camera's own frames" if _phone_info.get("direct", false) else "the browser's video"
	_camera.start()
	# A bright circle in stripes, so the phone can find its edge and see
	# whether the stripes are blurred.
	_show_patch(CameraCalibration.split(Color(0.9, 0.9, 0.9), Color.WHITE, 0.5))
	var page := _full_page()
	# Dragging anywhere moves the circle, to where the phone can rest in front of it.
	var drag := Control.new()
	drag.set_anchors_preset(Control.PRESET_FULL_RECT)
	drag.mouse_default_cursor_shape = Control.CURSOR_MOVE
	drag.gui_input.connect(func(event):
		var pressed: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		var dragged: bool = event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT
		if (pressed or dragged) and _camera.progress == 0:
			_place_disc(event.position / drag.size)
	)
	page.add_child(drag)
	var words := _text(page, "Phone connected. Drag the circle here to where the phone can rest still in front of it. Then, on the phone, fit the circle between the two dashed rings and tap Start.", 22, Color.WHITE)
	words.offset_left = 24
	words.offset_right = -24
	words.add_theme_constant_override("outline_size", 8)
	words.add_theme_color_override("font_outline_color", Color.BLACK)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var backing := StyleBoxFlat.new()  # readable over the stripes
	backing.bg_color = Color(0, 0, 0, 0.75)
	backing.set_corner_radius_all(14)
	backing.set_content_margin_all(12)
	words.add_theme_stylebox_override("normal", backing)
	if not _camera.can_lock:
		words.text += "\nThis phone's browser can't fix its camera's exposure and white balance, so only the brightness curves can be measured. Chrome on Android usually can."
	_progress_note = words
	_corner_stop(page)
	_place_disc(_disc.at)


## With the Meter app: each color is a disc on a white screen (see
## RawCalibration), so a dark disc is shown to line up with: dragged under the
## phone's camera, and sized by the app to what it sees.
func _show_meter_aim() -> void:
	_camera = RawCalibration.new(_check_colors(), _phone_info)
	_camera.patch_changed.connect(_show_patch)
	_camera.finished.connect(_on_camera_finished)
	_camera.start()
	_show_patch(RawCalibration.AIM_PATCH)
	var page := _full_page()
	var drag := Control.new()
	drag.set_anchors_preset(Control.PRESET_FULL_RECT)
	drag.mouse_default_cursor_shape = Control.CURSOR_MOVE
	drag.gui_input.connect(func(event):
		var pressed: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		var dragged: bool = event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT
		if (pressed or dragged) and _camera.progress == 0:
			_place_disc(event.position / drag.size)
	)
	page.add_child(drag)
	var text := "Meter app connected (%s). Rest the phone with its camera facing this screen, a few centimeters away, then drag the dark circle under the camera until the app says it's lined up, and tap Start in the app." % _phone_info.get("model", "phone")
	if int(_phone_info.get("version", 0)) < CalibrationLink.METER_VERSION:
		text = "The Meter app on the phone is out of date. In the app, tap Update the meter (or Download it again on the page), install it, then open it again from the page."
	var words := _text(page, text, 21, Color.WHITE)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backing := StyleBoxFlat.new()
	backing.bg_color = Color(0, 0, 0, 0.75)
	backing.set_corner_radius_all(14)
	backing.set_content_margin_all(12)
	words.add_theme_stylebox_override("normal", backing)
	_progress_note = words
	_corner_stop(page)
	_place_disc(_disc.at)


## A small Stop in the corner, away from the middle the phone measures.
func _corner_stop(page: Control) -> void:
	var stop := Button.new()
	stop.name = "Stop"
	stop.text = "Stop"
	stop.add_theme_font_size_override("font_size", 20)
	PopupCard.tint(stop, STOP)
	stop.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stop.offset_left = 16
	stop.offset_bottom = -16
	stop.offset_top = -70
	stop.offset_right = 130
	stop.pressed.connect(_end.bind({}))
	page.add_child(stop)


func _on_reading(data: Dictionary) -> Dictionary:
	if not _camera:
		return {"done": true, "text": "Not ready yet: scan the code again."}
	var reply: Dictionary = _camera.on_reading(data)
	if is_instance_valid(_progress_note) and not reply.get("done", false):
		_progress_note.text = "Measuring: %d%%. Keep the phone still." % roundi(_camera.progress * 100)
	return reply


## Shows a patch: one color over the whole screen, (split) a solid circle in
## the middle of rows of a color and black, or (disc) a circle of a color on
## a plain background.
func _show_patch(patch: Dictionary) -> void:
	_patch.visible = true
	DisplayCalibration.bypass = not patch.corrected
	if patch.get("disc", false):
		_set_pattern(_patch.material, patch.background, 1, 1)
		_disc.color = patch.color
		_disc.visible = true
		_disc.queue_redraw()
	elif patch.get("split", false):
		_set_pattern(_patch.material, patch.rows.color, patch.rows.period, patch.rows.on)
		_disc.color = patch.color
		_disc.visible = true
		_disc.queue_redraw()
	else:
		_set_pattern(_patch.material, patch.color, 1, 1)
		_disc.visible = false


## Moves the circle to at (a share of the screen each way), keeping it on the
## screen, and the words and Stop to the half away from it. Remembered for
## next time.
func _place_disc(at: Vector2) -> void:
	_disc.at = at.clamp(Vector2(0.12, 0.15), Vector2(0.88, 0.85))
	_disc.queue_redraw()
	var config := ConfigFile.new()
	config.load(PLACE_PATH)
	config.set_value("calibration", "circle", _disc.at)
	config.save(PLACE_PATH)
	if not is_instance_valid(_progress_note):
		return
	var low := _disc.at.y > 0.5
	_progress_note.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if low else Control.PRESET_BOTTOM_WIDE)
	_progress_note.offset_left = 16
	_progress_note.offset_right = -146  # clear of Stop
	_progress_note.offset_top = 16 if low else -120
	_progress_note.offset_bottom = 120 if low else -16
	_progress_note.vertical_alignment = VERTICAL_ALIGNMENT_TOP if low else VERTICAL_ALIGNMENT_BOTTOM
	var stop: Control = _page.get_node_or_null("Stop")
	if stop:
		stop.set_anchors_preset(Control.PRESET_TOP_RIGHT if low else Control.PRESET_BOTTOM_RIGHT)
		stop.offset_left = -130
		stop.offset_right = -16
		stop.offset_top = 16.0 if low else -70.0
		stop.offset_bottom = stop.offset_top + 54
	_progress_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## DISC_CM across the screen itself, as far as it says how big its pixels
## are, but never tiny or nearly all of it.
func _disc_radius() -> float:
	var view := _root.get_viewport_rect().size
	var px_per_unit := _root.get_viewport().get_final_transform().get_scale().x
	var radius := DISC_CM / 2 / 2.54 * DisplayServer.screen_get_dpi() / maxf(px_per_unit, 0.01)
	return clampf(radius, minf(view.x, view.y) * DISC_RANGE.x, minf(view.x, view.y) * DISC_RANGE.y)


## While lining up, sizes the circle to the phone's distance: closer, so the
## stripes blur, makes it look bigger, so it shrinks to sit between the rings.
func _on_aimed(view: Dictionary) -> void:
	if not _camera or _camera.progress > 0 or view.get("edge") == null:
		return
	var edge := float(view.edge)
	if edge > AIM_EDGE.x and edge < AIM_EDGE.y:
		return
	var short := minf(_root.size.x, _root.size.y)
	_disc.radius = clampf(_disc.radius * clampf((AIM_EDGE.x + AIM_EDGE.y) / 2 / edge, 0.75, 1.33),
			short * DISC_RANGE.x, short * DISC_RANGE.y)
	_disc.queue_redraw()
	var config := ConfigFile.new()
	config.load(PLACE_PATH)
	config.set_value("calibration", "radius_share", _disc.radius / short)
	config.save(PLACE_PATH)


func _on_camera_finished(result: Dictionary) -> void:
	if result.is_empty() or _ended:
		return
	_write_log(result)
	_patch.visible = false
	_disc.visible = false
	var notes: Dictionary = result.notes
	var g: Dictionary = notes.gammas
	if not notes.get("trusted", true):
		# Not put to use: show the screen as it was.
		DisplayCalibration.set_state(_previous)
		DisplayCalibration.bypass = false
		var failed := _card_page("That measurement didn't work")
		_text(failed, "It came to %s, which no screen does, so it hasn't been used." % notes.get("problem", "readings that don't fit together"))
		var causes: Array = notes.get("causes", [])
		if causes.is_empty() and notes.get("raw", false):
			_text(failed, "Most often the phone moved or light fell on the screen. Rest the phone on something steady, dim the room, and try again.", 19, Color(Icons.INK, 0.8))
		elif causes.is_empty():
			_text(failed, "Most often the phone moved, light fell on the screen, or the camera saw the stripes sharply. Rest the phone on something, dim the room, and try again. Calibrating by eye works too.", 19, Color(Icons.INK, 0.8))
		else:
			_text(failed, "What went wrong:", 20)
			for cause in causes:
				_text(failed, "•  " + cause, 19, Color("c46a00"))
			_text(failed, "Calibrating by eye works too.", 18, Color(Icons.INK, 0.8))
		_text(failed, "Gamma measured: red %.2f, green %.2f, blue %.2f, gray %.2f." % [g.r, g.g, g.b, g.gray], 16, Color(Icons.INK, 0.6))
		_buttons(failed, [["Close", _end.bind({}), STOP], ["Use anyway", _end.bind(result)], ["Try again", _try_again, GO]])
		return
	DisplayCalibration.set_state(result)
	DisplayCalibration.bypass = false
	var body := _card_page("Measured with the camera")
	_text(body, "Gamma: red %.2f, green %.2f, blue %.2f, gray %.2f (standard is about 2.2)." % [g.r, g.g, g.b, g.gray])
	var parts: Array[String] = ["the brightness curves"]
	if notes.get("raw", false):
		parts.append("the gray balance (grays the same color as the screen's white)")
	if notes.get("gamut_used", false):
		parts.append("the color range")
	if notes.get("white_used", false):
		parts.append("the white point (to D65 daylight white)")
	_text(body, "Corrected: %s." % ", ".join(parts))
	if notes.get("source", ""):
		_text(body, "The phone measured %s." % notes.source, 18, Color(Icons.INK, 0.8))
	if notes.has("before_grays") and notes.has("after_grays"):
		var before: Dictionary = notes.before_grays
		var after: Dictionary = notes.after_grays
		var colors_before: Dictionary = notes.before
		var colors_after: Dictionary = notes.after
		_text(body, "Gray error (ΔE00, against the screen's own white), which the camera judges best:", 21)
		_text(body, "Before: average %.1f, worst %.1f (%s): %s." % [before.mean, before.max, before.worst, DisplayCalibration.tier(before.max)], 20)
		_text(body, "After: average %.1f, worst %.1f (%s): %s." % [after.mean, after.max, after.worst, DisplayCalibration.tier(after.max)], 20)
		_text(body, "All the game's colors: average %.1f before, %.1f after. A camera reads a screen's bright colors only roughly, so take these as estimates." % [colors_before.mean, colors_after.mean], 18, Color(Icons.INK, 0.8))
	elif notes.has("before") and notes.has("after"):
		var before: Dictionary = notes.before
		var after: Dictionary = notes.after
		_text(body, "Color error (ΔE00) over the game's colors and grays, as the camera saw them:", 21)
		_text(body, "Before: average %.1f, worst %.1f (%s): %s." % [before.mean, before.max, before.worst, DisplayCalibration.tier(before.max)], 20)
		_text(body, "After: average %.1f, worst %.1f (%s): %s." % [after.mean, after.max, after.worst, DisplayCalibration.tier(after.max)], 20)
		_text(body, "The aim for color vision tests is 2 or less. A phone camera's picture is processed, so take these as estimates.", 18, Color(Icons.INK, 0.8))
	for warning in notes.get("warnings", []):
		_text(body, "•  " + warning, 18, Color("c46a00"))
	_buttons(body, [["Discard", _end.bind({}), STOP], ["Try again", _try_again], ["Use it", _end.bind(result), GO]])


## Back to lining up, for another run; the phone has a button for it too.
func _try_again() -> void:
	DisplayCalibration.set_state(_previous)
	_show_aim()


## Every reading of the run, to look into a result that came out wrong.
func _write_log(result: Dictionary) -> void:
	_save_log("meter" if _phone_info.get("raw", false) else "web", {"time": Time.get_datetime_string_from_system(), "phone": _phone_info,
			"screen": {"dpi": DisplayServer.screen_get_dpi(), "size": DisplayServer.screen_get_size(), "disc_radius": _disc.radius, "disc_at": [_disc.at.x, _disc.at.y]},
			"result": result, "readings": _camera.history}, true)


## A run's log, kept by time and kind (a later run doesn't hide it), and for
## camera runs also as the last one.
func _save_log(kind: String, data: Dictionary, last := false) -> void:
	var text := JSON.stringify(data, "\t")
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var paths := ["%s/%s_%s.json" % [LOG_DIR, Time.get_datetime_string_from_system().replace(":", "-"), kind]]
	if last:
		paths.append(LOG_PATH)
	for path in paths:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(text)


## The solid circle of a split patch, in exactly its color.
class _Disc extends Control:
	var color := Color.WHITE
	var radius := 100.0
	var at := Vector2(0.5, 0.5)  # its middle, as a share of the screen each way

	func _draw() -> void:
		draw_circle(size * at, radius, color)
