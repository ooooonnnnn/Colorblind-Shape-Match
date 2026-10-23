class_name CalibrationArt
extends Control
## Small pictures that show each calibration instruction, so a grown-up can
## see what to do at a glance rather than read it: a slashed moon for night
## light off, a phone held 5 cm from the screen, the browser warning with the
## buttons to tap, and so on. Drawn as shapes, like Icons, in a 200 x 140 box
## scaled to fit. tiles() lays several out with a caption under each.

const BOX := Vector2(200, 140)  # the size every picture is drawn at, then scaled
const PAPER := Color("fffaf0")
const SCREEN := Color("2c2a3a")  # a device's screen, switched off
const BODY := Color("cfd6e3")  # a device's case
const GLOW := Color("ffe9a8")
const SUN := Color("ffd166")
const NO := Color("e05a47")
const YES := Color("4caf7a")
const LINK := Color("1f5fa8")

## What to draw: one of the names in _draw's match.
var picture := "":
	set(v):
		picture = v
		queue_redraw()


func _init(what := "", size_px := Vector2(190, 133)) -> void:
	picture = what
	custom_minimum_size = size_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## A row of pictures, each above its caption, wrapping onto more rows when
## narrow. items: [picture, caption] pairs.
static func tiles(items: Array, tile := Vector2(190, 133), caption_size := 18) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 14)
	row.add_theme_constant_override("v_separation", 14)
	for item in items:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 6)
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color.WHITE
		style.set_corner_radius_all(16)
		style.set_border_width_all(2)
		style.border_color = Color(Icons.INK, 0.25)
		card.add_theme_stylebox_override("panel", style)
		card.add_child(CalibrationArt.new(item[0], tile))
		column.add_child(card)
		var caption := Label.new()
		caption.text = item[1]
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.custom_minimum_size.x = tile.x
		caption.add_theme_font_size_override("font_size", caption_size)
		column.add_child(caption)
		row.add_child(column)
	return row


