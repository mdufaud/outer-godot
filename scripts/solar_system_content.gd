class_name SolarSystemContent
extends RefCounted


static func get_body_definitions() -> Array[Dictionary]:
	return [
		{
			"name": "Terra",
			"position": Vector3(5633.62, 0.0, 0.0),
			"data": {
				"body_kind": "earth", "radius": 46.0, "gravity": 8.0, "seed": 93847,
				"velocity": Vector3(0.0, 0.0, -33.6811247882), "ocean": true, "atmosphere": true,
			},
		},
		{
			"name": "Luna",
			"position": Vector3(5416.27, 0.0, 0.0),
			"data": {
				"body_kind": "moon", "surface_style": "terrain", "radius": 11.5, "gravity": 3.0,
				"seed": 29017, "velocity": Vector3(0.0, 0.0, -24.6505740298), "ocean": false,
				"atmosphere": false, "land_low_color": Color(0.17, 0.16, 0.15),
				"land_high_color": Color(0.58, 0.55, 0.5),
			},
		},
		{
			"name": "Fiery Twin",
			"position": Vector3(2537.59, 0.0, 109.48),
			"data": {
				"body_kind": "fiery_twin", "surface_style": "lava", "radius": 69.0, "gravity": 10.0,
				"seed": 0, "velocity": Vector3(0.0, 0.0, -55.3247124529), "ocean": true,
				"ocean_shallow_color": Color(1.0, 0.1909248, 0.0),
				"ocean_deep_color": Color(1.0, 0.73324853, 0.0), "ocean_wave_strength": 0.166,
				"ocean_wave_scale": 18.6, "ocean_wave_speed": 0.5, "ocean_smoothness": 0.842,
				"ocean_depth_multiplier": 39.1, "ocean_alpha_multiplier": 140.3,
				"ocean_specular_color": Color.WHITE, "atmosphere": false,
			},
		},
		{
			"name": "Icey Twin",
			"position": Vector3(2998.74, 0.0, 0.0),
			"data": {
				"body_kind": "glacier", "surface_style": "terrain", "radius": 69.0, "gravity": 10.0,
				"seed": 114, "velocity": Vector3(0.0, 0.0, -38.6544020779), "ocean": true,
				"ocean_shallow_color": Color(0.0, 0.5, 0.43362522),
				"ocean_deep_color": Color(0.0, 0.8329468, 1.0), "ocean_wave_strength": 0.759,
				"ocean_wave_scale": 20.0, "ocean_wave_speed": 0.5, "ocean_smoothness": 0.882,
				"ocean_depth_multiplier": 15.0, "ocean_alpha_multiplier": 70.0,
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
				"seed": 114, "velocity": Vector3(0.0, 0.0, -24.1230325623), "ocean": true,
				"ocean_level": 20.0, "ocean_shallow_color": Color(0.035, 0.19, 0.2),
				"ocean_deep_color": Color(0.005, 0.045, 0.065), "ocean_wave_strength": 1.25,
				"ocean_wave_scale": 34.0, "ocean_wave_speed": 1.35, "ocean_smoothness": 0.94,
				"ocean_depth_multiplier": 5.0, "ocean_alpha_multiplier": 3.8,
				"ocean_specular_color": Color(0.28, 0.5, 0.54), "atmosphere": false,
			},
		},
		{
			"name": "Tumbling Bean",
			"position": Vector3(11078.87, 0.0, 0.0),
			"data": {
				"body_kind": "asteroid", "surface_style": "terrain", "radius": 25.2, "gravity": 2.6,
				"seed": 0, "velocity": Vector3(0.0, 0.0, -1.7264993484), "ocean": false,
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
				"body_kind": "watchful_eye", "surface_style": "terrain", "radius": 20.7, "gravity": 4.5,
				"seed": 7, "velocity": Vector3(0.0, 0.0, -8.5365801115), "ocean": false,
				"atmosphere": false,
			},
		},
	]
