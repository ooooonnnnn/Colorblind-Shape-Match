shader_type canvas_item;
// A calibration patch, drawn in the screen's own pixel rows (FRAGCOORD), not
// the game's stretched units: on_rows rows of every period show lit and the
// rest black, so from far enough away, or out of focus, its light is
// on_rows / period of lit's. A solid patch is period 1.

uniform vec4 lit = vec4(1.0);
uniform int period = 1;
uniform int on_rows = 1;

void fragment() {
	int row = int(mod(floor(FRAGCOORD.y), float(period)));
	COLOR = row < on_rows ? lit : vec4(0.0, 0.0, 0.0, 1.0);
}
