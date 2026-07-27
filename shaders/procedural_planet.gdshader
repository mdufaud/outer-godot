shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform int body_kind = 0;
uniform float planet_radius = 1.0;
uniform vec3 sun_direction = vec3(0.5, 0.4, 0.75);
uniform vec2 height_min_max = vec2(1.0);
uniform float ocean_level = 1.0;
uniform sampler2D earth_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D moon_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D crater_ejecta : filter_linear_mipmap, repeat_enable;
uniform sampler2D moon_normal_flat : filter_linear_mipmap, repeat_enable;
uniform sampler2D moon_normal_steep : filter_linear_mipmap, repeat_enable;

uniform vec4 shore_low : source_color = vec4(0.98039216, 1.0, 0.6666667, 1.0);
uniform vec4 shore_high : source_color = vec4(0.9528302, 0.90580887, 0.38203096, 1.0);
uniform vec4 flat_low_a : source_color = vec4(0.7898985, 0.85882354, 0.0, 1.0);
uniform vec4 flat_high_a : source_color = vec4(0.19073083, 0.4627451, 0.0, 1.0);
uniform vec4 flat_low_b : source_color = vec4(0.58431375, 0.85882354, 0.0, 1.0);
uniform vec4 flat_high_b : source_color = vec4(0.19215687, 0.4627451, 0.0, 1.0);
uniform vec4 steep_low : source_color = vec4(0.5294118, 0.49019608, 0.1882353, 1.0);
uniform vec4 steep_high : source_color = vec4(0.14901961, 0.06666667, 0.0, 1.0);
uniform vec4 earth_test_params = vec4(-0.36, -0.05, 0.38, 0.0);

uniform vec4 moon_primary_a : source_color = vec4(1.0);
uniform vec4 moon_secondary_a : source_color = vec4(0.735849, 0.735849, 0.735849, 1.0);
uniform vec4 moon_primary_b : source_color = vec4(0.1792453, 0.1792453, 0.1792453, 1.0);
uniform vec4 moon_secondary_b : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 moon_ejecta : source_color = vec4(1.0, 0.96323127, 0.9386792, 1.0);
uniform float moon_biome_blend_strength = 1.37;
uniform float moon_biome_warp_strength = 6.08;
uniform vec4 moon_random_biome_values = vec4(-4.41, 0.0, -1.18, 5.65);
uniform float moon_average_biome_noise = 1.0;
uniform float moon_smoothness_a = 0.018220196;
uniform float moon_smoothness_b = 0.18875508;
uniform float moon_smoothness_ejecta = 0.037;
// Rocky moons stay matte; an icy crust needs a highlight to read as ice.
uniform float moon_specular = 0.0;
// Painted eye. Relief alone turns into a black pit the moment the light stops
// grazing it, so the eye is an albedo feature and reads from any distance.
uniform float eye_strength = 0.0;
uniform vec3 eye_direction = vec3(0.0, 0.176, 0.984);
uniform float eye_sclera_radius = 0.62;
uniform float eye_iris_radius = 0.34;
uniform float eye_pupil_radius = 0.14;
uniform vec4 eye_sclera_color : source_color = vec4(0.86, 0.94, 0.98, 1.0);
uniform vec4 eye_iris_color : source_color = vec4(0.05, 0.32, 0.46, 1.0);
uniform vec4 eye_pupil_color : source_color = vec4(0.01, 0.02, 0.04, 1.0);
uniform float eye_glow = 0.0;
uniform vec3 asteroid_col_flat : source_color = vec3(0.38, 0.35, 0.32);
uniform vec3 asteroid_col_flat_deep : source_color = vec3(0.19, 0.17, 0.16);
uniform vec3 asteroid_col_steep : source_color = vec3(0.28, 0.26, 0.25);
uniform vec3 asteroid_col_steep_deep : source_color = vec3(0.12, 0.11, 0.11);
uniform vec3 asteroid_col_ambient : source_color = vec3(0.30, 0.29, 0.30);
uniform float asteroid_height_min = 12.0;
uniform float asteroid_height_max = 24.0;
uniform float asteroid_height_bands = 4.0;
uniform vec3 glacier_col_flat : source_color = vec3(0.86, 0.92, 0.97);
uniform vec3 glacier_col_flat_deep : source_color = vec3(0.42, 0.58, 0.72);
uniform vec3 glacier_col_steep : source_color = vec3(0.55, 0.62, 0.70);
uniform vec3 glacier_col_steep_deep : source_color = vec3(0.22, 0.30, 0.42);
uniform vec3 glacier_col_ambient : source_color = vec3(0.42, 0.50, 0.60);
uniform float glacier_height_min = 20.0;
uniform float glacier_height_max = 29.0;
uniform float glacier_height_bands = 9.0;
uniform vec3 cyclops_core_color : source_color = vec3(0.08, 1.0, 0.72);

