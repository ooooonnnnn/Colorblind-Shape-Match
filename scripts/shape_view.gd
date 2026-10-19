class_name ShapeView
extends Control
## A piece or a hole. Draws one polygon from a 100x100 box, positioned by its
## center in board-relative (0..1) coordinates so it follows board resizes.

const CONFIG_PATH := "res://shape_size.json"

const PIECE_FILL := Color("f1ede2")
const HOLE_FILL := Color("0e1118")
const ACCENT := Color.WHITE

static var side_fraction := 0.2  # width as a fraction of the board's shorter side
## Width of a piece's outline, as a percentage of its side. Pieces are drawn
## hollow so they are harder to spot in the dot filter; bolder is easier, and
## much thinner the line slips between dot centers, where the filter samples.
static var outline_percent := 26.0

var is_piece := false
var shape_name := ""
var radius := 0.0  # bounding circle around the center, as a fraction of the side

# Pieces only.
var target_hole: ShapeView
var fill := PIECE_FILL:
	set(v):
		fill = v
		queue_redraw()
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
var squash := 0.0:  # > 0 is wide and flat, < 0 tall and thin
	set(v):
		squash = v
		queue_redraw()
var breath := 1.0:  # holes only: slow idle swell, on top of visual_scale
	set(v):
		breath = v
		queue_redraw()

var _points := PackedVector2Array()  # centered on (0, 0)
var _show_focus := false
var _move_tween: Tween
var _scale_tween: Tween
var _shake_tween: Tween
var _tilt_tween: Tween
var _squash_tween: Tween


func setup(shape: Dictionary, piece: bool) -> void:
	shape_name = shape.name
	is_piece = piece
	_points.clear()
	for v in shape.points:
		_points.append(v - Shapes.CENTER)
	radius = Shapes.radius(shape.points)
	set("accessibility_name", "%s %s" % [shape_name.replace("_", " "), "piece" if piece else "hole"])
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	z_index = 2 if piece else 0


func _ready() -> void:
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(queue_redraw)
	get_parent().resized.connect(_update_layout)
	_update_layout()
	if not is_piece:
		_breathe()


## Holes swell and settle slowly, out of step with each other, to show they
## are there to be filled.
func _breathe() -> void:
	var t := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_interval(randf_range(0.0, 1.2))
	t.tween_property(self, "breath", 1.05, 1.2)
	t.tween_property(self, "breath", 1.0, 1.2)


## Reads side_fraction and outline_percent from CONFIG_PATH.
static func load_size() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not data is Dictionary:
		push_error("Bad or missing shape size in %s" % CONFIG_PATH)
		return
	side_fraction = clampf(float(data.get("size_percent", side_fraction * 100)) / 100, 0.01, 1.0)
	outline_percent = clampf(float(data.get("outline_percent", outline_percent)), 1.0, 50.0)


static func save_size() -> Error:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var data := {"size_percent": snappedf(side_fraction * 100, 0.01), "outline_percent": snappedf(outline_percent, 0.01)}
	for key in data:
		if data[key] == int(data[key]):
			data[key] = int(data[key])  # keep whole numbers free of a trailing .0
	file.store_string(JSON.stringify(data, "\t", false) + "\n")
	return OK


## Side length in pixels of a piece or hole on a board of this size.
static func side_for(board_size: Vector2) -> float:
	return minf(board_size.x, board_size.y) * side_fraction


func _update_layout() -> void:
	var board := get_parent() as Control
	if board == null:
		return
	var side := side_for(board.size)
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


## Slides into a hole, then shrinks and fades away before freeing itself.
func vanish_into(target: Vector2) -> void:
	move_to(target)
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_interval(0.2)
	t.tween_property(self, "visual_scale", 0.0, 0.2)
	t.parallel().tween_property(self, "modulate:a", 0.0, 0.2)
	t.tween_callback(queue_free)


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


## Squish flat, then spring tall past the rest shape before settling, like a
## soft toy being pressed. amount is the first, flattest squash.
func squish(amount := 0.18) -> void:
	if _squash_tween:
		_squash_tween.kill()
	_squash_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_squash_tween.tween_property(self, "squash", amount, 0.06)
	_squash_tween.tween_property(self, "squash", -amount * 0.6, 0.1)
	_squash_tween.tween_property(self, "squash", amount * 0.25, 0.1)
	_squash_tween.tween_property(self, "squash", 0.0, 0.12)


func _on_focus_entered() -> void:
	# Only show the focus ring for keyboard focus, like CSS :focus-visible.
	_show_focus = not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	queue_redraw()


## A closed outline outline_percent wide, with rounded corners so sharp points
## like the star's stay joined.
func _draw_hollow(outline: PackedVector2Array, color: Color) -> void:
	draw_polyline(outline, color, outline_percent, true)
	for v in outline:
		draw_circle(v, outline_percent / 2, color)


## The outline grown outward by offset (in 100x100 box units), closed and
## placed on the canvas as currently drawn, moves and squashes included.
func outline_around(offset: float) -> Array[PackedVector2Array]:
	var to_canvas := get_global_transform() * _shape_transform()
	var loops: Array[PackedVector2Array] = []
	for grown in Geometry2D.offset_polygon(_points, offset, Geometry2D.JOIN_ROUND):
		var loop := to_canvas * grown
		loop.append(loop[0])
		loops.append(loop)
	return loops


func _shape_transform() -> Transform2D:
	var k := size.x / 100.0
	return Transform2D(tilt, Vector2(1 + squash, 1 - squash) * k * visual_scale * breath, 0, size / 2 + Vector2(shake_offset, 0))


func _draw() -> void:
	if _points.is_empty():
		return
	var k := size.x / 100.0
	draw_set_transform_matrix(_shape_transform())
	var outline := _points.duplicate()
	outline.append(_points[0])

	if dragging:
		var shadow := PackedVector2Array()
		for v in outline:
			shadow.append(v + Vector2(0, 6.0 / k))
		_draw_hollow(shadow, Color(0, 0, 0, 0.35))
	if selected:
		draw_polyline(outline, Color(ACCENT, 0.25), 12.0, true)
		draw_polyline(outline, Color(ACCENT, 0.6), 6.0, true)

	if is_piece:
		_draw_hollow(outline, fill)
	else:
		draw_colored_polygon(_points, HOLE_FILL)

	draw_set_transform(Vector2.ZERO)
	if has_focus() and _show_focus:
		var r := Rect2(Vector2.ZERO, size).grow(6)
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for i in 4:
			draw_dashed_line(corners[i], corners[(i + 1) % 4], ACCENT, 2.0, 4.0)
