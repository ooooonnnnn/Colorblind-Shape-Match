extends Control
## The stats screen: a card per color group, most worrying first, then the
## two checks to compare them against (extra shapes, and levels played without
## the filter). Each card gives a verdict, one sentence on why, and three big
## numbers; See details opens everything else in a pop-up: what happened to
## each piece, how fast each was spotted, each color, and what it means
## according to the articles (see Stats).

const ColorGroups := preload("res://scripts/color_groups.gd")
const Stats := preload("res://scripts/stats.gd")
const GroupPlate := preload("res://scripts/group_plate.gd")
const FOUND := Color("4caf7a")
const LATE := Color("d8c44a")
const LATE_TEXT := Color("8a7000")  # LATE, darkened to read on white
const SEEN := Color("e8a33d")
const MISSED := Color("e0655e")
const MISSED_TEXT := Color("b8423b")  # MISSED, darkened to read on white
const LEVEL_COLORS := {"none": Color("d9dde6"), "ok": Color("7bd88f"), "watch": Color("ffc46b"), "flag": Color("ff8f86")}
const LEVEL_NAMES := {"none": "Not enough play", "ok": "Looks fine", "watch": "Worth watching", "flag": "Missed a lot"}
const LEVEL_ORDER := ["flag", "watch", "ok", "none"]  # most worrying first
const MUTED := Color(0.231373, 0.184314, 0.290196, 0.78)  # Icons.INK, for captions
const TRACK := Color(0.231373, 0.184314, 0.290196, 0.12)  # empty part of a chart
const BASELINE_PLATE := {"background": Color("c9ccd3"), "colors": [Color("3b2f4a")]}  # the shapes in plain sight
const EXTRA_PLATE := {"background": Color("559c68"), "colors": [Color("6693ab"), Color("4d9f37")]}  # off the confusion lines
const NARROW := 1300.0  # px; a page narrower than this gets compact cards
const ABOUT_VERDICTS := "Each color group is made for one type of color blindness: its pieces blend into the dots for that type.\n\nLooks fine: the pieces were found, at the player's usual speed.\nWorth watching: some were found late, slowly, or missed more than elsewhere.\nMissed a lot: many were missed or found late, which on printed plates fails the screen for this type.\n\nA piece is late when it took several times longer than this player usually needs, so it was most likely not seen at first."
const ABOUT_CHECKS := "Extra shapes are pieces every type of color vision can see, shown in the same filtered levels. No filter is levels played without the dots.\n\nIf the player does well on these, the task itself is easy for them, so misses in a color group point to color. If they struggle here too, attention or the game may be the reason instead."
const ABOUT_DISCLAIMER := "Screens can't show calibrated test colors, and a diagnosis needs printed plates under daylight (D65) lighting, checked by a professional. Treat a flagged group as a reason to see an eye care professional, not as a result."

@onready var summary_label: Label = %Summary
@onready var cards: VBoxContainer = %Cards
@onready var scroll: ScrollContainer = $Margin/Rows/Scroll
@onready var export_button: Button = %Export
@onready var clear: Button = %Clear
@onready var back: ToyButton = %Back
@onready var disclaimer: Label = $Margin/Rows/Disclaimer

var _details: PopupCard  # the open details pop-up, or null
var _narrow := false  # the cards are built compact, for a narrow page


func _ready() -> void:
	var drag_scroll := DragScroll.new()  # drag anywhere to scroll the cards, or the open pop-up
	drag_scroll.target = func(): return _details.scroll() if is_instance_valid(_details) else scroll
	add_child(drag_scroll)
	back.activated.connect(func():
		await get_tree().create_timer(0.15).timeout  # let the button's pop play
		get_tree().change_scene_to_file("res://menu.tscn")
	)
	export_button.pressed.connect(_on_export)
	clear.pressed.connect(_on_clear)
	PopupCard.tint(clear, Color("ffd9d0"))
	# The disclaimer, short, with the rest a tap away.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	disclaimer.get_parent().add_child(footer)
	disclaimer.reparent(footer)
	disclaimer.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	disclaimer.autowrap_mode = TextServer.AUTOWRAP_OFF
	disclaimer.text = "A game, not a diagnosis: a flagged group is a reason to see an eye care professional."
	footer.add_child(InfoButton.new("A game, not a diagnosis", ABOUT_DISCLAIMER))
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_narrow = size.x < NARROW
	if _narrow:
		_compact_header()
	resized.connect(func():
		if (size.x < NARROW) != _narrow:
			_narrow = size.x < NARROW
			_compact_header()
			_build()
	)
	_build()


