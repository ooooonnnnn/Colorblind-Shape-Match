extends Control
## The launch splash: the 7493 logo fades in on black, holds a moment, fades
## out, and the menu opens. Godot's own boot splash cannot fade, so it only
## shows plain black (see project.godot) and this scene does the rest.

const FADE_IN := 0.35   # seconds
const HOLD := 0.7
const FADE_OUT := 0.35
const NEXT := "res://menu.tscn"

@onready var logo: TextureRect = $Logo


func _ready() -> void:
	PlaySettings.load_settings()
	PlaySettings.apply_orientation()
	logo.modulate.a = 0.0
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(logo, "modulate:a", 1.0, FADE_IN)
	t.tween_interval(HOLD)
	t.tween_property(logo, "modulate:a", 0.0, FADE_OUT)
	t.tween_callback(get_tree().change_scene_to_file.bind(NEXT))
