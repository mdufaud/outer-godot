shader_type spatial;

uniform vec3 base_color: source_color = vec3(0.62, 0.76, 0.88);
uniform vec3 crack_color: source_color = vec3(0.25, 0.5, 0.75);

varying vec3 v_pos;

#include "res://game/shared/shaders/noise.gdshaderinc"
#include "res://game/planets/shared/shaders/lod_dither.gdshaderinc"

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	lod_dither(FRAGCOORD.xy);
	vec3 p = v_pos * 0.1;
	float n = fbm(p, 4, 2.1);
	// thin crack lines: ridged noise
	float ridge = 1.0 - abs(2.0 * fbm(p * 2.7 + 31.0, 4, 2.1) - 1.0);
	float crack = smoothstep(0.88, 0.98, ridge);
	vec3 col = mix(base_color, base_color * 1.15, n);
	col = mix(col, crack_color, crack * 0.6);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = col;
	ROUGHNESS = 0.12 + 0.25 * n;
	SPECULAR = 0.7;
	EMISSION = base_color * fresnel * 0.35;
}
