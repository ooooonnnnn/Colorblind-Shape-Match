extends Control

const Dots := preload("res://scripts/dots.gd")
const DRAG_THRESHOLD := 6.0  # px of movement before a press counts as a drag
const SPACING := 16.0        # px of clear space between bounding circles at the start of a level
const TRAY_PADDING := 24.0   # px between the holes' bounding circles and the tray edge
const CHIME_STEPS := [0, 2, 4, 5, 7, 9, 11]  # major scale, in semitones

@onready var content: VBoxContainer = $Content
@onready var level_label: Label = $Content/Header/LevelValue
@onready var score_label: Label = $Content/Header/ScoreValue
@onready var timer_bar: TimerBar = $Content/TimerBar
@onready var timer_text: Label = $Content/TimerText
@onready var board: Panel = $Content/Board
@onready var tray: Panel = $Content/Board/Tray
@onready var toast: PanelContainer = $Content/Board/Toast
@onready var toast_label: Label = $Content/Board/Toast/Label
@onready var uh_uh: AudioStreamPlayer = $UhUh
@onready var chime: AudioStreamPlayer = $Chime
@onready var dots: Dots = $Dots

var levels: Array[Dictionary] = []  # see LevelConfig
var hole_count := 0
var pieces_per_shape := 0  # copies of each shape to sort into its hole
var level_time := 0.0      # seconds; <= 0 means no time limit
var level_num := 0
var score := 0
var holes: Array[ShapeView] = []
var pieces: Array[ShapeView] = []
var selected: ShapeView
var drag := {}  # empty when nothing is being dragged
var deadline_ms := 0
var transitioning := false
var board_size := Vector2.ZERO  # the board's laid-out size, known before containers sort
var _level_id := 0  # lets a pending level change notice it was superseded
var _toast_tween: Tween
var _chime_step := 0  # rises with each placement, resets each level


func _ready() -> void:
	levels = LevelConfig.load_levels()
	ShapeView.load_size()
	dots.colors_changed.connect(_recolor_pieces)
	resized.connect(_layout)
	_layout()
	new_level()


func _layout() -> void:
	# 95 px of header and timer above the board, 16 px margin below.
	board_size = Vector2(maxf(size.x - 32, 200), maxf(size.y - 111, 200))
	board.custom_minimum_size = board_size
	content.position = Vector2(16, 12)
	content.size = Vector2(board_size.x, 0)


# ---------- Level config ----------

## The entry for level n (1-based), or {} once the list has run out. An entry
## with repetitions <= 0 repeats forever.
func _level_config(n: int) -> Dictionary:
	for entry in levels:
		if entry.repetitions <= 0 or n <= entry.repetitions:
			return entry
		n -= entry.repetitions
	return {}


# ---------- Layout ----------

## Pixel centers for the holes, in a row centered on the board. The gap between
## neighbours' bounding circles is wider than the widest piece, so no piece can
## touch two holes at once.
func _hole_row(radii: Array[float], widest_piece: float) -> Array[Vector2]:
	var xs: Array[float] = [0.0]
	for i in range(1, radii.size()):
		xs.append(xs[i - 1] + radii[i - 1] + radii[i] + widest_piece + SPACING)
	var row_center := (xs[-1] + radii[-1] - radii[0]) / 2
	var spots: Array[Vector2] = []
	for x in xs:
		spots.append(board_size / 2 + Vector2(x - row_center, 0))
	return spots


## The smallest rectangle around the given circles.
func _bounds(centers: Array[Vector2], radii: Array[float]) -> Rect2:
	var rect := Rect2(centers[0], Vector2.ZERO)
	for i in centers.size():
		rect = rect.merge(Rect2(centers[i] - Vector2.ONE * radii[i], Vector2.ONE * radii[i] * 2))
	return rect


