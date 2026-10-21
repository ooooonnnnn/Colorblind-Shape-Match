class_name ToySwitch
extends Button
## An on/off switch in the game's style: a chunky card with its caption and a
## round knob that slides across a track, green when on.

const ON := Color("4caf7a")
const OFF := Color(0.231373, 0.184314, 0.290196, 0.22)  # Icons.INK, faded
const TRACK := Vector2(52, 28)  # px
const GAP := 18.0  # px between the caption and the track

var _knob := 0.0:  # 0 off, 1 on, sliding between
	set(v):
		_knob = v
		queue_redraw()


func _init(caption: String, on: bool) -> void:
	text = caption
	toggle_mode = true
	button_pressed = on
	_knob = 1.0 if on else 0.0
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_size_override("font_size", 20)
	toggled.connect(func(now_on):
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(self, "_knob", 1.0 if now_on else 0.0, 0.18)
	)


func _ready() -> void:
	# Room on the right for the track, and the same white card on or off: the
	# knob says which.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var from := {"pressed": "normal", "hover_pressed": "hover"}.get(state, state) as String
		var style := (get_theme_stylebox(from) as StyleBoxFlat).duplicate()
		style.content_margin_right += TRACK.x + GAP
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		add_theme_stylebox_override(state, style)


## Turns it on or off from code without the toggled signal.
func set_on(on: bool) -> void:
	set_pressed_no_signal(on)
	_knob = 1.0 if on else 0.0


func _draw() -> void:
	var ink := Color(Icons.INK, 0.4 if disabled else 1.0)
	var track := Rect2(Vector2(size.x - TRACK.x - 14, (size.y - TRACK.y) / 2), TRACK)
	var pill := StyleBoxFlat.new()
	pill.set_corner_radius_all(99)
	pill.bg_color = OFF.lerp(ON, clampf(_knob, 0, 1))
	pill.set_border_width_all(2)
	pill.border_color = ink
	draw_style_box(pill, track)
	var r := TRACK.y / 2 - 4
	var center := Vector2(lerpf(track.position.x + 4 + r, track.end.x - 4 - r, _knob), track.get_center().y)
	draw_circle(center, r, Color.WHITE)
	draw_arc(center, r, 0, TAU, 24, ink, 2, true)
