extends SceneTree

const ReportScript := preload("res://tests/shared/test_report.gd")
const ContractScript := preload("res://tests/shared/planet_contract.gd")
const VariantsScript := preload("res://tests/shared/config_variants.gd")
const TestWorldScript := preload("res://tests/shared/test_world.gd")
const ShapeProfileScript := preload("res://game/planets/shared/planet_shape_profile.gd")

const BODY_ID := &"Icey Twin"
# A glacier world is walkable ice with frozen seas trapped in its basins, not an ocean planet.
const MIN_ICE_FRACTION := 0.5

var report := ReportScript.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for variant in VariantsScript.build(BODY_ID):
		ContractScript.run(self, variant.config, report, "Icey Twin %s" % variant.label)
		_test_glacier_world(variant.config, "Icey Twin %s" % variant.label)
	report.finish("Icey Twin tests", self)


func _test_glacier_world(config: PlanetConfig, label: String) -> void:
	report.expect(config.ocean.enabled, "%s: the frozen seas are gone" % label)
	report.expect(config.atmosphere.enabled, "%s: the glacier world lost its atmosphere" % label)
	# The banded glacier shading reads the mesh height range, so the material profile must stay
	# GLACIER even though the shape profile is the twin's own.
	report.expect(config.surface.material_profile == ShapeProfileScript.GLACIER, "%s: the glacier banding was dropped" % label)
	report.expect(config.shape_profile == ShapeProfileScript.ICEY_TWIN, "%s: the twin shape was dropped" % label)
	var body := TestWorldScript.spawn_body(self, config)
	var directions := TestWorldScript.sphere_directions()
	var ice := 0
	for direction in directions:
		if body.get_surface_radius_towards(direction) > body.sea_level():
			ice += 1
	report.expect(float(ice) / float(directions.size()) > MIN_ICE_FRACTION, "%s: the sea flooded the ice shelf (%d of %d dry)" % [label, ice, directions.size()])
	body.queue_free()
