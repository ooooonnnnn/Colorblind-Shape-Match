extends Control
## The references screen: a card per research area listing the sources the
## game is based on (see References), numbered, each with a link that opens
## in the browser.

const References := preload("res://scripts/references.gd")
const LINK := Color("2f6fb0")

@onready var cards: VBoxContainer = %Cards
@onready var back: ToyButton = %Back


func _ready() -> void:
	back.activated.connect(func():
		await get_tree().create_timer(0.15).timeout  # let the button's pop play
		get_tree().change_scene_to_file("res://menu.tscn")
	)
	var number := 1
	for section in References.SECTIONS:
		var card := PanelContainer.new()
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 12)
		card.add_child(body)
		var heading := Label.new()
		heading.text = section.title
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		heading.add_theme_font_size_override("font_size", 26)
		body.add_child(heading)
		for ref in section.refs:
			body.add_child(_entry(number, ref))
			number += 1
		cards.add_child(card)


## One numbered reference, its link underneath.
func _entry(number: int, ref: Dictionary) -> RichTextLabel:
	var entry := RichTextLabel.new()
	entry.bbcode_enabled = true
	entry.fit_content = true
	entry.scroll_active = false
	entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_theme_font_size_override("normal_font_size", 18)
	entry.add_theme_font_size_override("bold_font_size", 18)
	entry.add_theme_color_override("default_color", Icons.INK)
	entry.text = "[b]%d.[/b] %s\n[color=#%s][url=%s]%s[/url][/color]" % [
			number, _escape(ref.text), LINK.to_html(false), ref.url, _escape(ref.url)]
	entry.meta_clicked.connect(func(url): OS.shell_open(str(url)))
	entry.meta_hover_started.connect(func(_url): entry.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND)
	entry.meta_hover_ended.connect(func(_url): entry.mouse_default_cursor_shape = Control.CURSOR_ARROW)
	return entry


## Shows square brackets as text instead of reading them as markup.
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
