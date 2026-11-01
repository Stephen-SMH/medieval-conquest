shader_type canvas_item;
// Dark teal sea with paper grain.

uniform sampler2D paper : repeat_enable, filter_linear_mipmap;
uniform vec4 sea_color : source_color = vec4(0.12, 0.29, 0.33, 1.0);

varying vec2 world;

void vertex() {
	world = VERTEX;
}

void fragment() {
	float grain = texture(paper, world / 420.0).r;
	float fine = texture(paper, world / 90.0).r;
	COLOR = vec4(sea_color.rgb * (0.7 + 0.35 * grain + 0.08 * fine), 1.0);
}
