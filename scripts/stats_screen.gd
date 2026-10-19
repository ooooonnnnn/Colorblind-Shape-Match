extends Control
## The stats screen: a card per color group (and for levels played without the
## filter, as a baseline) showing how many pieces the player found, saw or
## missed, how fast they spotted them, which colors they missed, and what that
## means according to the articles (see Stats).

const ColorGroups := preload("res://scripts/color_groups.gd")
const Stats := preload("res://scripts/stats.gd")
const GroupPlate := preload("res://scripts/group_plate.gd")
const FOUND := Color("4caf7a")
const LATE := Color("d8c44a")
const SEEN := Color("e8a33d")
const MISSED := Color("e0655e")
const LEVEL_COLORS := {"none": Color("6b7385"), "ok": Color("4caf7a"), "watch": Color("e8a33d"), "flag": Color("e0655e")}
const LEVEL_NAMES := {"none": "Not enough play", "ok": "Looks fine", "watch": "Worth watching", "flag": "Missed a lot"}
const BASELINE_PLATE := {"background": Color("c9ccd3"), "colors": [Color("3b2f4a")]}  # the shapes in plain sight

@onready var summary_label: Label = %Summary
@onready var cards: VBoxContainer = %Cards
@onready var clear: Button = %Clear
@onready var back: Button = %Back

var _clear_armed := false  # Clear asks for a second press before wiping the stats


func _ready() -> void:
	back.pressed.connect(get_tree().change_scene_to_file.bind("res://menu.tscn"))
	clear.pressed.connect(_on_clear)
	_build()


func _on_clear() -> void:
	if not _clear_armed:
		_clear_armed = true
		clear.text = "Press again to clear"
		return
	Stats.clear()
	_clear_armed = false
	clear.text = "Clear stats"
	_build()


func _build() -> void:
	for child in cards.get_children():
		child.queue_free()
	var summary := Stats.summarize(Stats.load_records())
	summary_label.text = "%d pieces over %d session%s" % [summary.pieces, summary.sessions, "" if summary.sessions == 1 else "s"]
	if summary.usual_ms >= 0:
		summary_label.text += " · usual spot time %.2f s, late past %.1f s" % [summary.usual_ms / 1000.0, summary.late_ms / 1000.0]

	# The groups in use, then any recorded group no longer in use, then the baseline.
	var groups: Array = ColorGroups.active(ColorGroups.load_settings()).duplicate()
	for article in ColorGroups.ARTICLE:
		if summary.groups.has(article.id) and not groups.any(func(g): return g.id == article.id):
			groups.append(article)
	var names := {Stats.BASELINE: "No filter"}
	for group in groups:
		names[group.id] = group.name
	for group in groups:
		_add_card(summary, group.id, group.name, "%s · %s" % [group.kind, group.prevalence], group, names)
	_add_card(summary, Stats.BASELINE, names[Stats.BASELINE], "Baseline: levels with the Ishihara filter off", BASELINE_PLATE, names)


