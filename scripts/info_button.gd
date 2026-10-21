class_name InfoButton
extends Button
## A small round "?" that opens a short explanation in a PopupCard, so the
## page itself can stay to a title and one plain line.

var title := ""
var about := ""
var squash := 0.0:
	set(v):
		squash = v
		queue_redraw()


func _init(about_title: String, about_text: String) -> void:
	title = about_title
	about = about_text
	flat = true
	custom_minimum_size = Vector2(40, 40)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "What is this?"
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(func():
		var t := create_tween().set_trans(Tween.TRANS_SINE)
		for s in [0.16, -0.1, 0.04, 0.0]:
			t.tween_property(self, "squash", s, 0.07)
	)
	pressed.connect(func(): PopupCard.info(get_tree().current_scene, title, about))


func _draw() -> void:
	var r := minf(size.x, size.y) / 2
	draw_set_transform(size / 2, 0, Vector2(1 + squash, 1 - squash))
	draw_circle(Vector2(0, r * 0.08), r, Color(0, 0, 0, 0.15))  # soft drop shadow
	draw_circle(Vector2.ZERO, r * 0.92, Color("ffe7a8") if is_hovered() else Color.WHITE)
	draw_arc(Vector2.ZERO, r * 0.92, 0, TAU, 32, Icons.INK, 2.5, true)
	var font := get_theme_default_font()
	var font_size := int(r * 1.25)
	var w := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(-w / 2, font_size * 0.36), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Icons.INK)
