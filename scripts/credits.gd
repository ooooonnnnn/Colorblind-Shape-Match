extends Label
## The "made by" line, in bold, tilted and slowly pulsing. Holding it fills the
## letters with yellow from left to right while it trembles, and once full a
## chat bubble pops up with the credits, our faces swishing in beside them with
## a message bling; tapping anywhere closes the bubble again.

const HOLD_SECONDS := 0.8
const CREDITS := "Game designer: Talor porat\nLead dev: Omri Tafla"
const TAIL := Vector2(22, 18)  # the bubble's tail: width at its base, and length
const FILL := Color("ffd166")
const EMBOLDEN := 0.5  # extra stroke weight on the theme font; much more and big letters get cut at their edges
const THICKEN := 3  # px of outline in the text's own color, for the rest of the bold look
const SHAKE := 3.0  # px, the largest tremble, reached as the bar fills
const FACES := preload("res://art_faces.png")
const FACES_SIZE := Vector2(150, 130)
const BLING := preload("res://sounds/bling.wav")
const SWISH_FROM := Vector2(-260, 70)  # px from the faces' resting spot where the swish starts
const TILT := -4.0  # degrees
const PULSE := 1.06  # scale at the top of the slow pulse
const PULSE_SECONDS := 1.2  # to swell, and again to shrink back
const INSET := 8.0  # px before the text, so the bold first letter isn't cut at the edge

var _holding := false
var _held := 0.0
var _bubble := PanelContainer.new()
var _clip := Control.new()  # shows the filled letters up to how full it is
var _filled := Label.new()  # the same text in the fill color, laid exactly over this one
var _fill := 0.0:  # 0..1, how far the letters have filled
	set(v):
		_fill = v
		_clip.size = Vector2(INSET + _text_width() * v, size.y)
var _rest := Vector2.ZERO  # where the line sits when it is not trembling
var _drain: Tween
var _faces := TextureRect.new()
var _bling := AudioStreamPlayer.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bold := FontVariation.new()
	bold.base_font = get_theme_font("font")
	bold.variation_embolden = EMBOLDEN
	add_theme_font_override("font", bold)
	add_theme_color_override("font_outline_color", get_theme_color("font_color"))
	add_theme_constant_override("outline_size", THICKEN)
	_filled.text = text
	_filled.vertical_alignment = vertical_alignment
	var inset := StyleBoxEmpty.new()
	inset.content_margin_left = INSET
	add_theme_stylebox_override("normal", inset)
	_filled.add_theme_stylebox_override("normal", inset)
	_filled.add_theme_font_override("font", bold)
	_filled.add_theme_font_size_override("font_size", get_theme_font_size("font_size"))
	_filled.add_theme_color_override("font_color", FILL)
	_filled.add_theme_color_override("font_outline_color", Icons.INK)
	_filled.add_theme_constant_override("outline_size", 6)
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_filled)
	add_child(_clip)
	resized.connect(func():
		_filled.size = size
		_fill = _fill
		pivot_offset = size / 2
	)
	pivot_offset = size / 2
	rotation_degrees = TILT
	var pulse := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(self, "scale", Vector2.ONE * PULSE, PULSE_SECONDS)
	pulse.tween_property(self, "scale", Vector2.ONE, PULSE_SECONDS)
	_filled.size = size
	_fill = 0.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_border_width_all(3)
	style.border_color = Icons.INK
	style.set_corner_radius_all(18)
	style.set_content_margin_all(16)
	_bubble.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_bubble.add_child(row)
	# The faces sit in a fixed spot that the swish moves them into, so the
	# bubble's layout never changes while they fly.
	var spot := Control.new()
	spot.custom_minimum_size = FACES_SIZE
	row.add_child(spot)
	_faces.texture = FACES
	_faces.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_faces.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_faces.size = FACES_SIZE
	_faces.pivot_offset = FACES_SIZE / 2
	spot.add_child(_faces)
	var lines := Label.new()
	lines.text = CREDITS
	lines.add_theme_font_size_override("font_size", 22)
	lines.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lines)
	_bling.stream = BLING
	add_child(_bling)
	_bubble.draw.connect(_draw_tail)
	_bubble.z_index = 10
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.hide()
	# Beside this line rather than on it, so the bubble neither tilts nor pulses.
	get_parent().add_child.call_deferred(_bubble)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not _bubble.visible:
			_holding = true
			_held = 0.0
			_rest = position
			if _drain:
				_drain.kill()
		elif not event.pressed and _holding:
			_let_go()


func _input(event: InputEvent) -> void:
	if _bubble.visible and event is InputEventMouseButton and event.pressed:
		_bubble.hide()
		_holding = false  # so this press does not reopen it
		_fill = 0.0


func _process(delta: float) -> void:
	if not _holding or _bubble.visible:
		return
	_held += delta
	_fill = minf(_held / HOLD_SECONDS, 1.0)
	position = _rest + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * SHAKE * _fill
	if _held >= HOLD_SECONDS:
		_holding = false
		position = _rest
		_pop_bubble()


## How wide the bold text is, so the fill ends on the last letter.
func _text_width() -> float:
	return get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size")).x


## Released early: stop trembling and let the fill drain away.
func _let_go() -> void:
	_holding = false
	position = _rest
	_drain = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_drain.tween_property(self, "_fill", 0.0, 0.25)


## Springs the bubble in above this line, its tail pointing down at it.
func _pop_bubble() -> void:
	_bubble.reset_size()
	_bubble.position = position + Vector2(0, -_bubble.size.y - TAIL.y - 4)
	_bubble.pivot_offset = Vector2(TAIL.x * 2, _bubble.size.y)  # grow out of the tail
	_bubble.scale = Vector2.ZERO
	_bubble.show()
	_fill = 0.0
	var t := _bubble.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for s in [Vector2(1.12, 0.9), Vector2(0.96, 1.05), Vector2.ONE]:
		t.tween_property(_bubble, "scale", s, 0.09)
	_bling.pitch_scale = randf_range(0.92, 1.08)  # never quite the same twice
	_bling.play()
	_swish_faces()


## The faces fly in from the left along a curve, spinning upright and growing,
## and overshoot a little before settling, like a message arriving.
func _swish_faces() -> void:
	_faces.position = SWISH_FROM
	_faces.rotation = -0.7
	_faces.scale = Vector2.ONE * 0.4
	_faces.modulate.a = 0.0
	var t := _faces.create_tween().set_parallel()
	# Sideways and up at different paces, which bends the path into a curve.
	t.tween_property(_faces, "position:x", 0.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_faces, "position:y", 0.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_faces, "rotation", 0.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_faces, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_faces, "modulate:a", 1.0, 0.15)


func _draw_tail() -> void:
	var base_y := _bubble.size.y - 3  # tucked under the border so the two join
	var left := TAIL.x * 1.2
	var tail := PackedVector2Array([Vector2(left, base_y), Vector2(left + TAIL.x, base_y), Vector2(left, base_y + TAIL.y)])
	_bubble.draw_colored_polygon(tail, Color.WHITE)
	_bubble.draw_polyline(PackedVector2Array([tail[1], tail[2], tail[0]]), Icons.INK, 3.0, true)
