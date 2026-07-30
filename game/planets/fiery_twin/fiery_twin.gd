extends PlanetBody

const ShapeProfileScript := preload("res://game/planets/shared/planet_shape_profile.gd")


func configure_planet(config: PlanetConfig) -> void:
	config.body_id = &"Fiery Twin"
	config.shape_profile = ShapeProfileScript.FIERY_TWIN
	config.surface.material_profile = ShapeProfileScript.FIERY_TWIN
	config.surface.style = &"lava"
	config.radius = 69.0
	config.surface_gravity = 10.0
	config.rng_seed = 0
	config.ocean.shallow_color = Color(1.0, 0.1909248, 0.0)
	config.ocean.deep_color = Color(1.0, 0.73324853, 0.0)
	config.ocean.wave_strength = 0.166
	config.ocean.wave_scale = 18.6
	config.ocean.wave_speed = 0.5
	config.ocean.smoothness = 0.842
	config.ocean.depth_multiplier = 39.1
	config.ocean.alpha_multiplier = 140.3
	config.ocean.specular_color = Color.WHITE
	config.atmosphere.enabled = false
	config.ocean.foam_scale = 0.9
	config.ocean.foam_distance = 0.0
	config.ocean.refraction_strength = 0.001
	config.ocean.underwater_tint = Color(0.62, 0.08, 0.015)
	config.ocean.underwater_darkness = 0.62
