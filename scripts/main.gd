extends Control

const Dots := preload("res://scripts/dots.gd")
const ColorGroups := preload("res://scripts/color_groups.gd")
const Stats := preload("res://scripts/stats.gd")
const MIN_LOOK_MS := 10000   # how long a level must have been up before leaving it counts its pieces as missed
const DRAG_THRESHOLD := 14.0  # px of movement before a press counts as a drag, so a shaky tap stays a tap
const GLIDE_RATE := 14.0     # how fast a dragged piece catches up with the finger, per second; lower trails more
const LEAN_MAX := 12.0       # degrees a dragged piece leans into its motion at most
const LEAN_SPEED := 1200.0   # px/s of sideways motion that gives the full lean
const LEAN_RATE := 10.0      # how fast the lean follows changes in motion, per second
const SPACING := 16.0        # px of clear space between bounding circles at the start of a level
const TRAY_PADDING := 24.0   # px between the holes' bounding circles and the tray edge
const TRAY_INSET := 16.0     # px between the tray and the bottom of the board
const EDGE_GROWTH := 1.2     # pieces swell up to this when pressed, squished or picked up
const EDGE_GAP := 16.0       # px of full-size dots kept between a piece and the board's edge
const CHIME_STEPS := [0, 2, 4, 5, 7, 9, 11]  # major scale, in semitones
## The tutorial level played first when PlaySettings.tutorial is on: one piece
## in plain sight, in a dark color everyone can see, while a TutorialHand shows
## how to move it. It has no level number and leaves no stats or score.
const TUTORIAL_LEVEL := {"duration": 0.0, "holes": 1, "shapes": 1, "repetitions": 1, "filter": false, "colors": "random", "time_bonus": false, "extra": 0, "extra_scored": true}
const TUTORIAL_COLOR := Icons.INK

@onready var content: VBoxContainer = $Content
@onready var home: ToyButton = $Content/Footer/Home
@onready var star_bar: StarBar = $Content/StarBar
@onready var timer_bar: TimerBar = $Content/Footer/TimerBar
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
var time_bonus := false    # matches and stray taps move the deadline (see LevelConfig)
var extra_scored := true   # placing an extra shape counts toward clearing the level (see LevelConfig)
var _left_to_clear := 0    # placements still needed to clear the level
var tutorial := false      # this level is TUTORIAL_LEVEL
var _tutorial_pending := false  # the tutorial is still to be cleared this game
var _hand: TutorialHand
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
var _stray_click := false  # a click no piece, hole or button has claimed yet (see _input)
# Stats (see Stats): pieces finished this level, waiting to be saved, and the
# moment the player was last free to look for a piece, so a piece's spot time
# never includes time spent handling another one.
var _session := int(Time.get_unix_time_from_system())
var _session_info := {}  # this session's details for Stats.add, filled in _ready and as levels start
var _level_group := ""  # the color group id, or Stats.BASELINE without the filter
var _level_started_ms := 0
var _search_from_ms := 0
var _finished: Array[Dictionary] = []


func _ready() -> void:
	levels = LevelConfig.load_levels()
	PlaySettings.load_settings()
	_tutorial_pending = PlaySettings.tutorial
	color_groups = ColorGroups.load_settings()
	ShapeView.load_size()
	ExtraShapes.load_settings()
	dots.colors_changed.connect(_recolor_pieces)
	_session_info = {
		"start": _session,
		"noise": dots.noise.duplicate(true),
		"size_percent": snappedf(ShapeView.side_fraction * 100, 0.01),
	}
	home.activated.connect(_go_home)
	home.gui_input.connect(_claim_click)
	resized.connect(_layout)
	_layout()
	new_level()


func _layout() -> void:
	# 16 px margins above and below, the 64 px star bar on top and the 72 px
	# footer (Home and the timer) below, 20 px gaps that leave room for the
	# board's frame, and 24 px margins at the sides.
	board_size = Vector2(maxf(size.x - 48, 200), maxf(size.y - 208, 200))
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

