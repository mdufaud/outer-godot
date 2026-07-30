shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 spray_color : source_color = vec3(0.3, 0.72, 0.7);
uniform float phase = 0.0;

varying float spray_noise;

float hash(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	float angle = atan(VERTEX.z, VERTEX.x);
	float wave = sin(angle * 9.0 - TIME * 7.0 + phase);
	float breakup = hash(vec2(floor(angle * 18.0), floor(TIME * 9.0 + phase)));
	VERTEX.xz *= 1.0 + wave * 0.08 + breakup * 0.05;
	VERTEX.y += sin(angle * 13.0 + TIME * 5.0 + phase) * 0.22;
	spray_noise = wave * 0.5 + breakup * 0.5;
}

void fragment() {
	float streak = smoothstep(-0.25, 0.75, spray_noise);
	ALBEDO = spray_color * streak;
	EMISSION = spray_color * streak * 0.7;
	ALPHA = streak * 0.34;
}
