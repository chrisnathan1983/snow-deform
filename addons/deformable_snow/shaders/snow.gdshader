shader_type spatial;

// Deformation map: R = pit depth (0 = untouched, 1 = fully pressed)
//                  G = berm (0 = none, 1 = max ridge)
//                  B = bulge (0 = none, 1 = max bulge)
uniform sampler2D deform_map : filter_linear, repeat_disable;
uniform float map_texel = 0.002;
uniform float max_depth = 0.25;
uniform float berm_height = 0.08;   // meters at G = 1
uniform float bulge_height = 0.38;   // meters at B = 1
uniform float vertex_texel = 0.005; // UV distance between mesh vertices (set by SnowField)

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
uniform vec3 sun_dir = vec3(0.4, 0.8, 0.3); // direction TOWARD the light
uniform float sparkle_fade_start = 20.0;
uniform float sparkle_fade_end = 45.0;

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float world_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(cell);
	float b = hash12(cell + vec2(1.0, 0.0));
	float c = hash12(cell + vec2(0.0, 1.0));
	float d = hash12(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Height in "depth units" (1.0 = max_depth): negative = pressed, positive = berm.
float height_n(vec3 m) {
	float pit = m.r;
	float rim = m.g * (1.0 - pit);
	// Steep cartoon dome with a slight perimeter dip at the base edge so normals pop
	float dome = smoothstep(0.20, 0.75, m.b);
	float moat = smoothstep(0.02, 0.20, m.b) * (1.0 - smoothstep(0.20, 0.40, m.b));
	float bulge = (dome - moat * 0.18) * (1.0 - pit);
	
	return (rim * berm_height + bulge * bulge_height) / max_depth - pit;

	// Plump rounded dome that cleanly fades to 0 with no negative trench in the wake
	//float bulge = pow(smoothstep(0.15, 0.85, m.b), 0.7) * (1.0 - pit);
	//return (rim * berm_height + bulge * bulge_height) / max_depth - pit;
}

vec3 sample_vertex_map(vec2 uv) {
	float k = vertex_texel * 0.75;
	vec3 center = textureLod(deform_map, uv, 0.0).rgb;
	vec3 upper_right = textureLod(deform_map, uv + vec2( k,  k), 0.0).rgb;
	vec3 upper_left = textureLod(deform_map, uv + vec2(-k,  k), 0.0).rgb;
	vec3 lower_right = textureLod(deform_map, uv + vec2( k, -k), 0.0).rgb;
	vec3 lower_left = textureLod(deform_map, uv + vec2(-k, -k), 0.0).rgb;
	vec3 m = center * 0.36;
	m += (upper_right + upper_left + lower_right + lower_left) * 0.16;

	// Smooth only the bulge over neighboring mesh vertices so tiny domes
	// don't inherit a square silhouette from the coarse vertex grid.
	float bulge = center.b * 0.25;
	bulge += textureLod(deform_map, uv + vec2( k, 0.0), 0.0).b * 0.125;
	bulge += textureLod(deform_map, uv + vec2(-k, 0.0), 0.0).b * 0.125;
	bulge += textureLod(deform_map, uv + vec2(0.0,  k), 0.0).b * 0.125;
	bulge += textureLod(deform_map, uv + vec2(0.0, -k), 0.0).b * 0.125;
	bulge += (upper_right.b + upper_left.b + lower_right.b + lower_left.b) * 0.0625;
	m.b = bulge;
	return m;
}

void vertex() {
	vec3 m = sample_vertex_map(UV);
	vec3 base_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Rapid cartoon "chugging" bounce on the active bulge crest
	float bob = sin(TIME * 28.0 + base_world_pos.x * 6.0 + base_world_pos.z * 6.0) * 0.035 * smoothstep(0.3, 1.0, m.b);
	VERTEX.y += height_n(m) * max_depth + bob * (1.0 - m.r);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = map_texel * 1.5;
	vec3 ml = texture(deform_map, UV - vec2(t, 0.0)).rgb;
	vec3 mr = texture(deform_map, UV + vec2(t, 0.0)).rgb;
	vec3 mu = texture(deform_map, UV - vec2(0.0, t)).rgb;
	vec3 md = texture(deform_map, UV + vec2(0.0, t)).rgb;
	float hl = height_n(ml);
	float hr = height_n(mr);
	float hu = height_n(mu);
	float hd = height_n(md);

float avg_pit = (ml.r + mr.r + mu.r + md.r) * 0.25;
	float avg_bulge = (ml.b + mr.b + mu.b + md.b) * 0.25 * (1.0 - avg_pit);
	float hc = 1.0 - avg_pit;

	// Separate bulge slope so only the steep walls of the active lump get darkened
	float b_hl = smoothstep(0.15, 0.85, ml.b);
	float b_hr = smoothstep(0.15, 0.85, mr.b);
	float b_hu = smoothstep(0.15, 0.85, mu.b);
	float b_hd = smoothstep(0.15, 0.85, md.b);
	float bulge_wall = clamp(length(vec2(b_hr - b_hl, b_hd - b_hu)) * 3.5, 0.0, 1.0);

	vec2 slope = vec2(hr - hl, hd - hu) * normal_strength;
	float edge_strength = smoothstep(0.05, 0.5, length(slope));
	vec2 noise_uv = world_pos.xz * bevel_noise_scale;
	vec2 noise_vec = vec2(
		world_noise(noise_uv),
		world_noise(noise_uv + vec2(43.17, 19.83))
	) * 2.0 - 1.0;

	// Chunky clods only on the upper half of the active lump (avg_bulge > 0.35)
	float active_lump = smoothstep(0.35, 0.75, avg_bulge);
	vec2 clod_uv = world_pos.xz * 6.5;
	vec2 clod_vec = vec2(
		world_noise(clod_uv),
		world_noise(clod_uv + vec2(17.4, 53.2))
	) * 2.0 - 1.0;

	slope += noise_vec * bevel_noise_strength * edge_strength * length(slope);
	slope += clod_vec * active_lump * normal_strength * 0.75;
	NORMAL_MAP = normalize(vec3(-slope, 1.0)) * 0.5 + 0.5;

	// Darken only the steep wall around the active lump and cracks on its crest,
	// so the decaying tail (< 0.35) disappears cleanly back into white snow
	float clod_cracks = smoothstep(0.4, 0.75, abs(clod_vec.x)) * active_lump;
	float bulge_darkening = clamp(bulge_wall * 0.65 * smoothstep(0.25, 0.5, avg_bulge) + clod_cracks * 0.75, 0.0, 1.0);

	ALBEDO = mix(shadow_color, snow_color, smoothstep(0.0, 0.9, hc * (1.0 - bulge_darkening)));
	ROUGHNESS = mix(0.50, 0.88, hc);

	if (sparkle_intensity > 0.0) {
		vec3 V = normalize(CAMERA_POSITION_WORLD - world_pos);
		vec3 H = normalize(V + normalize(sun_dir));

		vec2 cell = floor(world_pos.xz * sparkle_density);
		float r1 = hash12(cell);
		float r2 = hash12(cell + 17.31);
		float r3 = hash12(cell + 91.7);

		vec3 gn = normalize(vec3(r1 * 2.0 - 1.0, 1.6, r2 * 2.0 - 1.0));
		float s = smoothstep(sparkle_threshold, 1.0, dot(gn, H));
		
		float twinkle_speed = (2.0 + r3 * 5.0) + avg_bulge * 18.0;
		s *= 0.5 + 0.5 * sin(TIME * twinkle_speed + r3 * 40.0);

		float dist = length(CAMERA_POSITION_WORLD - world_pos);
		s *= 1.0 - smoothstep(sparkle_fade_start, sparkle_fade_end, dist);
		s *= smoothstep(0.3, 0.8, hc);

		EMISSION = vec3(s) * sparkle_intensity * 3.0;
	}
}

void light() {
	if (wrapped_diffuse_lighting) {
		// Soften the terminator slightly without lifting 0.0 shadows to white
		float NdotL = clamp((dot(NORMAL, LIGHT) + wrap_amount) / (1.0 + wrap_amount), 0.0, 1.0);
		
		// Red drops off slightly faster than Green/Blue on angled footprint rims,
		// giving bevels a cool winter mid-tone while still reaching 0.0 on the dark side
		vec3 cool_ramp = vec3(pow(NdotL, 1.35), pow(NdotL, 1.15), NdotL);
		
		DIFFUSE_LIGHT += cool_ramp * ATTENUATION * LIGHT_COLOR / PI;
	} else {
		float NdotL = max(dot(NORMAL, LIGHT), 0.0);
		DIFFUSE_LIGHT += NdotL * ATTENUATION * LIGHT_COLOR / PI;
	}
}