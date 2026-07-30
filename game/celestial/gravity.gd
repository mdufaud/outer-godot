class_name GravityService
extends Node

var sources: Array = []


func register(source: Node3D) -> void:
	if not sources.has(source):
		sources.append(source)


func unregister(source: Node3D) -> void:
	sources.erase(source)


func get_gravity(pos: Vector3) -> Vector3:
	var total := Vector3.ZERO
	for source in sources:
		if not is_instance_valid(source):
			continue
		total += _gravity_from(source, pos)
	return total


func get_strongest(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_magnitude := 0.0
	for source in sources:
		if not is_instance_valid(source):
			continue
		var acceleration := _gravity_from(source, pos)
		var magnitude := acceleration.length_squared()
		if magnitude > best_magnitude:
			best_magnitude = magnitude
			best = source
	return best


func get_nearest_surface(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_altitude := INF
	for source in sources:
		if not is_instance_valid(source) or not source.has_method("get_surface_radius_towards"):
			continue
		var direction: Vector3 = pos - source.global_position
		if direction.length_squared() < 0.0001:
			continue
		if direction.length() > float(source.get("influence_radius")):
			continue
		var surface_radius: float = source.get_surface_radius_towards(direction.normalized())
		var altitude: float = direction.length() - surface_radius
		if altitude < best_altitude:
			best_altitude = altitude
			best = source
	return best


func get_altitude(pos: Vector3) -> float:
	var source := get_strongest(pos)
	if source == null:
		return -1.0
	var direction := pos - source.global_position
	if direction.length_squared() < 0.0001:
		return -1.0
	var surface_radius := float(source.get("radius"))
	if source.has_method("get_surface_radius_towards"):
		surface_radius = source.get_surface_radius_towards(direction.normalized())
	return direction.length() - surface_radius


func get_relative_gravity(pos: Vector3, reference: Node3D) -> Vector3:
	return get_gravity(pos) - get_gravity(reference.global_position)


func get_gravity_from(source: Node3D, pos: Vector3) -> Vector3:
	if not is_instance_valid(source):
		return Vector3.ZERO
	return _gravity_from(source, pos)


func _gravity_from(source: Node3D, pos: Vector3) -> Vector3:
	var to_center := source.global_position - pos
	var distance := to_center.length()
	if distance < 0.01 or distance > float(source.get("influence_radius")):
		return Vector3.ZERO
	var radius := float(source.get("radius"))
	if source.has_method("get_surface_radius_towards"):
		radius = source.get_surface_radius_towards((pos - source.global_position).normalized())
	var surface_gravity := float(source.get("surface_gravity"))
	var magnitude := surface_gravity
	if distance > radius:
		magnitude = surface_gravity * radius * radius / (distance * distance)
	return to_center / distance * magnitude
