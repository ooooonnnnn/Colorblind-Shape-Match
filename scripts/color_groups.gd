extends RefCounted
## Color groups: a background color plus a few shapes, each with its own color,
## designed together so the shapes vanish into the background for one kind of
## color vision deficiency. ARTICLE holds the groups taken from the research
## articles; color_groups.json picks whether those or custom colors are used,
## and which group is played.
##
## Sources: "Advanced Colorimetry Protocols and Design in Color Vision
## Deficiency Diagnosis for Children Using Pseudoisochromatic Plates" (color
## pairs, shapes) and "Comprehensive Research Report on Color Vision
## Deficiencies" (prevalence). Each group's colors share one CIELAB lightness,
## so no shape stands out by brightness alone, as the first article requires.

const PATH := "res://color_groups.json"
const RANDOM := "random"  # the play setting that picks a new group every level

const ARTICLE := [
	{
		"id": "red_green",
		"name": "Red-green screening",
		"about": "Ishihara / CVTME vanishing plates: red, orange and red-purple on yellow-green to blue-green. Protan and deutan, ~8% of males, ~0.5% of females.",
		"background": Color("519b5c"),
		"shapes": {"circle": Color("e0655e"), "star": Color("ca7737"), "square": Color("cd6b9a")},
	},
	{
		"id": "transformation",
		"name": "Transformation",
		"about": "Inverted plates: unsaturated blue-green and yellow-green on red-orange. Protan and deutan, ~8% of males, ~0.5% of females.",
		"background": Color("d76d49"),
		"shapes": {"circle": Color("389a94"), "star": Color("859153"), "square": Color("389a94")},
	},
	{
		"id": "protan_deutan",
		"name": "Protan vs deutan",
		"about": "Ishihara plates 26/27: purple-magenta (protan line) and red (deutan line) on neutral gray. Protan ~2%, deutan ~6% of males.",
		"background": Color("8b8b8b"),
		"shapes": {"circle": Color("ab79b9"), "star": Color("cc726a"), "square": Color("ab79b9")},
	},
	{
		"id": "hrr_protan",
		"name": "HRR protan",
		"about": "HRR: unsaturated red and cyan on neutral gray. Protan, ~2% of males.",
		"background": Color("919191"),
		"shapes": {"circle": Color("c57e7c"), "triangle": Color("4e9d9f"), "square": Color("c57e7c")},
	},
	{
		"id": "hrr_deutan",
		"name": "HRR deutan",
		"about": "HRR: green and magenta on neutral gray. Deutan, ~6% of males (the most common deficiency).",
		"background": Color("919191"),
		"shapes": {"circle": Color("729b6e"), "triangle": Color("b281ab"), "square": Color("729b6e")},
	},
	{
		"id": "hrr_tritan",
		"name": "HRR tritan",
		"about": "HRR: blue-purple and yellow-green on neutral gray. Tritan, under 0.01%, males and females alike.",
		"background": Color("919191"),
		"shapes": {"circle": Color("8e8bc0"), "triangle": Color("91945e"), "square": Color("8e8bc0")},
	},
]


static func article_group(id: String) -> Dictionary:
	for group in ARTICLE:
		if group.id == id:
			return group
	return ARTICLE[0]


## {custom: bool, play: group id or RANDOM, colors: {id: {background, shapes}}}.
## colors holds the custom colors, filled in from ARTICLE where the file has none.
static func load_settings() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else {}
	if not data is Dictionary:
		push_error("Bad color group config in %s" % PATH)
		data = {}
	var saved = data.get("custom_colors")
	if not saved is Dictionary:
		saved = {}
	var colors := {}
	for group in ARTICLE:
		var entry = saved.get(group.id)
		if not entry is Dictionary:
			entry = {}
		var shapes = entry.get("shapes")
		if not shapes is Dictionary:
			shapes = {}
		colors[group.id] = {
			"background": Color.from_string(str(entry.get("background", "")), group.background),
			"shapes": {},
		}
		for shape_name in group.shapes:
			colors[group.id].shapes[shape_name] = Color.from_string(str(shapes.get(shape_name, "")), group.shapes[shape_name])
	var play := str(data.get("play", ARTICLE[0].id))
	if play != RANDOM and article_group(play).id != play:
		play = ARTICLE[0].id
	return {"custom": data.get("mode") == "custom", "play": play, "colors": colors}


static func save_settings(settings: Dictionary) -> Error:
	var custom_colors := {}
	for id in settings.colors:
		var shapes := {}
		for shape_name in settings.colors[id].shapes:
			shapes[shape_name] = "#" + settings.colors[id].shapes[shape_name].to_html(false)
		custom_colors[id] = {"background": "#" + settings.colors[id].background.to_html(false), "shapes": shapes}
	var data := {
		"mode": "custom" if settings.custom else "article",
		"play": settings.play,
		"custom_colors": custom_colors,
	}
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t", false) + "\n")
	return OK


## The group to play next: the chosen one, or a random one.
static func pick(settings: Dictionary) -> String:
	if settings.play == RANDOM:
		return ARTICLE.pick_random().id
	return settings.play


## {background, shapes: {shape name: color}} for group id, from the article or
## the custom colors as settings say.
static func colors(settings: Dictionary, id: String) -> Dictionary:
	if settings.custom:
		return settings.colors[id]
	var group := article_group(id)
	return {"background": group.background, "shapes": group.shapes}
