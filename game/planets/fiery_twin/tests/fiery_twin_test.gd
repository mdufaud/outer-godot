extends SceneTree

const ReportScript := preload("res://tests/shared/test_report.gd")
const ContractScript := preload("res://tests/shared/planet_contract.gd")
const VariantsScript := preload("res://tests/shared/config_variants.gd")
const TestWorldScript := preload("res://tests/shared/test_world.gd")

const BODY_ID := &"Fiery Twin"

var report := ReportScript.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for variant in VariantsScript.build(BODY_ID):
		ContractScript.run(self, variant.config, report, "Fiery Twin %s" % variant.label)
	_test_lava_world()
	_test_binary_pair()
	report.finish("Fiery Twin tests", self)


func _test_lava_world() -> void:
	var config := TestWorldScript.authored_config(BODY_ID)
	report.expect(config.surface.style == &"lava", "Fiery Twin lost its lava surface")
	report.expect(config.ocean.enabled, "Fiery Twin lost its lava sea")
	report.expect(not config.atmosphere.enabled, "Fiery Twin grew an atmosphere over the lava")
	# The lava sea is what makes it fiery: it must pool in the basins and leave crust to walk on.
	var body := TestWorldScript.spawn_body(self, config)
	var molten := 0
	var directions := TestWorldScript.sphere_directions()
	for direction in directions:
		if body.get_surface_radius_towards(direction) < body.sea_level():
			molten += 1
	report.expect(molten > 0, "Fiery Twin has no lava left")
	report.expect(molten < directions.size(), "Fiery Twin is one solid lava ball with no crust")
	body.queue_free()


# The twins are simulated as one barycentre, which only holds while they stay a matched pair.
func _test_binary_pair() -> void:
	var fiery := TestWorldScript.authored_config(BODY_ID)
	var icey := TestWorldScript.authored_config(&"Icey Twin")
	var fiery_entry := TestWorldScript.get_entry(BODY_ID)
	var icey_entry := TestWorldScript.get_entry(&"Icey Twin")
	report.expect(is_equal_approx(fiery.radius, icey.radius), "The twins are no longer the same size")
	report.expect(is_equal_approx(fiery.surface_gravity, icey.surface_gravity), "The twins no longer pull equally")
	report.expect(not fiery_entry.binary_group_id.is_empty(), "Fiery Twin left its binary group")
	report.expect(fiery_entry.binary_group_id == icey_entry.binary_group_id, "The twins are in different binary groups")
	report.expect(fiery.shape_profile != icey.shape_profile, "The twins share one shape profile")
