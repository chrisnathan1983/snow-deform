shader_type canvas_item;
render_mode blend_sub;

uniform float pit_levels = 1.0;
uniform float berm_levels = 1.5;
uniform float bulge_levels = 65.0;
uniform float seed = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float pit_whole = floor(pit_levels);
	float pit_extra = hash12(FRAGCOORD.xy + seed) < (pit_levels - pit_whole) ? 1.0 : 0.0;

	float berm_whole = floor(berm_levels);
	float berm_extra = hash12(FRAGCOORD.xy + seed + 37.0) < (berm_levels - berm_whole) ? 1.0 : 0.0;

	float bulge_whole = floor(bulge_levels);
	float bulge_extra = hash12(FRAGCOORD.xy + seed + 73.0) < (bulge_levels - bulge_whole) ? 1.0 : 0.0;

	COLOR = vec4(
		(pit_whole + pit_extra) / 255.0,
		(berm_whole + berm_extra) / 255.0,
		(bulge_whole + bulge_extra) / 255.0,
		1.0
	);
}
