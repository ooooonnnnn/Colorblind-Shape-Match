class_name Icons
## Literal picture icons for the toddler-facing UI, drawn as polygons so they
## stay crisp at any size. Each fits a box of the given side centered on center.

const INK := Color("3b2f4a")  # outline around icons, dark enough to read on any pastel
const PLUS := [[-0.2, -0.75], [0.2, -0.75], [0.2, -0.2], [0.75, -0.2], [0.75, 0.2], [0.2, 0.2], [0.2, 0.75],
		[-0.2, 0.75], [-0.2, 0.2], [-0.75, 0.2], [-0.75, -0.2], [-0.2, -0.2]]


static func draw(canvas: CanvasItem, icon: String, center: Vector2, side: float, color: Color) -> void:
	var outline := maxf(2.0, side * 0.06)
	for part in _parts(icon, side):
		var points: PackedVector2Array = part
		var placed := PackedVector2Array()
		for v in points:
			placed.append(center + v)
		canvas.draw_colored_polygon(placed, color)
		placed.append(placed[0])
		canvas.draw_polyline(placed, INK, outline, true)


## Polygons centered on (0, 0), in px.
static func _parts(icon: String, side: float) -> Array[PackedVector2Array]:
	var h := side / 2
	match icon:
		"star":
			return [star(h, h * 0.48)]
		"play":
			return [_scaled([[-0.55, -0.75], [0.8, 0.0], [-0.55, 0.75]], h)]
		"house":
			return [_scaled([[0, -0.9], [0.9, -0.05], [0.65, -0.05], [0.65, 0.8], [-0.65, 0.8], [-0.65, -0.05], [-0.9, -0.05]], h),
					_scaled([[-0.2, 0.8], [-0.2, 0.25], [0.2, 0.25], [0.2, 0.8]], h)]
		"chart":
			return [_scaled([[-0.85, 0.8], [-0.85, 0.05], [-0.35, 0.05], [-0.35, 0.8]], h),
					_scaled([[-0.25, 0.8], [-0.25, -0.75], [0.25, -0.75], [0.25, 0.8]], h),
					_scaled([[0.35, 0.8], [0.35, -0.3], [0.85, -0.3], [0.85, 0.8]], h)]
		"plus":
			return [_scaled(PLUS, h)]
		"minus":
			return [_scaled([[-0.75, -0.2], [0.75, -0.2], [0.75, 0.2], [-0.75, 0.2]], h)]
		"cross":
			return [Transform2D(PI / 4, Vector2.ZERO) * _scaled(PLUS, h)]
		"check":
			return [_scaled([[-0.8, 0.0], [-0.5, -0.3], [-0.2, 0.0], [0.5, -0.7], [0.8, -0.4], [-0.2, 0.6]], h)]
		"gear":
			var gear := PackedVector2Array()
			for i in 32:
				var a := TAU * i / 32.0
				gear.append(Vector2.from_angle(a) * h * (0.9 if (i / 2) % 2 == 0 else 0.68))
			return [gear, _circle(h * 0.28)]
	push_error("Unknown icon: %s" % icon)
	return []


static func star(outer: float, inner: float, points := 5) -> PackedVector2Array:
	var star := PackedVector2Array()
	for i in points * 2:
		star.append(Vector2.from_angle(-PI / 2 + PI * i / points) * (outer if i % 2 == 0 else inner))
	return star


static func _circle(r: float) -> PackedVector2Array:
	var circle := PackedVector2Array()
	for i in 24:
		circle.append(Vector2.from_angle(TAU * i / 24.0) * r)
	return circle


static func _scaled(coords: Array, h: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for c in coords:
		points.append(Vector2(c[0], c[1]) * h)
	return points
