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
## Deficiencies" (prevalence). Each group's colors share one CIELAB lightness,
## so no piece stands out by brightness alone, as the first article requires.

const PATH := "res://color_groups.json"
const RANDOM := "random"  # a level sequence's colors setting that picks a new group every level
const MAX_COLORS := 6  # figure colors per group; must match BASE_COUNT - 1 in dot_circle.gdshader
const LIGHTNESS_TOLERANCE := 5.0  # CIELAB L* a color may differ from its background before it shows by brightness

const ARTICLE := [
	{
		"id": "protan",
		"name": "Protan",
		"kind": "Red-weak (L-cones)",
		"prevalence": "~2% of males",
		"about": "Reds, oranges and purple-magenta on yellow-green: protans confuse red with yellow-green, and purple-magenta lies on the protan line (Ishihara plates 26/27). Protanomaly ~1% and protanopia ~1% of males.",
		"background": Color("7c9449"),
		"colors": [Color("e0655e"), Color("d76d49"), Color("c47a3e"), Color("bc72b3"), Color("d1689b")],
	},
	{
		"id": "deutan",
		"name": "Deutan",
		"kind": "Green-weak (M-cones)",
		"prevalence": "~6% of males, the most common",
		"about": "Red, magenta, purple and pink on green: deutans confuse green with purple-magenta, and red lies on the deutan line (Ishihara plates 26/27, HRR green/magenta). Deuteranomaly ~5% and deuteranopia ~1% of males.",
		"background": Color("489b6d"),
		"colors": [Color("e0655e"), Color("bc72b3"), Color("9e7ec1"), Color("d36a8d"), Color("d76d49")],
	},
	{
		"id": "tritan",
		"name": "Tritan",
		"kind": "Blue-weak (S-cones)",
		"prevalence": "under 0.01%, males and females alike",
		"about": "Blues, violets and yellows on neutral gray: tritans confuse blue, yellow and purple, and HRR tritan plates put blue-purple and yellow-green across the gray point.",
		"background": Color("8b8b8b"),
		"colors": [Color("8785c3"), Color("a27eb7"), Color("608fbf"), Color("8b9051"), Color("9d8a4d")],
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


## CIELAB lightness (L*, 0 black to 100 white) of an sRGB color.
static func lightness(color: Color) -> float:
	var y := 0.2126 * _linear(color.r) + 0.7152 * _linear(color.g) + 0.0722 * _linear(color.b)
	return 116.0 * pow(y, 1.0 / 3.0) - 16.0 if y > 0.008856 else 903.3 * y


static func _linear(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)