func _draw() -> void:
	var scale := minf(size.x / BOX.x, size.y / BOX.y)
	draw_set_transform((size - BOX * scale) / 2, 0, Vector2.ONE * scale)
	match picture:
		"night_light":
			_moon(Vector2(100, 70), 42)
			_star(Vector2(150, 35), 8)
			_star(Vector2(45, 40), 6)
			_slash(Vector2(55, 120), Vector2(145, 20))
		"color_mode":
			_screen(Rect2(30, 18, 140, 98))
			var muted := [Color("d98c7a"), Color("8cbf8c"), Color("7f9fd1")]
			for i in 3:
				_dot(Vector2(65 + i * 35, 58), 13, muted[i])
			_text(Vector2(100, 100), "Natural", 17, Color.WHITE)
			_badge(Vector2(165, 112), true)
		"brightness":
			_sun(Vector2(70, 58), 24)
			_text(Vector2(70, 122), "AUTO", 18, Icons.INK)
			draw_line(Vector2(42, 124), Vector2(98, 112), NO, 4, true)
			_padlock(Vector2(150, 78))
		"warm_up":
			_dot(Vector2(100, 68), 48, Color.WHITE)
			for i in 12:
				var a := TAU * i / 12
				draw_line(Vector2(100, 68) + Vector2.from_angle(a) * 40, Vector2(100, 68) + Vector2.from_angle(a) * 45, Icons.INK, 2.5, true)
			draw_line(Vector2(100, 68), Vector2(100, 36), Icons.INK, 4, true)
			draw_line(Vector2(100, 68), Vector2(122, 76), Icons.INK, 4, true)
			draw_arc(Vector2(100, 68), 30, -PI / 2, -PI / 2 + TAU * 5 / 60, 12, YES, 8, true)
			_text(Vector2(100, 134), "a few minutes", 15, Icons.INK)
		"glare":
			_screen(Rect2(105, 30, 80, 100))
			_lamp(Vector2(40, 40))
			for i in 3:
				draw_line(Vector2(55, 60 + i * 12), Vector2(102, 70 + i * 18), Color(SUN, 0.9), 4, true)
			_slash(Vector2(50, 120), Vector2(110, 40))
		"hardest":
			# Squares in gray stripes: the one hardest to see is the pick.
			var field := Rect2(8, 8, 184, 86)
			_stripes(field, Color.WHITE)
			var grays := [0.62, 0.74, 0.86]
			for i in 3:
				var square := Rect2(22 + i * 58, 26, 40, 50)
				if i == 1:
					_dashed(square)
				else:
					draw_rect(square, Color(grays[i], grays[i], grays[i]))
				_badge(Vector2(square.get_center().x, 116), i == 1)
		"neutral":
			# Grays with a tint, and the plain one.
			var tints := [Color("c9a8b4"), Color("b4b4b4"), Color("a9c2a6")]
			for i in 3:
				var square := Rect2(14 + i * 62, 18, 48, 66)
				_round(square, tints[i], 8)
				_badge(Vector2(square.get_center().x, 108), i == 1)
		"same_wifi":
			_tablet(Rect2(12, 40, 92, 70))
			_phone(Rect2(146, 42, 40, 72))
			for r in [14, 26, 38]:
				draw_arc(Vector2(125, 52), r, -PI * 0.78, -PI * 0.22, 12, LINK, 5, true)
			_dot(Vector2(125, 52), 4, LINK)
			_text(Vector2(100, 132), "same Wi-Fi", 16, Icons.INK)
		"scan":
			_tablet(Rect2(10, 22, 108, 96))
			_qr(Rect2(38, 44, 52, 52))
			_phone(Rect2(150, 30, 42, 80))
			draw_colored_polygon(PackedVector2Array([Vector2(150, 60), Vector2(92, 40), Vector2(92, 100), Vector2(150, 80)]), Color(SUN, 0.35))
			_dot(Vector2(150, 70), 4, Icons.INK)
		"warning":
			_phone(Rect2(12, 8, 72, 124))
			_triangle(Vector2(48, 36))
			for y in [58, 66, 74]:
				draw_line(Vector2(24, y), Vector2(72, y), Color(Icons.INK, 0.3), 3)
			_button(Rect2(22, 88, 52, 20), "Advanced", true)
			_arrow(Vector2(90, 70), Vector2(112, 70), "")
			_phone(Rect2(116, 8, 72, 124))
			for y in [30, 38, 46, 54]:
				draw_line(Vector2(128, y), Vector2(176, y), Color(Icons.INK, 0.3), 3)
			_button(Rect2(122, 70, 60, 22), "Proceed", true)
			_finger(Vector2(166, 100))
		"allow":
			_phone(Rect2(60, 6, 80, 128))
			var dialog := Rect2(66, 40, 68, 64)
			_round(dialog, Color.WHITE, 8)
			_camera_icon(Vector2(100, 58))
			_button(Rect2(70, 80, 28, 18), "No", false)
			_button(Rect2(102, 80, 28, 18), "Allow", true)
			_finger(Vector2(124, 108))
		"hold":
			# Seen from the side: the screen, and the phone parallel to it.
			_round(Rect2(40, 10, 14, 112), SCREEN, 4)
			draw_colored_polygon(PackedVector2Array([Vector2(118, 66), Vector2(54, 40), Vector2(54, 92)]), Color(SUN, 0.4))
			_round(Rect2(118, 24, 12, 84), BODY, 4)
			_dot(Vector2(118, 66), 4, Icons.INK)
			_arrow(Vector2(54, 128), Vector2(118, 128), "5 cm")
			_text(Vector2(165, 50), "keep", 15, Icons.INK)
			_text(Vector2(165, 68), "still", 15, Icons.INK)
		"aim":
			_phone(Rect2(60, 4, 80, 132))
			_round(Rect2(66, 16, 68, 100), Color(0.5, 0.5, 0.5), 4)
			draw_rect(Rect2(86, 48, 28, 36), YES, false, 3)
			_text(Vector2(100, 132), "", 14, Icons.INK)
		"too_bright":
			_phone(Rect2(60, 4, 80, 132))
			_round(Rect2(66, 16, 68, 100), Color.WHITE, 4)
			draw_rect(Rect2(86, 48, 28, 36), NO, false, 3)
			_sun(Vector2(100, 66), 9)
		_:
			pass
	draw_set_transform(Vector2.ZERO)


# ---------- Pieces ----------

func _round(rect: Rect2, color: Color, radius := 10.0, outline := true) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(radius))
	if outline:
		style.set_border_width_all(2)
		style.border_color = Icons.INK
	draw_style_box(style, rect)


func _dot(center: Vector2, r: float, color: Color) -> void:
	draw_circle(center, r, color)
	draw_arc(center, r, 0, TAU, 32, Icons.INK, 2, true)


