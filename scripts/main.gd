extends Node2D
## Shape matching game. Drag a piece onto its hole, or tap a piece and then tap a hole.

enum State { PLAY, BANNER }

const SCREEN := Vector2(720, 1280)
const CENTER := Vector2(360, 690)
const S := 58.0  # world size of a unit shape (pieces and holes share it, so fits are exact)
const DRAG_THRESHOLD := 12.0
const BASE_TIME := 12.0
const TIME_PER_HOLE := 6.0
const BANNER_TIME := 1.0

var hole_count := randi_range(2, 5)  # fixed for the whole session
var time_limit := BASE_TIME + TIME_PER_HOLE * hole_count
var time_left := 0.0
var solved := 0
var state := State.PLAY
var banner_text := ""
var banner_left := 0.0
var clock := 0.0

var piece_color := Color.WHITE
var holes: Array = []   # {id, poly, pos, filled, flash}
var pieces: Array = []  # {id, poly, home, pos, target, placed, shake}

var dragged = null
var selected = null
var press_pos := Vector2.ZERO
var grab_offset := Vector2.ZERO
var moved := false


func _ready() -> void:
	randomize()
	hole_count = randi_range(2, 5)
	time_limit = BASE_TIME + TIME_PER_HOLE * hole_count
	_new_level()


func _new_level() -> void:
	holes.clear()
	pieces.clear()
	dragged = null
	selected = null
	moved = false
	state = State.PLAY
	time_left = time_limit
	piece_color = Color.from_hsv(randf(), 0.65, 0.95)

	var names: Array = Shapes.NAMES.duplicate()
	names.shuffle()
	names = names.slice(0, hole_count)

	# Holes in the centre.
	var hole_radius := 110.0 if hole_count == 2 else 150.0
	var hole_start := 0.0 if hole_count == 2 else -PI / 2.0
	for i in hole_count:
		var a := hole_start + i * TAU / hole_count
		holes.append({
			"id": names[i], "poly": Shapes.get_shape(names[i]),
			"pos": CENTER + Vector2(cos(a), sin(a)) * hole_radius,
			"filled": false, "flash": 0.0,
		})

	# Pieces on an ellipse around the holes, in shuffled order.
	var order: Array = names.duplicate()
	order.shuffle()
	var offset := randf() * TAU
	for i in hole_count:
		var a := offset + i * TAU / hole_count + randf_range(-0.2, 0.2)
		var home := CENTER + Vector2(cos(a) * 280.0, sin(a) * 440.0)
		pieces.append({
			"id": order[i], "poly": Shapes.get_shape(order[i]),
			"home": home, "pos": home, "target": home, "placed": false, "shake": 0.0,
		})


func _process(delta: float) -> void:
	clock += delta
	if state == State.PLAY:
		time_left -= delta
		if time_left <= 0.0:
			_show_banner("Time's up!")
	else:
		banner_left -= delta
		if banner_left <= 0.0:
			_new_level()

	var k := 1.0 - exp(-18.0 * delta)
	for pc in pieces:
		pc.shake = maxf(0.0, pc.shake - delta)
		if pc == dragged and moved:
			continue
		pc.pos = pc.pos.lerp(pc.target, k)
	for h in holes:
		h.flash = maxf(0.0, h.flash - delta)
	queue_redraw()


func _show_banner(text: String) -> void:
	state = State.BANNER
	banner_text = text
	banner_left = BANNER_TIME
	dragged = null
	selected = null


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if state != State.PLAY:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = make_input_local(event).position
		if event.pressed:
			_press(p)
		else:
			_release(p)
	elif event is InputEventMouseMotion and dragged != null:
		_motion(make_input_local(event).position)


func _press(p: Vector2) -> void:
	press_pos = p
	moved = false
	dragged = _piece_at(p)
	if dragged != null:
		grab_offset = dragged.pos - p
		pieces.erase(dragged)
		pieces.append(dragged)  # draw on top


