extends Control
## Edits the level sequences (LevelConfig), the dot filter (dots.json), the dot
## color noise (noise.json), the color groups (ColorGroups) and the shape size
## (shape_size.json), one tab each. The preview shows all but the levels live,
## with the color group last chosen or edited; nothing is written until Save.

const Dots := preload("res://scripts/dots.gd")
const ColorGroups := preload("res://scripts/color_groups.gd")
const GroupPlate := preload("res://scripts/group_plate.gd")
const PREVIEW_SHAPES := ["circle", "star", "square"]  # the CVTME shapes
const PREVIEW_COPIES := 2  # pieces per preview shape, to show copies taking different colors
const LIGHTNESS_OK := Color("4caf7a")
const LIGHTNESS_OFF := Color("e8a33d")
const PREVIEW_SPACING := 16.0  # px between neighbouring preview shapes
const TRAY_PADDING := 24.0     # px between the holes and the tray edge, as in the game
const NEW_LEVEL := {"duration": 30.0, "holes": 3, "shapes": 3, "repetitions": 1, "filter": true}
const BADGE := Color("ffd166")
const REMOVE := Color("ffb4a2")
const MUTED := Color(0.231373, 0.184314, 0.290196, 0.7)  # Icons.INK, for explanations
const CHANNEL_NAMES := {"hue": "Hue", "saturation": "Saturation", "value": "Brightness"}
const PART_NAMES := {"background": "Background dots", "shapes": "Shape dots"}

@onready var levels_page: VBoxContainer = %LevelsPage
@onready var dots_page: VBoxContainer = %DotsPage
@onready var colors_page: VBoxContainer = %ColorsPage
@onready var shapes_page: VBoxContainer = %ShapesPage
@onready var back: ToyButton = %Back
@onready var save: Button = %Save
@onready var saved_note: Label = %SavedNote
@onready var preview: Panel = %Preview
@onready var tray: Panel = %Tray
@onready var dots: Dots = $Dots

var _rows: Array[Dictionary] = []  # each level sequence's card and controls, by field
var _level_list := VBoxContainer.new()
var _dot_sliders := {}  # {max_radius, gap, fill: HSlider}
var _noise_sliders := {}  # {part: {channel: {wavelength, amplitude}}} of HSliders, as in Dots.noise
var _size_slider: HSlider
var _outline_slider: HSlider
var _board_color := ColorPickerButton.new()
var _groups := {}  # see ColorGroups.load_settings
var _cards := {}  # {group id: {group, plate, status, bars: lightness bar per figure color}}
var _mode_buttons: Array[Button] = []  # article, custom
var _play_group := OptionButton.new()
var _groups_note := Label.new()
var _restore_groups := Button.new()
var _group_list := VBoxContainer.new()
var _preview_colors := {}  # {key: group id and palette size, indices: figure color per preview piece}
var _previewed := ""  # the color group shown in the preview
var _holes: Array[ShapeView] = []
var _pieces: Array[ShapeView] = []
var _saved_tween: Tween


func _ready() -> void:
	_build_levels_page()
	# Dots has loaded its settings by now, as children are ready first.
	_build_dots_page()
	ShapeView.load_size()
	_build_shapes_page()
	preview.resized.connect(_layout_preview)
	_build_colors_page()
	back.activated.connect(func():
		await get_tree().create_timer(0.15).timeout  # let the button's pop play
		get_tree().change_scene_to_file("res://menu.tscn")
	)
	save.pressed.connect(_save)


# ---------- Building blocks ----------

## A white card with a title and a plain-language explanation; returns the
## box to put its controls in.
func _card(parent: Control, title: String, about := "") -> VBoxContainer:
	var card := PanelContainer.new()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	card.add_child(body)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 24)
	body.add_child(heading)
	if about:
		body.add_child(_note(about))
	parent.add_child(card)
	return body


func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", MUTED)
	return label


