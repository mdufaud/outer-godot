extends PlanetBody

const ShapeProfileScript := preload("res://game/planets/shared/planet_shape_profile.gd")


func configure_planet(config: PlanetConfig) -> void:
	config.body_id = &"Icey Twin"
	config.shape_profile = ShapeProfileScript.ICEY_TWIN
	config.surface.material_profile = ShapeProfileScript.GLACIER
	config.radius = 69.0
	config.surface_gravity = 10.0
	config.rng_seed = 114
	config.ocean.level = -5.52
	config.ocean.shallow_color = Color(0.0, 0.5, 0.43362522)
	config.ocean.deep_color = Color(0.0, 0.8329468, 1.0)
	config.ocean.wave_strength = 0.759
	config.ocean.wave_scale = 20.0
	config.ocean.wave_speed = 0.5
	config.ocean.smoothness = 0.882
	config.ocean.depth_multiplier = 15.0
	config.ocean.alpha_multiplier = 70.0
	config.ocean.foam_scale = 1.8
	config.ocean.foam_distance = 1.1
	config.ocean.refraction_strength = 0.002
	config.ocean.underwater_tint = Color(0.0, 0.68, 1.0)
	config.ocean.underwater_darkness = 0.30
	config.atmosphere.scale = 0.588
	config.atmosphere.density_falloff = 6.0
	config.atmosphere.wavelengths = Vector3(678.0, 815.8, 479.9)
	config.atmosphere.scattering_strength = 26.51
	config.atmosphere.intensity = 0.25
