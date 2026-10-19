extends Control
## Edits the level sequences (LevelConfig), the dot filter (dots.json), the dot
## color noise (noise.json), the color groups (ColorGroups) and the shape size
## (shape_size.json). The preview shows all but the levels live, with the color
## group last chosen or edited; nothing is written until Save.

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

@onready var levels_grid: GridContainer = %Levels
@onready var add_level: Button = %AddLevel
@onready var max_radius: SpinBox = %MaxRadius
@onready var gap: SpinBox = %Gap
@onready var fill: SpinBox = %Fill
@onready var noise_grid: GridContainer = %Noise
@onready var open_groups: Button = %OpenGroups
@onready var settings_column: VBoxContainer = $Margin/Columns/Settings
@onready var groups_page: VBoxContainer = %GroupsPage
@onready var color_mode: OptionButton = %ColorMode
@onready var play_group: OptionButton = %PlayGroup
@onready var groups_note: Label = %GroupsNote
@onready var group_list: VBoxContainer = %GroupList
@onready var close_groups: Button = %CloseGroups
@onready var restore_groups: Button = %RestoreGroups
@onready var size_spin: SpinBox = %Size
@onready var back: Button = %Back
@onready var save: Button = %Save
@onready var preview: Panel = %Preview
@onready var tray: Panel = %Tray
@onready var dots: Dots = $Dots

var _rows: Array[Dictionary] = []  # each level sequence's controls, by field
var _noise_spins := {}  # {part: {channel: {wavelength, amplitude}}} of SpinBoxes, as in Dots.noise
var _groups := {}  # see ColorGroups.load_settings
var _cards := {}  # {group id: {group, plate, status, bars: lightness bar per figure color}}
var _preview_colors := {}  # {key: group id and palette size, indices: figure color per preview piece}
var _previewed := ""  # the color group shown in the preview
var _holes: Array[ShapeView] = []
var _pieces: Array[ShapeView] = []


func _ready() -> void:
	for header in ["Duration", "", "Holes", "Shapes per hole", "Repetitions", "", "", ""]:
		var label := Label.new()
		label.text = header
		levels_grid.add_child(label)
	for entry in LevelConfig.load_levels():
		_add_row(entry)
	add_level.pressed.connect(func(): _add_row(NEW_LEVEL))

	# Dots has loaded its settings by now, as children are ready first.
	max_radius.value = dots.max_radius
	gap.value = dots.gap
	fill.value = dots.fill * 100
	for spin in [max_radius, gap, fill]:
		spin.value_changed.connect(_on_dots_changed)
	_build_noise_grid()

	ShapeView.load_size()
	size_spin.value = ShapeView.side_fraction * 100
	size_spin.value_changed.connect(_on_size_changed)

	preview.resized.connect(_layout_preview)
	_build_groups()
	back.pressed.connect(get_tree().change_scene_to_file.bind("res://menu.tscn"))
	save.pressed.connect(_save)


# ---------- Level sequences ----------

func _add_row(entry: Dictionary) -> void:
	var row := {
		"duration": _spin(1, 600, 30, "s"),
		"no_limit": _check("No time limit"),
		"holes": _spin(1, Shapes.NAMES.size(), entry.holes),
		"shapes": _spin(1, 20, entry.shapes),
		"repetitions": _spin(1, 99, 1),
		"endless": _check("Endless"),
		"filter": _check("Ishihara filter"),
		"remove": Button.new(),
	}
	row.filter.button_pressed = entry.filter
	row.no_limit.toggled.connect(func(on): row.duration.editable = not on)
	row.endless.toggled.connect(func(on): row.repetitions.editable = not on)
	if entry.duration > 0:
		row.duration.value = entry.duration
	else:
		row.no_limit.button_pressed = true
	if entry.repetitions > 0:
		row.repetitions.value = entry.repetitions
	else:
		row.endless.button_pressed = true
	row.remove.text = "Remove"
	row.remove.pressed.connect(_remove_row.bind(row))
	for control in row.values():
		levels_grid.add_child(control)
	_rows.append(row)
	_update_remove_buttons()


