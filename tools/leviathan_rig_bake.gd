extends SceneTree

# Bakes a skeleton into the imported anglerfish. The Sketchfab model ships as a
# single unrigged sheet - no skin, no morph targets, no animation - so the bones,
# their weights and the skin are all generated here from the geometry itself.
#
# The jaw is not found with a cutting plane: the snout overhangs the mandible, so
# any plane that keeps the fangs also keeps the snout. It is found by flood
# filling the vertex graph from under the chin with a barrier at the hinge, which
# picks up the mandible and its fangs and nothing else, because the two halves of
# the mouth only join behind the hinge.
#
# The spine is a straight chain down the body axis, which is all an eel-shaped
# body needs for a swim wave.
#
# Run: godot --headless --script res://tools/leviathan_rig_bake.gd

const SOURCE := "res://assets/models/leviathan.glb"
const OUTPUT := "res://assets/models/leviathan_rigged.scn"

# Model space, the one game/leviathan/leviathan.gd measures its landmarks in: +Z
# runs forward to the maw, +Y is the crown. The glb node carries a quarter turn
# about X that the importer leaves on the mesh instance, so this tool bakes that
# transform into the vertices and the rig lives in model space with no offsets.
const HINGE_Z := 50.0
const SEED_MAX_Y := 25.0
const SMOOTH_PASSES := 6
const WELD := 1000.0
const CELL_SIZE := 6.0

# Joint positions down the length axis. The first is the hinge plane, so the head
# bone and the jaw bone share it and the mouth opens where the mesh already
# creases. The last sits at the base of the tail fan.
const SPINE_Z: Array[float] = [50.0, 20.0, -10.0, -45.0, -80.0, -112.0]

# The lantern stalk is a thin spar sticking out past the snout; it gets its own
# bone so the lure can bob and so the lantern light can ride a BoneAttachment3D.
const LURE_START_Z := 100.0
const LURE_END_Z := 122.0
const LURE_MAX_X := 12.0

const BONE_HEAD := 0
const BONE_JAW := 1
const BONE_LURE := 2
const BONE_SPINE_FIRST := 3


func _initialize() -> void:
	var scene := load(SOURCE) as PackedScene
	var source_root := scene.instantiate()
	var source_mesh_instance := source_root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var source_mesh := source_mesh_instance.mesh as ArrayMesh
	var material := source_mesh.surface_get_material(0)

	var arrays := source_mesh.surface_get_arrays(0)
	_bake_node_transform(arrays, source_mesh_instance.transform)

	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	print("vertices=%d triangles=%d" % [vertices.size(), indices.size() / 3])

	var weld := _weld(vertices)
	var adjacency := _adjacency(weld.map, weld.count, indices)
	var jaw := _jaw_weight(weld, adjacency, vertices)

	var joints := _joint_positions(vertices, jaw)
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array()
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array()
	_skin_weights(vertices, jaw, arrays)

	var mesh := _build_mesh(arrays, material)
	var packed := _build_scene(mesh, joints)
	var status := ResourceSaver.save(packed, OUTPUT)
	if status != OK:
		printerr("save failed: %d" % status)
		quit(1)
		return
	print("saved ", OUTPUT)
	quit()


# The importer leaves the glTF node rotation on the mesh instance, so raw VERTEX
# data is still Blender space. Folding it in here means the rig, the mesh and the
# landmark constants in leviathan.gd all speak the same coordinates.
func _bake_node_transform(arrays: Array, transform: Transform3D) -> void:
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	for i in vertices.size():
		vertices[i] = transform * vertices[i]
	arrays[Mesh.ARRAY_VERTEX] = vertices

	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	for i in normals.size():
		normals[i] = (transform.basis * normals[i]).normalized()
	arrays[Mesh.ARRAY_NORMAL] = normals

	var tangents := arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array
	for i in tangents.size() / 4:
		var base := i * 4
		var rotated := (transform.basis * Vector3(tangents[base], tangents[base + 1], tangents[base + 2])).normalized()
		tangents[base] = rotated.x
		tangents[base + 1] = rotated.y
		tangents[base + 2] = rotated.z
	arrays[Mesh.ARRAY_TANGENT] = tangents


