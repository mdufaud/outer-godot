float hash1(float value) {
	return fract(sin(value * 127.1) * 43758.5453);
}

float noise1(float value) {
	float cell = floor(value);
	float blend_value = fract(value);
	blend_value = blend_value * blend_value * (3.0 - 2.0 * blend_value);
	return mix(hash1(cell), hash1(cell + 1.0), blend_value);
}

float hash2(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453);
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

float offset_fbm(vec3 p, int octaves, float lacunarity, float gain, vec3 offset) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < octaves; i++) {
		v += a * value_noise(p);
		p = p * lacunarity + offset;
		a *= gain;
	}
	return v;
}

float fbm(vec3 p, int octaves, float lacunarity) {
	return offset_fbm(p, octaves, lacunarity, 0.5, vec3(0.0));
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

float sin_hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float sin_value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = sin_hash3(i);
	float n100 = sin_hash3(i + vec3(1.0, 0.0, 0.0));
	float n010 = sin_hash3(i + vec3(0.0, 1.0, 0.0));
	float n110 = sin_hash3(i + vec3(1.0, 1.0, 0.0));
	float n001 = sin_hash3(i + vec3(0.0, 0.0, 1.0));
	float n101 = sin_hash3(i + vec3(1.0, 0.0, 1.0));
	float n011 = sin_hash3(i + vec3(0.0, 1.0, 1.0));
	float n111 = sin_hash3(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z
	);
}

float sin_fbm(vec3 p, int octaves, float amplitude, float gain) {
	float value = 0.0;
	for (int octave = 0; octave < octaves; octave++) {
		value += sin_value_noise(p) * amplitude;
		p = p * 2.07 + vec3(11.3, 5.7, 3.1);
		amplitude *= gain;
	}
	return value;
}

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float hash31_value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z
	);
}

vec3 gradient_hash3(vec3 p) {
	p = vec3(
		dot(p, vec3(127.1, 311.7, 74.7)),
		dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6))
	);
	return fract(sin(p) * 43758.5453123) * 2.0 - 1.0;
}

float gradient_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 local = fract(p);
	vec3 weight = local * local * (3.0 - 2.0 * local);
	float result = 0.0;
	for (int x = 0; x < 2; x++) {
		for (int y = 0; y < 2; y++) {
			for (int z = 0; z < 2; z++) {
				vec3 corner = vec3(float(x), float(y), float(z));
				float value = dot(gradient_hash3(cell + corner), local - corner);
				vec3 blend = mix(1.0 - weight, weight, corner);
				result += value * blend.x * blend.y * blend.z;
			}
		}
	}
	return result * 0.5 + 0.5;
}

float gradient_fbm(vec3 p, int octaves, float lacunarity) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < octaves; octave++) {
		sum += gradient_noise(p) * amplitude;
		p *= lacunarity;
		amplitude *= 0.5;
	}
	return sum;
}
