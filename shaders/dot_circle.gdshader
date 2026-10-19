shader_type canvas_item;
// One circle of the dot effect, drawn on a unit quad. Finds which shape color,
// if any, the screen shows under the circle's center and fills with it, or
// with the background color otherwise.

const int BASE_COUNT = 7;        // background, then one per shape
const float MATCH = 0.08;        // how close the screen must be to a shape color to count as it

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec4 bases[BASE_COUNT];

void fragment() {
	vec2 from_center = UV - 0.5;
	if (length(from_center) > 0.5) {
		discard;
	}
	// The quad is axis-aligned, so screen UV per quad UV is constant across it.
	vec2 scale = vec2(dFdx(SCREEN_UV.x) / dFdx(UV.x), dFdy(SCREEN_UV.y) / dFdy(UV.y));
	vec3 seen = texture(screen_tex, SCREEN_UV - from_center * scale).rgb;

	// Glows, shadows and blended edges match nothing, so they read as background.
	int base = 0;
	float nearest = MATCH;
	for (int j = 1; j < BASE_COUNT; j++) {
		float d = distance(seen, bases[j].rgb);
		if (d < nearest) {
			nearest = d;
			base = j;
		}
	}
	COLOR = bases[base];
}