# UV seams split the mesh into islands that share positions but not indices, so
# the graph has to be built on welded positions or the flood fill stops at every
# seam.
func _weld(vertices: PackedVector3Array) -> Dictionary:
	var lookup := {}
	var map := PackedInt32Array()
	map.resize(vertices.size())
	for i in vertices.size():
		var v := vertices[i]
		var key := Vector3i(roundi(v.x * WELD), roundi(v.y * WELD), roundi(v.z * WELD))
		var welded: int = lookup.get(key, -1)
		if welded < 0:
			welded = lookup.size()
			lookup[key] = welded
		map[i] = welded
	print("welded %d vertices to %d positions" % [vertices.size(), lookup.size()])
	return {"map": map, "count": lookup.size()}


# Duplicate edges are left in: the flood fill ignores them and the smoothing pass
# only ends up weighting shared edges slightly more, which is harmless.
func _adjacency(map: PackedInt32Array, count: int, indices: PackedInt32Array) -> Array:
	var adjacency: Array = []
	adjacency.resize(count)
	for i in count:
		adjacency[i] = PackedInt32Array()
	for triangle in indices.size() / 3:
		var base := triangle * 3
		var a := map[indices[base]]
		var b := map[indices[base + 1]]
		var c := map[indices[base + 2]]
		adjacency[a].append(b)
		adjacency[a].append(c)
		adjacency[b].append(a)
		adjacency[b].append(c)
		adjacency[c].append(a)
		adjacency[c].append(b)
	return adjacency


# Flood fill from under the chin, refusing to cross the hinge plane, then relax
# the hard selection so the throat skin stretches into the gape instead of
# tearing away from the skull along one ring of triangles.
func _jaw_weight(weld: Dictionary, adjacency: Array, vertices: PackedVector3Array) -> PackedFloat32Array:
	var map := weld.map as PackedInt32Array
	var count := weld.count as int

	var welded_position := PackedVector3Array()
	welded_position.resize(count)
	for i in vertices.size():
		welded_position[map[i]] = vertices[i]

	var components := _components(adjacency, count)
	var body := components.largest as int
	print("components=%d body=%d verts=%d" % [components.count, body, (components.members[body] as PackedInt32Array).size()])

	var weight := PackedFloat32Array()
	weight.resize(count)
	var frontier := PackedInt32Array()
	for i in count:
		var p := welded_position[i]
		if p.z > HINGE_Z + 3.0 and p.y < SEED_MAX_Y:
			weight[i] = 1.0
			frontier.append(i)
	var seeds := frontier.size()

	var head := 0
	while head < frontier.size():
		var current := frontier[head]
		head += 1
		for neighbour in adjacency[current] as PackedInt32Array:
			if weight[neighbour] > 0.0 or welded_position[neighbour].z <= HINGE_Z:
				continue
			weight[neighbour] = 1.0
			frontier.append(neighbour)
	print("jaw flood fill: seeds=%d component=%d" % [seeds, frontier.size()])

	for _pass in SMOOTH_PASSES:
		var next := weight.duplicate()
		for i in count:
			var neighbours := adjacency[i] as PackedInt32Array
			if neighbours.is_empty():
				continue
			var total := 0.0
			for neighbour in neighbours:
				total += weight[neighbour]
			next[i] = weight[i] * 0.5 + (total / float(neighbours.size())) * 0.5
		weight = next

	weight = _graft_loose_shells(weight, welded_position, components, body)

	var per_vertex := PackedFloat32Array()
	per_vertex.resize(vertices.size())
	for i in vertices.size():
		per_vertex[i] = weight[map[i]]
	return per_vertex


