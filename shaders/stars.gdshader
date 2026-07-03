shader_type sky;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 dir = EYEDIR;
	float density = 220.0;
	vec3 cell = floor(dir * density);
	float h = hash3(cell);
	vec3 col = vec3(0.008, 0.008, 0.02);
	if (h > 0.997) {
		vec3 in_cell = fract(dir * density) - 0.5;
		float d = length(in_cell);
		float brightness = smoothstep(0.35, 0.0, d) * (0.4 + 0.6 * hash3(cell + 7.0));
		float tint = hash3(cell + 13.0);
		vec3 star_col = mix(vec3(0.8, 0.9, 1.0), vec3(1.0, 0.85, 0.7), tint);
		col += star_col * brightness;
	}
	COLOR = col;
}
