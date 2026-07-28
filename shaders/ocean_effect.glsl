#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D source_color;
layout(rgba16f, set = 0, binding = 1) uniform restrict writeonly image2D destination_color;
layout(set = 0, binding = 2) uniform sampler2D depth_texture;
layout(set = 0, binding = 3) uniform sampler2D wave_normal_a;
layout(set = 0, binding = 4) uniform sampler2D wave_normal_b;
layout(set = 0, binding = 5) uniform sampler2D foam_texture;
layout(set = 0, binding = 7) uniform sampler2D caustic_texture;

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
	vec4 underwater;
	vec4 storm_contacts[9];
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

vec3 triplanar_normal(vec3 position, vec3 surface_normal, float scale, vec2 offset, float lod, sampler2D normal_map) {
	vec3 weights = pow(abs(surface_normal), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.0001);
	vec3 normal_x = unpack_normal(textureLod(normal_map, position.zy * scale + offset, lod).rgb);
	vec3 normal_y = unpack_normal(textureLod(normal_map, position.xz * scale + offset, lod).rgb);
	vec3 normal_z = unpack_normal(textureLod(normal_map, position.xy * scale + offset, lod).rgb);
	normal_x = blend_rnm(vec3(surface_normal.zy, abs(surface_normal.x)), normal_x);
	normal_y = blend_rnm(vec3(surface_normal.xz, abs(surface_normal.y)), normal_y);
	normal_z = blend_rnm(vec3(surface_normal.xy, abs(surface_normal.z)), normal_z);
	normal_x.z *= sign(surface_normal.x);
	normal_y.z *= sign(surface_normal.y);
	normal_z.z *= sign(surface_normal.z);
	return normalize(normal_x.zyx * weights.x + normal_y.xzy * weights.y + normal_z.xyz * weights.z);
}

float triplanar_foam(vec3 position, vec3 normal, float scale, vec2 offset, float lod) {
	vec3 weights = normal * normal;
	weights /= max(dot(weights, vec3(1.0)), 0.0001);
	float x = textureLod(foam_texture, position.zy * scale + offset, lod).r;
	float y = textureLod(foam_texture, position.xz * scale + offset, lod).g;
	float z = textureLod(foam_texture, position.xy * scale + offset, lod).b;
	return dot(vec3(x, y, z), weights);
}

float directional_caustic(vec3 position, vec3 normal, vec3 light_direction, float scale, vec2 offset, float lod) {
	vec3 tangent = light_direction - normal * dot(light_direction, normal);
	if (dot(tangent, tangent) < 0.0001) {
		tangent = cross(normal, vec3(0.0, 1.0, 0.0));
		if (dot(tangent, tangent) < 0.0001) {
			tangent = cross(normal, vec3(1.0, 0.0, 0.0));
		}
	}
	tangent = normalize(tangent);
	vec3 bitangent = normalize(cross(normal, tangent));
	vec2 uv = vec2(dot(position, tangent), dot(position, bitangent)) * scale + offset;
	return textureLod(caustic_texture, uv, lod).r;
}

vec3 ray_direction_at(vec2 screen_uv, vec3 camera_position) {
	vec2 ndc = screen_uv * 2.0 - 1.0;
	vec4 near_point = params.inverse_view_projection * vec4(ndc, 1.0, 1.0);
	return normalize(near_point.xyz / near_point.w - camera_position);
}

float texture_lod(float world_footprint, float coordinate_scale, sampler2D sampled_texture) {
	float texel_footprint = world_footprint * coordinate_scale * float(textureSize(sampled_texture, 0).x) * 2.0;
	float maximum_lod = float(max(textureQueryLevels(sampled_texture) - 1, 0));
	return clamp(log2(max(texel_footprint, 1.0)), 0.0, maximum_lod);
}

