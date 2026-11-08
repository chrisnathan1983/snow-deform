shader_type canvas_item;
render_mode blend_mix;

uniform float berm_strength = 0.15;
uniform float berm_height_ratio = 0.32;
uniform float normal_strength = 10.0;
uniform float map_resolution = 512.0;
uniform bool textured_berm_dilation_enabled = false;
uniform sampler2D stamp_texture;

const float MAP_NEUTRAL = 128.0 / 255.0;
const float BERM_REACH = 2.0;
const float BERM_FORWARD = 0.3;

#include "res://addons/deformable_surface/shaders/deformable_surface_stamp_profile.gdshaderinc"

varying vec4 stamp_data;
varying vec3 stamp_params;
varying float stamp_phase;

void vertex() {
	stamp_data = INSTANCE_CUSTOM;
	stamp_params = COLOR.rgb;
	stamp_phase = COLOR.a;
}

// Alpha of the stamp sprite at a footprint-space pixel offset (0 outside the texture).
float sprite_alpha(vec2 p, vec2 pit_rad, float is_segment, float flag, float phase) {
	vec2 footprint_uv = p / (2.0 * pit_rad) + vec2(0.5);
	vec2 sprite_uv = vec2(footprint_uv.y, 1.0 - footprint_uv.x);
	if (is_segment > 0.5) {
		// One tile is as long as the track is wide times the texture's height/width ratio.
		vec2 tex_size = vec2(textureSize(stamp_texture, 0));
		float tile_px = 2.0 * pit_rad.y * tex_size.y / tex_size.x;
		sprite_uv.y = 1.0 - fract(phase + p.x / tile_px);
	}
	if (flag > 1.5) {
		sprite_uv.x = 1.0 - sprite_uv.x;
	}
	if (any(lessThan(sprite_uv, vec2(0.0))) || any(greaterThan(sprite_uv, vec2(1.0)))) {
		return 0.0;
	}
	return texture(stamp_texture, sprite_uv).a;
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
	float berm_enabled = step(0.0001, berm_strength);
	vec2 berm_rad = pit_rad * BERM_REACH * berm_enabled;
	vec2 berm_off = vec2(pit_rad.x * BERM_FORWARD * clamp(aspect - 1.0, 0.0, 1.0), 0.0) * berm_enabled;
	vec2 outer_ext = max(pit_rad, abs(berm_off) + berm_rad);
	if (is_capsule > 0.5) {
		// pit_rad = (half length, brush radius); must match DeformableSurface._stamp.
		berm_off = vec2(0.0);
		float capsule_margin = max(berm_rad.y, pit_rad.y);
		outer_ext = vec2(pit_rad.x + capsule_margin, capsule_margin);
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
		sprite_mask = sprite_alpha(pos_px, pit_rad, is_segment, stamp_data.w, stamp_phase);
		// Alpha gradient (central differences) shapes the pit walls to the sprite outline.
		float eps = max(0.04 * pit_rad.y, 1.0);
		sprite_grad = vec2(
			sprite_alpha(pos_px + vec2(eps, 0.0), pit_rad, is_segment, stamp_data.w, stamp_phase)
				- sprite_alpha(pos_px - vec2(eps, 0.0), pit_rad, is_segment, stamp_data.w, stamp_phase),
			sprite_alpha(pos_px + vec2(0.0, eps), pit_rad, is_segment, stamp_data.w, stamp_phase)
				- sprite_alpha(pos_px - vec2(0.0, eps), pit_rad, is_segment, stamp_data.w, stamp_phase)
		) / (2.0 * eps);
		if (mode < 0.5 && berm_strength > 0.0 && textured_berm_dilation_enabled) {
			// Dilated alpha: the berm only exists near the sprite's footprint, not as a full oval.
			sprite_cover = sprite_mask;
			for (int i = 0; i < 8; i++) {
				float a = float(i) * 0.78539816339;
				vec2 o = vec2(cos(a), sin(a)) * pit_rad * 0.4;
				sprite_cover = max(sprite_cover, sprite_alpha(pos_px + o, pit_rad, is_segment, stamp_data.w, stamp_phase));
			}
		}
	}

	float r_pit2;
	float pit_mask;
	float pit_shape;
	vec2 pit_grad;
	float berm_shape;
	vec2 berm_grad;
	stamp_profile(pos_px, pit_rad, berm_rad, berm_off, cap_q, is_segment, is_capsule,
			is_sliding, berm_strength, mode, sprite_mask, sprite_grad, sprite_cover,
			r_pit2, pit_mask, pit_shape, pit_grad, berm_shape, berm_grad);

	vec3 encoded;
	float alpha;
	compose_stamp_surface(r_pit2, pit_mask, pit_shape, pit_grad, berm_shape, berm_grad,
			strength, is_capsule, mode, berm_height_ratio, berm_strength, normal_strength,
			stamp_data.z, sprite_mask, encoded, alpha);

	COLOR = vec4(clamp(encoded, vec3(0.0), vec3(1.0)), clamp(alpha, 0.0, 1.0) * seg_in);
}