## Random pixel centers for the pieces that keep clear of each other and of keep_out.
func _scatter_pieces(radii: Array[float], keep_out: Rect2) -> Array[Vector2]:
	for attempt in 100:
		var spots: Array[Vector2] = []
		for r in radii:
			var spot := _free_spot(spots, radii, keep_out)
			if not spot.is_finite():
				break
			spots.append(spot)
		if spots.size() == radii.size():
			return spots
	push_error("Could not fit %d pieces on the board" % radii.size())
	var fallback: Array[Vector2] = []
	fallback.resize(radii.size())
	fallback.fill(board_size / 2)
	return fallback


## A random spot for piece number spots.size(), or Vector2.INF if none was found.
func _free_spot(spots: Array[Vector2], radii: Array[float], keep_out: Rect2) -> Vector2:
	var r := radii[spots.size()]
	var blocked := keep_out.grow(r + SPACING)
	for _try in 200:
		var c := Vector2(randf_range(r, board_size.x - r), randf_range(r, board_size.y - r))
		if blocked.has_point(c):
			continue
		var free := true
		for j in spots.size():
			if c.distance_to(spots[j]) <= radii[j] + r + SPACING:
				free = false
				break
		if free:
			return c
	return Vector2.INF


## Positions the tray behind the holes, anchored so it follows board resizes.
func _place_tray(rect: Rect2) -> void:
	tray.anchor_left = rect.position.x / board_size.x
	tray.anchor_top = rect.position.y / board_size.y
	tray.anchor_right = rect.end.x / board_size.x
	tray.anchor_bottom = rect.end.y / board_size.y
	tray.offset_left = 0
	tray.offset_top = 0
	tray.offset_right = 0
	tray.offset_bottom = 0


# ---------- Level lifecycle ----------

func new_level() -> void:
	_level_id += 1
	_clear_board()
	var config := _level_config(level_num + 1)
	if config.is_empty():
		end_game()
		return
	_chime_step = 0
	level_num += 1
	level_label.text = str(level_num)
	hole_count = config.holes
	pieces_per_shape = config.shapes
	level_time = config.duration
	dots.visible = config.filter
	dots.process_mode = Node.PROCESS_MODE_INHERIT if config.filter else Node.PROCESS_MODE_DISABLED

	var shapes := Shapes.pick(hole_count)
	var side := ShapeView.side_for(board_size)
	var hole_radii: Array[float] = []
	for shape in shapes:
		hole_radii.append(Shapes.radius(shape.points) * side)
	var piece_radii: Array[float] = []
	for i in hole_count * pieces_per_shape:
		piece_radii.append(hole_radii[i % hole_count])
	var hole_spots := _hole_row(hole_radii, hole_radii.max() * 2)
	var tray_rect := _bounds(hole_spots, hole_radii).grow(TRAY_PADDING)
	_place_tray(tray_rect)
	var piece_spots := _scatter_pieces(piece_radii, tray_rect)

	for i in hole_count:
		var hole := ShapeView.new()
		hole.setup(shapes[i], false)
		hole.norm_pos = hole_spots[i] / board_size
		board.add_child(hole)
		hole.gui_input.connect(_on_hole_input.bind(hole))
		holes.append(hole)

	for i in piece_radii.size():
		var p := ShapeView.new()
		p.setup(shapes[i % hole_count], true)
		p.fill = dots.shape_color(p.shape_name)
		p.target_hole = holes[i % hole_count]
		p.home = piece_spots[i] / board_size
		p.norm_pos = p.home
		board.add_child(p)
		p.gui_input.connect(_on_piece_input.bind(p))
		pieces.append(p)

	deadline_ms = Time.get_ticks_msec() + int(level_time * 1000)
	transitioning = false


func _recolor_pieces() -> void:
	for p in pieces:
		p.fill = dots.shape_color(p.shape_name)


func _clear_board() -> void:
	for node in holes + pieces:
		node.queue_free()
	holes.clear()
	pieces.clear()
	selected = null
	drag = {}


## Leaves the board empty with the toast showing; no further levels start.
func end_game() -> void:
	transitioning = true
	toast_label.text = "Game over"
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.2)


func end_level(message: String, delay: float) -> void:
	transitioning = true
	deselect()
	show_toast(message, delay)
	var id := _level_id
	get_tree().create_timer(delay).timeout.connect(func():
		if id == _level_id:
			new_level()
	)


