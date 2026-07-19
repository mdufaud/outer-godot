shader_type spatial;

uniform vec3 deep_color: source_color = vec3(0.05, 0.25, 0.3);
uniform vec3 band_color: source_color = vec3(0.15, 0.55, 0.55);
uniform vec3 storm_color: source_color = vec3(0.85, 0.95, 0.95);
uniform float swirl_speed = 0.06;

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
	vec3 d = normalize(v_pos);
	float lat = d.y;
	// rotate longitude over time, faster near equator (differential rotation)
	float speed = swirl_speed * (1.4 - 0.8 * abs(lat));
	float ang = atan(d.z, d.x) + TIME * speed;
	vec3 sp = vec3(cos(ang) * sqrt(1.0 - lat * lat), lat, sin(ang) * sqrt(1.0 - lat * lat));
	// wavy latitude bands distorted by noise
	float distort = fbm(sp * 3.0 + vec3(0.0, TIME * 0.02, 0.0));
	float bands = sin(lat * 14.0 + distort * 5.0);
	float clouds = fbm(sp * 5.0 + vec3(TIME * 0.03, 0.0, 0.0));
	vec3 col = mix(deep_color, band_color, 0.5 + 0.5 * bands);
	float storm = smoothstep(0.62, 0.8, clouds);
	col = mix(col, storm_color, storm * 0.8);
	ALBEDO = col;
	ROUGHNESS = 0.85;
	EMISSION = storm_color * storm * 0.08;
}
