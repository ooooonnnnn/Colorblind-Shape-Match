extends Control
## The grown-up settings, in four tabs by what they are for: Levels (the level
## sequences, LevelConfig), Playing (dragging, the tutorial and shape size),
## Dots (the dot filter, dots.json and noise.json, and the outline) and Colors
## (the color groups, ColorGroups, and extra shapes). Beside them, the preview
## shows the dots, colors and shapes live, with the color group last chosen or
## edited, and can show it all through color blind eyes (ColorVision). Nothing
## is written until Save; leaving with unsaved changes asks first.

const Dots := preload("res://scripts/dots.gd")
const ColorGroups := preload("res://scripts/color_groups.gd")
const GroupPlate := preload("res://scripts/group_plate.gd")
const PREVIEW_SHAPES := ["circle", "star", "square"]  # the CVTME shapes
const PREVIEW_COPIES := 2  # pieces per preview shape, to show copies taking different colors
const MATCH_OK := Color("4caf7a")
const MATCH_OFF := Color("e8a33d")
const PREVIEW_SPACING := 16.0  # px between neighbouring preview shapes
const TRAY_PADDING := 24.0     # px between the holes and the tray edge, as in the game
const NEW_LEVEL := {"duration": 30.0, "holes": 3, "shapes": 3, "repetitions": 1, "filter": true, "colors": "random", "time_bonus": true, "extra": 0, "extra_scored": true}
const BADGE := Color("ffd166")
const REMOVE := Color("ffb4a2")
const MUTED := Color(0.231373, 0.184314, 0.290196, 0.8)  # Icons.INK, for explanations
const UNSAVED := Color("c46a00")  # a dark orange that reads on the page's blue
const CHIP_COLORS := {"time": Color("fff0c2"), "plays": Color("e3f1ff"), "dots": Color("dff5e5"), "colors": Color("f3e6ff"), "extra": Color("ffe4dc")}
const CHANNEL_NAMES := {"hue": "Hue", "saturation": "Saturation", "value": "Brightness"}
const PART_NAMES := {"background": "Background dots", "shapes": "Shape dots"}
const NARROW := 1300.0  # px; a page narrower than this puts the preview under the tabs
const CHECK_EVERY := 0.25  # seconds between checks for unsaved changes
const EDGE_SCROLL := 90.0  # px from the list's top or bottom edge where a dragged card scrolls it
const EDGE_SPEED := 700.0  # px/s it scrolls at, right at the edge
const ABOUT_SEQUENCES := "The game plays these sequences from top to bottom. Each one plays its level the set number of times, then the next one starts. After the last, the game ends with a big star. Drag a card by the dots on its left to move it.\n\nA sequence set to play forever is the last one ever reached; any after it are shown faded."
const ABOUT_TIME_BONUS := "In a timed level, each right match adds %d s (never past the level's full time), and each tap that lands on no piece, hole or button takes %d s away. Wrong drops cost nothing."
const ABOUT_EXTRA := "Extra pieces on the board, in colors this sequence's color group's type of color blindness sees as well as anyone. A player who finds them but misses the group's own pieces is missing color, not attention.\n\nCounted: every piece must be placed to clear the level. Not counted: only the group's own pieces must be, and extras are optional."
const ABOUT_DRAG := "Pieces can always be moved by tapping one, then its hole. Dragging lets them be carried there too. Turn it off for players who find dragging hard, so every move is two taps."
const ABOUT_TUTORIAL := "Starts each game with an extra first level: one piece in a dark color everyone can see, without dots, and a hand that keeps showing how to move it, by dragging or by tapping, until it's in. It doesn't count toward the score or the stats."
const ABOUT_LANDSCAPE := "On phones and tablets the game stays sideways, turning only between the two sideways ways round, which gives the shapes the most room. Off, it also turns upright with the device, and the board gets narrower and taller. Computers and browsers are not affected."
const ABOUT_DOTS := "The dots that hide the shapes, like an Ishihara plate. Smaller, tighter dots make the shapes harder to pick out. Area covered is how much of the board the dots fill."
const ABOUT_OUTLINE := "Pieces are drawn hollow, as an outline, as a share of their size. Bolder is easier to spot; much thinner, and the line slips between the dots, where the filter can't see it."
const ABOUT_NOISE := "Each dot's color shifts a little, so a shape can't be found by one exact color. Amount is how far colors shift; patch size is how big the areas that shift together are."
const ABOUT_BOARD := "The color between the dots and on the board, like the paper of a printed plate. It is the same around every dot, so it never gives a shape away."
const ABOUT_GROUPS := "Each group is made for one type of color blindness: its piece colors blend into its background for that type. The level sequences use these groups.\n\nThe bar under each piece color shows whether it really blends in for that type: green blends in, orange may be spotted."
const ABOUT_EXTRA_COLORS := "Extra shapes take colors outside the group's confusion line, which its type sees as well as anyone. This sets how different they look from the background to that type, as a CIELAB distance: around 10 is subtle, 40 and up is plain to see. How many each level has is set per sequence."
const ABOUT_VISION := "Shows the whole page as someone with that type of color blindness sees it, to check that a color group really hides its shapes. It stays on in the game too until set back to normal vision.\n\nStrength: many color blind people still have weakened cones of the missing type, so they see some of the difference. 100% is the full form."

@onready var tabs: TabContainer = %Tabs
@onready var levels_page: VBoxContainer = %LevelsPage
@onready var playing_page: VBoxContainer = %PlayingPage
@onready var dots_page: VBoxContainer = %DotsPage
@onready var colors_page: VBoxContainer = %ColorsPage
@onready var back: ToyButton = %Back
@onready var save: Button = %Save
@onready var saved_note: Label = %SavedNote
@onready var preview: Panel = %Preview
@onready var tray: Panel = %Tray
@onready var dots: Dots = $Dots
@onready var columns: BoxContainer = $Margin/Page/Columns

