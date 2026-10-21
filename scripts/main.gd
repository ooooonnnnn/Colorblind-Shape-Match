extends Control

const Dots := preload("res://scripts/dots.gd")
const ColorGroups := preload("res://scripts/color_groups.gd")
const Stats := preload("res://scripts/stats.gd")
const GroupPlate := preload("res://scripts/group_plate.gd")
const CHEER_HOLD := 0.2  # seconds a level's star stays in the middle before flying to the counter
const PAUSE_LAYER := 120
const ANY_KEY_AFTER := 1.5  # seconds into the end of a run before any press goes home, so a last tap doesn't  # above the dots (100) and effects (101), below ColorVision (128)
const PLAIN_PLATE := {"background": Color("c9ccd3"), "colors": [Color("3b2f4a")]}  # shapes in plain sight, as on the stats screen
const MIN_LOOK_MS := 10000   # how long a level must have been up before leaving it counts its pieces as missed
const DRAG_THRESHOLD := 14.0  # px of movement before a press counts as a drag, so a shaky tap stays a tap
const GLIDE_RATE := 22.0     # how fast a dragged piece catches up with the finger, per second; lower trails more
const MAGNET := 0.3          # how far a piece hovering over a hole is pulled toward its center, 0 to 1
const COMBO_MS := 2500       # placements closer together than this make a combo, sending more stars
const STARS := 20            # stars streaming to the meter for a placement
const COMBO_STARS := 8       # more stars for each placement of a combo, up to three
const LEAN_MAX := 12.0       # degrees a dragged piece leans into its motion at most
const LEAN_SPEED := 1200.0   # px/s of sideways motion that gives the full lean
const LEAN_RATE := 10.0      # how fast the lean follows changes in motion, per second
const SPACING := 16.0        # px of clear space between bounding circles at the start of a level
const TRAY_PADDING := 24.0   # px between the holes' bounding circles and the tray edge
const TRAY_INSET := 16.0     # px between the tray and the bottom of the board
const EDGE_GROWTH := 1.2     # pieces swell up to this when pressed, squished or picked up
const EDGE_GAP := 16.0       # px of full-size dots kept between a piece and the board's edge
const DOTS_FADE := 2.5       # seconds the dots take to fade in over the shapes, the first time they show
## Soft jingles for a cleared level, one picked at random each time but never
## the same twice running, so they stay pleasant over a long session.
const CHEERS: Array[AudioStream] = [preload("res://sounds/cheer_1.wav"), preload("res://sounds/cheer_2.wav"), preload("res://sounds/cheer_3.wav")]
const CHIME_STEPS := [0, 2, 4, 5, 7, 9, 11]  # major scale, in semitones
## The tutorial level played first when PlaySettings.tutorial is on: one piece
## in plain sight, in a dark color everyone can see, while a TutorialHand shows
## how to move it. It has no level number and leaves no stats, but its star
## counts toward the run's stars like any other.
const TUTORIAL_LEVEL := {"duration": 0.0, "holes": 1, "shapes": 1, "repetitions": 1, "filter": false, "colors": "random", "time_bonus": false, "extra": 0, "extra_scored": true}
const TUTORIAL_COLOR := Icons.INK

