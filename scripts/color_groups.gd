extends RefCounted
## Color groups, one per type of color vision deficiency: a background color and
## a palette of figure colors that all fall on that type's confusion lines, so
## pieces in any of them vanish into the background for that type. Pieces take
## colors from the palette, more of it the more pieces a level has (see
## piece_colors). ARTICLE holds the groups taken from the research articles and
## never changes; color_groups.json holds whether those or the player's own copy
## (recolored, with colors added or removed, or groups deleted) is used. These
## are the groups available; each level sequence picks one of them or a random
## one (see LevelConfig).
##
## Sources: "Advanced Colorimetry Protocols and Design in Color Vision
## Deficiency Diagnosis for Children Using Pseudoisochromatic Plates" (confusion
## colors, backgrounds) and "Comprehensive Research Report on Color Vision
## Deficiencies" (prevalence). A color looks exactly like the background to a
## type when it differs only in the cone that type is missing: it then lies on
## the type's confusion line through the background, the line through the
## article's copunctal point, and the type sees it at the same brightness too,
## as the first article requires. Each figure color here is its background
## with only the missing cone raised or lowered (see color_vision.gd), by more for
## each color, so the palette runs from pale to vivid for normal vision.

const Vision := preload("res://scripts/color_vision.gd")
const PATH := "res://color_groups.json"
const RANDOM := "random"  # a level sequence's colors setting that picks a new group every level
const MAX_COLORS := 6  # figure colors per group
const MAX_EXTRA_COLORS := 2  # colors for extra shapes; with MAX_COLORS, must match BASE_COUNT - 1 in dot_circle.gdshader
const MATCH_TOLERANCE := 5.0  # CIELAB distance a color may show from its background, to its type, and still blend in

const ARTICLE := [
	{
		"id": "protan",
		"name": "Protan",
		"kind": "Red-weak (L-cones)",
		"prevalence": "~2% of males",
		"about": "Salmon reds and oranges on green, between yellow-green and blue-green: protans confuse red with yellow-green, and reds look dark to them. Every color is on the protan confusion line through the background, so only the L-cone tells them apart. Protanomaly ~1% and protanopia ~1% of males.",
		"background": Color("559c68"),
		"colors": [Color("b59267"), Color("c98e67"), Color("db8b67"), Color("eb8767"), Color("fa8366")],
	},
	{
		"id": "deutan",
		"name": "Deutan",
		"kind": "Green-weak (M-cones)",
		"prevalence": "~6% of males, the most common",
		"about": "Mauves and magentas on green: deutans confuse green with purple-magenta (HRR green/magenta). Every color is on the deutan confusion line through the background, so only the M-cone tells them apart. Deuteranomaly ~5% and deuteranopia ~1% of males.",
		"background": Color("489b6d"),
		"colors": [Color("8c807b"), Color("9f7180"), Color("b06085"), Color("be498a"), Color("cc248f")],
	},
	{
		"id": "tritan",
		"name": "Tritan",
		"kind": "Blue-weak (S-cones)",
		"prevalence": "under 0.01%, males and females alike",
		"about": "Violets and yellow-greens on neutral gray, as HRR tritan plates put blue-purple and yellow-green across the gray point. Every color is on the tritan confusion line through the background, so only the S-cone tells them apart.",
		"background": Color("8b8b8b"),
		"colors": [Color("977fc7"), Color("9d76e3"), Color("a46dfb"), Color("839245"), Color("819420")],
	},
]


## A fresh copy of the article groups, for the player to edit.
static func article_copy() -> Array:
	return ARTICLE.duplicate(true)


## {custom: bool, groups: the player's own groups, each like an ARTICLE entry}.
static func load_settings() -> Dictionary:
	var path := SettingsFile.read_path(PATH)
	var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	if not data is Dictionary:
		push_error("Bad color group config in %s" % PATH)
		data = {}
	var groups := []
	var saved = data.get("custom_groups")
	if saved is Array:
		for entry in saved:
			if not (entry is Dictionary and entry.get("colors") is Array and not entry.colors.is_empty()):
				continue  # also skips groups saved before groups had palettes
			var article := _article(str(entry.get("id", "")))
			var colors := []
			for hex in entry.colors.slice(0, MAX_COLORS):
				colors.append(Color.from_string(str(hex), Color.WHITE))
			groups.append({
				"id": str(entry.get("id", "group_%d" % groups.size())),
				"name": str(entry.get("name", article.get("name", "Group"))),
				"kind": article.get("kind", ""),
				"prevalence": article.get("prevalence", ""),
				"about": article.get("about", ""),
				"background": Color.from_string(str(entry.get("background", "")), Color.GRAY),
				"colors": colors,
			})
	if groups.is_empty():
		groups = article_copy()
	return {"custom": data.get("mode") == "custom", "groups": groups}


