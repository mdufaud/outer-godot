extends SceneTree

const ReportScript := preload("res://tests/shared/test_report.gd")
const ContractScript := preload("res://tests/shared/planet_contract.gd")
const VariantsScript := preload("res://tests/shared/config_variants.gd")
const TestWorldScript := preload("res://tests/shared/test_world.gd")

const BODY_ID := &"Cyclops"

var report := ReportScript.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for variant in VariantsScript.build(BODY_ID):
		ContractScript.run(self, variant.config, report, "Cyclops %s" % variant.label)
		_test_storm_world(variant.config, "Cyclops %s" % variant.label)
	_test_moons()
	report.finish("Cyclops tests", self)


# Cyclops is the drowned storm world: the sea covers the terrain everywhere, the sea bed stays a
# real floor above the core, and the cloud deck sits over open water.
func _test_storm_world(config: PlanetConfig, label: String) -> void:
	report.expect(config.ocean.enabled, "%s: the storm ocean is gone" % label)
	report.expect(config.weather.enabled, "%s: the storms are gone" % label)
	report.expect(not config.atmosphere.enabled, "%s: an atmosphere was added over the storm deck" % label)
	report.expect(config.core_radius > 0.0, "%s: the ocean lost its floor" % label)
	report.expect(config.weather.rock_count > 0, "%s: the only dry ground, the landing rocks, is gone" % label)
	var body := TestWorldScript.spawn_body(self, config)
	var sea := body.sea_level()
	var deepest := INF
	for direction in TestWorldScript.sphere_directions():
		deepest = minf(deepest, body.get_surface_radius_towards(direction))
	report.expect(deepest > body.get_core_radius() * 0.5, "%s: the sea bed collapsed towards the core" % label)
	report.expect(sea > body.get_core_radius(), "%s: the abyss has no depth" % label)
	report.expect(body.get_weather_deck_inner_radius() > sea, "%s: the cloud deck dips into the sea" % label)
	report.expect(is_equal_approx(body.global_position.distance_to(body.get_landing_point(Vector3.UP)), sea), "%s: landing no longer happens on the water" % label)
	body.queue_free()


func _test_moons() -> void:
	for moon_id in [&"Tumbling Bean", &"Watchful Eye"]:
		var entry := TestWorldScript.get_entry(moon_id)
		report.expect(entry.orbit_parent_id == &"cyclops", "%s stopped orbiting Cyclops" % moon_id)
		var moon := TestWorldScript.authored_config(moon_id)
		report.expect(not moon.ocean.enabled, "%s must stay dry, Cyclops is the water world" % moon_id)
		report.expect(moon.radius < TestWorldScript.authored_config(BODY_ID).radius, "%s is no longer smaller than Cyclops" % moon_id)
