shader_type canvas_item;
render_mode blend_mul;
// Old paper laid over the whole map (land and sea), multiplied in: broad
// mottling, brown water stains with darker tide rings, fibres and fine grain.

uniform sampler2D paper : repeat_enable, filter_linear_mipmap;
uniform float strength = 1.0;

varying vec2 world;

void vertex() {
	world = VERTEX;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		total += noise(p) * amplitude;
		p = p * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return total;
}

void fragment() {
	float mottle = fbm(world / 420.0);
	float stain_field = fbm(world / 300.0 + vec2(7.3, 2.1));
	float stain = smoothstep(0.56, 0.7, stain_field);
	float ring = smoothstep(0.02, 0.0, abs(stain_field - 0.585)) * 0.8;
	float fibre = texture(paper, world / 150.0).r;
	float streak = noise(vec2(world.x / 900.0, world.y / 14.0));
	float grain = hash(floor(world * 0.9));
	vec3 tint = vec3(1.0);
	tint *= mix(vec3(1.0), vec3(0.84, 0.8, 0.72), mottle);
	tint *= mix(vec3(1.0), vec3(0.86, 0.76, 0.6), stain * 0.75);
	tint *= mix(vec3(1.0), vec3(0.7, 0.6, 0.46), ring * 0.55);
	tint *= 0.86 + 0.14 * fibre;
	tint *= 0.97 + 0.03 * streak;
	tint *= 0.9 + 0.1 * grain;
	COLOR = vec4(mix(vec3(1.0), tint, strength), 1.0);
}
