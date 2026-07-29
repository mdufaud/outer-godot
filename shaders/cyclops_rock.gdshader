shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 rock_position;

float hash31(vec3 value) {
	value = fract(value * 0.1031);
	value += dot(value, value.yzx + 33.33);
	return fract((value.x + value.y) * value.z);
}

float noise3(vec3 value) {
	vec3 cell = floor(value);
	vec3 blend_value = fract(value);
	blend_value = blend_value * blend_value * (3.0 - 2.0 * blend_value);
	float lower = mix(
		mix(hash31(cell), hash31(cell + vec3(1.0, 0.0, 0.0)), blend_value.x),
		mix(hash31(cell + vec3(0.0, 1.0, 0.0)), hash31(cell + vec3(1.0, 1.0, 0.0)), blend_value.x),
		blend_value.y
	);
	float upper = mix(
		mix(hash31(cell + vec3(0.0, 0.0, 1.0)), hash31(cell + vec3(1.0, 0.0, 1.0)), blend_value.x),
		mix(hash31(cell + vec3(0.0, 1.0, 1.0)), hash31(cell + vec3(1.0)), blend_value.x),
		blend_value.y
	);
	return mix(lower, upper, blend_value.z);
}

void vertex() {
	rock_position = VERTEX;
}

void fragment() {
	float strata = sin(rock_position.y * 1.45 + sin(rock_position.x * 0.38) * 1.7 + rock_position.z * 0.16) * 0.5 + 0.5;
	strata = smoothstep(0.22, 0.82, strata);
	vec3 warp = vec3(
		noise3(rock_position * 0.13),
		noise3(rock_position * 0.13 + 17.0),
		noise3(rock_position * 0.13 + 41.0)
	);
	float mineral = noise3(rock_position * 0.34 + warp * 2.8);
	float veins = pow(clamp(1.0 - abs(mineral - 0.5) * 18.0, 0.0, 1.0), 2.0);
	float wet = 1.0 - smoothstep(-0.5, 5.0, rock_position.y);
	vec3 basalt = mix(vec3(0.004, 0.012, 0.014), vec3(0.012, 0.038, 0.040), strata);
	ALBEDO = basalt + vec3(0.0, 0.015, 0.014) * wet;
	EMISSION = vec3(0.02, 0.34, 0.28) * veins * (0.05 + wet * 0.10);
	ROUGHNESS = mix(0.86, 0.34, wet);
	METALLIC = 0.08;
	SPECULAR = 0.32;
}
