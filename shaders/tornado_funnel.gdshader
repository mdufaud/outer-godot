shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 dark_color : source_color = vec3(0.018, 0.035, 0.04);
uniform vec3 mist_color : source_color = vec3(0.32, 0.48, 0.5);
uniform float phase = 0.0;
uniform float layer_offset = 0.0;
uniform float opacity = 0.45;

varying vec3 local_position;

float hash(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 value) {
	vec2 cell = floor(value);
	vec2 blend_value = fract(value);
	blend_value = blend_value * blend_value * (3.0 - 2.0 * blend_value);
	return mix(
		mix(hash(cell), hash(cell + vec2(1.0, 0.0)), blend_value.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), blend_value.x),
		blend_value.y
	);
}

float fbm(vec2 value) {
	float result = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 5; octave++) {
		result += noise(value) * amplitude;
		value = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * value + 3.1;
		amplitude *= 0.52;
	}
	return result;
}

void vertex() {
	local_position = VERTEX;
	float height_fraction = UV.y;
	float angle = TIME * (2.4 + layer_offset) + phase + height_fraction * 10.0;
	vec2 sway = vec2(sin(TIME * 0.72 + height_fraction * 3.8 + phase), cos(TIME * 0.58 + height_fraction * 4.6 + phase));
	VERTEX.xz += vec2(cos(angle), sin(angle)) * (0.16 + height_fraction * 0.52);
	VERTEX.xz += sway * height_fraction * height_fraction * 0.85;
}

void fragment() {
	float angle = atan(local_position.z, local_position.x);
	float spiral = sin(angle * 7.0 - UV.y * 29.0 + TIME * (6.5 + layer_offset) + phase);
	float turbulence = fbm(vec2(angle * 2.2 + TIME * 0.7, UV.y * 12.0 - TIME * 2.1 + layer_offset));
	float gaps = fbm(vec2(angle * 5.0 - TIME * 1.3, UV.y * 23.0 + phase));
	float density = smoothstep(0.28, 0.86, turbulence + spiral * 0.23 - gaps * 0.2);
	float edge_fade = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.82, 1.0, UV.y));
	float inner_shadow = smoothstep(0.0, 0.7, abs(sin(angle + TIME * 2.0 + phase)));
	ALBEDO = mix(dark_color * (0.55 + inner_shadow * 0.35), mist_color, density);
	EMISSION = mist_color * density * 0.055;
	ALPHA = (0.08 + density * opacity) * edge_fade;
}