func _add_card(summary: Dictionary, id: String, title: String, subtitle: String, plate_colors: Dictionary, names: Dictionary) -> void:
	var g: Dictionary = summary.groups.get(id, Stats._empty())
	var reading := Stats.reading(summary, id, names)

	var style := StyleBoxFlat.new()
	style.bg_color = Color("252a37")
	style.set_corner_radius_all(10)
	style.set_content_margin_all(16)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	card.add_child(row)

	var plate: Control = GroupPlate.new()
	plate.custom_minimum_size = Vector2(120, 120)
	plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	plate.background = plate_colors.background
	plate.colors = plate_colors.colors
	row.add_child(plate)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 10)
	row.add_child(middle)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color("e9ecf2"))
	head.add_child(name_label)
	var sub := Label.new()
	sub.text = subtitle
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sub)
	head.add_child(_badge(reading.level))
	middle.add_child(head)

	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 32)
	var outcome := VBoxContainer.new()
	var bar := OutcomeBar.new()
	bar.custom_minimum_size = Vector2(260, 16)
	bar.counts = [g.found - g.late, g.late, g.seen, g.missed]
	outcome.add_child(bar)
	outcome.add_child(_caption("%d found · %d late · %d seen, not placed · %d missed" % [g.found - g.late, g.late, g.seen, g.missed]))
	metrics.add_child(outcome)
	metrics.add_child(_tile("%d%%" % roundi(Stats.miss_rate(g) * 100) if g.shown else "–", "missed"))
	metrics.add_child(_tile(str(g.late), "late finds"))
	metrics.add_child(_tile("%.1f s" % (g.median_ms / 1000.0) if g.median_ms >= 0 else "–", "typical spot time"))
	metrics.add_child(_tile(str(g.wrong), "wrong holes"))
	var times := VBoxContainer.new()
	times.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var strip := TimeStrip.new()
	strip.custom_minimum_size = Vector2(240, 28)
	strip.times = g.spot_ms
	strip.late_ms = summary.late_ms
	times.add_child(strip)
	times.add_child(_caption("each piece's spot time, 0.2 to 30 s+ · yellow line: late"))
	metrics.add_child(times)
	middle.add_child(metrics)

	if not g.colors.is_empty():
		var colors := HFlowContainer.new()
		colors.add_theme_constant_override("h_separation", 14)
		for hex in g.colors:
			var c: Dictionary = g.colors[hex]
			var cell := HBoxContainer.new()
			var swatch := ColorRect.new()
			swatch.color = Color(hex)
			swatch.custom_minimum_size = Vector2(26, 26)
			swatch.tooltip_text = "#%s: %d shown, %d missed, %d found late" % [hex, c.shown, c.missed, c.late]
			cell.add_child(swatch)
			var count := _caption("%d/%d missed%s" % [c.missed, c.shown, ", %d late" % c.late if c.late else ""])
			count.add_theme_color_override("font_color", MISSED if c.missed else LATE if c.late else Color("9aa3b5"))
			cell.add_child(count)
			colors.add_child(cell)
		middle.add_child(colors)

	for line in reading.lines:
		var label := Label.new()
		label.text = line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", Color("c8ccd6"))
		middle.add_child(label)

	cards.add_child(card)


func _badge(level: String) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = LEVEL_COLORS[level]
	style.set_corner_radius_all(14)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = LEVEL_NAMES[level]
	label.add_theme_color_override("font_color", Color("15181f"))
	badge.add_child(label)
	return badge


func _tile(value: String, caption: String) -> VBoxContainer:
	var tile := VBoxContainer.new()
	tile.add_theme_constant_override("separation", 0)
	var big := Label.new()
	big.text = value
	big.add_theme_font_size_override("font_size", 26)
	big.add_theme_color_override("font_color", Color("e9ecf2"))
	tile.add_child(big)
	tile.add_child(_caption(caption))
	return tile


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	return label


## A stacked bar of pieces found in time, found late, seen and missed.
class OutcomeBar extends Control:
	var counts: Array = [0, 0, 0, 0]

	func _draw() -> void:
		var total: float = counts.reduce(func(a, b): return a + b, 0)
		draw_rect(Rect2(Vector2.ZERO, size), Color("323848"))
		if total == 0:
			return
		var x := 0.0
		for i in counts.size():
			var w: float = size.x * counts[i] / total
			draw_rect(Rect2(x, 0, w, size.y), [FOUND, LATE, SEEN, MISSED][i])
			x += w


## A dot per spot time on a log scale from 0.2 to 30 s, so quick and slow
## finds both spread out. The yellow line is the player's late-find threshold;
## times past 30 s (the article's hesitation) pile up at the red end.
class TimeStrip extends Control:
	const LOW_MS := 200.0
	var times: Array = []
	var late_ms := -1

	func _x(ms: float) -> float:
		var t := log(maxf(ms, LOW_MS) / LOW_MS) / log(Stats.HESITATION_MS / LOW_MS)
		return (size.x - 8) * clampf(t, 0, 1)

	func _draw() -> void:
		var mid := size.y / 2
		draw_line(Vector2(0, mid), Vector2(size.x, mid), Color("323848"), 2)
		draw_line(Vector2(_x(Stats.HESITATION_MS), 2), Vector2(_x(Stats.HESITATION_MS), size.y - 2), MISSED, 2)
		if late_ms >= 0:
			draw_line(Vector2(_x(late_ms), 2), Vector2(_x(late_ms), size.y - 2), LATE, 2)
		for ms in times:
			var color := MISSED if ms > Stats.HESITATION_MS else LATE if late_ms >= 0 and ms > late_ms else FOUND
			draw_circle(Vector2(_x(ms), mid), 5, Color(color, 0.7))
