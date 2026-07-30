extends SceneTree

const ReportScript := preload("res://tests/shared/test_report.gd")
const ContractScript := preload("res://tests/shared/planet_contract.gd")
const VariantsScript := preload("res://tests/shared/config_variants.gd")
const TestWorldScript := preload("res://tests/shared/test_world.gd")

const BODY_ID := &"Terra"
# Terra is the spawn world: it must stay a mix of sea and walkable coast, never one big ocean and
# never a dry rock. The bounds are loose on purpose, only the mix is the requirement.
const MIN_LAND_FRACTION := 0.1
const MAX_LAND_FRACTION := 0.9

var report := ReportScript.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for variant in VariantsScript.build(BODY_ID):
		ContractScript.run(self, variant.config, report, "Terra %s" % variant.label)
	_test_spawn_world()
	report.finish("Terra tests", self)


func _test_spawn_world() -> void:
	for variant in VariantsScript.build(BODY_ID):
		var config: PlanetConfig = variant.config
		var label := "Terra %s" % variant.label
		report.expect(config.ocean.enabled, "%s: the spawn world lost its ocean" % label)
		report.expect(config.atmosphere.enabled, "%s: the spawn world lost its atmosphere" % label)
		var body := TestWorldScript.spawn_body(self, config)
		var directions := TestWorldScript.sphere_directions()
		var land := 0
		for direction in directions:
			if body.get_surface_radius_towards(direction) > body.sea_level():
				land += 1
		var fraction := float(land) / float(directions.size())
		report.expect_between(fraction, MIN_LAND_FRACTION, MAX_LAND_FRACTION, "%s: land coverage leaves no playable mix of coast and sea" % label)
		body.queue_free()