## Pixel centers for the holes, in a row centered across the board at height y. The gap between
## neighbours' bounding circles is wider than the widest piece, so no piece can
## touch two holes at once.
func _hole_row(radii: Array[float], widest_piece: float, y: float) -> Array[Vector2]:
	var xs: Array[float] = [0.0]
	for i in range(1, radii.size()):
		xs.append(xs[i - 1] + radii[i - 1] + radii[i] + widest_piece + SPACING)
	var row_center := (xs[-1] + radii[-1] - radii[0]) / 2
	var spots: Array[Vector2] = []
	for x in xs:
		spots.append(Vector2(board_size.x / 2 + x - row_center, y))
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
	# Room for the piece at its biggest, so it never pokes past the dots.
	var edge := r * EDGE_GROWTH + EDGE_GAP
	for _try in 200:
		var c := Vector2(randf_range(edge, board_size.x - edge), randf_range(edge, board_size.y - edge))
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
	tutorial = _tutorial_pending
	var config := TUTORIAL_LEVEL if tutorial else _level_config(level_num + 1)
	if config.is_empty():
		end_game()
		return
	_chime_step = 0
	if not tutorial:
		level_num += 1
	effects.clear_star()
	var group := ColorGroups.find(color_groups, ColorGroups.pick(color_groups, config.colors))
	# Extra shapes join the level's own pieces on the board, in colors its
	# group's type sees as well as anyone (see ExtraShapes). When they count,
	# every piece must be placed; when not, only the level's own pieces.
	var own: int = config.holes * config.shapes
	var extra_colors: Array[Color] = []
	if config.extra > 0:
		extra_colors = ColorGroups.extra_colors(group, ExtraShapes.difference)
	var extra_count: int = config.extra if not extra_colors.is_empty() else 0
	var total := own + extra_count
	extra_scored = config.extra_scored
	_left_to_clear = total if extra_scored else own
	dots.show_group(group, PackedColorArray(extra_colors))
	_level_group = group.id if config.filter else Stats.BASELINE
	hole_count = config.holes
	pieces_per_shape = config.shapes
	level_time = config.duration
	time_bonus = config.time_bonus
	dots.visible = config.filter
	dots.process_mode = Node.PROCESS_MODE_INHERIT if config.filter else Node.PROCESS_MODE_DISABLED
	timer_bar.modulate.a = 1.0 if level_time > 0 else 0.0  # hidden, but keeps its place in the layout
	star_bar.total = _left_to_clear

	var shapes := Shapes.pick(hole_count)
	var side := ShapeView.side_for(board_size)
	var hole_radii: Array[float] = []
	for shape in shapes:
		hole_radii.append(Shapes.radius(shape.points) * side)
	# A piece's outline is centered on its edge, so half of it reaches past the
	# shape; keeping that inside the board stops it showing beyond the dot filter.
	var outline_reach := side * ShapeView.outline_percent / 200
	var piece_radii: Array[float] = []
	for i in total:
		piece_radii.append(hole_radii[i % hole_count] + outline_reach)
	# Holes are drawn as big as a piece's outer edge, so the tray leaves room for that.
	var tray_margin := outline_reach + TRAY_PADDING
	var hole_y: float = board_size.y - TRAY_INSET - tray_margin - hole_radii.max()
	var hole_spots := _hole_row(hole_radii, hole_radii.max() * 2, hole_y)
	var tray_rect := _bounds(hole_spots, hole_radii).grow(tray_margin)
	_place_tray(tray_rect)
	# The tray sits along the bottom, and pieces only start above it, not beside it.
	var below_tray := Rect2(0, tray_rect.position.y, board_size.x, board_size.y - tray_rect.position.y)
	var piece_spots := _scatter_pieces(piece_radii, below_tray)

	for i in hole_count:
		var hole := ShapeView.new()
		hole.setup(shapes[i], false)
		hole.norm_pos = hole_spots[i] / board_size
		board.add_child(hole)
		hole.gui_input.connect(_on_hole_input.bind(hole))
		holes.append(hole)

	var colors := ColorGroups.piece_colors(group.colors.size(), hole_count, own)
	for i in piece_radii.size():
		var p := ShapeView.new()
		p.setup(shapes[i % hole_count], true)
		p.set_meta("spot_ms", -1)
		p.set_meta("wrong", 0)
		p.set_meta("touched_ms", -1)
		if i < own:
			p.set_meta("color", colors[i])
			p.fill = TUTORIAL_COLOR if tutorial else dots.figure_color(colors[i])
		else:
			p.set_meta("extra", true)
			p.fill = extra_colors[(i - own) % extra_colors.size()]
		p.target_hole = holes[i % hole_count]
		p.home = piece_spots[i] / board_size
		p.norm_pos = p.home
		board.add_child(p)
		p.gui_input.connect(_on_piece_input.bind(p))
		pieces.append(p)

	# new_level runs from a timer, after this frame's _process, so the filter
	# would otherwise show the last level's circles for a frame, with the old
	# tray's opening uncovering pieces.
	if config.filter:
		dots.refresh()
	if tutorial:
		_hand = TutorialHand.new()
		board.add_child(_hand)
		_hand.play(shapes[0], TUTORIAL_COLOR, pieces[0].home, holes[0].norm_pos, PlaySettings.drag)
	deadline_ms = Time.get_ticks_msec() + int(level_time * 1000)
	transitioning = false
	_level_started_ms = Time.get_ticks_msec()
	_search_from_ms = _level_started_ms


