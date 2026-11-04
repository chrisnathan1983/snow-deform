// Shared decoding for the deformation map. Include it from your own terrain or foliage shader:
//   #include "res://addons/deformable_surface/shaders/deformable_surface.gdshaderinc"
// Bind the map with DeformableSurface.get_deform_texture() and the area with
// DeformableSurface.get_deform_area_transform() (set `render_mesh` to false to use your own mesh).
//
// Map layout: R = height (neutral = flat, lower = pit, higher = berm),
//             G/B = encoded +dh/dx, +dh/dz gradients.

const float DEFORM_MAP_NEUTRAL = 128.0 / 255.0;
const float DEFORM_SLOPE_RANGE = 16.0;

struct DeformSample {
	float height;      // Signed world offset in meters (-max_depth .. +max_depth)
	float pit_depth;   // 0..1 normalized depression depth (darkening, roughness)
	vec2 slope;        // (dh/dx, dh/dz); points away from the center of a pit, so it also bends grass
	float mask;        // 0 outside the deformation area, 1 inside (feathered edge)
};

// Height in depth units (1.0 = max_depth): negative = pressed, positive = berm.
float deform_height_n(float encoded_height) {
	return (encoded_height - DEFORM_MAP_NEUTRAL) * 2.0;
}

vec2 deform_decode_slope(vec2 encoded_slope) {
	return (encoded_slope - vec2(DEFORM_MAP_NEUTRAL)) * DEFORM_SLOPE_RANGE;
}

// area_transform = (center_x, center_z, 1.0 / size_x, 1.0 / size_z)
vec2 deform_world_to_uv(vec3 world_pos, vec4 area_transform) {
	return (world_pos.xz - area_transform.xy) * area_transform.zw + vec2(0.5);
}

// Fades deformation out near the map edge, since the map does not tile.
float deform_bounds_mask(vec2 uv) {
	vec2 d = abs(uv - vec2(0.5)) * 2.0;
	return 1.0 - smoothstep(0.92, 1.0, max(d.x, d.y));
}

// Decodes height, pit depth and slope in one fetch. Fragment shaders and vertex shaders can both use it.
DeformSample sample_deformation(sampler2D map, vec3 world_pos, vec4 area_transform, float max_depth) {
	DeformSample s;
	vec2 uv = deform_world_to_uv(world_pos, area_transform);
	s.mask = deform_bounds_mask(uv);
	if (s.mask <= 0.001) {
		s.height = 0.0;
		s.pit_depth = 0.0;
		s.slope = vec2(0.0);
		return s;
	}
	vec3 raw = textureLod(map, uv, 0.0).rgb;
	float h_norm = deform_height_n(raw.r) * s.mask;
	s.height = h_norm * max_depth;
	s.pit_depth = clamp(-h_norm, 0.0, 1.0);
	s.slope = deform_decode_slope(raw.gb) * s.mask;
	return s;
}

// Vertical displacement in meters; add it to VERTEX.y in a vertex() function.
float sample_deformation_height(sampler2D map, vec3 world_pos, vec4 area_transform, float max_depth) {
	vec2 uv = deform_world_to_uv(world_pos, area_transform);
	float mask = deform_bounds_mask(uv);
	if (mask <= 0.001) {
		return 0.0;
	}
	return deform_height_n(textureLod(map, uv, 0.0).r) * max_depth * mask;
}

// Tilts a world-space normal by the deformation slope. `strength` ~ the surface's normal_strength / 10.
vec3 apply_deformation_normal(vec3 world_normal, vec2 slope, float strength) {
	return normalize(world_normal + vec3(-slope.x * strength, 0.0, -slope.y * strength));
}