func _text(at: Vector2, text: String, font_size: int, color: Color) -> void:
	if text.is_empty():
		return
	var font := get_theme_default_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, at + Vector2(-width / 2, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _slash(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, Color.WHITE, 12, true)
	draw_line(from, to, NO, 7, true)


func _badge(center: Vector2, good: bool) -> void:
	draw_circle(center, 11, YES if good else NO)
	if good:
		draw_polyline(PackedVector2Array([center + Vector2(-5, 0), center + Vector2(-1, 4), center + Vector2(6, -4)]), Color.WHITE, 3, true)
	else:
		draw_line(center + Vector2(-4, -4), center + Vector2(4, 4), Color.WHITE, 3, true)
		draw_line(center + Vector2(4, -4), center + Vector2(-4, 4), Color.WHITE, 3, true)


func _screen(rect: Rect2) -> void:
	_round(rect, SCREEN, 10)


func _tablet(rect: Rect2) -> void:
	_round(rect, BODY, 12)
	_round(rect.grow(-6), SCREEN, 6, false)


func _phone(rect: Rect2) -> void:
	_round(rect, BODY, 12)
	_round(rect.grow(-5), PAPER, 6, false)


func _moon(center: Vector2, r: float) -> void:
	draw_circle(center, r, SUN)
	draw_circle(center + Vector2(r * 0.45, -r * 0.3), r * 0.8, Color.WHITE)
	draw_arc(center, r, PI * 0.15, PI * 1.62, 24, Icons.INK, 2, true)


func _star(center: Vector2, r: float) -> void:
	var points := Icons.star(r, r * 0.45)
	for i in points.size():
		points[i] += center
	draw_colored_polygon(points, SUN)


func _sun(center: Vector2, r: float) -> void:
	for i in 8:
		var a := TAU * i / 8
		draw_line(center + Vector2.from_angle(a) * r * 1.3, center + Vector2.from_angle(a) * r * 1.75, Color("f4a933"), 4, true)
	_dot(center, r, SUN)


func _padlock(at: Vector2) -> void:
	draw_arc(at + Vector2(0, -10), 13, PI, TAU, 16, Icons.INK, 5, true)
	draw_line(at + Vector2(-13, -10), at + Vector2(-13, 0), Icons.INK, 5)
	draw_line(at + Vector2(13, -10), at + Vector2(13, 0), Icons.INK, 5)
	_round(Rect2(at + Vector2(-20, -2), Vector2(40, 32)), SUN, 6)
	draw_circle(at + Vector2(0, 12), 4, Icons.INK)


func _lamp(at: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(-20, 10), at + Vector2(-8, -12), at + Vector2(8, -12), at + Vector2(20, 10)]), Color("f4a933"))
	draw_polyline(PackedVector2Array([at + Vector2(-20, 10), at + Vector2(-8, -12), at + Vector2(8, -12), at + Vector2(20, 10), at + Vector2(-20, 10)]), Icons.INK, 2, true)
	draw_circle(at + Vector2(0, 16), 7, GLOW)


func _face(center: Vector2, squinting: bool) -> void:
	_dot(center, 26, Color("f2c9a0"))
	for side in [-1, 1]:
		var eye: Vector2 = center + Vector2(side * 9, -5)
		if squinting:
			draw_line(eye + Vector2(-5, 0), eye + Vector2(5, 0), Icons.INK, 3, true)
		else:
			draw_circle(eye, 3, Icons.INK)
	draw_arc(center + Vector2(0, 6), 9, 0.3, PI - 0.3, 12, Icons.INK, 2.5, true)


func _arrow(from: Vector2, to: Vector2, label: String) -> void:
	draw_line(from, to, Icons.INK, 2.5, true)
	var along := (to - from).normalized()
	var across := Vector2(-along.y, along.x)
	for tip in [[to, along], [from, -along]]:
		draw_colored_polygon(PackedVector2Array([tip[0], tip[0] - tip[1] * 9 + across * 5, tip[0] - tip[1] * 9 - across * 5]), Icons.INK)
	if label:
		_text((from + to) / 2 + Vector2(0, -10), label, 16, Icons.INK)


func _stripes(rect: Rect2, color: Color) -> void:
	draw_rect(rect, Color.BLACK)
	var y := rect.position.y
	while y < rect.end.y:
		draw_rect(Rect2(rect.position.x, y, rect.size.x, minf(2, rect.end.y - y)), color)
		y += 4


func _dashed(rect: Rect2) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), rect.position]
	for i in 4:
		draw_dashed_line(corners[i], corners[i + 1], Color.WHITE, 1.5, 4)


func _qr(rect: Rect2) -> void:
	draw_rect(rect, Color.WHITE)
	var cell := rect.size.x / 7
	var pattern := ["1110111", "1010101", "1110011", "0001100", "1110101", "1010010", "1110111"]
	for y in 7:
		for x in 7:
			if pattern[y][x] == "1":
				draw_rect(Rect2(rect.position + Vector2(x, y) * cell, Vector2.ONE * cell), Icons.INK)


func _triangle(center: Vector2) -> void:
	var points := PackedVector2Array([center + Vector2(0, -12), center + Vector2(13, 10), center + Vector2(-13, 10)])
	draw_colored_polygon(points, NO)
	draw_line(center + Vector2(0, -4), center + Vector2(0, 3), Color.WHITE, 3)
	draw_circle(center + Vector2(0, 7), 1.6, Color.WHITE)


func _button(rect: Rect2, label: String, highlighted: bool) -> void:
	if highlighted:
		draw_rect(rect.grow(4), Color(SUN, 0.8))
	_round(rect, Color.WHITE, 5)
	_text(rect.get_center() + Vector2(0, 1), label, 11 if label.length() > 5 else 12, LINK)


func _finger(tip: Vector2) -> void:
	var hand := Color("f2c9a0")
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(6, 2), tip + Vector2(12, 22), tip + Vector2(2, 26), tip + Vector2(-6, 8)]), hand)
	draw_polyline(PackedVector2Array([tip, tip + Vector2(6, 2), tip + Vector2(12, 22), tip + Vector2(2, 26), tip + Vector2(-6, 8), tip]), Icons.INK, 2, true)


func _camera_icon(center: Vector2) -> void:
	_round(Rect2(center + Vector2(-13, -8), Vector2(26, 17)), BODY, 4)
	_dot(center + Vector2(0, 1), 5, SCREEN)
