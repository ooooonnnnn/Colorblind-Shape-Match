extends Control

const Dots := preload("res://scripts/dots.gd")
const ColorGroups := preload("res://scripts/color_groups.gd")
const Stats := preload("res://scripts/stats.gd")
const MIN_LOOK_MS := 10000   # how long a level must have been up before leaving it counts its pieces as missed
const DRAG_THRESHOLD := 6.0  # px of movement before a press counts as a drag
const SPACING := 16.0        # px of clear space between bounding circles at the start of a level
const TRAY_PADDING := 24.0   # px between the holes' bounding circles and the tray edge
const CHIME_STEPS := [0, 2, 4, 5, 7, 9, 11]  # major scale, in semitones

@onready var content: VBoxContainer = $Content
@onready var home: ToyButton = $Content/Header/Home
@onready var pips: ProgressPips = $Content/Header/Pips
@onready var score_star: StarBadge = $Content/Header/ScoreStar
@onready var score_label: Label = $Content/Header/ScoreValue
@onready var timer_bar: TimerBar = $Content/TimerBar
@onready var board: Panel = $Content/Board
@onready var tray: Panel = $Content/Board/Tray
@onready var uh_uh: AudioStreamPlayer = $UhUh
@onready var chime: AudioStreamPlayer = $Chime
@onready var pop: AudioStreamPlayer = $Pop
@onready var boing: AudioStreamPlayer = $Boing
@onready var whoosh: AudioStreamPlayer = $Whoosh
@onready var fanfare: AudioStreamPlayer = $Fanfare
@onready var finale: AudioStreamPlayer = $Finale
@onready var dots: Dots = $Dots
@onready var effects: Effects = $Effects

var levels: Array[Dictionary] = []  # see LevelConfig
var color_groups := {}  # see ColorGroups.load_settings
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
var _chime_step := 0  # rises with each placement, resets each level
# Stats (see Stats): pieces finished this level, waiting to be saved, and the
# moment the player was last free to look for a piece, so a piece's spot time
# never includes time spent handling another one.
var _session := int(Time.get_unix_time_from_system())
var _level_group := ""  # the color group id, or Stats.BASELINE without the filter
var _level_started_ms := 0
var _search_from_ms := 0
var _finished: Array[Dictionary] = []


func _ready() -> void:
	levels = LevelConfig.load_levels()
	color_groups = ColorGroups.load_settings()
	ShapeView.load_size()
	dots.colors_changed.connect(_recolor_pieces)
	home.activated.connect(_go_home)
	resized.connect(_layout)
	_layout()
	new_level()


func _layout() -> void:
	# 16 px top margin, 72 px header, 18 px timer and 12 px gaps above the board,
	# 24 px margins at the sides and below, which leaves room for its frame.
	board_size = Vector2(maxf(size.x - 48, 200), maxf(size.y - 154, 200))
	board.custom_minimum_size = board_size
	content.position = Vector2(24, 16)
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
	effects.clear_star()
	var group := ColorGroups.find(color_groups, ColorGroups.pick(color_groups))
	dots.show_group(group)
	_level_group = group.id if config.filter else Stats.BASELINE
	hole_count = config.holes
	pieces_per_shape = config.shapes
	level_time = config.duration
	dots.visible = config.filter
	dots.process_mode = Node.PROCESS_MODE_INHERIT if config.filter else Node.PROCESS_MODE_DISABLED
	timer_bar.modulate.a = 1.0 if level_time > 0 else 0.0  # hidden, but keeps its place in the layout
	pips.total = hole_count * pieces_per_shape

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

	var colors := ColorGroups.piece_colors(group.colors.size(), hole_count, piece_radii.size())
	for i in piece_radii.size():
		var p := ShapeView.new()
		p.setup(shapes[i % hole_count], true)
		p.set_meta("color", colors[i])
		p.set_meta("spot_ms", -1)
		p.set_meta("wrong", 0)
		p.fill = dots.figure_color(colors[i])
		p.target_hole = holes[i % hole_count]
		p.home = piece_spots[i] / board_size
		p.norm_pos = p.home
		board.add_child(p)
		p.gui_input.connect(_on_piece_input.bind(p))
		pieces.append(p)

	deadline_ms = Time.get_ticks_msec() + int(level_time * 1000)
	transitioning = false
	_level_started_ms = Time.get_ticks_msec()
	_search_from_ms = _level_started_ms


func _recolor_pieces() -> void:
	for p in pieces:
		p.fill = dots.figure_color(p.get_meta("color"))


func _clear_board() -> void:
	for node in holes + pieces:
		node.queue_free()
	holes.clear()
	pieces.clear()
	selected = null
	drag = {}


## Leaves the board empty under a big star and confetti; no further levels
## start. The home button pulses to show the way back.
func end_game() -> void:
	transitioning = true
	var rect := board.get_global_rect()
	effects.cheer(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.5, 0.0, true)
	effects.confetti(rect, 120)
	finale.play()
	home.start_pulse()


