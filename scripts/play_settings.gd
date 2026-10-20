class_name PlaySettings
## How pieces are moved, kept in PATH. Pieces can always be tapped, then their
## hole; drag also lets them be carried there.

const PATH := "res://play.json"

static var drag := true


static func load_settings() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(SettingsFile.read_path(PATH)))
	if not data is Dictionary:
		push_error("Bad or missing play settings in %s" % PATH)
		return
	drag = bool(data.get("drag", drag))


static func save_settings() -> Error:
	var file := FileAccess.open(SettingsFile.write_path(PATH), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"drag": drag}, "\t", false) + "\n")
	return OK
