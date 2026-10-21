class_name CelestialBody
extends AnimatableBody3D

var radius := 0.0
var surface_gravity := 0.0
var influence_radius := 0.0
var orbital_velocity := Vector3.ZERO
var has_ocean := false
var ocean_level := 0.0
var has_atmosphere := false
var atmosphere_scale := 0.0


func get_gravitational_parameter() -> float:
	return surface_gravity * radius * radius


func get_surface_radius_towards(_direction: Vector3) -> float:
	return radius


func get_collider_surface_radius(_direction: Vector3) -> float:
	return radius


func get_water_depth(_position_value: Vector3) -> float:
	return -INF


func get_environment_force(_world_position: Vector3) -> Vector3:
	return Vector3.ZERO


func has_weather_capability() -> bool:
	return false


func set_orbital_state(next_position: Vector3, next_velocity: Vector3) -> void:
	global_position = next_position
	orbital_velocity = next_velocity
