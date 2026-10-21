shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 rock_position;

#include "res://game/shared/shaders/noise.gdshaderinc"

void vertex() {
	rock_position = VERTEX;
}

void fragment() {
	float strata = sin(rock_position.y * 1.45 + sin(rock_position.x * 0.38) * 1.7 + rock_position.z * 0.16) * 0.5 + 0.5;
	strata = smoothstep(0.22, 0.82, strata);
	vec3 warp = vec3(
		hash31_value_noise(rock_position * 0.13),
		hash31_value_noise(rock_position * 0.13 + 17.0),
		hash31_value_noise(rock_position * 0.13 + 41.0)
	);
	float mineral = hash31_value_noise(rock_position * 0.34 + warp * 2.8);
	float veins = pow(clamp(1.0 - abs(mineral - 0.5) * 18.0, 0.0, 1.0), 2.0);
	float wet = 1.0 - smoothstep(-0.5, 5.0, rock_position.y);
	vec3 basalt = mix(vec3(0.004, 0.012, 0.014), vec3(0.012, 0.038, 0.040), strata);
	ALBEDO = basalt + vec3(0.0, 0.015, 0.014) * wet;
	EMISSION = vec3(0.02, 0.34, 0.28) * veins * (0.05 + wet * 0.10);
	ROUGHNESS = mix(0.86, 0.34, wet);
	METALLIC = 0.08;
	SPECULAR = 0.32;
}