## Narrower Export and Clear buttons, so the header fits a narrow page.
func _compact_header() -> void:
	for b in [export_button, clear]:
		b.custom_minimum_size.x = 170.0 if _narrow else 220.0


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
		PopupCard.info(self, "Couldn't save the spreadsheet", "Something went wrong writing %s (%s). Try another folder." % [path.get_file(), error_string(err)])
		return
	PopupCard.info(self, "Spreadsheet saved", "Saved as %s, one sheet per session." % path.get_file())


func _on_clear() -> void:
	var wipe := func():
		Stats.clear()
		_build()
	PopupCard.confirm(self, "Clear all stats?",
			"Every record of every session will be deleted. Export a spreadsheet first if you want to keep them. This can't be undone.",
			"Clear everything", wipe, "Keep them", true)


func _build() -> void:
	for child in cards.get_children():
		child.queue_free()
	var summary := Stats.summarize(Stats.load_records())
	summary_label.text = "%d pieces over %d session%s" % [summary.pieces, summary.sessions, "" if summary.sessions == 1 else "s"]
	if summary.usual_ms >= 0:
		summary_label.text += "  ·  usually spots a piece in %.1f s, late past %.1f s" % [summary.usual_ms / 1000.0, summary.late_ms / 1000.0]

	# The groups in use, then any recorded group no longer in use, most worrying first.
	var groups: Array = ColorGroups.active(ColorGroups.load_settings()).duplicate()
	for article in ColorGroups.ARTICLE:
		if summary.groups.has(article.id) and not groups.any(func(g): return g.id == article.id):
			groups.append(article)
	var names := {Stats.BASELINE: "No filter", Stats.EXTRA: "Extra shapes"}
	for group in groups:
		names[group.id] = group.name
	groups.sort_custom(func(a, b):
		return LEVEL_ORDER.find(Stats.reading(summary, a.id, names).level) < LEVEL_ORDER.find(Stats.reading(summary, b.id, names).level)
	)

	_heading("Color groups", "One card for each type of color blindness the game checks, most worrying first.", "Reading the color groups", ABOUT_VERDICTS)
	for group in groups:
		_add_card(summary, group.id, group.name, "%s · %s" % [group.kind, group.prevalence], group, names)
	_heading("Checks to compare with", "Shapes everyone can see. Doing well here means misses above point to color.", "Why these checks", ABOUT_CHECKS)
	if summary.groups.has(Stats.EXTRA):
		_add_card(summary, Stats.EXTRA, names[Stats.EXTRA], "Shapes every type can see, in the filtered levels", EXTRA_PLATE, names)
	_add_card(summary, Stats.BASELINE, names[Stats.BASELINE], "Levels played without the dots", BASELINE_PLATE, names)


