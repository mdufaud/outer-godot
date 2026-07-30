extends RefCounted


static func underwater_effect_target(depth: float) -> float:
	return smoothstep(-0.12, 1.5, depth) if is_finite(depth) else 0.0


static func atmosphere_contains(position_value: Vector3, center: Vector3, body_radius: float, atmosphere_scale: float) -> bool:
	return position_value.distance_to(center) < body_radius * (1.0 + atmosphere_scale)


static func relative_velocity_components(ship_velocity: Vector3, body_velocity: Vector3, direction_to_body: Vector3, camera_up: Vector3, camera_right: Vector3) -> Vector3:
	var direction := direction_to_body.normalized()
	var horizontal := direction.cross(camera_up).normalized()
	if horizontal.length_squared() < 0.0001:
		horizontal = camera_right.normalized()
	if horizontal.dot(camera_right) < 0.0:
		horizontal = -horizontal
	var vertical := direction.cross(horizontal).normalized()
	if vertical.dot(camera_up) < 0.0:
		vertical = -vertical
	var relative := ship_velocity - body_velocity
	return Vector3(-relative.dot(horizontal), -relative.dot(vertical), relative.dot(direction))


static func ray_sphere_distance(center: Vector3, radius: float, origin: Vector3, direction: Vector3) -> float:
	var offset := origin - center
	var b := offset.dot(direction)
	var c := offset.length_squared() - radius * radius
	var discriminant := b * b - c
	if discriminant < 0.0:
		return INF
	var root := sqrt(discriminant)
	return maxf(-b - root, 0.0) if -b + root >= 0.0 else INF