vec3 sample_blurred_scene(vec2 uv, vec2 pixel_size, float radius) {
	vec2 horizontal = vec2(pixel_size.x * radius, 0.0);
	vec2 vertical = vec2(0.0, pixel_size.y * radius);
	vec3 colour = texture(source_color, uv).rgb * 0.2;
	colour += texture(source_color, clamp(uv + horizontal, vec2(0.001), vec2(0.999))).rgb * 0.12;
	colour += texture(source_color, clamp(uv - horizontal, vec2(0.001), vec2(0.999))).rgb * 0.12;
	colour += texture(source_color, clamp(uv + vertical, vec2(0.001), vec2(0.999))).rgb * 0.12;
	colour += texture(source_color, clamp(uv - vertical, vec2(0.001), vec2(0.999))).rgb * 0.12;
	colour += texture(source_color, clamp(uv + horizontal + vertical, vec2(0.001), vec2(0.999))).rgb * 0.08;
	colour += texture(source_color, clamp(uv + horizontal - vertical, vec2(0.001), vec2(0.999))).rgb * 0.08;
	colour += texture(source_color, clamp(uv - horizontal + vertical, vec2(0.001), vec2(0.999))).rgb * 0.08;
	colour += texture(source_color, clamp(uv - horizontal - vertical, vec2(0.001), vec2(0.999))).rgb * 0.08;
	return colour;
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
	float exterior_murk = body.foam.z;
	vec3 underwater_tint = body.underwater.rgb;
	float underwater_darkness = body.underwater.w;
	float time = params.camera_position.w;

	vec2 ndc = screen_uv * 2.0 - 1.0;
	vec4 near_point = params.inverse_view_projection * vec4(ndc, 1.0, 1.0);
	vec3 camera_position = params.camera_position.xyz;
	vec3 ray_direction = normalize(near_point.xyz / near_point.w - camera_position);

	vec2 hit = ray_sphere(planet_centre, ocean_radius, camera_position, ray_direction);
	float scene_distance_value = scene_distance(screen_uv);
	float ocean_depth = min(hit.y, scene_distance_value - hit.x);
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
	vec2 pixel_size = 1.0 / vec2(size);
	vec3 ray_direction_x = ray_direction_at(screen_uv + vec2(pixel_size.x, 0.0), camera_position);
	vec3 ray_direction_y = ray_direction_at(screen_uv + vec2(0.0, pixel_size.y), camera_position);
	vec2 hit_x = ray_sphere(planet_centre, ocean_radius, camera_position, ray_direction_x);
	vec2 hit_y = ray_sphere(planet_centre, ocean_radius, camera_position, ray_direction_y);
	vec3 intersection_x = camera_position + ray_direction_x * hit_x.x - planet_centre;
	vec3 intersection_y = camera_position + ray_direction_y * hit_y.x - planet_centre;
	float world_footprint = max(length(intersection_x - intersection), length(intersection_y - intersection));
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
	float normal_lod = texture_lod(world_footprint, normal_scale, wave_normal_a);
	vec3 normal_a = triplanar_normal(intersection, sphere_normal, normal_scale, offset_a, normal_lod, wave_normal_a);
	vec3 detail_normal = triplanar_normal(intersection, normal_a, normal_scale, offset_b, normal_lod, wave_normal_b);
	vec3 wave_normal = normalize(mix(sphere_normal, detail_normal, clamp(wave_strength, 0.0, 1.0)));
	vec3 ray_right = normalize(ray_direction_x - ray_direction);
	vec3 ray_up = normalize(ray_direction_y - ray_direction);
	vec3 wave_delta = wave_normal - sphere_normal;
	vec2 underwater_offset = vec2(dot(wave_delta, ray_right), dot(wave_delta, ray_up));
	float specular_wave_strength = clamp(wave_strength * exp2(-4.0 * normal_lod), 0.0, 1.0);
	vec3 specular_normal = normalize(mix(sphere_normal, detail_normal, specular_wave_strength));
	float depth_blend = 1.0 - exp(-ocean_depth / max(planet_scale, 0.00001) * depth_multiplier);
	float alpha = 1.0 - exp(-ocean_depth / max(planet_scale, 0.00001) * alpha_multiplier);
	vec3 ocean_colour = mix(shallow_colour, deep_colour, depth_blend);
	float diffuse_lighting = max(dot(sphere_normal, normalize(sun_direction)), 0.0);
	float wrapped_light = clamp(dot(wave_normal, normalize(sun_direction)) * 0.35 + 0.65, 0.0, 1.0);
	float cloud_diffusion = 0.72 + 0.28 * sin(dot(sphere_normal, vec3(9.1, 13.7, 7.3)) + time * 0.18);
	vec3 scattered_sky = ambient_colour * ambient_strength * mix(wrapped_light, cloud_diffusion, sky_diffusion);
	float specular_angle = acos(clamp(dot(normalize(normalize(sun_direction) - ray_direction), specular_normal), -1.0, 1.0));
	float specular_exponent = specular_angle / max(1.0 - smoothness, 0.0001);
	float specular_highlight = exp(-specular_exponent * specular_exponent) * above_water;
	vec3 lit_ocean = ocean_colour * diffuse_lighting + scattered_sky + specular_colour * specular_highlight;
	float shore = 1.0 - smoothstep(0.0, max(foam_distance, 0.001), ocean_depth);
	float foam_lod = texture_lod(world_footprint, foam_scale / max(planet_scale, 0.00001), foam_texture);
	float foam_noise = triplanar_foam(intersection / max(planet_scale, 0.00001), sphere_normal, foam_scale, offset_a * 0.35, foam_lod);
	float leading_edge = smoothstep(0.02, 0.35, ocean_depth / max(foam_distance, 0.001));
	float foam = shore * leading_edge * smoothstep(0.24, 0.78, 1.0 - foam_noise) * above_water * (1.0 - exterior_murk);
	lit_ocean = mix(lit_ocean, foam_colour * (0.65 + 0.35 * diffuse_lighting), foam);
	float wave_light = pow(max(dot(wave_normal, normalize(sun_direction)), 0.0), 6.0);
	float wave_slope = smoothstep(0.04, 0.3, length(wave_delta));
	float surface_relief = mix(0.58, 1.32, wave_light);
	lit_ocean *= mix(1.0, surface_relief, exterior_murk * above_water * 0.72);
	lit_ocean += shallow_colour * wave_slope * wave_light * exterior_murk * above_water * 0.28;
	float refraction_fade = shore * (1.0 - smoothstep(0.0, planet_scale * 4.0, surface_distance)) * above_water;
	vec2 refraction_uv = clamp(screen_uv + wave_normal.xy * refraction_strength * refraction_fade, vec2(0.001), vec2(0.999));
	if (scene_distance(refraction_uv) < hit.x) {
		refraction_uv = screen_uv;
	}
	vec3 refracted_scene = texture(source_color, refraction_uv).rgb;
	float exterior_depth = 1.0 - exp(-ocean_depth / max(planet_scale * 0.12, 1.0));
	float murk = exterior_murk * exterior_depth * above_water;
	if (murk > 0.001) {
		refraction_uv = clamp(
			refraction_uv + underwater_offset * refraction_strength * 5.0 * murk,
			vec2(0.001), vec2(0.999)
		);
		vec3 blurred_scene = sample_blurred_scene(refraction_uv, pixel_size, 1.5 + 18.5 * murk);
		refracted_scene = mix(refracted_scene, blurred_scene, murk);
		refracted_scene = min(refracted_scene, vec3(mix(1.25, 0.16, murk)));
		float exterior_tint_peak = max(max(underwater_tint.r, underwater_tint.g), underwater_tint.b);
		vec3 exterior_tint = underwater_tint / max(exterior_tint_peak, 0.001);
		refracted_scene *= mix(vec3(1.0), exterior_tint * 0.62, murk * 0.72);
	}
	vec3 surface_colour = mix(refracted_scene, lit_ocean, alpha);
	float murk_pattern = smoothstep(0.18, 0.82, foam_noise);
	float murk_contrast = mix(0.52, 1.28, murk_pattern);
	surface_colour *= mix(1.0, murk_contrast, murk * 0.72);
	surface_colour += shallow_colour * smoothstep(0.68, 0.92, foam_noise) * murk * 0.16;

	float underwater_amount = 1.0 - above_water;
	float underwater_refraction = refraction_strength * 0.7 * (1.0 - exp(-ocean_depth / max(planet_scale * 0.08, 0.5)));
	vec2 underwater_uv = clamp(screen_uv + underwater_offset * underwater_refraction, vec2(0.001), vec2(0.999));
	vec3 underwater_scene = min(texture(source_color, underwater_uv).rgb, vec3(1.25));
	float receiver_is_scene = 1.0 - step(hit.y - 0.001, scene_distance_value);
	vec3 receiver_position = camera_position + ray_direction * min(scene_distance_value, hit.y) - planet_centre;
	float receiver_depth = max(ocean_radius - length(receiver_position), 0.0);
	vec3 receiver_normal = normalize(receiver_position);
	float caustic_pattern = 0.0;
	if (receiver_is_scene > 0.5) {
		float caustic_scale = max(foam_scale * 28.0, 24.0);
		float caustic_lod = texture_lod(
			max(scene_distance_value, 0.0) / max(float(size.y), 1.0),
			caustic_scale / max(planet_scale, 0.00001),
			caustic_texture
		);
		float caustic_time = time * max(wave_speed, 0.1) * 0.06;
		vec3 receiver_position_normalized = receiver_position / max(planet_scale, 0.00001);
		float caustic_a = directional_caustic(
			receiver_position_normalized, receiver_normal, normalize(sun_direction),
			caustic_scale, vec2(caustic_time, -caustic_time * 0.73), caustic_lod
		);
		float caustic_b = directional_caustic(
			receiver_position_normalized, receiver_normal, normalize(sun_direction),
			caustic_scale * 1.27,
			vec2(-caustic_time * 0.61, caustic_time * 0.43) + vec2(caustic_a * 0.07),
			caustic_lod
		);
		float caustic_value = max(caustic_a, caustic_b);
		caustic_pattern = smoothstep(0.76, 0.98, caustic_value);
		caustic_pattern *= caustic_pattern;
	}
	float receiver_light = max(dot(receiver_normal, normalize(sun_direction)), 0.0);
	float caustic_fade = exp(-receiver_depth / max(planet_scale * 0.12, 0.5));
	vec3 caustic_colour = mix(vec3(0.72, 0.9, 1.0), normalize(underwater_tint + 0.001), 0.28);
	underwater_scene += caustic_colour * caustic_pattern * receiver_light * caustic_fade * receiver_is_scene * 0.085;

	float tint_peak = max(max(underwater_tint.r, underwater_tint.g), underwater_tint.b);
	vec3 tint_ratio = underwater_tint / max(tint_peak, 0.001);
	vec3 absorption = mix(vec3(2.3), vec3(0.28), tint_ratio) * mix(0.75, 1.8, underwater_darkness);
	float optical_distance = ocean_depth / max(planet_scale * 0.1, 1.0);
	vec3 transmission = exp(-absorption * optical_distance);
	float camera_depth = max(ocean_radius - length(camera_position - planet_centre), 0.0);
	vec3 camera_up = normalize(camera_position - planet_centre);
	float daylight = smoothstep(-0.08, 0.35, dot(camera_up, normalize(sun_direction)));
	float surface_light = exp(-camera_depth / max(planet_scale * 0.16, 1.0) * mix(1.0, 2.6, underwater_darkness));
	vec3 scattering_colour = underwater_tint * (0.12 + 0.88 * daylight * surface_light);
	float forward_scattering = pow(max(dot(ray_direction, normalize(sun_direction)), 0.0), 10.0);
	scattering_colour += caustic_colour * forward_scattering * daylight * surface_light * 0.04;
	vec3 underwater_colour = underwater_scene * transmission + scattering_colour * (vec3(1.0) - transmission);
	imageStore(destination_color, coordinate, vec4(mix(surface_colour, underwater_colour, underwater_amount), 1.0));
}
