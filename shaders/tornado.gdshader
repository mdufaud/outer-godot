shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 deep_color: source_color = vec3(0.008, 0.026, 0.032);
uniform vec3 band_color: source_color = vec3(0.035, 0.13, 0.15);
uniform vec3 storm_color: source_color = vec3(0.22, 0.52, 0.55);
uniform vec3 highlight_color: source_color = vec3(0.63, 0.9, 0.88);
uniform float swirl_speed = 0.018;

varying vec3 v_pos;

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
	for (int i = 0; i < 5; i++) {
		v += a * value_noise(p);
		p = p * 2.05 + vec3(17.0, -11.0, 7.0);
		a *= 0.48;
	}
	return v;
}

float ridged_fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		float n = 1.0 - abs(value_noise(p) * 2.0 - 1.0);
		v += n * n * a;
		p = p * 2.18 + vec3(-9.0, 13.0, 5.0);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_pos = normalize(VERTEX);
}

void fragment() {
	vec3 direction = normalize(v_pos);
	float time = TIME * swirl_speed;
	vec3 flow = direction;
	flow.x += sin(direction.y * 7.0 + direction.z * 3.0 + time * 5.0) * 0.12;
	flow.y += sin(direction.x * 5.0 - direction.z * 4.0 - time * 3.0) * 0.08;
	flow.z += cos(direction.y * 6.0 - direction.x * 3.0 + time * 4.0) * 0.12;
	flow = normalize(flow);

	float broad_noise = fbm(flow * 3.4 + vec3(time * 2.0, -time, time * 0.7));
	float fine_noise = fbm(flow * 10.0 + vec3(-time * 3.0, time * 1.7, time * 2.2));
	float ridge_noise = ridged_fbm(flow * 16.0 + vec3(time * 4.0, -time * 2.0, time));
	vec3 band_axis = normalize(vec3(0.36, 0.91, -0.2));
	float band_coordinate = dot(flow, band_axis) + (broad_noise - 0.5) * 0.24;
	float bands = 0.5 + 0.5 * sin(band_coordinate * 33.0 + fine_noise * 4.0);
	float broad_bands = smoothstep(0.14, 0.86, bands);
	float narrow_streaks = pow(max(bands, 0.0), 9.0) * smoothstep(0.28, 0.78, ridge_noise + broad_noise * 0.35);
	float dark_gaps = smoothstep(0.52, 0.9, 1.0 - bands) * (0.35 + fine_noise * 0.65);
	float storm_cells = smoothstep(0.52, 0.82, fine_noise + ridge_noise * 0.22);

	vec3 col = mix(deep_color, band_color, broad_bands * 0.86);
	col = mix(col, storm_color, storm_cells * 0.5);
	col += highlight_color * narrow_streaks * 0.9;
	col *= 1.0 - dark_gaps * 0.34;

	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float limb = smoothstep(0.0, 0.68, facing);
	float light_wrap = clamp(dot(direction, normalize(vec3(-0.55, 0.38, 0.74))) * 0.5 + 0.5, 0.0, 1.0);
	col *= mix(0.38, 1.0, limb) * mix(0.72, 1.08, light_wrap);
	col += storm_color * pow(1.0 - limb, 2.5) * 0.12;

	ALBEDO = col;
	EMISSION = col * 0.035 + highlight_color * narrow_streaks * 0.05;
}