@onready var content: VBoxContainer = $Content
@onready var home: ToyButton = $Content/Header/Home
@onready var star_bar: StarBar = $Content/Header/StarBar
@onready var star_counter: StarCounter = $Content/Header/Stars
@onready var testing: PanelContainer = $Content/Header/Testing
@onready var timer_bar: TimerBar = $Content/TimerBar
@onready var board: Panel = $Content/Board
@onready var glow: Backdrop = $Content/Board/Glow
@onready var tray: Panel = $Content/Board/Tray
@onready var uh_uh: AudioStreamPlayer = $UhUh
@onready var chime: AudioStreamPlayer = $Chime
@onready var pop: AudioStreamPlayer = $Pop
@onready var boing: AudioStreamPlayer = $Boing
@onready var whoosh: AudioStreamPlayer = $Whoosh
@onready var bling: AudioStreamPlayer = $Bling
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
var endless_extra := false  # a placed extra shape is replaced by a new one (see PlaySettings)
var _found_own := false     # a piece of the level's own has been placed, which can stop new extras
var _level_shapes := []     # the level's shapes, one per hole
var _extra_colors: Array[Color] = []
var _piece_reach := 0.0     # px a piece's outline reaches past its shape
var _below_tray := Rect2()  # where pieces never start
var _left_to_clear := 0    # placements still needed to clear the level
var tutorial := false      # this level is TUTORIAL_LEVEL
var _tutorial_pending := false  # the tutorial is still to be cleared this game
var _dots_faded := false  # the dots have come on once this game, faded in or not
var _hand: TutorialHand
var level_num := 0
var score := 0  # levels cleared this run, not counting the tutorial
var _game_over := false
var _last_cheer := -1  # the jingle played last, see CHEERS
var _stars_won := 0  # stars earned this run, counting any still on their way to the counter
var _any_key_home := false  # the run is over and any press now goes home
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
var _hover: ShapeView  # the hole a dragged piece is over, open to take it in
var _combo := 0  # placements so far in a quick run, see COMBO_MS
var _last_place_ms := -COMBO_MS
var _pause_layer: CanvasLayer  # the pause screen, while paused
var _paused_at := 0  # when the game was paused, to give the time back after
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
	pop.max_polyphony = 4  # quick runs of pops and blings overlap rather than cut each other off
	bling.max_polyphony = 4
	_session_info = {
		"start": _session,
		"noise": dots.noise.duplicate(true),
		"size_percent": snappedf(ShapeView.side_fraction * 100, 0.01),
	}
	home.activated.connect(_pause)
	home.gui_input.connect(_claim_click)
	resized.connect(_layout)
	_layout()
	new_level()


func _layout() -> void:
	# 16 px margins above and below, the 76 px header (Home, the star meter and
	# what is being tested) on top and the 40 px timer below, 20 px gaps that
	# leave room for the board's frame, and 24 px margins at the sides.
	board_size = Vector2(maxf(size.x - 48, 200), maxf(size.y - 188, 200))
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


