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
const LATE_TEXT := Color("9c7f00")  # LATE, darkened to read on white
const SEEN := Color("e8a33d")
const MISSED := Color("e0655e")
const LEVEL_COLORS := {"none": Color("d9dde6"), "ok": Color("4caf7a"), "watch": Color("e8a33d"), "flag": Color("e0655e")}
const LEVEL_NAMES := {"none": "Not enough play", "ok": "Looks fine", "watch": "Worth watching", "flag": "Missed a lot"}
const MUTED := Color(0.231373, 0.184314, 0.290196, 0.7)  # Icons.INK, for captions
const TRACK := Color(0.231373, 0.184314, 0.290196, 0.12)  # empty part of a chart
const BASELINE_PLATE := {"background": Color("c9ccd3"), "colors": [Color("3b2f4a")]}  # the shapes in plain sight

@onready var summary_label: Label = %Summary
@onready var cards: VBoxContainer = %Cards
@onready var scroll: ScrollContainer = $Margin/Rows/Scroll
@onready var export_button: Button = %Export
@onready var clear: Button = %Clear
@onready var back: ToyButton = %Back

var _clear_armed := false  # Clear asks for a second press before wiping the stats
var _overlay: ColorRect  # the open details pop-out, or null
var _details_scroll: ScrollContainer  # the pop-out's own scroll, while it is open


func _ready() -> void:
	var drag_scroll := DragScroll.new()  # drag anywhere to scroll the cards, or the open pop-out
	drag_scroll.target = func(): return _details_scroll if _overlay else scroll
	add_child(drag_scroll)
	back.activated.connect(func():
		await get_tree().create_timer(0.15).timeout  # let the button's pop play
		get_tree().change_scene_to_file("res://menu.tscn")
	)
	export_button.pressed.connect(_on_export)
	clear.pressed.connect(_on_clear)
	_build()


## Asks where to save all the records as an Excel workbook, one sheet per
## session, with the system's own save dialog where there is one (it is also
## the way to reach files on a tablet).
func _on_export() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray(["*.xlsx ; Excel workbooks"])
	dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	dialog.current_file = "shape_match_stats_%s.xlsx" % Time.get_date_string_from_system()
	dialog.file_selected.connect(_save_xlsx)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)


func _save_xlsx(path: String) -> void:
	var err := Stats.export_xlsx(path)
	if err != OK:
		push_error("Could not export stats to %s: %s" % [path, error_string(err)])
	export_button.text = "Saved!" if err == OK else "Couldn't save"
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(export_button):
			export_button.text = "Export spreadsheet"
	)


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

	var card := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	card.add_child(row)

	var plate: Control = GroupPlate.new()
	plate.custom_minimum_size = Vector2(120, 120)
	plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	plate.background = plate_colors.background
	plate.colors = plate_colors.colors
	plate.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(plate)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 10)
	row.add_child(middle)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", 24)
	head.add_child(name_label)
	var sub := Label.new()
	sub.text = subtitle
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.add_theme_color_override("font_color", MUTED)
	head.add_child(sub)
	head.add_child(_caption("Click for details ›"))
	head.add_child(_badge(reading.level))
	middle.add_child(head)

	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 32)
	var outcome := VBoxContainer.new()
	var bar := OutcomeBar.new()
	bar.custom_minimum_size = Vector2(260, 16)
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
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
	strip.mouse_filter = Control.MOUSE_FILTER_PASS
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
			swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			swatch.tooltip_text = "#%s: %d shown, %d missed, %d found late" % [hex, c.shown, c.missed, c.late]
			swatch.mouse_filter = Control.MOUSE_FILTER_PASS
			cell.add_child(swatch)
			var count := _caption("%d/%d missed%s" % [c.missed, c.shown, ", %d late" % c.late if c.late else ""])
			count.add_theme_color_override("font_color", MISSED if c.missed else LATE_TEXT if c.late else MUTED)
			cell.add_child(count)
			colors.add_child(cell)
		middle.add_child(colors)

	for line in reading.lines:
		var label := Label.new()
		label.text = line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		middle.add_child(label)

	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_open_details(summary, id, title, subtitle, plate_colors, names)
	)
	cards.add_child(card)


# ---------- Details pop-out ----------

