shader_type canvas_item;
render_mode blend_mix;

uniform float berm_strength = 0.15;
uniform float berm_height_ratio = 0.32;
uniform float normal_strength = 10.0;
uniform float map_resolution = 512.0;

const float MAP_NEUTRAL = 128.0 / 255.0;
const float BERM_REACH = 2.0;
const float BERM_FORWARD = 0.3;

#include "res://addons/deformable_surface/shaders/deformable_surface_stamp_profile.gdshaderinc"

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

	float r_pit2;
	float pit_mask;
	float pit_shape;
	vec2 pit_grad;
	float berm_shape;
	vec2 berm_grad;
	stamp_profile(pos_px, pit_rad, berm_rad, berm_off, cap_q, is_segment, is_capsule,
			is_sliding, berm_strength, mode, 1.0, vec2(0.0), 1.0,
			r_pit2, pit_mask, pit_shape, pit_grad, berm_shape, berm_grad);

	vec3 encoded;
	float alpha;
	compose_stamp_surface(r_pit2, pit_mask, pit_shape, pit_grad, berm_shape, berm_grad,
			strength, is_capsule, mode, berm_height_ratio, berm_strength, normal_strength,
			stamp_data.z, 1.0, encoded, alpha);

	COLOR = vec4(clamp(encoded, vec3(0.0), vec3(1.0)), clamp(alpha, 0.0, 1.0) * seg_in);
}