## A caption, a slider and its value, shown through format.
func _slider(parent: Control, caption: String, from: float, to: float, by: float, value: float,
		format: Callable, on_change: Callable, exponential := false) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(190, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = from
	slider.max_value = to
	slider.step = by
	slider.exp_edit = exponential
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = value
	row.add_child(slider)
	var shown := Label.new()
	shown.custom_minimum_size = Vector2(80, 0)
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shown.text = format.call(value)
	row.add_child(shown)
	slider.value_changed.connect(func(v):
		shown.text = format.call(v)
		on_change.call()
	)
	parent.add_child(row)
	return slider


# ---------- Level sequences ----------

func _build_levels_page() -> void:
	levels_page.add_child(_note("The game plays these sequences from top to bottom. Each one plays its level the set number of times, then the next sequence starts. After the last one, the game ends with a big star."))
	_level_list.add_theme_constant_override("separation", 12)
	levels_page.add_child(_level_list)
	for entry in LevelConfig.load_levels():
		_add_row(entry)
	var add := Button.new()
	add.text = "+  Add a sequence"
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(func(): _add_row(NEW_LEVEL))
	levels_page.add_child(add)


## One sequence: a numbered card with a picture of its level, a sentence
## saying what it does, and the controls to change it.
func _add_row(entry: Dictionary) -> void:
	var card := PanelContainer.new()
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	card.add_child(layout)

	var badge := Label.new()
	badge.custom_minimum_size = Vector2(48, 48)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 26)
	var circle := StyleBoxFlat.new()
	circle.bg_color = BADGE
	circle.set_corner_radius_all(99)
	circle.set_border_width_all(3)
	circle.border_color = Icons.INK
	badge.add_theme_stylebox_override("normal", circle)
	layout.add_child(badge)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	layout.add_child(body)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	body.add_child(top)
	var picture := LevelPicture.new()
	picture.custom_minimum_size = Vector2(230, 120)
	top.add_child(picture)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(words)
	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 20)
	words.add_child(summary)
	var unreached := _note("")
	words.add_child(unreached)

	var controls := HFlowContainer.new()
	controls.add_theme_constant_override("h_separation", 22)
	controls.add_theme_constant_override("v_separation", 10)
	body.add_child(controls)
	var row := {
		"card": card, "badge": badge, "picture": picture, "summary": summary, "unreached": unreached,
		"holes": Stepper.new("Holes", 1, Shapes.NAMES.size(), entry.holes),
		"shapes": Stepper.new("Pieces per hole", 1, 20, entry.shapes),
		"time_on": _switch("Time limit", entry.duration > 0),
		"duration": Stepper.new("Seconds", 5, 600, entry.duration if entry.duration > 0 else 30.0, 5),
		"forever": _switch("Plays forever", entry.repetitions <= 0),
		"repetitions": Stepper.new("Times to play", 1, 99, entry.repetitions if entry.repetitions > 0 else 1),
		"filter": _switch("Dots filter", entry.filter),
	}
	controls.add_child(row.holes)
	controls.add_child(row.shapes)
	controls.add_child(_stack([row.time_on, row.duration]))
	controls.add_child(_stack([row.forever, row.repetitions]))
	controls.add_child(_stack([row.filter]))
	for stepper in [row.holes, row.shapes, row.duration, row.repetitions]:
		stepper.changed.connect(func(_v): _refresh_rows())
	for switch in [row.time_on, row.forever, row.filter]:
		switch.toggled.connect(func(_on): _refresh_rows())

	var remove := ToyButton.new()
	remove.picture = "cross"
	remove.color = REMOVE
	remove.custom_minimum_size = Vector2(48, 48)
	remove.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	remove.tooltip_text = "Remove this sequence"
	remove.activated.connect(_remove_row.bind(row))
	layout.add_child(remove)
	row.remove = remove

	_level_list.add_child(card)
	_rows.append(row)
	_refresh_rows()


func _switch(text: String, on: bool) -> CheckButton:
	var switch := CheckButton.new()
	switch.text = text
	switch.button_pressed = on
	return switch


func _stack(controls: Array) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	for c in controls:
		box.add_child(c)
	return box


func _remove_row(row: Dictionary) -> void:
	if _rows.size() == 1:
		return  # the game needs at least one sequence
	row.card.queue_free()
	_rows.erase(row)
	_refresh_rows()


