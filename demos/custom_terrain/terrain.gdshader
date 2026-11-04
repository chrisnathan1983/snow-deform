shader_type spatial;
// Hilly terrain driven by a DeformableSurface with render_mesh = false.
// The vertex stage pushes the mesh by the deformation height; the fragment stage tints and
// tilts the normal from the same map.

#include "res://addons/deformable_surface/shaders/deformable_surface.gdshaderinc"

uniform sampler2D deform_map : filter_linear, repeat_disable;
uniform vec4 deform_area = vec4(0.0, 0.0, 0.025, 0.025);
uniform float deform_max_depth = 0.25;
uniform float normal_strength = 1.0;

uniform vec3 grass_color : source_color = vec3(0.30, 0.46, 0.17);
uniform vec3 rock_color : source_color = vec3(0.42, 0.40, 0.37);
uniform vec3 dirt_color : source_color = vec3(0.30, 0.20, 0.12);

varying vec3 terrain_world_pos;
varying vec3 terrain_world_normal;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sample_deformation_height(deform_map, wp, deform_area, deform_max_depth);
	terrain_world_pos = wp;
	terrain_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	DeformSample s = sample_deformation(deform_map, terrain_world_pos, deform_area, deform_max_depth);

	float steep = smoothstep(0.7, 0.9, 1.0 - terrain_world_normal.y);
	vec3 base = mix(grass_color, rock_color, steep);
	// Pressed ground shows bare dirt and is slightly darker; berms stay as they were.
	vec3 color = mix(base, dirt_color, smoothstep(0.05, 0.6, s.pit_depth));
	ALBEDO = color * (1.0 - 0.3 * s.pit_depth);
	ROUGHNESS = 0.92;

	vec3 n = apply_deformation_normal(terrain_world_normal, s.slope, normal_strength);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
