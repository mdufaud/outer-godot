extends PlanetBody

const ShapeProfileScript := preload("res://game/planets/shared/planet_shape_profile.gd")


func configure_planet(config: PlanetConfig) -> void:
	config.body_id = &"Tumbling Bean"
	config.shape_profile = ShapeProfileScript.ASTEROID
	config.surface.material_profile = ShapeProfileScript.ASTEROID
	config.radius = 25.2
	config.surface_gravity = 2.6
	config.rng_seed = 0
	config.ocean.enabled = false
	config.atmosphere.color = Color(0.2, 0.42, 0.38)
	config.atmosphere.scale = 0.48
	config.atmosphere.density_falloff = 2.4
	config.atmosphere.wavelengths = Vector3(670.0, 590.0, 520.0)
	config.atmosphere.scattering_strength = 32.0
	config.atmosphere.intensity = 0.62
