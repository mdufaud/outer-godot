shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform vec3 edge_color: source_color = vec3(0.92, 0.20, 0.03);
uniform vec3 body_color: source_color = vec3(1.0, 0.46, 0.07);
uniform vec3 hot_color: source_color = vec3(1.0, 0.86, 0.46);
uniform vec3 spot_color: source_color = vec3(0.55, 0.10, 0.02);
uniform float emission_strength: hint_range(1.0, 20.0) = 9.0;

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
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_pos = normalize(VERTEX);
}

void fragment() {
	vec3 direction = normalize(v_pos);
	vec3 flow_a = vec3(TIME * 0.035, TIME * 0.018, -TIME * 0.024);
	vec3 flow_b = vec3(-TIME * 0.021, TIME * 0.029, TIME * 0.016);
	float broad = fbm(direction * 3.5 + flow_a);
	float convection = fbm(direction * 15.0 + flow_b + broad * 2.2);
	float filaments = fbm(direction * 32.0 - flow_a * 1.7 + convection * 1.4);
	float heat = clamp(broad * 0.35 + convection * 0.45 + filaments * 0.35, 0.0, 1.0);
	float facing = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
	float limb = pow(facing, 0.55);
	vec3 color = mix(edge_color, body_color, limb);
	float spots = smoothstep(0.58, 0.26, broad) * smoothstep(0.55, 0.3, convection);
	color = mix(color, spot_color, spots * 0.7);
	float cells = smoothstep(0.44, 0.86, heat);
	color = mix(color, hot_color, cells * (0.3 + 0.5 * limb));
	float energy = emission_strength * mix(0.5, 1.7, heat) * mix(0.45, 1.0, limb) * (1.0 - spots * 0.65);
	ALBEDO = color;
	EMISSION = color * energy;
}
