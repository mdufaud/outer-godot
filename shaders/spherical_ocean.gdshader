shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always, unshaded, fog_disabled, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D wave_normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 planet_center = vec3(0.0);
uniform vec3 sun_direction = vec3(-1.0, 0.0, 0.0);
uniform float ocean_radius = 1.0;
uniform float planet_scale = 1.0;
uniform vec3 shallow_color : source_color = vec3(0.31401902, 0.943, 0.75800556);
uniform vec3 deep_color : source_color = vec3(0.05882353, 0.15686275, 0.35686275);
uniform vec3 specular_color : source_color = vec3(0.9669199, 1.0, 0.8820755);
uniform vec3 ambient_color : source_color = vec3(0.0);
uniform vec3 foam_color : source_color = vec3(0.92, 0.98, 1.0);
uniform float ambient_strength = 0.0;
uniform float sky_diffusion = 0.0;
uniform float depth_multiplier = 15.0;
uniform float alpha_multiplier = 70.0;
uniform float wave_strength = 0.668;
uniform float wave_scale = 25.0;
uniform float wave_speed = 0.5;
uniform float smoothness = 0.927;
uniform float foam_scale = 1.4;
uniform float foam_distance = 0.9;
uniform float refraction_strength = 0.003;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 ray_sphere(vec3 centre, float radius, vec3 origin, vec3 direction) {
	vec3 offset = origin - centre;
	float b = dot(offset, direction);
	float c = dot(offset, offset) - radius * radius;
	float discriminant = b * b - c;
	if (discriminant < 0.0) {
		return vec2(1000000.0, 0.0);
	}
	float root = sqrt(discriminant);
	float near_distance = max(0.0, -b - root);
	float far_distance = -b + root;
	return vec2(near_distance, max(0.0, far_distance - near_distance));
}

float scene_distance(vec2 screen_uv, mat4 inverse_projection) {
	float depth = texture(depth_texture, screen_uv).r;
	if (depth <= 0.0) {
		return 1000000.0;
	}
	vec4 view_position = inverse_projection * vec4(screen_uv * 2.0 - 1.0, depth, 1.0);
	return length(view_position.xyz / max(abs(view_position.w), 0.00001));
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

void fragment() {
	vec3 ray_direction = normalize(world_position - CAMERA_POSITION_WORLD);
	vec2 hit = ray_sphere(planet_center, ocean_radius, CAMERA_POSITION_WORLD, ray_direction);
	float ocean_depth = min(hit.y, scene_distance(SCREEN_UV, INV_PROJECTION_MATRIX) - hit.x);
	if (ocean_depth <= 0.0) {
		discard;
	}
	bool camera_underwater = distance(CAMERA_POSITION_WORLD, planet_center) < ocean_radius;
	float surface_distance = camera_underwater ? hit.y : hit.x;
	vec3 intersection = CAMERA_POSITION_WORLD + ray_direction * surface_distance - planet_center;
	vec3 sphere_normal = normalize(intersection);
	float normal_scale = wave_scale / max(planet_scale, 0.00001);
	vec2 offset_a = vec2(TIME * wave_speed * 0.08, TIME * wave_speed * 0.063);
	vec2 offset_b = vec2(-TIME * wave_speed * 0.057, TIME * wave_speed * 0.031);
	vec3 normal_a = triplanar_normal(intersection, sphere_normal, normal_scale, offset_a, wave_normal_a);
	vec3 normal_b = triplanar_normal(intersection, sphere_normal, normal_scale * 0.73, offset_b, wave_normal_b);
	vec3 detail_normal = normalize(blend_rnm(normal_a, normal_b));
	vec3 wave_normal = normalize(mix(sphere_normal, detail_normal, clamp(wave_strength, 0.0, 1.0)));
	float depth_blend = 1.0 - exp(-ocean_depth / max(planet_scale, 0.00001) * depth_multiplier);
	float alpha = 1.0 - exp(-ocean_depth / max(planet_scale, 0.00001) * alpha_multiplier);
	vec3 ocean_color = mix(shallow_color, deep_color, depth_blend);
	float diffuse_lighting = max(dot(sphere_normal, normalize(sun_direction)), 0.0);
	float wrapped_light = clamp(dot(wave_normal, normalize(sun_direction)) * 0.35 + 0.65, 0.0, 1.0);
	float cloud_diffusion = 0.72 + 0.28 * sin(dot(sphere_normal, vec3(9.1, 13.7, 7.3)) + TIME * 0.18);
	vec3 scattered_sky = ambient_color * ambient_strength * mix(wrapped_light, cloud_diffusion, sky_diffusion);
	float specular_angle = acos(clamp(dot(normalize(normalize(sun_direction) - ray_direction), wave_normal), -1.0, 1.0));
	float specular_exponent = specular_angle / max(1.0 - smoothness, 0.0001);
	float specular_highlight = exp(-specular_exponent * specular_exponent) * (camera_underwater ? 0.0 : 1.0);
	vec3 lit_ocean = ocean_color * diffuse_lighting + scattered_sky + specular_color * specular_highlight;
	float shore = 1.0 - smoothstep(0.0, max(foam_distance, 0.001), ocean_depth);
	float foam_noise = triplanar_foam(intersection / max(planet_scale, 0.00001), sphere_normal, foam_scale, offset_a * 0.35);
	float leading_edge = smoothstep(0.02, 0.35, ocean_depth / max(foam_distance, 0.001));
	float foam = shore * leading_edge * smoothstep(0.24, 0.78, 1.0 - foam_noise) * (camera_underwater ? 0.0 : 1.0);
	lit_ocean = mix(lit_ocean, foam_color * (0.65 + 0.35 * diffuse_lighting), foam);
	float refraction_fade = shore * (1.0 - smoothstep(0.0, planet_scale * 4.0, surface_distance)) * (camera_underwater ? 0.25 : 1.0);
	vec2 refraction_uv = clamp(SCREEN_UV + wave_normal.xy * refraction_strength * refraction_fade, vec2(0.001), vec2(0.999));
	if (scene_distance(refraction_uv, INV_PROJECTION_MATRIX) < hit.x) {
		refraction_uv = SCREEN_UV;
	}
	vec3 refracted_scene = textureLod(screen_texture, refraction_uv, 0.0).rgb;
	ALBEDO = mix(refracted_scene, lit_ocean, alpha);
	ALPHA = 1.0;
}
