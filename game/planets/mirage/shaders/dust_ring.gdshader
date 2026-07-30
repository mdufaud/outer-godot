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


vec3 hash3(vec3 position) {
	position = vec3(
		dot(position, vec3(127.1, 311.7, 74.7)),
		dot(position, vec3(269.5, 183.3, 246.1)),
		dot(position, vec3(113.5, 271.9, 124.6))
	);
	return fract(sin(position) * 43758.5453123) * 2.0 - 1.0;
}


float value_noise(vec3 position) {
	vec3 cell = floor(position);
	vec3 local = fract(position);
	vec3 weight = local * local * (3.0 - 2.0 * local);
	float result = 0.0;
	for (int x = 0; x < 2; x++) {
		for (int y = 0; y < 2; y++) {
			for (int z = 0; z < 2; z++) {
				vec3 corner = vec3(float(x), float(y), float(z));
				float value = dot(hash3(cell + corner), local - corner);
				vec3 blend = mix(1.0 - weight, weight, corner);
				result += value * blend.x * blend.y * blend.z;
			}
		}
	}
	return result * 0.5 + 0.5;
}


float fbm(vec3 position) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int layer = 0; layer < 4; layer++) {
		sum += value_noise(position) * amplitude;
		position *= 2.13;
		amplitude *= 0.5;
	}
	return sum;
}


void vertex() {
	local_position = VERTEX;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	float radius = length(local_position.xz);
	// Soft on both rims so the band has no visible cut edge.
	float band = smoothstep(inner_radius, inner_radius + 14.0, radius)
		* (1.0 - smoothstep(outer_radius - 20.0, outer_radius, radius));
	float angle = atan(local_position.z, local_position.x);
	// Streaks follow the ring: high frequency along the angle, low across it.
	float streaks = fbm(vec3(angle * 5.0, radius * 0.055, 0.0));
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