## Cleared levels get a cheering star, confetti and a fanfare. When time runs
## out there is no failure message: the pieces just float away with a whoosh.
func end_level(cleared: bool) -> void:
	transitioning = true
	deselect()
	_finish_level()
	var delay := 0.8
	if cleared:
		delay = 1.0
		var rect := board.get_global_rect()
		effects.cheer(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.4, 0.4)
		effects.confetti(rect)
		fanfare.play()
	else:
		whoosh.play()
		for p in pieces:
			var t := p.create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
			t.tween_property(p, "modulate:a", 0.0, 0.5)
			t.tween_property(p, "visual_scale", 0.4, 0.5)
	var id := _level_id
	get_tree().create_timer(delay).timeout.connect(func():
		if id == _level_id:
			new_level()
	)


func _go_home() -> void:
	if not transitioning:
		# Pieces left on a board that was barely up say nothing about seeing them.
		_finish_level(Time.get_ticks_msec() - _level_started_ms >= MIN_LOOK_MS)
	# A moment for the button's squish and pop before the scene goes.
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file("res://menu.tscn")


func _process(_delta: float) -> void:
	if level_time <= 0:
		timer_bar.ratio = 1.0
		timer_bar.low = false
		return
	var remaining := maxi(0, deadline_ms - Time.get_ticks_msec())
	timer_bar.ratio = remaining / (level_time * 1000)
	timer_bar.low = remaining < 5000
	if remaining == 0 and not transitioning:
		end_level(false)


# ---------- Matching ----------

func place(p: ShapeView) -> void:
	p.placed = true
	p.release_focus()
	p.focus_mode = Control.FOCUS_NONE
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.z_index = 1
	p.vanish_into(p.target_hole.norm_pos)
	play_chime()
	pips.add_one()
	# The hole gulps the piece down with a sparkle as it arrives.
	var hole := p.target_hole
	get_tree().create_timer(0.2).timeout.connect(func():
		if is_instance_valid(hole):
			hole.squish(0.25)
			var rect := hole.get_global_rect()
			effects.burst(rect.get_center(), rect.size.x * 0.5)
	)
	_finished.append(_record(p, "found"))
	_resume_search()
	pieces.erase(p)
	if pieces.is_empty():
		score += 1
		score_label.text = str(score)
		score_star.bounce()
		end_level(true)


func play_chime() -> void:
	var n := CHIME_STEPS.size()
	var semitones: int = CHIME_STEPS[_chime_step % n] + 12 * floori(_chime_step / float(n))
	chime.pitch_scale = pow(2.0, semitones / 12.0)
	chime.play()
	_chime_step += 1


func reject(p: ShapeView, _hole: ShapeView) -> void:
	p.set_meta("wrong", p.get_meta("wrong") + 1)
	_resume_search()
	p.nod()
	p.target_hole.bulge()
	uh_uh.play()
	boing.play()  # the soft spring back home
	p.move_to(p.home)


func select(p: ShapeView) -> void:
	deselect()
	selected = p
	p.selected = true
	effects.glow(p)
	p.scale_to(1.12)


func deselect() -> void:
	if selected:
		selected.selected = false
		selected.scale_to(1.0)
		effects.glow(null)
	selected = null


# ---------- Stats ----------

## The first time a piece is touched, the time since the player was last free
## to look is its spot time. Touching it also ends the search, so switching to
## another piece only counts the time since this one was found.
func _spot(p: ShapeView) -> void:
	var now := Time.get_ticks_msec()
	if p.get_meta("spot_ms") < 0:
		p.set_meta("spot_ms", now - _search_from_ms)
	_search_from_ms = now


## The player has let go of a piece (placed, sent back or put down) and is free
## to look for the next one.
func _resume_search() -> void:
	_search_from_ms = Time.get_ticks_msec()


func _record(p: ShapeView, outcome: String) -> Dictionary:
	return {
		"session": _session,
		"level": level_num,
		"group": _level_group,
		"filter": _level_group != Stats.BASELINE,
		"shape": p.shape_name,
		"color": p.fill.to_html(false),
		"outcome": outcome,
		"spot_ms": p.get_meta("spot_ms"),
		"wrong": p.get_meta("wrong"),
	}


## Saves the level's records, first recording the pieces still on the board as
## seen (touched) or missed if count_left.
func _finish_level(count_left := true) -> void:
	if count_left:
		for p in pieces:
			_finished.append(_record(p, "seen" if p.get_meta("spot_ms") >= 0 else "missed"))
	Stats.add(_finished)
	_finished.clear()


# ---------- Tap-tap ----------

func tap_piece(p: ShapeView) -> void:
	if p.placed or transitioning:
		return
	if selected == p:
		deselect()
		_resume_search()
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
		if not selected and not transitioning:
			_press_feedback(hole)  # a placement or rejection brings its own feedback
		tap_hole(hole)


## Squish and pop the moment something is pressed, before the press resolves
## into a tap or a drag, so it never seems unresponsive.
func _press_feedback(view: ShapeView) -> void:
	view.squish()
	pop.pitch_scale = randf_range(0.9, 1.15)
	pop.play()


# ---------- Drag and drop ----------

func _on_piece_input(event: InputEvent, p: ShapeView) -> void:
	if event.is_action_pressed("ui_accept"):
		p.accept_event()
		if not (p.placed or transitioning):
			_press_feedback(p)
			_spot(p)
		tap_piece(p)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		p.accept_event()
		if event.pressed:
			if not (p.placed or transitioning or drag):
				_press_feedback(p)
				_spot(p)
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
			effects.glow(p)
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
	effects.glow(null)
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
		_resume_search()
	elif target == p.target_hole:
		place(p)
	else:
		reject(p, target)
