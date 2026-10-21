shader_type canvas_item;
// One circle of the dot effect, drawn on a unit quad. Finds which figure color,
// if any, the screen shows under the circle's center and fills with it, or
// with the background color otherwise. The color's hue, saturation and value
// are then each shifted by their own Perlin noise, read at the circle's center.

const int BASE_COUNT = 9;        // background, up to ColorGroups.MAX_COLORS figure colors, then MAX_EXTRA_COLORS extra-shape colors
const float MATCH = 0.08;        // how close the screen must be to a shape color to count as it

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec4 bases[BASE_COUNT];
// Per channel (x = hue, y = saturation, z = value): wavelength in px, and the
// largest shift, in fractions of the hue wheel or of the 0-1 S and V range.
uniform vec3 background_wavelength = vec3(1.0);
uniform vec3 background_amplitude;
uniform vec3 shape_wavelength = vec3(1.0);
uniform vec3 shape_amplitude;
uniform float opacity = 1.0;  // below 1 while the dots fade in over the shapes

varying vec2 center;  // in px from the area's top-left corner

vec2 gradient(vec2 cell) {
	float a = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453) * 6.2831853;
	return vec2(cos(a), sin(a));
}

// Classic 2D Perlin noise, scaled to about -1..1.
float perlin(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(gradient(i), f);
	float b = dot(gradient(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(gradient(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(gradient(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.4142;
}

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void vertex() {
	center = INSTANCE_CUSTOM.xy;
}

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

	vec3 wavelength = base == 0 ? background_wavelength : shape_wavelength;
	vec3 amplitude = base == 0 ? background_amplitude : shape_amplitude;
	// Each channel reads its own noise field, set apart by a fixed offset.
	vec3 shift = amplitude * vec3(
			perlin(center / wavelength.x),
			perlin(center / wavelength.y + vec2(173.0, 37.0)),
			perlin(center / wavelength.z + vec2(59.0, 211.0)));
	vec3 hsv = rgb_to_hsv(bases[base].rgb);
	// A gray base has no hue to shift and must stay gray, so only its value varies.
	if (hsv.y < 0.001) {
		shift.xy = vec2(0.0);
	}
	hsv += shift;
	COLOR = vec4(hsv_to_rgb(vec3(fract(hsv.x), clamp(hsv.yz, 0.0, 1.0))), opacity);
}
