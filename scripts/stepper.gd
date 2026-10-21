class_name Stepper
extends VBoxContainer
## A caption over a big number between round − and + buttons: easier to read
## and to hit than a spin box.

signal changed(value: float)

var min_value := 1.0
var max_value := 99.0
var step := 1.0
var suffix := ""
var value := 1.0:
	set(v):
		value = clampf(v, min_value, max_value)
		if _number:
			_number.text = ("%d" % value if value == int(value) else str(value)) + suffix
			_minus.disabled = value <= min_value
			_plus.disabled = value >= max_value
var editable := true:
	set(v):
		editable = v
		modulate.a = 1.0 if v else 0.4
		mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE
		for b in [_minus, _plus]:
			if b:
				b.disabled = not v

var _number := Label.new()
var _minus := ToyButton.new()
var _plus := ToyButton.new()


func _init(caption: String, from: float, to: float, start: float, by := 1.0, unit := "") -> void:
	min_value = from
	max_value = to
	step = by
	suffix = unit
	add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for b in [_minus, _plus]:
		b.custom_minimum_size = Vector2(46, 46)
		b.color = Color("fff3d6")
		b.icon_color = Color.WHITE
	_minus.picture = "minus"
	_plus.picture = "plus"
	_minus.activated.connect(func(): _nudge(-step))
	_plus.activated.connect(func(): _nudge(step))
	_number.custom_minimum_size = Vector2(64, 0)
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_number.add_theme_font_size_override("font_size", 28)
	row.add_child(_minus)
	row.add_child(_number)
	row.add_child(_plus)
	add_child(row)
	value = start


func _nudge(by: float) -> void:
	if not editable:
		return
	var before := value
	value += by
	if value != before:
		changed.emit(value)
