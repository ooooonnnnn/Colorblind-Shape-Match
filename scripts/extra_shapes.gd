class_name ExtraShapes
## Extra shapes: pieces added to a level, as many as its sequence sets (see
## LevelConfig), in colors outside the level's color group, which the group's
## type of color blindness sees as plainly as normal vision does (see
## ColorGroups.extra_colors). They fit the level's holes like any other piece,
## so they work as a control inside the same level: a player who finds them
## but misses the group's pieces is missing color, not attention. Stats keep
## them apart (see Stats.EXTRA). This file holds how plain they are.

const PATH := "res://extra_shapes.json"

## How different they look from the background to the level's type, as a
## CIELAB distance: around 10 is subtle, 40 and up is plain to see.
static var difference := 30.0


static func load_settings() -> void:
	var path := SettingsFile.read_path(PATH)
	var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	if not data is Dictionary:
		push_error("Bad extra shapes config in %s" % PATH)
		data = {}
	difference = clampf(float(data.get("difference", difference)), 5.0, 80.0)


static func save_settings() -> Error:
	var file := FileAccess.open(SettingsFile.write_path(PATH), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"difference": roundi(difference)}, "\t", false) + "\n")
	return OK
