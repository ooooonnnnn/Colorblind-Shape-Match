shader_type canvas_item;
// Behind the dots: shows the screen inside the mask and a flat color elsewhere.
// Reading the screen here also makes Godot copy it before this draws, so the
// dots drawn after it still sample the original image.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec4 background : source_color;
uniform vec4 mask_rect;  // x, y, width, height as fractions of this rect

void fragment() {
	bool in_mask = all(greaterThanEqual(UV, mask_rect.xy)) && all(lessThan(UV, mask_rect.xy + mask_rect.zw));
	COLOR = in_mask ? texture(screen_tex, SCREEN_UV) : background;
}
