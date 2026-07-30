extends PlanetBody

const ShapeProfileScript := preload("res://game/planets/shared/planet_shape_profile.gd")


func configure_planet(config: PlanetConfig) -> void:
	config.body_id = &"Terra"
	config.shape_profile = ShapeProfileScript.EARTH
	config.surface.material_profile = ShapeProfileScript.EARTH
	config.radius = 46.0
	config.surface_gravity = 8.0
	config.rng_seed = 93847
	config.ocean.foam_scale = 1.6
	config.ocean.foam_distance = 0.85
	config.ocean.refraction_strength = 0.0025
	config.ocean.underwater_tint = Color(0.02, 0.38, 0.78)
	config.ocean.underwater_darkness = 0.22
