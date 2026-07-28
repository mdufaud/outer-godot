shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 core_color: source_color = vec3(1.0, 0.82, 0.42);
uniform vec3 corona_color: source_color = vec3(1.0, 0.38, 0.05);
uniform vec3 outer_color: source_color = vec3(0.62, 0.10, 0.34);
uniform vec3 band_color: source_color = vec3(0.18, 0.95, 0.72);
uniform vec3 ray_color: source_color = vec3(1.0, 0.62, 0.22);
uniform vec3 ember_color: source_color = vec3(1.0, 0.55, 0.18);
uniform float corona_strength: hint_range(0.0, 8.0) = 3.0;
uniform float disk_radius: hint_range(0.05, 0.5) = 0.25;
uniform bool pulse_enabled = true;
uniform bool god_rays_enabled = true;
uniform bool prominences_enabled = true;
uniform bool chromatic_band_enabled = true;
uniform bool embers_enabled = true;

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

float prominence_arcs(vec2 p) {
	float total = 0.0;
	for (int i = 0; i < 4; i++) {
		float index = float(i);
		float seed = hash3(vec3(index, 3.0, 7.0));
		float phase = hash3(vec3(index, 11.0, 2.0));
		float life = fract(TIME * (0.035 + seed * 0.025) + phase);
		float envelope = sin(life * 3.14159);
		float base_angle = phase * 6.28318 + life * 0.3;
		vec2 anchor = vec2(cos(base_angle), sin(base_angle));
		float loop_radius = disk_radius * (0.14 + 0.20 * seed) * envelope;
		vec2 center = anchor * (disk_radius + loop_radius * 0.55);
		float wobble = fbm(vec3(p * 7.0, TIME * 0.07 + index * 4.0));
		float distance_to_arc = abs(length(p - center) - loop_radius * (0.82 + 0.36 * wobble));
		total += exp(-distance_to_arc * 190.0) * envelope;
	}
	return total;
}

float ray_shafts(float angle, float rim) {
	float rotated = angle + TIME * 0.018;
	float shafts = fbm(vec3(cos(rotated), sin(rotated), 0.0) * 2.4 + 31.0);
	shafts = smoothstep(0.42, 0.9, shafts);
	return shafts * shafts * exp(-rim * 0.85);
}

float ember_sparks(float angle, float rim) {
	float row = floor(rim * 5.0);
	float drift = TIME * (0.02 + hash3(vec3(row, 2.0, 5.0)) * 0.05);
	float column_position = fract(angle / 6.28318 + 0.5 + drift) * 40.0;
	float column = floor(column_position);
	float seed = hash3(vec3(column, row, 11.0));
	if (seed < 0.82) {
		return 0.0;
	}
	vec2 offset = vec2(fract(column_position), fract(rim * 5.0))
		- vec2(0.3 + hash3(vec3(column, row, 3.0)) * 0.4, 0.3 + hash3(vec3(column, row, 4.0)) * 0.4);
	float spark = smoothstep(0.14, 0.0, length(offset));
	float flicker = 0.45 + 0.55 * sin(TIME * (2.0 + seed * 5.0) + seed * 30.0);
	return spark * flicker * exp(-rim * 1.6);
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

	vec3 color = core_color * chromosphere * 1.4
		+ corona_color * (halo * (0.5 + 0.5 * turbulence) + streamers * 0.6)
		+ outer_color * reach * 0.18;
	float alpha = chromosphere * 1.0 + halo * 0.55 + streamers * 0.45 + reach * 0.05;

	if (chromatic_band_enabled) {
		float band = exp(-pow((rim - 0.42) * 9.0, 2.0)) * (0.45 + 0.55 * turbulence);
		color += band_color * band * 0.22;
		alpha += band * 0.10;
	}
	if (god_rays_enabled) {
		float shafts = ray_shafts(angle, rim);
		color += ray_color * shafts * 0.45;
		alpha += shafts * 0.3;
	}
	if (prominences_enabled) {
		float arcs = prominence_arcs(p);
		color += mix(core_color, corona_color, 0.55) * arcs * 0.9;
		alpha += arcs * 0.55;
	}
	if (embers_enabled) {
		float sparks = ember_sparks(angle, rim);
		color += ember_color * sparks * 1.6;
		alpha += sparks * 0.9;
	}

	float pulse = pulse_enabled ? 0.86 + 0.14 * sin(TIME * 0.62) : 1.0;
	float occlude = smoothstep(disk_radius * 0.88, disk_radius * 1.02, radius);
	float fade = 1.0 - smoothstep(0.45, 0.9, radius);
	ALBEDO = color * corona_strength * pulse;
	ALPHA = clamp(alpha * occlude * fade, 0.0, 1.0);
}
