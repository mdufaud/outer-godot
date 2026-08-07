shader_type spatial;
render_mode unshaded, blend_mix, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 half_extents = vec3(2500.0, 1700.0, 3000.0);
uniform float field_scale = 1150.0;
uniform vec3 cloud_color : source_color = vec3(0.075, 0.030, 0.170);
uniform vec3 lightning_color : source_color = vec3(0.48, 0.08, 0.82);
uniform float visibility : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 local_position;
varying vec3 local_camera;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float value_noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 blend_value = fract(p);
	blend_value = blend_value * blend_value * (3.0 - 2.0 * blend_value);
	return mix(
		mix(mix(hash3(cell), hash3(cell + vec3(1.0, 0.0, 0.0)), blend_value.x),
			mix(hash3(cell + vec3(0.0, 1.0, 0.0)), hash3(cell + vec3(1.0, 1.0, 0.0)), blend_value.x), blend_value.y),
		mix(mix(hash3(cell + vec3(0.0, 0.0, 1.0)), hash3(cell + vec3(1.0, 0.0, 1.0)), blend_value.x),
			mix(hash3(cell + vec3(0.0, 1.0, 1.0)), hash3(cell + vec3(1.0, 1.0, 1.0)), blend_value.x), blend_value.y),
		blend_value.z
	);
}

float fbm3(vec3 p) {
	float value = 0.0;
	float amplitude = 0.52;
	for (int octave = 0; octave < 4; octave++) {
		value += value_noise3(p) * amplitude;
		p = p * 2.07 + vec3(11.3, 5.7, 3.1);
		amplitude *= 0.49;
	}
	return value;
}

float segment_distance(vec3 point, vec3 start, vec3 end) {
	vec3 line = end - start;
	float along = clamp(dot(point - start, line) / dot(line, line), 0.0, 1.0);
	return length(point - (start + line * along));
}

// Bolts run down the throat axis (local Z), kinking sideways, so they read as
// discharges inside the funnel rather than as a lattice crossing the box.
float bolt_field(vec3 point, float seed) {
	vec3 bend_a = vec3(hash3(vec3(seed, 1.0, 2.0)) - 0.5, hash3(vec3(seed, 3.0, 4.0)) - 0.5, -0.42);
	vec3 bend_b = vec3(hash3(vec3(seed, 5.0, 6.0)) - 0.5, hash3(vec3(seed, 7.0, 8.0)) - 0.5, 0.34);
	vec3 start = vec3(0.0, 0.0, -1.30);
	vec3 end = vec3(0.0, 0.0, 1.15);
	float distance_value = min(segment_distance(point, start, bend_a), segment_distance(point, bend_a, bend_b));
	distance_value = min(distance_value, segment_distance(point, bend_b, end));
	vec3 branch_end_a = bend_a + vec3(-0.62, 0.44, 0.40);
	vec3 branch_end_b = bend_b + vec3(0.55, -0.50, 0.36);
	distance_value = min(distance_value, segment_distance(point, bend_a, branch_end_a) * 1.18);
	distance_value = min(distance_value, segment_distance(point, bend_b, branch_end_b) * 1.18);
	return distance_value;
}

void vertex() {
	local_position = VERTEX;
	local_camera = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

void fragment() {
	if (visibility < 0.005) {
		discard;
	}
	vec3 direction = normalize(local_position - local_camera);
	vec3 inverse_direction = 1.0 / direction;
	vec3 slab_a = (-half_extents - local_camera) * inverse_direction;
	vec3 slab_b = (half_extents - local_camera) * inverse_direction;
	vec3 near_slab = min(slab_a, slab_b);
	vec3 far_slab = max(slab_a, slab_b);
	float near_t = max(max(near_slab.x, near_slab.y), max(near_slab.z, 0.0));
	float far_t = min(min(far_slab.x, far_slab.y), far_slab.z);
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	scene_view.xyz /= scene_view.w;
	vec3 scene_world = (INV_VIEW_MATRIX * vec4(scene_view.xyz, 1.0)).xyz;
	vec3 scene_local = (inverse(MODEL_MATRIX) * vec4(scene_world, 1.0)).xyz;
	far_t = min(far_t, distance(scene_local, local_camera));
	if (far_t <= near_t) {
		discard;
	}

	vec3 step_vector = direction * (far_t - near_t) / 40.0;
	// Without a per-pixel offset the swirl lands on the same shells for every ray
	// and the funnel shows concentric contour rings instead of cloud.
	float jitter = fract(sin(dot(SCREEN_UV, vec2(12.9898, 78.233)) + TIME) * 43758.5453);
	vec3 position = local_camera + direction * near_t + step_vector * jitter;
	vec3 accumulated = vec3(0.0);
	float alpha = 0.0;
	float bolt_seed = floor(TIME * 0.31) + 7.0;
	for (int index = 0; index < 40; index++) {
		vec3 shape_position = position / half_extents;
		float shape = 1.0 - dot(shape_position, shape_position);
		float edge = smoothstep(0.0, 0.34, shape);
		// Everything below works in box-normalised space so the funnel keeps its
		// proportions whatever the maw is scaled to.
		float radius = length(shape_position.xy);
		// Swirl faster toward the axis: a tornado, not a rotating slab.
		float swirl = TIME * 0.85 / (radius + 0.28) - shape_position.z * 1.7;
		float sine = sin(swirl);
		float cosine = cos(swirl);
		vec3 twisted = vec3(
			shape_position.x * cosine - shape_position.y * sine,
			shape_position.x * sine + shape_position.y * cosine,
			shape_position.z
		);
		vec3 metric_position = twisted * (max(half_extents.x, half_extents.z) / field_scale);
		vec3 advected = metric_position * 1.35 + vec3(0.0, 0.0, -TIME * 0.55);
		float turbulence = fbm3(advected);
		// Local +Z runs down the gullet, so the cloud is a wide wall at the lips
		// narrowing to a throat that swallows the light. The radius is chewed up
		// by the same noise, so the funnel never shows a clean analytic edge.
		float ragged = radius * (0.72 + turbulence * 0.78);
		float funnel = 1.0 - smoothstep(0.14 + max(-shape_position.z, 0.0) * 0.80, 1.05, ragged);
		float clouds = smoothstep(0.38, 0.72, turbulence) * funnel;
		float density = clouds * 0.30 * visibility * edge;
		float bolt_distance = bolt_field(shape_position * 1.35, bolt_seed);
		float bolt = exp(-bolt_distance * 30.0) * flash * edge;
		// The throat keeps a standing glow of its own, otherwise the vortex is
		// only readable during a strike and the maw reads as a plain black hole.
		float core = pow(clamp(1.0 - radius, 0.0, 1.0), 3.0) * edge * (0.30 + clouds * 1.8);
		vec3 sample_color = cloud_color * (0.20 + clouds * 3.2)
			+ lightning_color * (bolt * 8.0 + core * 0.07 + flash * clouds * 0.55);
		float sample_alpha = clamp(density + core * 0.03 + bolt * 0.36, 0.0, 1.0);
		accumulated += (1.0 - alpha) * sample_color * sample_alpha;
		alpha += (1.0 - alpha) * sample_alpha;
		position += step_vector;
		if (alpha > 0.97) {
			break;
		}
	}
	if (alpha < 0.005) {
		discard;
	}
	ALBEDO = accumulated;
	EMISSION = accumulated * (1.0 + flash * 2.3);
	ALPHA = alpha * visibility;
}
