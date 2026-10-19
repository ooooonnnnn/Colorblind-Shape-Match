class_name LevelPicture
extends Control
## A tiny drawing of a level: its holes in a cream tray, each with the pieces
## that go into it lined up underneath, and dots behind when the filter is on.

const HOLE := Color("0e1118")
const TRAY := Color("fff3d6")
const TRAY_EDGE := Color("f4b860")
const PIECE := Color("ff8fab")
const DOT := Color("2ecc71")
const Dots := preload("res://scripts/dots.gd")
const SHAPES := ["circle", "square", "triangle", "star", "kite", "crescent"]  # one per hole, in this order

var holes := 3:
	set(v):
		holes = v
		queue_redraw()
var pieces := 3:  # per hole
	set(v):
		pieces = v
		queue_redraw()
var filter := true:
	set(v):
		filter = v
		queue_redraw()


func _draw() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Dots.PAPER
	bg.set_corner_radius_all(12)
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	if filter:
		# A sprinkle of dots, always the same, standing for the Ishihara filter.
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		for i in 70:
			draw_circle(Vector2(rng.randf() * size.x, rng.randf() * size.y), rng.randf_range(1.5, 3.5), Color(DOT, 0.7))

	var shown := mini(holes, SHAPES.size())
	var cell := minf(size.x / (shown + 0.6), size.y * 0.42)
	var x0 := (size.x - cell * shown) / 2
	var tray := Rect2(x0 - cell * 0.15, size.y * 0.08, cell * (shown + 0.3), cell * 0.95)
	var tray_box := StyleBoxFlat.new()
	tray_box.bg_color = TRAY
	tray_box.border_color = TRAY_EDGE
	tray_box.set_border_width_all(2)
	tray_box.set_corner_radius_all(8)
	draw_style_box(tray_box, tray)

	var piece_row := size.y * 0.08 + cell * 1.25
	var piece_side := minf(cell * 0.32, (size.y - piece_row) / maxf(1, ceilf(pieces / 3.0)) * 0.9)
	for i in shown:
		var center := Vector2(x0 + cell * (i + 0.5), tray.get_center().y)
		_draw_shape(SHAPES[i], center, cell * 0.7, HOLE, false)
		# Up to three pieces per row under the hole; a number when there are many.
		if pieces > 9:
			_draw_shape(SHAPES[i], Vector2(center.x - cell * 0.15, piece_row + piece_side / 2), piece_side, PIECE, true)
			draw_string(get_theme_default_font(), Vector2(center.x, piece_row + piece_side * 0.8), "×%d" % pieces,
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(piece_side * 0.9), Icons.INK)
			continue
		for j in pieces:
			var col := j % 3
			var row := j / 3
			var across := mini(3, pieces - row * 3)
			var px := center.x + (col - (across - 1) / 2.0) * piece_side * 1.1
			_draw_shape(SHAPES[i], Vector2(px, piece_row + piece_side * (row + 0.5) * 1.1), piece_side, PIECE, true)
	if holes > shown:
		draw_string(get_theme_default_font(), Vector2(tray.end.x + 4, tray.get_center().y + 6), "+%d" % (holes - shown),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Icons.INK)


func _draw_shape(shape_name: String, center: Vector2, side: float, color: Color, hollow: bool) -> void:
	var points := PackedVector2Array()
	for v in Shapes.make(shape_name):
		points.append(center + (v - Shapes.CENTER) / 100.0 * side)
	if hollow:
		points.append(points[0])
		draw_polyline(points, color, maxf(1.5, side * 0.1), true)
	else:
		draw_colored_polygon(points, color)
