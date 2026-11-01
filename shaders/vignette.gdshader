shader_type canvas_item;
// Darkens and browns the screen edges, like the burnt rim of an old map.

uniform float strength = 0.75;

void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 1.1);
	float v = smoothstep(0.26, 0.8, length(d));
	COLOR = vec4(0.1, 0.06, 0.02, v * strength);
}
