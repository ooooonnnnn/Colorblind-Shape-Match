shader_type canvas_item;
// One circle of the dot effect, drawn on a unit quad. Fills with the screen
// color found under the circle's center.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

void fragment() {
	vec2 from_center = UV - 0.5;
	if (length(from_center) > 0.5) {
		discard;
	}
	// The quad is axis-aligned, so screen UV per quad UV is constant across it.
	vec2 scale = vec2(dFdx(SCREEN_UV.x) / dFdx(UV.x), dFdy(SCREEN_UV.y) / dFdy(UV.y));
	COLOR = texture(screen_tex, SCREEN_UV - from_center * scale);
}
