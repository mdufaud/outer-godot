shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_prepass_alpha, shadows_disabled, fog_disabled;

uniform vec3 dark_color : source_color = vec3(0.0015, 0.012, 0.014);
uniform vec3 water_color : source_color = vec3(0.008, 0.065, 0.06);
uniform vec3 mist_color : source_color = vec3(0.035, 0.105, 0.098);
uniform float phase = 0.0;
uniform float layer_offset = 0.0;
uniform float radial_scale = 1.0;
uniform float opacity = 0.9;

varying float height_fraction;
varying float angular_position;
varying float churn_value;
varying float crown_mask;

float wave_noise(vec3 value) {
	float first = sin(value.x + sin(value.y * 1.37) * 1.8);
	float second = sin(value.y * 1.91 - value.z * 0.73 + first * 1.2);
	float third = sin(value.z * 2.47 + value.x * 0.61 - second);
	return (first + second + third) / 3.0;
}

void vertex() {
	height_fraction = UV.y;
	crown_mask = COLOR.a;
	float angle = atan(VERTEX.z, VERTEX.x);
	float joint_phase = dot(COLOR.rgb, vec3(0.0, 1.7, 3.8));
	float spin = TIME * (2.35 + layer_offset * 0.64) + phase + height_fraction * 9.0 + joint_phase;
	float coarse = wave_noise(vec3(angle * 2.1, height_fraction * 8.0 - TIME * 0.68, phase + layer_offset));
	float fine = wave_noise(vec3(angle * 5.7 + TIME, height_fraction * 19.0, phase * 1.9));
	float displacement = coarse * mix(0.42, 1.55, crown_mask) + fine * 0.34;
	vec2 radial_direction = normalize(VERTEX.xz);
	VERTEX.xz *= radial_scale;
	VERTEX.xz += radial_direction * displacement;
	VERTEX.xz += vec2(sin(spin), cos(spin * 0.83)) * (0.12 + height_fraction * height_fraction * 0.72);
	angular_position = angle + spin * 0.18;
	churn_value = coarse * 0.63 + fine * 0.37;
}

void fragment() {
	float descending_band = sin(angular_position * 1.35 - height_fraction * 58.0 + TIME * (5.4 + layer_offset * 1.1) + phase);
	float broken_band = sin(angular_position * 4.2 + height_fraction * 17.0 - TIME * 2.3 + churn_value * 2.6);
	float broad_mass = sin(angular_position * 0.72 - height_fraction * 21.0 + TIME * 1.8 + phase * 0.6);
	float density = smoothstep(-0.52, 0.72, descending_band + broken_band * 0.34 + churn_value * 0.55);
	density = mix(density, smoothstep(-0.78, 0.45, broad_mass + churn_value), crown_mask * 0.42);
	float height_fade = smoothstep(0.0, 0.018, height_fraction) * (1.0 - smoothstep(0.975, 1.0, height_fraction));
	float silhouette_breakup = smoothstep(-0.95, -0.18, churn_value + density * 0.82 + crown_mask * 0.18);
	float fresnel = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);
	vec3 body_color = mix(dark_color, water_color, density * 0.58 + height_fraction * 0.12);
	body_color = mix(body_color, mist_color, fresnel * (0.16 + crown_mask * 0.22) + density * 0.08 * layer_offset);
	float outer_layer = smoothstep(0.25, 0.72, layer_offset);
	silhouette_breakup = mix(0.86 + density * 0.14, silhouette_breakup, outer_layer);
	float layer_alpha = mix(0.82 + density * 0.18, 0.13 + density * 0.44 + fresnel * 0.2, outer_layer);
	ALBEDO = body_color;
	EMISSION = mist_color * fresnel * 0.018;
	ALPHA = opacity * layer_alpha * height_fade * silhouette_breakup;
	ALPHA_SCISSOR_THRESHOLD = mix(0.018, 0.11, outer_layer);
}
