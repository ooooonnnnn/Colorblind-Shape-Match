class_name Effects
extends CanvasLayer
## Celebration effects: sparkle bursts, confetti and a big cheering star.
## Sits above the dot filter's layer, so the filter never samples what is drawn
## here and the effects cannot change which dots show a shape.

const COLORS := [Color("ffd166"), Color("ff8fab"), Color("8fd3ff"), Color("b8f2a6"), Color("cdb4ff"), Color.WHITE]
const GRAVITY := 900.0  # px/s², confetti only
const GLOW_REACH := 24.0  # how far the glow fades out past a piece's outline, in 100x100 box units
const GLOW_COLOR := Color(1.0, 0.93, 0.62)  # warm golden white, bright on the blue-gray board and the dots
const GLOW_STRENGTH := 0.4  # opacity right at the outline
const GLOW_BANDS := 24
const FLIGHT := 0.65  # seconds for a cheering star to fly in from its start (see cheer)
const SWING := 0.35   # how far the flight path bows out to the side, as a fraction of its length

## Each: {pos, vel, spin, angle, size, color, life, age, star, falls}
var _particles: Array[Dictionary] = []
var _canvas := Node2D.new()
var _star_node: Node2D
var _star_tween: Tween
var _glowing: ShapeView  # the picked-up piece, or null


func _ready() -> void:
	layer = 101
	add_child(_canvas)
	_canvas.draw.connect(_draw_particles)


## A quick ring of sparkles flying out from center, sized to reach about radius.
func burst(center: Vector2, radius: float) -> void:
	var count := 14
	for i in count:
		var dir := Vector2.from_angle(TAU * (i + randf_range(-0.3, 0.3)) / count)
		_particles.append({
			"pos": center, "vel": dir * radius * randf_range(5.0, 7.0),
			"spin": randf_range(-6, 6), "angle": randf() * TAU,
			"size": radius * randf_range(0.12, 0.2), "color": COLORS.pick_random(),
			"life": randf_range(0.45, 0.6), "age": 0.0, "star": i % 2 == 0, "falls": false,
		})


## Confetti popping up from the middle of rect and fluttering down across it.
func confetti(rect: Rect2, count := 70) -> void:
	var reach := rect.size * 0.5
	for i in count:
		_particles.append({
			"pos": rect.get_center(),
			"vel": Vector2(randf_range(-1, 1) * reach.x * 1.6, -randf_range(0.6, 1.0) * sqrt(2 * GRAVITY * reach.y)),
			"spin": randf_range(-8, 8), "angle": randf() * TAU,
			"size": randf_range(12, 22), "color": COLORS.pick_random(),
			"life": randf_range(2.0, 2.8), "age": 0.0, "star": randf() < 0.3, "falls": true,
		})


## A star of the given side centered on center, with a happy face if face.
static func draw_star(canvas: CanvasItem, center: Vector2, side: float, color: Color, face := true) -> void:
	var points := Icons.star(side / 2, side * 0.24)
	for i in points.size():
		points[i] += center
	canvas.draw_colored_polygon(points, color)
	points.append(points[0])
	canvas.draw_polyline(points, Icons.INK, maxf(2.0, side * 0.035), true)
	if not face:
		return
	# Two friendly eyes and a smile, so the star reads as a happy face.
	for eye in [-1, 1]:
		canvas.draw_circle(center + Vector2(eye * side * 0.08, -side * 0.02), side * 0.03, Icons.INK)
	canvas.draw_arc(center + Vector2(0, side * 0.04), side * 0.07, 0.2, PI - 0.2, 16, Icons.INK, side * 0.025, true)


## A big star that springs into view at center. Given from, the spot of a
## smaller star elsewhere on screen (see StarBar.star_spot), it flies from there
## instead, swinging out along a curve and spinning as it grows, and lands
## FLIGHT seconds later. Unless stay is set it shrinks away after hold seconds;
## with stay it bobs gently until clear() is called.
func cheer(center: Vector2, side: float, hold := 1.0, stay := false, from := Rect2()) -> void:
	clear_star()
	_star_node = Node2D.new()
	_star_node.position = center
	_star_node.scale = Vector2.ZERO
	_star_node.rotation = -0.4
	_star_node.draw.connect(func(): draw_star(_star_node, Vector2.ZERO, side, Color("ffd166")))
	add_child(_star_node)
	_star_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if from.has_area():
		_fly_in(from, center, side)
	else:
		# Untwist while it springs in; bound to the star so it dies with it.
		_star_node.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).tween_property(_star_node, "rotation", 0.0, 0.32)
	# Squash and stretch on the way in, then settle.
	for s in [Vector2(1.3, 0.8), Vector2(0.9, 1.15), Vector2(1.05, 0.97), Vector2.ONE]:
		_star_tween.tween_property(_star_node, "scale", s, 0.08)
	if stay:
		_star_tween.tween_callback(func():
			_star_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_star_tween.tween_property(_star_node, "position:y", center.y - side * 0.06, 0.8)
			_star_tween.tween_property(_star_node, "position:y", center.y, 0.8)
		)
	else:
		_star_tween.tween_interval(hold)
		_star_tween.tween_property(_star_node, "scale", Vector2.ZERO, 0.2).set_ease(Tween.EASE_IN)
		_star_tween.tween_callback(clear_star)


