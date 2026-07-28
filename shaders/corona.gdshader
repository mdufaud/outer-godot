shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 core_color: source_color = vec3(1.0, 0.82, 0.42);
uniform vec3 corona_color: source_color = vec3(1.0, 0.38, 0.05);
uniform vec3 outer_color: source_color = vec3(0.62, 0.10, 0.34);
uniform float corona_strength: hint_range(0.0, 8.0) = 3.0;
uniform float disk_radius: hint_range(0.05, 0.5) = 0.25;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i);
	float n100 = hash3(i + vec3(1, 0, 0));
	float n010 = hash3(i + vec3(0, 1, 0));
	float n110 = hash3(i + vec3(1, 1, 0));
	float n001 = hash3(i + vec3(0, 0, 1));
	float n101 = hash3(i + vec3(1, 0, 1));
	float n011 = hash3(i + vec3(0, 1, 1));
	float n111 = hash3(i + vec3(1, 1, 1));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z
	);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * value_noise(p);
		p *= 2.3;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	vec3 center_view = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	POSITION = PROJECTION_MATRIX * vec4(center_view + vec3(VERTEX.xy, 0.0), 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	vec3 ring = vec3(cos(angle), sin(angle), 0.0);
	float turbulence = fbm(ring * 3.4 + vec3(0.0, 0.0, TIME * 0.06) + radius * 2.2);
	float wisps = fbm(ring * 9.0 - vec3(0.0, 0.0, TIME * 0.11) + radius * 5.0);

	float rim = max(radius - disk_radius, 0.0) / max(disk_radius, 0.001);
	float chromosphere = exp(-rim * 11.0);
	float halo = exp(-rim * 3.4);
	float reach = exp(-rim * 1.35);
	float spikes = pow(max(sin(angle * 6.0 + TIME * 0.09 + turbulence * 4.5), 0.0), 4.0);
	float streamers = reach * spikes * (0.25 + 0.75 * wisps);

	float occlude = smoothstep(disk_radius * 0.88, disk_radius * 1.02, radius);
	float fade = 1.0 - smoothstep(0.45, 0.9, radius);
	vec3 color = core_color * chromosphere * 1.4
		+ corona_color * (halo * (0.5 + 0.5 * turbulence) + streamers * 0.6)
		+ outer_color * reach * 0.18;
	float alpha = (chromosphere * 1.0 + halo * 0.55 + streamers * 0.45 + reach * 0.05) * occlude * fade;
	ALBEDO = color * corona_strength;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
