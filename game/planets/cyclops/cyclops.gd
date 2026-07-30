extends PlanetBody

const ShapeProfileScript := preload("res://game/planets/shared/planet_shape_profile.gd")
const StormsScript := preload("res://game/planets/cyclops/cyclops_storms.gd")
const RocksScript := preload("res://game/planets/cyclops/cyclops_rocks.gd")
const GeometryScript := preload("res://game/planets/cyclops/cyclops_geometry.gd")
const RockShader := preload("res://game/planets/cyclops/shaders/cyclops_rock.gdshader")
const CloudShader := preload("res://game/planets/cyclops/shaders/tornado.gdshader")
const FunnelShader := preload("res://game/planets/cyclops/shaders/tornado_funnel.gdshader")
const RainShader := preload("res://game/planets/cyclops/shaders/rain_lens.gdshader")


func configure_planet(config: PlanetConfig) -> void:
	config.body_id = &"Cyclops"
	config.shape_profile = ShapeProfileScript.CYCLOPS
	config.surface.material_profile = ShapeProfileScript.CYCLOPS
	config.radius = 145.0
	config.core_radius = 72.5
	config.surface_gravity = 14.0
	config.rng_seed = 114
	config.ocean.level = 20.0
	config.ocean.shallow_color = Color(0.008, 0.065, 0.06)
	config.ocean.deep_color = Color(0.0015, 0.012, 0.014)
	config.ocean.wave_strength = 0.9
	config.ocean.wave_scale = 9.0
	config.ocean.wave_speed = 1.35
	config.ocean.smoothness = 0.94
	config.ocean.depth_multiplier = 7.5
	config.ocean.alpha_multiplier = 12.0
	config.ocean.specular_color = Color(0.03, 0.10, 0.095)
	config.ocean.foam_scale = 2.3
	config.ocean.foam_distance = 1.7
	config.ocean.refraction_strength = 0.0015
	config.ocean.swell_height = 2.5
	config.ocean.swell_wavelength = 34.0
	config.ocean.swell_speed = 0.55
	config.ocean.underwater_tint = Color(0.004, 0.045, 0.05)
	config.ocean.underwater_darkness = 0.72
	config.atmosphere.enabled = false
	config.weather.enabled = true
	config.weather.contact_count = 9
	config.weather.rock_count = 5
	config.weather.rock_feature_script = RocksScript
	config.weather.feature_script = StormsScript
	config.weather.geometry = GeometryScript
	config.weather.rock_shader = RockShader
	config.weather.cloud_shader = CloudShader
	config.weather.funnel_shader = FunnelShader
	config.weather.rain_shader = RainShader
