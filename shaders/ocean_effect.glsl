#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D source_color;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D destination_color;
layout(set = 0, binding = 2) uniform sampler2D depth_texture;
layout(set = 0, binding = 3) uniform sampler2D wave_normal_a;
layout(set = 0, binding = 4) uniform sampler2D wave_normal_b;
layout(set = 0, binding = 5) uniform sampler2D foam_texture;

struct OceanBody {
	vec4 centre_radius;
	vec4 sun_scale;
	vec4 shallow;
	vec4 deep;
	vec4 specular;
	vec4 ambient;
	vec4 foam_colour;
	vec4 wave;
	vec4 foam;
};

layout(std430, set = 0, binding = 6) restrict readonly buffer OceanBuffer {
	OceanBody data[];
} bodies;

layout(push_constant, std430) uniform Params {
	mat4 inverse_view_projection;
	vec4 camera_position;
	ivec4 screen;
} params;

const float MAX_DISTANCE = 1000000.0;

vec2 ray_sphere(vec3 centre, float radius, vec3 origin, vec3 direction) {
	vec3 offset = origin - centre;
	float b = dot(offset, direction);
	float c = dot(offset, offset) - radius * radius;
	float discriminant = b * b - c;
	if (discriminant < 0.0) {
		return vec2(MAX_DISTANCE, 0.0);
	}
	float root = sqrt(discriminant);
	float near_distance = max(0.0, -b - root);
	float far_distance = -b + root;
	return vec2(near_distance, max(0.0, far_distance - near_distance));
}

float scene_distance(vec2 screen_uv) {
	float depth = texture(depth_texture, screen_uv).r;
	if (depth <= 0.0) {
		return MAX_DISTANCE;
	}
	vec2 ndc = screen_uv * 2.0 - 1.0;
	vec4 world_position = params.inverse_view_projection * vec4(ndc, depth, 1.0);
	return length(world_position.xyz / world_position.w - params.camera_position.xyz);
}

vec3 unpack_normal(vec3 packed_normal) {
	vec3 normal = packed_normal * 2.0 - 1.0;
	normal.z = sqrt(max(1.0 - dot(normal.xy, normal.xy), 0.0));
	return normal;
}

vec3 blend_rnm(vec3 first, vec3 second) {
	first.z += 1.0;
	second.xy = -second.xy;
	return first * dot(first, second) / max(first.z, 0.0001) - second;
}

vec3 triplanar_normal(vec3 position, vec3 surface_normal, float scale, vec2 offset, sampler2D normal_map) {
	vec3 weights = pow(abs(surface_normal), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.0001);
	vec3 normal_x = unpack_normal(texture(normal_map, position.zy * scale + offset).rgb);
	vec3 normal_y = unpack_normal(texture(normal_map, position.xz * scale + offset).rgb);
	vec3 normal_z = unpack_normal(texture(normal_map, position.xy * scale + offset).rgb);
	normal_x = blend_rnm(vec3(surface_normal.zy, abs(surface_normal.x)), normal_x);
	normal_y = blend_rnm(vec3(surface_normal.xz, abs(surface_normal.y)), normal_y);
	normal_z = blend_rnm(vec3(surface_normal.xy, abs(surface_normal.z)), normal_z);
	normal_x.z *= sign(surface_normal.x);
	normal_y.z *= sign(surface_normal.y);
	normal_z.z *= sign(surface_normal.z);
	return normalize(normal_x.zyx * weights.x + normal_y.xzy * weights.y + normal_z.xyz * weights.z);
}

float triplanar_foam(vec3 position, vec3 normal, float scale, vec2 offset) {
	vec3 weights = normal * normal;
	weights /= max(dot(weights, vec3(1.0)), 0.0001);
	float x = texture(foam_texture, position.zy * scale + offset).r;
	float y = texture(foam_texture, position.xz * scale + offset).g;
	float z = texture(foam_texture, position.xy * scale + offset).b;
	return dot(vec3(x, y, z), weights);
}

