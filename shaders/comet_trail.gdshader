shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 head_color : source_color = vec3(0.78, 0.97, 1.0);
uniform vec3 tail_color : source_color = vec3(0.13, 0.40, 0.80);
uniform float intensity = 2.3;
uniform float flicker_speed = 0.9;
uniform float edge_softness = 1.6;
uniform float streak_count = 9.0;
uniform float streak_contrast = 0.85;
uniform float core_width = 0.35;

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash1(i);
	float b = hash1(i + vec2(1.0, 0.0));
	float c = hash1(i + vec2(0.0, 1.0));
	float d = hash1(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return sum;
}

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float along = clamp(UV.x, 0.0, 1.0);
	float halo = pow(clamp(1.0 - across, 0.0, 1.0), edge_softness);
	float core = pow(clamp(1.0 - across / core_width, 0.0, 1.0), 2.0);
	// Lengthwise filaments: noise sampled fine across the plume and coarse along
	// it, so it breaks into flame streamers instead of a smooth cone.
	float streaks = fbm(vec2(UV.y * streak_count, along * 1.6 - TIME * flicker_speed));
	// Each streamer reaches a different distance, which gives the ragged tip.
	float reach = mix(0.45, 1.15, streaks);
	float body = smoothstep(reach, reach - 0.55, along);
	float flame = mix(1.0, smoothstep(0.25, 0.75, streaks), streak_contrast);
	vec3 color = mix(head_color, tail_color, sqrt(along));
	ALBEDO = color;
	ALPHA = (halo * flame * body + core * (1.0 - along * 0.6)) * COLOR.a * intensity;
}
