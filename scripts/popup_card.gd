class_name PopupCard
extends Control
## A window that springs open over a dimmed page and shrinks away again: for
## editors, explanations and questions. It closes with its cross, a click
## outside it, or Esc. Put contents in body and buttons in buttons.

signal closing  ## about to shrink away; take back anything that must outlive it

const DIM := Color(0.231373, 0.184314, 0.290196, 0.45)  # Icons.INK, see-through
const PAPER := Color("fffaf0")  # the window, warm white like the board's frame
const OPEN_TIME := 0.22  # seconds to spring open
const CLOSE_TIME := 0.14
const YES := Color("7bd88f")
const DANGER := Color("ffb4a2")

var body := VBoxContainer.new()
var buttons := HBoxContainer.new()
var _window := PanelContainer.new()
var _scroll := ScrollContainer.new()
var _title := Label.new()
var _closed := false


## Opens a window with a title over parent's whole area, width as a fraction
## of it. Fill body and buttons after.
static func open(parent: Node, title: String, width := 0.6) -> PopupCard:
	var popup := PopupCard.new()
	popup._title.text = title
	popup._window.anchor_left = (1.0 - width) / 2
	popup._window.anchor_right = 1.0 - (1.0 - width) / 2
	parent.add_child(popup)
	return popup


## A question with a choice: yes_text runs on_yes and closes, the other button
## just closes. danger colors the yes button as something that can't be undone.
static func confirm(parent: Node, title: String, text: String, yes_text: String, on_yes: Callable,
		no_text := "Cancel", danger := false) -> PopupCard:
	var popup := open(parent, title, 0.44)
	popup.add_text(text)
	popup.add_button(no_text, popup.close)
	var yes := func():
		on_yes.call()
		popup.close()
	popup.add_button(yes_text, yes, DANGER if danger else YES)
	return popup


## An explanation and an OK.
static func info(parent: Node, title: String, text: String) -> PopupCard:
	var popup := open(parent, title, 0.44)
	popup.add_text(text)
	popup.add_button("Got it", popup.close, Color("ffd166"))
	return popup


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0  # until it springs open
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			close()
	)
	add_child(dim)

	_window.anchor_top = 0.07
	_window.anchor_bottom = 0.93
	var solid := StyleBoxFlat.new()  # like the cards, but solid and outlined like the buttons
	solid.bg_color = PAPER
	solid.set_corner_radius_all(26)
	solid.set_border_width_all(3)
	solid.border_color = Icons.INK
	solid.set_content_margin_all(26)
	solid.shadow_color = Color(Icons.INK, 0.25)
	solid.shadow_size = 14
	solid.shadow_offset = Vector2(0, 6)
	_window.add_theme_stylebox_override("panel", solid)
	add_child(_window)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	_window.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 32)
	head.add_child(_title)
	var cross := ToyButton.new()
	cross.picture = "cross"
	cross.color = DANGER
	cross.custom_minimum_size = Vector2(56, 56)
	cross.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cross.tooltip_text = "Close"
	cross.activated.connect(close)
	head.add_child(cross)
	column.add_child(head)

	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	_scroll.add_child(body)
	column.add_child(_scroll)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 14)
	column.add_child(buttons)


func _ready() -> void:
	# Short windows shrink to fit their contents, centered, rather than fill the
	# page. Wrapped text knows its height only once it has its width, a frame in.
	await get_tree().process_frame
	await get_tree().process_frame
	if _closed:
		return
	# The scroll asks for no height of its own, so the window's minimum leaves out the body.
	var wanted := _window.get_combined_minimum_size().y + body.get_combined_minimum_size().y + 8
	var room := size.y * (_window.anchor_bottom - _window.anchor_top)
	if wanted < room:
		var top := (1.0 - wanted / size.y) / 2
		_window.anchor_top = top
		_window.anchor_bottom = 1.0 - top
	# Spring open from the middle once the window has its size.
	await get_tree().process_frame
	if _closed:
		return
	_window.pivot_offset = _window.size / 2
	var t := create_tween().set_parallel()
	t.tween_property(self, "modulate:a", 1.0, OPEN_TIME * 0.6)
	t.tween_property(_window, "scale", Vector2.ONE, OPEN_TIME).from(Vector2.ONE * 0.85).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A paragraph in the body, in the readable size.
func add_text(text: String, muted := false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 21)
	if muted:
		label.add_theme_color_override("font_color", Color(Icons.INK, 0.78))
	body.add_child(label)
	return label


## A titled group in the body; returns the box for its contents.
func add_section(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 25)
	box.add_child(heading)
	body.add_child(box)
	return box


func add_button(text: String, on_press: Callable, color := Color.WHITE) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 54)
	b.add_theme_font_size_override("font_size", 21)
	b.pressed.connect(on_press)
	buttons.add_child(b)
	if color != Color.WHITE:
		tint(b, color)
	return b


## Gives a theme button a colored face, lighter on hover. b must be in the
## tree, or it gets Godot's own button style rather than the game's.
static func tint(b: Button, color: Color) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := (b.get_theme_stylebox(state) as StyleBoxFlat).duplicate()
		style.bg_color = color.lightened(0.2) if state == "hover" else color
		b.add_theme_stylebox_override(state, style)


## The scroll the window's contents live in, for DragScroll.
func scroll() -> ScrollContainer:
	return _scroll


func close() -> void:
	if _closed:
		return
	_closed = true
	closing.emit()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.pivot_offset = _window.size / 2
	var t := create_tween().set_parallel()
	t.tween_property(self, "modulate:a", 0.0, CLOSE_TIME)
	t.tween_property(_window, "scale", Vector2.ONE * 0.9, CLOSE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if not _closed and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
