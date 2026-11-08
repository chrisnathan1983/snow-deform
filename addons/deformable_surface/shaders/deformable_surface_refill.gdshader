shader_type canvas_item;
render_mode blend_mix;

#include "res://addons/deformable_surface/shaders/deformable_surface_initial_noise.gdshaderinc"

uniform float recovery_alpha = 0.0;
uniform float seed = 0.0;
uniform sampler2D recovery_target : filter_linear, repeat_disable;
uniform bool recovery_target_enabled = false;
uniform bool procedural_initial_noise_enabled = false;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	// Stochastically boost alpha above 0.51 on a fraction of pixels so 8-bit values
	// close to their target don't stall.
	float dither_snap = step(hash12(FRAGCOORD.xy + seed), recovery_alpha * 0.75) * 0.52;
	vec3 target = procedural_initial_noise_enabled
		? initial_map_color(UV)
		: (recovery_target_enabled
			? texture(recovery_target, UV).rgb
			: vec3(128.0 / 255.0));
	COLOR = vec4(target, max(recovery_alpha, dither_snap));
}