uniform float earth_noise_scale = 10.0;
uniform float earth_noise_scale_detail = 50.0;

uniform float ice_cap_strength = 0.0;
uniform vec3 ice_cap_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float ice_cap_start = 0.94;
uniform float ice_cap_blend = 0.03;
uniform float ice_cap_noise_a = 3.0;
uniform float ice_cap_noise_b = 2.87;
uniform float ice_cap_highlight = 1.2;
uniform float ice_cap_specular = 0.704;

uniform vec3 fresnel_color : source_color = vec3(1.0, 0.9, 0.665);
uniform float fresnel_strength_near = 0.0;
uniform float fresnel_strength_far = 0.0;
uniform float fresnel_power = 12.0;

varying vec4 terrain_data;
varying vec3 terrain_vertex;
varying vec3 terrain_normal;
varying vec3 terrain_tangent;

float remap01(float value, float minimum, float maximum) {
	return clamp((value - minimum) / max(maximum - minimum, 0.00001), 0.0, 1.0);
}

float blend(float start_height, float blend_distance, float value) {
	return smoothstep(start_height - blend_distance * 0.5, start_height + blend_distance * 0.5, value);
}

vec4 triplanar(vec3 vertex_position, vec3 normal, float scale, sampler2D texture_source) {
	vec4 color_x = texture(texture_source, vertex_position.zy * scale);
	vec4 color_y = texture(texture_source, vertex_position.xz * scale);
	vec4 color_z = texture(texture_source, vertex_position.xy * scale);
	vec3 weight = normal * normal;
	weight /= dot(weight, vec3(1.0));
	return color_x * weight.x + color_y * weight.y + color_z * weight.z;
}

vec3 blend_rnm(vec3 first_normal, vec3 second_normal) {
	first_normal.z += 1.0;
	second_normal.xy = -second_normal.xy;
	return first_normal * dot(first_normal, second_normal) / first_normal.z - second_normal;
}

vec3 triplanar_normal(vec3 vertex_position, vec3 normal, float scale, sampler2D texture_source) {
	vec3 absolute_normal = abs(normal);
	vec3 weight = pow(absolute_normal, vec3(4.0));
	weight /= dot(weight, vec3(1.0));
	vec3 tangent_normal_x = texture(texture_source, vertex_position.zy * scale).xyz * 2.0 - 1.0;
	vec3 tangent_normal_y = texture(texture_source, vertex_position.xz * scale).xyz * 2.0 - 1.0;
	vec3 tangent_normal_z = texture(texture_source, vertex_position.xy * scale).xyz * 2.0 - 1.0;
	tangent_normal_x = blend_rnm(vec3(normal.zy, absolute_normal.x), tangent_normal_x);
	tangent_normal_y = blend_rnm(vec3(normal.xz, absolute_normal.y), tangent_normal_y);
	tangent_normal_z = blend_rnm(vec3(normal.xy, absolute_normal.z), tangent_normal_z);
	vec3 axis_sign = sign(normal);
	tangent_normal_x.z *= axis_sign.x;
	tangent_normal_y.z *= axis_sign.y;
	tangent_normal_z.z *= axis_sign.z;
	return normalize(tangent_normal_x.zyx * weight.x + tangent_normal_y.xzy * weight.y + tangent_normal_z.xyz * weight.z);
}

vec3 object_to_tangent(vec3 object_space_vector, vec3 normal, vec3 tangent) {
	vec3 normalized_tangent = normalize(tangent);
	vec3 binormal = cross(normal, normalized_tangent);
	return vec3(dot(normalized_tangent, object_space_vector), dot(binormal, object_space_vector), dot(normal, object_space_vector));
}

