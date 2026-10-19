extends RefCounted
## Play statistics: one record per piece, kept across sessions in PATH, and
## the article-based reading of them shown on the stats screen.
##
## Each record is {session, level, group, filter, shape, color, outcome,
## spot_ms, wrong}:
##   session  unix time the game scene was opened
##   group    color group id, or BASELINE for levels with the dot filter off
##   outcome  "found" (placed), "seen" (touched but never placed) or "missed"
##            (never touched before the level ended)
##   spot_ms  search time before the piece was first touched, or -1; it only
##            counts time the player was free to look, so time spent handling
##            other pieces is never included (see main.gd)
##   wrong    drops on a wrong hole
##   moved    whether it was moved from where it started (dragged, or placed)
##   at_ms    when it was placed, in ms since the game scene opened, or -1
##
## Beside the records, PATH keeps each session's details (see add), for the
## CSV export.
##
## The reading follows "Advanced Colorimetry Protocols and Design in Color
## Vision Deficiency Diagnosis for Children Using Pseudoisochromatic Plates":
## failing to see a figure on a vanishing plate fails the screen, hesitating
## over 30 s or correcting oneself points to a deficiency even when the answer
## ends up right, and demonstration plates (here, levels without the filter)
## show the child can do the task when color is not in the way. Prevalence
## notes come from "Comprehensive Research Report on Color Vision Deficiencies".
##
## Each spot time is also compared with the player's own usual speed (the
## median of all their spot times): a piece found several times slower than
## usual was most likely not seen at first, a miss the player recovered from,
## so it counts as a late find alongside the misses.

const PATH := "user://stats.json"
const BASELINE := "baseline"
const HESITATION_MS := 30000  # the article's "taking over 30 seconds to identify a plate"
const MIN_PIECES := 5         # pieces a group needs before it gets a reading
const MISS_FLAG := 0.5        # miss rate that reads as failing the screen
const MISS_GAP := 0.25        # miss rate above the best group that is worth watching
const SLOW_RATIO := 2.0       # median spot time against the fastest group worth watching
const SLOW_MIN_MS := 2000     # ...when also at least this much slower
const LATE_RATIO := 3.0       # spot time against the player's usual that counts as a late find
const LATE_MIN_MS := 1500     # ...when also at least this much slower, so quick players' jitter is not a stall

const GROUP_NOTES := {
	"protan": "Protan (red-weak) is ~2% of males; reds can look dark or brownish to them.",
	"deutan": "Deutan (green-weak) is the most common type, ~6% of males.",
	"tritan": "Tritan (blue-weak) is under 0.01% from birth and is more often acquired, so a tritan pattern is worth raising with an eye doctor.",
}


static func load_records() -> Array:
	return _load().pieces


## {session id (as text): details}, see add.
static func load_sessions() -> Dictionary:
	return _load().sessions


## Saves records, and if given, the details of their session: {start (unix
## time, the session id), end (unix time), board_color, backgrounds: {group id:
## background dot color}, noise (as Dots.noise), size_percent}.
static func add(records: Array, session := {}) -> void:
	if records.is_empty() and session.is_empty():
		return
	var data := _load()
	data.pieces.append_array(records)
	if not session.is_empty():
		data.sessions[str(session.start)] = session
	_write(data)


static func clear() -> void:
	_write({"pieces": [], "sessions": {}})


static func _load() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else {}
	if not (data is Dictionary and data.get("pieces", []) is Array):
		push_error("Bad stats file %s" % PATH)
		data = {}
	var sessions = data.get("sessions")
	return {"pieces": data.get("pieces", []), "sessions": sessions if sessions is Dictionary else {}}