## Renumbers the cards, redraws their pictures and sentences, and fades the
## ones that can never be reached because an earlier one plays forever.
func _refresh_rows() -> void:
	var endless_at := -1
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var holes := int(row.holes.value)
		var pieces := int(row.shapes.value)
		row.badge.text = str(i + 1)
		row.picture.holes = holes
		row.picture.pieces = pieces
		row.picture.filter = row.filter.button_pressed
		row.duration.editable = row.time_on.button_pressed
		row.repetitions.editable = not row.forever.button_pressed
		row.remove.disabled = _rows.size() == 1
		row.summary.text = "%d %s, %d %s for each.\n%s · %s · %s" % [
				holes, "hole" if holes == 1 else "holes", pieces, "piece" if pieces == 1 else "pieces",
				"%d seconds per level" % row.duration.value if row.time_on.button_pressed else "No time limit",
				"plays forever" if row.forever.button_pressed else ("plays once" if row.repetitions.value == 1 else "plays %d times" % row.repetitions.value),
				"dots on" if row.filter.button_pressed else "no dots"]
		var reached := endless_at < 0
		row.card.modulate.a = 1.0 if reached else 0.5
		row.unreached.visible = not reached
		row.unreached.text = "Never reached: sequence %d before it plays forever." % (endless_at + 1)
		if reached and row.forever.button_pressed:
			endless_at = i


func _levels() -> Array[Dictionary]:
	var levels: Array[Dictionary] = []
	for row in _rows:
		levels.append({
			"duration": row.duration.value if row.time_on.button_pressed else 0.0,
			"holes": int(row.holes.value),
			"shapes": int(row.shapes.value),
			"repetitions": 0 if row.forever.button_pressed else int(row.repetitions.value),
			"filter": row.filter.button_pressed,
		})
	return levels


# ---------- Dots ----------

