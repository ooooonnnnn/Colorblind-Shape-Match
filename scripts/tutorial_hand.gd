class_name TutorialHand
extends Control
## A pointing hand that shows how to play the tutorial level, over and over
## until it is freed: it carries a faded copy of the piece into its hole when
## pieces can be dragged, or otherwise taps the piece, vanishes, and appears
## over the hole to tap it, so it never looks like a drag. Its
## fingertip is at its position, which follows norm_pos on the board.

const FILL := Color.WHITE
const PRESSED := 0.85  # the hand's scale while pressing
const SIZE := 0.8      # the hand's height as a fraction of a piece's side
const GHOST_LIGHTEN := 0.55  # how much lighter the carried copy of the piece is

var norm_pos := Vector2.ZERO:
	set(v):
		norm_pos = v
		_update_layout()
var press := 0.0:  # 0 up, 1 pressed: shrinks the hand and rings the fingertip
	set(v):
		press = v
		queue_redraw()

var _ghost: ShapeView


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 4
	get_parent().resized.connect(_update_layout)
	_update_layout()


func _exit_tree() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()


func _update_layout() -> void:
	var board := get_parent() as Control
	if board:
		position = norm_pos * board.size
		queue_redraw()


## Loops the demonstration of moving a piece of shape (see Shapes.pick) and
## fill from board-relative from to to.
func play(shape: Dictionary, fill: Color, from: Vector2, to: Vector2, drag: bool) -> void:
	norm_pos = from
	modulate.a = 0.0
	var t := create_tween().set_loops()
	t.tween_callback(func(): norm_pos = from)
	t.tween_property(self, "modulate:a", 1.0, 0.3)
	if drag:
		_ghost = ShapeView.new()
		_ghost.setup(shape, true)
		# Solid and lighter rather than see-through, as the overlapping strokes
		# of a see-through outline would show darker where they meet.
		_ghost.fill = fill.lerp(Color.WHITE, GHOST_LIGHTEN)
		_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ghost.focus_mode = Control.FOCUS_NONE
		_ghost.z_index = 3
		_ghost.visible = false
		get_parent().add_child(_ghost)
		t.tween_callback(func(): _ghost.norm_pos = from)
		t.tween_property(self, "press", 1.0, 0.15)
		t.tween_callback(func(): _ghost.visible = true)
		t.tween_interval(0.15)
		t.tween_property(self, "norm_pos", to, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.parallel().tween_property(_ghost, "norm_pos", to, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_callback(func(): _ghost.visible = false)
		t.tween_property(self, "press", 0.0, 0.15)
	else:
		_tap(t)
		t.tween_interval(0.25)
		t.tween_property(self, "modulate:a", 0.0, 0.12)
		t.tween_interval(0.25)
		t.tween_callback(func(): norm_pos = to)
		t.tween_property(self, "modulate:a", 1.0, 0.12)
		t.tween_interval(0.15)
		_tap(t)
		t.tween_interval(0.3)
	t.tween_property(self, "modulate:a", 0.0, 0.3)
	t.tween_interval(0.5)


func _tap(t: Tween) -> void:
	t.tween_property(self, "press", 1.0, 0.12)
	t.tween_property(self, "press", 0.0, 0.18)


func _draw() -> void:
	var board := get_parent() as Control
	if board:
		draw_hand(self, Vector2.ZERO, ShapeView.side_for(board.size) * SIZE / 100, press)


## A white hand with an ink outline, pointing up with its fingertip at tip,
## about 100 units tall; press 0..1 shrinks it toward the tip and rings it.
static func draw_hand(canvas: CanvasItem, tip: Vector2, unit: float, press := 0.0) -> void:
	if press > 0:
		canvas.draw_arc(tip, unit * (10 + 14 * press), 0, TAU, 32, Color(Icons.INK, 0.6 * press), maxf(2.0, unit * 3), true)
	var scale := unit * (1.0 - (1.0 - PRESSED) * press)
	canvas.draw_set_transform(tip, -0.3, Vector2(scale, scale))
	var outline := 5.0  # in units
	# The outline pass draws every part grown by outline in ink; the fill pass
	# then covers the insides, leaving one outline around the whole hand.
	for pass_grow in [outline, 0.0]:
		var color: Color = Icons.INK if pass_grow > 0 else FILL
		_capsule(canvas, Vector2(0, 8), Vector2(0, 52), 8 + pass_grow, color)      # index finger
		_capsule(canvas, Vector2(15, 40), Vector2(15, 62), 7.5 + pass_grow, color)  # folded fingers
		_capsule(canvas, Vector2(28, 44), Vector2(28, 64), 7 + pass_grow, color)
		_capsule(canvas, Vector2(39, 50), Vector2(39, 66), 6 + pass_grow, color)
		_capsule(canvas, Vector2(-6, 74), Vector2(-20, 58), 8 + pass_grow, color)   # thumb
		_round_rect(canvas, Rect2(-8, 54, 53, 44), 14, pass_grow, color)            # palm
	for x in [7.5, 21.5, 33.5]:
		canvas.draw_line(Vector2(x, 46), Vector2(x, 60), Icons.INK, 2.5, true)
	canvas.draw_set_transform(Vector2.ZERO)


static func _capsule(canvas: CanvasItem, a: Vector2, b: Vector2, r: float, color: Color) -> void:
	canvas.draw_line(a, b, color, r * 2)
	canvas.draw_circle(a, r, color)
	canvas.draw_circle(b, r, color)


static func _round_rect(canvas: CanvasItem, rect: Rect2, r: float, grow: float, color: Color) -> void:
	rect = rect.grow(grow)
	r += grow
	canvas.draw_rect(Rect2(rect.position.x + r, rect.position.y, rect.size.x - 2 * r, rect.size.y), color)
	canvas.draw_rect(Rect2(rect.position.x, rect.position.y + r, rect.size.x, rect.size.y - 2 * r), color)
	for corner in [rect.position + Vector2(r, r), Vector2(rect.end.x - r, rect.position.y + r),
			Vector2(rect.position.x + r, rect.end.y - r), rect.end - Vector2(r, r)]:
		canvas.draw_circle(corner, r, color)
