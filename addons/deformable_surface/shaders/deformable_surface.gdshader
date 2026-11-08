shader_type spatial;

#include "res://addons/deformable_surface/shaders/deformable_surface.gdshaderinc"

// Deformation map: R = combined height (0.5 = flat, lower = pit, higher = berm)
//                  G/B = encoded X/Z height gradients.
uniform sampler2D deform_map : filter_linear, repeat_disable;
uniform float max_depth = 0.25;

uniform vec3 surface_color : source_color = vec3(0.90, 0.93, 0.98);
uniform vec3 shadow_color : source_color = vec3(0.68, 0.74, 0.84);
uniform float normal_strength = 10.0;
uniform bool wrapped_diffuse_lighting = true;
uniform float wrap_amount : hint_range(0.0, 0.5) = 0.4;
uniform float cool_shading : hint_range(0.0, 1.0) = 1.0; // blue-shifted terminator; 0 = neutral
uniform float disturbed_darkening : hint_range(0.0, 1.0) = 0.0; // darkens any disturbed ground (damp earth under dry crust)
uniform float bevel_noise_scale = 32.0;
uniform float bevel_noise_strength = 0.45;
uniform vec2 bevel_origin_fraction = vec2(0.0);
uniform vec2 bevel_origin_cell = vec2(0.0);

// Optional material textures. Leave empty for flat colors.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 albedo_tint : source_color = vec3(1.0);
uniform float texture_scale = 0.5;       // triplanar: tiles per meter
uniform float uv_tiling = 8.0;           // non-triplanar: tiles across the whole surface
uniform float texture_normal_strength = 1.0;
uniform bool triplanar = false;          // project by world position/normal instead of mesh UV
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;

// Material response
uniform float base_roughness : hint_range(0.0, 1.0) = 0.88;
uniform float pressed_roughness : hint_range(0.0, 1.0) = 0.50;
uniform float glaze_roughness : hint_range(0.0, 1.0) = 0.18;
uniform float glaze_amount : hint_range(0.0, 1.0) = 1.0; // 0 = no icy glaze in deep pits
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;

uniform float sparkle_strength = 1.0;    // per-material multiplier; 0 disables sparkle
uniform float sparkle_intensity = 1.0;   // quality-level scale, set by DeformableSurface; 0 = off (skips the whole block)
uniform float sparkle_density = 24.0;    // cells per meter
uniform float sparkle_threshold = 0.99;
uniform vec3 sun_dir = vec3(0.424, 0.848, 0.318); // direction TOWARD the light
uniform float sparkle_fade_start = 20.0;
uniform float sparkle_fade_end = 45.0;
uniform vec2 sparkle_origin_fraction = vec2(0.0);
uniform vec2 sparkle_origin_cell = vec2(0.0);

