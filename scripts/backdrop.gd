class_name Backdrop
extends Control
## A soft vertical gradient in a rounded rectangle, with an optional warm glow
## near the top and a few faint pastel bubbles: the page's sky, and the board
## of levels without the dot filter. Draws nothing it is clicked through.

const GLOW := Color(1.0, 0.97, 0.85)  # warm sunlight

@export var top := Color("d6f0ff")
@export var bottom := Color("b8e0ff")
@export var radius := 0.0  ## px, rounding of the corners
@export var glow := false  ## a soft warm light near the top middle
@export var bubbles := false  ## faint pastel circles drifting slowly

var _time := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	if bubbles and is_visible_in_tree():
		_time += delta
		queue_redraw()


func _draw() -> void:
	var outline := _rounded(Rect2(Vector2.ZERO, size), radius)
	var colors := PackedColorArray()
	for v in outline:
		colors.append(top.lerp(bottom, v.y / maxf(size.y, 1.0)))
	draw_polygon(outline, colors)
	if glow:
		# Rings fading outward, so the light has no edge.
		var center := Vector2(size.x / 2, size.y * 0.12)
		var reach := minf(size.x, size.y) * 0.75
		for i in 14:
			var f := 1.0 - i / 14.0
			draw_circle(center, reach * f, Color(GLOW, 0.06))
	if bubbles:
		# Fixed spots, each bobbing on its own slow beat, kept clear of the corners.
		var spots := [[0.12, 0.3, 0.09, Color("ffd6e5")], [0.85, 0.22, 0.12, Color("fff1b8")],
				[0.3, 0.75, 0.07, Color("d9f7d6")], [0.7, 0.62, 0.1, Color("e6dcff")], [0.52, 0.18, 0.05, Color("ffe1cc")]]
		var side := minf(size.x, size.y)
		for i in spots.size():
			var s: Array = spots[i]
			var bob := sin(_time * 0.6 + i * 1.7) * side * 0.012
			draw_circle(Vector2(size.x * s[0], size.y * s[1] + bob), side * s[2], Color(s[3], 0.45))


## The corners of rect, rounded by r, as a polygon.
static func _rounded(rect: Rect2, r: float) -> PackedVector2Array:
	r = minf(r, minf(rect.size.x, rect.size.y) / 2)
	var points := PackedVector2Array()
	if r <= 0:
		return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var corners := [Vector2(rect.end.x - r, rect.position.y + r), Vector2(rect.end.x - r, rect.end.y - r),
			Vector2(rect.position.x + r, rect.end.y - r), Vector2(rect.position.x + r, rect.position.y + r)]
	for c in 4:
		for i in 9:
			points.append(corners[c] + Vector2.from_angle(-PI / 2 + PI / 2 * (c + i / 8.0)) * r)
	return points
