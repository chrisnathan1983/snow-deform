shader_type spatial;

// Deformation map: R = combined height (0.5 = flat, lower = pit, higher = berm)
//                  G/B = encoded X/Z height gradients.
uniform sampler2D deform_map : filter_linear, repeat_disable;
uniform float max_depth = 0.25;

uniform vec3 snow_color : source_color = vec3(0.90, 0.93, 0.98);
uniform vec3 shadow_color : source_color = vec3(0.68, 0.74, 0.84);
uniform float normal_strength = 10.0;
uniform bool wrapped_diffuse_lighting = true;
uniform float wrap_amount : hint_range(0.0, 0.5) = 0.4;
uniform float bevel_noise_scale = 32.0;
uniform float bevel_noise_strength = 0.45;

uniform float sparkle_intensity = 1.0;   // 0 = off (skips the whole block)
uniform float sparkle_density = 24.0;    // cells per meter
uniform float sparkle_threshold = 0.99;
uniform vec3 sun_dir = vec3(0.424, 0.848, 0.318); // direction TOWARD the light
uniform float sparkle_fade_start = 20.0;
uniform float sparkle_fade_end = 45.0;

varying vec3 world_pos;

const float MAP_NEUTRAL = 128.0 / 255.0;
const float SLOPE_RANGE = 16.0;

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

vec2 world_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec2 a = hash22(cell);
	vec2 b = hash22(cell + vec2(1.0, 0.0));
	vec2 c = hash22(cell + vec2(0.0, 1.0));
	vec2 d = hash22(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Height in "depth units" (1.0 = max_depth): negative = pressed, positive = berm.
float height_n(float encoded_height) {
	return (encoded_height - MAP_NEUTRAL) * 2.0;
}

float sample_vertex_height(vec2 uv) {
	return textureLod(deform_map, uv, 0.0).r;
}

void vertex() {
	float height = height_n(sample_vertex_height(UV));
	vec3 base_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dy = height * max_depth;
	VERTEX.y += dy;
	world_pos = base_world_pos + vec3(0.0, dy, 0.0); // Avoids 2nd matrix multiply
}

void fragment() {
	vec3 map_sample = texture(deform_map, UV).rgb;
	float height = height_n(map_sample.r);
	float pit_depth = clamp(-height, 0.0, 1.0);
	float hc = 1.0 - pit_depth;
	float ice_glaze = smoothstep(0.75, 0.98, pit_depth);
	vec2 slope = (map_sample.gb - vec2(MAP_NEUTRAL)) * SLOPE_RANGE * (normal_strength / 10.0);

	// Fast path: skip all noise and slope math on untouched flat snow
	if (abs(height) + abs(slope.x) + abs(slope.y) > 0.02) {
		float slope_len = length(slope);
		float edge_strength = smoothstep(0.05, 0.5, slope_len);

		if (edge_strength > 0.001) {
			vec2 noise_uv = world_pos.xz * bevel_noise_scale;
			vec2 noise_vec = world_noise(noise_uv) * 2.0 - 1.0;
			slope += noise_vec * (bevel_noise_strength * edge_strength * slope_len);
		}

		NORMAL_MAP = normalize(vec3(-slope, 1.0)) * 0.5 + 0.5;
		ALBEDO = mix(shadow_color, snow_color, smoothstep(0.0, 0.9, hc));
		ROUGHNESS = mix(mix(0.50, 0.88, hc), 0.18, ice_glaze);
	} else {
		ALBEDO = snow_color;
		ROUGHNESS = 0.88;
	}

	if (sparkle_intensity > 0.0 && hc > 0.3) {
		vec3 to_cam = CAMERA_POSITION_WORLD - world_pos;
		float dist_sq = dot(to_cam, to_cam);
		if (dist_sq < sparkle_fade_end * sparkle_fade_end) {
			float dist = sqrt(dist_sq);
			vec3 V = to_cam / max(dist, 0.0001);
			vec3 H = normalize(V + sun_dir); // Normalize sun_dir on CPU in SnowField

			vec2 cell = floor(world_pos.xz * sparkle_density);
			float r1 = hash12(cell);
			float r2 = hash12(cell + 17.31);
			float r3 = hash12(cell + 91.7);

			vec3 gn = normalize(vec3(r1 * 2.0 - 1.0, 1.6, r2 * 2.0 - 1.0));
			float s = smoothstep(sparkle_threshold, 1.0, dot(gn, H));

			float twinkle_speed = 2.0 + r3 * 5.0;
			s *= 0.5 + 0.5 * sin(mod(TIME, 628.3185) * twinkle_speed + r3 * 40.0);
			s *= 1.0 - smoothstep(sparkle_fade_start, sparkle_fade_end, dist);
			s *= smoothstep(0.3, 0.8, hc);

			EMISSION = vec3(s) * (sparkle_intensity * 3.0) * mix(1.0, 2.0, ice_glaze);
		}
	}
}

void light() {
	if (wrapped_diffuse_lighting) {
		float NdotL = clamp((dot(NORMAL, LIGHT) + wrap_amount) / (1.0 + wrap_amount), 0.0, 1.0);
		// Fast polynomial approximation of pow(NdotL, 1.35) and pow(NdotL, 1.15)
		vec3 cool_ramp = vec3(NdotL * mix(0.65, 1.0, NdotL), NdotL * mix(0.85, 1.0, NdotL), NdotL);
		DIFFUSE_LIGHT += cool_ramp * ATTENUATION * LIGHT_COLOR / PI;
	} else {
		float NdotL = max(dot(NORMAL, LIGHT), 0.0);
		DIFFUSE_LIGHT += NdotL * ATTENUATION * LIGHT_COLOR / PI;
	}
}