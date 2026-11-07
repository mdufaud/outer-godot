extends SceneTree

# An origin shift must move every body on screen in the same frame: sync_to_physics keeps an
# AnimatableBody3D node on its last stepped transform, which drew the planets a frame behind the
# shifted camera.

const ReportScript := preload("res://tests/shared/test_report.gd")
const FloatingOriginScript := preload("res://game/celestial/floating_origin.gd")

const OFFSET := Vector3(-800.0, 0.0, 600.0)

var report := ReportScript.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var body := AnimatableBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	body.add_child(shape)
	body.position = Vector3(1200.0, 0.0, -900.0)
	world.add_child(body)
	var floating_origin: FloatingOrigin = FloatingOriginScript.new()
	world.add_child(floating_origin)
	for _tick in 3:
		await physics_frame
	var before := body.global_position
	floating_origin._shift(OFFSET)
	report.expect(body.global_position.is_equal_approx(before + OFFSET), "The shift left the animatable body at %v instead of %v until the next step" % [body.global_position, before + OFFSET])
	for _tick in 3:
		await physics_frame
	report.expect(body.global_position.is_equal_approx(before + OFFSET), "After stepping the animatable body sits at %v instead of %v" % [body.global_position, before + OFFSET])
	report.finish("Floating origin tests", self)