func _stop_hand() -> void:
	if _hand:
		_hand.queue_free()
		_hand = null


func _recolor_pieces() -> void:
	if tutorial:
		return
	for p in pieces:
		if p.has_meta("extra"):
			continue
		p.fill = dots.figure_color(p.get_meta("color"))


func _clear_board() -> void:
	for node in holes + pieces:
		node.queue_free()
	holes.clear()
	pieces.clear()
	selected = null
	drag = {}
	_stop_hand()


## Leaves the board empty under a big star and confetti; no further levels
## start. The home button pulses to show the way back.
func end_game() -> void:
	transitioning = true
	var rect := board.get_global_rect()
	effects.cheer(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.5, 0.0, true)
	effects.confetti(rect, 120)
	finale.play()
	home.start_pulse()


## Cleared levels get a cheering star, confetti and a fanfare (see _cheer).
## When time runs out there is no failure message: the pieces just float away
## with a whoosh.
func end_level(cleared: bool) -> void:
	transitioning = true
	deselect()
	if cleared:
		# Extra shapes left over float off unrecorded, as the level never needed
		# them. Any of the group's own pieces left (extras took their place)
		# are recorded as usual.
		var spare: Array[ShapeView] = []
		for p in pieces:
			if p.has_meta("extra"):
				spare.append(p)
		for p in spare:
			pieces.erase(p)
		_float_away(spare, true)
	_finish_level()
	_stop_hand()
	if tutorial:
		_tutorial_pending = false
	var delay := 0.8
	if cleared:
		# The stars and meter filling, the star's flight, its landing and a moment to enjoy it.
		delay = Effects.STREAM_ARRIVE + StarBar.FILL_TIME + Effects.FLIGHT + 1.1
		_cheer()
	else:
		whoosh.play()
	_float_away(pieces)  # anything left, as a cleared level may not need every piece
	var id := _level_id
	get_tree().create_timer(delay).timeout.connect(func():
		if id == _level_id:
			new_level()
	)


## Once the stars have reached the meter and filled it, its star flies off with a whoosh, swinging into
## the middle of the board as it grows; confetti and the fanfare greet it there.
## Timers call methods, not lambdas, so leaving for the menu mid-cheer drops them.
func _cheer() -> void:
	get_tree().create_timer(Effects.STREAM_ARRIVE + StarBar.FILL_TIME).timeout.connect(_launch_star.bind(_level_id))


func _launch_star(id: int) -> void:
	if id != _level_id:
		return
	var rect := board.get_global_rect()
	effects.cheer(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.4, 0.5, false, star_bar.star_spot())
	star_bar.take_star()
	whoosh.play()
	get_tree().create_timer(Effects.FLIGHT).timeout.connect(_star_landed.bind(id))


func _star_landed(id: int) -> void:
	if id != _level_id:
		return
	effects.confetti(board.get_global_rect())
	fanfare.play()


## Fades and shrinks views away, then frees them if free, for views no longer
## in pieces, which _clear_board would otherwise free.
func _float_away(views: Array[ShapeView], free := false) -> void:
	for p in views:
		var t := p.create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
		t.tween_property(p, "modulate:a", 0.0, 0.5)
		t.tween_property(p, "visual_scale", 0.4, 0.5)
		if free:
			t.chain().tween_callback(p.queue_free)


func _go_home() -> void:
	if not transitioning:
		# Pieces left on a board that was barely up say nothing about seeing them.
		_finish_level(Time.get_ticks_msec() - _level_started_ms >= MIN_LOOK_MS)
	# A moment for the button's squish and pop before the scene goes.
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file("res://menu.tscn")


func _process(delta: float) -> void:
	if _hand:
		_hand.visible = not (drag and drag.moved)  # out of the way while the player drags
	# A dragged piece glides after the finger instead of sticking to it.
	# It also leans into its motion, like something carried, tipping toward the
	# side it moves to.
	if drag and drag.moved:
		var p: ShapeView = drag.p
		var was := p.norm_pos
		p.move_to(p.norm_pos.lerp(drag.target, 1.0 - exp(-GLIDE_RATE * delta)), false)
		if delta > 0:
			var sideways := (p.norm_pos.x - was.x) * board.size.x / delta
			var lean := deg_to_rad(LEAN_MAX) * clampf(sideways / LEAN_SPEED, -1.0, 1.0)
			p.tilt = lerpf(p.tilt, lean, 1.0 - exp(-LEAN_RATE * delta))
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
	if _counts(p):
		_send_stars(p)
	# The hole pulses with a sparkle as the piece arrives.
	var hole := p.target_hole
	get_tree().create_timer(0.2).timeout.connect(func():
		if is_instance_valid(hole):
			hole.pulse()
			var rect := hole.get_global_rect()
			effects.burst(rect.get_center(), rect.size.x * 0.5)
	)
	_finished.append(_record(p, "found"))
	_resume_search()
	_add_time(LevelConfig.TIME_BONUS)
	pieces.erase(p)
	if _counts(p):
		_left_to_clear -= 1
	if _left_to_clear <= 0:
		if not tutorial:
			score += 1
		end_level(true)


