shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.55, 0.72, 1.0, 1.0);
uniform float strength = 0.0;
uniform float cloud_strength = 0.0;

void fragment() {
	float radius = length(SCREEN_UV - vec2(0.5));
	float ring = smoothstep(0.72, 0.18, radius) * smoothstep(0.0, 0.22, radius);
	float cloud_alpha = cloud_strength;
	vec3 cloud_color = vec3(0.28, 0.46, 0.42);
	float transition_alpha = ring * strength * 0.24;
	float combined_alpha = 1.0 - (1.0 - transition_alpha) * (1.0 - cloud_alpha);
	vec3 combined_color = mix(tint.rgb, cloud_color, clamp(cloud_alpha * 2.0, 0.0, 1.0));
	COLOR = vec4(combined_color, combined_alpha);
}