## Every session as a block of CSV: a header section with its start and end
## (local time), board color, background dot colors, background and shape
## noise and shape size, then a row per piece: its shape and color, whether it
## was moved from where it started, and when it was placed, counted from the
## start of the game. Details recorded before they were kept read "unknown".
static func to_csv(records: Array, sessions: Dictionary) -> String:
	var by_session := {}
	for r in records:
		by_session.get_or_add(str(int(r.session)), []).append(r)
	var ids := by_session.keys()
	ids.sort_custom(func(a, b): return int(a) < int(b))
	var lines := PackedStringArray()
	for id in ids:
		var s: Dictionary = sessions.get(id, {})
		lines.append("Session start,%s" % _local_time(int(id)))
		lines.append("Session end,%s" % (_local_time(int(s.end)) if s.has("end") else "unknown"))
		lines.append("Board color,%s" % s.get("board_color", "unknown"))
		var backgrounds: Dictionary = s.get("backgrounds", {})
		if backgrounds.is_empty():
			lines.append("Background dot color,%s" % ("none (filter off)" if s.has("backgrounds") else "unknown"))
		for group in backgrounds:
			lines.append("Background dot color (%s),%s" % [group, backgrounds[group]])
		for part in [["background", "Background"], ["shapes", "Shape"]]:
			for channel in ["hue", "saturation", "value"]:
				var noise: Dictionary = s.get("noise", {}).get(part[0], {}).get(channel, {})
				lines.append("%s noise %s amplitude,%s" % [part[1], channel, _number(noise.get("amplitude"))])
				lines.append("%s noise %s wavelength (px),%s" % [part[1], channel, _number(noise.get("wavelength"))])
		lines.append("Shape size (%% of the board's shorter side),%s" % _number(s.get("size_percent")))
		lines.append("")
		lines.append("Shape,Color,Moved from original position,Time from game start (s)")
		for r in by_session[id]:
			var at_ms := int(r.get("at_ms", -1))
			lines.append(",".join(PackedStringArray([
				r.shape,
				"#" + str(r.color),
				("yes" if r.moved else "no") if r.has("moved") else "unknown",
				("%.1f" % (at_ms / 1000.0) if at_ms >= 0 else "not placed") if r.has("at_ms") else "unknown",
			])))
		lines.append("")
	return "\n".join(lines)


static func _local_time(unix: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix + Time.get_time_zone_from_system().bias * 60, true)


static func _number(value) -> String:
	if value == null:
		return "unknown"
	return str(int(value)) if float(value) == int(value) else str(snappedf(value, 0.001))


static func _write(data: Dictionary) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not save stats: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data))


## {sessions, pieces, usual_ms, late_ms, groups: {group id: summary}} where
## usual_ms is the player's median spot time and late_ms the spot time past
## which a find counts as late (both -1 with too little play), and a summary is
## {shown, found, late, seen, missed, wrong, spot_ms: sorted times, median_ms,
## hesitations, colors: {hex: {shown, missed, late, spot_ms}}}. late counts
## found pieces that were late finds; found includes them.
static func summarize(records: Array) -> Dictionary:
	var sessions := {}
	var groups := {}
	var all_spots := []
	for r in records:
		if r.spot_ms >= 0:
			all_spots.append(int(r.spot_ms))
	all_spots.sort()
	var usual := _median(all_spots) if all_spots.size() >= MIN_PIECES else -1
	var late_ms := maxi(roundi(usual * LATE_RATIO), usual + LATE_MIN_MS) if usual >= 0 else -1
	for r in records:
		sessions[r.session] = true
		var g: Dictionary = groups.get_or_add(r.group, _empty())
		var c: Dictionary = g.colors.get_or_add(r.color, {"shown": 0, "missed": 0, "late": 0, "spot_ms": []})
		g.shown += 1
		c.shown += 1
		g[r.outcome] += 1
		if r.outcome == "missed":
			c.missed += 1
		elif r.outcome == "found" and late_ms >= 0 and r.spot_ms > late_ms:
			g.late += 1
			c.late += 1
		g.wrong += int(r.wrong)
		if r.spot_ms >= 0:
			g.spot_ms.append(int(r.spot_ms))
			c.spot_ms.append(int(r.spot_ms))
	for g in groups.values():
		g.spot_ms.sort()
		g.median_ms = _median(g.spot_ms)
		g.hesitations = g.spot_ms.filter(func(ms): return ms > HESITATION_MS).size()
	return {"sessions": sessions.size(), "pieces": records.size(), "usual_ms": usual, "late_ms": late_ms, "groups": groups}


