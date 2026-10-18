class_name ShapeView
extends Control
## A piece or a hole. Draws one polygon from a 100x100 box, positioned by its
## center in board-relative (0..1) coordinates so it follows board resizes.

const SIZE := 0.15  # width as a fraction of the board

const PIECE_FILL := Color("f1ede2")
const PIECE_EDGE := Color("8b8778")
const HOLE_FILL := Color("0e1118")
const HOLE_EDGE := Color("3b4254")
const ACCENT := Color.WHITE

var is_piece := false
var shape_name := ""

# Pieces only.
var target_hole: ShapeView
var home := Vector2.ZERO
var placed := false:
	set(v):
		placed = v
		queue_redraw()
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var dragging := false:
	set(v):
		dragging = v
		queue_redraw()

# Holes only.
var filled := false

var norm_pos := Vector2.ZERO:
	set(v):
		norm_pos = v
		_update_layout()
var visual_scale := 1.0:
	set(v):
		visual_scale = v
		queue_redraw()
var shake_offset := 0.0:
	set(v):
		shake_offset = v
		queue_redraw()
var tilt := 0.0:  # radians
	set(v):
		tilt = v
		queue_redraw()

var _points := PackedVector2Array()  # centered on (0, 0)
var _show_focus := false
var _move_tween: Tween
var _scale_tween: Tween
var _shake_tween: Tween
var _tilt_tween: Tween


func setup(shape: Dictionary, piece: bool) -> void:
	shape_name = shape.name
	is_piece = piece
	_points.clear()
	for v in shape.points:
		_points.append(v - Shapes.CENTER)
	set("accessibility_name", "%s %s" % [shape_name.replace("_", " "), "piece" if piece else "hole"])
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	z_index = 2 if piece else 0


func _ready() -> void:
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(queue_redraw)
	get_parent().resized.connect(_update_layout)
	_update_layout()


func _update_layout() -> void:
	var board := get_parent() as Control
	if board == null:
		return
	var side := board.size.x * SIZE
	size = Vector2(side, side)
	position = norm_pos * board.size - size / 2


func move_to(target: Vector2, animate := true) -> void:
	if _move_tween:
		_move_tween.kill()
	if not animate:
		norm_pos = target
		return
	_move_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "norm_pos", target, 0.25)


func scale_to(s: float) -> void:
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "visual_scale", s, 0.15)


func shake() -> void:
	if _shake_tween:
		_shake_tween.kill()
	_shake_tween = create_tween()
	for x in [-6.0, 6.0, -4.0, 4.0, 0.0]:
		_shake_tween.tween_property(self, "shake_offset", x, 0.07)


# Rock clockwise and counter-clockwise, like shaking a head "no".
func nod() -> void:
	if _tilt_tween:
		_tilt_tween.kill()
	_tilt_tween = create_tween().set_trans(Tween.TRANS_SINE)
	for deg in [16.0, -16.0, 10.0, -10.0, 0.0]:
		_tilt_tween.tween_property(self, "tilt", deg_to_rad(deg), 0.09)


# Swell briefly to point itself out.
func bulge() -> void:
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween().set_trans(Tween.TRANS_SINE)
	for i in 2:
		_scale_tween.tween_property(self, "visual_scale", 1.25, 0.14).set_ease(Tween.EASE_OUT)
		_scale_tween.tween_property(self, "visual_scale", 1.0, 0.18).set_ease(Tween.EASE_IN)


func _on_focus_entered() -> void:
	# Only show the focus ring for keyboard focus, like CSS :focus-visible.
	_show_focus = not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	queue_redraw()


func _draw() -> void:
	if _points.is_empty():
		return
	var k := size.x / 100.0
	draw_set_transform(size / 2 + Vector2(shake_offset, 0), tilt, Vector2.ONE * k * visual_scale)
	var outline := _points.duplicate()
	outline.append(_points[0])

	if dragging:
		var shadow := PackedVector2Array()
		for v in _points:
			shadow.append(v + Vector2(0, 6.0 / k))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	if selected:
		draw_polyline(outline, Color(ACCENT, 0.25), 12.0, true)
		draw_polyline(outline, Color(ACCENT, 0.6), 6.0, true)

	if is_piece:
		draw_colored_polygon(_points, PIECE_FILL)
		draw_polyline(outline, PIECE_FILL if placed else PIECE_EDGE, 2.0, true)
	else:
		draw_colored_polygon(_points, HOLE_FILL)
		draw_polyline(outline, HOLE_EDGE, 2.5, true)

	draw_set_transform(Vector2.ZERO)
	if has_focus() and _show_focus:
		var r := Rect2(Vector2.ZERO, size).grow(6)
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for i in 4:
			draw_dashed_line(corners[i], corners[(i + 1) % 4], ACCENT, 2.0, 4.0)