void vertex() {
	terrain_data = vec4(UV, UV2);
	terrain_vertex = VERTEX;
	terrain_normal = NORMAL;
	terrain_tangent = TANGENT;
}

void fragment() {
	vec3 sphere_normal = normalize(terrain_vertex);
	vec3 mesh_normal = normalize(terrain_normal);
	float terrain_height = length(terrain_vertex) / max(planet_radius, 0.00001);
	float height01 = remap01(terrain_height, height_min_max.x, height_min_max.y);
	float steepness = 1.0 - dot(sphere_normal, mesh_normal);
	if (body_kind == 2) {
		float asteroid_height01 = remap01(length(terrain_vertex), asteroid_height_min, asteroid_height_max);
		asteroid_height01 = float(int(asteroid_height01 * asteroid_height_bands)) / asteroid_height_bands;
		float flatness = dot(sphere_normal, mesh_normal);
		float flat_t = smoothstep(0.76 - 0.01, 0.76 + 0.01, flatness);
		vec3 shading = vec3(dot(normalize(sun_direction), mesh_normal) * 0.5 + 0.5);
		shading += asteroid_col_ambient;
		shading = pow(max(shading, vec3(0.0)), vec3(1.5));
		vec3 c_flat = mix(asteroid_col_flat_deep, asteroid_col_flat, asteroid_height01);
		vec3 c_steep = mix(asteroid_col_steep_deep, asteroid_col_steep, asteroid_height01);
		ALBEDO = vec3(0.0);
		EMISSION = mix(c_flat, c_steep, 1.0 - flat_t) * shading;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	} else if (body_kind == 3) {
		float glacier_height01 = remap01(terrain_height, glacier_height_min, glacier_height_max);
		glacier_height01 = float(int(glacier_height01 * glacier_height_bands)) / glacier_height_bands;
		float flatness = dot(sphere_normal, mesh_normal);
		float flat_t = smoothstep(0.76 - 0.01, 0.76 + 0.01, flatness);
		vec3 shading = vec3(dot(normalize(sun_direction), mesh_normal) * 0.5 + 0.5);
		shading += glacier_col_ambient;
		shading = pow(max(shading, vec3(0.0)), vec3(1.5));
		vec3 c_flat = mix(glacier_col_flat_deep, glacier_col_flat, glacier_height01);
		vec3 c_steep = mix(glacier_col_steep_deep, glacier_col_steep, glacier_height01);
		ALBEDO = vec3(0.0);
		EMISSION = mix(c_flat, c_steep, 1.0 - flat_t) * shading;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	} else if (body_kind == 4) {
		float vein_a = abs(sin(dot(sphere_normal, vec3(17.0, 11.0, 23.0)) + terrain_data.x * 7.0));
		float vein_b = abs(sin(dot(sphere_normal, vec3(-13.0, 29.0, 9.0)) - terrain_data.y * 11.0));
		float veins = pow(clamp(1.0 - abs(vein_a - vein_b) * 4.5, 0.0, 1.0), 7.0);
		float pulse = 0.72 + 0.28 * sin(TIME * 0.8 + dot(sphere_normal, vec3(5.0, 8.0, 3.0)));
		ALBEDO = mix(vec3(0.008, 0.025, 0.03), vec3(0.025, 0.12, 0.11), veins);
		EMISSION = cyclops_core_color * veins * pulse * 1.6;
		ROUGHNESS = 0.78;
		SPECULAR = 0.18;
	} else if (body_kind == 0) {
		vec4 source_noise = triplanar(terrain_vertex / planet_radius, mesh_normal, earth_noise_scale, earth_noise);
		vec4 detail_noise = triplanar(terrain_vertex / planet_radius, mesh_normal, earth_noise_scale_detail, earth_noise);
		steepness = remap01(steepness, 0.0, 0.65);
		float shore_height = mix(height_min_max.x, 1.0, ocean_level);
		float above_shore_height01 = remap01(terrain_height, shore_height, height_min_max.y);
		float flat_height01 = remap01(above_shore_height01, 0.0, 0.52);
		float flat_col_blend_weight = blend(0.0, 1.5, (flat_height01 - 0.5) + (source_noise.b - 0.5) * 0.3);
		vec3 flat_terrain_col_a = mix(flat_low_a.rgb, flat_high_a.rgb, flat_col_blend_weight);
		flat_terrain_col_a = mix(flat_terrain_col_a, (flat_low_a.rgb + flat_high_a.rgb) * 0.5, source_noise.a);
		vec3 flat_terrain_col_b = mix(flat_low_b.rgb, flat_high_b.rgb, flat_col_blend_weight);
		flat_terrain_col_b = mix(flat_terrain_col_b, (flat_low_b.rgb + flat_high_b.rgb) * 0.5, source_noise.a);
		float biome_weight = blend(0.0, earth_test_params.z, terrain_vertex.x / planet_radius + terrain_data.x * earth_test_params.x + terrain_data.y * earth_test_params.y);
		vec3 flat_terrain_col = mix(flat_terrain_col_a, flat_terrain_col_b, biome_weight);
		float shore_blend_weight = 1.0 - blend(0.058, 0.089, flat_height01);
		vec3 shore_col = mix(shore_low.rgb, shore_high.rgb, remap01(above_shore_height01, 0.0, 0.058));
		shore_col = mix(shore_col, (shore_low.rgb + shore_high.rgb) * 0.5, source_noise.g);
		flat_terrain_col = mix(flat_terrain_col, shore_col, shore_blend_weight);
		vec3 sphere_tangent = normalize(vec3(-sphere_normal.z, 0.0, sphere_normal.x));
		vec3 normal_tangent = normalize(mesh_normal - sphere_normal * dot(mesh_normal, sphere_normal));
		float banding = dot(sphere_tangent, normal_tangent) * 0.5 + 0.5;
		banding = float(int(banding * 9.0)) / 8.0;
		banding = (abs(banding - 0.5) * 2.0 - 0.5) * 0.5;
		vec3 steep_terrain_col = mix(steep_low.rgb, steep_high.rgb, above_shore_height01 + banding);
		float flat_blend_noise = (detail_noise.r - 0.5) * 0.026;
		float flat_strength = 1.0 - blend(0.378 + flat_blend_noise, 0.051, steepness);
		float flat_height_falloff = 1.0 - blend(0.52 + flat_blend_noise, 0.051, above_shore_height01);
		ALBEDO = mix(steep_terrain_col, flat_terrain_col, flat_strength * flat_height_falloff);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		if (ice_cap_strength > 0.0) {
			float snow_line_noise = terrain_data.y * ice_cap_noise_a * 0.01 + (source_noise.b - 0.5) * ice_cap_noise_b * 0.01;
			float cap_weight = blend(ice_cap_start, ice_cap_blend, abs(terrain_vertex.y / planet_radius + snow_line_noise)) * ice_cap_strength;
			float speckle = 1.0 - detail_noise.g * 0.05;
			vec3 snow_col = ice_cap_color * mix(1.0, ice_cap_highlight, above_shore_height01 + banding) * speckle;
			ALBEDO = mix(ALBEDO, snow_col, cap_weight);
			ROUGHNESS = mix(ROUGHNESS, 1.0 - ice_cap_specular, cap_weight);
			SPECULAR = mix(SPECULAR, 0.5, cap_weight);
		}
	} else {
		vec4 source_noise = triplanar(terrain_vertex / planet_radius, mesh_normal, 8.0, moon_noise);
		steepness = remap01(steepness, 0.0, 0.3);
		float warp_noise = blend(0.0, 3.0, terrain_data.z);
		float height_noise_a = -source_noise.g * steepness - (source_noise.b - 0.5) * 0.7 + (source_noise.a - 0.5) * moon_random_biome_values.x;
		float height_noise_b = (source_noise.g - 0.5) * moon_random_biome_values.y + (source_noise.r - 0.5) * moon_random_biome_values.z;
		float height_blend_weight_a = blend(0.5, 0.6, height01 + height_noise_a) * warp_noise;
		float height_blend_weight_b = blend(0.5, 0.6, height01 + height_noise_b) * warp_noise;
		vec3 col_biome_a = mix(moon_primary_a.rgb, moon_secondary_a.rgb, height_blend_weight_a);
		vec3 col_biome_b = mix(moon_primary_b.rgb, moon_secondary_b.rgb, height_blend_weight_b);
		float biome_noise = dot(source_noise.ga - 0.5, moon_random_biome_values.zw) * 4.0;
		float biome_weight = blend(moon_average_biome_noise * 0.8 + terrain_data.z * moon_biome_warp_strength, moon_biome_blend_strength + warp_noise * 15.0, terrain_data.w + biome_noise);
		vec2 crater_uv = 0.5 + vec2(cos(terrain_data.x), sin(terrain_data.x)) * terrain_data.y;
		float ejecta = texture(crater_ejecta, crater_uv).r;
		float crater_alpha = float(abs(terrain_data.y) < 0.5);
		float ejecta_weight = clamp(ejecta * 1.5, 0.0, 1.0) * crater_alpha;
		ALBEDO = mix(mix(col_biome_a, col_biome_b, biome_weight), moon_ejecta.rgb, ejecta_weight);
		float smoothness = mix(moon_smoothness_a, moon_smoothness_b, biome_weight);
		smoothness = mix(smoothness, moon_smoothness_ejecta, ejecta_weight);
		if (eye_strength > 0.0) {
			vec3 eye_up = normalize(terrain_vertex);
			float eye_angle = acos(clamp(dot(eye_up, eye_direction), -1.0, 1.0));
			vec3 eye_side = normalize(cross(eye_direction, vec3(0.0, 1.0, 0.0)));
			vec3 eye_top = cross(eye_direction, eye_side);
			float around = atan(dot(eye_up, eye_top), dot(eye_up, eye_side));
			// Iris fibres, so the ring is not a flat disc of colour.
			float fibres = 0.5 + 0.5 * sin(around * 34.0 + source_noise.r * 6.0);
			float sclera = 1.0 - blend(eye_sclera_radius, eye_sclera_radius * 0.28, eye_angle);
			float iris = 1.0 - blend(eye_iris_radius, eye_iris_radius * 0.42, eye_angle);
			float pupil = 1.0 - blend(eye_pupil_radius, eye_pupil_radius * 0.5, eye_angle);
			vec3 iris_col = eye_iris_color.rgb * mix(0.72, 1.28, fibres);
			ALBEDO = mix(ALBEDO, eye_sclera_color.rgb, sclera * eye_strength);
			ALBEDO = mix(ALBEDO, iris_col, iris * eye_strength);
			ALBEDO = mix(ALBEDO, eye_pupil_color.rgb, pupil * eye_strength);
			smoothness = mix(smoothness, 0.6, sclera * eye_strength);
			EMISSION = eye_iris_color.rgb * (iris - pupil) * eye_glow;
		}
		ROUGHNESS = 1.0 - smoothness;
		// Unity's MetallicA of 0.811 relies on reflection probes; without them a
		// metallic moon just renders black here.
		METALLIC = 0.0;
		SPECULAR = moon_specular;
		vec3 normal_flat = object_to_tangent(triplanar_normal(terrain_vertex / planet_radius, mesh_normal, 20.0, moon_normal_flat), mesh_normal, terrain_tangent);
		vec3 normal_steep = object_to_tangent(triplanar_normal(terrain_vertex / planet_radius, mesh_normal, 20.0, moon_normal_steep), mesh_normal, terrain_tangent);
		float normal_blend = mix(source_noise.r, source_noise.g, blend(0.0, 2.0, terrain_data.z));
		vec3 flat_and_steep_normal = mix(normal_flat, normal_steep, normal_blend);
		vec3 terrain_normal_map = mix(flat_and_steep_normal, normal_steep, steepness);
		terrain_normal_map = mix(vec3(0.0, 0.0, 1.0), terrain_normal_map, 0.589);
		NORMAL_MAP = terrain_normal_map * 0.5 + 0.5;
	}

	if (fresnel_strength_near > 0.0 || fresnel_strength_far > 0.0) {
		float radii_from_surface = length(VERTEX) / max(planet_radius, 0.00001) - 1.0;
		float fresnel_t = smoothstep(0.0, 1.0, radii_from_surface);
		float fresnel_strength = mix(fresnel_strength_near, fresnel_strength_far, fresnel_t);
		float rim = clamp(fresnel_strength * pow(1.0 - dot(normalize(VIEW), normalize(NORMAL)), fresnel_power), 0.0, 1.0);
		ALBEDO = mix(ALBEDO, fresnel_color, rim);
	}
}
