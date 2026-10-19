extends Control
## Soft pastel shapes drifting around the edges of the title screen.
## A little secret: the triangle can be picked up, and dropping it on the play
## button's triangle fits it in place (see matched).

signal matched  ## the triangle was dropped on target and has fitted itself in

const COLORS := [Color("ffd6a5"), Color("ffadad"), Color("caffbf"), Color("9bf6ff"), Color("bdb2ff"), Color("fdffb6")]
## Where each shape floats, as fractions of the screen, kept clear of the middle.
const SPOTS := [Vector2(0.1, 0.18), Vector2(0.26, 0.82), Vector2(0.88, 0.2), Vector2(0.75, 0.84),
		Vector2(0.07, 0.56), Vector2(0.93, 0.55), Vector2(0.38, 0.1), Vector2(0.62, 0.92)]
const SECRET := "triangle"  # the shape that fits the play button
const POINTS_RIGHT := PI / 2  # turns the upright triangle to point like the play icon

enum {FLOATING, HELD, FLYING, DONE}

@export var target: Control  ## where the triangle fits: the play button

## Each {points, color, spot, phase, spin, name, state}; while not FLOATING a
## shape is drawn at `at` (local position) turned by `turn` and scaled by `grow`.
var _shapes: Array[Dictionary] = []
var _grab_offset := Vector2.ZERO  # from the pointer to the triangle's center while held


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # the triangle is picked up in _input
	for i in SPOTS.size():
		var shape_name: String = Shapes.NAMES[i % Shapes.NAMES.size()]
		var points := PackedVector2Array()
		for v in Shapes.make(shape_name):
			points.append(v - Shapes.CENTER)
		_shapes.append({"points": points, "color": COLORS[i % COLORS.size()], "spot": SPOTS[i],
				"phase": randf() * TAU, "spin": randf_range(-0.25, 0.25), "name": shape_name,
				"state": FLOATING, "at": Vector2.ZERO, "turn": 0.0, "grow": 1.0})


func _side() -> float:
	return minf(size.x, size.y) * 0.16


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Where shape s is drawn right now, as a transform from its 100x100 box.
func _transform_of(s: Dictionary) -> Transform2D:
	var box := Vector2.ONE * _side() / 100.0
	if s.state != FLOATING:
		return Transform2D(s.turn, box * s.grow, 0, s.at)
	var t := _now()
	var bob := Vector2(0, sin(t * 0.9 + s.phase) * _side() * 0.12)
	return Transform2D(s.phase + t * s.spin, box, 0, s.spot * size + bob)


func _secret() -> Dictionary:
	for s in _shapes:
		if s.name == SECRET:
			return s
	return {}


func _input(event: InputEvent) -> void:
	var s := _secret()
	if s.is_empty() or s.state == FLYING or s.state == DONE:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = get_global_transform().affine_inverse() * event.position
		if event.pressed and s.state == FLOATING and _hits(s, pos):
			var xf := _transform_of(s)
			s.at = xf.origin
			s.turn = xf.get_rotation()
			s.state = HELD
			_grab_offset = s.at - pos
			z_index = 10  # carried over the buttons
			get_viewport().set_input_as_handled()
		elif not event.pressed and s.state == HELD:
			get_viewport().set_input_as_handled()
			_drop(s)
	elif event is InputEventMouseMotion and s.state == HELD:
		s.at = get_global_transform().affine_inverse() * event.position + _grab_offset
		get_viewport().set_input_as_handled()


## Generous on purpose: anywhere within the shape's reach counts.
func _hits(s: Dictionary, pos: Vector2) -> bool:
	return pos.distance_to(_transform_of(s).origin) <= _side() * 0.55


## Fits into the target if dropped on it, otherwise floats back home.
func _drop(s: Dictionary) -> void:
	s.state = FLYING
	var goal := _target_center()
	if target and s.at.distance_to(goal) <= target.size.x / 2:
		_fit(s, goal)
		return
	# Back to where it floats, turning to the tilt it will have when it lands.
	var back := 0.35
	var land := _now() + back
	var home: Vector2 = s.spot * size + Vector2(0, sin(land * 0.9 + s.phase) * _side() * 0.12)
	var tilt: float = s.phase + land * s.spin
	tilt += TAU * roundf((s.turn - tilt) / TAU)  # the nearest way round
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(p: Vector2): s.at = p, s.at, home, back)
	tween.tween_method(func(a: float): s.turn = a, s.turn, tilt, back)
	tween.chain().tween_callback(func():
		s.state = FLOATING
		z_index = 0
	)


## Slides onto the play icon, turns to point the same way, then shrinks into it.
func _fit(s: Dictionary, goal: Vector2) -> void:
	var aim: float = POINTS_RIGHT + TAU * roundf((s.turn - POINTS_RIGHT) / TAU)  # the nearest way round
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(p: Vector2): s.at = p, s.at, goal, 0.3)
	tween.tween_method(func(a: float): s.turn = a, s.turn, aim, 0.3)
	tween.chain().tween_method(func(g: float): s.grow = g, 1.0, 0.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func():
		s.state = DONE
		z_index = 0
		matched.emit()
	)


func _target_center() -> Vector2:
	if not target:
		return Vector2.ZERO
	return get_global_transform().affine_inverse() * target.get_global_rect().get_center()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var secret := _secret()
	for s in _shapes:
		if s != secret and s.state != DONE:
			_draw_shape(s)
	if not secret.is_empty() and secret.state != DONE:
		_draw_shape(secret)  # last, so it is carried over the other shapes
	draw_set_transform(Vector2.ZERO)


func _draw_shape(s: Dictionary) -> void:
	draw_set_transform_matrix(_transform_of(s))
	draw_colored_polygon(s.points, s.color)
	var outline: PackedVector2Array = s.points.duplicate()
	outline.append(outline[0])
	draw_polyline(outline, Color(Icons.INK, 0.35), 4.0, true)
