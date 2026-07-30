extends SceneTree

# The landing rocks are the only dry ground on Cyclops: a ship must find them at sea level, they must
# be solid, and they must not pile onto each other or hide at the poles under the static tornadoes.

const ReportScript := preload("res://tests/shared/test_report.gd")
const VariantsScript := preload("res://tests/shared/config_variants.gd")
const TestWorldScript := preload("res://tests/shared/test_world.gd")
const RocksScript := preload("res://game/planets/cyclops/cyclops_rocks.gd")

const BODY_ID := &"Cyclops"
# The polar caps belong to the two static tornadoes, so rocks stay away from the axis.
const MAX_POLAR_ALIGNMENT := 0.75

var report := ReportScript.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for variant in VariantsScript.build(BODY_ID):
		_test_rocks(variant.config, "Cyclops rocks %s" % variant.label)
	report.finish("Cyclops rocks tests", self)


func _test_rocks(config: PlanetConfig, label: String) -> void:
	var body := TestWorldScript.spawn_body(self, config)
	var rocks := RocksScript.new()
	rocks.setup(body)
	body.attach_rock_feature(rocks)
	var directions := body.get_landing_rock_directions()
	var radii := body.get_landing_rock_radii()
	var sea := body.sea_level()

	report.expect(directions.size() == config.weather.rock_count, "%s: rock count changed to %d" % [label, directions.size()])
	report.expect(radii.size() == directions.size(), "%s: a rock has no radius" % label)
	for index in directions.size():
		report.expect(radii[index] > 0.0 and radii[index] < sea * 0.25, "%s: rock %d has an unusable radius of %f" % [label, index, radii[index]])
		report.expect(absf((directions[index] as Vector3).y) < MAX_POLAR_ALIGNMENT, "%s: rock %d sits under a polar tornado" % [label, index])
	for first in directions.size():
		for second in range(first + 1, directions.size()):
			var separation: float = (directions[first] as Vector3).angle_to(directions[second])
			var required: float = (radii[first] + radii[second]) / sea
			if separation <= required:
				report.expect(false, "%s: rocks %d and %d overlap, %f apart with %f required" % [label, first, second, separation, required])
				return

	var meshes := 0
	var colliders := 0
	for child in rocks.get_children():
		var instance := child as MeshInstance3D
		if instance != null:
			meshes += 1
			report.expect(instance.mesh.get_surface_count() > 0, "%s: a rock mesh is empty" % label)
			report.expect_close(body.global_position.distance_to(instance.global_position), sea, 0.001, "%s: a rock floats off the water" % label)
		var collision := child as CollisionShape3D
		if collision != null:
			colliders += 1
			var shape := collision.shape as ConvexPolygonShape3D
			report.expect(shape != null and shape.points.size() > 0, "%s: a rock has no solid shape" % label)
	report.expect(meshes == directions.size(), "%s: %d rock meshes for %d rocks" % [label, meshes, directions.size()])
	report.expect(colliders == directions.size(), "%s: %d rock colliders for %d rocks" % [label, colliders, directions.size()])
	body.queue_free()
