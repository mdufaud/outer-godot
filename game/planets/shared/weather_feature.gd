class_name WeatherFeature
extends Node3D


func setup(_body: PlanetBody) -> void:
	pass


func get_contacts() -> Array[Area3D]:
	return []


func get_visibility() -> float:
	return 0.0


func get_environment_force(_world_position: Vector3) -> Vector3:
	return Vector3.ZERO
