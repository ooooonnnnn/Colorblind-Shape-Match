extends Control
## Title screen: a big play button for the child, and a gear for grown-ups
## that only opens the config scene after being held down (see ToyButton).

@onready var play: ToyButton = $Center/Play
@onready var config: ToyButton = $Config


func _ready() -> void:
	play.activated.connect(_open.bind("res://main.tscn"))
	config.activated.connect(_open.bind("res://config.tscn"))
	play.start_pulse()
	play.grab_focus()


func _open(scene: String) -> void:
	# A moment for the button's squish and pop before the scene goes.
	await get_tree().create_timer(0.15).timeout
	get_tree().change_scene_to_file(scene)