func show_toast(message: String, duration: float) -> void:
	toast_label.text = message
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(maxf(0, duration - 0.3))
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.2)


func _process(_delta: float) -> void:
	if level_time <= 0:
		timer_bar.ratio = 1.0
		timer_bar.low = false
		timer_text.text = "No time limit"
		return
	var remaining := maxi(0, deadline_ms - Time.get_ticks_msec())
	timer_bar.ratio = remaining / (level_time * 1000)
	timer_bar.low = remaining < 5000
	timer_text.text = "%ds" % ceili(remaining / 1000.0)
	if remaining == 0 and not transitioning:
		end_level("Time's up!", 1.2)


# ---------- Matching ----------

func place(p: ShapeView) -> void:
	p.placed = true
	p.release_focus()
	p.focus_mode = Control.FOCUS_NONE
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.z_index = 1
	p.vanish_into(p.target_hole.norm_pos)
	play_chime()
	pieces.erase(p)
	if pieces.is_empty():
		score += 1
		score_label.text = str(score)
		end_level("Level cleared!", 0.9)


func play_chime() -> void:
	var n := CHIME_STEPS.size()
	var semitones: int = CHIME_STEPS[_chime_step % n] + 12 * floori(_chime_step / float(n))
	chime.pitch_scale = pow(2.0, semitones / 12.0)
	chime.play()
	_chime_step += 1


func reject(p: ShapeView, _hole: ShapeView) -> void:
	p.nod()
	p.target_hole.bulge()
	uh_uh.play()
	p.move_to(p.home)


func select(p: ShapeView) -> void:
	deselect()
	selected = p
	p.selected = true
	p.scale_to(1.12)


func deselect() -> void:
	if selected:
		selected.selected = false
		selected.scale_to(1.0)
	selected = null


# ---------- Tap-tap ----------

func tap_piece(p: ShapeView) -> void:
	if p.placed or transitioning:
		return
	if selected == p:
		deselect()
	else:
		select(p)


func tap_hole(hole: ShapeView) -> void:
	if not selected or transitioning:
		return
	var p := selected
	deselect()
	if p.target_hole == hole:
		place(p)
	else:
		reject(p, hole)


func _on_hole_input(event: InputEvent, hole: ShapeView) -> void:
	var clicked: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	if clicked or event.is_action_pressed("ui_accept"):
		hole.accept_event()
		tap_hole(hole)


# ---------- Drag and drop ----------

func _on_piece_input(event: InputEvent, p: ShapeView) -> void:
	if event.is_action_pressed("ui_accept"):
		p.accept_event()
		tap_piece(p)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		p.accept_event()
		if event.pressed:
			if not (p.placed or transitioning or drag):
				drag = {"p": p, "start": event.global_position, "origin": p.norm_pos, "moved": false}
		elif drag and drag.p == p:
			_end_drag()
	elif event is InputEventMouseMotion and drag and drag.p == p:
		p.accept_event()
		var delta: Vector2 = event.global_position - drag.start
		if not drag.moved and delta.length() > DRAG_THRESHOLD:
			drag.moved = true
			deselect()
			p.dragging = true
			p.z_index = 3
			p.scale_to(1.08)
		if drag.moved:
			p.move_to(drag.origin + delta / board.size, false)


func _end_drag() -> void:
	var p: ShapeView = drag.p
	var moved: bool = drag.moved
	drag = {}
	if not moved:
		tap_piece(p)
		return

	p.dragging = false
	p.z_index = 2
	p.scale_to(1.0)
	if transitioning:
		p.move_to(p.home)
		return

	# A drop counts when the bounding circles touch. _hole_row keeps holes far
	# enough apart that a piece can touch at most one.
	var side := ShapeView.side_for(board.size)
	var target: ShapeView = null
	for hole in holes:
		var dist := ((hole.norm_pos - p.norm_pos) * board.size).length()
		if dist <= (hole.radius + p.radius) * side:
			target = hole
			break

	if not target:
		p.move_to(p.home)
	elif target == p.target_hole:
		place(p)
	else:
		reject(p, target)
