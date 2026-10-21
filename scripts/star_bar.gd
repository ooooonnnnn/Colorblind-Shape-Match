class_name StarBar
extends Control
## How far the level has come, as a meter across the top split into a step per
## piece, filling from the right toward a big star at its left end. Each placed
## piece fills it smoothly a step further, once the stars streaming from the
## piece arrive (see Effects.stream_stars); when it is full the star lights up,
## ready for main.gd to send it flying (see Effects.cheer) as the level is won.

const FILL := Color("ffd166")    # sunny yellow, as the timer bar
const UNLIT := Color(1, 1, 1, 0.55)  # the star before the meter reaches it
const DIVIDER := Color(0.231373, 0.184314, 0.290196, 0.45)  # Icons.INK, faded
const TRACK := 0.56              # the meter's height, as a fraction of the bar's
const STAR := 1.45               # the star's side, as a fraction of the bar's height
const FILL_TIME := 0.3           # seconds for the meter to fill a step
const BUMP := 0.22               # how much taller the meter swells as a step fills, at most
const WIGGLE_EVERY := 1.1        # seconds between the star's wiggles when one step is left

var total := 0:
	set(v):
		total = v
		_done = 0
		_filling = 0
		_shown = 0.0
		_lit = 0.0
		_flash = 0.0
		_taken = false
		_level += 1
		if _tween:
			_tween.kill()
		queue_redraw()

var _done := 0  # steps promised by add_one, some perhaps still waiting to fill
var _filling := 0  # the step filling now, from 1, which the gleam covers
var _level := 0  # counts levels, so a fill still waiting from the last one is dropped
var _shown := 0.0:  # the meter's drawn fill, 0 to 1, easing after _filling
	set(v):
		_shown = v
		queue_redraw()
var _lit := 0.0:  # 0 unlit, 1 lit; overshoots a little as the star pops on
	set(v):
		_lit = v
		queue_redraw()
var _flash := 0.0:  # a white gleam over the step just filled, fading out
	set(v):
		_flash = v
		queue_redraw()
var _bump := 0.0:  # 0 at rest, 1 at the top of the swell as a step fills
	set(v):
		_bump = v
		queue_redraw()
var _taken := false  # the star has flown off to cheer
var _tween: Tween
var _bg := StyleBoxFlat.new()
var _fill := StyleBoxFlat.new()


func _init() -> void:
	_bg.bg_color = Color(1, 1, 1, 0.75)
	_bg.set_corner_radius_all(99)
	_fill.bg_color = FILL
	_fill.set_corner_radius_all(99)


## Where on screen the next step to fill is, for stars to fly to.
func next_spot() -> Vector2:
	var track := _track()
	var x := track.end.x - track.size.x * (_done + 0.5) / maxi(total, 1)
	return get_global_transform() * Vector2(x, size.y / 2)


## Fills the meter one step further after delay seconds, with a gleam over the
## new step; the last one lights the star.
## Each step waits on its own timer, so quick placements still fill one by one.
func add_one(delay := 0.0) -> void:
	if _done >= total:
		return
	_done += 1
	get_tree().create_timer(delay).timeout.connect(_fill_to.bind(_done, _level))


func _fill_to(step: int, level: int) -> void:
	if level != _level:
		return
	_filling = step
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_shown", float(step) / total, FILL_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "_flash", 0.0, FILL_TIME * 2).from(0.8)
	_tween.parallel().tween_property(self, "_bump", 0.0, FILL_TIME * 1.5).from(1.0).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if step == total:
		_tween.tween_property(self, "_lit", 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The star's center on screen and its side, where a flying star starts.
func star_spot() -> Rect2:
	var side := size.y * STAR
	var center := get_global_transform() * Vector2(side / 2, size.y / 2)
	return Rect2(center - Vector2.ONE * side / 2, Vector2.ONE * side)


## Hides the star, which has flown off; the next level's total brings it back.
func take_star() -> void:
	_taken = true
	queue_redraw()


## With one step left the star wiggles now and then, waiting to be won.
func _process(_delta: float) -> void:
	if _almost():
		queue_redraw()


func _almost() -> bool:
	return total > 1 and _filling == total - 1 and not _taken


## The meter, which starts under the middle of the star, so filling it reaches the star.
func _track() -> Rect2:
	var side := size.y * STAR
	var h := size.y * TRACK
	return Rect2(side / 2, (size.y - h) / 2, size.x - side / 2, h)


func _draw() -> void:
	# The meter swells taller about its middle line as a step fills.
	draw_set_transform(Vector2(0, -size.y / 2 * BUMP * _bump), 0, Vector2(1, 1 + BUMP * _bump))
	var track := _track()
	var h := track.size.y
	var shadow := _bg.duplicate()
	shadow.bg_color = Color(Icons.INK, 0.15)
	draw_style_box(shadow, Rect2(track.position + Vector2(0, 3), track.size))
	draw_style_box(_bg, track)
	if _shown > 0:
		var w := maxf(track.size.x * _shown, h)
		var fill := Rect2(track.end.x - w, track.position.y, w, h).grow(-3)
		draw_style_box(_fill, fill)
		# A glossy band along the top of the fill.
		var gloss := _fill.duplicate()
		gloss.bg_color = Color(1, 1, 1, 0.4)
		draw_style_box(gloss, Rect2(fill.position + Vector2(h * 0.3, fill.size.y * 0.12), Vector2(maxf(fill.size.x - h * 0.6, 0), fill.size.y * 0.3)))
		if _flash > 0 and _filling > 0:
			# The gleam covers the step filling now, as far as the fill has reached into it.
			var step := track.size.x / total
			var left := maxf(fill.position.x, track.end.x - step * _filling)
			var right := minf(fill.end.x, track.end.x - step * (_filling - 1))
			if right > left:
				draw_rect(Rect2(left, fill.position.y, right - left, fill.size.y), Color(1, 1, 1, _flash * 0.6))
	for i in range(1, total):
		var x := track.end.x - track.size.x * i / total
		draw_line(Vector2(x, track.position.y + 4), Vector2(x, track.end.y - 4), DIVIDER, 2.0)
	var border := StyleBoxFlat.new()  # drawn last, over the fill
	border.set_corner_radius_all(99)
	border.draw_center = false
	border.set_border_width_all(3)
	border.border_color = Icons.INK
	draw_style_box(border, track)
	draw_set_transform(Vector2.ZERO)
	if _taken:
		return
	var side := size.y * STAR
	var center := Vector2(side / 2, size.y / 2)
	var pop := 1.0 + 0.15 * sin(clampf(_lit, 0, 1) * PI)  # swells as it lights, then settles
	var turn := 0.0
	if _almost():
		# A quick wobble at the start of each WIGGLE_EVERY, still the rest of the time.
		var t := fmod(Time.get_ticks_msec() / 1000.0, WIGGLE_EVERY)
		turn = sin(t * 28.0) * 0.22 * maxf(0.0, 1.0 - t / 0.45)
		pop *= 1.0 + 0.08 * maxf(0.0, 1.0 - t / 0.45)
	draw_set_transform(center, turn, Vector2.ONE * pop)
	Effects.draw_star(self, Vector2.ZERO, side, UNLIT.lerp(FILL, clampf(_lit, 0, 1)), _lit >= 1)
	draw_set_transform(Vector2.ZERO)