var _rows: Array[Dictionary] = []  # each level sequence's card, editor and controls, by field
var _level_list := VBoxContainer.new()
var _dot_sliders := {}  # {max_radius, gap, fill: HSlider}
var _noise_sliders := {}  # {part: {channel: {wavelength, amplitude}}} of HSliders, as in Dots.noise
var _size_slider: HSlider
var _outline_slider: HSlider
var _extra_slider: HSlider
var _extra_swatches := VBoxContainer.new()  # each color group's extra-shape colors
var _board_color := ColorPickerButton.new()
var _groups := {}  # see ColorGroups.load_settings
var _cards := {}  # {group id: {group, plate, bars: match bar per figure color}}
var _mode_buttons: Array[Button] = []  # article, custom
var _groups_note := Label.new()
var _restore_groups := Button.new()
var _group_list := VBoxContainer.new()
var _preview_colors := {}  # {key: group id and palette size, indices: figure color per preview piece}
var _previewed := ""  # the color group shown in the preview
var _holes: Array[ShapeView] = []
var _pieces: Array[ShapeView] = []
var _vision_buttons := {}  # {ColorVision mode: Button}
var _severity_slider: HSlider
var _saved_tween: Tween
var _tutorial_card := PanelContainer.new()
var _tutorial_summary := Label.new()
var _popup: PopupCard  # the open pop-up, or null
var _clean := ""  # the settings as last loaded or saved, see _state
var _dirty := false
var _check_in := 0.0
var _reorder := {}  # {row, pointer} while a sequence card is being dragged to a new place


func _ready() -> void:
	_groups = ColorGroups.load_settings()  # the level cards offer its groups
	PlaySettings.load_settings()  # the Levels tab shows the tutorial from it
	var drag_scroll := DragScroll.new()  # drag anywhere on a tab, or in a pop-up, to scroll it
	drag_scroll.target = func():
		if is_instance_valid(_popup):
			return _popup.scroll()
		return tabs.get_current_tab_control() as ScrollContainer
	add_child(drag_scroll)
	for i in tabs.get_tab_count():
		tabs.set_tab_title(i, ["Levels", "Playing", "Dots", "Colors"][i])
	tabs.add_theme_font_size_override("font_size", 24)
	_build_levels_page()
	# Dots has loaded its settings by now, as children are ready first.
	ShapeView.load_size()
	ExtraShapes.load_settings()
	_build_playing_page()
	_build_dots_page()
	preview.resized.connect(_layout_preview)
	_build_colors_page()
	_build_vision_controls()
	back.activated.connect(_on_back)
	save.pressed.connect(_save)
	resized.connect(_fit_columns)
	_fit_columns()
	_clean = _state()


# ---------- Building blocks ----------

## A white card with a title, a one-line explanation and a ? for the rest;
## returns the box to put its controls in.
func _card(parent: Control, title: String, line := "", about := "") -> VBoxContainer:
	var card := PanelContainer.new()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	card.add_child(body)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 27)
	head.add_child(heading)
	if about:
		head.add_child(InfoButton.new(title, about))
	body.add_child(head)
	if line:
		body.add_child(_note(line))
	parent.add_child(card)
	return body


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", MUTED)
	return label


## A caption, a slider and its value, shown through format.
func _slider(parent: Control, caption: String, from: float, to: float, by: float, value: float,
		format: Callable, on_change: Callable, exponential := false) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(230, 0)
	label.add_theme_font_size_override("font_size", 20)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = from
	slider.max_value = to
	slider.step = by
	slider.exp_edit = exponential
	slider.custom_minimum_size = Vector2(0, 36)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = value
	row.add_child(slider)
	var shown := Label.new()
	shown.custom_minimum_size = Vector2(86, 0)
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shown.add_theme_font_size_override("font_size", 21)
	shown.text = format.call(value)
	row.add_child(shown)
	slider.value_changed.connect(func(v):
		shown.text = format.call(v)
		on_change.call()
	)
	parent.add_child(row)
	return slider


func _switch(text: String, on: bool) -> ToySwitch:
	return ToySwitch.new(text, on)


func _row(controls: Array, separation := 22) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", separation)
	row.add_theme_constant_override("v_separation", 12)
	for c in controls:
		row.add_child(c)
	return row


## A pill naming one fact about a level, tinted by kind (see CHIP_COLORS).
func _chip(text: String, kind: String) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = CHIP_COLORS[kind]
	style.set_corner_radius_all(99)
	style.set_border_width_all(2)
	style.border_color = Color(Icons.INK, 0.35)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 19)
	chip.add_child(label)
	return chip


func _badge(text: String) -> Label:
	var badge := Label.new()
	badge.text = text
	badge.custom_minimum_size = Vector2(52, 52)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 28)
	var circle := StyleBoxFlat.new()
	circle.bg_color = BADGE
	circle.set_corner_radius_all(99)
	circle.set_border_width_all(3)
	circle.border_color = Icons.INK
	badge.add_theme_stylebox_override("normal", circle)
	return badge


## A page's opening line, with a ? for the rest.
func _intro(parent: Control, line: String, title := "", about := "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := _note(line)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if about:
		row.add_child(InfoButton.new(title, about))
	parent.add_child(row)


# ---------- Levels ----------

func _build_levels_page() -> void:
	_intro(levels_page, "The game plays these from top to bottom. Drag a card by its dots to move it, or tap Edit to change it.", "How sequences play", ABOUT_SEQUENCES)
	_build_tutorial_card()
	_level_list.add_theme_constant_override("separation", 14)
	levels_page.add_child(_level_list)
	for entry in LevelConfig.load_levels():
		_add_row(entry)
	var add := Button.new()
	add.text = "+  Add a sequence"
	add.custom_minimum_size = Vector2(0, 56)
	add.add_theme_font_size_override("font_size", 21)
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(func(): _open_editor(_add_row(NEW_LEVEL)))
	levels_page.add_child(add)


## The tutorial level, shown before the sequences while it is on (see the
## Playing tab); it has no controls of its own.
func _build_tutorial_card() -> void:
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 20)
	_tutorial_card.add_child(layout)
	layout.add_child(_badge("T"))
	var picture := LevelPicture.new()
	picture.custom_minimum_size = Vector2(190, 104)
	picture.holes = 1
	picture.pieces = 1
	picture.filter = false
	picture.tutorial = true
	layout.add_child(picture)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 6)
	layout.add_child(words)
	var title := Label.new()
	title.text = "Tutorial"
	title.add_theme_font_size_override("font_size", 25)
	words.add_child(title)
	_tutorial_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_summary.add_theme_font_size_override("font_size", 19)
	_tutorial_summary.add_theme_color_override("font_color", MUTED)
	words.add_child(_tutorial_summary)
	levels_page.add_child(_tutorial_card)
	_refresh_tutorial_card()