## Shrinks the level's shapes (ShapeView.fit_scale) until the row of holes,
## with its tray, fits across the board with the pieces' edge gap to spare.
## The row's gaps include fixed pixels, so it takes a few rounds to settle.
func _fit_holes(shapes: Array) -> void:
	ShapeView.fit_scale = 1.0
	var room := board_size.x - 2 * EDGE_GAP
	for _round in 4:
		var side := ShapeView.side_for(board_size)
		var radii: Array[float] = []
		for shape in shapes:
			radii.append(Shapes.radius(shape.points) * side)
		var spots := _hole_row(radii, radii.max() * 2, 0.0)
		var width := _bounds(spots, radii).grow(side * ShapeView.outline_percent / 200 + TRAY_PADDING).size.x
		if width <= room:
			return
		ShapeView.fit_scale *= room / width * 0.98


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
	_combo = 0
	if not tutorial:
		level_num += 1
	effects.clear_star()
	var group := ColorGroups.find(color_groups, ColorGroups.pick(color_groups, config.colors))
	# Extra shapes join the level's own pieces on the board, in colors its
	# group's type sees as well as anyone (see ExtraShapes). When they count,
	# every piece must be placed; when not, only the level's own pieces.
	var own: int = config.holes * config.shapes
	var extra_colors: Array[Color] = []
	# Endless extras go in every level but the tutorial, which shows one piece only.
	endless_extra = PlaySettings.endless_extra and not tutorial
	_found_own = false
	var wanted: int = 1 if endless_extra else config.extra
	if wanted > 0:
		extra_colors = ColorGroups.extra_colors(group, ExtraShapes.difference)
	var extra_count: int = wanted if not extra_colors.is_empty() else 0
	var total := own + extra_count
	# Endless extras always count, so a player who can't see the group's pieces
	# still fills the meter with them.
	extra_scored = config.extra_scored or endless_extra
	_extra_colors = extra_colors
	_left_to_clear = total if extra_scored else own
	dots.show_group(group, PackedColorArray(extra_colors))
	_level_group = group.id if config.filter else Stats.BASELINE
	hole_count = config.holes
	pieces_per_shape = config.shapes
	level_time = config.duration
	time_bonus = config.time_bonus
	dots.visible = config.filter
	# The soft sky only shows without the filter, which would read its colors.
	glow.visible = not config.filter
	_show_testing(group if config.filter and not tutorial else {}, tutorial)
	dots.process_mode = Node.PROCESS_MODE_INHERIT if config.filter else Node.PROCESS_MODE_DISABLED
	timer_bar.modulate.a = 1.0 if level_time > 0 else 0.0  # hidden, but keeps its place in the layout
	star_bar.total = _left_to_clear

	var shapes := Shapes.pick(hole_count)
	_fit_holes(shapes)
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
	_level_shapes = shapes
	_piece_reach = outline_reach
	_below_tray = below_tray

	for i in hole_count:
		var hole := ShapeView.new()
		hole.setup(shapes[i], false)
		hole.norm_pos = hole_spots[i] / board_size
		board.add_child(hole)
		hole.gui_input.connect(_on_hole_input.bind(hole))
		holes.append(hole)
		# The holes pop up one after another, each with a pop a little higher.
		hole.pop_in(i * 0.07)
		get_tree().create_timer(i * 0.07 + 0.05).timeout.connect(_play_pop.bind(1.0 + i * 0.12))

	var colors := ColorGroups.piece_colors(group.colors.size(), hole_count, own)
	for i in piece_radii.size():
		var fill: Color
		if i < own:
			fill = TUTORIAL_COLOR if tutorial else dots.figure_color(colors[i])
		else:
			fill = extra_colors[(i - own) % extra_colors.size()]
		var p := _add_piece(i % hole_count, fill, piece_spots[i], piece_radii[i])
		if i < own:
			p.set_meta("color", colors[i])
		else:
			p.set_meta("extra", true)
		# Under the filter they appear at once: a piece growing would make its
		# dots change color in a way anyone could see, giving it away.
		if not config.filter:
			p.pop_in(0.12 + i * 0.04)

	# new_level runs from a timer, after this frame's _process, so the filter
	# would otherwise show the last level's circles for a frame, with the old
	# tray's opening uncovering pieces.
	if config.filter:
		dots.refresh()
	# The first time the dots come on, the shapes show plainly and the dots fade
	# in over them, so the player sees what they're looking for. The clock and
	# the search times wait until the dots are fully in.
	var fade := 0.0
	if config.filter and not _dots_faded:
		_dots_faded = true
		if PlaySettings.fade_in:
			fade = DOTS_FADE
			dots.fade_in(fade)
	if tutorial:
		_hand = TutorialHand.new()
		board.add_child(_hand)
		_hand.play(shapes[0], TUTORIAL_COLOR, pieces[0].home, holes[0].norm_pos, PlaySettings.drag)
	deadline_ms = Time.get_ticks_msec() + int((level_time + fade) * 1000)
	transitioning = false
	_level_started_ms = Time.get_ticks_msec()
	_search_from_ms = _level_started_ms + int(fade * 1000)


## A piece of the level's shape number k, for its hole, filled with fill,
## starting at spot (px on the board).
func _add_piece(k: int, fill: Color, spot: Vector2, radius: float) -> ShapeView:
	var p := ShapeView.new()
	p.setup(_level_shapes[k], true)
	p.set_meta("spot_ms", -1)
	p.set_meta("wrong", 0)
	p.set_meta("touched_ms", -1)
	p.set_meta("radius", radius)  # px, to keep later pieces clear of it
	p.fill = fill
	p.target_hole = holes[k]
	p.home = spot / board_size
	p.norm_pos = p.home
	board.add_child(p)
	p.gui_input.connect(_on_piece_input.bind(p))
	pieces.append(p)
	return p