func _motion(p: Vector2) -> void:
	if not moved and p.distance_to(press_pos) > DRAG_THRESHOLD:
		moved = true
		selected = null
	if moved:
		dragged.pos = p + grab_offset


func _release(p: Vector2) -> void:
	if dragged != null and moved:
		var pc = dragged
		dragged = null
		var h = _hole_near(pc.pos)
		if h != null:
			_try_place(pc, h)
		return
	dragged = null
	_tap(p)


func _tap(p: Vector2) -> void:
	var pc = _piece_at(p)
	if pc != null:
		selected = null if pc == selected else pc
		return
	if selected != null:
		var h = _hole_near(p)
		if h != null:
			var sel = selected
			selected = null
			_try_place(sel, h)
			return
	selected = null


func _try_place(pc, h) -> void:
	if h.id == pc.id:
		pc.placed = true
		pc.target = h.pos
		h.filled = true
		selected = null
		var all_done := true
		for other in holes:
			all_done = all_done and other.filled
		if all_done:
			solved += 1
			_show_banner("Nice!")
	else:
		h.flash = 0.4
		pc.shake = 0.35
		pc.target = pc.home


func _piece_at(p: Vector2):
	for i in range(pieces.size() - 1, -1, -1):
		var pc = pieces[i]
		if pc.placed:
			continue
		var local: Vector2 = (p - pc.pos) / S
		if Geometry2D.is_point_in_polygon(local, pc.poly) or local.length() < 0.5:
			return pc
	return null


func _hole_near(p: Vector2):
	var best = null
	var best_d := S
	for h in holes:
		if h.filled:
			continue
		var d: float = h.pos.distance_to(p)
		if d < best_d:
			best_d = d
			best = h
	return best


# ---------------------------------------------------------------- drawing

func _world_poly(poly: PackedVector2Array, pos: Vector2, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		out.append(pos + v * scale)
	return out


func _outline(pts: PackedVector2Array, color: Color, width: float) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, color, width, true)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.11, 0.12, 0.17))
	draw_circle(CENTER, 230.0, Color(0.15, 0.16, 0.22))

	for h in holes:
		var pts := _world_poly(h.poly, h.pos, S)
		draw_colored_polygon(pts, Color(0.05, 0.05, 0.08))
		var edge := Color(0.4, 0.42, 0.52)
		if h.flash > 0.0:
			edge = Color(1.0, 0.3, 0.3)
		_outline(pts, edge, 4.0)

	for pc in pieces:
		var pos: Vector2 = pc.pos
		if pc.shake > 0.0:
			pos.x += sin(clock * 70.0) * 10.0 * (pc.shake / 0.35)
		var is_sel: bool = pc == selected
		var is_drag: bool = pc == dragged and moved
		var scale := S * (1.08 if (is_sel or is_drag) else 1.0)
		var pts := _world_poly(pc.poly, pos, scale)
		draw_colored_polygon(pts, piece_color)
		if pc.placed:
			_outline(pts, piece_color.lightened(0.25), 3.0)
		elif is_sel:
			_outline(pts, Color.WHITE, 5.0 + sin(clock * 8.0) * 1.5)
		else:
			_outline(pts, piece_color.darkened(0.3), 3.0)

	_draw_hud()


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var frac := clampf(time_left / time_limit, 0.0, 1.0)
	var bar := Rect2(60, 90, 600, 18)
	draw_rect(bar, Color(0.2, 0.21, 0.28))
	var bar_color := Color(0.4, 0.85, 0.5).lerp(Color(0.95, 0.3, 0.3), 1.0 - minf(frac * 2.0, 1.0))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), bar_color)
	draw_string(font, Vector2(0, 60), "%d s" % ceili(maxf(time_left, 0.0)),
			HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, 40, Color.WHITE)
	draw_string(font, Vector2(0, 1240), "Solved: %d" % solved,
			HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, 32, Color(0.7, 0.72, 0.8))
	if state == State.BANNER:
		draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0, 0, 0, 0.55))
		draw_string(font, Vector2(0, CENTER.y + 20), banner_text,
				HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, 72, Color.WHITE)
