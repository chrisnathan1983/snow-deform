// World-space value noise for the built-in starting-surface profile.
uniform vec2 initial_noise_origin = vec2(0.0);
uniform vec2 initial_noise_area = vec2(32.0);
uniform float initial_noise_resolution = 256.0;
uniform float initial_noise_depth = 0.4;
uniform float initial_noise_frequency = 0.8;
uniform float initial_noise_height = 0.2;
uniform float initial_noise_detail = 0.6;
uniform float initial_noise_detail_scale = 0.25;
uniform float initial_noise_mound_height = 0.3;
uniform float initial_noise_mound_frequency = 0.1;
uniform bool initial_noise_invert = false;

const float INITIAL_MAP_NEUTRAL = 128.0 / 255.0;

float initial_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float initial_value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = initial_hash(cell) * 2.0 - 1.0;
	float b = initial_hash(cell + vec2(1.0, 0.0)) * 2.0 - 1.0;
	float c = initial_hash(cell + vec2(0.0, 1.0)) * 2.0 - 1.0;
	float d = initial_hash(cell + vec2(1.0, 1.0)) * 2.0 - 1.0;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec2 initial_world_position(vec2 uv) {
	// Align fragment centers with the CPU path's endpoint-inclusive texel samples.
	vec2 texel = uv * initial_noise_resolution - vec2(0.5);
	return initial_noise_origin + texel * initial_noise_area / (initial_noise_resolution - 1.0);
}

float initial_height_at(vec2 world_pos) {
	float frequency = max(initial_noise_frequency, 0.01);
	float detail = clamp(initial_noise_detail, 0.0, 1.0);
	float value = initial_value_noise(world_pos * frequency);
	if (detail > 0.0) {
		value = (value + detail * initial_value_noise(world_pos * frequency * max(initial_noise_detail_scale, 0.05))) / (1.0 + detail);
	}
	if (initial_noise_invert) {
		value = -value;
	}
	float amplitude = clamp(initial_noise_height, 0.0, initial_noise_depth);
	float mound_height = clamp(initial_noise_mound_height, 0.0, initial_noise_depth);
	float mound = smoothstep(-0.1, 0.6, initial_value_noise(world_pos * max(initial_noise_mound_frequency, 0.005) + vec2(17.13, 29.71)));
	float surface_level = amplitude + mound * mound_height;
	return min(surface_level * (1.0 + value) - amplitude, initial_noise_depth);
}

vec3 initial_map_color(vec2 uv) {
	vec2 world_pos = initial_world_position(uv);
	float height = initial_height_at(world_pos);
	vec2 texel_step = initial_noise_area / (initial_noise_resolution - 1.0);
	float slope_x = (initial_height_at(world_pos + vec2(texel_step.x, 0.0))
		- initial_height_at(world_pos - vec2(texel_step.x, 0.0))) / (2.0 * texel_step.x);
	float slope_z = (initial_height_at(world_pos + vec2(0.0, texel_step.y))
		- initial_height_at(world_pos - vec2(0.0, texel_step.y))) / (2.0 * texel_step.y);
	return vec3(
		INITIAL_MAP_NEUTRAL + height / (2.0 * initial_noise_depth),
		INITIAL_MAP_NEUTRAL + slope_x / 16.0,
		INITIAL_MAP_NEUTRAL + slope_z / 16.0
	);
}
