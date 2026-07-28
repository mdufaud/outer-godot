class_name SolarSystemContent
extends RefCounted


static func get_body_definitions() -> Array[Dictionary]:
	return [
		{
			"name": "Terra",
			"position": Vector3(5633.62, 0.0, 0.0),
			"data": {
				"body_kind": "earth", "radius": 46.0, "gravity": 8.0, "seed": 93847, "ocean": true, "atmosphere": true,
				"ocean_foam_scale": 1.6, "ocean_foam_distance": 0.85, "ocean_refraction_strength": 0.0025,
				"underwater_tint": Color(0.03, 0.46, 0.68), "underwater_darkness": 0.32,
			},
		},
		{
			"name": "Luna",
			"position": Vector3(5416.27, 0.0, 0.0),
			"data": {
				"body_kind": "moon", "surface_style": "terrain", "radius": 11.5, "gravity": 3.0,
				"seed": 29017, "ocean": false,
				"atmosphere": false, "land_low_color": Color(0.17, 0.16, 0.15),
				"land_high_color": Color(0.58, 0.55, 0.5),
			},
		},
		{
			"name": "Mirage",
			"position": Vector3(0.0, 0.0, -1487.5),
			"data": {
				"body_kind": "mirage", "surface_style": "terrain", "radius": 34.0, "gravity": 7.0,
				"seed": 4711, "ocean": false, "perturb_strength": 0.03,
				"atmosphere": true, "atmosphere_scale": 0.42, "atmosphere_density_falloff": 3.2,
				"atmosphere_wavelengths": Vector3(460.0, 540.0, 700.0),
				"atmosphere_scattering_strength": 24.0, "atmosphere_intensity": 0.3,
			},
		},
		{
			"name": "Fiery Twin",
			"position": Vector3(2537.59, 0.0, 109.48),
			"data": {
				"body_kind": "fiery_twin", "surface_style": "lava", "radius": 69.0, "gravity": 10.0,
				"seed": 0, "ocean": true,
				"ocean_shallow_color": Color(1.0, 0.1909248, 0.0),
				"ocean_deep_color": Color(1.0, 0.73324853, 0.0), "ocean_wave_strength": 0.166,
				"ocean_wave_scale": 18.6, "ocean_wave_speed": 0.5, "ocean_smoothness": 0.842,
				"ocean_depth_multiplier": 39.1, "ocean_alpha_multiplier": 140.3,
				"ocean_specular_color": Color.WHITE, "atmosphere": false,
				"ocean_foam_scale": 0.9, "ocean_foam_distance": 0.0, "ocean_refraction_strength": 0.001,
				"underwater_tint": Color(0.62, 0.08, 0.015), "underwater_darkness": 0.62,
			},
		},
		{
			"name": "Icey Twin",
			"position": Vector3(2998.74, 0.0, 0.0),
			"data": {
				"body_kind": "glacier", "surface_style": "terrain", "radius": 69.0, "gravity": 10.0,
				"seed": 114, "ocean": true,
				"ocean_shallow_color": Color(0.0, 0.5, 0.43362522),
				"ocean_deep_color": Color(0.0, 0.8329468, 1.0), "ocean_wave_strength": 0.759,
				"ocean_wave_scale": 20.0, "ocean_wave_speed": 0.5, "ocean_smoothness": 0.882,
				"ocean_depth_multiplier": 15.0, "ocean_alpha_multiplier": 70.0,
				"ocean_foam_scale": 1.8, "ocean_foam_distance": 1.1, "ocean_refraction_strength": 0.002,
				"underwater_tint": Color(0.04, 0.44, 0.55), "underwater_darkness": 0.50,
				"atmosphere": true, "atmosphere_scale": 0.588, "atmosphere_density_falloff": 6.0,
				"atmosphere_wavelengths": Vector3(678.0, 815.8, 479.9),
				"atmosphere_scattering_strength": 26.51, "atmosphere_intensity": 0.25,
			},
		},
		{
			"name": "Cyclops",
			"position": Vector3(11456.53, 0.0, 0.0),
			"data": {
				"body_kind": "cyclops", "surface_style": "terrain", "radius": 145.0, "gravity": 14.0,
				"core_radius": 72.5,
				"seed": 114, "ocean": true,
				"ocean_level": 20.0, "ocean_shallow_color": Color(0.008, 0.065, 0.06),
				"ocean_deep_color": Color(0.0015, 0.012, 0.014), "ocean_wave_strength": 0.9,
				"ocean_wave_scale": 9.0, "ocean_wave_speed": 1.35, "ocean_smoothness": 0.94,
				"ocean_depth_multiplier": 7.5, "ocean_alpha_multiplier": 12.0,
				"ocean_specular_color": Color(0.03, 0.10, 0.095), "atmosphere": false,
				"ocean_foam_scale": 2.3, "ocean_foam_distance": 1.7, "ocean_refraction_strength": 0.0015,
				"underwater_tint": Color(0.004, 0.045, 0.05), "underwater_darkness": 0.72,
			},
		},
		{
			"name": "Tumbling Bean",
			"position": Vector3(11078.87, 0.0, 0.0),
			"data": {
				"body_kind": "asteroid", "surface_style": "terrain", "radius": 25.2, "gravity": 2.6,
				"seed": 0, "ocean": false,
				"atmosphere": true, "atmosphere_color": Color(0.2, 0.42, 0.38),
				"atmosphere_scale": 0.48, "atmosphere_density_falloff": 2.4,
				"atmosphere_wavelengths": Vector3(670.0, 590.0, 520.0),
				"atmosphere_scattering_strength": 32.0, "atmosphere_intensity": 0.62,
			},
		},
		{
			"name": "Watchful Eye",
			"position": Vector3(10676.6, 0.0, 0.0),
			"data": {
				"body_kind": "watchful_eye", "surface_style": "terrain", "radius": 20.7, "gravity": 8.0,
				"seed": 7, "ocean": false,
				"atmosphere": false,
			},
		},
	]
