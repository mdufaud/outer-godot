shader_type spatial;

uniform vec3 base_color: source_color = vec3(0.62, 0.76, 0.88);
uniform vec3 crack_color: source_color = vec3(0.25, 0.5, 0.75);

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
	v_pos = VERTEX;
}

void fragment() {
	vec3 p = v_pos * 0.1;
	float n = fbm(p);
	// thin crack lines: ridged noise
	float ridge = 1.0 - abs(2.0 * fbm(p * 2.7 + 31.0) - 1.0);
	float crack = smoothstep(0.88, 0.98, ridge);
	vec3 col = mix(base_color, base_color * 1.15, n);
	col = mix(col, crack_color, crack * 0.6);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = col;
	ROUGHNESS = 0.12 + 0.25 * n;
	SPECULAR = 0.7;
	EMISSION = base_color * fresnel * 0.35;
}