func _components(adjacency: Array, count: int) -> Dictionary:
	var label := PackedInt32Array()
	label.resize(count)
	label.fill(-1)
	var members: Array = []
	var largest := 0
	for start in count:
		if label[start] >= 0:
			continue
		var component := members.size()
		var queue := PackedInt32Array([start])
		label[start] = component
		var head := 0
		while head < queue.size():
			var current := queue[head]
			head += 1
			for neighbour in adjacency[current] as PackedInt32Array:
				if label[neighbour] >= 0:
					continue
				label[neighbour] = component
				queue.append(neighbour)
		members.append(queue)
		if queue.size() > (members[largest] as PackedInt32Array).size():
			largest = component
	return {"label": label, "members": members, "count": members.size(), "largest": largest}


# Every fang is its own closed shell dropped into the gum, so it shares no edge
# with the flesh and the flood fill can never reach it. Each loose shell takes
# the weight of the body vertex it is anchored nearest to, which puts the lower
# fangs on the mandible and leaves the palate fangs on the skull.
func _graft_loose_shells(weight: PackedFloat32Array, welded_position: PackedVector3Array,
		components: Dictionary, body: int) -> PackedFloat32Array:
	var body_members := components.members[body] as PackedInt32Array
	var grid := {}
	for i in body_members:
		var cell := _cell(welded_position[i])
		if not grid.has(cell):
			grid[cell] = PackedInt32Array()
		grid[cell].append(i)

	var grafted := 0
	for component in components.count:
		if component == body:
			continue
		var members := components.members[component] as PackedInt32Array
		var anchor := -1
		var best := INF
		for radius in range(1, 6):
			for i in members:
				var here := _cell(welded_position[i])
				for dx in range(-radius, radius + 1):
					for dy in range(-radius, radius + 1):
						for dz in range(-radius, radius + 1):
							var key := here + Vector3i(dx, dy, dz)
							if not grid.has(key):
								continue
							for candidate in grid[key] as PackedInt32Array:
								var distance := welded_position[i].distance_squared_to(welded_position[candidate])
								if distance < best:
									best = distance
									anchor = candidate
			if anchor >= 0:
				break
		if anchor < 0:
			continue
		var anchored := weight[anchor]
		for i in members:
			weight[i] = anchored
		if anchored > 0.5:
			grafted += 1
	print("loose shells grafted to the jaw: %d of %d" % [grafted, components.count - 1])
	return weight


func _cell(position: Vector3) -> Vector3i:
	return Vector3i((position / CELL_SIZE).floor())


# Bones sit on the body centreline rather than on y=0, so a spine rotation swings
# the body around its own axis instead of pivoting it about the belly. The jaw
# pivot is taken from the mandible itself, at the commissure where it meets the
# skull.
func _joint_positions(vertices: PackedVector3Array, jaw: PackedFloat32Array) -> Dictionary:
	# One height for the whole chain, taken as the median of the core column: an
	# average is dragged upwards by the dorsal crest and would leave the spine
	# sagging in the middle, which shows the moment the wave gets any pitch.
	var column := PackedFloat32Array()
	for i in vertices.size():
		var v := vertices[i]
		if absf(v.x) > LURE_MAX_X or v.z > SPINE_Z[0] or v.z < SPINE_Z[SPINE_Z.size() - 1]:
			continue
		column.append(v.y)
	column.sort()
	var axis_y := column[column.size() / 2] if not column.is_empty() else 0.0

	var spine := PackedVector3Array()
	for z in SPINE_Z:
		spine.append(Vector3(0.0, axis_y, z))

	var jaw_total := 0.0
	var jaw_samples := 0
	for i in vertices.size():
		var v := vertices[i]
		if jaw[i] < 0.5 or v.z > HINGE_Z + 8.0:
			continue
		jaw_total += v.y
		jaw_samples += 1
	var jaw_pivot := Vector3(0.0, jaw_total / maxf(float(jaw_samples), 1.0), HINGE_Z)

	var lure_total := 0.0
	var lure_samples := 0
	for i in vertices.size():
		var v := vertices[i]
		if absf(v.z - LURE_START_Z) > 6.0 or absf(v.x) > LURE_MAX_X:
			continue
		lure_total += v.y
		lure_samples += 1
	var lure_pivot := Vector3(0.0, lure_total / maxf(float(lure_samples), 1.0), LURE_START_Z)

	print("spine joints ", spine)
	print("jaw pivot ", jaw_pivot, " lure pivot ", lure_pivot)
	return {"spine": spine, "jaw": jaw_pivot, "lure": lure_pivot}


