extends Control
## Edits the level sequences (LevelConfig), the dot filter (dots.json), the dot
## color noise (noise.json) and the shape size (shape_size.json). The preview
## shows all but the levels live; nothing is written until Save.

const Dots := preload("res://scripts/dots.gd")
const PREVIEW_SHAPES := ["square", "star", "crescent"]
const PREVIEW_SPACING := 16.0  # px between neighbouring preview shapes
const TRAY_PADDING := 24.0     # px between the holes and the tray edge, as in the game
const NEW_LEVEL := {"duration": 30.0, "holes": 3, "shapes": 3, "repetitions": 1, "filter": true}

@onready var levels_grid: GridContainer = %Levels
@onready var add_level: Button = %AddLevel
@onready var max_radius: SpinBox = %MaxRadius
@onready var gap: SpinBox = %Gap
@onready var fill: SpinBox = %Fill
@onready var noise_grid: GridContainer = %Noise
@onready var size_spin: SpinBox = %Size
@onready var back: Button = %Back
@onready var save: Button = %Save
@onready var preview: Panel = %Preview
@onready var tray: Panel = %Tray
@onready var dots: Dots = $Dots

var _rows: Array[Dictionary] = []  # each level sequence's controls, by field
var _noise_spins := {}  # {part: {channel: {wavelength, amplitude}}} of SpinBoxes, as in Dots.noise
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

	_build_preview()
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


# ---------- Preview ----------

func _on_dots_changed(_value: float) -> void:
	dots.apply_config({"max_radius": max_radius.value, "gap": gap.value, "fill_percent": fill.value})


func _on_size_changed(value: float) -> void:
	ShapeView.side_fraction = value / 100
	_layout_preview()


func _build_preview() -> void:
	for shape_name in PREVIEW_SHAPES:
		var shape := {"name": shape_name, "points": Shapes.make(shape_name)}
		for piece in [false, true]:
			var view := ShapeView.new()
			view.setup(shape, piece)
			view.focus_mode = Control.FOCUS_NONE
			view.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if piece:
				view.fill = dots.shape_color(shape_name)
				_pieces.append(view)
			else:
				_holes.append(view)
			preview.add_child(view)
	preview.resized.connect(_layout_preview)
	_layout_preview()


## Holes in a row inside the tray, with their pieces in a row below.
func _layout_preview() -> void:
	var board := preview.size
	if board.x <= 0 or board.y <= 0:
		return
	var side := ShapeView.side_for(board)
	var step := side + PREVIEW_SPACING
	var first_x := board.x / 2 - step * (PREVIEW_SHAPES.size() - 1) / 2
	var holes_y := board.y * 0.3
	for i in PREVIEW_SHAPES.size():
		var x := first_x + step * i
		_holes[i].norm_pos = Vector2(x, holes_y) / board
		_pieces[i].norm_pos = Vector2(x, board.y * 0.75) / board
	var row := Rect2(first_x - side / 2, holes_y - side / 2, step * PREVIEW_SHAPES.size() - PREVIEW_SPACING, side)
	var tray_rect := row.grow(TRAY_PADDING)
	tray.position = tray_rect.position
	tray.size = tray_rect.size


# ---------- Saving ----------

func _save() -> void:
	for result in [LevelConfig.save_levels(_levels()), dots.save_config(), dots.save_noise(), ShapeView.save_size()]:
		if result != OK:
			push_error("Could not save config: %s" % error_string(result))
