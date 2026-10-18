class_name TimerBar
extends Control
## Countdown bar that empties from the right. Low time is signalled by a
## stripe pattern, not by color alone.

const STRIPE := 8.0  # stripe thickness, measured across the 45° stripes

const FG := Color("e9ecf2")
const MUTED := Color("9aa3b5")

var ratio := 1.0:
	set(v):
		if v != ratio:
			ratio = v
			queue_redraw()
var low := false:
	set(v):
		if v != low:
			low = v
			queue_redraw()

var _bg := StyleBoxFlat.new()


func _init() -> void:
	_bg.bg_color = Color("252a37")
	_bg.set_corner_radius_all(4)


func _draw() -> void:
	draw_style_box(_bg, Rect2(Vector2.ZERO, size))
	var w := size.x * ratio
	if w <= 0:
		return
	var h := size.y
	if not low:
		draw_rect(Rect2(0, 0, w, h), FG)
		return

	draw_rect(Rect2(0, 0, w, h), MUTED)
	var fill := PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	var step := STRIPE * sqrt(2.0)  # horizontal width of one stripe
	var x := -h
	while x < w:
		var stripe := PackedVector2Array([Vector2(x, h), Vector2(x + h, 0), Vector2(x + h + step, 0), Vector2(x + step, h)])
		for part in Geometry2D.intersect_polygons(stripe, fill):
			draw_colored_polygon(part, FG)
		x += step * 2
