class_name StarBar
extends Control
## How far the level has come, as a meter across the top that runs into a big
## star at its end. Each placed piece fills it smoothly a step further; when it
## is full the star lights up, ready for main.gd to send it flying (see
## Effects.cheer) as the level is won.

const FILL := Color("ffd166")    # sunny yellow, as the timer bar
const UNLIT := Color(1, 1, 1, 0.55)  # the star before the meter reaches it
const TRACK := 0.5               # the meter's height, as a fraction of the bar's
const STAR := 1.45               # the star's side, as a fraction of the bar's height
const FILL_TIME := 0.4           # seconds for the meter to catch up after a placement

var total := 0:
	set(v):
		total = v
		_done = 0
		_shown = 0.0
		_lit = 0.0
		_taken = false
		if _tween:
			_tween.kill()
		queue_redraw()

var _done := 0
var _shown := 0.0:  # the meter's drawn fill, 0 to 1, easing after _done
	set(v):
		_shown = v
		queue_redraw()
var _lit := 0.0:  # 0 unlit, 1 lit; overshoots a little as the star pops on
	set(v):
		_lit = v
		queue_redraw()
var _taken := false  # the star has flown off to cheer
var _tween: Tween
var _bg := StyleBoxFlat.new()
var _fill := StyleBoxFlat.new()


func _init() -> void:
	_bg.bg_color = Color(1, 1, 1, 0.6)
	_bg.set_border_width_all(2)
	_bg.border_color = Icons.INK
	_bg.set_corner_radius_all(99)
	_fill.bg_color = FILL
	_fill.set_corner_radius_all(99)


## Eases the meter one piece further; the last one lights the star.
func add_one() -> void:
	if _done >= total:
		return
	_done += 1
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_shown", float(_done) / total, FILL_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _done == total:
		_tween.tween_property(self, "_lit", 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The star's center on screen and its side, where a flying star starts.
func star_spot() -> Rect2:
	var side := size.y * STAR
	var center := get_global_transform() * Vector2(size.x - side / 2, size.y / 2)
	return Rect2(center - Vector2.ONE * side / 2, Vector2.ONE * side)


## Hides the star, which has flown off; the next level's total brings it back.
func take_star() -> void:
	_taken = true
	queue_redraw()


func _draw() -> void:
	var side := size.y * STAR
	var h := size.y * TRACK
	# The meter ends under the middle of the star, so filling it reaches the star.
	var track := Rect2(0, (size.y - h) / 2, size.x - side / 2, h)
	draw_style_box(_bg, track)
	if _shown > 0:
		var w := maxf(track.size.x * _shown, h)
		draw_style_box(_fill, Rect2(track.position, Vector2(w, h)).grow(-2))
	if _taken:
		return
	var center := Vector2(size.x - side / 2, size.y / 2)
	var pop := 1.0 + 0.15 * sin(clampf(_lit, 0, 1) * PI)  # swells as it lights, then settles
	Effects.draw_star(self, center, side * pop, UNLIT.lerp(FILL, clampf(_lit, 0, 1)), _lit >= 1)
