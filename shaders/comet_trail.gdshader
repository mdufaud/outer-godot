shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

// Interloper style plume: a raymarched volume, not a billboard. The box is
// anchored on the body with +Z pointing away from the sun; the density field is
// a coma sphere welded to the surface plus a widening cone streaming outward.

uniform vec3 head_color : source_color = vec3(0.78, 0.97, 1.0);
uniform vec3 tail_color : source_color = vec3(0.13, 0.40, 0.80);
uniform vec3 half_extents = vec3(124.0, 124.0, 250.0);
// Body centre along the box axis, in box space.
uniform float head_z = -240.0;
uniform float plume_length = 455.0;
uniform float body_radius = 20.7;
uniform float coma_radius = 52.0;
uniform float head_radius = 22.0;
uniform float mouth_radius = 40.0;
uniform float tail_radius = 124.0;
uniform float intensity = 1.9;
uniform float sigma = 3.4;
uniform float noise_scale = 0.022;
uniform float flow_speed = 9.0;
uniform int steps = 40;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying vec3 world_position;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float value_noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 blend_value = fract(p);
	blend_value = blend_value * blend_value * (3.0 - 2.0 * blend_value);
	float c000 = hash3(cell);
	float c100 = hash3(cell + vec3(1.0, 0.0, 0.0));
	float c010 = hash3(cell + vec3(0.0, 1.0, 0.0));
	float c110 = hash3(cell + vec3(1.0, 1.0, 0.0));
	float c001 = hash3(cell + vec3(0.0, 0.0, 1.0));
	float c101 = hash3(cell + vec3(1.0, 0.0, 1.0));
	float c011 = hash3(cell + vec3(0.0, 1.0, 1.0));
	float c111 = hash3(cell + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(c000, c100, blend_value.x), mix(c010, c110, blend_value.x), blend_value.y),
		mix(mix(c001, c101, blend_value.x), mix(c011, c111, blend_value.x), blend_value.y),
		blend_value.z
	);
}

float fbm3(vec3 p) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 2; octave++) {
		sum += value_noise3(p) * amplitude;
		p = p * 2.07 + vec3(11.3, 5.7, 3.1);
		amplitude *= 0.5;
	}
	return sum;
}

// Radius of the plume envelope at a given fraction along the axis.
float cone_radius(float along) {
	float mouth = mix(head_radius, mouth_radius, smoothstep(0.0, 0.22, along));
	return mix(mouth, tail_radius, pow(along, 0.6));
}

float sample_density(vec3 position) {
	vec3 rel = position - vec3(0.0, 0.0, head_z);
	float distance_to_body = length(rel);
	if (distance_to_body < body_radius) {
		return 0.0;
	}
	float along = clamp(rel.z / plume_length, 0.0, 1.0);
	float radial = length(rel.xy);
	float envelope = cone_radius(along);
	float cone = exp(-pow(radial / envelope, 2.0) * 3.2);
	// The cone only exists downwind; sunward of the body only the coma remains.
	cone *= smoothstep(-body_radius * 0.6, body_radius * 0.4, rel.z);
	// Thins out along the axis, then feathers away over the last fifth.
	cone *= mix(1.0, 0.45, along) * smoothstep(1.0, 0.78, along);
	float coma = exp(-pow(distance_to_body / coma_radius, 2.0) * 2.6) * 1.5;
	// Most samples along a ray sit outside the envelope: bail before the noise.
	if (cone + coma < 0.006) {
		return 0.0;
	}
	float flow_time = TIME * flow_speed;
	vec2 flutter = vec2(
		sin(rel.z * 0.031 - TIME * 1.1),
		cos(rel.z * 0.023 - TIME * 0.83)
	) * mix(2.0, 18.0, along);
	vec3 flow = vec3(
		(rel.xy + flutter) * noise_scale,
		(rel.z - flow_time) * noise_scale
	);
	// Squashed across the axis and stretched along it, so the noise reads as
	// filaments streaming outward rather than as blobs.
	float wisps = smoothstep(0.18, 0.72, fbm3(vec3(flow.xy * 2.6, flow.z * 0.55)));
	float packet_phase = (rel.z - flow_time) * 0.055;
	float packets = smoothstep(-0.35, 0.7, sin(packet_phase + sin(packet_phase * 0.37) * 1.8));
	float shedding = mix(1.0, mix(0.42, 1.4, packets), smoothstep(0.08, 0.72, along));
	// The coma stays smooth, the tail is where the streamers show.
	return coma * mix(0.75, 1.15, wisps) + cone * mix(0.08, 1.35, wisps) * shedding;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	mat4 world_to_box = inverse(MODEL_MATRIX);
	vec3 origin = (world_to_box * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 direction = normalize(mat3(world_to_box) * normalize(world_position - CAMERA_POSITION_WORLD));

	vec3 inverse_direction = 1.0 / direction;
	vec3 slab_a = (-half_extents - origin) * inverse_direction;
	vec3 slab_b = (half_extents - origin) * inverse_direction;
	vec3 near_slab = min(slab_a, slab_b);
	vec3 far_slab = max(slab_a, slab_b);
	float near_t = max(max(near_slab.x, near_slab.y), max(near_slab.z, 0.0));
	float far_t = min(min(far_slab.x, far_slab.y), far_slab.z);

	// Depth test is disabled so the volume is not clipped by the box faces;
	// opaque geometry occludes it analytically instead.
	float scene_depth = texture(depth_texture, SCREEN_UV).x;
	if (scene_depth > 0.0) {
		vec4 view_position = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
		far_t = min(far_t, length(view_position.xyz / view_position.w));
	}
	if (far_t <= near_t) {
		discard;
	}

	float span = far_t - near_t;
	float step_size = span / float(steps);
	float normalized_step = step_size / plume_length;
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	float t = near_t + step_size * jitter;
	vec3 accumulated = vec3(0.0);
	float transmittance = 1.0;
	for (int i = 0; i < steps; i++) {
		vec3 position = origin + direction * t;
		float density = sample_density(position);
		if (density > 0.004) {
			float along = clamp((position.z - head_z) / plume_length, 0.0, 1.0);
			vec3 emission = mix(head_color, tail_color, sqrt(along));
			accumulated += transmittance * emission * density * normalized_step;
			transmittance *= exp(-sigma * density * normalized_step);
			if (transmittance < 0.01) {
				break;
			}
		}
		t += step_size;
	}
	// Looking down the axis integrates the whole tail and would blow out to white;
	// a soft knee keeps the plume translucent from every angle.
	vec3 color = accumulated * intensity;
	ALBEDO = color / (1.0 + color * 0.5);
	ALPHA = 1.0;
}
