class_name LevelConfig
## The level sequences in config.json. Each entry is {duration, holes, shapes,
## repetitions, filter, colors, time_bonus, extra, extra_scored}: duration <= 0
## means no time limit,
## shapes is pieces per hole, repetitions <= 0 repeats the entry forever, filter
## turns the Ishihara dots on, colors is the color group its levels use (an id
## from ColorGroups) or "random" for a random one each level, and time_bonus
## makes a timed level give TIME_BONUS for each match and take TIME_PENALTY for
## each tap on neither a piece nor a hole, against spamming. extra is how many
## extra shapes (see ExtraShapes) join the level's pieces on the board, and
## extra_scored whether they are part of the total to place: if so, every
## piece must be placed to clear the level; if not, only its holes * shapes
## own pieces, and extras left when it clears float off.

const PATH := "res://config.json"
const TIME_BONUS := 2.0    # seconds a right match adds, up to the level's full time
const TIME_PENALTY := 1.0  # seconds a stray tap takes off


static func load_levels() -> Array[Dictionary]:
	var data = JSON.parse_string(FileAccess.get_file_as_string(SettingsFile.read_path(PATH)))
	if not (data is Dictionary and data.get("levels") is Array and not data.levels.is_empty()):
		push_error("Bad or missing level list in %s" % PATH)
		data = {"levels": [{}]}
	var levels: Array[Dictionary] = []
	for entry in data.levels:
		levels.append({
			"duration": float(entry.get("duration", 0)),
			"holes": clampi(int(entry.get("holes", 3)), 1, Shapes.NAMES.size()),
			"shapes": maxi(1, int(entry.get("shapes", 1))),
			"repetitions": int(entry.get("repetitions", 0)),
			"filter": bool(entry.get("filter", true)),
			"colors": str(entry.get("colors", "random")),
			"time_bonus": bool(entry.get("time_bonus", true)),
			"extra": maxi(0, int(entry.get("extra", 0))),
			"extra_scored": bool(entry.get("extra_scored", true)),
		})
	return levels


## Writes one entry per line, like the hand-written file.
static func save_levels(levels: Array[Dictionary]) -> Error:
	var lines := PackedStringArray()
	for e in levels:
		var duration: float = e.duration
		lines.append('\t\t{ "duration": %s, "holes": %d, "shapes": %d, "repetitions": %d, "filter": %s, "colors": %s, "time_bonus": %s, "extra": %d, "extra_scored": %s }' % [
				str(int(duration)) if duration == int(duration) else str(duration),
				e.holes, e.shapes, e.repetitions, JSON.stringify(e.filter), JSON.stringify(e.colors),
				JSON.stringify(e.time_bonus), e.extra, JSON.stringify(e.extra_scored)])
	var file := FileAccess.open(SettingsFile.write_path(PATH), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string('{\n\t"levels": [\n%s\n\t]\n}\n' % ",\n".join(lines))
	return OK
