class_name ToyButton
extends Button
## A round, chunky picture button. It reacts the moment it is pressed, with a
## squish and a pop, since toddlers press and hold rather than tap and release.
## With hold_seconds set it only fires after being held that long, with a ring
## filling up meanwhile: a gate that a reading adult gets past, but not a toddler.

signal activated

const POP := preload("res://sounds/pop.wav")

@export var picture := "play"  ## an Icons name
@export var color := Color("ffd166")
@export var icon_color := Color.WHITE
@export var hold_seconds := 0.0
@export var square := false  ## a rounded square, like a toy block, rather than a circle

var squash := 0.0:
	set(v):
		squash = v
		queue_redraw()
var pulse := 1.0:  # swell used to draw attention, see start_pulse
	set(v):
		pulse = v
		queue_redraw()

var _held := 0.0  # seconds held so far, while gated; < 0 once fired
var _holding := false
var _pop: AudioStreamPlayer  # made in _ready, so a button never shown leaves none behind
var _squash_tween: Tween
var _pulse_tween: Tween


func _ready() -> void:
	flat = true  # all drawing is in _draw
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_pop = AudioStreamPlayer.new()
	_pop.stream = POP
	add_child(_pop)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button_down.connect(_on_down)
	button_up.connect(func():
		_holding = false
		_held = 0.0
		queue_redraw()
	)


func _on_down() -> void:
	_holding = true
	_pop.pitch_scale = randf_range(0.9, 1.15)
	_pop.play()
	squish()
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(10)  # felt as well as heard
	if hold_seconds <= 0:
		activated.emit()


## Squish flat and spring back, like a soft toy being pressed.
func squish(amount := 0.16) -> void:
	if _squash_tween:
		_squash_tween.kill()
	_squash_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for s in [amount, -amount * 0.6, amount * 0.25, 0.0]:
		_squash_tween.tween_property(self, "squash", s, 0.08)


func _process(delta: float) -> void:
	if hold_seconds <= 0 or not _holding or _held < 0:
		return
	_held += delta
	queue_redraw()
	if _held >= hold_seconds:
		_held = -1.0  # fired; wait for release before counting again
		activated.emit()


## Swells softly over and over to show this is what to press next.
func start_pulse() -> void:
	if _pulse_tween:
		return
	_pulse_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(self, "pulse", 1.12, 0.5)
	_pulse_tween.tween_property(self, "pulse", 1.0, 0.5)


func _draw() -> void:
	var r := minf(size.x, size.y) / 2 * pulse
	var c := size / 2
	draw_set_transform(c, 0, Vector2(1 + squash, 1 - squash))
	if square:
		_draw_block(r)
	else:
		draw_circle(Vector2(0, r * 0.08), r, Color(0, 0, 0, 0.18))  # soft drop shadow
		draw_circle(Vector2.ZERO, r * 0.94, color)
		draw_arc(Vector2.ZERO, r * 0.94, 0, TAU, 48, Icons.INK, maxf(2.0, r * 0.07), true)
	Icons.draw(self, picture, Vector2.ZERO, r * (1.15 if square else 1.3), icon_color)
	if hold_seconds > 0 and _held > 0:
		var ring := r * 1.08
		draw_arc(Vector2.ZERO, ring, -PI / 2, -PI / 2 + TAU * minf(_held / hold_seconds, 1.0), 48, Icons.INK, r * 0.12, true)
	if has_focus():
		draw_arc(Vector2.ZERO, r * 1.1, 0, TAU, 48, Color.WHITE, 3.0, true)


## A chunky rounded square with a darker lip along its bottom, like a toy
## block seen a little from above, and a glossy band across its top.
func _draw_block(r: float) -> void:
	var box := Rect2(-r * 0.94, -r * 0.94, r * 1.88, r * 1.88)
	var block := StyleBoxFlat.new()
	block.set_corner_radius_all(int(r * 0.5))
	block.bg_color = Color(0, 0, 0, 0.18)  # soft drop shadow
	draw_style_box(block, Rect2(box.position + Vector2(0, r * 0.12), box.size))
	block.bg_color = color.darkened(0.18)  # the lip
	draw_style_box(block, Rect2(box.position + Vector2(0, r * 0.08), box.size))
	block.bg_color = color
	draw_style_box(block, box)
	var gloss := StyleBoxFlat.new()
	gloss.set_corner_radius_all(int(r * 0.35))
	gloss.bg_color = Color(1, 1, 1, 0.35)
	draw_style_box(gloss, Rect2(box.position + Vector2(r * 0.22, r * 0.14), Vector2(box.size.x - r * 0.44, r * 0.42)))
	block.draw_center = false
	block.set_border_width_all(int(maxf(2.0, r * 0.07)))
	block.border_color = Icons.INK
	draw_style_box(block, box)
