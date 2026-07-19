shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D baked_optical_depth : filter_linear, repeat_disable;

uniform vec3 planet_center = vec3(0.0);
uniform float planet_radius = 46.0;
uniform float atmosphere_radius = 60.812;
uniform vec3 sun_direction = vec3(-1.0, 0.0, 0.0);
uniform int in_scattering_points = 10;
uniform vec3 scattering_coefficients = vec3(2.26359, 6.88789, 12.1383);
uniform float intensity = 1.0;
uniform float density_falloff = 4.3;

const float MAX_DISTANCE = 3.402823466e+38;

vec2 ray_sphere(vec3 center, float radius, vec3 origin, vec3 direction) {
	vec3 offset = origin - center;
	float b = 2.0 * dot(offset, direction);
	float c = dot(offset, offset) - radius * radius;
	float discriminant = b * b - 4.0 * c;
	if (discriminant > 0.0) {
		float root = sqrt(discriminant);
		float near_distance = max(0.0, (-b - root) * 0.5);
		float far_distance = (-b + root) * 0.5;
		if (far_distance >= 0.0) {
			return vec2(near_distance, far_distance - near_distance);
		}
	}
	return vec2(MAX_DISTANCE, 0.0);
}

float density_at(vec3 point) {
	float height = length(point - planet_center) - planet_radius;
	float height_fraction = height / (atmosphere_radius - planet_radius);
	return exp(-height_fraction * density_falloff) * (1.0 - height_fraction);
}

float optical_depth_baked(vec3 origin, vec3 direction) {
	float height = length(origin - planet_center) - planet_radius;
	float height_fraction = clamp(height / (atmosphere_radius - planet_radius), 0.0, 1.0);
	float u = 1.0 - (dot(normalize(origin - planet_center), direction) * 0.5 + 0.5);
	return texture(baked_optical_depth, vec2(u, height_fraction)).r;
}

float optical_depth_between(vec3 origin, vec3 direction, float ray_length) {
	vec3 end_point = origin + direction * ray_length;
	float alignment = dot(direction, normalize(origin - planet_center));
	float blend_weight = clamp(alignment * 1.5 + 0.5, 0.0, 1.0);
	float forward_depth = optical_depth_baked(origin, direction) - optical_depth_baked(end_point, direction);
	float backward_depth = optical_depth_baked(end_point, -direction) - optical_depth_baked(origin, -direction);
	return mix(backward_depth, forward_depth, blend_weight);
}

vec3 calculate_light(vec3 origin, vec3 direction, float ray_length, vec3 original_color, int sample_count) {
	vec3 point = origin;
	float step_size = ray_length / float(sample_count - 1);
	vec3 in_scattered_light = vec3(0.0);
	float view_ray_optical_depth = 0.0;
	for (int index = 0; index < in_scattering_points; index++) {
		if (index >= sample_count) {
			break;
		}
		float sun_optical_depth = optical_depth_baked(point, sun_direction);
		float local_density = density_at(point);
		view_ray_optical_depth = optical_depth_between(origin, direction, step_size * float(index));
		vec3 transmittance = exp(-(sun_optical_depth + view_ray_optical_depth) * scattering_coefficients);
		in_scattered_light += local_density * transmittance;
		point += direction * step_size;
	}
	in_scattered_light *= scattering_coefficients * intensity * step_size / planet_radius;
	const float brightness_adaptation_strength = 0.15;
	const float reflected_light_out_scatter_strength = 3.0;
	float brightness_adaptation = dot(in_scattered_light, vec3(1.0)) * brightness_adaptation_strength;
	float brightness_sum = view_ray_optical_depth * intensity * reflected_light_out_scatter_strength + brightness_adaptation;
	float reflected_light_strength = exp(-brightness_sum);
	float hdr_strength = clamp(dot(original_color, vec3(1.0)) / 3.0 - 1.0, 0.0, 1.0);
	reflected_light_strength = mix(reflected_light_strength, 1.0, hdr_strength);
	return original_color * reflected_light_strength + in_scattered_light;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 original_color = texture(screen_texture, SCREEN_UV).rgb;
	vec2 ndc = SCREEN_UV * 2.0 - 1.0;
	vec4 view_far = INV_PROJECTION_MATRIX * vec4(ndc, 1.0, 1.0);
	vec3 view_ray = view_far.xyz / view_far.w;
	vec3 ray_direction = normalize((INV_VIEW_MATRIX * vec4(view_ray, 0.0)).xyz);
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	float scene_distance = MAX_DISTANCE;
	if (raw_depth > 0.0) {
		vec4 view_position = INV_PROJECTION_MATRIX * vec4(ndc, raw_depth, 1.0);
		scene_distance = length(view_position.xyz / view_position.w);
	}
	ALPHA = 1.0;
	vec2 atmosphere_hit = ray_sphere(planet_center, atmosphere_radius, CAMERA_POSITION_WORLD, ray_direction);
	float ray_length = min(atmosphere_hit.y, scene_distance - atmosphere_hit.x);
	if (ray_length > 0.0) {
		const float epsilon = 0.0001;
		vec3 ray_origin = CAMERA_POSITION_WORLD + ray_direction * (atmosphere_hit.x + epsilon);
		ALBEDO = calculate_light(ray_origin, ray_direction, ray_length - epsilon * 2.0, original_color, in_scattering_points);
	} else {
		ALBEDO = original_color;
	}
}
