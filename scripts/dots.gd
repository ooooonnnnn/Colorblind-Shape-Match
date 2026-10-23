extends CanvasLayer
## Redraws the area rectangle, except the mask rectangle, as non-overlapping
## circles. Each circle shows the background color, or a figure color while a
## piece in that color is under its center, with its hue, saturation and value
## shifted by Perlin noise (see NOISE_PATH).
## The circles are packed once per area and mask position; which base color
## each one uses follows the screen live.

signal colors_changed  ## a base color was edited, e.g. in the inspector while running

const CONFIG_PATH := "res://dots.json"
const NOISE_PATH := "res://noise.json"
const ColorGroups := preload("res://scripts/color_groups.gd")
const MIN_RADIUS := 1.0     # px; spots that only fit a smaller circle are skipped
const DEFAULT_BOARD_COLOR := Color("dde6ef")  # a soft blue-gray, like the paper of a printed plate
## The plate-like starting point for CONFIG_PATH and NOISE_PATH, which the
## config page's reset goes back to. The noise is the same for figure and
## background, so only hue tells them apart.
const DEFAULT_CONFIG := {"max_radius": 6.0, "gap": 1.0, "fill_percent": 50.0}
const DEFAULT_NOISE := {
	"background": {
		"hue": {"wavelength": 10.0, "amplitude": 0.02},
		"saturation": {"wavelength": 10.0, "amplitude": 0.05},
		"value": {"wavelength": 10.0, "amplitude": 0.15},
	},
	"shapes": {
		"hue": {"wavelength": 10.0, "amplitude": 0.02},
		"saturation": {"wavelength": 10.0, "amplitude": 0.05},
		"value": {"wavelength": 10.0, "amplitude": 0.15},
	},
}
const CELL := 4.0          # px; side of the cells used to track where free space is left
const NOISE_PARTS := {"background": "background", "shapes": "shape"}  # NOISE_PATH key: shader uniform prefix
const NOISE_CHANNELS := ["hue", "saturation", "value"]

@export var area: Control  ## the part of the screen the circles fill
@export var mask: Control  ## stays clear of circles

@export_group("Colors")
## Shows between the dots, like the paper of a printed plate, and is the area's
## own color, so levels without the filter look the same. It is the same around
## figure and background dots, so it gives no cue to where a piece is.
@export var board_color := DEFAULT_BOARD_COLOR:
	set(v):
		board_color = v
		if is_node_ready():
			_show_board_color()
@export var background_color := Color("559c68")
## The colors pieces are filled with, at most ColorGroups.MAX_COLORS.
@export var figure_colors := PackedColorArray([Color("b59267"), Color("c98e67"), Color("db8b67"), Color("eb8767"), Color("fa8366")])
## The colors of the level's extra shapes, at most ColorGroups.MAX_EXTRA_COLORS.
@export var extra_colors := PackedColorArray()

var max_radius: float = DEFAULT_CONFIG.max_radius  # px
var gap: float = DEFAULT_CONFIG.gap                # px between neighbouring circles
var fill: float = DEFAULT_CONFIG.fill_percent / 100  # fraction of the area outside the mask to cover
## {part: {channel: {wavelength, amplitude}}} for each NOISE_PARTS key and NOISE_CHANNELS entry
var noise := {}

var _background := ColorRect.new()
var _circles := MultiMeshInstance2D.new()
var _packed_in := Rect2()   # the area rect the circles were packed into
var _packed_for := Rect2()  # the mask rect the circles were packed around
var _shown_colors := PackedColorArray()  # the base colors last given to the shader
var _fade: Tween


func _ready() -> void:
	layer = 100

	var bg_material := ShaderMaterial.new()
	bg_material.shader = preload("res://shaders/dot_background.gdshader")
	_background.material = bg_material
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var circle_material := ShaderMaterial.new()
	circle_material.shader = preload("res://shaders/dot_circle.gdshader")
	_circles.material = circle_material
	_circles.multimesh = MultiMesh.new()
	_circles.multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_circles.multimesh.use_custom_data = true
	_circles.multimesh.mesh = quad
	add_child(_circles)
	_load_config()
	_show_board_color()
	_load_noise()


func _load_config() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(SettingsFile.read_path(CONFIG_PATH)))
	if not data is Dictionary:
		push_error("Bad or missing dot config in %s" % CONFIG_PATH)
		data = {}
	apply_config(data)


## Takes {max_radius, gap, fill_percent, board_color}, as in CONFIG_PATH;
## missing keys keep their current value. The circles are repacked with the new
## settings.
func apply_config(data: Dictionary) -> void:
	max_radius = maxf(MIN_RADIUS, float(data.get("max_radius", max_radius)))
	gap = maxf(0.0, float(data.get("gap", gap)))
	fill = clampf(float(data.get("fill_percent", fill * 100)) / 100, 0.0, 1.0)
	board_color = Color.from_string(str(data.get("board_color", "")), board_color)
	_packed_in = Rect2()


