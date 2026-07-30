class_name PlanetDefaults
extends RefCounted

const PlanetShapeProfileScript := preload("res://game/planets/shared/planet_shape_profile.gd")

static func create_config() -> PlanetConfig:
	var config := PlanetConfig.new()
	config.body_id = &"Planet"
	config.shape_profile = PlanetShapeProfileScript.EARTH
	config.radius = 46.0
	config.core_radius = 0.0
	config.surface_gravity = 12.0
	config.influence_scale = 30.0
	config.rng_seed = 1337
	config.perturb_strength = 0.0
	config.quality_profile = &"desktop_high"

	config.ocean.enabled = true
	config.ocean.level = 0.0
	config.ocean.shallow_color = Color(0.31401902, 0.943, 0.75800556)
	config.ocean.deep_color = Color(0.05882353, 0.15686275, 0.35686275)
	config.ocean.wave_strength = 0.668
	config.ocean.wave_scale = 25.0
	config.ocean.wave_speed = 0.5
	config.ocean.smoothness = 0.927
	config.ocean.depth_multiplier = 15.0
	config.ocean.alpha_multiplier = 70.0
	config.ocean.specular_color = Color(0.9669199, 1.0, 0.8820755)
	config.ocean.foam_scale = 1.4
	config.ocean.foam_distance = 0.9
	config.ocean.refraction_strength = 0.003
	config.ocean.swell_height = 0.0
	config.ocean.swell_wavelength = 40.0
	config.ocean.swell_speed = 0.6
	config.ocean.underwater_tint = Color(0.1, 0.4, 0.5)
	config.ocean.underwater_darkness = 0.45

	config.atmosphere.enabled = true
	config.atmosphere.color = Color(0.18, 0.48, 1.0)
	config.atmosphere.scale = 0.322
	config.atmosphere.density_falloff = 4.3
	config.atmosphere.wavelengths = Vector3(700.0, 530.0, 460.0)
	config.atmosphere.scattering_strength = 20.0
	config.atmosphere.intensity = 0.25

	config.surface.style = &"terrain"
	config.surface.material_profile = PlanetShapeProfileScript.EARTH
	config.surface.shore_color = Color(0.66, 0.58, 0.36)
	config.surface.land_low_color = Color(0.13, 0.34, 0.12)
	config.surface.land_high_color = Color(0.35, 0.24, 0.12)
	return config
