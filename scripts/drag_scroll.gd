class_name DragScroll
extends Node
## Lets a finger (or the mouse) scroll a ScrollContainer by dragging anywhere
## on it, as expected on a tablet. ScrollContainer only scrolls from drags that
## reach it, and the cards, pictures and controls inside stop them, so presses
## are sorted out here first, in _input.
##
## A press on the scroll is held back until it shows what it is:
## - moving mostly sideways on a slider hands the press to the slider, which
##   then drags as usual;
## - any other move past the slop scrolls, and the press never reaches the
##   control under it, so scrolling never changes a setting or opens anything;
## - letting go within the slop is a tap, handed on to the control as if the
##   press had never been held.
## The slop is a physical distance, so a wobbly tap on a dense tablet screen
## still counts as a tap.
##
## The mouse wheel scrolls too, wherever the pointer is on the scroll; it never
## reaches the controls, so turning it over a slider does not change the slider.

const SLOP_INCHES := 0.1   # how far a tap may wander, about 2.5 mm
const MIN_SLOP := 12.0     # px, so a mouse needs a deliberate drag too

enum {DECIDING, SCROLLING, PASSING}

var target: Callable  ## returns the ScrollContainer to drag right now, or null

var _drag := {}  # {scroll, press, start, from, slider, mode} from a press until it is let go
var _replaying := false  # true while held-back events are sent on, so _input lets them by


func _input(event: InputEvent) -> void:
	if _replaying:
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var scroll := _scroll_at(event.position)
		if scroll:
			get_viewport().set_input_as_handled()
			if event.pressed:
				# The same step ScrollContainer takes for a wheel notch.
				var bar := scroll.get_v_scroll_bar()
				var step: float = bar.page / 8.0 * (event.factor if event.factor > 0 else 1.0)
				bar.value += step if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -step
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var scroll := _scroll_at(event.position)
			if scroll and not scroll.get_v_scroll_bar().get_global_rect().has_point(event.position):
				_drag = {"scroll": scroll, "press": event, "start": event.position, "from": scroll.scroll_vertical,
						"slider": _slider_at(scroll, event.position), "mode": DECIDING}
				get_viewport().set_input_as_handled()
		elif not _drag.is_empty():
			if _drag.mode == DECIDING:  # a tap
				get_viewport().set_input_as_handled()
				_replay.call_deferred([_drag.press, event])
			elif _drag.mode == SCROLLING:  # nothing below saw the press
				get_viewport().set_input_as_handled()
			_drag = {}
	elif event is InputEventMouseMotion and not _drag.is_empty():
		var moved: Vector2 = event.position - _drag.start
		match _drag.mode:
			DECIDING:
				get_viewport().set_input_as_handled()
				if moved.length() < _slop():
					return
				if _drag.slider and absf(moved.x) > absf(moved.y):
					_drag.mode = PASSING
					_replay.call_deferred([_drag.press, event])
				else:
					_drag.mode = SCROLLING
					_drag.start = event.position  # scroll from here, without a jump
					_drag.from = _drag.scroll.scroll_vertical
			SCROLLING:
				get_viewport().set_input_as_handled()
				_drag.scroll.scroll_vertical = int(_drag.from - moved.y)


## The scroll to work on, if pos is on it.
func _scroll_at(pos: Vector2) -> ScrollContainer:
	var scroll: ScrollContainer = target.call() if target.is_valid() else null
	if scroll and scroll.is_visible_in_tree() and scroll.get_global_rect().has_point(pos):
		return scroll
	return null


## The slop in this viewport's pixels.
func _slop() -> float:
	var to_screen := get_viewport().get_final_transform().get_scale().x
	return maxf(MIN_SLOP, DisplayServer.screen_get_dpi() * SLOP_INCHES / maxf(to_screen, 0.01))


func _slider_at(scroll: ScrollContainer, pos: Vector2) -> Slider:
	for node in scroll.find_children("*", "Slider", true, false):
		if node.is_visible_in_tree() and node.get_global_rect().has_point(pos):
			return node
	return null


## Sends held-back events on to the controls, past _input.
func _replay(events: Array) -> void:
	_replaying = true
	for e in events:
		get_viewport().push_input(e, true)
	_replaying = false
