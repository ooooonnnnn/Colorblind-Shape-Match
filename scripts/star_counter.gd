class_name StarCounter
extends Control
## The stars earned this run: a chunky pill with a happy star and the count.
## A level's cheering star flies into it (see Effects.cheer), and it bumps
## and wiggles as the count goes up.

const STAR := 0.86  # the star's side, as a fraction of the pill's height

var count := 0:
	set(v):
		count = v
		queue_redraw()

var _bump := 0.0:  # 0 at rest; swells the pill and tips the star while it springs back
	set(v):
		_bump = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(150, 64)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


## Counts one more, with a springy bump.
func add_one() -> void:
	count += 1
	var t := create_tween()
	t.tween_property(self, "_bump", 0.0, 0.5).from(1.0).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Where on screen the star sits and its side, for a flying star to land in.
func star_spot() -> Rect2:
	var side := size.y * STAR
	var center := get_global_transform() * Vector2(size.y / 2 + 4, size.y / 2)
	return Rect2(center - Vector2.ONE * side / 2, Vector2.ONE * side)


func _draw() -> void:
	var swell := 1.0 + 0.12 * _bump
	draw_set_transform(size / 2, 0, Vector2.ONE * swell)
	var box := Rect2(-size / 2, size)
	var pill := StyleBoxFlat.new()
	pill.set_corner_radius_all(99)
	pill.bg_color = Color(Icons.INK, 0.15)  # soft drop shadow
	draw_style_box(pill, Rect2(box.position + Vector2(0, 3), box.size))
	pill.bg_color = Color(1, 1, 1, 0.85)
	draw_style_box(pill, box)
	pill.bg_color = Color.TRANSPARENT
	pill.set_border_width_all(3)
	pill.border_color = Icons.INK
	draw_style_box(pill, box)
	var star_center := Vector2(-size.x / 2 + size.y / 2 + 4, 0)
	draw_set_transform(size / 2 + star_center * swell, sin(_bump * 9.0) * 0.3 * _bump, Vector2.ONE * swell)
	Effects.draw_star(self, Vector2.ZERO, size.y * STAR, Color("ffd166"))
	draw_set_transform(size / 2, 0, Vector2.ONE * swell)
	var font := get_theme_default_font()
	var text := str(count)
	var font_size := int(size.y * 0.58)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := star_center.x + size.y * STAR / 2 + (size.x / 2 - (star_center.x + size.y * STAR / 2) - w) / 2
	draw_string_outline(font, Vector2(x, font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 8, Color.WHITE)
	draw_string(font, Vector2(x, font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Icons.INK)
	draw_set_transform(Vector2.ZERO)
