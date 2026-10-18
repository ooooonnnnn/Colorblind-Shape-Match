class_name Shapes
## Shape generators. Each returns a closed polygon in a 100x100 box centered on (50, 50).

const NAMES := [
	"triangle", "square", "rectangle", "pentagon", "hexagon", "octagon", "star", "cross",
	"diamond", "trapezoid", "arrow", "l_shape", "t_shape", "heart", "crescent", "ellipse", "blob",
]

const CENTER := Vector2(50, 50)


static func make(shape_name: String) -> PackedVector2Array:
	match shape_name:
		"triangle":
			return _poly([[50, 6], [94, 84], [6, 84]])
		"square":
			return _poly([[16, 16], [84, 16], [84, 84], [16, 84]])
		"rectangle":
			var h := randf_range(16, 22)
			return _poly([[6, 50 - h], [94, 50 - h], [94, 50 + h], [6, 50 + h]])
		"pentagon":
			return _ngon(5)
		"hexagon":
			return _ngon(6)
		"octagon":
			return _ngon(8)
		"star":
			var points := randi_range(4, 6)
			var inner := randf_range(18, 24)
			var radii := []
			for i in points * 2:
				radii.append(inner if i % 2 else 48.0)
			return _radial(radii)
		"cross":
			var t := randf_range(12, 16)
			var a := 50 - t
			var b := 50 + t
			return _poly([[a, 4], [b, 4], [b, a], [96, a], [96, b], [b, b], [b, 96], [a, 96], [a, b], [4, b], [4, a], [a, a]])
		"diamond":
			var w := randf_range(26, 32)
			return _poly([[50, 4], [50 + w, 50], [50, 96], [50 - w, 50]])
		"trapezoid":
			var top := randf_range(14, 24)
			return _poly([[50 - top, 22], [50 + top, 22], [94, 78], [6, 78]])
		"arrow":
			return _poly([[6, 38], [56, 38], [56, 14], [94, 50], [56, 86], [56, 62], [6, 62]])
		"l_shape":
			return _poly([[16, 6], [44, 6], [44, 66], [86, 66], [86, 94], [16, 94]])
		"t_shape":
			return _poly([[6, 8], [94, 8], [94, 36], [64, 36], [64, 94], [36, 94], [36, 36], [6, 36]])
		"heart":
			return _heart()
		"crescent":
			return _crescent()
		"ellipse":
			return _ellipse(46, randf_range(22, 30))
		"blob":
			var radii := []
			for i in 7:
				radii.append(randf_range(26, 47))
			return _radial(radii, randf_range(0, 360))
	push_error("Unknown shape: %s" % shape_name)
	return PackedVector2Array()


## Distinct shape families per level so every piece fits exactly one hole.
static func pick(n: int) -> Array[Dictionary]:
	var names := NAMES.duplicate()
	names.shuffle()
	var shapes: Array[Dictionary] = []
	for shape_name in names.slice(0, n):
		var rot := deg_to_rad(randi_range(0, 359))
		var points := PackedVector2Array()
		for v in make(shape_name):
			points.append(CENTER + (v - CENTER).rotated(rot))
		shapes.append({"name": shape_name, "points": points})
	return shapes


static func _poly(coords: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for c in coords:
		points.append(Vector2(c[0], c[1]))
	return points


static func _radial(radii: Array, start := -90.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in radii.size():
		var t := deg_to_rad(start + 360.0 * i / radii.size())
		points.append(CENTER + Vector2.from_angle(t) * radii[i])
	return points


static func _ngon(n: int) -> PackedVector2Array:
	var radii := []
	radii.resize(n)
	radii.fill(46.0)
	return _radial(radii)


static func _ellipse(rx: float, ry: float, steps := 48) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in steps:
		var t := TAU * i / steps
		points.append(CENTER + Vector2(rx * cos(t), ry * sin(t)))
	return points


static func _heart() -> PackedVector2Array:
	# Cubic Bezier segments: start, control 1, control 2, end.
	var segments := [
		[Vector2(50, 90), Vector2(14, 64), Vector2(2, 40), Vector2(14, 22)],
		[Vector2(14, 22), Vector2(26, 6), Vector2(46, 10), Vector2(50, 28)],
		[Vector2(50, 28), Vector2(54, 10), Vector2(74, 6), Vector2(86, 22)],
		[Vector2(86, 22), Vector2(98, 40), Vector2(86, 64), Vector2(50, 90)],
	]
	var steps := 12
	var points := PackedVector2Array([segments[0][0]])
	for s in segments:
		for i in range(1, steps + 1):
			points.append(s[0].bezier_interpolate(s[1], s[2], s[3], float(i) / steps))
	points.remove_at(points.size() - 1)  # the last point closes back onto the first
	return points


static func _crescent() -> PackedVector2Array:
	# Outer arc: radius 48 from (66, 4) around the left side to (66, 96).
	# Inner arc: radius 52 from (66, 96) back up to (66, 4), bulging left.
	var tip_top := Vector2(66, 4)
	var outer_center := Vector2(66 - sqrt(48.0 * 48 - 46 * 46), 50)
	var inner_center := Vector2(66 + sqrt(52.0 * 52 - 46 * 46), 50)
	var points := PackedVector2Array()
	var steps := 24
	var a := (tip_top - outer_center).angle()
	for i in steps + 1:
		points.append(outer_center + Vector2.from_angle(a - (TAU + 2 * a) * i / steps) * 48)
	var b := (Vector2(66, 96) - inner_center).angle()
	for i in range(1, steps):
		points.append(inner_center + Vector2.from_angle(b + (TAU - 2 * b) * i / steps) * 52)
	return points