func _refresh_tutorial_card() -> void:
	_tutorial_card.visible = PlaySettings.tutorial
	_tutorial_summary.text = "One piece, no dots, no timer: %s. Not scored. Turn it off on the Playing tab." % (
			"a hand drags it into its hole" if PlaySettings.drag else "a hand taps it, then its hole")


## One sequence: a numbered card with a picture of its level, its size in big
## words and a chip for each other setting, with Edit opening its controls in
## a pop-up. Returns the row.
func _add_row(entry: Dictionary) -> Dictionary:
	var card := PanelContainer.new()
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 20)
	card.add_child(layout)
	var grip := Grip.new()
	layout.add_child(grip)
	var badge := _badge("")
	layout.add_child(badge)
	var picture := LevelPicture.new()
	picture.custom_minimum_size = Vector2(190, 104)
	layout.add_child(picture)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 8)
	layout.add_child(words)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 25)
	words.add_child(title)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	words.add_child(chips)
	var unreached := _note("")
	words.add_child(unreached)
	var edit := Button.new()
	edit.text = "Edit"
	edit.custom_minimum_size = Vector2(120, 56)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.add_theme_font_size_override("font_size", 21)
	layout.add_child(edit)

	var row := {
		"card": card, "badge": badge, "picture": picture, "title": title, "chips": chips, "unreached": unreached,
		"holes": Stepper.new("Holes", 1, Shapes.NAMES.size(), entry.holes),
		"shapes": Stepper.new("Pieces per hole", 1, 20, entry.shapes),
		"time_on": _switch("Time limit", entry.duration > 0),
		"duration": Stepper.new("Seconds", 5, 600, entry.duration if entry.duration > 0 else 30.0, 5),
		"time_bonus": _switch("Bonus and penalty", entry.time_bonus),
		"forever": _switch("Play forever", entry.repetitions <= 0),
		"repetitions": Stepper.new("Times to play", 1, 99, entry.repetitions if entry.repetitions > 0 else 1),
		"filter": _switch("Dots on", entry.filter),
		"colors": OptionButton.new(),
		"extra": Stepper.new("Extra shapes", 0, 20, entry.extra),
		"extra_scored": _switch("Counted", entry.extra_scored),
	}
	edit.pressed.connect(_open_editor.bind(row))
	grip.gui_input.connect(_on_grip_input.bind(row))
	row.colors.set_meta("choice", entry.colors)
	row.colors.custom_minimum_size = Vector2(300, 52)
	row.colors.add_theme_font_size_override("font_size", 20)
	_fill_color_choices(row.colors)
	row.colors.item_selected.connect(func(index):
		row.colors.set_meta("choice", row.colors.get_item_metadata(index))
		if row.colors.get_meta("choice") != ColorGroups.RANDOM:
			_preview_group(row.colors.get_meta("choice"))
		_refresh_rows()
	)
	for stepper in [row.holes, row.shapes, row.duration, row.repetitions, row.extra]:
		stepper.changed.connect(func(_v): _refresh_rows())
	for switch in [row.time_on, row.time_bonus, row.forever, row.filter, row.extra_scored]:
		switch.toggled.connect(func(_on): _refresh_rows())
	row.editor = _build_editor(row)
	_level_list.add_child(card)
	_rows.append(row)
	_refresh_rows()
	return row


## The editor a sequence's Edit opens: its picture and chips, then its
## controls in groups. Built once and kept, so the pop-up only borrows it.
func _build_editor(row: Dictionary) -> VBoxContainer:
	var editor := VBoxContainer.new()
	editor.add_theme_constant_override("separation", 18)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	var picture := LevelPicture.new()
	picture.custom_minimum_size = Vector2(260, 140)
	top.add_child(picture)
	var chips := HFlowContainer.new()
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	top.add_child(chips)
	editor.add_child(top)
	row.editor_picture = picture
	row.editor_chips = chips

	var colors_box := VBoxContainer.new()
	var colors_label := Label.new()
	colors_label.text = "Color group"
	colors_label.add_theme_font_size_override("font_size", 18)
	colors_box.add_child(colors_label)
	colors_box.add_child(row.colors)
	for group in [
			["The board", "How many shapes, and copies of each.", [row.holes, row.shapes], ""],
			["Time", "A countdown for each level, or none.", [row.time_on, row.duration, row.time_bonus],
					ABOUT_TIME_BONUS % [LevelConfig.TIME_BONUS, LevelConfig.TIME_PENALTY]],
			["How many times", "How often this level plays before the next sequence.", [row.repetitions, row.forever], ""],
			["Dots and colors", "Hide the pieces in dots, in one color group's colors.", [row.filter, colors_box], ""],
			["Extra shapes", "Pieces every type can see, as a check.", [row.extra, row.extra_scored], ABOUT_EXTRA]]:
		editor.add_child(HSeparator.new())
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		var heading := Label.new()
		heading.text = group[0]
		heading.add_theme_font_size_override("font_size", 25)
		head.add_child(heading)
		if group[3]:
			head.add_child(InfoButton.new(group[0], group[3]))
		editor.add_child(head)
		editor.add_child(_note(group[1]))
		var controls := _row(group[2], 30)
		for c in group[2]:
			c.size_flags_vertical = Control.SIZE_SHRINK_END
		editor.add_child(controls)
	return editor


# ---------- Reordering ----------

## A press on a card's grip picks the card up; it follows the pointer from
## slot to slot until let go. The grip keeps getting the pointer's moves
## while held, wherever it goes.
func _on_grip_input(event: InputEvent, row: Dictionary) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _reorder.is_empty():
			_reorder = {"row": row, "pointer": event.global_position}
			_lift(row.card, true)
		elif not event.pressed and _reorder.get("row") == row:
			_lift(row.card, false)
			_reorder = {}
	elif event is InputEventMouseMotion and _reorder.get("row") == row:
		_reorder.pointer = event.global_position
		_follow_pointer()


