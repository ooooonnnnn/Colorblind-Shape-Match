class_name Effects
extends CanvasLayer
## Celebration effects: sparkle bursts, confetti and a big cheering star.
## Sits above the dot filter's layer, so the filter never samples what is drawn
## here and the effects cannot change which dots show a shape.

const COLORS := [Color("ffd166"), Color("ff8fab"), Color("8fd3ff"), Color("b8f2a6"), Color("cdb4ff"), Color.WHITE]
const GRAVITY := 900.0  # px/s², confetti only
const GLOW_REACH := 22.0  # how far the glow fades out past a piece's outline, in 100x100 box units
const GLOW_COLOR := Color(0.75, 0.88, 1.0)  # white with a touch of blue
const GLOW_BANDS := 8

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


## A big star that springs into view at center. Unless stay is set it shrinks
## away after hold seconds; with stay it bobs gently until clear() is called.
func cheer(center: Vector2, side: float, hold := 1.0, stay := false) -> void:
	clear_star()
	_star_node = Node2D.new()
	_star_node.position = center
	_star_node.scale = Vector2.ZERO
	_star_node.rotation = -0.4
	_star_node.draw.connect(func():
		var points := Icons.star(side / 2, side * 0.24)
		_star_node.draw_colored_polygon(points, Color("ffd166"))
		points.append(points[0])
		_star_node.draw_polyline(points, Icons.INK, side * 0.035, true)
		# Two friendly eyes and a smile, so the star reads as a happy face.
		for eye in [-1, 1]:
			_star_node.draw_circle(Vector2(eye * side * 0.08, -side * 0.02), side * 0.03, Icons.INK)
		_star_node.draw_arc(Vector2(0, side * 0.04), side * 0.07, 0.2, PI - 0.2, 16, Icons.INK, side * 0.025, true)
	)
	add_child(_star_node)
	# Untwist while it springs in; bound to the star so it dies with it.
	_star_node.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).tween_property(_star_node, "rotation", 0.0, 0.32)
	_star_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
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


## A faint bluish-white glow hugging a picked-up piece, so it is easy to keep track
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
			for loop in _glowing.outline_around(ShapeView.PIECE_OUTLINE / 2 + band * (i + 0.5)):
				_canvas.draw_polyline(loop, Color(GLOW_COLOR, 0.42 * (1.0 - f) * (1.0 - f)), band * px + 1.0, true)
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
