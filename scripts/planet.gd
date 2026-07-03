extends StaticBody3D

@export var radius := 50.0
@export var surface_gravity := 12.0
@export var influence_scale := 6.0
@export var color := Color(0.4, 0.7, 0.3)
@export var prop_kind := "tree"
@export var prop_count := 40
@export var rng_seed := 0

var influence_radius: float


func _ready() -> void:
	influence_radius = radius * influence_scale

	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	sphere.material = mat
	mesh.mesh = sphere
	add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	col.shape = shape
	add_child(col)

	_scatter_props()
	Gravity.register(self)


func _exit_tree() -> void:
	Gravity.unregister(self)


func _scatter_props() -> void:
	if prop_kind == "none" or prop_count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in prop_count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if dir.length_squared() < 0.01:
			dir = Vector3.UP
		dir = dir.normalized()
		var prop := _make_prop(rng)
		add_child(prop)
		prop.position = dir * radius
		var basis := Basis()
		basis.y = dir
		basis.x = Vector3.FORWARD.cross(dir)
		if basis.x.length_squared() < 0.001:
			basis.x = Vector3.RIGHT
		basis = basis.orthonormalized()
		prop.basis = basis.rotated(dir, rng.randf_range(0.0, TAU))


func _make_prop(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	match prop_kind:
		"tree":
			var trunk := MeshInstance3D.new()
			var trunk_mesh := CylinderMesh.new()
			trunk_mesh.top_radius = 0.15
			trunk_mesh.bottom_radius = 0.2
			trunk_mesh.height = 1.2
			trunk_mesh.material = _flat_material(Color(0.4, 0.26, 0.13))
			trunk.mesh = trunk_mesh
			trunk.position.y = 0.5
			root.add_child(trunk)
			var crown := MeshInstance3D.new()
			var crown_mesh := CylinderMesh.new()
			crown_mesh.top_radius = 0.0
			crown_mesh.bottom_radius = rng.randf_range(0.7, 1.1)
			crown_mesh.height = rng.randf_range(1.8, 3.0)
			crown_mesh.material = _flat_material(Color(0.12, 0.45, 0.18))
			crown.mesh = crown_mesh
			crown.position.y = 1.1 + crown_mesh.height * 0.5
			root.add_child(crown)
		"rock":
			var rock := MeshInstance3D.new()
			var rock_mesh := BoxMesh.new()
			var s := rng.randf_range(0.6, 2.2)
			rock_mesh.size = Vector3(s, s * rng.randf_range(0.5, 1.0), s * rng.randf_range(0.6, 1.3))
			rock_mesh.material = _flat_material(color.darkened(0.3))
			rock.mesh = rock_mesh
			rock.rotation = Vector3(rng.randf_range(0, TAU), rng.randf_range(0, TAU), 0)
			rock.position.y = rock_mesh.size.y * 0.15
			root.add_child(rock)
		"ice":
			var spike := MeshInstance3D.new()
			var spike_mesh := CylinderMesh.new()
			spike_mesh.top_radius = 0.0
			spike_mesh.bottom_radius = rng.randf_range(0.4, 1.0)
			spike_mesh.height = rng.randf_range(1.5, 4.0)
			var ice_mat := _flat_material(Color(0.75, 0.9, 1.0))
			ice_mat.roughness = 0.2
			spike_mesh.material = ice_mat
			spike.mesh = spike_mesh
			spike.position.y = spike_mesh.height * 0.4
			spike.rotation = Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
			root.add_child(spike)
	return root


func _flat_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m
