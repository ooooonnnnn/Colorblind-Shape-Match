shader_type canvas_item;
// Shows the screen as someone with a type of color blindness sees it (see
// color_vision.gd for the model). The matrices work on linear RGB, so the
// screen's sRGB colors are converted to linear and back around them. Each
// color takes side_a or side_b by which side of the separation plane it is on.
// severity blends from normal vision (0) to the full dichromacy (1), the way
// milder, anomalous forms lie in between.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform mat3 side_a = mat3(1.0);
uniform mat3 side_b = mat3(1.0);
uniform vec3 separation;
uniform float severity : hint_range(0.0, 1.0) = 1.0;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

void fragment() {
	vec3 linear = to_linear(texture(screen_tex, SCREEN_UV).rgb);
	mat3 simulation = dot(separation, linear) >= 0.0 ? side_a : side_b;
	vec3 simulated = clamp(simulation * linear, 0.0, 1.0);
	COLOR = vec4(to_srgb(mix(linear, simulated, severity)), 1.0);
}
