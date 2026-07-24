shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.1, 0.4, 0.5, 1.0);
uniform float distortion = 0.004;
uniform float darkness = 0.45;
uniform float effect_strength = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	uv += vec2(
		sin(uv.y * 22.0 + TIME * 1.4),
		cos(uv.x * 18.0 - TIME * 1.1)) * distortion * effect_strength;
	uv = clamp(uv, vec2(0.001), vec2(0.999));
	float blur_level = effect_strength * 1.35;
	vec3 original = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec3 color = textureLod(screen_texture, uv, blur_level).rgb;
	color = mix(color, color * tint.rgb, 0.55);
	float vignette = smoothstep(1.1, 0.35, length(SCREEN_UV - 0.5));
	color *= mix(1.0 - darkness, 1.0, vignette);
	COLOR = vec4(mix(original, color, effect_strength), 1.0);
}
