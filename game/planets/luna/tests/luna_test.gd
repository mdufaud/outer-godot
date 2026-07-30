extends SceneTree

const ReportScript := preload("res://tests/shared/test_report.gd")
const ContractScript := preload("res://tests/shared/planet_contract.gd")
const VariantsScript := preload("res://tests/shared/config_variants.gd")
const TestWorldScript := preload("res://tests/shared/test_world.gd")

const BODY_ID := &"Luna"

var report := ReportScript.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for variant in VariantsScript.build(BODY_ID):
		ContractScript.run(self, variant.config, report, "Luna %s" % variant.label)
	_test_moon_of_terra()
	report.finish("Luna tests", self)


func _test_moon_of_terra() -> void:
	var config := TestWorldScript.authored_config(BODY_ID)
	var terra := TestWorldScript.authored_config(&"Terra")
	report.expect(not config.ocean.enabled, "Luna grew an ocean")
	report.expect(not config.atmosphere.enabled, "Luna grew an atmosphere")
	report.expect(config.radius < terra.radius, "Luna is no longer smaller than the planet it orbits")
	report.expect(config.surface_gravity < terra.surface_gravity, "Luna no longer pulls weaker than the planet it orbits")
	report.expect(TestWorldScript.get_entry(BODY_ID).orbit_parent_id == &"terra", "Luna stopped orbiting Terra")