## A big window over a dimmed page with one group's stats spelled out: the
## outcome bar and spot times drawn large with labels, each number explained,
## and every color on its own line. Closes with the cross, a click outside, or Esc.
func _open_details(summary: Dictionary, id: String, title: String, subtitle: String, plate_colors: Dictionary, names: Dictionary) -> void:
	_close_details()
	var g: Dictionary = summary.groups.get(id, Stats._empty())
	var reading := Stats.reading(summary, id, names)

	_overlay = ColorRect.new()
	_overlay.color = Color(Icons.INK, 0.45)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_close_details()
	)
	add_child(_overlay)
	var window := PanelContainer.new()
	window.anchor_left = 0.1
	window.anchor_right = 0.9
	window.anchor_top = 0.06
	window.anchor_bottom = 0.94
	var solid := StyleBoxFlat.new()  # like the cards, but fully opaque
	solid.bg_color = Color.WHITE
	solid.set_corner_radius_all(24)
	solid.set_border_width_all(3)
	solid.border_color = Icons.INK
	solid.set_content_margin_all(28)
	solid.shadow_color = Color(Icons.INK, 0.25)
	solid.shadow_size = 12
	window.add_theme_stylebox_override("panel", solid)
	_overlay.add_child(window)
	_details_scroll = ScrollContainer.new()
	_details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	window.add_child(_details_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	_details_scroll.add_child(body)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	var plate: Control = GroupPlate.new()
	plate.custom_minimum_size = Vector2(170, 170)
	plate.background = plate_colors.background
	plate.colors = plate_colors.colors
	head.add_child(plate)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", 40)
	titles.add_child(name_label)
	titles.add_child(_wrapped(subtitle, MUTED, 18))
	var badge := _badge(reading.level)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	titles.add_child(badge)
	head.add_child(titles)
	var close := ToyButton.new()
	close.picture = "cross"
	close.color = Color("ffb4a2")
	close.custom_minimum_size = Vector2(60, 60)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.tooltip_text = "Close"
	close.activated.connect(_close_details)
	head.add_child(close)
	body.add_child(head)

	var outcomes := _section(body, "What happened to the %d pieces" % g.shown)
	var bar := OutcomeBar.new()
	bar.custom_minimum_size = Vector2(0, 34)
	bar.counts = [g.found - g.late, g.late, g.seen, g.missed]
	outcomes.add_child(bar)
	var late_note := "found, but much slower than usual (needs more play to tell)"
	if summary.late_ms >= 0:
		late_note = "found, but over %.1f s, several times slower than usual: most likely not seen at first" % (summary.late_ms / 1000.0)
	for entry in [[FOUND, g.found - g.late, "found in time", "spotted at the usual speed and put in their hole"],
			[LATE, g.late, "found late", late_note],
			[SEEN, g.seen, "seen, not placed", "touched but never put in their hole"],
			[MISSED, g.missed, "missed", "never touched before the level ended"]]:
		outcomes.add_child(_legend(entry[0], "%d %s" % [entry[1], entry[2]], entry[3]))

	var numbers := _section(body, "The numbers")
	var tiles := HFlowContainer.new()
	tiles.add_theme_constant_override("h_separation", 40)
	tiles.add_theme_constant_override("v_separation", 16)
	tiles.add_child(_big_tile("%d%%" % roundi(Stats.miss_rate(g) * 100) if g.shown else "-", "missed",
			"%d of %d pieces never touched" % [g.missed, g.shown]))
	tiles.add_child(_big_tile(str(g.late), "late finds", "found much slower than usual"))
	tiles.add_child(_big_tile("%.1f s" % (g.median_ms / 1000.0) if g.median_ms >= 0 else "-", "typical spot time",
			"half the pieces were spotted faster than this"))
	tiles.add_child(_big_tile(str(g.hesitations), "over 30 s", "the article's sign of hesitation"))
	tiles.add_child(_big_tile(str(g.wrong), "wrong holes", "about matching shapes, not seeing colors"))
	numbers.add_child(tiles)

	var times := _section(body, "How fast each piece was spotted")
	var strip := TimeStrip.new()
	strip.custom_minimum_size = Vector2(0, 64)
	strip.times = g.spot_ms
	strip.late_ms = summary.late_ms
	strip.ticks = true
	times.add_child(strip)
	var late_line := ""
	if summary.late_ms >= 0:
		late_line = " (past %.1f s, against your usual %.2f s)" % [summary.late_ms / 1000.0, summary.usual_ms / 1000.0]
	times.add_child(_wrapped("Each dot is one piece; further right is slower. Yellow line: a late find%s. Red line: 30 s, where the article counts a child as hesitating." % late_line, MUTED, 16))

	if not g.colors.is_empty():
		var colors := _section(body, "By color")
		for hex in g.colors:
			var c: Dictionary = g.colors[hex]
			var spots: Array = c.spot_ms.duplicate()
			spots.sort()
			var typical := Stats._median(spots)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 14)
			var swatch := Panel.new()
			var chip := StyleBoxFlat.new()
			chip.bg_color = Color(hex)
			chip.set_corner_radius_all(10)
			chip.set_border_width_all(2)
			chip.border_color = Icons.INK
			swatch.add_theme_stylebox_override("panel", chip)
			swatch.custom_minimum_size = Vector2(44, 44)
			row.add_child(swatch)
			var line := Label.new()
			line.text = "%d shown · %d missed · %d found late" % [c.shown, c.missed, c.late]
			if typical >= 0:
				line.text += " · typical %.1f s" % (typical / 1000.0)
			line.add_theme_font_size_override("font_size", 20)
			line.add_theme_color_override("font_color", MISSED if c.missed else LATE_TEXT if c.late else Icons.INK)
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(line)
			colors.add_child(row)

	var meaning := _section(body, "What it means")
	for text in reading.lines:
		meaning.add_child(_wrapped(text, Icons.INK, 19))

	# Spring open from the middle once the window has its size.
	_overlay.modulate.a = 0.0
	window.scale = Vector2(0.9, 0.9)
	await get_tree().process_frame
	if not is_instance_valid(window):
		return
	window.pivot_offset = window.size / 2
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_overlay, "modulate:a", 1.0, 0.15)
	t.tween_property(window, "scale", Vector2.ONE, 0.25)


