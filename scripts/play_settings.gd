class_name PlaySettings
## How pieces are moved, kept in PATH. Pieces can always be tapped, then their
## hole; drag also lets them be carried there. tutorial starts each game with a
## level where a hand shows how (see main.gd and TutorialHand). landscape keeps
## phones and tablets sideways, turning with the device between the two
## landscape ways round; off, the screen follows the device upright too.

const PATH := "res://play.json"

static var drag := true
static var tutorial := false
static var landscape := true


static func load_settings() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(SettingsFile.read_path(PATH)))
	if not data is Dictionary:
		push_error("Bad or missing play settings in %s" % PATH)
		return
	drag = bool(data.get("drag", drag))
	tutorial = bool(data.get("tutorial", tutorial))
	landscape = bool(data.get("landscape", landscape))


## Turns the screen the way landscape says; only phones and tablets can be turned.
static func apply_orientation() -> void:
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE if landscape else DisplayServer.SCREEN_SENSOR)


static func save_settings() -> Error:
	var file := FileAccess.open(SettingsFile.write_path(PATH), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"drag": drag, "tutorial": tutorial, "landscape": landscape}, "\t", false) + "\n")
	return OK
