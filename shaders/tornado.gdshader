shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 deep_color: source_color = vec3(0.004, 0.016, 0.015);
uniform vec3 band_color: source_color = vec3(0.014, 0.048, 0.045);
uniform vec3 storm_color: source_color = vec3(0.03, 0.09, 0.085);
uniform vec3 highlight_color: source_color = vec3(0.07, 0.17, 0.16);
uniform vec3 interior_deep_color: source_color = vec3(0.016, 0.038, 0.036);
uniform vec3 interior_band_color: source_color = vec3(0.048, 0.115, 0.108);
uniform vec3 interior_storm_color: source_color = vec3(0.08, 0.18, 0.17);
uniform vec3 interior_highlight_color: source_color = vec3(0.11, 0.25, 0.235);
uniform vec3 lightning_color: source_color = vec3(0.72, 0.95, 0.9);
uniform vec3 rim_color: source_color = vec3(0.25, 0.95, 0.82);
uniform float swirl_speed = 0.018;

varying vec3 v_pos;
varying vec3 v_local_camera;
varying float v_radius;
varying float v_exterior;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float hash1(float value) {
	return fract(sin(value * 127.1) * 43758.5453);
}

float noise1(float value) {
	float cell = floor(value);
	float blend_value = fract(value);
	blend_value = blend_value * blend_value * (3.0 - 2.0 * blend_value);
	return mix(hash1(cell), hash1(cell + 1.0), blend_value);
}

vec3 lightning_direction(float seed, vec3 observer_direction) {
	vec3 reference = abs(observer_direction.y) > 0.82 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 tangent_x = normalize(cross(reference, observer_direction));
	vec3 tangent_y = cross(observer_direction, tangent_x);
	float offset_x = (hash1(seed + 1.3) * 2.0 - 1.0) * 0.72;
	float offset_y = (hash1(seed + 5.7) * 2.0 - 1.0) * 0.58;
	return normalize(observer_direction + tangent_x * offset_x + tangent_y * offset_y);
}

vec2 lightning_coordinates(vec3 direction, vec3 strike_direction) {
	vec3 reference = abs(strike_direction.y) > 0.82 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 tangent_x = normalize(cross(reference, strike_direction));
	vec3 tangent_y = cross(strike_direction, tangent_x);
	return vec2(dot(direction, tangent_x), dot(direction, tangent_y));
}

float lightning_bolt(vec3 direction, vec3 observer_direction, float seed, out float cloud_glow) {
	vec3 strike_direction = lightning_direction(seed, observer_direction);
	vec2 coordinates = lightning_coordinates(direction, strike_direction);
	float depth = dot(direction, strike_direction);
	float coarse_frequency = mix(18.0, 43.0, hash1(seed + 8.1));
	float fine_frequency = mix(57.0, 109.0, hash1(seed + 11.7));
	float path = (noise1(coordinates.y * coarse_frequency + seed) - 0.5) * mix(0.035, 0.082, hash1(seed + 15.3));
	path += (noise1(coordinates.y * fine_frequency - seed * 1.7) - 0.5) * mix(0.008, 0.024, hash1(seed + 19.9));
	float thickness = mix(0.0025, 0.006, hash1(seed + 23.4));
	float trunk = 1.0 - smoothstep(thickness * 0.25, thickness, abs(coordinates.x - path));
	float vertical_start = mix(-0.38, -0.19, hash1(seed + 27.8));
	float vertical_end = mix(0.12, 0.32, hash1(seed + 31.2));
	float vertical_mask = smoothstep(vertical_start, vertical_start + 0.045, coordinates.y) * (1.0 - smoothstep(vertical_end - 0.055, vertical_end, coordinates.y));
	float branch_origin = mix(-0.08, 0.11, hash1(seed + 35.6));
	float branch_end = min(branch_origin + mix(0.07, 0.19, hash1(seed + 39.1)), vertical_end);
	float branch_side = hash1(seed + 42.5) < 0.5 ? -1.0 : 1.0;
	float branch_path = path + (coordinates.y - branch_origin) * mix(0.2, 0.72, hash1(seed + 46.9)) * branch_side;
	float branch = 1.0 - smoothstep(thickness * 0.2, thickness * 0.78, abs(coordinates.x - branch_path));
	branch *= smoothstep(branch_origin, branch_origin + 0.025, coordinates.y) * (1.0 - smoothstep(branch_end - 0.03, branch_end, coordinates.y));
	float second_origin = mix(-0.14, 0.05, hash1(seed + 50.4));
	float second_end = min(second_origin + mix(0.06, 0.15, hash1(seed + 53.8)), vertical_end);
	float second_path = path - (coordinates.y - second_origin) * mix(0.18, 0.58, hash1(seed + 57.2)) * branch_side;
	float second_branch = 1.0 - smoothstep(thickness * 0.2, thickness * 0.7, abs(coordinates.x - second_path));
	second_branch *= smoothstep(second_origin, second_origin + 0.025, coordinates.y) * (1.0 - smoothstep(second_end - 0.025, second_end, coordinates.y));
	second_branch *= step(0.45, hash1(seed + 61.6));
	float facing_mask = smoothstep(0.72, 0.91, depth);
	cloud_glow = pow(max(depth, 0.0), 16.0);
	return max(trunk * vertical_mask, max(branch * 0.72, second_branch * 0.58)) * facing_mask;
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i);
	float n100 = hash3(i + vec3(1, 0, 0));
	float n010 = hash3(i + vec3(0, 1, 0));
	float n110 = hash3(i + vec3(1, 1, 0));
	float n001 = hash3(i + vec3(0, 0, 1));
	float n101 = hash3(i + vec3(1, 0, 1));
	float n011 = hash3(i + vec3(0, 1, 1));
	float n111 = hash3(i + vec3(1, 1, 1));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z
	);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * value_noise(p);
		p = p * 2.05 + vec3(17.0, -11.0, 7.0);
		a *= 0.48;
	}
	return v;
}