## Moves the held card to the slot under the pointer: past every card whose
## middle the pointer is below.
func _follow_pointer() -> void:
	var row: Dictionary = _reorder.row
	var slot := 0
	for other in _rows:
		if other != row and _reorder.pointer.y > other.card.get_global_rect().get_center().y:
			slot += 1
	if slot == _rows.find(row):
		return
	_rows.erase(row)
	_rows.insert(slot, row)
	_level_list.move_child(row.card, slot)
	_refresh_rows()
	_play_tick()


## A held card swells a little, with a bold outline and a deeper shadow, and
## settles back when let go.
func _lift(card: PanelContainer, up: bool) -> void:
	if up:
		var style := (card.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
		style.bg_color = Color("fffaf0")
		style.set_border_width_all(3)
		style.border_color = Icons.INK
		style.shadow_size = 14
		style.shadow_offset = Vector2(0, 8)
		style.shadow_color = Color(Icons.INK, 0.25)
		card.add_theme_stylebox_override("panel", style)
		card.z_index = 1
		_play_tick()
	else:
		card.remove_theme_stylebox_override("panel")
		card.z_index = 0
	card.pivot_offset = card.size / 2
	card.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(card, "scale", Vector2.ONE * (1.03 if up else 1.0), 0.15)


## The soft pop of the toy buttons, as a card is picked up or passes another.
func _play_tick() -> void:
	var tick := AudioStreamPlayer.new()
	tick.stream = ToyButton.POP
	tick.pitch_scale = randf_range(1.1, 1.3)
	tick.volume_db = -6.0
	tick.finished.connect(tick.queue_free)
	add_child(tick)
	tick.play()


## Scrolls the list while a held card is near its top or bottom edge,
## faster the closer it gets, so a card can be carried past what fits.
func _edge_scroll(delta: float) -> void:
	var scroll := tabs.get_current_tab_control() as ScrollContainer
	var rect := scroll.get_global_rect()
	var y: float = _reorder.pointer.y
	var push := 0.0
	if y < rect.position.y + EDGE_SCROLL:
		push = -(1.0 - (y - rect.position.y) / EDGE_SCROLL)
	elif y > rect.end.y - EDGE_SCROLL:
		push = 1.0 - (rect.end.y - y) / EDGE_SCROLL
	if push != 0.0:
		scroll.scroll_vertical += int(EDGE_SPEED * clampf(push, -1.0, 1.0) * delta)
		_follow_pointer()


## Opens row's editor in a pop-up; closing it keeps the editor for next time.
func _open_editor(row: Dictionary) -> void:
	if is_instance_valid(_popup):
		return
	_popup = PopupCard.open(self, "Sequence %d" % (_rows.find(row) + 1), 0.62)
	var popup := _popup
	popup.body.add_child(row.editor)
	popup.closing.connect(func(): popup.body.remove_child(row.editor))
	var delete := popup.add_button("Delete sequence", _confirm_remove.bind(row), REMOVE)
	delete.disabled = _rows.size() == 1
	delete.tooltip_text = "The game needs at least one sequence." if _rows.size() == 1 else ""
	popup.add_button("Done", popup.close, Color("ffd166"))


func _confirm_remove(row: Dictionary) -> void:
	if _rows.size() == 1:
		return  # the game needs at least one sequence
	var n := _rows.find(row) + 1
	var remove := func():
		if is_instance_valid(_popup):
			_popup.close()
		_remove_row(row)
	PopupCard.confirm(self, "Delete sequence %d?" % n, "Its level settings go. Nothing is saved until you press Save.",
			"Delete", remove, "Keep it", true)


func _remove_row(row: Dictionary) -> void:
	row.card.queue_free()
	row.editor.queue_free()
	_rows.erase(row)
	_refresh_rows()


func _notification(what: int) -> void:
	# Closed editors live outside the tree, so they go with the page here.
	if what == NOTIFICATION_PREDELETE:
		for row in _rows:
			if is_instance_valid(row.editor) and not row.editor.is_inside_tree():
				row.editor.free()


## Offers "Random" and each color group in the Colors tab, keeping the one
## chosen (kept in the "choice" meta), or falling back to random if that group
## is gone.
func _fill_color_choices(choices: OptionButton) -> void:
	var choice: String = choices.get_meta("choice", ColorGroups.RANDOM)
	choices.clear()
	choices.add_item("Random each level")
	choices.set_item_metadata(0, ColorGroups.RANDOM)
	for group in ColorGroups.active(_groups):
		choices.add_item("%s (%s)" % [group.name, group.kind])
		choices.set_item_metadata(choices.item_count - 1, group.id)
	choices.selected = 0
	for i in choices.item_count:
		if choices.get_item_metadata(i) == choice:
			choices.selected = i
	choices.set_meta("choice", choices.get_item_metadata(choices.selected))


## Renumbers the cards, redraws their pictures, titles and chips, and fades
## the ones that can never be reached because an earlier one plays forever.
func _refresh_rows() -> void:
	var endless_at := -1
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var holes := int(row.holes.value)
		var pieces := int(row.shapes.value)
		row.badge.text = str(i + 1)
		for picture in [row.picture, row.editor_picture]:
			picture.holes = holes
			picture.pieces = pieces
			picture.filter = row.filter.button_pressed
		row.duration.editable = row.time_on.button_pressed
		row.time_bonus.disabled = not row.time_on.button_pressed
		row.repetitions.editable = not row.forever.button_pressed
		row.colors.disabled = not row.filter.button_pressed
		var extra := int(row.extra.value)
		row.extra_scored.disabled = extra == 0
		row.title.text = "%d %s · %d %s each" % [holes, "hole" if holes == 1 else "holes", pieces, "piece" if pieces == 1 else "pieces"]
		for box in [row.chips, row.editor_chips]:
			for child in box.get_children():
				child.queue_free()
			for chip in _chips_for(row):
				box.add_child(_chip(chip[0], chip[1]))
		var reached := endless_at < 0
		row.card.modulate.a = 1.0 if reached else 0.5
		row.unreached.visible = not reached
		row.unreached.text = "Never reached: sequence %d plays forever." % (endless_at + 1)
		if reached and row.forever.button_pressed:
			endless_at = i


## [text, kind] for each chip on row's card.
func _chips_for(row: Dictionary) -> Array:
	var chips := []
	if row.time_on.button_pressed:
		chips.append(["%d s per level%s" % [row.duration.value, ", with bonus" if row.time_bonus.button_pressed else ""], "time"])
	else:
		chips.append(["No timer", "time"])
	var times := int(row.repetitions.value)
	chips.append(["Plays forever" if row.forever.button_pressed else "Plays once" if times == 1 else "Plays %d times" % times, "plays"])
	if row.filter.button_pressed:
		chips.append(["Dots on", "dots"])
		chips.append(["Random colors" if row.colors.get_meta("choice") == ColorGroups.RANDOM
				else "%s colors" % row.colors.get_item_text(row.colors.selected).get_slice(" (", 0), "colors"])
	else:
		chips.append(["No dots", "dots"])
	var extra := int(row.extra.value)
	if extra > 0:
		chips.append(["+%d extra, %s" % [extra, "counted" if row.extra_scored.button_pressed else "not counted"], "extra"])
	return chips


func _levels() -> Array[Dictionary]:
	var levels: Array[Dictionary] = []
	for row in _rows:
		levels.append({
			"duration": row.duration.value if row.time_on.button_pressed else 0.0,
			"holes": int(row.holes.value),
			"shapes": int(row.shapes.value),
			"repetitions": 0 if row.forever.button_pressed else int(row.repetitions.value),
			"filter": row.filter.button_pressed,
			"colors": row.colors.get_meta("choice"),
			"time_bonus": row.time_bonus.button_pressed,
			"extra": int(row.extra.value),
			"extra_scored": row.extra_scored.button_pressed,
		})
	return levels


# ---------- Playing ----------

func _build_playing_page() -> void:
	var moving := _card(playing_page, "Moving pieces", "Drag a piece into its hole, or tap it and then its hole.", ABOUT_DRAG)
	var drag := _switch("Drag pieces", PlaySettings.drag)
	drag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	drag.toggled.connect(func(on):
		PlaySettings.drag = on  # the game reads the saved file, so unsaved changes stay here
		_refresh_tutorial_card()
	)
	moving.add_child(drag)

	var tutorial_card := _card(playing_page, "Tutorial", "A first practice level, with a hand showing how to play.", ABOUT_TUTORIAL)
	var tutorial := _switch("Start with the tutorial", PlaySettings.tutorial)
	tutorial.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tutorial.toggled.connect(func(on):
		PlaySettings.tutorial = on
		_refresh_tutorial_card()
	)
	tutorial_card.add_child(tutorial)

	var screen_card := _card(playing_page, "Screen", "Keep phones and tablets sideways.", ABOUT_LANDSCAPE)
	var landscape := _switch("Lock to landscape", PlaySettings.landscape)
	landscape.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	landscape.toggled.connect(func(on): PlaySettings.landscape = on)
	screen_card.add_child(landscape)

	var size_card := _card(playing_page, "Shape size", "Bigger shapes are easier to see and to grab.")
	_size_slider = _slider(size_card, "Size", 5, 40, 1, ShapeView.side_fraction * 100,
			func(v): return "%d%%" % v, _on_size_changed)
	size_card.add_child(_note("As a share of the board's shorter side."))


func _on_size_changed() -> void:
	ShapeView.side_fraction = _size_slider.value / 100
	_layout_preview()


# ---------- Dots ----------

func _build_dots_page() -> void:
	var top := HBoxContainer.new()
	var line := _note("How the dot plates look. The preview shows each change right away.")
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(line)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.custom_minimum_size = Vector2(0, 50)
	reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset.pressed.connect(func(): PopupCard.confirm(self, "Reset the dots?",
			"The dot pattern, outlines, color variation and board color go back to their starting values. Nothing is saved until you press Save.",
			"Reset", _reset_dots_tab, "Cancel", true))
	top.add_child(reset)
	dots_page.add_child(top)

	var size_card := _card(dots_page, "Dot pattern", "Smaller, tighter dots hide the shapes better.", ABOUT_DOTS)
	var px := func(v): return "%s px" % (str(int(v)) if v == int(v) else "%.1f" % v)
	_dot_sliders.max_radius = _slider(size_card, "Largest dot", 1, 15, 0.5, dots.max_radius, px, _on_dots_changed)
	_dot_sliders.gap = _slider(size_card, "Space between", 0, 8, 0.5, dots.gap, px, _on_dots_changed)
	_dot_sliders.fill = _slider(size_card, "Area covered", 20, 100, 1, dots.fill * 100,
			func(v): return "%d%%" % v, _on_dots_changed)

	var outline_card := _card(dots_page, "Shape outlines", "Bolder outlines are easier to spot in the dots.", ABOUT_OUTLINE)
	_outline_slider = _slider(outline_card, "Thickness", 1, 50, 0.5, ShapeView.outline_percent,
			func(v): return "%s%%" % (str(int(v)) if v == int(v) else "%.1f" % v), _on_outline_changed)

	var noise_card := _card(dots_page, "Color variation", "Small shifts in each dot's color, so no single color gives a shape away.", ABOUT_NOISE)
	var fold := VBoxContainer.new()
	fold.add_theme_constant_override("separation", 12)
	fold.visible = false
	var toggle := Button.new()
	toggle.text = "Show the fine-tuning"
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	toggle.custom_minimum_size = Vector2(0, 50)
	toggle.pressed.connect(func():
		fold.visible = not fold.visible
		toggle.text = "Hide the fine-tuning" if fold.visible else "Show the fine-tuning"
	)
	noise_card.add_child(toggle)
	noise_card.add_child(fold)
	for part in Dots.NOISE_PARTS:
		var heading := Label.new()
		heading.text = PART_NAMES.get(part, part.capitalize())
		heading.add_theme_font_size_override("font_size", 23)
		fold.add_child(heading)
		_noise_sliders[part] = {}
		for channel in Dots.NOISE_CHANNELS:
			var values: Dictionary = dots.noise[part][channel]
			var channel_name: String = CHANNEL_NAMES.get(channel, channel.capitalize())
			_noise_sliders[part][channel] = {
				"amplitude": _slider(fold, "%s amount" % channel_name, 0, 1, 0.01, values.amplitude,
						func(v): return "%d%%" % roundi(v * 100), _on_noise_changed),
				"wavelength": _slider(fold, "%s patch size" % channel_name, 1, 500, 1, values.wavelength,
						func(v): return "%d px" % v, _on_noise_changed, true),
			}
		if part != Dots.NOISE_PARTS.keys()[-1]:
			fold.add_child(HSeparator.new())

	var board_card := _card(dots_page, "Board background", "The paper color between the dots.", ABOUT_BOARD)
	_board_color.custom_minimum_size = Vector2(140, 52)
	_board_color.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_board_color.edit_alpha = false
	_board_color.color = dots.board_color
	_board_color.color_changed.connect(func(color): dots.board_color = color)
	board_card.add_child(_board_color)


## Puts every setting on the Dots tab back to its default. The sliders' own
## change handlers pass the values on to the preview.
func _reset_dots_tab() -> void:
	_dot_sliders.max_radius.value = Dots.DEFAULT_CONFIG.max_radius
	_dot_sliders.gap.value = Dots.DEFAULT_CONFIG.gap
	_dot_sliders.fill.value = Dots.DEFAULT_CONFIG.fill_percent
	for part in _noise_sliders:
		for channel in _noise_sliders[part]:
			var defaults: Dictionary = Dots.DEFAULT_NOISE[part][channel]
			_noise_sliders[part][channel].amplitude.value = defaults.amplitude
			_noise_sliders[part][channel].wavelength.value = defaults.wavelength
	_board_color.color = Dots.DEFAULT_BOARD_COLOR
	dots.board_color = Dots.DEFAULT_BOARD_COLOR


func _on_dots_changed() -> void:
	dots.apply_config({"max_radius": _dot_sliders.max_radius.value, "gap": _dot_sliders.gap.value,
			"fill_percent": _dot_sliders.fill.value})


func _on_noise_changed() -> void:
	var data := {}
	for part in _noise_sliders:
		data[part] = {}
		for channel in _noise_sliders[part]:
			var sliders: Dictionary = _noise_sliders[part][channel]
			data[part][channel] = {"wavelength": sliders.wavelength.value, "amplitude": sliders.amplitude.value}
	dots.apply_noise(data)


func _on_outline_changed() -> void:
	ShapeView.outline_percent = _outline_slider.value
	for view in _holes + _pieces:
		view.queue_redraw()
	_layout_preview()  # holes grow with the outline, and the tray with them


# ---------- Colors ----------

func _build_colors_page() -> void:
	var choose := _card(colors_page, "Color groups", "One group of colors for each type of color blindness.", ABOUT_GROUPS)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	for i in 2:
		var b := Button.new()
		b.text = ["From the research", "My own colors"][i]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 52)
		b.add_theme_font_size_override("font_size", 20)
		b.button_pressed = (i == 1) == _groups.custom
		b.pressed.connect(_on_color_mode_selected.bind(i))
		modes.add_child(b)
		_mode_buttons.append(b)
	choose.add_child(modes)
	_groups_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_groups_note.add_theme_font_size_override("font_size", 19)
	_groups_note.add_theme_color_override("font_color", MUTED)
	choose.add_child(_groups_note)
	_restore_groups.text = "Reset my colors to the research ones"
	_restore_groups.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_restore_groups.pressed.connect(func(): PopupCard.confirm(self, "Reset your colors?",
			"Your own colors are replaced by a copy of the research ones. Nothing is saved until you press Save.",
			"Reset", _on_restore_groups, "Cancel", true))
	choose.add_child(_restore_groups)

	_group_list.add_theme_constant_override("separation", 14)
	colors_page.add_child(_group_list)

	var extra_card := _card(colors_page, "Extra shape colors", "How easy the extra shapes are to see.", ABOUT_EXTRA_COLORS)
	_extra_slider = _slider(extra_card, "How easy to see", 5, 80, 1, ExtraShapes.difference,
			func(v): return "%d" % v, _on_extra_changed)
	_extra_swatches.add_theme_constant_override("separation", 8)
	extra_card.add_child(_extra_swatches)
	_rebuild_groups()
	_on_extra_changed()


