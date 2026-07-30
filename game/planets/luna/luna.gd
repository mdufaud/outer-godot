extends PlanetBody

const ShapeProfileScript := preload("res://game/planets/shared/planet_shape_profile.gd")


func configure_planet(config: PlanetConfig) -> void:
	config.body_id = &"Luna"
	config.shape_profile = ShapeProfileScript.MOON
	config.surface.material_profile = ShapeProfileScript.MOON
	config.radius = 11.5
	config.surface_gravity = 3.0
	config.rng_seed = 29017
	config.ocean.enabled = false
	config.atmosphere.enabled = false
	config.surface.land_low_color = Color(0.17, 0.16, 0.15)
	config.surface.land_high_color = Color(0.58, 0.55, 0.5)