## Paints the gaps and the area's own panel in board_color.
func _show_board_color() -> void:
	_background.material.set_shader_parameter("background", board_color)
	var panel := area.get_theme_stylebox("panel") if area else null
	if panel is StyleBoxFlat:
		var painted: StyleBoxFlat = panel.duplicate()
		painted.bg_color = board_color
		area.add_theme_stylebox_override("panel", painted)


func save_config() -> Error:
	var file := FileAccess.open(SettingsFile.write_path(CONFIG_PATH), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var data := {"max_radius": max_radius, "gap": gap, "fill_percent": snappedf(fill * 100, 0.01)}
	for key in data:
		if data[key] == int(data[key]):
			data[key] = int(data[key])  # keep whole numbers free of a trailing .0
	data.board_color = "#" + board_color.to_html(false)
	file.store_string(JSON.stringify(data, "\t", false) + "\n")
	return OK


func _load_noise() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(SettingsFile.read_path(NOISE_PATH)))
	if not data is Dictionary:
		push_error("Bad or missing noise config in %s" % NOISE_PATH)
		data = {}
	apply_noise(data)


## Takes the H, S and V noises' wavelength and amplitude, separately for the
## background and the shapes, shaped like NOISE_PATH; missing values keep their
## current one (wavelength 1, amplitude 0 at first). The circles show it at once.
func apply_noise(data: Dictionary) -> void:
	for part in NOISE_PARTS:
		var channels = data.get(part)
		if not channels is Dictionary:
			channels = {}
		if not noise.has(part):
			noise[part] = {}
		var wavelength := Vector3.ONE
		var amplitude := Vector3.ZERO
		for i in NOISE_CHANNELS.size():
			var channel: String = NOISE_CHANNELS[i]
			var current: Dictionary = noise[part].get(channel, {"wavelength": 1.0, "amplitude": 0.0})
			var given = channels.get(channel)
			if not given is Dictionary:
				given = {}
			wavelength[i] = maxf(1.0, float(given.get("wavelength", current.wavelength)))
			amplitude[i] = float(given.get("amplitude", current.amplitude))
			noise[part][channel] = {"wavelength": wavelength[i], "amplitude": amplitude[i]}
		_circles.material.set_shader_parameter(NOISE_PARTS[part] + "_wavelength", wavelength)
		_circles.material.set_shader_parameter(NOISE_PARTS[part] + "_amplitude", amplitude)


