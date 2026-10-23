shader_type spatial;

uniform vec3 base_color: source_color = vec3(0.1, 0.08, 0.07);
uniform vec3 glow_color: source_color = vec3(1.0, 0.4, 0.05);

varying vec3 v_pos;

#include "res://game/shared/shaders/noise.gdshaderinc"
#include "res://game/planets/shared/shaders/lod_dither.gdshaderinc"

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	lod_dither(FRAGCOORD.xy);
	vec3 p = v_pos * 0.12;
	float crust = fbm(p + vec3(0.0, TIME * 0.02, 0.0), 4, 2.1);
	float cracks = fbm(p * 2.3 + vec3(TIME * 0.05, 0.0, TIME * 0.03), 4, 2.1);
	// crust high -> dark basalt; low -> molten
	float molten = (1.0 - smoothstep(0.35, 0.55, crust));
	float vein = smoothstep(0.45, 0.65, cracks) * molten;
	float pulse = 0.8 + 0.2 * sin(TIME * 1.5 + crust * 10.0);
	vec3 rock = base_color * (0.7 + 0.6 * crust);
	vec3 col = mix(rock, glow_color, vein);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.4, vein);
	EMISSION = glow_color * vein * 2.5 * pulse + glow_color * molten * 0.15;
}
