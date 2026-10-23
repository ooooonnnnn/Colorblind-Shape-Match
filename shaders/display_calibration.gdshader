shader_type canvas_item;
// Runs every pixel of the screen through the calibration's 3D lookup table
// (see display_calibration.gd). The table is 32 slices of 32x32 laid side by
// side, one per blue level, with red across each slice and green down it, so
// a 2D texture serves on every device. Within a slice the texture's own
// filtering blends red and green; between the two nearest slices the shader
// blends by hand.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D lut : filter_linear, repeat_disable;

const float N = 32.0;

vec3 look(float slice, vec3 c) {
	vec2 uv = vec2((slice * N + c.r * (N - 1.0) + 0.5) / (N * N), (c.g * (N - 1.0) + 0.5) / N);
	return texture(lut, uv).rgb;
}

void fragment() {
	vec3 c = clamp(texture(screen_tex, SCREEN_UV).rgb, 0.0, 1.0);
	float b = c.b * (N - 1.0);
	float b0 = floor(b);
	float b1 = min(b0 + 1.0, N - 1.0);
	COLOR = vec4(mix(look(b0, c), look(b1, c), b - b0), 1.0);
}
