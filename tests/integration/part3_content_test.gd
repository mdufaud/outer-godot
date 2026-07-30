extends SceneTree

const SolarSystemManifestScript := preload("res://game/celestial/solar_system_manifest.gd")
const PlanetShapeProfileScript := preload("res://game/planets/shared/planet_shape_profile.gd")
const PlanetGeneratorScript := preload("res://game/planets/shared/planet_generator.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var entries: Array[CelestialEntry] = SolarSystemManifestScript.get_entries()
	var mirage: PlanetBody = entries[2].scene.instantiate()
	var config: PlanetConfig = mirage.create_planet_config()
	_expect(config.shape_profile == PlanetShapeProfileScript.MIRAGE, "Mirage shape profile changed")
	_expect(not config.ocean.enabled, "Mirage must remain dry")
	_expect(config.perturb_strength > 0.0, "Mirage must request vertex perturbation")
	for entry in entries:
		_expect(not entry.orbit_parent_id.is_empty(), "%s has no orbit parent" % entry.body_id)
	var directions := [Vector3(1.0, 2.0, 3.0).normalized(), Vector3(-2.0, 0.5, 1.0).normalized(), Vector3(0.1, -1.0, 0.3).normalized()]
	var first := PlanetGeneratorScript.new(config.shape_profile, config.rng_seed)
	var second := PlanetGeneratorScript.new(config.shape_profile, config.rng_seed)
	for direction in directions:
		var first_value: float = first.sample_factor(direction)
		_expect(is_finite(first_value), "Mirage produced a non-finite height")
		_expect(is_equal_approx(first_value, second.sample_factor(direction)), "Mirage generation is not deterministic")
	if failures.is_empty():
		print("Part 3 content tests passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
