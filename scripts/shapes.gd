class_name Shapes
## Shape generators. Each returns a closed polygon in a 100x100 box centered on (50, 50).

const NAMES := ["square", "circle", "triangle", "star", "kite", "crescent"]

const CENTER := Vector2(50, 50)


static func make(shape_name: String) -> PackedVector2Array:
	match shape_name:
		"square":
			return _poly([[16, 16], [84, 16], [84, 84], [16, 84]])
		"circle":
			return _ellipse(46, 46)
		"triangle":
			return _poly([[50, 6], [94, 84], [6, 84]])
		"star":
			var radii := []
			for i in 10:
				radii.append(20.0 if i % 2 else 48.0)
			return _radial(radii)
		"kite":
			return _poly([[50, 4], [78, 36], [50, 96], [22, 36]])
		"crescent":
			return _crescent()
	push_error("Unknown shape: %s" % shape_name)
	return PackedVector2Array()


## Radius of the bounding circle around the box center, as a fraction of the box size.
static func radius(points: PackedVector2Array) -> float:
	var r := 0.0
	for v in points:
		r = maxf(r, v.distance_to(CENTER))
	return r / 100.0


## Distinct shape families per level so every piece fits exactly one hole,
## drawn from the given names (all shapes by default).
static func pick(n: int, from: Array = NAMES) -> Array[Dictionary]:
	var names := from.duplicate()
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


static func _ellipse(rx: float, ry: float, steps := 48) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in steps:
		var t := TAU * i / steps
		points.append(CENTER + Vector2(rx * cos(t), ry * sin(t)))
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
