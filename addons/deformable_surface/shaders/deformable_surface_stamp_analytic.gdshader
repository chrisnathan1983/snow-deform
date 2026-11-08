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
varying vec3 stamp_params;

void vertex() {
	stamp_data = INSTANCE_CUSTOM;
	stamp_params = COLOR.rgb;
}

void fragment() {
	float strength = stamp_params.x;
	float radius_px = max(stamp_params.y * map_resolution, 0.5);
	float mode = floor(stamp_params.z * 4.0 + 0.5);
	float aspect = stamp_data.x * 8.0;
	float is_sliding = stamp_data.y;
	float is_capsule = step(2.5, is_sliding);
	float is_segment = step(1.5, is_sliding) * (1.0 - is_capsule);

	vec2 pit_rad = vec2(radius_px * sqrt(aspect), radius_px / sqrt(aspect));
	float berm_enabled = step(0.0001, berm_strength);
	vec2 berm_rad = pit_rad * BERM_REACH * berm_enabled;
	vec2 berm_off = vec2(pit_rad.x * BERM_FORWARD * clamp(aspect - 1.0, 0.0, 1.0), 0.0) * berm_enabled;
	vec2 outer_ext = max(pit_rad, abs(berm_off) + berm_rad);
	if (is_capsule > 0.5) {
		berm_off = vec2(0.0);
		float capsule_margin = max(berm_rad.y, pit_rad.y);
		outer_ext = vec2(pit_rad.x + capsule_margin, capsule_margin);
	}
	vec2 pos_px = (UV - vec2(0.5)) * (2.0 * outer_ext);
	float seg_in = 1.0;
	if (is_segment > 0.5) {
		berm_off = vec2(0.0);
		seg_in = step(-pit_rad.x, pos_px.x) * (1.0 - step(pit_rad.x, pos_px.x));
	}
	vec2 cap_q = vec2(0.0);
	if (is_capsule > 0.5) {
		seg_in = step(-pit_rad.x, pos_px.x);
		cap_q = vec2(max(abs(pos_px.x) - pit_rad.x, 0.0), pos_px.y);
	}

	vec2 p_norm = pos_px / pit_rad;
	if (is_segment > 0.5) {
		p_norm.x = 0.0;
	}
	if (is_capsule > 0.5) {
		p_norm = cap_q / pit_rad.y;
	}
	float r_pit2 = dot(p_norm, p_norm);
	float pit_mask = max(1.0 - r_pit2, 0.0);
	float pit_shape = pit_mask * pit_mask;
	vec2 pit_grad = (-4.0 * pit_mask) * (p_norm / pit_rad);
	if (is_capsule > 0.5) {
		pit_grad = (-4.0 * pit_mask) * vec2(cap_q.x * sign(pos_px.x), cap_q.y) / (pit_rad.y * pit_rad.y);
	}

	float berm_shape = 0.0;
	vec2 berm_grad = vec2(0.0);
	if (berm_strength > 0.0 && mode < 0.5) {
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
		berm_shape *= trail_mask;
		float d_berm_dr = (step(0.35, r_berm) * step(r_berm, 0.65) * 3.33 - step(0.65, r_berm) * step(r_berm, 1.0) * 2.85) * trail_mask;
		berm_grad = (r_berm > 0.001) ? (b_norm / (r_berm * berm_rad)) * d_berm_dr : vec2(0.0);
		if (is_capsule > 0.5) {
			berm_grad = (r_berm > 0.001) ? (b_norm / (r_berm * berm_rad.y)) * d_berm_dr : vec2(0.0);
			berm_grad.x *= sign(pos_px.x);
		}
	}

	float in_pit = 1.0 - smoothstep(0.65, 1.0, r_pit2);
	float target_h = mix(berm_height_ratio * 0.5, -0.5 * pit_shape * strength, in_pit);
	vec2 local_grad = mix(berm_grad * (berm_height_ratio * berm_strength), -pit_grad * (0.7 * strength), in_pit);
	vec2 local_slope = local_grad * (2.5 * normal_strength);
	float heading = (stamp_data.z - 0.5) * 6.28318530718;
	float c = cos(heading);
	float s = sin(heading);
	vec2 map_slope = vec2(c * local_slope.x - s * local_slope.y, s * local_slope.x + c * local_slope.y);
	vec3 encoded = vec3(MAP_NEUTRAL) + vec3(target_h, map_slope / 16.0);
	float pit_alpha = in_pit * mix(0.85, 1.0, is_capsule);
	float berm_alpha = berm_shape * berm_strength * strength;
	float alpha = mix(berm_alpha, pit_alpha, in_pit);

	if (mode > 1.5) {
		encoded = vec3(MAP_NEUTRAL);
		alpha = clamp(pit_mask * 1.5, 0.0, 1.0) * strength;
	} else if (mode > 0.5) {
		map_slope = vec2(c * -local_slope.x - s * -local_slope.y, s * -local_slope.x + c * -local_slope.y);
		encoded = vec3(MAP_NEUTRAL) + vec3(-target_h, map_slope / 16.0);
	}

	COLOR = vec4(clamp(encoded, vec3(0.0), vec3(1.0)), clamp(alpha, 0.0, 1.0) * seg_in);
}