func _build_dots_page() -> void:
	var size_card := _card(dots_page, "Dot pattern",
			"The dots that hide the shapes. Smaller, tighter dots make the shapes harder to pick out.")
	var px := func(v): return "%s px" % (str(int(v)) if v == int(v) else "%.1f" % v)
	_dot_sliders.max_radius = _slider(size_card, "Largest dot", 1, 15, 0.5, dots.max_radius, px, _on_dots_changed)
	_dot_sliders.gap = _slider(size_card, "Space between dots", 0, 8, 0.5, dots.gap, px, _on_dots_changed)
	_dot_sliders.fill = _slider(size_card, "Area covered", 20, 100, 1, dots.fill * 100,
			func(v): return "%d%%" % v, _on_dots_changed)

	var noise_card := _card(dots_page, "Color variation",
			"Each dot's color shifts a little, so a shape can't be found by one exact color. Amount is how far colors shift; patch size is how big the areas that shift together are.")
	for part in Dots.NOISE_PARTS:
		var heading := Label.new()
		heading.text = PART_NAMES.get(part, part.capitalize())
		heading.add_theme_font_size_override("font_size", 20)
		noise_card.add_child(heading)
		_noise_sliders[part] = {}
		for channel in Dots.NOISE_CHANNELS:
			var values: Dictionary = dots.noise[part][channel]
			var channel_name: String = CHANNEL_NAMES.get(channel, channel.capitalize())
			_noise_sliders[part][channel] = {
				"amplitude": _slider(noise_card, "%s amount" % channel_name, 0, 1, 0.01, values.amplitude,
						func(v): return "%d%%" % roundi(v * 100), _on_noise_changed),
				"wavelength": _slider(noise_card, "%s patch size" % channel_name, 1, 500, 1, values.wavelength,
						func(v): return "%d px" % v, _on_noise_changed, true),
			}
		if part != Dots.NOISE_PARTS.keys()[-1]:
			noise_card.add_child(HSeparator.new())

	var board_card := _card(dots_page, "Board background",
			"The color between the dots and on the board, like the paper of a printed plate. It is the same around every dot, so it never gives a shape away.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_board_color.custom_minimum_size = Vector2(120, 44)
	_board_color.edit_alpha = false
	_board_color.color = dots.board_color
	_board_color.color_changed.connect(func(color): dots.board_color = color)
	row.add_child(_board_color)
	var reset := Button.new()
	reset.text = "Default"
	reset.pressed.connect(func():
		_board_color.color = Dots.DEFAULT_BOARD_COLOR
		dots.board_color = Dots.DEFAULT_BOARD_COLOR
	)
	row.add_child(reset)
	board_card.add_child(row)


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


# ---------- Shapes ----------

func _build_shapes_page() -> void:
	var card := _card(shapes_page, "Shape size",
			"How big the pieces and holes are, as a share of the board's shorter side. Bigger shapes are easier to see and to grab.")
	_size_slider = _slider(card, "Size", 5, 40, 1, ShapeView.side_fraction * 100,
			func(v): return "%d%%" % v, _on_size_changed)

	var outline_card := _card(shapes_page, "Outline thickness",
			"Pieces are drawn hollow, as an outline, as a share of their size. Bolder is easier to spot; much thinner and the line slips between the dots.")
	_outline_slider = _slider(outline_card, "Thickness", 1, 50, 0.5, ShapeView.outline_percent,
			func(v): return "%s%%" % (str(int(v)) if v == int(v) else "%.1f" % v), _on_outline_changed)


func _on_size_changed() -> void:
	ShapeView.side_fraction = _size_slider.value / 100
	_layout_preview()


func _on_outline_changed() -> void:
	ShapeView.outline_percent = _outline_slider.value
	for view in _holes + _pieces:
		view.queue_redraw()
	_layout_preview()  # holes grow with the outline, and the tray with them


# ---------- Color groups ----------

func _build_colors_page() -> void:
	_groups = ColorGroups.load_settings()
	var choose := _card(colors_page, "Which colors",
			"Each group is made for one type of color blindness: its piece colors blend into its background for that type. Hover a group for details.")
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	for i in 2:
		var b := Button.new()
		b.text = ["From the research", "My own colors"][i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = (i == 1) == _groups.custom
		b.pressed.connect(_on_color_mode_selected.bind(i))
		modes.add_child(b)
		_mode_buttons.append(b)
	choose.add_child(modes)
	var play_row := HBoxContainer.new()
	play_row.add_theme_constant_override("separation", 12)
	var play_label := Label.new()
	play_label.text = "Play with"
	play_row.add_child(play_label)
	play_row.add_child(_play_group)
	_play_group.item_selected.connect(_on_play_group_selected)
	choose.add_child(play_row)
	_groups_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_groups_note.add_theme_font_size_override("font_size", 16)
	_groups_note.add_theme_color_override("font_color", MUTED)
	choose.add_child(_groups_note)
	_restore_groups.text = "Reset my colors to the research ones"
	_restore_groups.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_restore_groups.pressed.connect(_on_restore_groups)
	choose.add_child(_restore_groups)

	_group_list.add_theme_constant_override("separation", 12)
	colors_page.add_child(_group_list)
	_rebuild_groups()


func _on_color_mode_selected(index: int) -> void:
	_groups.custom = index == 1
	_rebuild_groups()


func _on_play_group_selected(index: int) -> void:
	_groups.play = _play_group.get_item_metadata(index)
	_update_cards()
	if _groups.play != ColorGroups.RANDOM:
		_preview_group(_groups.play)


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


## Refills the play choices and the group cards from the groups in use, after
## the mode changed or groups or colors were added, deleted or restored.
func _rebuild_groups() -> void:
	var groups := ColorGroups.active(_groups)
	if _groups.play != ColorGroups.RANDOM and ColorGroups.find(_groups, _groups.play).is_empty():
		_groups.play = groups[0].id
	_fill_play_choices()
	_groups_note.text = ("These are your own colors: click a color to change it, + to add a piece color and × to remove one." if _groups.custom
			else "These colors come from the research and can't be changed. Pick \"My own colors\" to edit a copy of them.")
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


func _fill_play_choices() -> void:
	_play_group.clear()
	for group in ColorGroups.active(_groups):
		_play_group.add_item("%s (%s)" % [group.name, group.kind])
		_play_group.set_item_metadata(_play_group.item_count - 1, group.id)
	_play_group.add_item("A random group each level")
	_play_group.set_item_metadata(_play_group.item_count - 1, ColorGroups.RANDOM)
	for i in _play_group.item_count:
		if _play_group.get_item_metadata(i) == _groups.play:
			_play_group.selected = i


## One group: a mini plate in its colors, what it tests, and its swatches, each
## piece color over a bar showing whether it matches the background's
## lightness. Editable only with "My own colors".
func _add_card(group: Dictionary, group_count: int) -> void:
	var editable: bool = _groups.custom
	var card := PanelContainer.new()
	card.tooltip_text = group.about
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)

	var plate: Control = GroupPlate.new()
	plate.custom_minimum_size = Vector2(112, 112)
	row.add_child(plate)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 6)
	row.add_child(middle)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 10)
	var name_label := Label.new()
	name_label.text = group.name
	name_label.add_theme_font_size_override("font_size", 22)
	title.add_child(name_label)
	var status := Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title.add_child(status)
	middle.add_child(title)
	middle.add_child(_note("%s · %s" % [group.kind, group.prevalence]))

	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 8)
	var background := _swatch(group, -1, editable, Vector2(72, 44))
	swatches.add_child(background.box)
	swatches.add_child(VSeparator.new())
	var bars: Array[ColorRect] = []
	for i in group.colors.size():
		var swatch := _swatch(group, i, editable, Vector2(44, 44))
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
		add.custom_minimum_size = Vector2(44, 44)
		add.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		add.tooltip_text = "Add a piece color"
		add.pressed.connect(_add_color.bind(group))
		swatches.add_child(add)
	middle.add_child(swatches)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var show_button := Button.new()
	show_button.text = "Preview"
	show_button.pressed.connect(_preview_group.bind(group.id))
	buttons.add_child(show_button)
	if editable:
		var delete := Button.new()
		delete.text = "Delete"
		delete.disabled = group_count == 1
		delete.pressed.connect(_delete_group.bind(group.id))
		buttons.add_child(delete)
	row.add_child(buttons)

	_group_list.add_child(card)
	_cards[group.id] = {"group": group, "plate": plate, "status": status, "bars": bars}