func _on_color_mode_selected(index: int) -> void:
	_groups.custom = index == 1
	_rebuild_groups()


func _on_restore_groups() -> void:
	_groups.groups = ColorGroups.article_copy()
	_rebuild_groups()


func _delete_group(id: String) -> void:
	_groups.groups = _groups.groups.filter(func(g): return g.id != id)
	_rebuild_groups()


func _add_color(group: Dictionary) -> void:
	group.colors.append(group.colors[-1])
	_rebuild_groups()


func _remove_color(group: Dictionary, i: int) -> void:
	group.colors.remove_at(i)
	_rebuild_groups()


func _on_extra_changed() -> void:
	ExtraShapes.difference = _extra_slider.value
	_show_extra_colors()


## Swatches of the extra-shape colors each color group in use would get.
func _show_extra_colors() -> void:
	for child in _extra_swatches.get_children():
		child.queue_free()
	for group in ColorGroups.active(_groups):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var label := Label.new()
		label.text = group.name
		label.custom_minimum_size = Vector2(130, 0)
		label.add_theme_font_size_override("font_size", 20)
		row.add_child(label)
		var colors := ColorGroups.extra_colors(group, ExtraShapes.difference)
		for color in colors:
			var swatch := ColorRect.new()
			swatch.color = color
			swatch.custom_minimum_size = Vector2(48, 32)
			swatch.tooltip_text = "#%s, which %s players see %d apart from the background" % [color.to_html(false), group.name,
					roundi(ColorGroups.seen_difference(group.id, color, group.background))]
			row.add_child(swatch)
		if colors.is_empty():
			row.add_child(_note("No color found, so its levels get no extra shapes."))
		_extra_swatches.add_child(row)


