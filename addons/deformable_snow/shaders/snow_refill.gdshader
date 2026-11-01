shader_type canvas_item;
render_mode blend_mix;

uniform float recovery_alpha = 0.0;
uniform float seed = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	// Stochastically boost alpha above 0.51 on a fraction of pixels so 8-bit values
	// within ±26 of 128 don't stall. Pixels already at 128 stay at 128 for any alpha.
	float dither_snap = step(hash12(FRAGCOORD.xy + seed), recovery_alpha * 0.75) * 0.52;
	COLOR = vec4(vec3(128.0 / 255.0), max(recovery_alpha, dither_snap));
}