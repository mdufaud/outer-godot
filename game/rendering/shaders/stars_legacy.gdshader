shader_type sky;

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

vec3 star_layer(vec3 dir, float density, float rate, float max_bright, float twinkle_amt) {
	vec3 cell = floor(dir * density);
	float h = hash3(cell);
	if (h < 1.0 - rate) {
		return vec3(0.0);
	}
	// star center jittered inside cell so grid never shows
	vec3 center = (cell + 0.5 + (vec3(
		hash3(cell + 3.0),
		hash3(cell + 5.0),
		hash3(cell + 9.0)) - 0.5) * 0.7) / density;
	float d = length(normalize(center) - dir) * density;
	float core = smoothstep(0.35, 0.0, d);
	float halo = smoothstep(0.9, 0.0, d) * 0.15;
	float mag = pow(hash3(cell + 7.0), 2.0) * max_bright;
	float twinkle = 1.0 - twinkle_amt * 0.5 * (1.0 + sin(TIME * (1.0 + hash3(cell + 11.0) * 3.0) + hash3(cell) * 40.0));
	float temp = hash3(cell + 13.0);
	vec3 star_col = mix(vec3(0.65, 0.8, 1.0), vec3(1.0, 0.82, 0.6), temp);
	if (temp > 0.94) {
		star_col = vec3(1.0, 0.55, 0.45);
	}
	return star_col * (core + halo) * mag * twinkle;
}

void sky() {
	vec3 dir = EYEDIR;

	// deep space base
	vec3 col = vec3(0.004, 0.005, 0.012);

	// faint nebula clouds, two hues
	float neb1 = fbm(dir * 3.0 + 17.0);
	float neb2 = fbm(dir * 5.0 - 42.0);
	col += vec3(0.10, 0.05, 0.18) * pow(neb1, 3.0) * 0.9;
	col += vec3(0.03, 0.10, 0.16) * pow(neb2, 3.5) * 0.7;

	// milky-way-like band: denser glow near an arbitrary great circle
	float band = 1.0 - abs(dot(dir, normalize(vec3(0.3, 1.0, 0.2))));
	float band_glow = pow(band, 6.0) * fbm(dir * 8.0 + 5.0);
	col += vec3(0.09, 0.09, 0.13) * band_glow;

	// three star layers: many faint, medium, few bright twinkling
	col += star_layer(dir, 420.0, 0.06, 0.5, 0.0);
	col += star_layer(dir, 180.0, 0.02, 1.1, 0.25);
	col += star_layer(dir, 70.0, 0.008, 2.2, 0.45);

	COLOR = col;
}
