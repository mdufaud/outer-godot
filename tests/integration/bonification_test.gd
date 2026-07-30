extends SceneTree

const BonificationMathScript := preload("res://game/shared/bonification_math.gd")
const SolarSystemManifestScript := preload("res://game/celestial/solar_system_manifest.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_environment_feedback()
	_test_navigation_math()
	_test_body_settings()
	if failures.is_empty():
		print("Bonification tests passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_environment_feedback() -> void:
	_expect(is_zero_approx(BonificationMathScript.underwater_effect_target(-1.0)), "Underwater effect appears above the surface")
	_expect(BonificationMathScript.underwater_effect_target(1.5) > 0.99, "Underwater effect does not reach full strength at depth")
	_expect(BonificationMathScript.atmosphere_contains(Vector3(10.0, 0.0, 0.0), Vector3.ZERO, 10.0, 0.2), "Atmosphere boundary rejected an interior point")
	_expect(not BonificationMathScript.atmosphere_contains(Vector3(13.0, 0.0, 0.0), Vector3.ZERO, 10.0, 0.2), "Atmosphere boundary accepted an exterior point")


func _test_navigation_math() -> void:
	var components := BonificationMathScript.relative_velocity_components(
		Vector3(10.0, 5.0, -30.0), Vector3(2.0, 1.0, -10.0), Vector3.FORWARD, Vector3.UP, Vector3.RIGHT
	)
	_expect(components.is_equal_approx(Vector3(-8.0, -4.0, 20.0)), "Relative velocity components use the wrong reference frame: %s" % components)
	var hit := BonificationMathScript.ray_sphere_distance(Vector3(0.0, 0.0, -10.0), 2.0, Vector3.ZERO, Vector3.FORWARD)
	_expect(is_equal_approx(hit, 8.0), "Lock-on ray/sphere intersection is incorrect: %f" % hit)
	var miss := BonificationMathScript.ray_sphere_distance(Vector3(10.0, 0.0, -10.0), 2.0, Vector3.ZERO, Vector3.FORWARD)
	_expect(not is_finite(miss), "Lock-on ray selected a missed body")


func _test_body_settings() -> void:
	var by_name := {}
	for entry in SolarSystemManifestScript.get_entries():
		var body: PlanetBody = entry.scene.instantiate()
		by_name[String(entry.body_id)] = body.create_planet_config()
	var terra: PlanetConfig = by_name["Terra"]
	var icey: PlanetConfig = by_name["Icey Twin"]
	var fiery: PlanetConfig = by_name["Fiery Twin"]
	var cyclops: PlanetConfig = by_name["Cyclops"]
	_expect(terra.ocean.foam_distance > 0.0, "Terra ocean foam settings are missing")
	_expect(cyclops.ocean.underwater_darkness > terra.ocean.underwater_darkness, "Cyclops underwater profile should be darker than Terra")
	var terra_tint: Color = terra.ocean.underwater_tint
	var icey_tint: Color = icey.ocean.underwater_tint
	var fiery_tint: Color = fiery.ocean.underwater_tint
	var cyclops_tint: Color = cyclops.ocean.underwater_tint
	_expect(terra_tint.b > terra_tint.g and terra_tint.g > terra_tint.r, "Terra underwater tint should be blue-turquoise")
	_expect(icey_tint.b > icey_tint.g and icey_tint.g > icey_tint.r, "Icey Twin underwater tint should be cyan-turquoise")
	_expect(fiery_tint.r > fiery_tint.g and fiery_tint.r > fiery_tint.b, "Fiery Twin underwater tint should stay warm")
	_expect(terra_tint == Color(0.02, 0.38, 0.78) and is_equal_approx(terra.ocean.underwater_darkness, 0.22), "Terra underwater profile changed")
	_expect(icey_tint == Color(0.0, 0.68, 1.0) and is_equal_approx(icey.ocean.underwater_darkness, 0.30), "Icey Twin underwater profile changed")
	_expect(cyclops_tint == Color(0.004, 0.045, 0.05) and is_equal_approx(cyclops.ocean.underwater_darkness, 0.72), "Cyclops underwater profile changed")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
