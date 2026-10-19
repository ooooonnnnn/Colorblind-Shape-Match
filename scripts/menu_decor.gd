extends Control
## Soft pastel shapes drifting around the edges of the title screen.

const COLORS := [Color("ffd6a5"), Color("ffadad"), Color("caffbf"), Color("9bf6ff"), Color("bdb2ff"), Color("fdffb6")]
## Where each shape floats, as fractions of the screen, kept clear of the middle.
const SPOTS := [Vector2(0.1, 0.18), Vector2(0.26, 0.82), Vector2(0.88, 0.2), Vector2(0.75, 0.84),
		Vector2(0.07, 0.56), Vector2(0.93, 0.55), Vector2(0.38, 0.1), Vector2(0.62, 0.92)]

var _shapes: Array[Dictionary] = []  # {points, color, spot, phase, spin}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in SPOTS.size():
		var points := PackedVector2Array()
		for v in Shapes.make(Shapes.NAMES[i % Shapes.NAMES.size()]):
			points.append(v - Shapes.CENTER)
		_shapes.append({"points": points, "color": COLORS[i % COLORS.size()], "spot": SPOTS[i],
				"phase": randf() * TAU, "spin": randf_range(-0.25, 0.25)})


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var side := minf(size.x, size.y) * 0.16
	for s in _shapes:
		var bob := Vector2(0, sin(t * 0.9 + s.phase) * side * 0.12)
		draw_set_transform(s.spot * size + bob, s.phase + t * s.spin, Vector2.ONE * side / 100.0)
		draw_colored_polygon(s.points, s.color)
		var outline: PackedVector2Array = s.points.duplicate()
		outline.append(outline[0])
		draw_polyline(outline, Color(Icons.INK, 0.35), 4.0, true)
	draw_set_transform(Vector2.ZERO)
