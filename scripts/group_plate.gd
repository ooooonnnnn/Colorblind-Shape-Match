extends Control
## A small dotted plate in a color group's colors: background dots around a star
## of figure-color dots, varying in size and lightness like the game's filter.

const ATTEMPTS := 3000      # random placements tried when laying out the dots
const MIN_RADIUS := 0.018   # dot radii, as fractions of the plate's side
const MAX_RADIUS := 0.045
const GAP := 0.006
const SHADE := 0.12         # largest lightness shift of a dot, in HSV value

var background := Color.GRAY:
	set(v):
		background = v
		queue_redraw()
var colors: Array = []:
	set(v):
		colors = v
		queue_redraw()

## {pos, radius} in plate fractions, shade, figure (index or -1); laid out
## once and shared by every plate.
static var _dots: Array[Dictionary] = []


func _ready() -> void:
	if _dots.is_empty():
		_lay_out()


static func _lay_out() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var star := PackedVector2Array()
	for v in Shapes.make("star"):
		star.append(Vector2(0.5, 0.5) + (v - Shapes.CENTER) / 100.0 * 0.62)
	for _try in ATTEMPTS:
		var pos := Vector2(rng.randf(), rng.randf())
		var room := 0.5 - pos.distance_to(Vector2(0.5, 0.5))
		for d in _dots:
			room = minf(room, pos.distance_to(d.pos) - d.radius - GAP)
		if room < MIN_RADIUS:
			continue
		_dots.append({
			"pos": pos,
			"radius": minf(room, rng.randf_range(MIN_RADIUS, MAX_RADIUS)),
			"shade": rng.randf_range(-SHADE, SHADE),
			"figure": rng.randi() if Geometry2D.is_point_in_polygon(pos, star) else -1,
		})


func _draw() -> void:
	var side := minf(size.x, size.y)
	var corner := (size - Vector2.ONE * side) / 2
	for d in _dots:
		var base: Color = colors[d.figure % colors.size()] if d.figure >= 0 and not colors.is_empty() else background
		var shaded := Color.from_hsv(base.h, base.s, clampf(base.v + d.shade, 0, 1))
		draw_circle(corner + d.pos * side, d.radius * side, shaded)
