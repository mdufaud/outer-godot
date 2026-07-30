class_name PlanetConfig
extends RefCounted

class OceanConfig extends RefCounted:
	var enabled := false
	var level := 0.0
	var shallow_color := Color.WHITE
	var deep_color := Color.BLACK
	var wave_strength := 0.0
	var wave_scale := 1.0
	var wave_speed := 0.0
	var smoothness := 0.0
	var depth_multiplier := 1.0
	var alpha_multiplier := 1.0
	var specular_color := Color.WHITE
	var foam_scale := 1.0
	var foam_distance := 0.0
	var refraction_strength := 0.0
	var swell_height := 0.0
	var swell_wavelength := 1.0
	var swell_speed := 0.0
	var underwater_tint := Color(0.1, 0.4, 0.5)
	var underwater_darkness := 0.45


class AtmosphereConfig extends RefCounted:
	var enabled := false
	var color := Color.WHITE
	var scale := 0.0
	var density_falloff := 1.0
	var wavelengths := Vector3.ONE
	var scattering_strength := 0.0
	var intensity := 0.0


class SurfaceConfig extends RefCounted:
	var style: StringName = &"terrain"
	var material_profile := 0
	var shore_color := Color(0.66, 0.58, 0.36)
	var land_low_color := Color(0.13, 0.34, 0.12)
	var land_high_color := Color(0.35, 0.24, 0.12)


class WeatherConfig extends RefCounted:
	var enabled := false
	var contact_count := 0
	var rock_count := 0
	var rock_feature_script: Script
	var feature_script: Script
	var geometry: Script
	var rock_shader: Shader
	var cloud_shader: Shader
	var funnel_shader: Shader
	var rain_shader: Shader


var body_id: StringName = &"Planet"
var shape_profile := 0
var radius := 0.0
var core_radius := 0.0
var surface_gravity := 0.0
var influence_scale := 30.0
var rng_seed := 0
var perturb_strength := 0.0
var quality_profile: StringName = &"desktop_high"
var ocean := OceanConfig.new()
var atmosphere := AtmosphereConfig.new()
var surface := SurfaceConfig.new()
var weather := WeatherConfig.new()
