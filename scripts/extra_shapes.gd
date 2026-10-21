class_name ExtraShapes
## Extra shapes: pieces added to a level, as many as its sequence sets (see
## LevelConfig), in colors from TEMPLATE that every type of color blindness
## sees apart from the level's background, not only the group's own type (see
## ColorGroups.extra_colors). They fit the level's holes like any other piece,
## so they work as a control inside the same level: a player who finds them
## but misses the group's pieces is missing color, not attention. Stats keep
## them apart (see Stats.EXTRA). This file holds how plain they are.

const PATH := "res://extra_shapes.json"
## The colors extra shapes may take. They differ from the groups' mid-tone
## backgrounds mostly in lightness, which every type of color vision keeps,
## so none of them vanish for anyone: near-black stands out by about 50 to
## every type, the rest by 33 to 47 (CIELAB).
const TEMPLATE: Array[Color] = [Color("111111"), Color("1d3557"), Color("6b1d1d"), Color("2b2b2b"), Color("ffd93d"), Color("ffffff")]
const MAX_DIFFERENCE := 50.0  # about the most TEMPLATE reaches for every type

## How different they must look from the background to every type and to
## normal vision, as a CIELAB distance: around 10 is subtle, 40 and up is
## plain to see.
static var difference := 30.0


static func load_settings() -> void:
	var path := SettingsFile.read_path(PATH)
	var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	if not data is Dictionary:
		push_error("Bad extra shapes config in %s" % PATH)
		data = {}
	difference = clampf(float(data.get("difference", difference)), 5.0, MAX_DIFFERENCE)


static func save_settings() -> Error:
	var file := FileAccess.open(SettingsFile.write_path(PATH), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"difference": roundi(difference)}, "\t", false) + "\n")
	return OK
