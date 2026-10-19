extends Control
## Title screen: starts the game or opens the config scene.


func _ready() -> void:
	$Buttons/Play.pressed.connect(get_tree().change_scene_to_file.bind("res://main.tscn"))
	$Buttons/Config.pressed.connect(get_tree().change_scene_to_file.bind("res://config.tscn"))
	$Buttons/Play.grab_focus()
