extends Label
## The "made by" line. Holding it fills a bar behind it while it trembles,
## and a full bar pops up a chat bubble with the credits; tapping anywhere
## closes the bubble again.

const HOLD_SECONDS := 0.8
const CREDITS := "Game designer: Talor porat\nLead dev: Omri"
const TAIL := Vector2(22, 18)  # the bubble's tail: width at its base, and length
const BAR := Color("ffd166")
const SHAKE := 3.0  # px, the largest tremble, reached as the bar fills

var _holding := false
var _held := 0.0
var _bubble := PanelContainer.new()
var _bar := Control.new()  # drawn behind the text
var _fill := 0.0:  # 0..1, how full the bar is
	set(v):
		_fill = v
		_bar.queue_redraw()
var _rest := Vector2.ZERO  # where the line sits when it is not trembling
var _drain: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.show_behind_parent = true
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_border_width_all(3)
	style.border_color = Icons.INK
	style.set_corner_radius_all(18)
	style.set_content_margin_all(16)
	_bubble.add_theme_stylebox_override("panel", style)
	var text := Label.new()
	text.text = CREDITS
	text.add_theme_font_size_override("font_size", 22)
	_bubble.add_child(text)
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


## Released early: stop trembling and let the bar drain away.
func _let_go() -> void:
	_holding = false
	position = _rest
	_drain = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_drain.tween_property(self, "_fill", 0.0, 0.25)


## A pale track the size of the line, filling with yellow from the left.
func _draw_bar() -> void:
	if _fill <= 0.0:
		return
	var track := Rect2(-10, -4, size.x + 20, size.y + 8)
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(int(track.size.y / 2))
	box.bg_color = Color(1, 1, 1, 0.6)
	_bar.draw_style_box(box, track)
	box.bg_color = BAR
	_bar.draw_style_box(box, Rect2(track.position, Vector2(maxf(track.size.y, track.size.x * _fill), track.size.y)))


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