## A color picker for group's background (i = -1) or its piece color i, over
## a bar that shows whether a piece color matches the background's lightness.
func _swatch(group: Dictionary, i: int, editable: bool, swatch_size: Vector2) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = swatch_size
	picker.edit_alpha = false
	picker.disabled = not editable
	picker.color = group.background if i < 0 else group.colors[i]
	picker.tooltip_text = "Background" if i < 0 else "Piece color %d" % (i + 1)
	picker.color_changed.connect(_on_group_color_changed.bind(group, i))
	box.add_child(picker)
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(swatch_size.x, 5)
	bar.color = Color.TRANSPARENT
	box.add_child(bar)
	return {"box": box, "bar": bar}


func _on_group_color_changed(color: Color, group: Dictionary, i: int) -> void:
	if i < 0:
		group.background = color
	else:
		group.colors[i] = color
	_update_cards()
	_preview_group(group.id)


## Refreshes each card's plate, play status and lightness bars.
func _update_cards() -> void:
	for id in _cards:
		var card: Dictionary = _cards[id]
		var group: Dictionary = card.group
		card.plate.background = group.background
		card.plate.colors = group.colors
		if _groups.play == ColorGroups.RANDOM:
			card.status.text = "In the random mix"
		else:
			card.status.text = "Playing now" if _groups.play == id else ""
		var background_l := ColorGroups.lightness(group.background)
		for i in card.bars.size():
			var l := ColorGroups.lightness(group.colors[i])
			var matches := absf(l - background_l) <= ColorGroups.LIGHTNESS_TOLERANCE
			card.bars[i].color = LIGHTNESS_OK if matches else LIGHTNESS_OFF
			card.bars[i].tooltip_text = "Lightness %d, background %d: %s" % [roundi(l), roundi(background_l),
					"matches, so it can only be told apart by color" if matches else "color-blind players may spot it by brightness"]


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


# ---------- Preview ----------

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


# ---------- Saving ----------

func _save() -> void:
	var failed := false
	for result in [LevelConfig.save_levels(_levels()), dots.save_config(), dots.save_noise(), ColorGroups.save_settings(_groups), ShapeView.save_size()]:
		if result != OK:
			failed = true
			push_error("Could not save config: %s" % error_string(result))
	saved_note.text = "Couldn't save, see the log" if failed else "Saved!"
	if _saved_tween:
		_saved_tween.kill()
	_saved_tween = create_tween()
	_saved_tween.tween_property(saved_note, "modulate:a", 1.0, 0.15)
	_saved_tween.tween_interval(1.5)
	_saved_tween.tween_property(saved_note, "modulate:a", 0.0, 0.4)
