shader_type spatial;
// Pine foliage with snow settled on up-facing surfaces and along the lower
// rim of each tier. COLOR.r is baked into the mesh: 0 at a tier's apex, 1 at its rim.

uniform vec3 leaf_color : source_color = vec3(0.13, 0.35, 0.22);
uniform vec3 snow_color : source_color = vec3(0.90, 0.93, 0.98);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.9;

varying vec3 w_pos;
varying vec3 w_normal;
varying float v_rim;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_rim = COLOR.r;
}

void fragment() {
	float n = hash12(floor(w_pos.xz * 5.0 + w_pos.y * 3.0));
	float n2 = hash12(floor(w_pos.xz * 1.5) + 7.0);

	float on_top = smoothstep(0.30, 0.70, w_normal.y + (n - 0.5) * 0.5);
	float band = smoothstep(0.54, 0.89, v_rim);          // 1 near the tier's lower rim
	float snow = clamp(on_top * 0.6 + band * (0.35 + 0.45 * n), 0.0, 1.0);
	snow = smoothstep(0.30, 0.60, snow) * step(-0.2, w_normal.y) * snow_amount;

	vec3 leaves = leaf_color * (0.85 + 0.3 * n2);
	ALBEDO = mix(leaves, snow_color, snow);
	ROUGHNESS = mix(0.9, 0.65, snow);
}