func _remove_row(row: Dictionary) -> void:
	for control in row.values():
		control.queue_free()
	_rows.erase(row)
	_update_remove_buttons()


## The game needs at least one level sequence.
func _update_remove_buttons() -> void:
	for row in _rows:
		row.remove.disabled = _rows.size() == 1


func _spin(min_value: float, max_value: float, value: float, suffix := "") -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.allow_greater = true
	spin.value = value
	spin.suffix = suffix
	return spin


func _check(text: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	return check


func _levels() -> Array[Dictionary]:
	var levels: Array[Dictionary] = []
	for row in _rows:
		levels.append({
			"duration": 0.0 if row.no_limit.button_pressed else row.duration.value,
			"holes": int(row.holes.value),
			"shapes": int(row.shapes.value),
			"repetitions": 0 if row.endless.button_pressed else int(row.repetitions.value),
			"filter": row.filter.button_pressed,
		})
	return levels


# ---------- Dot color noise ----------

## A row per channel, with each part's wavelength and amplitude side by side.
func _build_noise_grid() -> void:
	noise_grid.add_child(Label.new())
	for part in Dots.NOISE_PARTS:
		for field in ["wavelength", "amplitude"]:
			var header := Label.new()
			header.text = "%s %s" % [part.capitalize(), field]
			noise_grid.add_child(header)
		_noise_spins[part] = {}
	for channel in Dots.NOISE_CHANNELS:
		var label := Label.new()
		label.text = channel.capitalize()
		noise_grid.add_child(label)
		for part in Dots.NOISE_PARTS:
			var values: Dictionary = dots.noise[part][channel]
			var wavelength := _spin(1, 2000, values.wavelength, "px")
			var amplitude := _spin(0, 1, values.amplitude)
			amplitude.step = 0.01
			amplitude.value = values.amplitude
			for spin in [wavelength, amplitude]:
				spin.value_changed.connect(_on_noise_changed)
				noise_grid.add_child(spin)
			_noise_spins[part][channel] = {"wavelength": wavelength, "amplitude": amplitude}


func _on_noise_changed(_value: float) -> void:
	var data := {}
	for part in _noise_spins:
		data[part] = {}
		for channel in _noise_spins[part]:
			var spins: Dictionary = _noise_spins[part][channel]
			data[part][channel] = {"wavelength": spins.wavelength.value, "amplitude": spins.amplitude.value}
	dots.apply_noise(data)


# ---------- Color groups ----------

func _build_groups() -> void:
	_groups = ColorGroups.load_settings()
	color_mode.add_item("Article-based (default)")
	color_mode.add_item("Custom")
	color_mode.selected = 1 if _groups.custom else 0
	color_mode.item_selected.connect(_on_color_mode_selected)
	play_group.item_selected.connect(_on_play_group_selected)
	open_groups.pressed.connect(_show_groups_page.bind(true))
	close_groups.pressed.connect(_show_groups_page.bind(false))
	restore_groups.pressed.connect(_on_restore_groups)
	_rebuild_groups()


func _show_groups_page(on: bool) -> void:
	settings_column.visible = not on
	groups_page.visible = on


func _on_color_mode_selected(index: int) -> void:
	_groups.custom = index == 1
	_rebuild_groups()


func _on_play_group_selected(index: int) -> void:
	_groups.play = play_group.get_item_metadata(index)
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
	groups_note.text = ("Your own groups: click a swatch to recolor, + and × to add or remove figure colors. The game uses them after Save." if _groups.custom
			else "The article-based groups are fixed. Switch Colors to Custom to edit your own copy.")
	restore_groups.disabled = not _groups.custom

	for child in group_list.get_children():
		child.queue_free()
	_cards.clear()
	for group in groups:
		_add_card(group, groups.size())
	_update_cards()
	if ColorGroups.find(_groups, _previewed).is_empty():
		_previewed = ColorGroups.pick(_groups)
	_preview_group(_previewed)


func _fill_play_choices() -> void:
	play_group.clear()
	for group in ColorGroups.active(_groups):
		play_group.add_item("%s (%s)" % [group.name, group.kind])
		play_group.set_item_metadata(play_group.item_count - 1, group.id)
	play_group.add_item("Random group each level")
	play_group.set_item_metadata(play_group.item_count - 1, ColorGroups.RANDOM)
	for i in play_group.item_count:
		if play_group.get_item_metadata(i) == _groups.play:
			play_group.selected = i


## One group: a mini plate in its colors, what it tests, and its swatches, each
## figure color with a bar showing whether it matches the background's
## lightness. Editable only in custom mode.
func _add_card(group: Dictionary, group_count: int) -> void:
	var editable: bool = _groups.custom
	var style := StyleBoxFlat.new()
	style.bg_color = Color("252a37")
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", style)
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
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color("e9ecf2"))
	title.add_child(name_label)
	var kind := Label.new()
	kind.text = "%s · %s" % [group.kind, group.prevalence]
	title.add_child(kind)
	var status := Label.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_theme_color_override("font_color", Color("e9ecf2"))
	title.add_child(status)
	middle.add_child(title)

	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 8)
	var background := _swatch(group, -1, editable, Vector2(72, 44))
	swatches.add_child(background.box)
	var divider := VSeparator.new()
	swatches.add_child(divider)
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
		add.tooltip_text = "Add a figure color"
		add.pressed.connect(_add_color.bind(group))
		swatches.add_child(add)
	middle.add_child(swatches)

	var buttons := VBoxContainer.new()
	var show_button := Button.new()
	show_button.text = "Preview"
	show_button.pressed.connect(_preview_group.bind(group.id))
	buttons.add_child(show_button)
	var delete := Button.new()
	delete.text = "Delete"
	delete.disabled = not editable or group_count == 1
	delete.pressed.connect(_delete_group.bind(group.id))
	buttons.add_child(delete)
	row.add_child(buttons)

	group_list.add_child(card)
	_cards[group.id] = {"group": group, "plate": plate, "status": status, "bars": bars}