## Adds the flight from from to center to the start of _star_tween: a curve
## bowing downward, like a swing dropping and sweeping up, while the star grows
## to full size and spins a full turn, landing with the squash cheer adds after.
func _fly_in(from: Rect2, center: Vector2, side: float) -> void:
	var start := from.get_center()
	var path := center - start
	var bow := Vector2(-path.y, path.x).normalized() * path.length() * SWING
	if bow.y < 0:
		bow = -bow
	var control := (start + center) / 2 + bow
	var small := from.size.x / side
	_star_node.position = start
	_star_node.rotation = 0.0
	_star_node.scale = Vector2.ONE * small
	_star_tween.tween_method(func(t: float):
		# A quadratic Bezier from start through control's pull to center.
		_star_node.position = start.lerp(control, t).lerp(control.lerp(center, t), t)
		_star_node.rotation = -TAU * t
		_star_node.scale = Vector2.ONE * lerpf(small, 1.0, t)
	, 0.0, 1.0, FLIGHT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


## A warm golden glow hugging a picked-up piece, so it is easy to keep track
## of. It starts just outside the piece's outline, so the dots that draw the
## piece stay uncovered.
func glow(view: ShapeView) -> void:
	_glowing = view
	_canvas.queue_redraw()


func clear_star() -> void:
	if _star_tween:
		_star_tween.kill()
	if _star_node:
		_star_node.queue_free()
		_star_node = null


func _process(delta: float) -> void:
	if _glowing and not is_instance_valid(_glowing):
		_glowing = null
	if _glowing:
		_canvas.queue_redraw()  # follows the piece as it moves and scales
	if _particles.is_empty():
		return
	for p in _particles:
		p.age += delta
		if p.falls:
			p.vel.y += GRAVITY * delta
			p.vel.x *= 1.0 - 1.5 * delta  # air drag, so pieces flutter rather than fly
			p.vel.y = minf(p.vel.y, 260.0)
		else:
			p.vel *= 1.0 - 5.0 * delta  # sparkles burst out fast and slow to a stop
		p.pos += p.vel * delta
		p.angle += p.spin * delta
	_particles.assign(_particles.filter(func(p): return p.age < p.life))
	_canvas.queue_redraw()


func _draw_particles() -> void:
	if _glowing:
		var px := _glowing.size.x / 100.0 * _glowing.visual_scale  # canvas px per box unit
		var reach := GLOW_REACH * (1.0 + 0.1 * sin(Time.get_ticks_msec() / 160.0))
		var band := reach / GLOW_BANDS
		for i in GLOW_BANDS:
			var f := float(i) / GLOW_BANDS
			for loop in _glowing.outline_around(ShapeView.outline_percent / 2 + band * (i + 0.5)):
				# A bell-shaped fade, so the glow melts into the board with no edge.
				_canvas.draw_polyline(loop, Color(GLOW_COLOR, GLOW_STRENGTH * exp(-5.0 * f * f)), band * px + 0.5, true)
	for p in _particles:
		var fade := clampf((p.life - p.age) / 0.3, 0.0, 1.0)
		var color: Color = p.color
		color.a = fade
		_canvas.draw_set_transform(p.pos, p.angle, Vector2.ONE)
		if p.star:
			_canvas.draw_colored_polygon(Icons.star(p.size, p.size * 0.45), color)
		elif p.falls:
			_canvas.draw_rect(Rect2(-p.size / 2, -p.size / 4, p.size, p.size / 2), color)
		else:
			_canvas.draw_circle(Vector2.ZERO, p.size * 0.6, color)
	_canvas.draw_set_transform(Vector2.ZERO)
