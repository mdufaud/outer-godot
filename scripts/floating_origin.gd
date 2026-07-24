extends Node

const SHIFT_THRESHOLD := 1000.0

var total_shift := Vector3.ZERO

var _root: Node


func _ready() -> void:
	process_physics_priority = 100
	_root = get_parent()


func _physics_process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _root == null:
		return
	var origin := camera.global_position
	if origin.length() < SHIFT_THRESHOLD:
		return
	_shift(-origin)


func _shift(offset: Vector3) -> void:
	for node in _root.get_children():
		if node == self or not (node is Node3D):
			continue
		var body := node as Node3D
		if body is RigidBody3D:
			var transform := body.global_transform
			transform.origin += offset
			PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, transform)
			body.global_transform = transform
		else:
			body.global_position += offset
	total_shift += offset
	get_tree().call_group("origin_shift_listener", "apply_origin_shift", offset)
