class_name ShapeView
extends Control
## A piece or a hole. Draws one polygon from a 100x100 box, positioned by its
## center in board-relative (0..1) coordinates so it follows board resizes.

const CONFIG_PATH := "res://shape_size.json"

const PIECE_FILL := Color("f1ede2")
const HOLE_FILL := Color("161b28")  # very dark, a touch lighter than the shadow so the depth shows
const HOLE_SHADOW := Color("030406")  # the top inner wall, in the hole's own shadow
const HOLE_RIM := Color("d9a35a")     # the tray's edge turning down into the hole
const HOLE_LIP := Color(1, 1, 1, 0.75)  # light catching the tray's edge below the hole
const HOLE_DEPTH := 9.0  # box units the inner shadow reaches down from the hole's top edge
const ACCENT := Color.WHITE
const TOUCH_SLOP := 0.12  # how far past its outline a tap still lands, as a fraction of the side

static var side_fraction := 0.2  # width as a fraction of the board's shorter side
## Width of a piece's outline, as a percentage of its side. Pieces are drawn
## hollow so they are harder to spot in the dot filter; bolder is easier, and
## much thinner the line slips between dot centers, where the filter samples.
static var outline_percent := 26.0
## Shrinks shapes below side_fraction for a level whose row of holes would
## not fit across the board otherwise, as on an upright phone (see main.gd).
static var fit_scale := 1.0

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
var opening := 1.0:  # holes only: swell while a dragged piece hovers over it, on top of breath
	set(v):
		opening = v
		queue_redraw()

var _points := PackedVector2Array()  # centered on (0, 0)
var _show_focus := false
var _move_tween: Tween
var _scale_tween: Tween
var _shake_tween: Tween
var _tilt_tween: Tween
var _squash_tween: Tween
var _open_tween: Tween


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
	fit_scale = 1.0
	var data = JSON.parse_string(FileAccess.get_file_as_string(SettingsFile.read_path(CONFIG_PATH)))
	if not data is Dictionary:
		push_error("Bad or missing shape size in %s" % CONFIG_PATH)
		return
	side_fraction = clampf(float(data.get("size_percent", side_fraction * 100)) / 100, 0.01, 1.0)
	outline_percent = clampf(float(data.get("outline_percent", outline_percent)), 1.0, 50.0)


static func save_size() -> Error:
	var file := FileAccess.open(SettingsFile.write_path(CONFIG_PATH), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var data := {"size_percent": snappedf(side_fraction * 100, 0.01), "outline_percent": snappedf(outline_percent, 0.01)}
	for key in data:
		if data[key] == int(data[key]):
			data[key] = int(data[key])  # keep whole numbers free of a trailing .0
	file.store_string(JSON.stringify(data, "\t", false) + "\n")
	return OK


## Taps land anywhere in the bounding circle, outline included, and a little
## past it, so a slightly-off tap still counts, even outside the square box.
func _has_point(point: Vector2) -> bool:
	return point.distance_to(size / 2) <= size.x * (radius + outline_percent / 200 + TOUCH_SLOP)


## Side length in pixels of a piece or hole on a board of this size.
static func side_for(board_size: Vector2) -> float:
	return minf(board_size.x, board_size.y) * side_fraction * fit_scale


func _update_layout() -> void:
	var board := get_parent() as Control
	if board == null:
		return
	var side := side_for(board.size)
	size = Vector2(side, side)
	position = norm_pos * board.size - size / 2


## Slides to target; springy overshoots and settles, like a toy sent bouncing back.
func move_to(target: Vector2, animate := true, springy := false) -> void:
	if _move_tween:
		_move_tween.kill()
	if not animate:
		norm_pos = target
		return
	if springy:
		_move_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_move_tween.tween_property(self, "norm_pos", target, 0.32)
	else:
		_move_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_move_tween.tween_property(self, "norm_pos", target, 0.18)


## Snaps into a hole, swells for a moment as if gulped, then shrinks away and frees itself.
func vanish_into(target: Vector2) -> void:
	if _move_tween:
		_move_tween.kill()
	_move_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "norm_pos", target, 0.15)
	var t := create_tween()
	t.tween_interval(0.1)
	t.tween_property(self, "visual_scale", 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(self, "modulate:a", 0.0, 0.18).set_delay(0.06)
	t.tween_callback(queue_free)


func scale_to(s: float) -> void:
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "visual_scale", s, 0.12)


