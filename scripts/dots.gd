extends CanvasLayer
## Redraws the area rectangle, except the mask rectangle, as non-overlapping
## circles. Each circle gets a random shade (from ArtManager) of the background
## color, or of a shape's color while that shape's piece is under its center.
## The circles are packed once per area and mask position; which base color
## each one uses follows the screen live.

signal colors_changed  ## a base color was edited, e.g. in the inspector while running

const ArtManager := preload("res://scripts/ArtManager.gd")
const CONFIG_PATH := "res://dots.json"
const MIN_RADIUS := 1.0     # px; spots that only fit a smaller circle are skipped
const CELL := 4.0          # px; side of the cells used to track where free space is left
const SHADE_COLUMNS := 2048  # circles per row of the shade texture; must match dot_circle.gdshader

@export var area: Control  ## the part of the screen the circles fill
@export var mask: Control  ## stays clear of circles

@export_group("Colors")
@export var background_color := Color("2ecc71")
@export var square_color := Color("e74c3c")
@export var circle_color := Color("e67e22")
@export var triangle_color := Color("f1c40f")
@export var star_color := Color("3498db")
@export var kite_color := Color("9b59b6")
@export var crescent_color := Color("e84393")

var max_radius := 14.0  # px
var gap := 3.0          # px between neighbouring circles
var fill := 0.5         # fraction of the area outside the mask to cover

var _background := ColorRect.new()
var _circles := MultiMeshInstance2D.new()
var _packed_in := Rect2()   # the area rect the circles were packed into
var _packed_for := Rect2()  # the mask rect the circles were packed around
var _shaded_for := PackedColorArray()  # the base colors the shades were picked from


func _ready() -> void:
	layer = 100
	_load_config()

	var bg_material := ShaderMaterial.new()
	bg_material.shader = preload("res://shaders/dot_background.gdshader")
	bg_material.set_shader_parameter("background", ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color"))
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
	_circles.multimesh.mesh = quad
	add_child(_circles)


func _load_config() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not data is Dictionary:
		push_error("Bad or missing dot config in %s" % CONFIG_PATH)
		data = {}
	max_radius = maxf(MIN_RADIUS, float(data.get("max_radius", max_radius)))
	gap = maxf(0.0, float(data.get("gap", gap)))
	fill = clampf(float(data.get("fill_percent", fill * 100)) / 100, 0.0, 1.0)


## The color pieces of this shape are filled with, and the base for their circles.
func shape_color(shape_name: String) -> Color:
	return get(shape_name + "_color")


## The background color, then each shape's color in Shapes.NAMES order.
func _base_colors() -> PackedColorArray:
	var colors := PackedColorArray([background_color])
	for shape_name in Shapes.NAMES:
		colors.append(shape_color(shape_name))
	return colors


func _process(_delta: float) -> void:
	if _base_colors() != _shaded_for:
		_shade(_circles.multimesh.instance_count)
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
	_circles.position = area_rect.position
	var circles := _pack(size, mask_rect)
	_show(circles)
	_shade(circles.size())


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


## Picks every circle's shade of every base color, and gives the shader the
## bases so it can tell which shape, if any, is under a circle.
func _shade(count: int) -> void:
	var bases := _base_colors()
	_shaded_for = bases
	var image := Image.create_empty(SHADE_COLUMNS * bases.size(), maxi(1, ceili(count / float(SHADE_COLUMNS))), false, Image.FORMAT_RGBA8)
	for i in count:
		for j in bases.size():
			image.set_pixel((i % SHADE_COLUMNS) * bases.size() + j, i / SHADE_COLUMNS, ArtManager.get_random_background_color(bases[j]))
	_circles.material.set_shader_parameter("shades", ImageTexture.create_from_image(image))
	_circles.material.set_shader_parameter("bases", bases)


func _show(circles: PackedVector3Array) -> void:
	var mm := _circles.multimesh
	mm.instance_count = circles.size()
	for i in circles.size():
		var c := circles[i]
		mm.set_instance_transform_2d(i, Transform2D(0, Vector2.ONE * c.z * 2, 0, Vector2(c.x, c.y)))