## Refills the group cards, and the level cards' color choices, from the
## groups in use, after the mode changed or groups or colors were added,
## deleted or restored.
func _rebuild_groups() -> void:
	var groups := ColorGroups.active(_groups)
	for row in _rows:
		_fill_color_choices(row.colors)
	_refresh_rows()
	if _extra_slider:
		_show_extra_colors()
	_groups_note.text = ("Your own colors: tap a color to change it, + to add a piece color, × to remove one." if _groups.custom
			else "These come from the research and can't be changed. Choose \"My own colors\" to edit a copy.")
	_restore_groups.visible = _groups.custom

	for child in _group_list.get_children():
		child.queue_free()
	_cards.clear()
	for group in groups:
		_add_card(group, groups.size())
	_update_cards()
	if ColorGroups.find(_groups, _previewed).is_empty():
		_previewed = ColorGroups.pick(_groups)
	_preview_group(_previewed)


## One group: a mini plate in its colors, what it tests, and its swatches, each
## piece color over a bar showing whether it blends into the background for
## the group's type of color blindness. Editable only with "My own colors".
func _add_card(group: Dictionary, group_count: int) -> void:
	var editable: bool = _groups.custom
	var card := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)

	var plate: Control = GroupPlate.new()
	plate.custom_minimum_size = Vector2(112, 112)
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(plate)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 8)
	row.add_child(middle)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	name_label.text = group.name
	name_label.add_theme_font_size_override("font_size", 25)
	title.add_child(name_label)
	if group.get("about", ""):
		title.add_child(InfoButton.new(group.name, group.about))
	middle.add_child(title)
	middle.add_child(_note("%s · %s" % [group.kind, group.prevalence]))

	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 8)
	var background := _swatch(group, -1, editable, Vector2(76, 48))
	swatches.add_child(background.box)
	swatches.add_child(VSeparator.new())
	var bars: Array[ColorRect] = []
	for i in group.colors.size():
		var swatch := _swatch(group, i, editable, Vector2(48, 48))
		bars.append(swatch.bar)
		if editable and group.colors.size() > 1:
			var remove := Button.new()
			remove.text = "×"
			remove.flat = true
			remove.tooltip_text = "Remove this color"
			remove.pressed.connect(_remove_color.bind(group, i))
			swatch.box.add_child(remove)
		swatches.add_child(swatch.box)
	if editable and group.colors.size() < ColorGroups.MAX_COLORS:
		var add := Button.new()
		add.text = "+"
		add.custom_minimum_size = Vector2(48, 48)
		add.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		add.tooltip_text = "Add a piece color"
		add.pressed.connect(_add_color.bind(group))
		swatches.add_child(add)
	middle.add_child(swatches)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var show_button := Button.new()
	show_button.text = "Preview"
	show_button.custom_minimum_size = Vector2(130, 50)
	show_button.pressed.connect(_preview_group.bind(group.id))
	buttons.add_child(show_button)
	if editable:
		var delete := Button.new()
		delete.text = "Delete"
		delete.custom_minimum_size = Vector2(130, 50)
		delete.disabled = group_count == 1
		var remove := func(): PopupCard.confirm(self, "Delete %s?" % group.name,
				"Level sequences using it switch to random colors. Nothing is saved until you press Save.",
				"Delete", _delete_group.bind(group.id), "Keep it", true)
		delete.pressed.connect(remove)
		buttons.add_child(delete)
	row.add_child(buttons)

	_group_list.add_child(card)
	_cards[group.id] = {"group": group, "plate": plate, "bars": bars}


