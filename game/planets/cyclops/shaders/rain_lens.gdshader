shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength = 0.0;
uniform vec3 tint : source_color = vec3(0.035, 0.105, 0.098);
uniform int droplet_layers : hint_range(1, 3) = 3;

#include "res://game/shared/shaders/noise.gdshaderinc"

// A bead sits at most 0.5 * 0.72 + 0.17 from its cell centre, so besides its own cell only the
// side neighbour a pixel is within 1 - BEAD_REACH of can touch it, never a diagonal one.
const float BEAD_REACH = 0.53;

float bead_mask(vec2 offset, float radius) {
	return 1.0 - smoothstep(radius * 0.45, radius, length(offset));
}

// One cell's bead: x is its mask, yz the central differences of that mask over pixel_step (cell units).
vec3 droplet_cell(vec2 local, vec2 cell, vec2 neighbour, vec2 pixel_step, float life, float seed) {
	vec2 identifier = cell + neighbour + seed;
	float slot = floor(TIME / life + hash2(identifier * 1.37));
	if (hash2(identifier + slot * 7.31) < 0.74) {
		return vec3(0.0);
	}
	vec2 centre = vec2(hash2(identifier + slot * 3.17), hash2(identifier + slot * 5.91)) - 0.5;
	float age = fract(TIME / life + hash2(identifier * 1.37));
	float radius = mix(0.07, 0.17, hash2(identifier + slot * 11.3));
	radius *= smoothstep(0.0, 0.14, age) * (1.0 - smoothstep(0.7, 1.0, age));
	vec2 offset = local - neighbour - centre * 0.72;
	if (radius <= 0.0 || length(offset) >= radius) {
		return vec3(0.0);
	}
	return vec3(bead_mask(offset, radius),
		bead_mask(offset + vec2(pixel_step.x, 0.0), radius) - bead_mask(offset - vec2(pixel_step.x, 0.0), radius),
		bead_mask(offset + vec2(0.0, pixel_step.y), radius) - bead_mask(offset - vec2(0.0, pixel_step.y), radius));
}

// Cell-noise droplets: at most one bead per cell, respawning on its own timer so
// the pattern reads as falling rain instead of a frozen texture.
vec3 droplet_layer(vec2 position, vec2 pixel_step, float cell_size, float life, float seed) {
	vec2 scaled = position / cell_size;
	vec2 cell = floor(scaled);
	vec2 local = fract(scaled) - 0.5;
	vec2 local_step = pixel_step / cell_size;
	vec3 bead = droplet_cell(local, cell, vec2(0.0), local_step, life, seed);
	if (abs(local.x) > 1.0 - BEAD_REACH) {
		vec3 side = droplet_cell(local, cell, vec2(sign(local.x), 0.0), local_step, life, seed);
		bead = side.x > bead.x ? side : bead;
	}
	if (abs(local.y) > 1.0 - BEAD_REACH) {
		vec3 side = droplet_cell(local, cell, vec2(0.0, sign(local.y)), local_step, life, seed);
		bead = side.x > bead.x ? side : bead;
	}
	return bead;
}

// x is the bead mask, yz its central differences over pixel_step on the aspect-corrected screen.
vec3 droplet_field(vec2 position, vec2 pixel_step) {
	vec3 field = droplet_layer(position, pixel_step, 0.17, 2.3, 0.0);
	if (droplet_layers > 1) {
		vec3 layer = droplet_layer(position, pixel_step, 0.27, 3.1, 17.0) * 0.95;
		field = layer.x > field.x ? layer : field;
	}
	if (droplet_layers > 2) {
		vec3 layer = droplet_layer(position, pixel_step, 0.105, 1.7, 43.0) * 0.72;
		field = layer.x > field.x ? layer : field;
	}
	return field;
}

// A few slow beads sliding down the glass, biased to the lower half of the view.
float trickle_field(vec2 position) {
	vec2 scaled = vec2(position.x / 0.21, position.y);
	float column = floor(scaled.x);
	if (hash2(vec2(column, 21.7)) < 0.6) {
		return 0.0;
	}
	float speed = mix(0.03, 0.075, hash2(vec2(column, 3.7)));
	float head = fract(hash2(vec2(column, 9.1)) + TIME * speed);
	float lateral = (fract(scaled.x) - 0.5) + (hash2(vec2(column, 5.3)) - 0.5) * 0.55;
	float trail = smoothstep(-0.13, 0.0, position.y - head) * step(position.y, head);
	float bead = (1.0 - smoothstep(0.0, 0.022, abs(position.y - head)));
	return (1.0 - smoothstep(0.0, 0.05, abs(lateral))) * max(bead, trail * 0.4);
}

void fragment() {
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec2 position = SCREEN_UV * aspect;
	vec2 step_size = SCREEN_PIXEL_SIZE * aspect * 2.0;

	vec3 field = droplet_field(position, step_size);
	float beads = field.x;
	float trickles = trickle_field(SCREEN_UV) * smoothstep(0.1, 0.8, SCREEN_UV.y);
	float mask = max(beads, trickles);

	// Fake bead normal from the mask gradient, used to bend the view behind it.
	vec2 bead_normal = field.yz;
	float gradient_y = bead_normal.y;

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
