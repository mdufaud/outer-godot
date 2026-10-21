shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 dust_color : source_color = vec3(0.62, 0.52, 0.38);
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
// 0 far away (solid band) to 1 up close, where the rocks take over.
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float inner_radius = 78.0;
uniform float outer_radius = 132.0;
uniform float brightness = 0.55;

varying vec3 local_position;
varying vec3 world_position;
varying vec3 world_normal;


#include "res://game/shared/shaders/noise.gdshaderinc"


void vertex() {
	local_position = VERTEX;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}


void fragment() {
	float radius = length(local_position.xz);
	// Soft on both rims so the band has no visible cut edge.
	float band = smoothstep(inner_radius, inner_radius + 14.0, radius)
		* (1.0 - smoothstep(outer_radius - 20.0, outer_radius, radius));
	vec2 around = normalize(local_position.xz) * 5.0;
	// Streaks follow the ring: high frequency along the angle, low across it.
	float streaks = gradient_fbm(vec3(around.x, radius * 0.055, around.y), 4, 2.13);
	streaks = mix(0.45, 1.35, streaks);
	// Dust lights up when the camera looks through it towards the sun.
	vec3 to_camera = normalize(CAMERA_POSITION_WORLD - world_position);
	float backlit = 1.0 + pow(max(dot(-to_camera, normalize(sun_direction)), 0.0), 6.0) * 1.6;
	// Grazing angles cross more dust, so the band thickens when seen edge on.
	float grazing = 1.0 - abs(dot(world_normal, to_camera));
	float thickness = mix(1.0, 2.6, grazing);
	float density = band * streaks * backlit * thickness * brightness * (1.0 - dissolve);
	ALBEDO = dust_color;
	ALPHA = clamp(density, 0.0, 1.0);
}
