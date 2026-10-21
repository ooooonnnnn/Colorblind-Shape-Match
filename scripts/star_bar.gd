class_name StarBar
extends Control
## How far the level has come, as a bar across the top split into one cell per
## piece to place. Each cell shows the star it holds; placing a piece sweeps
## the next cell full of yellow and makes its star pop.

const FILL := Color("ffd166")    # sunny yellow, as the timer bar
const STAR := Color("ff9f43")    # warmer orange, so a won star shows on the yellow
const WAITING := 0.45            # alpha of a star still to be won
const DIVIDER := 2.0             # px, the lines between cells
const SWEEP := 0.25              # seconds for the yellow to cross a cell

var total := 0:
	set(v):
		total = v
		_filled.clear()
		_pops.clear()
		queue_redraw()

var _filled: Array[float] = []  # how full each won cell is, 0 to 1
var _pops := {}  # cell index: its star's pop scale while animating
var _bg := StyleBoxFlat.new()
var _fill := StyleBoxFlat.new()
var _border: StyleBoxFlat


func _init() -> void:
	_bg.bg_color = Color(1, 1, 1, 0.6)
	_bg.set_border_width_all(2)
	_bg.border_color = Icons.INK
	_bg.set_corner_radius_all(18)
	_fill.bg_color = FILL
	_border = _bg.duplicate()
	_border.draw_center = false


## Fills the next cell, then pops its star with a little spring.
func add_one() -> void:
	if _filled.size() >= total:
		return
	var i := _filled.size()
	_filled.append(0.0)
	var t := create_tween()
	t.tween_method(func(f: float):
		_filled[i] = f
		queue_redraw()
	, 0.0, 1.0, SWEEP).set_trans(Tween.TRANS_SINE)
	t.tween_method(func(s: float):
		_pops[i] = s
		queue_redraw()
	, 0.6, 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func(): _pops.erase(i))


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_style_box(_bg, rect)
	if total <= 0:
		return
	var cell := size.x / total
	var r := _bg.corner_radius_top_left
	for i in _filled.size():
		# Only the end cells take the bar's round corners.
		_fill.corner_radius_top_left = r if i == 0 else 0
		_fill.corner_radius_bottom_left = r if i == 0 else 0
		var last := i == total - 1 and _filled[i] >= 1.0
		_fill.corner_radius_top_right = r if last else 0
		_fill.corner_radius_bottom_right = r if last else 0
		draw_style_box(_fill, Rect2(cell * i, 0, cell * _filled[i], size.y).grow(-1))
	for i in range(1, total):
		draw_line(Vector2(cell * i, 0), Vector2(cell * i, size.y), Icons.INK, DIVIDER)
	draw_style_box(_border, rect)  # the border again, over the yellow
	var star := minf(size.y * 0.7, cell * 0.7)
	for i in total:
		var c := Vector2(cell * (i + 0.5), size.y / 2)
		if i < _filled.size() and _filled[i] >= 1.0:
			Icons.draw(self, "star", c, star * _pops.get(i, 1.0) * 1.1, STAR)
		else:
			var faded := FILL
			faded.a = WAITING
			Icons.draw(self, "star", c, star * 0.85, faded)
