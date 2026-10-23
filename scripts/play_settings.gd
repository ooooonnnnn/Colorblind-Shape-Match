class_name PlaySettings
## How pieces are moved, kept in PATH. Pieces can always be tapped, then their
## hole; drag also lets them be carried there. tutorial starts each game with a
## level where a hand shows how (see main.gd and TutorialHand). landscape keeps
## phones and tablets sideways, turning with the device between the two
## landscape ways round; off, the screen follows the device upright too.
## fade_in shows the shapes plainly the first time a game's dots come on, then
## fades the dots in over them (see main.gd). endless_extra gives every level
## one extra shape that counts, and a new one each time one is placed, in place
## of each sequence's own extra and extra_scored (see LevelConfig and main.gd).
## The new one comes extra_delay seconds later, so the player has a moment to
## look for the others, and with extra_stop none come once the player has
## placed one of the level's own pieces.

const PATH := "res://play.json"

static var drag := true
static var tutorial := false
static var landscape := true
static var fade_in := true
static var endless_extra := false
static var extra_delay := 3.0  # seconds
static var extra_stop := true


static func load_settings() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(SettingsFile.read_path(PATH)))
	if not data is Dictionary:
		push_error("Bad or missing play settings in %s" % PATH)
		return
	drag = bool(data.get("drag", drag))
	tutorial = bool(data.get("tutorial", tutorial))
	landscape = bool(data.get("landscape", landscape))
	fade_in = bool(data.get("fade_in", fade_in))
	endless_extra = bool(data.get("endless_extra", endless_extra))
	extra_delay = maxf(0.0, float(data.get("extra_delay", extra_delay)))
	extra_stop = bool(data.get("extra_stop", extra_stop))


## Turns the screen the way landscape says; only phones and tablets can be turned.
static func apply_orientation() -> void:
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE if landscape else DisplayServer.SCREEN_SENSOR)


static func save_settings() -> Error:
	var file := FileAccess.open(SettingsFile.write_path(PATH), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"drag": drag, "tutorial": tutorial, "landscape": landscape, "fade_in": fade_in, "endless_extra": endless_extra,
			"extra_delay": extra_delay, "extra_stop": extra_stop}, "\t", false) + "\n")
	return OK
