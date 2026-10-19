shader_type canvas_item;
// Behind the dots: shows the screen inside the mask and the gap color elsewhere.
// The mask has rounded corners like the tray it clears, so the board behind
// the tray's corners is covered too. Reading the screen here also makes Godot
// copy it before this draws, so the dots drawn after it still sample the
// original image.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec4 background : source_color;
uniform vec4 mask_rect;      // x, y, width, height as fractions of this rect
uniform vec2 area_size;      // this rect's size in px
uniform float mask_radius;   // the mask's corner radius in px

void fragment() {
	vec2 p = UV * area_size;
	vec2 half_size = mask_rect.zw * area_size / 2.0;
	vec2 center = mask_rect.xy * area_size + half_size;
	// Signed distance to the rounded mask rectangle; negative inside.
	vec2 q = abs(p - center) - half_size + mask_radius;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - mask_radius;
	COLOR = d < 0.0 ? texture(screen_tex, SCREEN_UV) : background;
}