varying vec3 world_pos;
varying vec3 world_normal;
varying vec2 surface_local_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec2 world_noise(vec2 p, vec2 origin_cell) {
	vec2 cell = mod(floor(p) + origin_cell, vec2(8192.0));
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec2 a = hash22(cell);
	vec2 b = hash22(cell + vec2(1.0, 0.0));
	vec2 c = hash22(cell + vec2(0.0, 1.0));
	vec2 d = hash22(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float sample_vertex_height(vec2 uv) {
	return textureLod(deform_map, uv, 0.0).r;
}

void vertex() {
	surface_local_pos = VERTEX.xz;
	float height = deform_height_n(sample_vertex_height(UV));
	vec3 base_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dy = height * max_depth;
	VERTEX.y += dy;
	world_pos = base_world_pos + vec3(0.0, dy, 0.0); // Avoids 2nd matrix multiply
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Returns albedo (rgb) and a tangent-space normal offset (written to nxy).
vec3 sample_material(vec2 uv, out vec2 nxy) {
	vec3 col = vec3(1.0);
	nxy = vec2(0.0);
	bool has_albedo = textureSize(albedo_texture, 0).x > 1;
	bool has_normal = textureSize(normal_texture, 0).x > 1;
	if (!has_albedo && !has_normal) {
		return col;
	}

	if (triplanar) {
		vec3 w = pow(abs(world_normal), vec3(triplanar_sharpness));
		w /= max(w.x + w.y + w.z, 0.0001);
		vec2 uv_x = world_pos.zy * texture_scale;
		vec2 uv_y = world_pos.xz * texture_scale;
		vec2 uv_z = world_pos.xy * texture_scale;
		if (has_albedo) {
			col = texture(albedo_texture, uv_x).rgb * w.x
				+ texture(albedo_texture, uv_y).rgb * w.y
				+ texture(albedo_texture, uv_z).rgb * w.z;
		}
		if (has_normal) {
			nxy = (texture(normal_texture, uv_x).xy * 2.0 - 1.0) * w.x
				+ (texture(normal_texture, uv_y).xy * 2.0 - 1.0) * w.y
				+ (texture(normal_texture, uv_z).xy * 2.0 - 1.0) * w.z;
		}
	} else {
		vec2 tuv = uv * uv_tiling;
		if (has_albedo) {
			col = texture(albedo_texture, tuv).rgb;
		}
		if (has_normal) {
			nxy = texture(normal_texture, tuv).xy * 2.0 - 1.0;
		}
	}
	return col;
}

void fragment() {
	vec3 map_sample = texture(deform_map, UV).rgb;
	float height = deform_height_n(map_sample.r);
	float pit_depth = clamp(-height, 0.0, 1.0);
	float hc = 1.0 - pit_depth;
	float ice_glaze = smoothstep(0.75, 0.98, pit_depth) * glaze_amount;
	vec2 slope = deform_decode_slope(map_sample.gb) * (normal_strength / 10.0);

	vec2 detail_n;
	vec3 tex_col = sample_material(UV, detail_n) * albedo_tint;
	vec2 detail_slope = vec2(-detail_n.x, detail_n.y) * texture_normal_strength;
	vec3 lit_surface_color = surface_color;
	vec3 lit_shadow_color = shadow_color;
	SPECULAR = specular_amount;
	if (wrapped_diffuse_lighting) {
		float wrapped_light = clamp((dot(normalize(world_normal), normalize(sun_dir)) + wrap_amount) / (1.0 + wrap_amount), 0.0, 1.0);
		vec3 cool_tint = mix(vec3(0.68, 0.82, 1.0), vec3(1.0), cool_shading * smoothstep(0.0, 0.8, wrapped_light));
		lit_surface_color *= cool_tint;
		lit_shadow_color *= cool_tint;
	}

	// Fast path: skip all noise and slope math on an untouched flat surface
	if (abs(height) + abs(slope.x) + abs(slope.y) > 0.02) {
		float slope_len = length(slope);
		float edge_strength = smoothstep(0.05, 0.5, slope_len);

		if (edge_strength > 0.001) {
			vec2 noise_uv = surface_local_pos * bevel_noise_scale + bevel_origin_fraction;
			vec2 noise_vec = world_noise(noise_uv, bevel_origin_cell) * 2.0 - 1.0;
			slope += noise_vec * (bevel_noise_strength * edge_strength * slope_len);
		}

		slope += detail_slope;
		NORMAL_MAP = normalize(vec3(-slope.x, slope.y, 1.0)) * 0.5 + 0.5;
		float disturbed = smoothstep(0.2, 0.6, abs(height) + length(slope) * 0.5);
		ALBEDO = mix(lit_shadow_color, lit_surface_color, smoothstep(0.0, 0.9, hc)) * tex_col;
		ALBEDO *= 1.0 - disturbed_darkening * disturbed;
		ROUGHNESS = mix(mix(pressed_roughness, base_roughness, hc), glaze_roughness, ice_glaze);
	} else {
		NORMAL_MAP = normalize(vec3(-detail_slope.x, detail_slope.y, 1.0)) * 0.5 + 0.5;
		ALBEDO = lit_surface_color * tex_col;
		ROUGHNESS = base_roughness;
	}

	if (sparkle_intensity * sparkle_strength > 0.0 && hc > 0.3) {
		vec3 to_cam = CAMERA_POSITION_WORLD - world_pos;
		float dist_sq = dot(to_cam, to_cam);
		if (dist_sq < sparkle_fade_end * sparkle_fade_end) {
			float dist = sqrt(dist_sq);
			vec3 V = to_cam / max(dist, 0.0001);
			vec3 H = normalize(V + sun_dir); // Normalize sun_dir on CPU in DeformableSurface

			vec2 sparkle_uv = surface_local_pos * sparkle_density + sparkle_origin_fraction;
			vec2 cell = mod(floor(sparkle_uv) + sparkle_origin_cell, vec2(8192.0));
			float r1 = hash12(cell);
			float r2 = hash12(cell + 17.31);
			float r3 = hash12(cell + 91.7);

			vec3 gn = normalize(vec3(r1 * 2.0 - 1.0, 1.6, r2 * 2.0 - 1.0));
			float s = smoothstep(sparkle_threshold, 1.0, dot(gn, H));

			float twinkle_speed = 2.0 + r3 * 5.0;
			s *= 0.5 + 0.5 * sin(mod(TIME, 628.3185) * twinkle_speed + r3 * 40.0);
			s *= 1.0 - smoothstep(sparkle_fade_start, sparkle_fade_end, dist);
			s *= smoothstep(0.3, 0.8, hc);

			EMISSION = vec3(s) * (sparkle_intensity * sparkle_strength * 3.0) * mix(1.0, 2.0, ice_glaze);
		}
	}
}