## Stars stream from p up to the meter, which fills a step as they arrive, with
## a sparkle where they land.
func _send_stars(p: ShapeView) -> void:
	var rect := p.get_global_rect()
	var to := star_bar.next_spot()
	effects.stream_stars(rect.get_center(), to, rect.size.x * 0.5)
	star_bar.add_one(Effects.STREAM_ARRIVE)
	get_tree().create_timer(Effects.STREAM_ARRIVE).timeout.connect(effects.burst.bind(to, 14.0))


## Whether placing p counts toward clearing the level: every piece but extra
## shapes in a level whose extras do not count.
func _counts(p: ShapeView) -> bool:
	return extra_scored or not p.has_meta("extra")


func play_chime() -> void:
	var n := CHIME_STEPS.size()
	var semitones: int = CHIME_STEPS[_chime_step % n] + 12 * floori(_chime_step / float(n))
	chime.pitch_scale = pow(2.0, semitones / 12.0)
	chime.play()
	_chime_step += 1


## Moves a timed level's deadline by seconds if it has time_bonus, never past
## its full time; running out this way ends the level in _process like any other.
func _add_time(seconds: float) -> void:
	if level_time <= 0 or not time_bonus or transitioning:
		return
	var now := Time.get_ticks_msec()
	deadline_ms = mini(deadline_ms + int(seconds * 1000), now + int(level_time * 1000))


## Every click starts out stray; the piece, hole or Home button it lands on
## claims it in its own input handler, which runs before _penalize_stray.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_stray_click = true
		_penalize_stray.call_deferred()


func _penalize_stray() -> void:
	if _stray_click:
		_stray_click = false
		_add_time(-LevelConfig.TIME_PENALTY)


func _claim_click(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_stray_click = false


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
## to look is its spot time, and the time since the level started is kept for
## the export. Touching it also ends the search, so switching to another piece
## only counts the time since this one was found.
func _spot(p: ShapeView) -> void:
	var now := Time.get_ticks_msec()
	if p.get_meta("spot_ms") < 0:
		p.set_meta("spot_ms", now - _search_from_ms)
		p.set_meta("touched_ms", now - _level_started_ms)
	_search_from_ms = now


## The player has let go of a piece (placed, sent back or put down) and is free
## to look for the next one.
func _resume_search() -> void:
	_search_from_ms = Time.get_ticks_msec()


func _record(p: ShapeView, outcome: String) -> Dictionary:
	return {
		"session": _session,
		"level": level_num,
		"group": Stats.EXTRA if p.has_meta("extra") and _level_group != Stats.BASELINE else _level_group,
		"filter": _level_group != Stats.BASELINE,
		"extra": p.has_meta("extra"),
		"shape": p.shape_name,
		"color": p.fill.to_html(false),
		"outcome": outcome,
		"spot_ms": p.get_meta("spot_ms"),
		"wrong": p.get_meta("wrong"),
		"touched_ms": p.get_meta("touched_ms"),
	}


## Saves the level's records, first recording the pieces still on the board as
## seen (touched) or missed if count_left.
func _finish_level(count_left := true) -> void:
	if tutorial:
		_finished.clear()
		return
	if count_left:
		for p in pieces:
			_finished.append(_record(p, "seen" if p.get_meta("spot_ms") >= 0 else "missed"))
	_session_info.end = int(Time.get_unix_time_from_system())
	Stats.add(_finished, _session_info)
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
	_claim_click(event)
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
	_claim_click(event)
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
				# Selected the moment it is pressed, not on release, so it answers at once;
				# pressing the selected piece again lets go of it on release, or at once
				# without dragging.
				var was_selected := selected == p
				select(p)
				if PlaySettings.drag:
					drag = {"p": p, "start": event.global_position, "origin": p.norm_pos, "moved": false, "was_selected": was_selected}
				elif was_selected:
					deselect()
					_resume_search()
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
			drag.target = drag.origin + delta / board.size  # _process glides the piece there


func _end_drag() -> void:
	var p: ShapeView = drag.p
	var moved: bool = drag.moved
	# Where the finger let go, which the gliding piece may not have reached yet.
	var drop: Vector2 = drag.get("target", p.norm_pos)
	var was_selected: bool = drag.was_selected
	drag = {}
	if not moved:
		if was_selected:
			deselect()
			_resume_search()
		return

	p.dragging = false
	p.level_tilt()
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
		var dist := ((hole.norm_pos - drop) * board.size).length()
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
