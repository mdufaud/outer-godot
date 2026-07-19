shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always, unshaded, fog_disabled, shadows_disabled;

uniform vec3 planet_center = vec3(0.0);
uniform vec3 sun_direction = vec3(-1.0, 0.0, 0.0);
uniform float ocean_radius = 1.0;
uniform float planet_scale = 1.0;
uniform vec3 shallow_color : source_color = vec3(0.31401902, 0.943, 0.75800556);
uniform vec3 deep_color : source_color = vec3(0.05882353, 0.15686275, 0.35686275);
uniform vec3 specular_color : source_color = vec3(0.9669199, 1.0, 0.8820755);
uniform float depth_multiplier = 15.0;
uniform float alpha_multiplier = 70.0;
uniform float wave_strength = 0.668;
uniform float wave_scale = 25.0;
uniform float wave_speed = 0.5;
uniform float smoothness = 0.927;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

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
	vec4 view_position = inverse_projection * vec4(screen_uv * 2.0 - 1.0, depth, 1.0);
	return length(view_position.xyz / max(abs(view_position.w), 0.00001));
}

float wave_height(vec3 position) {
	vec3 scaled = position * (wave_scale / max(planet_scale, 0.00001));
	float first = sin(dot(scaled, vec3(0.91, 0.37, 0.17)) + TIME * wave_speed);
	float second = sin(dot(scaled, vec3(-0.31, 0.83, 0.47)) - TIME * wave_speed * 0.8);
	float third = sin(dot(scaled, vec3(0.21, -0.43, 0.88)) + TIME * wave_speed * 0.3);
	return first + second * 0.55 + third * 0.25;
}

void fragment() {
	vec3 ray_direction = normalize(world_position - CAMERA_POSITION_WORLD);
	vec2 hit = ray_sphere(planet_center, ocean_radius, CAMERA_POSITION_WORLD, ray_direction);
	float ocean_depth = min(hit.y, scene_distance(SCREEN_UV, INV_PROJECTION_MATRIX) - hit.x);
	if (ocean_depth <= 0.0) {
		discard;
	}
	vec3 intersection = CAMERA_POSITION_WORLD + ray_direction * hit.x - planet_center;
	vec3 sphere_normal = normalize(intersection);
	vec3 tangent = normalize(cross(sphere_normal, abs(sphere_normal.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 bitangent = normalize(cross(sphere_normal, tangent));
	float epsilon = max(planet_scale * 0.0005, 0.0001);
	float gradient_tangent = wave_height(intersection + tangent * epsilon) - wave_height(intersection - tangent * epsilon);
	float gradient_bitangent = wave_height(intersection + bitangent * epsilon) - wave_height(intersection - bitangent * epsilon);
	vec3 wave_normal = normalize(sphere_normal - (tangent * gradient_tangent + bitangent * gradient_bitangent) * wave_strength);
	float depth_blend = 1.0 - exp(-ocean_depth / max(planet_scale, 0.00001) * depth_multiplier);
	float alpha = 1.0 - exp(-ocean_depth / max(planet_scale, 0.00001) * alpha_multiplier);
	vec3 ocean_color = mix(shallow_color, deep_color, depth_blend);
	float diffuse_lighting = max(dot(sphere_normal, normalize(sun_direction)), 0.0);
	float specular_angle = acos(clamp(dot(normalize(normalize(sun_direction) - ray_direction), wave_normal), -1.0, 1.0));
	float specular_exponent = specular_angle / max(1.0 - smoothness, 0.0001);
	float specular_highlight = exp(-specular_exponent * specular_exponent);
	ALBEDO = ocean_color * diffuse_lighting + specular_color * specular_highlight;
	ALPHA = alpha;
}
