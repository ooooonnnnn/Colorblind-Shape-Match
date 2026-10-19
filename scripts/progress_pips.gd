class_name ProgressPips
extends Control
## How far the level has come, as a row of empty circles that each turn into a
## star as a piece is placed: a concrete count instead of an abstract bar.

const EMPTY := Color(0.231373, 0.184314, 0.290196, 0.35)  # Icons.INK, faded
const STAR := Color("ffd166")
const MAX_PIP := 34.0  # px, the largest a pip grows when there is room

var total := 0:
	set(v):
		total = v
		done = 0
		queue_redraw()
var done := 0:
	set(v):
		done = v
		queue_redraw()

var _pops := {}  # pip index: its pop-in scale while animating


## Turns the next pip into a star with a little spring.
func add_one() -> void:
	var i := done
	done += 1
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_method(func(s: float):
		_pops[i] = s
		queue_redraw()
	, 0.3, 1.0, 0.3)
	t.tween_callback(func(): _pops.erase(i))


func _draw() -> void:
	if total <= 0:
		return
	var pip := minf(MAX_PIP, minf(size.y, size.x / total / 1.25))
	var step := pip * 1.25
	var x0 := (size.x - step * (total - 1)) / 2
	for i in total:
		var c := Vector2(x0 + step * i, size.y / 2)
		if i < done:
			var s: float = _pops.get(i, 1.0)
			Icons.draw(self, "star", c, pip * s, STAR)
		else:
			draw_arc(c, pip * 0.3, 0, TAU, 24, EMPTY, maxf(2.0, pip * 0.1), true)
