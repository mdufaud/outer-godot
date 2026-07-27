#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D source_color;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D destination_color;
layout(set = 0, binding = 2) uniform sampler2D depth_texture;
layout(set = 0, binding = 3) uniform sampler2D blue_noise;

struct AtmosphereBody {
	vec4 centre_radius;
	vec4 shell;
	vec4 sun_dither;
	vec4 scattering;
	vec4 colour_ocean;
};

layout(std430, set = 0, binding = 4) restrict readonly buffer AtmosphereBuffer {
	AtmosphereBody data[];
} bodies;

layout(set = 1, binding = 0) uniform sampler2D baked_optical_depth;

layout(push_constant, std430) uniform Params {
	mat4 inverse_view_projection;
	vec4 camera_position;
	ivec4 screen;
} params;

const float MAX_DISTANCE = 3.402823466e+38;

vec3 planet_centre;
float planet_radius;
float atmosphere_radius;
vec3 sun_direction;
vec3 scattering_coefficients;
vec3 atmosphere_colour;
float intensity;
float density_falloff;
int in_scattering_points;

vec2 ray_sphere(vec3 centre, float radius, vec3 origin, vec3 direction) {
	vec3 offset = origin - centre;
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
	float height = length(point - planet_centre) - planet_radius;
	float height_fraction = height / (atmosphere_radius - planet_radius);
	return exp(-height_fraction * density_falloff) * (1.0 - height_fraction);
}

float optical_depth_baked(vec3 origin, vec3 direction) {
	float height = length(origin - planet_centre) - planet_radius;
	float height_fraction = clamp(height / (atmosphere_radius - planet_radius), 0.0, 1.0);
	float u = 1.0 - (dot(normalize(origin - planet_centre), direction) * 0.5 + 0.5);
	return texture(baked_optical_depth, vec2(u, height_fraction)).r;
}

float optical_depth_between(vec3 origin, vec3 direction, float ray_length) {
	vec3 end_point = origin + direction * ray_length;
	float alignment = dot(direction, normalize(origin - planet_centre));
	float blend_weight = clamp(alignment * 1.5 + 0.5, 0.0, 1.0);
	float forward_depth = optical_depth_baked(origin, direction) - optical_depth_baked(end_point, direction);
	float backward_depth = optical_depth_baked(end_point, -direction) - optical_depth_baked(origin, -direction);
	return mix(backward_depth, forward_depth, blend_weight);
}

vec3 calculate_light(vec3 origin, vec3 direction, float ray_length, vec3 original_colour, int sample_count, float jitter) {
	float step_size = ray_length / float(sample_count - 1);
	vec3 point = origin + direction * step_size * jitter;
	vec3 in_scattered_light = vec3(0.0);
	float view_ray_optical_depth = 0.0;
	for (int index = 0; index < sample_count; index++) {
		float sun_optical_depth = optical_depth_baked(point, sun_direction);
		float local_density = density_at(point);
		view_ray_optical_depth = optical_depth_between(origin, direction, step_size * float(index));
		vec3 transmittance = exp(-(sun_optical_depth + view_ray_optical_depth) * scattering_coefficients);
		in_scattered_light += local_density * transmittance;
		point += direction * step_size;
	}
	in_scattered_light *= scattering_coefficients * intensity * step_size / planet_radius;
	in_scattered_light *= atmosphere_colour;
	const float brightness_adaptation_strength = 0.15;
	const float reflected_light_out_scatter_strength = 3.0;
	float brightness_adaptation = dot(in_scattered_light, vec3(1.0)) * brightness_adaptation_strength;
	float brightness_sum = view_ray_optical_depth * intensity * reflected_light_out_scatter_strength + brightness_adaptation;
	float reflected_light_strength = exp(-brightness_sum);
	float hdr_strength = clamp(dot(original_colour, vec3(1.0)) / 3.0 - 1.0, 0.0, 1.0);
	reflected_light_strength = mix(reflected_light_strength, 1.0, hdr_strength);
	return original_colour * reflected_light_strength + in_scattered_light;
}

void main() {
	ivec2 coordinate = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = params.screen.xy;
	if (coordinate.x >= size.x || coordinate.y >= size.y) {
		return;
	}
	vec2 screen_uv = (vec2(coordinate) + 0.5) / vec2(size);
	vec3 original_colour = texture(source_color, screen_uv).rgb;

	AtmosphereBody body = bodies.data[params.screen.z];
	planet_centre = body.centre_radius.xyz;
	planet_radius = body.centre_radius.w;
	atmosphere_radius = body.shell.x;
	density_falloff = body.shell.y;
	intensity = body.shell.z;
	float dither_strength = body.shell.w;
	sun_direction = body.sun_dither.xyz;
	float dither_scale = body.sun_dither.w;
	scattering_coefficients = body.scattering.rgb;
	in_scattering_points = int(body.scattering.w);
	atmosphere_colour = body.colour_ocean.rgb;
	float ocean_radius = body.colour_ocean.w;
	vec3 camera_position = params.camera_position.xyz;
	vec2 ndc = screen_uv * 2.0 - 1.0;
	vec4 near_point = params.inverse_view_projection * vec4(ndc, 1.0, 1.0);
	vec3 ray_direction = normalize(near_point.xyz / near_point.w - camera_position);

	float raw_depth = texture(depth_texture, screen_uv).r;
	float scene_distance = MAX_DISTANCE;
	if (raw_depth > 0.0) {
		vec4 world_position = params.inverse_view_projection * vec4(ndc, raw_depth, 1.0);
		scene_distance = length(world_position.xyz / world_position.w - camera_position);
	}

	if (ocean_radius > 0.0) {
		vec2 ocean_hit = ray_sphere(planet_centre, ocean_radius, camera_position, ray_direction);
		scene_distance = min(scene_distance, ocean_hit.x);
	}

	vec3 result = original_colour;
	vec2 atmosphere_hit = ray_sphere(planet_centre, atmosphere_radius, camera_position, ray_direction);
	float ray_start = atmosphere_hit.x;
	float ray_length = min(atmosphere_hit.x + atmosphere_hit.y, scene_distance) - ray_start;
	if (ray_length > 0.0) {
		const float epsilon = 0.0001;
		vec3 ray_origin = camera_position + ray_direction * (ray_start + epsilon);
		float jitter = texture(blue_noise, screen_uv * dither_scale).r;
		result = calculate_light(ray_origin, ray_direction, ray_length - epsilon * 2.0, original_colour, in_scattering_points, jitter * dither_strength);
	}
	imageStore(destination_color, coordinate, vec4(result, 1.0));
}