void main() {
	ivec2 coordinate = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = params.screen.xy;
	if (coordinate.x >= size.x || coordinate.y >= size.y) {
		return;
	}
	vec2 screen_uv = (vec2(coordinate) + 0.5) / vec2(size);
	vec3 source = texture(source_color, screen_uv).rgb;

	OceanBody body = bodies.data[params.screen.z];
	vec3 planet_centre = body.centre_radius.xyz;
	float ocean_radius = body.centre_radius.w;
	vec3 sun_direction = body.sun_scale.xyz;
	float planet_scale = body.sun_scale.w;
	vec3 shallow_colour = body.shallow.rgb;
	float depth_multiplier = body.shallow.w;
	vec3 deep_colour = body.deep.rgb;
	float alpha_multiplier = body.deep.w;
	vec3 specular_colour = body.specular.rgb;
	float smoothness = body.specular.w;
	vec3 ambient_colour = body.ambient.rgb;
	float ambient_strength = body.ambient.w;
	vec3 foam_colour = body.foam_colour.rgb;
	float sky_diffusion = body.foam_colour.w;
	float wave_strength = body.wave.x;
	float wave_scale = body.wave.y;
	float wave_speed = body.wave.z;
	float refraction_strength = body.wave.w;
	float foam_scale = body.foam.x;
	float foam_distance = body.foam.y;
	float time = params.camera_position.w;

	vec2 ndc = screen_uv * 2.0 - 1.0;
	vec4 near_point = params.inverse_view_projection * vec4(ndc, 1.0, 1.0);
	vec3 camera_position = params.camera_position.xyz;
	vec3 ray_direction = normalize(near_point.xyz / near_point.w - camera_position);

	vec2 hit = ray_sphere(planet_centre, ocean_radius, camera_position, ray_direction);
	float ocean_depth = min(hit.y, scene_distance(screen_uv) - hit.x);
	if (ocean_depth <= 0.0) {
		imageStore(destination_color, coordinate, vec4(source, 1.0));
		return;
	}

	// Reference: SebLague OceanEffect rayOceanIntersectPos — always the near hit.
	// Underwater it collapses to the camera itself, which stays continuous across
	// the surface. Swapping to the far hit jumps the shading point to the other
	// side of the planet, past the terminator, and blacks out the sea bed.
	float surface_distance = hit.x;
	vec3 intersection = camera_position + ray_direction * surface_distance - planet_centre;
	// Reference: SebLague dstAboveWater — measured at the near plane, so it is a
	// per-pixel test. A camera-wide bool flips the whole screen at once and makes
	// the image slam when the waterline sits mid-screen.
	float depth_above_water = length(near_point.xyz / near_point.w - planet_centre) - ocean_radius;
	float above_water = smoothstep(-0.01, 0.01, depth_above_water);
	vec3 sphere_normal = normalize(intersection);
	float normal_scale = wave_scale / max(planet_scale, 0.00001);
	float wave_time = time * wave_speed * 0.05;
	vec2 offset_a = vec2(wave_time, wave_time * 0.8);
	vec2 offset_b = vec2(wave_time * -0.8, wave_time * -0.3);
	vec3 normal_a = triplanar_normal(intersection, sphere_normal, normal_scale, offset_a, wave_normal_a);
	vec3 detail_normal = triplanar_normal(intersection, normal_a, normal_scale, offset_b, wave_normal_b);
	vec3 wave_normal = normalize(mix(sphere_normal, detail_normal, clamp(wave_strength, 0.0, 1.0)));
	float depth_blend = 1.0 - exp(-ocean_depth / max(planet_scale, 0.00001) * depth_multiplier);
	float alpha = 1.0 - exp(-ocean_depth / max(planet_scale, 0.00001) * alpha_multiplier);
	vec3 ocean_colour = mix(shallow_colour, deep_colour, depth_blend);
	float diffuse_lighting = max(dot(sphere_normal, normalize(sun_direction)), 0.0);
	float wrapped_light = clamp(dot(wave_normal, normalize(sun_direction)) * 0.35 + 0.65, 0.0, 1.0);
	float cloud_diffusion = 0.72 + 0.28 * sin(dot(sphere_normal, vec3(9.1, 13.7, 7.3)) + time * 0.18);
	vec3 scattered_sky = ambient_colour * ambient_strength * mix(wrapped_light, cloud_diffusion, sky_diffusion);
	float specular_angle = acos(clamp(dot(normalize(normalize(sun_direction) - ray_direction), wave_normal), -1.0, 1.0));
	float specular_exponent = specular_angle / max(1.0 - smoothness, 0.0001);
	float specular_highlight = exp(-specular_exponent * specular_exponent) * above_water;
	vec3 lit_ocean = ocean_colour * diffuse_lighting + scattered_sky + specular_colour * specular_highlight;
	float shore = 1.0 - smoothstep(0.0, max(foam_distance, 0.001), ocean_depth);
	float foam_noise = triplanar_foam(intersection / max(planet_scale, 0.00001), sphere_normal, foam_scale, offset_a * 0.35);
	float leading_edge = smoothstep(0.02, 0.35, ocean_depth / max(foam_distance, 0.001));
	float foam = shore * leading_edge * smoothstep(0.24, 0.78, 1.0 - foam_noise) * above_water;
	lit_ocean = mix(lit_ocean, foam_colour * (0.65 + 0.35 * diffuse_lighting), foam);
	float refraction_fade = shore * (1.0 - smoothstep(0.0, planet_scale * 4.0, surface_distance)) * above_water;
	vec2 refraction_uv = clamp(screen_uv + wave_normal.xy * refraction_strength * refraction_fade, vec2(0.001), vec2(0.999));
	if (scene_distance(refraction_uv) < hit.x) {
		refraction_uv = screen_uv;
	}
	vec3 refracted_scene = texture(source_color, refraction_uv).rgb;
	imageStore(destination_color, coordinate, vec4(mix(refracted_scene, lit_ocean, alpha), 1.0));
}
