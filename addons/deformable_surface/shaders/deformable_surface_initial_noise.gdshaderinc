// Shared, seamless noise textures sampled in world space for the starting surface.
uniform vec2 initial_noise_origin = vec2(0.0);
uniform vec2 initial_noise_area = vec2(32.0);
uniform float initial_noise_resolution = 256.0;
uniform float initial_noise_depth = 0.4;
uniform float initial_noise_world_period = 128.0;
uniform bool initial_noise_enabled = true;
uniform sampler2D initial_noise_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D initial_noise_detail_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D initial_noise_mound_texture : filter_linear_mipmap, repeat_enable;
uniform float initial_noise_frequency = 0.8;
uniform float initial_noise_height = 0.2;
uniform float initial_noise_detail = 0.6;
uniform float initial_noise_detail_scale = 0.25;
uniform float initial_noise_mound_height = 0.3;
uniform float initial_noise_mound_frequency = 0.1;
uniform bool initial_noise_invert = false;

const float INITIAL_MAP_NEUTRAL = 128.0 / 255.0;

vec2 initial_world_position(vec2 uv) {
	// Align fragment centers with endpoint-inclusive map texel samples.
	vec2 texel = uv * initial_noise_resolution - vec2(0.5);
	return initial_noise_origin + texel * initial_noise_area / (initial_noise_resolution - 1.0);
}

float initial_height_at(vec2 world_pos) {
	float frequency = max(initial_noise_frequency, 0.01);
	float detail = clamp(initial_noise_detail, 0.0, 1.0);
	vec2 base_uv = world_pos * (frequency / initial_noise_world_period);
	float value = texture(initial_noise_texture, base_uv).r * 2.0 - 1.0;
	if (detail > 0.0) {
		vec2 detail_uv = world_pos * (frequency * max(initial_noise_detail_scale, 0.05) / initial_noise_world_period);
		float fine_value = texture(initial_noise_detail_texture, detail_uv).r * 2.0 - 1.0;
		value = (value + detail * fine_value) / (1.0 + detail);
	}
	if (initial_noise_invert) {
		value = -value;
	}
	float amplitude = clamp(initial_noise_height, 0.0, initial_noise_depth);
	float mound_height = clamp(initial_noise_mound_height, 0.0, initial_noise_depth);
	vec2 mound_uv = world_pos * (max(initial_noise_mound_frequency, 0.005) / initial_noise_world_period);
	float mound_noise = texture(initial_noise_mound_texture, mound_uv).r * 2.0 - 1.0;
	float mound = smoothstep(-0.1, 0.6, mound_noise);
	float surface_level = amplitude + mound * mound_height;
	return min(surface_level * (1.0 + value) - amplitude, initial_noise_depth);
}

vec3 initial_map_color(vec2 uv) {
	if (!initial_noise_enabled) {
		return vec3(INITIAL_MAP_NEUTRAL);
	}
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