static func _empty() -> Dictionary:
	return {"shown": 0, "found": 0, "late": 0, "seen": 0, "missed": 0, "wrong": 0, "spot_ms": [], "median_ms": -1, "hesitations": 0, "colors": {}}


static func _median(sorted: Array) -> int:
	if sorted.is_empty():
		return -1
	return sorted[sorted.size() / 2]


static func miss_rate(g: Dictionary) -> float:
	return g.missed / float(g.shown) if g.shown else 0.0


## Pieces missed or found late, as a share of the pieces shown.
static func trouble_rate(g: Dictionary) -> float:
	return (g.missed + g.late) / float(g.shown) if g.shown else 0.0


## How the player reacted to group id, as {level, lines}: level is "none" (too
## little play), "ok", "watch" or "flag", and lines explain it in the articles'
## terms. names maps group ids to display names.
static func reading(summary: Dictionary, id: String, names: Dictionary) -> Dictionary:
	var g: Dictionary = summary.groups.get(id, _empty())
	if g.shown < MIN_PIECES:
		return {"level": "none", "lines": ["Not enough play yet: %d of %d pieces." % [g.shown, MIN_PIECES]]}

	# The best other group with enough play, to compare against.
	var best_miss := INF
	var best_miss_id := ""
	var best_median := INF
	var best_median_id := ""
	for other in summary.groups:
		var o: Dictionary = summary.groups[other]
		if other == id or o.shown < MIN_PIECES:
			continue
		if trouble_rate(o) < best_miss:
			best_miss = trouble_rate(o)
			best_miss_id = other
		if o.median_ms >= 0 and o.median_ms < best_median:
			best_median = o.median_ms
			best_median_id = other

	var lines: Array[String] = []
	var level := "ok"
	var rate := trouble_rate(g)
	if id == BASELINE:
		if rate >= 0.3:
			level = "watch"
			lines.append("Missed or was slow on %d%% even without the filter, so trouble elsewhere may come from attention or the game itself rather than color vision." % roundi(rate * 100))
		else:
			lines.append("Found the shapes without the filter. Like the article's demonstration plates, this shows the child can do the task, so misses with the filter point to color.")
		return {"level": level, "lines": lines}

	if rate >= MISS_FLAG:
		level = "flag"
		lines.append("Missed or found late %d%% of pieces. On vanishing plates, not seeing the figure fails the screen for this type." % roundi(rate * 100))
	elif best_miss_id and rate - best_miss >= MISS_GAP:
		level = "watch"
		lines.append("Missed or found late %d%% of pieces, against %d%% in %s." % [roundi(rate * 100), roundi(best_miss * 100), names.get(best_miss_id, best_miss_id)])
	if g.late:
		if level == "ok":
			level = "watch"
		lines.append("%d piece%s took over %.1f s to spot, against the player's usual %.2f s, so %s probably not seen at first: a miss the player recovered from." % [
				g.late, "" if g.late == 1 else "s", summary.late_ms / 1000.0, summary.usual_ms / 1000.0, "it was" if g.late == 1 else "they were"])
	if g.median_ms >= 0 and best_median_id and g.median_ms >= best_median * SLOW_RATIO and g.median_ms - best_median >= SLOW_MIN_MS:
		if level == "ok":
			level = "watch"
		lines.append("Took %.1f× as long to spot pieces as in %s. The article links slow, hesitant answers to a deficiency even when they end up right, and mild cases often pass on accuracy alone." % [g.median_ms / best_median, names.get(best_median_id, best_median_id)])
	if g.hesitations:
		if level == "ok":
			level = "watch"
		lines.append("%d piece%s took over 30 s to spot, which the article counts as hesitation." % [g.hesitations, "" if g.hesitations == 1 else "s"])
	if level == "ok":
		lines.append("Spotted reliably and quickly: no sign of trouble with these colors so far.")
	elif GROUP_NOTES.has(id):
		lines.append(GROUP_NOTES[id])
	if g.wrong:
		lines.append("%d drop%s on the wrong hole: that is about matching shapes, not seeing colors." % [g.wrong, "" if g.wrong == 1 else "s"])
	return {"level": level, "lines": lines}
