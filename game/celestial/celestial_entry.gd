class_name CelestialEntry
extends RefCounted

var body_id: StringName
var scene: PackedScene
var initial_position := Vector3.ZERO
var orbit_parent_id: StringName
var binary_group_id: StringName


func _init(
	entry_body_id: StringName,
	entry_scene: PackedScene,
	entry_position: Vector3,
	entry_orbit_parent_id: StringName,
	entry_binary_group_id: StringName = &""
) -> void:
	body_id = entry_body_id
	scene = entry_scene
	initial_position = entry_position
	orbit_parent_id = entry_orbit_parent_id
	binary_group_id = entry_binary_group_id
