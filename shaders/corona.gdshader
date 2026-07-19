shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 corona_color: source_color = vec3(1.0, 0.7, 0.16);
uniform float corona_strength: hint_range(0.0, 8.0) = 4.0;

void vertex() {
	vec3 center_view = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	POSITION = PROJECTION_MATRIX * vec4(center_view + vec3(VERTEX.xy, 0.0), 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float flicker = sin(angle * 11.0 + TIME * 0.7) * 0.5 + sin(angle * 23.0 - TIME * 1.1) * 0.25;
	float irregular_edge = 0.565 + flicker * 0.012;
	float inner_halo = exp(-max(radius - irregular_edge, 0.0) * 16.0) * smoothstep(0.51, irregular_edge, radius);
	float outer_halo = exp(-max(radius - 0.58, 0.0) * 6.5) * smoothstep(0.48, 0.59, radius);
	float rays = exp(-max(radius - 0.57, 0.0) * 3.5) * max(flicker, 0.0) * 0.18;
	float edge_fade = 1.0 - smoothstep(0.82, 1.0, radius);
	float alpha = clamp((inner_halo + outer_halo * 0.3 + rays) * edge_fade, 0.0, 1.0);
	ALBEDO = corona_color * corona_strength;
	ALPHA = alpha;
}
