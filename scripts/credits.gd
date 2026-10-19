extends Label
## The "made by" line, in bold. Holding it fills the letters with yellow from
## left to right while it trembles, and once full a chat bubble pops up with
## the credits; tapping anywhere closes the bubble again.

const HOLD_SECONDS := 0.8
const CREDITS := "Game designer: Talor porat\nLead dev: Omri"
const TAIL := Vector2(22, 18)  # the bubble's tail: width at its base, and length
const FILL := Color("ffd166")
const EMBOLDEN := 0.9  # extra stroke weight on the theme font
const SHAKE := 3.0  # px, the largest tremble, reached as the bar fills

var _holding := false
var _held := 0.0
var _bubble := PanelContainer.new()
var _clip := Control.new()  # shows the filled letters up to how full it is
var _filled := Label.new()  # the same text in the fill color, laid exactly over this one
var _fill := 0.0:  # 0..1, how far the letters have filled
	set(v):
		_fill = v
		_clip.size = Vector2(_text_width() * v, size.y)
var _rest := Vector2.ZERO  # where the line sits when it is not trembling
var _drain: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bold := FontVariation.new()
	bold.base_font = get_theme_font("font")
	bold.variation_embolden = EMBOLDEN
	add_theme_font_override("font", bold)
	_filled.text = text
	_filled.vertical_alignment = vertical_alignment
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
	)
	_filled.size = size
	_fill = 0.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_border_width_all(3)
	style.border_color = Icons.INK
	style.set_corner_radius_all(18)
	style.set_content_margin_all(16)
	_bubble.add_theme_stylebox_override("panel", style)
	var lines := Label.new()
	lines.text = CREDITS
	lines.add_theme_font_size_override("font_size", 22)
	_bubble.add_child(lines)
	_bubble.draw.connect(_draw_tail)
	_bubble.z_index = 10
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.hide()
	add_child(_bubble)


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
	_bubble.position = Vector2(0, -_bubble.size.y - TAIL.y - 4)
	_bubble.pivot_offset = Vector2(TAIL.x * 2, _bubble.size.y)  # grow out of the tail
	_bubble.scale = Vector2.ZERO
	_bubble.show()
	_fill = 0.0
	var t := _bubble.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for s in [Vector2(1.12, 0.9), Vector2(0.96, 1.05), Vector2.ONE]:
		t.tween_property(_bubble, "scale", s, 0.09)


func _draw_tail() -> void:
	var base_y := _bubble.size.y - 3  # tucked under the border so the two join
	var left := TAIL.x * 1.2
	var tail := PackedVector2Array([Vector2(left, base_y), Vector2(left + TAIL.x, base_y), Vector2(left, base_y + TAIL.y)])
	_bubble.draw_colored_polygon(tail, Color.WHITE)
	_bubble.draw_polyline(PackedVector2Array([tail[1], tail[2], tail[0]]), Icons.INK, 3.0, true)