## A color picker for group's background (i = -1) or its figure color i, over
## a bar that shows whether a figure color matches the background's lightness.
func _swatch(group: Dictionary, i: int, editable: bool, swatch_size: Vector2) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = swatch_size
	picker.edit_alpha = false
	picker.disabled = not editable
	picker.color = group.background if i < 0 else group.colors[i]
	picker.tooltip_text = "Background" if i < 0 else "Figure color %d" % (i + 1)
	picker.color_changed.connect(_on_group_color_changed.bind(group, i))
	box.add_child(picker)
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(swatch_size.x, 4)
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
			card.status.text = "In the random rotation"
		else:
			card.status.text = "Playing" if _groups.play == id else ""
		var background_l := ColorGroups.lightness(group.background)
		for i in card.bars.size():
			var l := ColorGroups.lightness(group.colors[i])
			var matches := absf(l - background_l) <= ColorGroups.LIGHTNESS_TOLERANCE
			card.bars[i].color = LIGHTNESS_OK if matches else LIGHTNESS_OFF
			card.bars[i].tooltip_text = "Lightness %d, background %d: %s" % [roundi(l), roundi(background_l),
					"matches, so it can only be told apart by color" if matches else "color-blind players may spot it by brightness"]


## Shows group id in the preview: its background, and two copies of each
## preview shape in its figure colors, given out as in the game.
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

func _on_dots_changed(_value: float) -> void:
	dots.apply_config({"max_radius": max_radius.value, "gap": gap.value, "fill_percent": fill.value})


func _on_size_changed(value: float) -> void:
	ShapeView.side_fraction = value / 100
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
	var tray_rect := row.grow(TRAY_PADDING)
	tray.position = tray_rect.position
	tray.size = tray_rect.size


# ---------- Saving ----------

func _save() -> void:
	for result in [LevelConfig.save_levels(_levels()), dots.save_config(), dots.save_noise(), ColorGroups.save_settings(_groups), ShapeView.save_size()]:
		if result != OK:
			push_error("Could not save config: %s" % error_string(result))