## A color picker for group's background (i = -1) or its piece color i, over
## a bar that shows whether a piece color blends into the background for the
## group's type of color blindness.
func _swatch(group: Dictionary, i: int, editable: bool, swatch_size: Vector2) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = swatch_size
	picker.edit_alpha = false
	picker.disabled = not editable
	picker.color = group.background if i < 0 else group.colors[i]
	picker.tooltip_text = "Background" if i < 0 else "Piece color %d" % (i + 1)
	picker.color_changed.connect(_on_group_color_changed.bind(group, i))
	box.add_child(picker)
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(swatch_size.x, 7)
	bar.color = Color.TRANSPARENT
	box.add_child(bar)
	return {"box": box, "bar": bar}


func _on_group_color_changed(color: Color, group: Dictionary, i: int) -> void:
	if i < 0:
		group.background = color
		_show_extra_colors()  # they are worked out from the background
	else:
		group.colors[i] = color
	_update_cards()
	_preview_group(group.id)


## Refreshes each card's plate and match bars.
func _update_cards() -> void:
	for id in _cards:
		var card: Dictionary = _cards[id]
		var group: Dictionary = card.group
		card.plate.background = group.background
		card.plate.colors = group.colors
		for i in card.bars.size():
			var difference := ColorGroups.seen_difference(group.id, group.colors[i], group.background)
			var matches := difference <= ColorGroups.MATCH_TOLERANCE
			card.bars[i].color = MATCH_OK if matches else MATCH_OFF
			card.bars[i].tooltip_text = "%s players see it %d apart from the background: %s" % [group.name, roundi(difference),
					"it blends in, on their confusion line" if matches else "off their confusion line, so they may spot it"]


# ---------- Preview ----------

## Under the preview's title: buttons to see it all as each type of color
## blindness does, and how strongly.
func _build_vision_controls() -> void:
	var column := preview.get_parent()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = "See it as"
	label.add_theme_font_size_override("font_size", 20)
	head.add_child(label)
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	var names := {ColorVision.NONE: "Normal"}
	for type in ColorVision.TYPES:
		names[type] = ColorVision.TYPES[type].name
	for mode in names:
		var b := Button.new()
		b.text = names[mode]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 46)
		b.button_pressed = mode == ColorVision.mode
		b.pressed.connect(_on_vision_selected.bind(mode))
		choices.add_child(b)
		_vision_buttons[mode] = b
	head.add_child(choices)
	head.add_child(InfoButton.new("Seeing it as color blind", ABOUT_VISION))
	box.add_child(head)
	_severity_slider = _slider(box, "Strength", 10, 100, 5, ColorVision.severity * 100,
			func(v): return "%d%%" % v, func(): ColorVision.severity = _severity_slider.value / 100)
	column.add_child(box)
	column.move_child(box, preview.get_index() - 1)
	_on_vision_selected(ColorVision.mode)


func _on_vision_selected(mode: String) -> void:
	ColorVision.mode = mode
	_severity_slider.editable = mode != ColorVision.NONE
	_severity_slider.get_parent().modulate.a = 1.0 if mode != ColorVision.NONE else 0.45