## A section title with a one-line explanation and a ? for the rest.
func _heading(title: String, line: String, about_title: String, about: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_outline_color", Color.WHITE)
	label.add_theme_constant_override("outline_size", 10)
	row.add_child(label)
	row.add_child(InfoButton.new(about_title, about))
	box.add_child(row)
	box.add_child(_wrapped(line, MUTED, 19))
	if cards.get_child_count() > 0:
		var space := Control.new()
		space.custom_minimum_size = Vector2(0, 14)
		cards.add_child(space)
	cards.add_child(box)


## One group's card: its plate, name and verdict, the main reason, what
## happened to its pieces, and three big numbers. Tapping it opens the details.
func _add_card(summary: Dictionary, id: String, title: String, subtitle: String, plate_colors: Dictionary, names: Dictionary) -> void:
	var g: Dictionary = summary.groups.get(id, Stats._empty())
	var reading := Stats.reading(summary, id, names)

	var card := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14 if _narrow else 24)
	card.add_child(row)

	var plate: Control = GroupPlate.new()
	plate.custom_minimum_size = Vector2.ONE * (84 if _narrow else 124)
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.background = plate_colors.background
	plate.colors = plate_colors.colors
	plate.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(plate)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 12)
	row.add_child(middle)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", 30)
	head.add_child(name_label)
	head.add_child(_badge(reading.level))
	middle.add_child(head)
	middle.add_child(_wrapped(subtitle, MUTED, 18))
	middle.add_child(_wrapped(reading.lines[0], Icons.INK, 21))

	var numbers := HBoxContainer.new()
	numbers.add_theme_constant_override("separation", 18 if _narrow else 36)
	var outcome := VBoxContainer.new()
	outcome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outcome.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	outcome.add_theme_constant_override("separation", 6)
	var bar := OutcomeBar.new()
	bar.custom_minimum_size = Vector2(140 if _narrow else 220, 22)
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.counts = [g.found - g.late, g.late, g.seen, g.missed]
	outcome.add_child(bar)
	outcome.add_child(_wrapped("%d found  ·  %d late  ·  %d touched only  ·  %d missed" % [g.found - g.late, g.late, g.seen, g.missed], MUTED, 17))
	numbers.add_child(outcome)
	numbers.add_child(_tile("%d%%" % roundi(Stats.miss_rate(g) * 100) if g.shown else "–", "missed",
			MISSED_TEXT if g.missed else Icons.INK))
	numbers.add_child(_tile(str(g.late), "found late", LATE_TEXT if g.late else Icons.INK))
	numbers.add_child(_tile("%.1f s" % (g.median_ms / 1000.0) if g.median_ms >= 0 else "–", "to spot one", Icons.INK))
	middle.add_child(numbers)

	var more := Button.new()
	more.text = "See details"
	more.custom_minimum_size = Vector2(130 if _narrow else 170, 56)
	more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	more.add_theme_font_size_override("font_size", 20)
	more.pressed.connect(_open_details.bind(summary, id, title, subtitle, plate_colors, names))
	row.add_child(more)

	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(event):
		# DragScroll only lets a press through once it is sure it is a tap.
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_open_details(summary, id, title, subtitle, plate_colors, names)
	)
	cards.add_child(card)


# ---------- Details pop-up ----------

## One group's stats spelled out: the outcome bar and spot times drawn large
## with labels, each number explained, every color on its own line, and what
## it all means.
func _open_details(summary: Dictionary, id: String, title: String, subtitle: String, plate_colors: Dictionary, names: Dictionary) -> void:
	if is_instance_valid(_details):
		return
	var g: Dictionary = summary.groups.get(id, Stats._empty())
	var reading := Stats.reading(summary, id, names)
	_details = PopupCard.open(self, title, 0.8)
	var popup := _details

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	var plate: Control = GroupPlate.new()
	plate.custom_minimum_size = Vector2(150, 150)
	plate.background = plate_colors.background
	plate.colors = plate_colors.colors
	head.add_child(plate)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", 10)
	titles.add_child(_wrapped(subtitle, MUTED, 20))
	var badge := _badge(reading.level)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	titles.add_child(badge)
	head.add_child(titles)
	popup.body.add_child(head)

	var meaning := _section(popup, "What it means")
	for text in reading.lines:
		meaning.add_child(_wrapped("•  " + text, Icons.INK, 21))

	var outcomes := _section(popup, "What happened to the %d pieces" % g.shown)
	var bar := OutcomeBar.new()
	bar.custom_minimum_size = Vector2(0, 34)
	bar.counts = [g.found - g.late, g.late, g.seen, g.missed]
	outcomes.add_child(bar)
	var late_note := "found, but much slower than usual (needs more play to tell)"
	if summary.late_ms >= 0:
		late_note = "found, but took over %.1f s: most likely not seen at first" % (summary.late_ms / 1000.0)
	for entry in [[FOUND, g.found - g.late, "found in time", "spotted at the usual speed and put in their hole"],
			[LATE, g.late, "found late", late_note],
			[SEEN, g.seen, "touched only", "picked up but never put in their hole"],
			[MISSED, g.missed, "missed", "never touched before the level ended"]]:
		outcomes.add_child(_legend(entry[0], "%d %s" % [entry[1], entry[2]], entry[3]))

	var numbers := _section(popup, "The numbers")
	var tiles := HFlowContainer.new()
	tiles.add_theme_constant_override("h_separation", 40)
	tiles.add_theme_constant_override("v_separation", 18)
	tiles.add_child(_big_tile("%d%%" % roundi(Stats.miss_rate(g) * 100) if g.shown else "–", "missed",
			"%d of %d pieces never touched" % [g.missed, g.shown]))
	tiles.add_child(_big_tile(str(g.late), "found late", "found much slower than usual"))
	tiles.add_child(_big_tile("%.1f s" % (g.median_ms / 1000.0) if g.median_ms >= 0 else "–", "to spot one",
			"half the pieces were spotted faster than this"))
	tiles.add_child(_big_tile(str(g.hesitations), "over 30 s", "the article's sign of hesitation"))
	tiles.add_child(_big_tile(str(g.wrong), "wrong holes", "about matching shapes, not seeing colors"))
	numbers.add_child(tiles)

	var times := _section(popup, "How fast each piece was spotted")
	var strip := TimeStrip.new()
	strip.custom_minimum_size = Vector2(0, 70)
	strip.times = g.spot_ms
	strip.late_ms = summary.late_ms
	strip.ticks = true
	times.add_child(strip)
	var late_line := ""
	if summary.late_ms >= 0:
		late_line = " (past %.1f s, against the usual %.1f s)" % [summary.late_ms / 1000.0, summary.usual_ms / 1000.0]
	times.add_child(_wrapped("Each dot is one piece; further right is slower. Yellow line: a late find%s. Red line: 30 s, where the article counts a child as hesitating." % late_line, MUTED, 18))

	if not g.colors.is_empty():
		var colors := _section(popup, "By color")
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
			line.text = "%d shown  ·  %d missed  ·  %d found late" % [c.shown, c.missed, c.late]
			if typical >= 0:
				line.text += "  ·  %.1f s to spot" % (typical / 1000.0)
			line.add_theme_font_size_override("font_size", 20)
			line.add_theme_color_override("font_color", MISSED_TEXT if c.missed else LATE_TEXT if c.late else Icons.INK)
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(line)
			colors.add_child(row)
	popup.add_button("Close", popup.close, Color("ffd166"))