func save_noise() -> Error:
	var file := FileAccess.open(SettingsFile.write_path(NOISE_PATH), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var data := {}
	for part in NOISE_PARTS:
		data[part] = {}
		for channel in NOISE_CHANNELS:
			var wavelength: float = noise[part][channel].wavelength
			data[part][channel] = {
				# Keep whole numbers free of a trailing .0.
				"wavelength": int(wavelength) if wavelength == int(wavelength) else wavelength,
				"amplitude": snappedf(noise[part][channel].amplitude, 0.001),
			}
	file.store_string(JSON.stringify(data, "\t", false) + "\n")
	return OK


## Lets the shapes show plainly at first, then covers them with the dots over
## seconds. The circles still follow the screen all along, so they settle on
## the shapes as they come in.
func fade_in(seconds: float) -> void:
	if _fade:
		_fade.kill()
	_set_opacity(0.0)
	_fade = create_tween()
	_fade.tween_method(_set_opacity, 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _set_opacity(opacity: float) -> void:
	_background.material.set_shader_parameter("opacity", opacity)
	_circles.material.set_shader_parameter("opacity", opacity)


## Takes a color group's background and figure colors (see ColorGroups), and
## the level's extra-shape colors, if any.
func show_group(group: Dictionary, extra := PackedColorArray()) -> void:
	background_color = group.background
	figure_colors = PackedColorArray(group.colors)
	extra_colors = extra


## Figure color i, which a piece is filled with and its circles are based on.
func figure_color(i: int) -> Color:
	return figure_colors[i % figure_colors.size()]


## The background color, then the figure and extra-shape colors, padded to
## the shader's count with colors no screen pixel comes near.
func _base_colors() -> PackedColorArray:
	var colors := PackedColorArray([background_color])
	colors.append_array(figure_colors.slice(0, ColorGroups.MAX_COLORS))
	colors.append_array(extra_colors.slice(0, ColorGroups.MAX_EXTRA_COLORS))
	while colors.size() < ColorGroups.MAX_COLORS + ColorGroups.MAX_EXTRA_COLORS + 1:
		colors.append(Color(10, 10, 10))
	return colors


func _process(_delta: float) -> void:
	refresh()


## Brings the circles up to date with the colors and the area and mask rects
## right away. Call it after changing those, so the frame that shows the
## change never shows the old circles, which could leave a piece uncovered.
func refresh() -> void:
	if _base_colors() != _shown_colors:
		_shown_colors = _base_colors()
		_circles.material.set_shader_parameter("bases", _shown_colors)
		colors_changed.emit()
	var area_rect := area.get_global_rect() if area else get_viewport().get_visible_rect()
	var mask_rect := mask.get_global_rect() if mask else Rect2()
	if area_rect == _packed_in and mask_rect == _packed_for:
		return
	_packed_in = area_rect
	_packed_for = mask_rect
	var size := area_rect.size
	# From here on both are relative to the area's top-left corner.
	mask_rect = Rect2(mask_rect.position - area_rect.position, mask_rect.size).intersection(Rect2(Vector2.ZERO, size))
	_background.position = area_rect.position
	_background.size = size
	_background.material.set_shader_parameter("mask_rect",
			Vector4(mask_rect.position.x / size.x, mask_rect.position.y / size.y,
					mask_rect.size.x / size.x, mask_rect.size.y / size.y))
	_background.material.set_shader_parameter("area_size", size)
	var mask_style := mask.get_theme_stylebox("panel") if mask else null
	_background.material.set_shader_parameter("mask_radius", mask_style.corner_radius_top_left if mask_style is StyleBoxFlat else 0.0)
	_circles.position = area_rect.position
	_show(_pack(size, mask_rect))


## Circles as (x, y, radius), placed one at a time at random free spots, each
## as large as fits, until they cover the fill fraction of the area outside mask_rect.
func _pack(screen: Vector2, mask_rect: Rect2) -> PackedVector3Array:
	var circles := PackedVector3Array()
	var valid_area := screen.x * screen.y - mask_rect.get_area()
	var target := fill * valid_area
	var covered := 0.0
	var mask_center := mask_rect.get_center()
	var mask_half := mask_rect.size / 2

	# Any circle that can touch a new one has its center within reach of it,
	# so only the 3x3 grid cells around a candidate need checking.
	var reach := 2 * max_radius + gap
	var cols := ceili(screen.x / reach)
	var rows := ceili(screen.y / reach)
	var grid: Array[PackedInt32Array] = []
	grid.resize(cols * rows)

	# Candidates are drawn from small cells whose centers are not yet covered
	# by a circle plus its gap, so draws rarely land on taken space.
	var free_cols := ceili(screen.x / CELL)
	var free_rows := ceili(screen.y / CELL)
	var free := PackedInt32Array()      # ids of free cells, in no order
	var slot := PackedInt32Array()      # each cell's index in free, or -1
	slot.resize(free_cols * free_rows)
	for id in slot.size():
		var center := (Vector2(id % free_cols, id / free_cols) + Vector2.ONE * 0.5) * CELL
		if mask_rect.has_point(center):
			slot[id] = -1
		else:
			slot[id] = free.size()
			free.append(id)

	while covered < target and not free.is_empty():
		var id := free[randi() % free.size()]
		var p := (Vector2(id % free_cols, id / free_cols) + Vector2(randf(), randf())) * CELL
		p = p.min(screen)
		var r := -1.0
		if not mask_rect.has_point(p):
			var to_mask := ((p - mask_center).abs() - mask_half).max(Vector2.ZERO).length()
			r = minf(max_radius, minf(to_mask, minf(minf(p.x, screen.x - p.x), minf(p.y, screen.y - p.y))))
			var col := int(p.x / reach)
			var row := int(p.y / reach)
			for y in range(maxi(row - 1, 0), mini(row + 2, rows)):
				for x in range(maxi(col - 1, 0), mini(col + 2, cols)):
					for i in grid[y * cols + x]:
						var c := circles[i]
						r = minf(r, p.distance_to(Vector2(c.x, c.y)) - c.z - gap)
		if r < MIN_RADIUS:
			_take(id, free, slot)
			continue
		grid[mini(int(p.y / reach), rows - 1) * cols + mini(int(p.x / reach), cols - 1)].append(circles.size())
		circles.append(Vector3(p.x, p.y, r))
		covered += PI * r * r
		# Retire the cells this circle and its gap now cover.
		var blocked := r + gap
		for y in range(maxi(floori((p.y - blocked) / CELL), 0), mini(ceili((p.y + blocked) / CELL), free_rows)):
			for x in range(maxi(floori((p.x - blocked) / CELL), 0), mini(ceili((p.x + blocked) / CELL), free_cols)):
				var cell := y * free_cols + x
				if slot[cell] >= 0 and ((Vector2(x, y) + Vector2.ONE * 0.5) * CELL).distance_to(p) < blocked:
					_take(cell, free, slot)

	if covered < target:
		push_warning("Dots covered %d%% of the area, short of %d%%" % [roundi(covered / valid_area * 100), roundi(fill * 100)])
	return circles


## Removes cell id from free in constant time.
func _take(id: int, free: PackedInt32Array, slot: PackedInt32Array) -> void:
	var i := slot[id]
	var last := free[free.size() - 1]
	free[i] = last
	slot[last] = i
	free.resize(free.size() - 1)
	slot[id] = -1


func _show(circles: PackedVector3Array) -> void:
	var mm := _circles.multimesh
	mm.instance_count = circles.size()
	for i in circles.size():
		var c := circles[i]
		mm.set_instance_transform_2d(i, Transform2D(0, Vector2.ONE * c.z * 2, 0, Vector2(c.x, c.y)))
		mm.set_instance_custom_data(i, Color(c.x, c.y, 0, 0))  # center, for the noise
