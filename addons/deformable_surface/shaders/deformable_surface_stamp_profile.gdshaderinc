// Shared analytic pit, berm, and slope profile used by sprite and non-sprite stamps.
void stamp_profile(
		vec2 pos_px, vec2 pit_rad, vec2 berm_rad, vec2 berm_off, vec2 cap_q,
		float is_segment, float is_capsule, float is_sliding, float profile_berm_strength, float stamp_mode,
		float sprite_mask, vec2 sprite_grad, float sprite_cover,
		out float r_pit2, out float pit_mask, out float pit_shape, out vec2 pit_grad,
		out float berm_shape, out vec2 berm_grad) {
	vec2 p_norm = pos_px / pit_rad;
	if (is_segment > 0.5) {
		p_norm.x = 0.0;
	}
	if (is_capsule > 0.5) {
		p_norm = cap_q / pit_rad.y;
	}
	r_pit2 = dot(p_norm, p_norm);
	pit_mask = max(1.0 - r_pit2, 0.0);
	pit_shape = pit_mask * pit_mask;
	pit_grad = (-4.0 * pit_mask) * (p_norm / pit_rad);
	if (is_capsule > 0.5) {
		pit_grad = (-4.0 * pit_mask) * vec2(cap_q.x * sign(pos_px.x), cap_q.y)
				/ (pit_rad.y * pit_rad.y);
	}
	pit_grad = pit_grad * sprite_mask + pit_shape * sprite_grad;

	berm_shape = 0.0;
	berm_grad = vec2(0.0);
	if (profile_berm_strength > 0.0 && stamp_mode < 0.5) {
		vec2 b_norm = (pos_px - berm_off) / berm_rad;
		if (is_segment > 0.5) {
			b_norm.x = 0.0;
		}
		if (is_capsule > 0.5) {
			b_norm = cap_q / berm_rad.y;
		}
		float r_berm = length(b_norm);
		float b_in = smoothstep(0.35, 0.65, r_berm);
		float b_out = 1.0 - smoothstep(0.65, 1.0, r_berm);
		berm_shape = b_in * b_out;

		float trail_mask = 1.0;
		if (is_sliding > 0.5 && is_segment < 0.5 && is_capsule < 0.5) {
			trail_mask = smoothstep(-0.3 * pit_rad.x, 0.1 * pit_rad.x, pos_px.x);
		} else if (is_capsule > 0.5) {
			trail_mask = smoothstep(-0.3 * pit_rad.y, 0.1 * pit_rad.y, pos_px.x + pit_rad.x);
		}
		berm_shape *= trail_mask * sprite_cover;

		float d_berm_dr = (step(0.35, r_berm) * step(r_berm, 0.65) * 3.33
				- step(0.65, r_berm) * step(r_berm, 1.0) * 2.85) * trail_mask;
		berm_grad = (r_berm > 0.001)
				? (b_norm / (r_berm * berm_rad)) * d_berm_dr * sprite_cover : vec2(0.0);
		if (is_capsule > 0.5) {
			berm_grad = (r_berm > 0.001)
					? (b_norm / (r_berm * berm_rad.y)) * d_berm_dr : vec2(0.0);
			berm_grad.x *= sign(pos_px.x);
		}
	}
}


void compose_stamp_surface(
		float r_pit2, float pit_mask, float pit_shape, vec2 pit_grad,
		float berm_shape, vec2 berm_grad, float strength, float is_capsule,
		float mode, float profile_berm_height_ratio, float profile_berm_strength,
		float surface_normal_strength, float packed_heading, float sprite_mask,
		out vec3 encoded, out float alpha) {
	float in_pit = 1.0 - smoothstep(0.65, 1.0, r_pit2);
	float target_h = mix(profile_berm_height_ratio * 0.5,
			-0.5 * pit_shape * strength, in_pit);
	vec2 local_grad = mix(berm_grad * (profile_berm_height_ratio * profile_berm_strength),
			-pit_grad * (0.7 * strength), in_pit);
	vec2 local_slope = local_grad * (2.5 * surface_normal_strength);
	float heading = (packed_heading - 0.5) * 6.28318530718;
	float c = cos(heading);
	float s = sin(heading);
	vec2 map_slope = vec2(c * local_slope.x - s * local_slope.y,
		s * local_slope.x + c * local_slope.y);
	encoded = vec3(MAP_NEUTRAL) + vec3(target_h, map_slope / 16.0);
	float pit_alpha = in_pit * mix(0.85, 1.0, is_capsule) * sprite_mask;
	float berm_alpha = berm_shape * profile_berm_strength * strength;
	alpha = mix(berm_alpha, pit_alpha, in_pit);

	if (mode > 1.5) {
		encoded = vec3(MAP_NEUTRAL);
		alpha = clamp(pit_mask * 1.5, 0.0, 1.0) * strength * sprite_mask;
	} else if (mode > 0.5) {
		map_slope = vec2(c * -local_slope.x - s * -local_slope.y,
			s * -local_slope.x + c * -local_slope.y);
		encoded = vec3(MAP_NEUTRAL) + vec3(-target_h, map_slope / 16.0);
	}
}