## A titled part of the details pop-up, below a line; returns the box for its contents.
func _section(popup: PopupCard, title: String) -> VBoxContainer:
	popup.body.add_child(HSeparator.new())
	return popup.add_section(title)


func _legend(color: Color, what: String, meaning: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var chip := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color = Icons.INK
	chip.add_theme_stylebox_override("panel", style)
	chip.custom_minimum_size = Vector2(24, 24)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)
	var label := Label.new()
	label.text = what
	label.add_theme_font_size_override("font_size", 21)
	row.add_child(label)
	var note := _wrapped(meaning, MUTED, 18)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(note)
	return row


func _big_tile(value: String, caption: String, meaning: String) -> VBoxContainer:
	var tile := VBoxContainer.new()
	tile.custom_minimum_size = Vector2(210, 0)
	tile.add_theme_constant_override("separation", 2)
	var big := Label.new()
	big.text = value
	big.add_theme_font_size_override("font_size", 46)
	tile.add_child(big)
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 21)
	tile.add_child(label)
	var note := _wrapped(meaning, MUTED, 17)
	note.custom_minimum_size = Vector2(210, 0)
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
	style.set_corner_radius_all(99)
	style.set_border_width_all(3)
	style.border_color = Icons.INK
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", style)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_PASS
	var label := Label.new()
	label.text = LEVEL_NAMES[level]
	label.add_theme_font_size_override("font_size", 20)
	badge.add_child(label)
	return badge


func _tile(value: String, caption: String, color: Color) -> VBoxContainer:
	var tile := VBoxContainer.new()
	tile.custom_minimum_size = Vector2(90 if _narrow else 110, 0)
	tile.add_theme_constant_override("separation", 0)
	var big := Label.new()
	big.text = value
	big.add_theme_font_size_override("font_size", 38)
	big.add_theme_color_override("font_color", color)
	tile.add_child(big)
	tile.add_child(_wrapped(caption, MUTED, 17))
	return tile


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
				draw_string(font, Vector2(clampf(x - 16, 0, size.x - 40), size.y - 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, MUTED)
		draw_line(Vector2(0, mid), Vector2(size.x, mid), TRACK, 4)
		draw_line(Vector2(_x(Stats.HESITATION_MS), 2), Vector2(_x(Stats.HESITATION_MS), size.y - 2), MISSED, 2)
		if late_ms >= 0:
			draw_line(Vector2(_x(late_ms), 2), Vector2(_x(late_ms), size.y - 2), LATE, 2)
		for ms in times:
			var color := MISSED if ms > Stats.HESITATION_MS else LATE if late_ms >= 0 and ms > late_ms else FOUND
			draw_circle(Vector2(_x(ms), mid), 6, Color(color, 0.75))
