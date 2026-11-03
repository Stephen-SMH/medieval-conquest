shader_type canvas_item;
// A white-on-clear icon drawn as a pencil sketch on parchment, as the cards
// of S&T's Forge: graphite outlines along every edge of the shape (its inner
// cut lines too), a light wash with diagonal hatching inside, denser on the
// side away from the light, and paper grain. The draw colour picks the pass:
// red 1 draws the sketch (its alpha fades it); red 0 draws the shape a little
// wider in the paper colour, to hide what is behind it when figures overlap.

uniform vec4 ink : source_color = vec4(0.26, 0.23, 0.19, 1.0);
uniform vec4 paper : source_color = vec4(0.91, 0.85, 0.68, 1.0);
// Texels per screen pixel, roughly: the icon's texture size over its drawn size.
uniform float texels = 2.5;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float shape(sampler2D tex, vec2 uv) {
	return texture(tex, uv).a;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * texels;
	// A slight wobble, so lines aren't ruler-straight.
	vec2 uv = UV + vec2(sin(UV.y * 71.0), cos(UV.x * 67.0)) * px * 0.12;
	float a = shape(TEXTURE, uv);
	if (tint.r < 0.5) {
		float wide = a;
		for (int i = 0; i < 8; i++) {
			float angle = float(i) * 0.785398;
			wide = max(wide, shape(TEXTURE, uv + vec2(cos(angle), sin(angle)) * px * 2.2));
		}
		COLOR = vec4(paper.rgb, smoothstep(0.1, 0.5, wide) * tint.a);
	} else {
		// Outline: where the shape's edge passes, across about a pixel and a half.
		float edge = 0.0;
		for (int i = 0; i < 4; i++) {
			float angle = float(i) * 0.785398;
			vec2 d = vec2(cos(angle), sin(angle)) * px * 0.6;
			edge = max(edge, abs(shape(TEXTURE, uv + d) - shape(TEXTURE, uv - d)));
		}
		edge = smoothstep(0.2, 0.75, edge);
		// Shade: the part of the shape whose lower right is still the shape
		// faces away from the light (top left).
		float away = shape(TEXTURE, uv + px * vec2(5.0, 6.0));
		float rim = a * (1.0 - shape(TEXTURE, uv - px * vec2(4.0, 5.0)));
		vec2 screen = FRAGCOORD.xy;
		float hatch = smoothstep(0.32, 0.12, abs(fract((screen.x + screen.y) / 3.6) - 0.5));
		float cross_hatch = smoothstep(0.3, 0.1, abs(fract((screen.x - screen.y) / 4.2) - 0.5));
		float grain = 0.72 + 0.28 * hash(floor(screen));
		float fill = a * (0.1 + hatch * (0.12 + 0.26 * away) + cross_hatch * 0.2 * away * (1.0 - rim));
		float alpha = max(edge * 0.92, fill) * grain;
		COLOR = vec4(ink.rgb, clamp(alpha, 0.0, 1.0) * tint.a);
	}
}