# Every vertex ends up on the jaw, on the lure stalk, or shared between the two
# spine joints it lies between. Three influences at most, so the four slots the
# default vertex format gives are never crowded.
func _skin_weights(vertices: PackedVector3Array, jaw: PackedFloat32Array, arrays: Array) -> void:
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(vertices.size() * 4)
	weights.resize(vertices.size() * 4)

	for i in vertices.size():
		var v := vertices[i]
		var jaw_weight := clampf(jaw[i], 0.0, 1.0)
		var lure_weight := 0.0
		if absf(v.x) <= LURE_MAX_X:
			lure_weight = smoothstep(LURE_START_Z, LURE_END_Z, v.z)

		var first := BONE_HEAD
		var second := BONE_HEAD
		var blend := 0.0
		if v.z < SPINE_Z[SPINE_Z.size() - 1]:
			first = BONE_SPINE_FIRST + SPINE_Z.size() - 2
			second = first
		elif v.z < SPINE_Z[0]:
			for segment in SPINE_Z.size() - 1:
				if v.z >= SPINE_Z[segment + 1]:
					first = BONE_HEAD if segment == 0 else BONE_SPINE_FIRST + segment - 1
					second = BONE_SPINE_FIRST + segment
					blend = smoothstep(SPINE_Z[segment], SPINE_Z[segment + 1], v.z)
					break

		var body := (1.0 - jaw_weight) * (1.0 - lure_weight)
		var base := i * 4
		bones[base] = BONE_JAW
		weights[base] = jaw_weight
		bones[base + 1] = BONE_LURE
		weights[base + 1] = (1.0 - jaw_weight) * lure_weight
		bones[base + 2] = first
		weights[base + 2] = body * (1.0 - blend)
		bones[base + 3] = second
		weights[base + 3] = body * blend

	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights


func _build_mesh(arrays: Array, material: Material) -> ArrayMesh:
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, material, "Beast_Anglerfish", 0)
	importer.generate_lods(25.0, 60.0, [])
	var mesh := importer.get_mesh()
	print("lods generated: ", importer.get_surface_lod_count(0))
	return mesh


func _build_scene(mesh: ArrayMesh, joints: Dictionary) -> PackedScene:
	var root := Node3D.new()
	root.name = "leviathan"

	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	root.add_child(skeleton)
	skeleton.owner = root

	var spine := joints.spine as PackedVector3Array
	skeleton.add_bone("Head")
	skeleton.set_bone_rest(BONE_HEAD, Transform3D(Basis(), spine[0]))

	skeleton.add_bone("Jaw")
	skeleton.set_bone_parent(BONE_JAW, BONE_HEAD)
	skeleton.set_bone_rest(BONE_JAW, Transform3D(Basis(), (joints.jaw as Vector3) - spine[0]))

	skeleton.add_bone("Lure")
	skeleton.set_bone_parent(BONE_LURE, BONE_HEAD)
	skeleton.set_bone_rest(BONE_LURE, Transform3D(Basis(), (joints.lure as Vector3) - spine[0]))

	for segment in range(1, spine.size()):
		var bone := skeleton.add_bone("Spine%d" % segment)
		skeleton.set_bone_parent(bone, BONE_HEAD if segment == 1 else bone - 1)
		skeleton.set_bone_rest(bone, Transform3D(Basis(), spine[segment] - spine[segment - 1]))

	skeleton.reset_bone_poses()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Beast_Anglerfish"
	mesh_instance.mesh = mesh
	skeleton.add_child(mesh_instance)
	mesh_instance.owner = root
	mesh_instance.skin = skeleton.create_skin_from_rest_transforms()
	mesh_instance.skeleton = NodePath("..")

	var packed := PackedScene.new()
	var status := packed.pack(root)
	assert(status == OK)
	return packed
