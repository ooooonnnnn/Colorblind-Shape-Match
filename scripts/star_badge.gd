class_name StarBadge
extends Control
## The star beside the cleared-level count. Hops when the count goes up.

var squash := 0.0:
	set(v):
		squash = v
		queue_redraw()

var _tween: Tween


func bounce() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for s in [0.25, -0.2, 0.08, 0.0]:
		_tween.tween_property(self, "squash", s, 0.1)


func _draw() -> void:
	draw_set_transform(size / 2, 0, Vector2(1 + squash, 1 - squash))
	Icons.draw(self, "star", Vector2.ZERO, minf(size.x, size.y), Color("ffd166"))