## Brings in a new extra shape, in a random one of the level's shapes and extra
## colors, at a free spot clear of the pieces on the board, if it is still
## wanted after the wait (see PlaySettings). Without the filter
## it pops in like the level's first pieces; under it, it appears at once.
func _spawn_extra(id: int) -> void:
	# The level may have ended, or a piece of its own been found, while it waited.
	if id != _level_id or transitioning or (PlaySettings.extra_stop and _found_own):
		return
	var k := randi() % hole_count
	var spots: Array[Vector2] = []
	var radii: Array[float] = []
	for p in pieces:
		spots.append(p.norm_pos * board_size)
		radii.append(p.get_meta("radius"))
	radii.append(Shapes.radius(_level_shapes[k].points) * ShapeView.side_for(board_size) + _piece_reach)
	var spot := _free_spot(spots, radii, _below_tray)
	if spot == Vector2.INF:
		return  # the board is too full for now; the level goes on without it
	var p := _add_piece(k, _extra_colors[randi() % _extra_colors.size()], spot, radii[-1])
	p.set_meta("extra", true)
	if _level_group == Stats.BASELINE:
		p.pop_in(0.0)


## The badge at the top right: a little plate in the colors being tested and
## which type of color blindness they check for, or that this level has no
## dots. It pops when it changes.
func _show_testing(group: Dictionary, practice: bool) -> void:
	for child in testing.get_children():
		child.queue_free()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.85)
	style.set_corner_radius_all(22)
	style.set_border_width_all(3)
	style.border_color = Icons.INK
	style.shadow_color = Color(Icons.INK, 0.15)
	style.shadow_offset = Vector2(0, 3)
	style.content_margin_left = 10
	style.content_margin_right = 20
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	testing.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	testing.add_child(row)
	var plate: Control = GroupPlate.new()
	plate.custom_minimum_size = Vector2(52, 52)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var colors: Dictionary = PLAIN_PLATE if group.is_empty() else {"background": group.background, "colors": group.colors}
	plate.background = colors.background
	plate.colors = colors.colors
	row.add_child(plate)
	var words := VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", -2)
	row.add_child(words)
	var caption := Label.new()
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", Color(Icons.INK, 0.75))
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 24)
	if practice:
		caption.text = "Practice"
		title.text = "Tutorial"
	elif group.is_empty():
		caption.text = "No dots"
		title.text = "Plain shapes"
	else:
		caption.text = "Checking for"
		title.text = "%s · %s" % [group.name, str(group.kind).get_slice(" (", 0).to_lower()]
	words.add_child(caption)
	words.add_child(title)
	testing.pivot_offset = testing.size / 2
	var t := testing.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(testing, "scale", Vector2.ONE, 0.3).from(Vector2.ONE * 0.8)


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
	_game_over = true
	# Pause has nothing left to pause, so its button becomes the way home.
	home.picture = "house"
	home.queue_redraw()
	var rect := board.get_global_rect()
	effects.cheer(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.5, 0.0, true)
	effects.confetti(rect, 120)
	_play_varied(finale, 0.04)
	home.start_pulse()
	# Every star earned this run pops out of the counter and bounces around
	# the screen until the player goes home.
	var spot := star_counter.star_spot()
	effects.party(spot.get_center(), _stars_won, spot.size.x * 1.6)
	for i in mini(_stars_won, Effects.PARTY_MAX):
		get_tree().create_timer(i * Effects.PARTY_EVERY).timeout.connect(_party_pop.bind(i))
	get_tree().create_timer(ANY_KEY_AFTER).timeout.connect(_offer_home)


