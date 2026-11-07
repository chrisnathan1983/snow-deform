shader_type spatial;
render_mode cull_disabled;
// Grass blades that read the deformation map at their root: they lean away from footprints
// (the map slope points outward), lie flatter in pits and follow the ground height.

#include "res://addons/deformable_surface/shaders/deformable_surface.gdshaderinc"

uniform sampler2D deform_map : filter_linear, repeat_disable;
uniform vec4 deform_area = vec4(0.0, 0.0, 0.025, 0.025);
uniform float deform_max_depth = 0.25;
uniform float bend_strength = 0.35;
uniform float flatten_amount = 0.75;

uniform vec3 base_color : source_color = vec3(0.14, 0.26, 0.07);
uniform vec3 tip_color : source_color = vec3(0.55, 0.72, 0.24);

varying float tip;
varying float tint;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	DeformSample s = sample_deformation(deform_map, root, deform_area, deform_max_depth);

	tip = UV.y;
	tint = fract(sin(dot(root.xz, vec2(12.9898, 78.233))) * 43758.5453);

	// Bend in world space, then bring it back into the blade's rotated model space.
	vec2 slope = clamp(s.slope, vec2(-1.0), vec2(1.0));
	vec3 world_bend = vec3(slope.x, 0.0, slope.y) * bend_strength * tip * tip;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * world_bend;

	VERTEX.y *= 1.0 - flatten_amount * s.pit_depth;
	// The root moves with the ground; blade scale is uniform, so convert meters to model units.
	VERTEX.y += s.height / max(length(MODEL_MATRIX[1].xyz), 0.0001);
}

void fragment() {
	ALBEDO = mix(base_color, tip_color, tip) * (0.8 + 0.4 * tint);
	ROUGHNESS = 0.85;
}
