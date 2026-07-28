extends Node3D

const PlanetScript := preload("res://scripts/planet.gd")
const PlanetHeightGeneratorScript := preload("res://scripts/planet_height_generator.gd")

# Debris ring meant to be added as a child of a planet node, so the orbital
# state written on the parent and the floating origin recentring both carry it
# for free.
const ROCK_VARIANTS := 4
const ROCK_TOPOLOGY := 3
const BANDS := 4
const ROCKS_PER_BAND_VARIANT := 30
const INNER_RADIUS := 78.0
const OUTER_RADIUS := 132.0
const BAND_THICKNESS := 4.0
# Beyond this the individual rocks are sub-pixel, so only the dust band shows.
const ROCK_VISIBILITY_DISTANCE := 700.0
const DUST_FADE_NEAR := 220.0
const DUST_FADE_FAR := 620.0

var _bands: Array[Node3D] = []
var _dust: MeshInstance3D
var _dust_material: ShaderMaterial


func _ready() -> void:
	var meshes := _build_rock_meshes()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.44, 0.40, 0.35)
	material.roughness = 0.95
	material.metallic_specular = 0.15
	var rng := RandomNumberGenerator.new()
	rng.seed = 20873
	var parent_mu := 0.0
	var parent := get_parent()
	if parent != null and parent.has_method("get_gravitational_parameter"):
		parent_mu = float(parent.call("get_gravitational_parameter"))
	for band_index in BANDS:
		var span := (OUTER_RADIUS - INNER_RADIUS) / float(BANDS)
		var band_inner := INNER_RADIUS + span * float(band_index)
		var band := Node3D.new()
		band.name = "Band%d" % band_index
		# Random tilt keeps the ring from reading as four perfect coplanar discs.
		band.rotation = Vector3(rng.randf_range(-0.03, 0.03), rng.randf_range(0.0, TAU), rng.randf_range(-0.03, 0.03))
		# Keplerian rate at the band centre: inner bands lap the outer ones, so
		# the ring shears over time instead of turning like a painted disc.
		var orbit_radius := band_inner + span * 0.5
		var speed := sqrt(parent_mu / pow(orbit_radius, 3.0)) if parent_mu > 0.0 else 0.05
		band.set_meta("speed", speed)
		add_child(band)
		_bands.append(band)
		for variant in meshes.size():
			band.add_child(_build_band_variant(meshes[variant], material, band_inner, span, rng, band_index, variant))
	_build_dust()


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance := camera.global_position.distance_to(global_position)
	var visible_rocks := distance < ROCK_VISIBILITY_DISTANCE
	for band in _bands:
		band.visible = visible_rocks
		if visible_rocks:
			band.rotate_y(float(band.get_meta("speed")) * delta)
	# The illusion: a solid dust band from far away that breaks apart into
	# scattered rocks on approach.
	_dust_material.set_shader_parameter("dissolve", 1.0 - smoothstep(DUST_FADE_NEAR, DUST_FADE_FAR, distance))
	var sun := get_tree().get_first_node_in_group("sun") as Node3D
	if sun != null:
		_dust_material.set_shader_parameter("sun_direction", (sun.global_position - global_position).normalized())


func _build_band_variant(mesh: ArrayMesh, material: StandardMaterial3D, band_inner: float, span: float, rng: RandomNumberGenerator, band_index: int, variant: int) -> MultiMeshInstance3D:
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = mesh
	multi_mesh.instance_count = ROCKS_PER_BAND_VARIANT
	for index in ROCKS_PER_BAND_VARIANT:
		var angle := rng.randf_range(0.0, TAU)
		var radius := band_inner + rng.randf_range(0.0, span)
		# Squaring the sample packs the debris towards the ring plane.
		var height := BAND_THICKNESS * rng.randf_range(-1.0, 1.0) * rng.randf()
		var basis := Basis.from_euler(Vector3(
			rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU)
		)).scaled(Vector3.ONE * rng.randf_range(0.25, 1.6))
		multi_mesh.set_instance_transform(index, Transform3D(
			basis, Vector3(cos(angle) * radius, height, sin(angle) * radius)
		))
	var instance := MultiMeshInstance3D.new()
	instance.name = "Rocks%d_%d" % [band_index, variant]
	instance.multimesh = multi_mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


# The rocks reuse the asteroid height profile of Tumbling Bean so the debris
# shares the shape language of the rest of the system, at a resolution low
# enough that the analytic CPU sampler stays cheap.
func _build_rock_meshes() -> Array[ArrayMesh]:
	var topology := PlanetScript._topology_for(ROCK_TOPOLOGY)
	var directions: PackedVector3Array = topology.directions
	var indices: PackedInt32Array = topology.indices
	var meshes: Array[ArrayMesh] = []
	for variant in ROCK_VARIANTS:
		var generator := PlanetHeightGeneratorScript.new("asteroid", 4200 + variant * 137)
		var vertices := PackedVector3Array()
		vertices.resize(directions.size())
		for index in directions.size():
			vertices[index] = directions[index] * generator.sample_factor(directions[index])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = PlanetScript._compute_normals(vertices, indices)
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		meshes.append(mesh)
	return meshes


func _build_dust() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = INNER_RADIUS
	mesh.outer_radius = OUTER_RADIUS
	mesh.rings = 96
	mesh.ring_segments = 8
	_dust_material = ShaderMaterial.new()
	_dust_material.shader = preload("res://shaders/dust_ring.gdshader")
	_dust_material.set_shader_parameter("inner_radius", INNER_RADIUS)
	_dust_material.set_shader_parameter("outer_radius", OUTER_RADIUS)
	_dust = MeshInstance3D.new()
	_dust.name = "DustBand"
	_dust.mesh = mesh
	_dust.material_override = _dust_material
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Flattening the torus turns the tube into the lens shaped haze of a ring.
	_dust.scale = Vector3(1.0, 0.05, 1.0)
	add_child(_dust)
