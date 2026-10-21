extends Control
## Title screen: a big play button for the child, and a magnifying glass, a
## chart and a gear for grown-ups that only open the references, stats and
## config scenes after being held down (see ToyButton).

@onready var play: ToyButton = $Center/Play
@onready var references: ToyButton = $References
@onready var stats: ToyButton = $Stats
@onready var config: ToyButton = $Config
@onready var decor: Control = $Decor


func _ready() -> void:
	play.activated.connect(_open.bind("res://main.tscn"))
	references.activated.connect(_open.bind("res://references.tscn"))
	stats.activated.connect(_open.bind("res://stats.tscn"))
	config.activated.connect(_open.bind("res://config.tscn"))
	decor.matched.connect(_on_triangle_fitted)
	play.start_pulse()
	play.grab_focus()


## The secret: the floating triangle was fitted into the play button. It
## celebrates like a placed piece, and the play triangle turns gold.
func _on_triangle_fitted() -> void:
	var effects := Effects.new()
	add_child(effects)
	var rect := play.get_global_rect()
	effects.burst(rect.get_center(), rect.size.x * 0.5)
	effects.confetti(get_global_rect(), 90)
	var chime := AudioStreamPlayer.new()
	chime.stream = preload("res://sounds/chime.mp3")
	add_child(chime)
	chime.pitch_scale = randf_range(0.94, 1.06)  # never quite the same twice
	chime.play()
	play.squish(0.25)
	play.icon_color = Color("ffd166")
	play.queue_redraw()


func _open(scene: String) -> void:
	# A moment for the button's squish and pop before the scene goes.
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file(scene)