## Shows group id in the preview: its background, and two copies of each
## preview shape in its piece colors, given out as in the game.
func _preview_group(id: String) -> void:
	_previewed = id
	var group := ColorGroups.find(_groups, id)
	dots.show_group(group)
	var key := "%s/%d" % [id, group.colors.size()]
	if _preview_colors.get("key") != key:
		_preview_colors = {"key": key, "indices": ColorGroups.piece_colors(group.colors.size(), PREVIEW_SHAPES.size(), PREVIEW_SHAPES.size() * PREVIEW_COPIES)}
	for view in _holes + _pieces:
		view.queue_free()
	_holes.clear()
	_pieces.clear()
	for i in PREVIEW_SHAPES.size() * (PREVIEW_COPIES + 1):
		var shape := {"name": PREVIEW_SHAPES[i % PREVIEW_SHAPES.size()], "points": Shapes.make(PREVIEW_SHAPES[i % PREVIEW_SHAPES.size()])}
		var piece := i >= PREVIEW_SHAPES.size()
		var view := ShapeView.new()
		view.setup(shape, piece)
		view.focus_mode = Control.FOCUS_NONE
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if piece:
			view.fill = dots.figure_color(_preview_colors.indices[_pieces.size()])
			_pieces.append(view)
		else:
			_holes.append(view)
		preview.add_child(view)
	_layout_preview()


## Holes in a row inside the tray, with their pieces in a row below.
func _layout_preview() -> void:
	var board := preview.size
	if board.x <= 0 or board.y <= 0:
		return
	var side := ShapeView.side_for(board)
	var step := side + PREVIEW_SPACING
	var first_x := board.x / 2 - step * (_holes.size() - 1) / 2
	var holes_y := board.y * 0.3
	for i in _holes.size():
		_holes[i].norm_pos = Vector2(first_x + step * i, holes_y) / board
	# Each shape's copies stack in a column below its hole.
	for i in _pieces.size():
		var x := first_x + step * (i % _holes.size())
		_pieces[i].norm_pos = Vector2(x, board.y * (0.6 + 0.22 * (i / _holes.size()))) / board
	var row := Rect2(first_x - side / 2, holes_y - side / 2, step * _holes.size() - PREVIEW_SPACING, side)
	var tray_rect := row.grow(side * ShapeView.outline_percent / 200 + TRAY_PADDING)  # holes reach out to a piece's outer edge
	tray.position = tray_rect.position
	tray.size = tray_rect.size


# ---------- Saving and leaving ----------

## Side by side on a wide screen; on a narrow one, as an upright phone or
## window, the preview goes under the tabs, which take the room left.
func _fit_columns() -> void:
	var narrow := size.x < NARROW
	columns.vertical = narrow
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.get_parent().custom_minimum_size.y = 560.0 if narrow else 0.0
	preview.get_parent().size_flags_vertical = Control.SIZE_FILL if narrow else Control.SIZE_EXPAND_FILL


## Everything Save writes, as text, to tell whether anything changed since.
func _state() -> String:
	return var_to_str([_levels(), dots.max_radius, dots.gap, dots.fill, dots.board_color, dots.noise, _groups,
			ShapeView.side_fraction, ShapeView.outline_percent, ExtraShapes.difference,
			ColorVision.mode, ColorVision.severity, PlaySettings.drag, PlaySettings.tutorial, PlaySettings.landscape])


## Shows "Unsaved changes" by Save while there are any, and carries a held
## card along the list's edges.
func _process(delta: float) -> void:
	if not _reorder.is_empty():
		_edge_scroll(delta)
	_check_in -= delta
	if _check_in > 0:
		return
	_check_in = CHECK_EVERY
	var dirty := _state() != _clean
	if dirty == _dirty:
		return
	_dirty = dirty
	if _saved_tween:
		_saved_tween.kill()
	saved_note.text = "Unsaved changes"
	saved_note.add_theme_color_override("font_color", UNSAVED)
	saved_note.modulate.a = 1.0 if dirty else 0.0


func _on_back() -> void:
	if _state() == _clean:
		_leave()
		return
	if is_instance_valid(_popup):
		_popup.close()
	var popup := PopupCard.open(self, "Leave without saving?", 0.46)
	popup.add_text("You have changes that aren't saved yet.")
	popup.add_button("Keep editing", popup.close)
	popup.add_button("Leave", _leave, REMOVE)
	var save_and_leave := func():
		if _save():
			_leave()
	popup.add_button("Save and leave", save_and_leave, Color("7bd88f"))


func _leave() -> void:
	ColorVision.load_settings()  # leave unsaved changes behind
	PlaySettings.load_settings()
	await get_tree().create_timer(0.15).timeout  # let the button's pop play
	get_tree().change_scene_to_file("res://menu.tscn")


## Writes every settings file; returns whether all of them were written.
func _save() -> bool:
	var failed := false
	for result in [LevelConfig.save_levels(_levels()), dots.save_config(), dots.save_noise(), ColorGroups.save_settings(_groups), ShapeView.save_size(), ExtraShapes.save_settings(), ColorVision.save_settings(), PlaySettings.save_settings()]:
		if result != OK:
			failed = true
			push_error("Could not save config: %s" % error_string(result))
	if not failed:
		PlaySettings.apply_orientation()
		_clean = _state()
		_dirty = false
	saved_note.text = "Couldn't save, see the log" if failed else "Saved!"
	saved_note.add_theme_color_override("font_color", UNSAVED if failed else Icons.INK)
	if _saved_tween:
		_saved_tween.kill()
	_saved_tween = create_tween()
	_saved_tween.tween_property(saved_note, "modulate:a", 1.0, 0.15)
	if not failed:
		_saved_tween.tween_interval(1.5)
		_saved_tween.tween_property(saved_note, "modulate:a", 0.0, 0.4)
	return not failed


## The handle on a sequence card's left: two columns of dots, to press and
## drag the card up or down the list (see _on_grip_input).
class Grip extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(34, 84)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_default_cursor_shape = Control.CURSOR_MOVE
		tooltip_text = "Drag to change the order"
		add_to_group(DragScroll.HANDLES)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var pill := StyleBoxFlat.new()
		pill.set_corner_radius_all(12)
		pill.bg_color = Color(Icons.INK, 0.1 if get_global_rect().has_point(get_global_mouse_position()) else 0.04)
		draw_style_box(pill, Rect2(Vector2.ZERO, size))
		for col in 2:
			for line in 3:
				draw_circle(size / 2 + Vector2((col - 0.5) * 11, (line - 1) * 14), 3.5, Color(Icons.INK, 0.6))