static func save_settings(settings: Dictionary) -> Error:
	var groups := []
	for group in settings.groups:
		groups.append({
			"id": group.id,
			"name": group.name,
			"background": "#" + group.background.to_html(false),
			"colors": group.colors.map(func(c): return "#" + c.to_html(false)),
		})
	var data := {"mode": "custom" if settings.custom else "article", "custom_groups": groups}
	var file := FileAccess.open(SettingsFile.write_path(PATH), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t", false) + "\n")
	return OK


static func _article(id: String) -> Dictionary:
	for group in ARTICLE:
		if group.id == id:
			return group
	return {}


## The groups in use: the article's, or the player's own when custom.
static func active(settings: Dictionary) -> Array:
	return settings.groups if settings.custom else ARTICLE


## The group in use with this id, or {} if there is none.
static func find(settings: Dictionary, id: String) -> Dictionary:
	for group in active(settings):
		if group.id == id:
			return group
	return {}


## The id of the group to play: choice, if it is a group in use, or else (as
## for RANDOM) a random one of them.
static func pick(settings: Dictionary, choice := RANDOM) -> String:
	var group := find(settings, choice)
	if group.is_empty():
		group = active(settings).pick_random()
	return group.id


## Indices into a palette of palette_size colors for piece_count pieces, where
## piece i is copy i / shape_count of shape i % shape_count, as the game lays
## them out. A level uses one color per piece up to the whole palette, picked
## at random, and copies of one shape take different colors where there are
## enough.
static func piece_colors(palette_size: int, shape_count: int, piece_count: int) -> Array[int]:
	var order := range(palette_size)
	order.shuffle()
	var used := mini(palette_size, piece_count)
	var indices: Array[int] = []
	for i in piece_count:
		indices.append(order[(i % shape_count + i / shape_count) % used])
	return indices


## Up to MAX_EXTRA_COLORS colors for extra shapes (see ExtraShapes) in group:
## its background with one of the cones its type still has raised or lowered,
## until that type sees it about difference (CIELAB) from the background, or
## as far as sRGB allows. Being off the type's confusion lines, they show to
## it and to normal vision alike. The colors closest to difference are picked.
static func extra_colors(group: Dictionary, difference: float) -> Array[Color]:
	var missing: int = Vision.TYPES[group.id].cone if Vision.TYPES.has(group.id) else -1
	var found: Array[Dictionary] = []
	for cone in 3:
		if cone == missing:
			continue
		for direction in [1.0, -1.0]:
			var best := {}
			for step in range(1, 400):
				var color = Vision.shift_cone(group.background, cone, 1.0 + direction * step * 0.01)
				if color == null:
					break
				best = {"color": color, "seen": seen_difference(group.id, color, group.background)}
				if best.seen >= difference:
					break
			if best:
				found.append(best)
	found.sort_custom(func(a, b): return minf(a.seen, difference) > minf(b.seen, difference))
	var colors: Array[Color] = []
	for entry in found.slice(0, MAX_EXTRA_COLORS):
		colors.append(entry.color)
	return colors


## How far apart color and background look to the type of color blindness
## group_id is made for (CIELAB distance; within MATCH_TOLERANCE they blend
## in), or to normal vision for a group that is no type.
static func seen_difference(group_id: String, color: Color, background: Color) -> float:
	if Vision.TYPES.has(group_id):
		color = Vision.simulate(color, group_id)
		background = Vision.simulate(background, group_id)
	return _lab(color).distance_to(_lab(background))


## CIELAB (L*, a*, b*) of an sRGB color, against a D65 white.
static func _lab(color: Color) -> Vector3:
	var c := color.srgb_to_linear()
	var xyz := Vector3(
			0.4124564 * c.r + 0.3575761 * c.g + 0.1804375 * c.b,
			0.2126729 * c.r + 0.7151522 * c.g + 0.0721750 * c.b,
			0.0193339 * c.r + 0.1191920 * c.g + 0.9503041 * c.b) / Vector3(0.95047, 1.0, 1.08883)
	var f := Vector3.ZERO
	for i in 3:
		f[i] = pow(xyz[i], 1.0 / 3.0) if xyz[i] > 0.008856 else 7.787 * xyz[i] + 16.0 / 116.0
	return Vector3(116.0 * f.y - 16.0, 500.0 * (f.x - f.y), 200.0 * (f.y - f.z))
