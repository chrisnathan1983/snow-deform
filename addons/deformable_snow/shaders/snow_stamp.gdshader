shader_type canvas_item;
render_mode blend_mix;

uniform float berm_strength = 0.15;
uniform float berm_height_ratio = 0.32;
uniform float normal_strength = 10.0;
uniform float map_resolution = 512.0;

const float MAP_NEUTRAL = 128.0 / 255.0;
const float BERM_REACH = 2.0;
const float BERM_FORWARD = 0.3;

varying vec4 stamp_data;

void vertex() {
	stamp_data = INSTANCE_CUSTOM;
}

void fragment() {
	float strength = COLOR.r;
	float radius_px = max(COLOR.g * map_resolution, 0.5);
	float aspect = stamp_data.x * 8.0;
	float is_sliding = stamp_data.y;

	vec2 pit_rad = vec2(radius_px * sqrt(aspect), radius_px / sqrt(aspect));
	vec2 berm_rad = pit_rad * BERM_REACH;
	vec2 berm_off = vec2(pit_rad.x * BERM_FORWARD * clamp(aspect - 1.0, 0.0, 1.0), 0.0);
	vec2 outer_ext = max(pit_rad, abs(berm_off) + berm_rad);
	vec2 pos_px = (UV - vec2(0.5)) * (2.0 * outer_ext);

	// 1. Pit profile & exact analytical gradient (flat floor at center, smooth walls)
	vec2 p_norm = pos_px / pit_rad;
	float r_pit2 = dot(p_norm, p_norm);
	float pit_mask = max(1.0 - r_pit2, 0.0);
	float pit_shape = pit_mask * pit_mask; // (1 - r^2)^2
	// Derivative of (1 - r^2)^2 with respect to pos_px:
	vec2 pit_grad = (-4.0 * pit_mask) * (p_norm / pit_rad);

	// 2. Berm profile & analytical gradient
	float berm_shape = 0.0;
	vec2 berm_grad = vec2(0.0);
	if (berm_strength > 0.0) {
		vec2 b_norm = (pos_px - berm_off) / berm_rad;
		float r_berm = length(b_norm);
		// Smooth ring peaking at r_berm = 0.65, zero inside 0.35 and outside 1.0
		float b_in = smoothstep(0.35, 0.65, r_berm);
		float b_out = 1.0 - smoothstep(0.65, 1.0, r_berm);
		berm_shape = b_in * b_out;

		// Suppress trailing berm behind a sliding deformer so it doesn't refill its own track
		float trail_mask = 1.0;
		if (is_sliding > 0.5) {
			trail_mask = smoothstep(-0.3 * pit_rad.x, 0.1 * pit_rad.x, pos_px.x);
		}
		berm_shape *= trail_mask;

		// Approximate radial derivative of berm ring
		float d_berm_dr = (step(0.35, r_berm) * step(r_berm, 0.65) * 3.33 - step(0.65, r_berm) * step(r_berm, 1.0) * 2.85) * trail_mask;
		berm_grad = (r_berm > 0.001) ? (b_norm / (r_berm * berm_rad)) * d_berm_dr : vec2(0.0);
	}

	// Combine pit and berm based on region
	float in_pit = step(r_pit2, 1.0);
	float target_h = mix(berm_height_ratio * 0.5, -0.5 * pit_shape, in_pit);
	vec2 local_grad = mix(berm_grad * (berm_height_ratio * berm_strength), pit_grad * 0.7, in_pit);
	vec2 local_slope = local_grad * (2.5 * normal_strength);

	float heading = (stamp_data.z - 0.5) * 6.28318530718;
	float c = cos(heading);
	float s = sin(heading);
	vec2 map_slope = vec2(c * local_slope.x - s * local_slope.y, s * local_slope.x + c * local_slope.y);

	vec3 encoded = vec3(MAP_NEUTRAL) + vec3(target_h, map_slope / 16.0);
	float pit_alpha = smoothstep(1.0, 0.65, r_pit2) * strength * 0.85;
	float berm_alpha = berm_shape * berm_strength * strength;
	float alpha = max(pit_alpha, berm_alpha * (1.0 - in_pit));

	COLOR = vec4(clamp(encoded, vec3(0.0), vec3(1.0)), clamp(alpha, 0.0, 1.0));
}