## Springs up from nothing after delay seconds, as a level starts.
func pop_in(delay: float) -> void:
	visual_scale = 0.0
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.tween_interval(delay)
	_scale_tween.tween_property(self, "visual_scale", 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Holes only: opens up while a dragged piece hovers over it, ready to take it in.
func set_open(open: bool) -> void:
	if _open_tween:
		_open_tween.kill()
	_open_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(self, "opening", 1.12 if open else 1.0, 0.14)


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
		_tilt_tween.tween_property(self, "tilt", deg_to_rad(deg), 0.07)


## Ease back upright, as when let go after leaning into a drag.
func level_tilt() -> void:
	if _tilt_tween:
		_tilt_tween.kill()
	_tilt_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tilt_tween.tween_property(self, "tilt", 0.0, 0.3)


## One soft, even swell and back, as when a hole takes in its piece.
func pulse() -> void:
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_scale_tween.tween_property(self, "visual_scale", 1.12, 0.12).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "visual_scale", 1.0, 0.24).set_ease(Tween.EASE_IN_OUT)


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
	_squash_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_squash_tween.tween_property(self, "squash", amount, 0.06)
	_squash_tween.tween_property(self, "squash", -amount * 0.6, 0.1)
	_squash_tween.tween_property(self, "squash", amount * 0.25, 0.1)
	_squash_tween.tween_property(self, "squash", 0.0, 0.12)


func _on_focus_entered() -> void:
	# Only show the focus ring for keyboard focus, like CSS :focus-visible.
	_show_focus = not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	queue_redraw()


## A closed outline outline_percent wide with round corners. The sides are
## separate segments, since a connected thick line gets mitered spikes at sharp
## points; this way the outer edge is exactly the outline grown by half the
## width with round joins, which is what outline_around and the glow follow.
func _draw_hollow(outline: PackedVector2Array, color: Color) -> void:
	var sides := PackedVector2Array()
	for i in outline.size() - 1:
		sides.append(outline[i])
		sides.append(outline[i + 1])
	draw_multiline(sides, color, outline_percent, true)
	for v in outline:
		draw_circle(v, outline_percent / 2, color)


## A hole cut into the tray, lit from above: a rim where the tray's edge turns
## down, a bright lip where light catches the edge below it, the very dark
## hole, and a deeper shadow along its top inner wall. All in box units.
func _draw_hole(silhouette: PackedVector2Array) -> void:
	for rim in Geometry2D.offset_polygon(silhouette, 3.5, Geometry2D.JOIN_ROUND):
		draw_colored_polygon(rim, HOLE_RIM)
	var lower := Transform2D(0, Vector2(0, 3.0)) * silhouette
	for lip in Geometry2D.clip_polygons(lower, silhouette):
		draw_colored_polygon(lip, HOLE_LIP)
	draw_colored_polygon(silhouette, HOLE_FILL)
	var deeper := Transform2D(0, Vector2(0, HOLE_DEPTH)) * silhouette
	for shade in Geometry2D.clip_polygons(silhouette, deeper):
		draw_colored_polygon(shade, HOLE_SHADOW)


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
	return Transform2D(tilt, Vector2(1 + squash, 1 - squash) * k * visual_scale * breath * opening, 0, size / 2 + Vector2(shake_offset, 0))


func _draw() -> void:
	if _points.is_empty():
		return
	draw_set_transform_matrix(_shape_transform())
	var outline := _points.duplicate()
	outline.append(_points[0])

	if selected:
		draw_polyline(outline, Color(ACCENT, 0.25), 12.0, true)
		draw_polyline(outline, Color(ACCENT, 0.6), 6.0, true)

	if is_piece:
		_draw_hollow(outline, fill)
	else:
		# The piece's outer edge: its outline grown by half the outline width with
		# round corners, so a piece fits its hole exactly, corners and all.
		for silhouette in Geometry2D.offset_polygon(_points, outline_percent / 2, Geometry2D.JOIN_ROUND):
			_draw_hole(silhouette)

	draw_set_transform(Vector2.ZERO)
	if has_focus() and _show_focus:
		var r := Rect2(Vector2.ZERO, size).grow(6)
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for i in 4:
			draw_dashed_line(corners[i], corners[(i + 1) % 4], ACCENT, 2.0, 4.0)
