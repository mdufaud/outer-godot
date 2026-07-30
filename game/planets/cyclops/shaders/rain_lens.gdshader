shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength = 0.0;
uniform vec3 tint : source_color = vec3(0.035, 0.105, 0.098);
uniform int droplet_layers : hint_range(1, 3) = 3;

float hash(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453);
}

// Cell-noise droplets: at most one bead per cell, respawning on its own timer so
// the pattern reads as falling rain instead of a frozen texture.
float droplet_layer(vec2 position, float cell_size, float life, float seed) {
	vec2 scaled = position / cell_size;
	vec2 cell = floor(scaled);
	vec2 local = fract(scaled) - 0.5;
	float mask = 0.0;
	for (int offset_x = -1; offset_x <= 1; offset_x++) {
		for (int offset_y = -1; offset_y <= 1; offset_y++) {
			vec2 neighbour = vec2(float(offset_x), float(offset_y));
			vec2 identifier = cell + neighbour + seed;
			float slot = floor(TIME / life + hash(identifier * 1.37));
			if (hash(identifier + slot * 7.31) < 0.74) {
				continue;
			}
			vec2 centre = vec2(hash(identifier + slot * 3.17), hash(identifier + slot * 5.91)) - 0.5;
			float age = fract(TIME / life + hash(identifier * 1.37));
			float radius = mix(0.07, 0.17, hash(identifier + slot * 11.3));
			radius *= smoothstep(0.0, 0.14, age) * (1.0 - smoothstep(0.7, 1.0, age));
			float distance_to_centre = length(local - neighbour - centre * 0.72);
			mask = max(mask, smoothstep(radius, radius * 0.45, distance_to_centre));
		}
	}
	return mask;
}

float droplet_field(vec2 position) {
	float field = droplet_layer(position, 0.17, 2.3, 0.0);
	if (droplet_layers > 1) {
		field = max(field, droplet_layer(position, 0.27, 3.1, 17.0) * 0.95);
	}
	if (droplet_layers > 2) {
		field = max(field, droplet_layer(position, 0.105, 1.7, 43.0) * 0.72);
	}
	return field;
}

// A few slow beads sliding down the glass, biased to the lower half of the view.
float trickle_field(vec2 position) {
	vec2 scaled = vec2(position.x / 0.21, position.y);
	float column = floor(scaled.x);
	if (hash(vec2(column, 21.7)) < 0.6) {
		return 0.0;
	}
	float speed = mix(0.03, 0.075, hash(vec2(column, 3.7)));
	float head = fract(hash(vec2(column, 9.1)) + TIME * speed);
	float lateral = (fract(scaled.x) - 0.5) + (hash(vec2(column, 5.3)) - 0.5) * 0.55;
	float trail = smoothstep(0.13, 0.0, position.y - head) * step(position.y, head);
	float bead = smoothstep(0.022, 0.0, abs(position.y - head));
	return smoothstep(0.05, 0.0, abs(lateral)) * max(bead, trail * 0.4);
}

void fragment() {
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 position = SCREEN_UV * aspect;
	vec2 step_size = SCREEN_PIXEL_SIZE * aspect * 2.0;

	float beads = droplet_field(position);
	float trickles = trickle_field(SCREEN_UV) * smoothstep(0.1, 0.8, SCREEN_UV.y);
	float mask = max(beads, trickles);

	// Fake bead normal from the mask gradient, used to bend the view behind it.
	float gradient_x = droplet_field(position + vec2(step_size.x, 0.0)) - droplet_field(position - vec2(step_size.x, 0.0));
	float gradient_y = droplet_field(position + vec2(0.0, step_size.y)) - droplet_field(position - vec2(0.0, step_size.y));
	vec2 bead_normal = vec2(gradient_x, gradient_y);

	// Real beads invert and magnify what is behind them.
	vec2 refracted_uv = clamp(
		SCREEN_UV - bead_normal * 0.035 - (SCREEN_UV - 0.5) * beads * 0.02,
		vec2(0.001), vec2(0.999)
	);
	vec3 colour = texture(screen_texture, refracted_uv).rgb;

	// Thin sliver of light on the upper edge only, so the bead reads as a lens
	// rather than an outlined ring. Beads must stay legible against a near-black
	// sea, where refraction alone shows nothing.
	float sliver = smoothstep(0.04, 0.22, max(-gradient_y, 0.0));
	float shade = smoothstep(0.04, 0.22, max(gradient_y, 0.0));
	colour = mix(colour, colour * 0.86 + tint * 0.55, 0.24);
	colour += tint * sliver * 3.2;
	colour *= 1.0 - shade * 0.45;

	COLOR = vec4(colour, clamp(mask, 0.0, 1.0) * strength * 0.85);
}
