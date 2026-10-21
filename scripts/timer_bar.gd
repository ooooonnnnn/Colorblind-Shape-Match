class_name TimerBar
extends Control
## Countdown bar that empties from the right: a chunky pill with a drop
## shadow and a glossy fill, like a toy. Low time is signalled by a stripe
## pattern, not by color alone.

const STRIPE := 8.0  # stripe thickness, measured across the 45° stripes

const FG := Color("ffd166")     # sunny yellow
const MUTED := Color("ff9f43")  # warmer orange under the low-time stripes

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


func _draw() -> void:
	var h := size.y
	var pill := StyleBoxFlat.new()
	pill.set_corner_radius_all(99)
	pill.bg_color = Color(Icons.INK, 0.15)  # soft drop shadow
	draw_style_box(pill, Rect2(0, 3, size.x, h))
	pill.bg_color = Color(1, 1, 1, 0.75)
	draw_style_box(pill, Rect2(Vector2.ZERO, size))
	var w := size.x * ratio
	if w > 0:
		var inner := Rect2(3, 3, maxf(w - 6, h - 6), h - 6)
		if not low:
			pill.bg_color = FG
			draw_style_box(pill, inner)
		else:
			var fill := Backdrop._rounded(inner, inner.size.y / 2)  # stripes stay inside the round ends
			pill.bg_color = MUTED
			draw_style_box(pill, inner)
			var step := STRIPE * sqrt(2.0)  # horizontal width of one stripe
			var x := inner.position.x - h
			while x < inner.end.x:
				var stripe := PackedVector2Array([Vector2(x, inner.end.y), Vector2(x + h, inner.position.y),
						Vector2(x + h + step, inner.position.y), Vector2(x + step, inner.end.y)])
				for part in Geometry2D.intersect_polygons(stripe, fill):
					draw_colored_polygon(part, FG)
				x += step * 2
		# A glossy band along the top of the fill.
		pill.bg_color = Color(1, 1, 1, 0.4)
		draw_style_box(pill, Rect2(inner.position + Vector2(h * 0.3, inner.size.y * 0.12), Vector2(maxf(inner.size.x - h * 0.6, 0), inner.size.y * 0.3)))
	pill.bg_color = Color.TRANSPARENT
	pill.set_border_width_all(3)
	pill.border_color = Icons.INK
	draw_style_box(pill, Rect2(Vector2.ZERO, size))
