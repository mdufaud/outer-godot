extends RefCounted

# Retuning a planet must not break its suite. Every contract runs against the authored config plus
# these rescaled copies: if an invariant only holds at the numbers currently in the planet script,
# one of the variants fails and the invariant gets fixed instead of the value being frozen.

const TestWorldScript := preload("res://tests/shared/test_world.gd")

# Ocean level moves by a small fraction of the radius only: a large shift would drown or drain a
# world on purpose, which is a design change and not something an invariant can survive.
const OCEAN_SHIFT_RATIO := 0.01


static func build(body_id: StringName) -> Array[Dictionary]:
	return [
		{"label": "authored", "config": _scaled(body_id, 1.0, 1.0, 0.0)},
		{"label": "radius x2", "config": _scaled(body_id, 2.0, 1.0, 0.0)},
		{"label": "radius x0.5", "config": _scaled(body_id, 0.5, 1.0, 0.0)},
		{"label": "gravity x3", "config": _scaled(body_id, 1.0, 3.0, 0.0)},
		{"label": "ocean raised", "config": _scaled(body_id, 1.0, 1.0, OCEAN_SHIFT_RATIO)},
	]


# Scaling the radius drags the core and the ocean level with it: the planet keeps its shape and only
# its size changes, which is what "resize a planet" means in this project.
static func _scaled(body_id: StringName, radius_scale: float, gravity_scale: float, ocean_shift_ratio: float) -> PlanetConfig:
	var config := TestWorldScript.authored_config(body_id)
	config.radius *= radius_scale
	config.core_radius *= radius_scale
	config.surface_gravity *= gravity_scale
	config.ocean.level = config.ocean.level * radius_scale + config.radius * ocean_shift_ratio
	return config
