extends PlanetBody

const ShapeProfileScript := preload("res://game/planets/shared/planet_shape_profile.gd")


func configure_planet(config: PlanetConfig) -> void:
	config.body_id = &"Luna"
	config.shape_profile = ShapeProfileScript.MOON
	config.surface.material_profile = ShapeProfileScript.MOON
	config.radius = 11.5
	config.surface.detail_radius = 11.5
	config.surface_gravity = 3.0
	config.rng_seed = 29017
	config.ocean.enabled = false
	config.atmosphere.enabled = false