func _close_details() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func _unhandled_input(event: InputEvent) -> void:
	if _overlay and event.is_action_pressed("ui_cancel"):
		_close_details()
		get_viewport().set_input_as_handled()


## A titled part of the details window; returns the box for its contents.
func _section(parent: Control, title: String) -> VBoxContainer:
	parent.add_child(HSeparator.new())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 26)
	box.add_child(heading)
	parent.add_child(box)
	return box


func _legend(color: Color, what: String, meaning: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var chip := ColorRect.new()
	chip.color = color
	chip.custom_minimum_size = Vector2(22, 22)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)
	var label := Label.new()
	label.text = what
	label.add_theme_font_size_override("font_size", 20)
	row.add_child(label)
	var note := _wrapped(meaning, MUTED, 17)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(note)
	return row


func _big_tile(value: String, caption: String, meaning: String) -> VBoxContainer:
	var tile := VBoxContainer.new()
	tile.custom_minimum_size = Vector2(200, 0)
	tile.add_theme_constant_override("separation", 2)
	var big := Label.new()
	big.text = value
	big.add_theme_font_size_override("font_size", 44)
	tile.add_child(big)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 19)
	tile.add_child(label)
	var note := _wrapped(meaning, MUTED, 15)
	note.custom_minimum_size = Vector2(200, 0)
	tile.add_child(note)
	return tile


func _wrapped(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _badge(level: String) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = LEVEL_COLORS[level]
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = Icons.INK
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = LEVEL_NAMES[level]
	badge.add_child(label)
	return badge


func _tile(value: String, caption: String) -> VBoxContainer:
	var tile := VBoxContainer.new()
	tile.add_theme_constant_override("separation", 0)
	var big := Label.new()
	big.text = value
	big.add_theme_font_size_override("font_size", 28)
	tile.add_child(big)
	tile.add_child(_caption(caption))
	return tile


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", MUTED)
	return label


## A stacked bar of pieces found in time, found late, seen and missed.
class OutcomeBar extends Control:
	var counts: Array = [0, 0, 0, 0]

	func _draw() -> void:
		var total: float = counts.reduce(func(a, b): return a + b, 0)
		var pill := StyleBoxFlat.new()
		pill.set_corner_radius_all(int(size.y / 2))
		pill.bg_color = TRACK
		draw_style_box(pill, Rect2(Vector2.ZERO, size))
		if total == 0:
			return
		# Segments are drawn as one pill each, clipped by drawing the later ones on top.
		var x := size.x
		for i in range(counts.size() - 1, -1, -1):
			if counts[i] == 0:
				continue
			pill.bg_color = [FOUND, LATE, SEEN, MISSED][i]
			draw_style_box(pill, Rect2(0, 0, maxf(x, size.y), size.y))
			x -= size.x * counts[i] / total
		pill.bg_color = Color.TRANSPARENT
		pill.set_border_width_all(2)
		pill.border_color = Icons.INK
		draw_style_box(pill, Rect2(Vector2.ZERO, size))


## A dot per spot time on a log scale from 0.2 to 30 s, so quick and slow
## finds both spread out. The yellow line is the player's late-find threshold;
## times past 30 s (the article's hesitation) pile up at the red end.
class TimeStrip extends Control:
	const LOW_MS := 200.0
	var times: Array = []
	var late_ms := -1
	var ticks := false  # time labels under the line, for the big version

	func _x(ms: float) -> float:
		var t := log(maxf(ms, LOW_MS) / LOW_MS) / log(Stats.HESITATION_MS / LOW_MS)
		return (size.x - 8) * clampf(t, 0, 1)

	func _draw() -> void:
		var mid := size.y * (0.35 if ticks else 0.5)
		if ticks:
			var font := get_theme_default_font()
			for ms in [200, 500, 1000, 2000, 5000, 10000, 30000]:
				var x := _x(ms)
				draw_line(Vector2(x, mid + 8), Vector2(x, mid + 14), MUTED, 2)
				var text := ("%.1f s" % (ms / 1000.0)) if ms < 1000 else ("%d s" % (ms / 1000))
				draw_string(font, Vector2(clampf(x - 14, 0, size.x - 34), size.y - 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MUTED)
		draw_line(Vector2(0, mid), Vector2(size.x, mid), TRACK, 4)
		draw_line(Vector2(_x(Stats.HESITATION_MS), 2), Vector2(_x(Stats.HESITATION_MS), size.y - 2), MISSED, 2)
		if late_ms >= 0:
			draw_line(Vector2(_x(late_ms), 2), Vector2(_x(late_ms), size.y - 2), LATE, 2)
		for ms in times:
			var color := MISSED if ms > Stats.HESITATION_MS else LATE if late_ms >= 0 and ms > late_ms else FOUND
			draw_circle(Vector2(_x(ms), mid), 5, Color(color, 0.7))
