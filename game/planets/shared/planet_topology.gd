class_name PlanetTopology
extends RefCounted

static var _topology_cache: Dictionary = {}
static var _topology_mutex := Mutex.new()


static func compute_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for index in range(0, indices.size(), 3):
		var first := indices[index]
		var second := indices[index + 1]
		var third := indices[index + 2]
		var face := (vertices[second] - vertices[first]).cross(vertices[third] - vertices[first])
		normals[first] += face
		normals[second] += face
		normals[third] += face
	for index in normals.size():
		var normal := normals[index]
		if normal.length_squared() < 0.0000000001:
			normal = vertices[index]
		normal = normal.normalized()
		if normal.dot(vertices[index]) < 0.0:
			normal = -normal
		normals[index] = normal
	return normals


static func build_for(resolution: int) -> Dictionary:
	_topology_mutex.lock()
	if _topology_cache.has(resolution):
		var cached: Dictionary = _topology_cache[resolution]
		_topology_mutex.unlock()
		return cached
	var divisions := maxi(resolution, 0)
	var vertices := PackedVector3Array([
		Vector3(0.0, 1.0, 0.0), Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0),
		Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, -1.0, 0.0),
	])
	var edge_pairs := PackedInt32Array([0, 1, 0, 2, 0, 3, 0, 4, 1, 2, 2, 3, 3, 4, 4, 1, 5, 1, 5, 2, 5, 3, 5, 4])
	var edge_triplets := PackedInt32Array([0, 1, 4, 1, 2, 5, 2, 3, 6, 3, 0, 7, 8, 9, 4, 9, 10, 5, 10, 11, 6, 11, 8, 7])
	var edges: Array[PackedInt32Array] = []
	for pair_index in range(0, edge_pairs.size(), 2):
		var start_index := edge_pairs[pair_index]
		var end_index := edge_pairs[pair_index + 1]
		var edge := PackedInt32Array()
		edge.resize(divisions + 2)
		edge[0] = start_index
		for division_index in divisions:
			var t := float(division_index + 1) / float(divisions + 1)
			edge[division_index + 1] = vertices.size()
			vertices.append(vertices[start_index].slerp(vertices[end_index], t))
		edge[divisions + 1] = end_index
		edges.append(edge)
	var indices := PackedInt32Array()
	for triplet_index in range(0, edge_triplets.size(), 3):
		_append_face(
			vertices,
			indices,
			edges[edge_triplets[triplet_index]],
			edges[edge_triplets[triplet_index + 1]],
			edges[edge_triplets[triplet_index + 2]],
			triplet_index / 3 >= 4,
			divisions
		)
	_orient_clockwise(vertices, indices)
	var topology := {"directions": vertices, "indices": indices}
	_topology_cache[resolution] = topology
	_topology_mutex.unlock()
	return topology


static func _append_face(vertices: PackedVector3Array, indices: PackedInt32Array, side_a: PackedInt32Array, side_b: PackedInt32Array, bottom: PackedInt32Array, reverse: bool, divisions: int) -> void:
	var vertex_map := PackedInt32Array()
	vertex_map.append(side_a[0])
	for edge_index in range(1, side_a.size() - 1):
		vertex_map.append(side_a[edge_index])
		var a := vertices[side_a[edge_index]]
		var b := vertices[side_b[edge_index]]
		for inner_index in range(edge_index - 1):
			var t := float(inner_index + 1) / float(edge_index)
			vertex_map.append(vertices.size())
			vertices.append(a.slerp(b, t))
		vertex_map.append(side_b[edge_index])
	for index in bottom:
		vertex_map.append(index)
	for row in divisions + 1:
		var top_vertex := ((row + 1) * (row + 1) - row - 1) / 2
		var bottom_vertex := ((row + 2) * (row + 2) - row - 2) / 2
		for column in 1 + 2 * row:
			var v0 := 0
			var v1 := 0
			var v2 := 0
			if column % 2 == 0:
				v0 = top_vertex
				v1 = bottom_vertex + 1
				v2 = bottom_vertex
				top_vertex += 1
				bottom_vertex += 1
			else:
				v0 = top_vertex
				v1 = bottom_vertex
				v2 = top_vertex - 1
			indices.append(vertex_map[v0])
			indices.append(vertex_map[v2] if reverse else vertex_map[v1])
			indices.append(vertex_map[v1] if reverse else vertex_map[v2])


static func _orient_clockwise(vertices: PackedVector3Array, indices: PackedInt32Array) -> void:
	for index in range(0, indices.size(), 3):
		var a := vertices[indices[index]]
		var b := vertices[indices[index + 1]]
		var c := vertices[indices[index + 2]]
		if (b - a).cross(c - a).dot(a + b + c) > 0.0:
			var swap := indices[index + 1]
			indices[index + 1] = indices[index + 2]
			indices[index + 2] = swap
