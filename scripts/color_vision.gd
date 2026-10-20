extends CanvasLayer
## Color blind mode: shows the whole game, every screen, as someone with one
## type of color blindness sees it. An autoload, so it stays over each scene;
## it sits above every other layer, the dot filter and effects included, so it
## changes only what the player sees, never which dots show a shape.
##
## The simulation follows the research articles (see ColorGroups): each type
## is missing one cone, and colors on one of its confusion lines, the straight
## lines through its copunctal point on the CIE 1931 xy diagram, look the same
## to it. The cones are set up so their missing axes point exactly at those
## copunctal points, and a color is moved along the missing cone's axis onto
## what that type still sees (Brettel, Viénot and Mollon, 1997), so colors on
## one confusion line come out identical.

const PATH := "res://color_vision.json"
const NONE := "none"
## Name, description, the missing cone (0 L, 1 M, 2 S), its CIE 1931 copunctal
## point, and the two wavelengths (nm) whose colors look the same to that type
## as to normal vision (Brettel et al., 1997).
const TYPES := {
	"protan": {
		"name": "Protan",
		"about": "No working red (L) cones. Reds look dark, and red runs together with yellow-green and gray. About 2% of males.",
		"cone": 0, "copunctal": Vector2(0.747, 0.253), "anchors": [475, 575],
	},
	"deutan": {
		"name": "Deutan",
		"about": "No working green (M) cones, the most common type. Green runs together with purple-magenta and gray. About 6% of males.",
		"cone": 1, "copunctal": Vector2(1.080, -0.800), "anchors": [475, 575],
	},
	"tritan": {
		"name": "Tritan",
		"about": "No working blue (S) cones, which is rare. Blue runs together with green, and yellow with pink and purple.",
		"cone": 2, "copunctal": Vector2(0.171, 0.000), "anchors": [485, 660],
	},
}
## CIE 1931 2° color matching functions (X, Y, Z) at the anchor wavelengths.
const SPECTRUM := {
	475: Vector3(0.1421, 0.1126, 1.0419),
	485: Vector3(0.0580, 0.1693, 0.6162),
	575: Vector3(0.8425, 0.9154, 0.0018),
	660: Vector3(0.1649, 0.0610, 0.0000),
}

var mode := NONE:  # NONE or a TYPES key
	set(v):
		mode = v if TYPES.has(v) else NONE
		_apply()
var severity := 1.0:  # 0 is normal vision, 1 the full form
	set(v):
		severity = clampf(v, 0.0, 1.0)
		_apply()

var _screen := ColorRect.new()


func _ready() -> void:
	layer = 128  # the highest, above the dots (100) and effects (101)
	_screen.material = ShaderMaterial.new()
	_screen.material.shader = preload("res://shaders/color_vision.gdshader")
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_screen)
	load_settings()


## Reads mode and severity from PATH; without the file, vision is normal.
func load_settings() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(SettingsFile.read_path(PATH)))
	if not data is Dictionary:
		data = {}
	mode = str(data.get("mode", NONE))
	severity = float(data.get("severity_percent", 100)) / 100
	_apply()  # in case the setters ran before the node counted as ready


func save_settings() -> Error:
	var file := FileAccess.open(SettingsFile.write_path(PATH), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"mode": mode, "severity_percent": roundi(severity * 100)}, "\t", false) + "\n")
	return OK


func _apply() -> void:
	if not is_node_ready():
		return
	_screen.visible = mode != NONE
	if mode == NONE:
		return
	var sim := simulation(mode)
	_screen.material.set_shader_parameter("side_a", sim.side_a)
	_screen.material.set_shader_parameter("side_b", sim.side_b)
	_screen.material.set_shader_parameter("separation", sim.separation)
	_screen.material.set_shader_parameter("severity", severity)


# ---------- The model ----------

## Linear sRGB to CIE XYZ (D65).
static func _rgb_to_xyz() -> Basis:
	return Basis(Vector3(0.4124564, 0.3575761, 0.1804375), Vector3(0.2126729, 0.7151522, 0.0721750),
			Vector3(0.0193339, 0.1191920, 0.9503041)).transposed()  # written as rows


## CIE XYZ to cone (L, M, S) responses whose axes have the TYPES copunctal
## points as their chromaticities, scaled so sRGB white is (1, 1, 1).
static func _xyz_to_lms() -> Basis:
	var axes: Array[Vector3] = []
	for type in TYPES.values():
		var p: Vector2 = type.copunctal
		axes.append(Vector3(p.x, p.y, 1.0 - p.x - p.y))
	var from_xyz := Basis(axes[0], axes[1], axes[2]).inverse()
	var white := from_xyz * (_rgb_to_xyz() * Vector3.ONE)
	return Basis.from_scale(Vector3.ONE / white) * from_xyz


static func _rgb_to_lms() -> Basis:
	return _xyz_to_lms() * _rgb_to_xyz()


## For type: two matrices from linear sRGB to what that type sees, in linear
## sRGB, one for each side of the plane through white along the missing cone,
## and that plane's normal; colors where dot(separation, rgb) >= 0 take side_a.
static func simulation(type: String) -> Dictionary:
	var info: Dictionary = TYPES[type]
	var k: int = info.cone
	var to_lms := _rgb_to_lms()
	var white := Vector3.ONE  # sRGB white, by _xyz_to_lms's scaling
	var axis := Vector3.ZERO
	axis[k] = 1.0
	var separation := white.cross(axis)
	var sides: Array[Basis] = []
	for wavelength in info.anchors:
		var anchor: Vector3 = _xyz_to_lms() * (SPECTRUM[wavelength] as Vector3)
		if sides.is_empty() and separation.dot(anchor) < 0:
			separation = -separation  # face the first anchor, so side_a is its side
		# The plane through white and the anchor: the missing cone is set so
		# the color lands on it, leaving the other two cones as they are.
		var normal := white.cross(anchor)
		var rows: Array[Vector3] = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
		var row := -normal / normal[k]
		row[k] = 0.0
		rows[k] = row
		var project := Basis(rows[0], rows[1], rows[2]).transposed()
		sides.append(to_lms.inverse() * project * to_lms)
	return {"side_a": sides[0], "side_b": sides[1], "separation": to_lms.transposed() * separation}


## How color looks to type, at severity (0 normal vision, 1 the full form).
static func simulate(color: Color, type: String, amount := 1.0) -> Color:
	var c := color.srgb_to_linear()
	var linear := Vector3(c.r, c.g, c.b)
	var sim := simulation(type)
	var seen: Vector3 = (sim.side_a if sim.separation.dot(linear) >= 0 else sim.side_b) * linear
	seen = linear.lerp(seen.clamp(Vector3.ZERO, Vector3.ONE), amount)
	return Color(seen.x, seen.y, seen.z).linear_to_srgb()
