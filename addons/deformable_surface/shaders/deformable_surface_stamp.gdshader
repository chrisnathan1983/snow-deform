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
varying float stamp_phase;

void vertex() {
	stamp_data = INSTANCE_CUSTOM;
	stamp_params = COLOR.rgb;
	stamp_phase = COLOR.a;
}

// Alpha of the stamp sprite at a footprint-space pixel offset (0 outside the texture).
float sprite_alpha(sampler2D tex, vec2 p, vec2 pit_rad, float is_segment, float flag, float phase) {
	vec2 footprint_uv = p / (2.0 * pit_rad) + vec2(0.5);
	vec2 sprite_uv = vec2(footprint_uv.y, 1.0 - footprint_uv.x);
	if (is_segment > 0.5) {
		// One tile is as long as the track is wide times the texture's height/width ratio.
		vec2 tex_size = vec2(textureSize(tex, 0));
		float tile_px = 2.0 * pit_rad.y * tex_size.y / tex_size.x;
		sprite_uv.y = 1.0 - fract(phase + p.x / tile_px);
	}
	if (flag > 1.5) {
		sprite_uv.x = 1.0 - sprite_uv.x;
	}
	if (any(lessThan(sprite_uv, vec2(0.0))) || any(greaterThan(sprite_uv, vec2(1.0)))) {
		return 0.0;
	}
	return texture(tex, sprite_uv).a;
}

