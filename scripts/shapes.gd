class_name Shapes
extends RefCounted
## Library of unit-sized outline polygons (max vertex radius == 1, bbox-centred).

const NAMES := [
	"circle", "triangle", "square", "pentagon", "hexagon", "star",
	"cross", "heart", "diamond", "arrow", "semicircle", "lshape",
]


static func get_shape(name: String) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match name:
		"circle":
			pts = _regular(40, 0.0)
		"triangle":
			pts = _regular(3, -PI / 2.0)
		"square":
			pts = _regular(4, PI / 4.0)
		"pentagon":
			pts = _regular(5, -PI / 2.0)
		"hexagon":
			pts = _regular(6, 0.0)
		"star":
			for i in 10:
				var r := 1.0 if i % 2 == 0 else 0.45
				var a := -PI / 2.0 + i * PI / 5.0
				pts.append(Vector2(cos(a), sin(a)) * r)
		"cross":
			var t := 0.34
			for v in [[-t, -1], [t, -1], [t, -t], [1, -t], [1, t], [t, t], [t, 1], [-t, 1],
					[-t, t], [-1, t], [-1, -t], [-t, -t]]:
				pts.append(Vector2(v[0], v[1]))
		"heart":
			for i in 48:
				var a := i * TAU / 48.0
				var x := 16.0 * pow(sin(a), 3.0)
				var y := -(13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a))
				pts.append(Vector2(x, y))
		"diamond":
			for v in [[0, -1], [0.6, 0], [0, 1], [-0.6, 0]]:
				pts.append(Vector2(v[0], v[1]))
		"arrow":
			for v in [[0, -1], [1, 0], [0.4, 0], [0.4, 1], [-0.4, 1], [-0.4, 0], [-1, 0]]:
				pts.append(Vector2(v[0], v[1]))
		"semicircle":
			for i in 25:
				var a := PI + i * PI / 24.0
				pts.append(Vector2(cos(a), sin(a)))
		"lshape":
			for v in [[-1, -1], [-0.2, -1], [-0.2, 0.2], [1, 0.2], [1, 1], [-1, 1]]:
				pts.append(Vector2(v[0], v[1]))
	return _normalize(pts)


static func _regular(n: int, start: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := start + i * TAU / n
		pts.append(Vector2(cos(a), sin(a)))
	return pts


static func _normalize(pts: PackedVector2Array) -> PackedVector2Array:
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var c := (lo + hi) * 0.5
	var m := 0.0
	for p in pts:
		m = maxf(m, (p - c).length())
	var out := PackedVector2Array()
	for p in pts:
		out.append((p - c) / m)
	return out
