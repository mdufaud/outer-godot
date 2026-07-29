shader_type sky;

uniform vec3 camera_position = vec3(0.0);
uniform vec3 sun_direction = vec3(1.0, 0.0, 0.0);
uniform float daylight = 0.0;
uniform float underwater_strength = 0.0;
uniform int ocean_count = 0;
uniform vec4 ocean_spheres[8];
uniform bool sun_glow_enabled = true;
uniform bool sun_pulse_enabled = true;
uniform float sun_glow_strength: hint_range(0.0, 1.0) = 1.0;
uniform vec3 sun_glow_color: source_color = vec3(1.0, 0.45, 0.12);
uniform vec3 sun_glow_outer_color: source_color = vec3(0.62, 0.10, 0.34);

bool ray_hits_sphere(vec3 origin, vec3 direction, vec4 sphere) {
	vec3 offset = origin - sphere.xyz;
	float b = dot(offset, direction);
	float c = dot(offset, offset) - sphere.w * sphere.w;
	float discriminant = b * b - c;
	if (discriminant < 0.0) {
		return false;
	}
	float root = sqrt(discriminant);
	return -b + root > 0.0 && max(-b - root, 0.0) < 1000000.0;
}

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

vec3 star_layer(vec3 dir, float density, float rate, float max_bright, float halo_strength, float twinkle_amt) {
	vec3 cell = floor(dir * density);
	float h = hash3(cell);
	if (h < 1.0 - rate) {
		return vec3(0.0);
	}
	vec3 center = (cell + 0.5 + (vec3(
		hash3(cell + 3.0),
		hash3(cell + 5.0),
		hash3(cell + 9.0)) - 0.5) * 0.7) / density;
	float d = length(normalize(center) - dir) * density;
	float core = smoothstep(0.24, 0.0, d);
	float halo = smoothstep(0.62, 0.0, d) * halo_strength;
	float mag = (0.2 + 0.8 * pow(hash3(cell + 7.0), 3.0)) * max_bright;
	float twinkle = 1.0 - twinkle_amt * 0.5 * (1.0 + sin(TIME * (1.0 + hash3(cell + 11.0) * 3.0) + hash3(cell) * 40.0));
	float temp = hash3(cell + 13.0);
	vec3 star_col = mix(vec3(0.72, 0.84, 1.0), vec3(1.0, 0.88, 0.7), temp);
	return star_col * (core + halo) * mag * twinkle;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 col = vec3(0.002, 0.004, 0.009);
	float haze = smoothstep(0.42, 0.82, fbm(dir * 2.4 + 17.0));
	col += vec3(0.008, 0.012, 0.022) * haze;
	vec3 stars = star_layer(dir, 360.0, 0.035, 0.18, 0.015, 0.0);
	stars += star_layer(dir, 150.0, 0.018, 0.32, 0.025, 0.04);
	stars += star_layer(dir, 62.0, 0.009, 0.58, 0.04, 0.08);
	float ocean_mask = 1.0;
	for (int index = 0; index < 8; index++) {
		if (index >= ocean_count) {
			break;
		}
		if (ray_hits_sphere(camera_position, dir, ocean_spheres[index])) {
			ocean_mask = 0.0;
		}
	}
	float sun_fade = 1.0 - smoothstep(0.65, 0.995, dot(dir, normalize(sun_direction)));
	stars *= ocean_mask * sun_fade * (1.0 - daylight * 0.96) * (1.0 - underwater_strength);
	col += stars;

	if (sun_glow_enabled) {
		float sun_dot = max(dot(dir, normalize(sun_direction)), 0.0);
		float pulse = sun_pulse_enabled ? 0.86 + 0.14 * sin(TIME * 0.62) : 1.0;
		vec3 glow = sun_glow_color * pow(sun_dot, 260.0) * 2.4
			+ sun_glow_color * pow(sun_dot, 42.0) * 0.30
			+ sun_glow_outer_color * pow(sun_dot, 9.0) * 0.05;
		col += glow * pulse * sun_glow_strength * ocean_mask * (1.0 - underwater_strength);
	}

	COLOR = col;
}
