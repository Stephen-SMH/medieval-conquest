shader_type canvas_item;
// A region painted on parchment: its colour with paper grain. A capture
// sweeps the new colour out from `sweep_origin` as `sweep_radius` grows.

uniform sampler2D paper : repeat_enable, filter_linear_mipmap;
uniform vec4 fill_color : source_color = vec4(1.0);
uniform vec4 old_color : source_color = vec4(1.0);
uniform vec2 sweep_origin = vec2(0.0);
uniform float sweep_radius = 100000.0;
uniform float glow = 0.0;

varying vec2 world;

void vertex() {
	world = VERTEX;
}

void fragment() {
	float d = distance(world, sweep_origin);
	float edge = smoothstep(sweep_radius - 24.0, sweep_radius, d);
	vec4 c = mix(fill_color, old_color, edge);
	float grain = texture(paper, world / 320.0).r;
	COLOR = vec4(c.rgb * (0.84 + 0.22 * grain) + vec3(glow * 0.12, glow * 0.1, glow * 0.04), 1.0);
}
