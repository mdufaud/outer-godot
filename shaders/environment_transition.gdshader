shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.55, 0.72, 1.0, 1.0);
uniform float strength = 0.0;

void fragment() {
	float radius = length(SCREEN_UV - vec2(0.5));
	float ring = smoothstep(0.72, 0.18, radius) * smoothstep(0.0, 0.22, radius);
	COLOR = vec4(tint.rgb, ring * strength * 0.24);
}
