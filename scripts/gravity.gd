extends Node

var sources: Array = []


func register(source: Node3D) -> void:
	sources.append(source)


func unregister(source: Node3D) -> void:
	sources.erase(source)


func get_gravity(pos: Vector3) -> Vector3:
	var best_vec := Vector3.ZERO
	var best_mag := 0.0
	for s in sources:
		var to_center: Vector3 = s.global_position - pos
		var dist := to_center.length()
		if dist < 0.01 or dist > s.influence_radius:
			continue
		var mag: float = s.surface_gravity
		if dist > s.radius:
			mag = s.surface_gravity * s.radius * s.radius / (dist * dist)
		if mag > best_mag:
			best_mag = mag
			best_vec = to_center / dist * mag
	return best_vec


func get_strongest(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_mag := 0.0
	for s in sources:
		var dist: float = (s.global_position - pos).length()
		if dist < 0.01 or dist > s.influence_radius:
			continue
		var mag: float = s.surface_gravity
		if dist > s.radius:
			mag = s.surface_gravity * s.radius * s.radius / (dist * dist)
		if mag > best_mag:
			best_mag = mag
			best = s
	return best


func get_altitude(pos: Vector3) -> float:
	var s := get_strongest(pos)
	if s == null:
		return -1.0
	return (s.global_position - pos).length() - s.radius
