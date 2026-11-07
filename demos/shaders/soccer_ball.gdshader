shader_type spatial;

uniform vec3 ball_color : source_color = vec3(0.94, 0.94, 0.91);
uniform vec3 panel_color : source_color = vec3(0.025, 0.03, 0.04);
uniform float roughness = 0.38;

void fragment() {
	vec2 grid = UV * vec2(12.0, 6.0);
	float row = floor(grid.y);
	float shifted_x = grid.x - 0.5 * mod(row, 2.0);
	vec2 cell = vec2(floor(shifted_x), row);
	vec2 local = vec2(fract(shifted_x), fract(grid.y)) - 0.5;
	float hex_distance = max(dot(abs(local), vec2(0.8660254, 0.5)), abs(local.y));
	float panel = 1.0 - smoothstep(0.35, 0.39, hex_distance);
	float is_black_panel = 1.0 - step(1.0, mod(cell.x + 2.0 * cell.y, 3.0));

	ALBEDO = mix(ball_color, panel_color, panel * is_black_panel);
	ROUGHNESS = roughness;
}
