shader_type spatial;

uniform vec3 base_color: source_color = vec3(0.1, 0.08, 0.07);
uniform vec3 glow_color: source_color = vec3(1.0, 0.4, 0.05);

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
	vec3 p = v_pos * 0.12;
	float crust = fbm(p + vec3(0.0, TIME * 0.02, 0.0));
	float cracks = fbm(p * 2.3 + vec3(TIME * 0.05, 0.0, TIME * 0.03));
	// crust high -> dark basalt; low -> molten
	float molten = smoothstep(0.55, 0.35, crust);
	float vein = smoothstep(0.45, 0.65, cracks) * molten;
	float pulse = 0.8 + 0.2 * sin(TIME * 1.5 + crust * 10.0);
	vec3 rock = base_color * (0.7 + 0.6 * crust);
	vec3 col = mix(rock, glow_color, vein);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.4, vein);
	EMISSION = glow_color * vein * 2.5 * pulse + glow_color * molten * 0.15;
}