## After the end of a run has had a moment, says that any press goes home,
## and from then on one does (see _input).
func _offer_home() -> void:
	_any_key_home = true
	var layer := CanvasLayer.new()
	layer.layer = PAUSE_LAYER
	add_child(layer)
	var label := Label.new()
	label.theme = theme
	label.text = "Press anything to go home"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 52)
	label.add_theme_color_override("font_outline_color", Color.WHITE)
	label.add_theme_constant_override("outline_size", 16)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.offset_bottom = -70
	layer.add_child(label)
	# Fades in, then breathes gently so it is noticed without nagging.
	label.modulate.a = 0.0
	var t := label.create_tween()
	t.tween_property(label, "modulate:a", 1.0, 0.4)
	t.tween_callback(func():
		var breathe := label.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		breathe.tween_property(label, "modulate:a", 0.55, 0.9)
		breathe.tween_property(label, "modulate:a", 1.0, 0.9)
	)


## Every level ends with a cheering star, confetti and a jingle (see _cheer),
## even when time runs out: then the meter fills the rest of the way at once,
## and the pieces left float away quietly. Only a cleared level adds to score,
## and pieces left are recorded as missed either way.
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
	if not cleared:
		for _step in _left_to_clear:
			star_bar.add_one()
	# The stars and meter filling, the star's flight, its landing, a moment
	# to enjoy it and its trip into the counter.
	var delay := Effects.STREAM_ARRIVE + StarBar.FILL_TIME + Effects.FLIGHT + Effects.LAND + CHEER_HOLD + Effects.STORE + 0.1
	_cheer()
	_float_away(pieces)  # anything left, as a cleared level may not need every piece
	var id := _level_id
	get_tree().create_timer(delay).timeout.connect(func():
		if id == _level_id:
			new_level()
	)


## Once the stars have reached the meter and filled it, its star flies off with a whoosh, swinging into
## the middle of the board as it grows; confetti and a jingle greet it there.
## Timers call methods, not lambdas, so leaving for the menu mid-cheer drops them.
func _cheer() -> void:
	get_tree().create_timer(Effects.STREAM_ARRIVE + StarBar.FILL_TIME).timeout.connect(_launch_star.bind(_level_id))


func _launch_star(id: int) -> void:
	if id != _level_id:
		return
	var rect := board.get_global_rect()
	_stars_won += 1
	effects.cheer(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.4, CHEER_HOLD, false, star_bar.star_spot(), star_counter.star_spot())
	get_tree().create_timer(Effects.FLIGHT + Effects.LAND + CHEER_HOLD + Effects.STORE).timeout.connect(_star_stored.bind(id))
	star_bar.take_star()
	_play_varied(whoosh, 0.1)
	get_tree().create_timer(Effects.FLIGHT).timeout.connect(_star_landed.bind(id))


## The cheering star has reached the counter: it counts up, with a sparkle and
## a bling. It counts even if the next level has just begun, as its timer can
## land a frame late on a slow device.
func _star_stored(_id: int) -> void:
	star_counter.add_one()
	var spot := star_counter.star_spot()
	effects.burst(spot.get_center(), spot.size.x * 0.5)
	bling.pitch_scale = 1.5 * randf_range(0.92, 1.08)
	bling.play()
	_buzz(25)


## One of the run's stars pops out of the counter, each a little higher.
func _party_pop(i: int) -> void:
	_play_pop(minf(1.0 + i * 0.05, 1.8))
	star_counter.bump()
	_buzz(8)


func _star_landed(id: int) -> void:
	if id != _level_id:
		return
	effects.confetti(board.get_global_rect())
	var pick := randi() % CHEERS.size()
	if pick == _last_cheer:
		pick = (pick + 1 + randi() % (CHEERS.size() - 1)) % CHEERS.size()
	_last_cheer = pick
	fanfare.stream = CHEERS[pick]
	_play_varied(fanfare, 0.03)
	_buzz(60)


## Fades and shrinks views away, then frees them if free, for views no longer
## in pieces, which _clear_board would otherwise free.
func _float_away(views: Array[ShapeView], free := false) -> void:
	for p in views:
		var t := p.create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
		t.tween_property(p, "modulate:a", 0.0, 0.35)
		t.tween_property(p, "visual_scale", 0.4, 0.35)
		if free:
			t.chain().tween_callback(p.queue_free)


