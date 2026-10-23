extends SceneTree

const SolarSystemManifestScript := preload("res://game/celestial/solar_system_manifest.gd")
const CelestialSystemScript := preload("res://game/celestial/celestial_system.gd")
const PlanetGeneratorScript := preload("res://game/planets/shared/planet_generator.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var entries: Array[CelestialEntry] = SolarSystemManifestScript.get_entries()
	var names: Array[String] = []
	for entry in entries:
		names.append(String(entry.body_id))
	_expect(names == ["Terra", "Luna", "Mirage", "Fiery Twin", "Icey Twin", "Cyclops", "Tumbling Bean", "Watchful Eye"], "Unexpected body roster: %s" % [names])
	var configs := {}
	for entry in entries:
		var body: PlanetBody = entry.scene.instantiate()
		configs[String(entry.body_id)] = body.create_planet_config()
	_expect(configs["Fiery Twin"].ocean.enabled and not configs["Fiery Twin"].atmosphere.enabled, "Fiery Twin effects changed")
	_expect(is_equal_approx(configs["Icey Twin"].ocean.level, -5.52), "Icey Twin ocean level changed")
	_expect(configs["Cyclops"].ocean.enabled and not configs["Cyclops"].atmosphere.enabled, "Cyclops effects changed")
	_expect(not configs["Tumbling Bean"].ocean.enabled and not configs["Watchful Eye"].ocean.enabled, "Cyclops moons must remain dry")
	_test_surface_profiles(entries)
	_test_native_sampler(configs.values())
	_test_orbit_helpers(entries)
	if failures.is_empty():
		print("Solar system tests passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_surface_profiles(entries: Array[CelestialEntry]) -> void:
	var directions := [Vector3(1.0, 2.0, 3.0).normalized(), Vector3(-2.0, 0.5, 1.0).normalized(), Vector3(0.1, -1.0, 0.3).normalized()]
	var samples := {}
	for entry in entries:
		var body: PlanetBody = entry.scene.instantiate()
		var config: PlanetConfig = body.create_planet_config()
		var generator := PlanetGeneratorScript.new(config.shape_profile, config.rng_seed)
		var values: Array[float] = []
		for direction in directions:
			values.append(generator.sample_factor(direction))
			samples[String(entry.body_id)] = values
		_expect(values.all(func(value: float) -> bool: return is_finite(value)), "%s produced invalid heights" % entry.body_id)
	_expect(samples["Fiery Twin"] != samples["Terra"], "Fiery Twin still uses Terra profile")
	_expect(samples["Tumbling Bean"] != samples["Luna"], "Tumbling Bean still uses Luna profile")


func _test_native_sampler(configs: Array) -> void:
	var profiles: Array = [[PlanetShapeProfile.GLACIER, 0]]
	for config: PlanetConfig in configs:
		profiles.append([config.shape_profile, config.rng_seed])
	if Native.enabled:
		_expect(ClassDB.class_exists(&"PlanetSampler"), "PlanetSampler is not loaded")
	var native_enabled := Native.enabled
	for profile in profiles:
		var results: Array[PackedByteArray] = []
		for enabled in [true, false]:
			Native.enabled = enabled
			var generator := PlanetGeneratorScript.new(profile[0], profile[1])
			var values := []
			for index in 256:
				var y := 1.0 - (float(index) + 0.5) / 128.0
				var angle := float(index) * PI * (3.0 - sqrt(5.0))
				var direction := Vector3(cos(angle) * sqrt(1.0 - y * y), y, sin(angle) * sqrt(1.0 - y * y))
				values.append(generator.sample_factor(direction))
				values.append(generator.sample_shading_data(direction))
			results.append(var_to_bytes(values))
		_expect(results[0] == results[1], "Native sampler diverges from GDScript for shape profile %d" % profile[0])
	Native.enabled = native_enabled


func _test_orbit_helpers(entries: Array[CelestialEntry]) -> void:
	var ids: Array[StringName] = [&"sun"]
	var positions: Array[Vector3] = [Vector3.ZERO]
	var mu: Array[float] = [345.0 * 345.0 * 50.0]
	var parents := {}
	for entry in entries:
		if not entry.binary_group_id.is_empty():
			continue
		var body: PlanetBody = entry.scene.instantiate()
		var config: PlanetConfig = body.create_planet_config()
		var id := entry.body_id.to_lower()
		ids.append(id)
		positions.append(entry.initial_position)
		mu.append(config.surface_gravity * config.radius * config.radius)
		parents[id] = entry.orbit_parent_id
	var velocities := CelestialSystemScript.compute_initial_velocities(ids, positions, mu, parents)
	var pair_mu := CelestialSystemScript.build_pair_mu(ids, mu, parents)
	_expect(velocities.size() == ids.size(), "Orbit helper velocity count changed")
	if Native.enabled:
		_expect(ClassDB.class_exists(&"NBodyKernel"), "NBodyKernel is not loaded")
	var native_enabled := Native.enabled
	var results := []
	for enabled in [true, false]:
		Native.enabled = enabled
		results.append(CelestialSystemScript.advance(CelestialSystemScript.pack_state(positions), CelestialSystemScript.pack_state(velocities), pair_mu, 1.0 / 120.0, 7200))
	Native.enabled = native_enabled
	_expect(var_to_bytes(results[0]) == var_to_bytes(results[1]), "Native N-body diverges from the GDScript integrator")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
