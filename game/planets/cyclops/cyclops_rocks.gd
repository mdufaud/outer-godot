class_name CyclopsRocks
extends Node3D

var body: PlanetBody
var _rock_directions: Array[Vector3] = []
var _rock_radii: Array[float] = []


func setup(next_body: PlanetBody) -> void:
	body = next_body


func _ready() -> void:
	_build_landing_rocks()


func get_directions() -> Array[Vector3]:
	return _rock_directions


func get_radii() -> Array[float]:
	return _rock_radii


func _surface_basis(direction: Vector3, roll: float) -> Basis:
	var reference := Vector3.UP if absf(direction.y) < 0.92 else Vector3.FORWARD
	var tangent := reference.cross(direction).normalized()
	var bitangent := tangent.cross(direction).normalized()
	return Basis(tangent, direction, bitangent).rotated(direction, roll)


func _build_landing_rocks() -> void:
	if not body.weather_enabled or body.config.weather.rock_shader == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = body.rng_seed * 6211 + 203
	var material := ShaderMaterial.new()
	material.shader = body.config.weather.rock_shader
	var ocean_radius := body.sea_level()
	for index in body.config.weather.rock_count:
		var direction := _choose_landing_rock_direction(rng)
		var rock_radius := rng.randf_range(0.042, 0.061) * ocean_radius
		var rock_height := rng.randf_range(0.061, 0.091) * ocean_radius
		var geometry := _build_landing_rock_geometry(rock_radius, rock_height, rng)
		var rock_basis := _surface_basis(direction, rng.randf_range(0.0, TAU))
		var rock_transform := Transform3D(rock_basis, direction * ocean_radius)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "LandingRock%d" % index
		mesh_instance.mesh = geometry.mesh
		mesh_instance.material_override = material
		mesh_instance.transform = rock_transform
		add_child(mesh_instance)
		var collision := CollisionShape3D.new()
		collision.name = "LandingRockCollision%d" % index
		var shape := ConvexPolygonShape3D.new()
		shape.points = geometry.points
		collision.shape = shape
		collision.transform = rock_transform
		add_child(collision)
		_rock_directions.append(direction)
		_rock_radii.append(rock_radius)


func _choose_landing_rock_direction(rng: RandomNumberGenerator) -> Vector3:
	var best := Vector3.FORWARD
	var best_clearance := -INF
	for _attempt in 256:
		var candidate := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-0.58, 0.58),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		var clearance := acos(clampf(absf(candidate.y), -1.0, 1.0))
		for existing in _rock_directions:
			clearance = minf(clearance, candidate.angle_to(existing))
		if clearance > best_clearance:
			best = candidate
			best_clearance = clearance
	return best


func _build_landing_rock_geometry(rock_radius: float, rock_height: float, rng: RandomNumberGenerator) -> Dictionary:
	const SEGMENTS := 11
	const RINGS := 5
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var ring_heights: Array[float] = [-7.0, -1.0, rock_height * 0.30, rock_height * 0.68, rock_height * 0.88]
	var ring_scales: Array[float] = [0.66, 1.0, 0.82, 0.58, 0.36]
	var phase_a := rng.randf_range(0.0, TAU)
	var phase_b := rng.randf_range(0.0, TAU)
	var lean := Vector2(rng.randf_range(-0.18, 0.18), rng.randf_range(-0.18, 0.18)) * rock_radius
	for ring in RINGS:
		var ring_fraction := float(ring) / float(RINGS - 1)
		var centre := lean * ring_fraction
		for segment in SEGMENTS:
			var angle := TAU * float(segment) / float(SEGMENTS)
			var angular_shape := 1.0 + sin(angle * 3.0 + phase_a) * 0.13 + sin(angle * 5.0 + phase_b) * 0.08
			var radius_value := rock_radius * ring_scales[ring] * angular_shape * rng.randf_range(0.91, 1.09)
			vertices.append(Vector3(
				centre.x + cos(angle) * radius_value,
				ring_heights[ring] + rng.randf_range(-0.35, 0.35) * ring_fraction,
				centre.y + sin(angle) * radius_value
			))
	for ring in RINGS - 1:
		for segment in SEGMENTS:
			var next := (segment + 1) % SEGMENTS
			var lower := ring * SEGMENTS + segment
			var lower_next := ring * SEGMENTS + next
			var upper := (ring + 1) * SEGMENTS + segment
			var upper_next := (ring + 1) * SEGMENTS + next
			indices.append_array(PackedInt32Array([lower, upper, lower_next, lower_next, upper, upper_next]))
	var top_centre := vertices.size()
	vertices.append(Vector3(lean.x, rock_height, lean.y))
	for segment in SEGMENTS:
		var next := (segment + 1) % SEGMENTS
		indices.append_array(PackedInt32Array([SEGMENTS * (RINGS - 1) + segment, top_centre, SEGMENTS * (RINGS - 1) + next]))
	var faceted_vertices := PackedVector3Array()
	var faceted_normals := PackedVector3Array()
	for index in range(0, indices.size(), 3):
		var first := vertices[indices[index]]
		var second := vertices[indices[index + 1]]
		var third := vertices[indices[index + 2]]
		var normal := (second - first).cross(third - first).normalized()
		for vertex in [first, third, second]:
			faceted_vertices.append(vertex)
			faceted_normals.append(normal)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faceted_vertices
	arrays[Mesh.ARRAY_NORMAL] = faceted_normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "points": vertices}



