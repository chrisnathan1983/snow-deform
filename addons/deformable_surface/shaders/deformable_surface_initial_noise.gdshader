shader_type canvas_item;

#include "res://addons/deformable_surface/shaders/deformable_surface_initial_noise.gdshaderinc"

void fragment() {
	COLOR = vec4(initial_map_color(UV), 1.0);
}
