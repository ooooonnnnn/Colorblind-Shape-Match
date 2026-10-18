extends Control

const LEVEL_TIME := 30.0     # seconds per level
const HOLE_GAP := 0.19       # center-to-center spacing of holes
const RING_RADIUS := 0.39    # distance of pieces from the board center
const DRAG_THRESHOLD := 6.0  # px of movement before a press counts as a drag

@onready var content: VBoxContainer = $Content
@onready var level_label: Label = $Content/Header/LevelValue
@onready var score_label: Label = $Content/Header/ScoreValue
@onready var hole_select: OptionButton = $Content/Header/HoleCount
@onready var timer_bar: TimerBar = $Content/TimerBar
@onready var timer_text: Label = $Content/TimerText
@onready var board: Panel = $Content/Board
@onready var toast: PanelContainer = $Content/Board/Toast
@onready var toast_label: Label = $Content/Board/Toast/Label
@onready var cheer: AudioStreamPlayer = $Cheer

var hole_count := 3
var level_num := 0
var score := 0
var holes: Array[ShapeView] = []
var pieces: Array[ShapeView] = []
var selected: ShapeView
var drag := {}  # empty when nothing is being dragged
var deadline_ms := 0
var transitioning := false
var _level_id := 0  # lets a pending level change notice it was superseded
var _toast_tween: Tween


func _ready() -> void:
	for n in [2, 3, 4, 5]:
		hole_select.add_item(str(n), n)
	hole_select.select(hole_select.get_item_index(hole_count))
	hole_select.item_selected.connect(_on_hole_count_selected)
	resized.connect(_layout)
	_layout()
	new_level()


func _layout() -> void:
	var side := clampf(minf(size.x - 32, size.y - 150), 100, 640)
	board.custom_minimum_size = Vector2(side, side)
	content.position = Vector2((size.x - side) / 2, 12)
	content.size = Vector2(side, 0)


# ---------- Layout ----------

func _hole_layout(n: int) -> Array[Vector2]:
	var rows: Array = {2: [2], 3: [3], 4: [2, 2], 5: [3, 2]}[n]
	var spots: Array[Vector2] = []
	for r in rows.size():
		var y := 0.5 + (r - (rows.size() - 1) / 2.0) * HOLE_GAP
		for i in rows[r]:
			spots.append(Vector2(0.5 + (i - (rows[r] - 1) / 2.0) * HOLE_GAP, y))
	spots.shuffle()
	return spots


func _ring_layout(n: int) -> Array[Vector2]:
	var offset := randf_range(0, TAU)
	var spots: Array[Vector2] = []
	for i in n:
		spots.append(Vector2(0.5, 0.5) + Vector2.from_angle(offset + TAU * i / n) * RING_RADIUS)
	spots.shuffle()
	return spots


# ---------- Level lifecycle ----------

func new_level() -> void:
	_level_id += 1
	level_num += 1
	level_label.text = str(level_num)
	for node in holes + pieces:
		node.queue_free()
	holes.clear()
	pieces.clear()
	selected = null
	drag = {}

	var shapes := Shapes.pick(hole_count)
	var hole_spots := _hole_layout(hole_count)
	var piece_spots := _ring_layout(hole_count)

	for i in hole_count:
		var hole := ShapeView.new()
		hole.setup(shapes[i], false)
		hole.norm_pos = hole_spots[i]
		board.add_child(hole)
		hole.gui_input.connect(_on_hole_input.bind(hole))
		holes.append(hole)

	for i in hole_count:
		var p := ShapeView.new()
		p.setup(shapes[i], true)
		p.target_hole = holes[i]
		p.home = piece_spots[i]
		p.norm_pos = p.home
		board.add_child(p)
		p.gui_input.connect(_on_piece_input.bind(p))
		pieces.append(p)

	deadline_ms = Time.get_ticks_msec() + int(LEVEL_TIME * 1000)
	transitioning = false


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
	var remaining := maxi(0, deadline_ms - Time.get_ticks_msec())
	timer_bar.ratio = remaining / (LEVEL_TIME * 1000)
	timer_bar.low = remaining < 5000
	timer_text.text = "%ds" % ceili(remaining / 1000.0)
	if remaining == 0 and not transitioning:
		end_level("Time's up!", 1.2)


# ---------- Matching ----------

func place(p: ShapeView) -> void:
	p.placed = true
	p.target_hole.filled = true
	for node in [p, p.target_hole]:
		node.release_focus()
		node.focus_mode = Control.FOCUS_NONE
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.mouse_default_cursor_shape = Control.CURSOR_ARROW
	p.z_index = 1
	p.move_to(p.target_hole.norm_pos)
	cheer.play()
	if pieces.all(func(q: ShapeView) -> bool: return q.placed):
		score += 1
		score_label.text = str(score)
		end_level("Level cleared!", 0.9)


func reject(p: ShapeView, hole: ShapeView) -> void:
	p.shake()
	hole.shake()
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
	if not selected or hole.filled or transitioning:
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

	var target: ShapeView = null
	var best := ShapeView.SIZE * 0.6
	for hole in holes:
		var dist := hole.norm_pos.distance_to(p.norm_pos)
		if not hole.filled and dist < best:
			target = hole
			best = dist

	if not target:
		p.move_to(p.home)
	elif target == p.target_hole:
		place(p)
	else:
		reject(p, target)


# ---------- Settings ----------

func _on_hole_count_selected(index: int) -> void:
	hole_count = hole_select.get_item_id(index)
	level_num = 0
	score = 0
	score_label.text = str(score)
	new_level()