func _go_home() -> void:
	get_tree().paused = false  # or the menu would start paused
	if not transitioning:
		# Pieces left on a board that was barely up say nothing about seeing them.
		_finish_level(Time.get_ticks_msec() - _level_started_ms >= MIN_LOOK_MS)
	# A moment for the button's squish and pop before the scene goes.
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file("res://menu.tscn")


# ---------- Pause ----------

## Freezes the game under a dimmed screen with two big toy buttons: play to
## carry on, the house to go home. Nothing moves meanwhile, the timer
## included, and the time away is given back to the timer and the stats.
func _pause() -> void:
	if _game_over:
		_go_home()
		return
	if _pause_layer or transitioning:
		return
	if drag:
		_end_drag()  # its release would never arrive while paused
	_paused_at = Time.get_ticks_msec()
	get_tree().paused = true
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = PAUSE_LAYER
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_layer)
	var screen := Control.new()
	screen.theme = theme
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(screen)
	var dim := ColorRect.new()
	dim.color = Color(Icons.INK, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 40)
	screen.add_child(column)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_outline_color", Color.WHITE)
	title.add_theme_constant_override("outline_size", 18)
	column.add_child(title)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 80)
	column.add_child(buttons)
	var play := ToyButton.new()
	play.picture = "play"
	play.color = Color("7bd88f")
	play.custom_minimum_size = Vector2(200, 200)
	play.activated.connect(_resume)
	buttons.add_child(play)
	var house := ToyButton.new()
	house.picture = "house"
	house.color = home.color
	house.square = true
	house.custom_minimum_size = Vector2(170, 170)
	house.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	house.activated.connect(_go_home)
	buttons.add_child(house)
	# Spring in once laid out.
	screen.modulate.a = 0.0
	await get_tree().process_frame
	column.pivot_offset = column.size / 2
	var t := screen.create_tween().set_parallel()
	t.tween_property(screen, "modulate:a", 1.0, 0.15)
	t.tween_property(column, "scale", Vector2.ONE, 0.3).from(Vector2.ONE * 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _resume() -> void:
	if not _pause_layer:
		return
	var away := Time.get_ticks_msec() - _paused_at
	deadline_ms += away
	_level_started_ms += away
	_search_from_ms += away
	_last_place_ms += away
	var layer := _pause_layer
	_pause_layer = null
	get_tree().paused = false
	var screen: Control = layer.get_child(0)
	var t := screen.create_tween()
	t.tween_property(screen, "modulate:a", 0.0, 0.15)
	t.tween_callback(layer.queue_free)


func _process(delta: float) -> void:
	if _hand:
		_hand.visible = not (drag and drag.moved)  # out of the way while the player drags
	# A dragged piece glides after the finger instead of sticking to it.
	# It also leans into its motion, like something carried, tipping toward the
	# side it moves to.
	if drag and drag.moved:
		var p: ShapeView = drag.p
		var was := p.norm_pos
		# Over a hole, the hole opens up and draws the piece a little toward its middle.
		var over := _hole_under(drag.target, p)
		_set_hover(over)
		var aim: Vector2 = drag.target
		if over:
			aim = aim.lerp(over.norm_pos, MAGNET)
		p.move_to(p.norm_pos.lerp(aim, 1.0 - exp(-GLIDE_RATE * delta)), false)
		if delta > 0:
			var sideways := (p.norm_pos.x - was.x) * board.size.x / delta
			var lean := deg_to_rad(LEAN_MAX) * clampf(sideways / LEAN_SPEED, -1.0, 1.0)
			p.tilt = lerpf(p.tilt, lean, 1.0 - exp(-LEAN_RATE * delta))
	if level_time <= 0:
		timer_bar.ratio = 1.0
		timer_bar.low = false
		return
	var remaining := maxi(0, deadline_ms - Time.get_ticks_msec())
	timer_bar.ratio = minf(1.0, remaining / (level_time * 1000))  # full while the dots fade in
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
	_buzz(30)
	# The hole pulses with a sparkle as the piece arrives.
	var hole := p.target_hole
	get_tree().create_timer(0.15).timeout.connect(func():
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
	if not p.has_meta("extra"):
		_found_own = true
	if endless_extra and p.has_meta("extra") and _left_to_clear > 0:
		# Paused time doesn't count toward the wait.
		get_tree().create_timer(PlaySettings.extra_delay, false).timeout.connect(_spawn_extra.bind(_level_id))
	if _left_to_clear <= 0:
		if not tutorial:
			score += 1
		end_level(true)


## Stars stream from p's hole, where it has just gone in, up to the meter,
## which fills a step as they arrive, with a sparkle where they land.
## Placements in a quick run (see COMBO_MS) send more.
func _send_stars(p: ShapeView) -> void:
	var now := Time.get_ticks_msec()
	_combo = _combo + 1 if now - _last_place_ms < COMBO_MS else 0
	_last_place_ms = now
	var rect := p.target_hole.get_global_rect()
	var to := star_bar.next_spot()
	var step := star_bar.total - _left_to_clear  # the meter step these stars fill, from 0
	effects.stream_stars(rect.get_center(), to, rect.size.x * 0.5, STARS + COMBO_STARS * mini(_combo, 3))
	star_bar.add_one(Effects.STREAM_ARRIVE)
	get_tree().create_timer(Effects.STREAM_ARRIVE).timeout.connect(_stars_landed.bind(_level_id, to, step))


## The stars reach the meter: a sparkle and a bling, higher for each step, so
## filling the meter climbs like a scale.
func _stars_landed(id: int, at: Vector2, step: int) -> void:
	if id != _level_id:
		return
	effects.burst(at, 14.0)
	var n := CHIME_STEPS.size()
	bling.pitch_scale = pow(2.0, (CHIME_STEPS[step % n] + 12 * floori(step / float(n))) / 12.0)
	bling.play()
	_buzz(15)


## A short buzz on phones, so a touch can be felt as well as seen and heard.
func _buzz(ms: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


## Plays a sound a little higher or lower each time, by up to spread, so a
## sound heard over and over never comes out quite the same.
func _play_varied(player: AudioStreamPlayer, spread: float) -> void:
	player.pitch_scale = randf_range(1.0 - spread, 1.0 + spread)
	player.play()


func _play_pop(pitch: float) -> void:
	pop.pitch_scale = pitch
	pop.play()


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
	if _any_key_home and event.is_pressed() and not event.is_echo() \
			and (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey or event is InputEventJoypadButton):
		_any_key_home = false
		get_viewport().set_input_as_handled()
		_play_pop(1.0)
		_go_home()
		return
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
	_play_varied(uh_uh, 0.08)
	_play_varied(boing, 0.12)  # the soft spring back home
	p.move_to(p.home, true, true)
	_buzz(20)


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
	_play_pop(randf_range(0.9, 1.15))
	_buzz(10)


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
	_set_hover(null)
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

	var target := _hole_under(drop, p)
	if not target:
		p.move_to(p.home, true, true)
		_resume_search()
	elif target == p.target_hole:
		place(p)
	else:
		reject(p, target)


## The hole p would drop into with its center at pos, or null. A drop counts
## when the bounding circles touch. _hole_row keeps holes far enough apart that
## a piece can touch at most one.
func _hole_under(pos: Vector2, p: ShapeView) -> ShapeView:
	var side := ShapeView.side_for(board.size)
	for hole in holes:
		if ((hole.norm_pos - pos) * board.size).length() <= (hole.radius + p.radius) * side:
			return hole
	return null


## Opens hole and closes the last one, with a light tick as a new one opens.
func _set_hover(hole: ShapeView) -> void:
	if hole == _hover:
		return
	if is_instance_valid(_hover):
		_hover.set_open(false)
	_hover = hole
	if hole:
		hole.set_open(true)
		_play_pop(1.5)
		_buzz(6)
