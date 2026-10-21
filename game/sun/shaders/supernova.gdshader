shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 core_color: source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 mid_color: source_color = vec3(0.45, 0.78, 1.0);
uniform vec3 edge_color: source_color = vec3(0.10, 0.36, 0.95);
uniform float emission_strength: hint_range(0.5, 10.0) = 5.0;
uniform float wave_progress: hint_range(0.0, 1.0) = 0.0;
uniform float ignition: hint_range(0.0, 1.0) = 0.0;

varying vec3 v_pos;

#include "res://game/shared/shaders/noise.gdshaderinc"

void vertex() {
	v_pos = normalize(VERTEX);
}

void fragment() {
	vec3 direction = normalize(v_pos);
	vec3 churn = vec3(TIME * 0.09, -TIME * 0.07, TIME * 0.05);
	float broad = fbm(direction * 2.6 + churn, 4, 2.1);
	float cells = fbm(direction * 8.0 - churn * 1.6 + broad * 2.4, 4, 2.1);
	float filaments = fbm(direction * 19.0 + churn * 0.8 + cells * 1.8, 4, 2.1);
	float turbulence = clamp(broad * 0.4 + cells * 0.4 + filaments * 0.35, 0.0, 1.0);
	// Grazing angles are where the shell is thickest along the view ray, so the
	// silhouette has to read hotter than the face pointing straight at the camera.
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), VIEW)), 2.4);
	vec3 color = mix(edge_color, mid_color, smoothstep(0.15, 0.62, turbulence));
	color = mix(color, core_color, smoothstep(0.66, 1.0, turbulence) * 0.7);
	color = mix(color, core_color, rim * 0.9);
	// The front thins as it sweeps outwards: bright wall up close, faint veil at the rim.
	float thinning = 1.0 - smoothstep(0.35, 1.0, wave_progress);
	float plasma = pow(turbulence, 1.6);
	float energy = emission_strength * plasma * (0.45 + rim * 1.3) * mix(0.3, 1.0, thinning);
	// The first instant is a white-out: the structure only resolves once the flash decays.
	color = mix(color, vec3(1.0), ignition * 0.9);
	energy *= 1.0 + ignition * 8.0;
	ALBEDO = color * energy;
	float alpha = (plasma * 0.75 + rim * 0.95) * mix(0.35, 1.0, thinning);
	ALPHA = clamp(max(alpha, ignition), 0.0, 1.0);
}