float ridged_fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		float n = 1.0 - abs(value_noise(p) * 2.0 - 1.0);
		v += n * n * a;
		p = p * 2.18 + vec3(-9.0, 13.0, 5.0);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_pos = normalize(VERTEX);
	vec3 local_camera = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	v_local_camera = local_camera;
	v_radius = length(VERTEX);
	v_exterior = float(length(local_camera) > length(VERTEX));
}

void fragment() {
	vec3 direction = normalize(v_pos);
	float time = TIME * swirl_speed;
	vec3 flow = direction;
	flow.x += sin(direction.y * 7.0 + direction.z * 3.0 + time * 5.0) * 0.12;
	flow.y += sin(direction.x * 5.0 - direction.z * 4.0 - time * 3.0) * 0.08;
	flow.z += cos(direction.y * 6.0 - direction.x * 3.0 + time * 4.0) * 0.12;
	flow = normalize(flow);

	float broad_noise = fbm(flow * 3.4 + vec3(time * 2.0, -time, time * 0.7));
	float fine_noise = fbm(flow * 10.0 + vec3(-time * 3.0, time * 1.7, time * 2.2));
	float ridge_noise = ridged_fbm(flow * 16.0 + vec3(time * 4.0, -time * 2.0, time));
	float broad_clouds = smoothstep(0.22, 0.78, broad_noise * 0.78 + fine_noise * 0.22);
	float cloud_detail = smoothstep(0.38, 0.82, fine_noise * 0.62 + ridge_noise * 0.38);
	float dark_cells = smoothstep(0.5, 0.86, (1.0 - broad_noise) * 0.82 + ridge_noise * 0.18);
	float cloud_highlights = smoothstep(0.68, 0.92, broad_noise * 0.65 + ridge_noise * 0.35);

	bool interior = v_exterior < 0.5;
	vec3 base_deep = interior ? interior_deep_color : deep_color;
	vec3 base_band = interior ? interior_band_color : band_color;
	vec3 base_storm = interior ? interior_storm_color : storm_color;
	vec3 base_highlight = interior ? interior_highlight_color : highlight_color;
	vec3 col = mix(base_deep, base_band, broad_clouds * (interior ? 0.62 : 0.72));
	col = mix(col, base_storm, cloud_detail * (interior ? 0.24 : 0.36));
	col += base_highlight * cloud_highlights * (interior ? 0.1 : 0.14);
	col *= 1.0 - dark_cells * (interior ? 0.48 : 0.32);

	float facing = abs(dot(direction, normalize(v_local_camera - direction * v_radius)));
	float limb = smoothstep(0.0, 0.68, facing);
	float light_wrap = clamp(dot(direction, normalize(vec3(-0.55, 0.38, 0.74))) * 0.5 + 0.5, 0.0, 1.0);
	float lightning = 0.0;
	float lightning_glow = 0.0;
	vec3 observer_direction = normalize(v_local_camera);
	float event_cell_duration = 2.5;
	float event_cell = floor(TIME / event_cell_duration);
	float event_cell_time = TIME - event_cell * event_cell_duration;
	for (int channel = 0; channel < 6; channel++) {
		float channel_value = float(channel);
		float channel_seed = channel_value * 47.31 + 8.7;
		float strike_time = 0.5 + hash1(event_cell * 19.73 + channel_seed) * 1.5;
		float local_time = event_cell_time - strike_time;
		float active = step(0.0, local_time) * (1.0 - step(0.25, local_time));
		float bolt_seed = event_cell * 83.17 + channel_seed;
		float primary_flash = exp(-local_time * mix(22.0, 38.0, hash1(bolt_seed + 9.2)));
		float echo_delay = mix(0.05, 0.11, hash1(bolt_seed + 13.5));
		float secondary_flash = exp(-abs(local_time - echo_delay) * mix(42.0, 68.0, hash1(bolt_seed + 17.8))) * mix(0.3, 0.72, hash1(bolt_seed + 21.1));
		float pulse = min(primary_flash + secondary_flash, 1.0) * active;
		float bolt_glow = 0.0;
		float bolt = lightning_bolt(direction, observer_direction, bolt_seed, bolt_glow);
		lightning = max(lightning, bolt * pulse);
		lightning_glow = max(lightning_glow, bolt_glow * pulse);
	}
	if (interior) {
		col *= mix(0.52, 0.92, limb) * mix(0.72, 1.0, light_wrap);
		col += interior_storm_color * (0.035 + broad_noise * 0.045);
		col += lightning_color * (lightning * 1.8 + lightning_glow * 0.14);
	} else {
		col *= mix(0.26, 0.9, limb) * mix(0.58, 1.02, light_wrap);
		col += lightning_color * (lightning * 1.25 + lightning_glow * 0.08);
	}
	float rim = interior ? 0.0 : 1.0 - smoothstep(0.03, 0.2, facing);
	col = mix(col, rim_color, rim * 0.65);

	ALBEDO = col;
	EMISSION = col * 0.008 + base_highlight * cloud_highlights * 0.008 + rim_color * rim * 0.8;
	float exterior_lightning_filter = interior ? 1.0 : 0.72;
	EMISSION += lightning_color * (lightning * 1.8 + lightning_glow * 0.32) * exterior_lightning_filter;
}