void fragment() {
	float strength = stamp_params.x;
	float radius_px = max(stamp_params.y * map_resolution, 0.5);
	// 0 = carve, 1 = raise, 2 = smooth (flatten toward neutral)
	float mode = floor(stamp_params.z * 4.0 + 0.5);
	float aspect = stamp_data.x * 8.0;
	float is_sliding = stamp_data.y;
	// 3 = capsule: a segment with a rounded front, used for smooth continuous brush strokes.
	float is_capsule = step(2.5, is_sliding);
	// 2 = track segment: a straight strip whose tread is sampled by distance travelled.
	float is_segment = step(1.5, is_sliding) * (1.0 - is_capsule);
	float has_sprite = step(0.5, stamp_data.w);

	vec2 pit_rad = vec2(radius_px * sqrt(aspect), radius_px / sqrt(aspect));
	vec2 berm_rad = pit_rad * BERM_REACH;
	vec2 berm_off = vec2(pit_rad.x * BERM_FORWARD * clamp(aspect - 1.0, 0.0, 1.0), 0.0);
	vec2 outer_ext = max(pit_rad, abs(berm_off) + berm_rad);
	if (is_capsule > 0.5) {
		// pit_rad = (half length, brush radius); must match DeformableSurface._stamp.
		berm_off = vec2(0.0);
		outer_ext = vec2(pit_rad.x + berm_rad.y, berm_rad.y);
	}
	vec2 pos_px = (UV - vec2(0.5)) * (2.0 * outer_ext);
	// Segments cover exactly [-length/2, length/2) so neighbours abut without overlap.
	float seg_in = 1.0;
	if (is_segment > 0.5) {
		berm_off = vec2(0.0);
		seg_in = step(-pit_rad.x, pos_px.x) * (1.0 - step(pit_rad.x, pos_px.x));
	}
	// Capsules drop their rear cap: the previous capsule's front cap already covers the joint.
	vec2 cap_q = vec2(0.0);
	if (is_capsule > 0.5) {
		seg_in = step(-pit_rad.x, pos_px.x);
		cap_q = vec2(max(abs(pos_px.x) - pit_rad.x, 0.0), pos_px.y);
	}
	float sprite_mask = 1.0;
	vec2 sprite_grad = vec2(0.0);
	float sprite_cover = 1.0;
	if (has_sprite > 0.5) {
		sprite_mask = sprite_alpha(TEXTURE, pos_px, pit_rad, is_segment, stamp_data.w, stamp_phase);
		// Alpha gradient (central differences) shapes the pit walls to the sprite outline.
		float eps = max(0.04 * pit_rad.y, 1.0);
		sprite_grad = vec2(
			sprite_alpha(TEXTURE, pos_px + vec2(eps, 0.0), pit_rad, is_segment, stamp_data.w, stamp_phase)
				- sprite_alpha(TEXTURE, pos_px - vec2(eps, 0.0), pit_rad, is_segment, stamp_data.w, stamp_phase),
			sprite_alpha(TEXTURE, pos_px + vec2(0.0, eps), pit_rad, is_segment, stamp_data.w, stamp_phase)
				- sprite_alpha(TEXTURE, pos_px - vec2(0.0, eps), pit_rad, is_segment, stamp_data.w, stamp_phase)
		) / (2.0 * eps);
		if (mode < 0.5) {
			// Dilated alpha: the berm only exists near the sprite's footprint, not as a full oval.
			sprite_cover = sprite_mask;
			for (int i = 0; i < 8; i++) {
				float a = float(i) * 0.78539816339;
				vec2 o = vec2(cos(a), sin(a)) * pit_rad * 0.4;
				sprite_cover = max(sprite_cover, sprite_alpha(TEXTURE, pos_px + o, pit_rad, is_segment, stamp_data.w, stamp_phase));
			}
		}
	}

	// 1. Pit profile & exact analytical gradient (flat floor at center, smooth walls)
	vec2 p_norm = pos_px / pit_rad;
	if (is_segment > 0.5) {
		p_norm.x = 0.0;
	}
	if (is_capsule > 0.5) {
		p_norm = cap_q / pit_rad.y;
	}
	float r_pit2 = dot(p_norm, p_norm);
	float pit_mask = max(1.0 - r_pit2, 0.0);
	float pit_shape = pit_mask * pit_mask; // (1 - r^2)^2
	// Derivative of (1 - r^2)^2 with respect to pos_px:
	vec2 pit_grad = (-4.0 * pit_mask) * (p_norm / pit_rad);
	if (is_capsule > 0.5) {
		pit_grad = (-4.0 * pit_mask) * vec2(cap_q.x * sign(pos_px.x), cap_q.y) / (pit_rad.y * pit_rad.y);
	}
	if (has_sprite > 0.5) {
		// Height is pit_shape * sprite_mask, so differentiate the product.
		pit_grad = pit_grad * sprite_mask + pit_shape * sprite_grad;
	}

	// 2. Berm profile & analytical gradient
	float berm_shape = 0.0;
	vec2 berm_grad = vec2(0.0);
	if (berm_strength > 0.0 && mode < 0.5) {
		vec2 b_norm = (pos_px - berm_off) / berm_rad;
		if (is_segment > 0.5) {
			b_norm.x = 0.0; // side ridges only
		}
		if (is_capsule > 0.5) {
			b_norm = cap_q / berm_rad.y;
		}
		float r_berm = length(b_norm);
		// Smooth ring peaking at r_berm = 0.65, zero inside 0.35 and outside 1.0
		float b_in = smoothstep(0.35, 0.65, r_berm);
		float b_out = 1.0 - smoothstep(0.65, 1.0, r_berm);
		berm_shape = b_in * b_out;

		// Suppress trailing berm behind a sliding deformer so it doesn't refill its own track
		float trail_mask = 1.0;
		if (is_sliding > 0.5 && is_segment < 0.5 && is_capsule < 0.5) {
			trail_mask = smoothstep(-0.3 * pit_rad.x, 0.1 * pit_rad.x, pos_px.x);
		} else if (is_capsule > 0.5) {
			trail_mask = smoothstep(-0.3 * pit_rad.y, 0.1 * pit_rad.y, pos_px.x + pit_rad.x);
		}
		berm_shape *= trail_mask * sprite_cover;

		// Approximate radial derivative of berm ring
		float d_berm_dr = (step(0.35, r_berm) * step(r_berm, 0.65) * 3.33 - step(0.65, r_berm) * step(r_berm, 1.0) * 2.85) * trail_mask;
		berm_grad = (r_berm > 0.001) ? (b_norm / (r_berm * berm_rad)) * d_berm_dr * sprite_cover : vec2(0.0);
		if (is_capsule > 0.5) {
			berm_grad = (r_berm > 0.001) ? (b_norm / (r_berm * berm_rad.y)) * d_berm_dr : vec2(0.0);
			berm_grad.x *= sign(pos_px.x);
		}
	}

	// Combine pit and berm based on region
	float in_pit = 1.0 - smoothstep(0.65, 1.0, r_pit2);
	float target_h = mix(berm_height_ratio * 0.5, -0.5 * pit_shape * strength, in_pit);
	// Slopes encode +dh/dx like the berm and baked-noise slopes; strength scales the pit gradient.
	vec2 local_grad = mix(berm_grad * (berm_height_ratio * berm_strength), -pit_grad * (0.7 * strength), in_pit);
	vec2 local_slope = local_grad * (2.5 * normal_strength);

	float heading = (stamp_data.z - 0.5) * 6.28318530718;
	float c = cos(heading);
	float s = sin(heading);
	vec2 map_slope = vec2(c * local_slope.x - s * local_slope.y, s * local_slope.x + c * local_slope.y);

	vec3 encoded = vec3(MAP_NEUTRAL) + vec3(target_h, map_slope / 16.0);
	// Keep coverage high; strength controls pit depth rather than blend accumulation.
	float pit_alpha = in_pit * mix(0.85, 1.0, is_capsule) * sprite_mask;
	float berm_alpha = berm_shape * berm_strength * strength;
	float alpha = mix(berm_alpha, pit_alpha, in_pit);

	if (mode > 1.5) {
		// Smooth: feathered blend toward a flat neutral surface.
		encoded = vec3(MAP_NEUTRAL);
		alpha = clamp(pit_mask * 1.5, 0.0, 1.0) * strength * sprite_mask;
	} else if (mode > 0.5) {
		// Raise: the pit profile mirrored upward, no berm.
		map_slope = vec2(c * -local_slope.x - s * -local_slope.y, s * -local_slope.x + c * -local_slope.y);
		encoded = vec3(MAP_NEUTRAL) + vec3(-target_h, map_slope / 16.0);
	}

	COLOR = vec4(clamp(encoded, vec3(0.0), vec3(1.0)), clamp(alpha, 0.0, 1.0) * seg_in);
}