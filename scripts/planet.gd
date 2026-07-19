extends AnimatableBody3D

const PlanetQualityScript := preload("res://scripts/planet_quality.gd")
const PlanetHeightGeneratorScript := preload("res://scripts/planet_height_generator.gd")
const AtmosphereLutScript := preload("res://scripts/atmosphere_lut.gd")
const EarthNoiseTexture := preload("res://assets/planet_textures/earth_noise.png")
const MoonNoiseTexture := preload("res://assets/planet_textures/moon_noise.png")
const CraterEjectaTexture := preload("res://assets/planet_textures/crater_ejecta_ray.png")
const MoonFlatNormalTexture := preload("res://assets/planet_textures/moon_normal_flat.png")
const MoonSteepNormalTexture := preload("res://assets/planet_textures/moon_normal_steep.png")
const MESH_CACHE_VERSION := 1

static var _topology_cache: Dictionary = {}

@export_enum("earth", "moon", "alien", "shattered", "moat", "fiery_twin", "icey_twin", "cyclops", "tumbling_bean", "watchful_eye") var body_kind := "earth"
@export_enum("terrain", "lava", "ice") var surface_style := "terrain"
@export var radius := 46.0
@export var surface_gravity := 12.0
@export var influence_scale := 30.0
@export var rng_seed := 1337
@export var initial_velocity := Vector3.ZERO
@export var quality_profile := "desktop_high"
@export var has_ocean := true
@export var ocean_level := 0.0
@export var ocean_shallow_color := Color(0.31401902, 0.943, 0.75800556)
@export var ocean_deep_color := Color(0.05882353, 0.15686275, 0.35686275)
@export var ocean_wave_strength := 0.668
@export var ocean_wave_scale := 25.0
@export var ocean_wave_speed := 0.5
@export var ocean_smoothness := 0.927
@export var ocean_depth_multiplier := 15.0
@export var ocean_alpha_multiplier := 70.0
@export var ocean_specular_color := Color(0.9669199, 1.0, 0.8820755)
@export var has_atmosphere := true
@export var atmosphere_color := Color(0.18, 0.48, 1.0)
@export var atmosphere_scale := 0.322
@export var atmosphere_density_falloff := 4.3
@export var atmosphere_wavelengths := Vector3(700.0, 530.0, 460.0)
@export var atmosphere_scattering_strength := 20.0
@export var atmosphere_intensity := 0.25
@export var shore_color := Color(0.66, 0.58, 0.36)
@export var land_low_color := Color(0.13, 0.34, 0.12)
@export var land_high_color := Color(0.35, 0.24, 0.12)

var influence_radius := 0.0
var orbital_velocity := Vector3.ZERO

var _terrain: MeshInstance3D
var _lod_meshes: Array[ArrayMesh] = []
var _collision_mesh: ArrayMesh
var _surface_material: ShaderMaterial
var _ocean_material: ShaderMaterial
var _atmosphere_material: ShaderMaterial
var _atmosphere_mesh: MeshInstance3D
var _atmosphere_lut: RefCounted
var _atmosphere_lut_bound := false
var _height_generator: RefCounted
var _height_generator_initialized := false
var _lod_resolutions: Array[int] = []
var _next_lod_request := 0
var _active_lod := -1
var _pending_factors := PackedFloat32Array()
var _pending_resolution := -1
var _terrain_height_minmax := Vector2.ONE
var _has_terrain_height_minmax := false
var _collision_task_id := -1
var _collision_task_resolution := -1
var _collision_factors := PackedFloat32Array()
var _collision_ready := false


func _ready() -> void:
	add_to_group("celestial_body")
	collision_layer = 2
	orbital_velocity = initial_velocity
	influence_radius = radius * influence_scale
	_height_generator = PlanetHeightGeneratorScript.new(body_kind, rng_seed)
	_build_terrain()
	_build_collision()
	_build_ocean()
	_build_atmosphere()
	Gravity.register(self)


func _exit_tree() -> void:
	if _height_generator != null and _height_generator_initialized:
		_height_generator.shutdown()
	if _atmosphere_lut != null:
		_atmosphere_lut.shutdown()
	Gravity.unregister(self)


func _process(_delta: float) -> void:
	_poll_collision_generation()
	_poll_terrain_generation()
	_poll_atmosphere_lut()
	_update_lod()
	_update_lighting()


func get_surface_radius_towards(direction: Vector3) -> float:
	return radius + _height_for(direction.normalized())


func get_water_depth(position_value: Vector3) -> float:
	if not has_ocean:
		return -INF
	return radius + ocean_level - position_value.distance_to(global_position)


func get_gravitational_parameter() -> float:
	return surface_gravity * radius * radius


func get_boot_progress() -> float:
	var completed := _lod_meshes.size() + (1 if _collision_ready else 0)
	var total := _lod_resolutions.size() + 1
	if has_atmosphere:
		total += 1
		if _atmosphere_lut_bound:
			completed += 1
	return float(completed) / float(maxi(total, 1))


func is_boot_ready() -> bool:
	return _collision_ready and _lod_meshes.size() == _lod_resolutions.size() and (not has_atmosphere or _atmosphere_lut_bound)


func set_orbital_state(next_position: Vector3, next_velocity: Vector3) -> void:
	global_position = next_position
	orbital_velocity = next_velocity


func get_landing_point(direction: Vector3, clearance := 0.0) -> Vector3:
	var unit_direction := direction.normalized()
	return global_position + unit_direction * (get_surface_radius_towards(unit_direction) + clearance)


func get_sunlit_spawn_direction(sun_position: Vector3) -> Vector3:
	var direction_to_sun := (sun_position - global_position).normalized()
	var best_direction := direction_to_sun
	var best_score := -INF
	const SAMPLE_COUNT := 512
	const GOLDEN_ANGLE := PI * (3.0 - sqrt(5.0))
	for index in SAMPLE_COUNT:
		var y := 1.0 - 2.0 * (float(index) + 0.5) / float(SAMPLE_COUNT)
		var radial := sqrt(maxf(0.0, 1.0 - y * y))
		var angle := GOLDEN_ANGLE * float(index)
		var direction := Vector3(cos(angle) * radial, y, sin(angle) * radial)
		var light := direction.dot(direction_to_sun)
		if light <= 0.25:
			continue
		if has_ocean and _height_for(direction) <= ocean_level + 0.7:
			continue
		var score := light
		if _is_moon_profile():
			score -= _height_generator.sample_shading_data(direction).w * 0.1
		if score <= best_score:
			continue
		best_score = score
		best_direction = direction
	return best_direction


func get_land_direction() -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed * 7919 + 17
	for _attempt in 256:
		var direction := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(0.05, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		if not has_ocean or _height_for(direction) > ocean_level + 0.7:
			return direction
	return Vector3.UP


func get_nearby_land_direction(origin: Vector3) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed * 1543 + 29
	var tangent_a := origin.cross(Vector3.UP)
	if tangent_a.length_squared() < 0.001:
		tangent_a = origin.cross(Vector3.RIGHT)
	tangent_a = tangent_a.normalized()
	var tangent_b := origin.cross(tangent_a).normalized()
	for _attempt in 256:
		var offset := tangent_a * rng.randf_range(-0.22, 0.22) + tangent_b * rng.randf_range(-0.22, 0.22)
		var direction := (origin + offset).normalized()
		if origin.angle_to(direction) * radius >= 8.0 and _height_for(direction) > ocean_level + 0.7:
			return direction
	return origin


func _build_terrain() -> void:
	var profile := PlanetQualityScript.get_profile(quality_profile)
	for subdivisions in profile.lod:
		_lod_resolutions.append(int(subdivisions))
	_terrain = MeshInstance3D.new()
	_surface_material = ShaderMaterial.new()
	match surface_style:
		"lava":
			_surface_material.shader = preload("res://shaders/lava.gdshader")
			_surface_material.set_shader_parameter("base_color", Color(0.103773594, 0.058548227, 0.042586338))
			_surface_material.set_shader_parameter("glow_color", Color(1.0, 0.1909248, 0.0))
		"ice":
			_surface_material.shader = preload("res://shaders/ice.gdshader")
			_surface_material.set_shader_parameter("base_color", Color(0.66245013, 0.58739763, 0.754717))
			_surface_material.set_shader_parameter("crack_color", Color(0.21960784, 0.2784314, 0.42352942))
		_:
			_surface_material.shader = preload("res://shaders/procedural_planet.gdshader")
	_terrain.material_override = _surface_material
	add_child(_terrain)
	var cached_meshes: Array[ArrayMesh] = []
	for resolution in _lod_resolutions:
		var cached_mesh := _load_cached_mesh("terrain", resolution)
		if cached_mesh == null:
			cached_meshes.clear()
			break
		cached_meshes.append(cached_mesh)
	if cached_meshes.size() == _lod_resolutions.size():
		_lod_meshes = cached_meshes
		_restore_terrain_properties(_lod_meshes[0])
		_set_lod(0)
		return
	_height_generator.initialize()
	_height_generator_initialized = true
	_request_next_lod()


func _build_collision() -> void:
	var profile := PlanetQualityScript.get_profile(quality_profile)
	var resolution := int(profile.collision)
	_collision_mesh = _load_cached_mesh("collision", resolution)
	if _collision_mesh != null:
		_install_collision(_collision_mesh)
		return
	var topology := _topology_for(resolution)
	_collision_task_resolution = resolution
	_collision_task_id = WorkerThreadPool.add_task(
		_generate_collision_factors.bind(topology.directions),
		false,
		"Generate %s collision" % name
	)


func _generate_collision_factors(directions: PackedVector3Array) -> void:
	var generator := PlanetHeightGeneratorScript.new(body_kind, rng_seed)
	var factors := PackedFloat32Array()
	factors.resize(directions.size())
	for index in directions.size():
		factors[index] = generator.sample_factor(directions[index])
	_collision_factors = factors


func _poll_collision_generation() -> void:
	if _collision_task_id < 0 or not WorkerThreadPool.is_task_completed(_collision_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_collision_task_id)
	_collision_mesh = _build_mesh_from_factors(_collision_task_resolution, _collision_factors, PackedFloat32Array())
	_save_cached_mesh(_collision_mesh, "collision", _collision_task_resolution)
	_install_collision(_collision_mesh)
	_collision_factors = PackedFloat32Array()
	_collision_task_id = -1
	_collision_task_resolution = -1


func _install_collision(mesh: ArrayMesh) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for index in range(0, indices.size(), 3):
		faces[index] = vertices[indices[index]]
		faces[index + 1] = vertices[indices[index + 1]]
		faces[index + 2] = vertices[indices[index + 2]]
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)
	_collision_ready = true


func _build_ocean() -> void:
	if not has_ocean:
		return
	var ocean := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius + ocean_level + 0.03
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 128
	mesh.rings = 64
	_ocean_material = ShaderMaterial.new()
	_ocean_material.shader = preload("res://shaders/spherical_ocean.gdshader")
	_ocean_material.set_shader_parameter("planet_center", global_position)
	_ocean_material.set_shader_parameter("ocean_radius", mesh.radius)
	_ocean_material.set_shader_parameter("planet_scale", radius)
	_ocean_material.set_shader_parameter("shallow_color", ocean_shallow_color)
	_ocean_material.set_shader_parameter("deep_color", ocean_deep_color)
	_ocean_material.set_shader_parameter("wave_strength", ocean_wave_strength)
	_ocean_material.set_shader_parameter("wave_scale", ocean_wave_scale)
	_ocean_material.set_shader_parameter("wave_speed", ocean_wave_speed)
	_ocean_material.set_shader_parameter("smoothness", ocean_smoothness)
	_ocean_material.set_shader_parameter("depth_multiplier", ocean_depth_multiplier)
	_ocean_material.set_shader_parameter("alpha_multiplier", ocean_alpha_multiplier)
	_ocean_material.set_shader_parameter("specular_color", ocean_specular_color)
	_ocean_material.render_priority = 1
	ocean.mesh = mesh
	ocean.material_override = _ocean_material
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean)


func _build_atmosphere() -> void:
	if not has_atmosphere:
		return
	_atmosphere_mesh = MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	_atmosphere_material = ShaderMaterial.new()
	_atmosphere_material.shader = preload("res://shaders/planet_atmosphere.gdshader")
	_atmosphere_material.set_shader_parameter("planet_center", global_position)
	_atmosphere_material.set_shader_parameter("planet_radius", radius)
	_atmosphere_material.set_shader_parameter("atmosphere_radius", radius * (1.0 + atmosphere_scale))
	_atmosphere_material.set_shader_parameter("density_falloff", atmosphere_density_falloff)
	_atmosphere_material.set_shader_parameter("scattering_coefficients", Vector3(
		pow(400.0 / atmosphere_wavelengths.x, 4.0),
		pow(400.0 / atmosphere_wavelengths.y, 4.0),
		pow(400.0 / atmosphere_wavelengths.z, 4.0)
	) * atmosphere_scattering_strength)
	_atmosphere_material.set_shader_parameter("intensity", atmosphere_intensity)
	_atmosphere_mesh.mesh = mesh
	_atmosphere_mesh.material_override = _atmosphere_material
	_atmosphere_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_atmosphere_mesh.custom_aabb = AABB(Vector3(-10000.0, -10000.0, -10000.0), Vector3(20000.0, 20000.0, 20000.0))
	_atmosphere_mesh.visible = false
	add_child(_atmosphere_mesh)
	_atmosphere_lut = AtmosphereLutScript.new()
	_atmosphere_lut.initialize(1.0 + atmosphere_scale, atmosphere_density_falloff)
func _poll_atmosphere_lut() -> void:
	if _atmosphere_lut_bound or _atmosphere_lut == null or _atmosphere_lut.texture == null:
		return
	_atmosphere_material.set_shader_parameter("baked_optical_depth", _atmosphere_lut.texture)
	_atmosphere_mesh.visible = true
	_atmosphere_lut_bound = true


func _update_lod() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var apparent_radius := radius / maxf(camera.global_position.distance_to(global_position), 0.01)
	if apparent_radius > 0.15:
		_set_lod(0)
	elif apparent_radius > 0.045:
		_set_lod(1)
	else:
		_set_lod(2)


func _set_lod(index: int) -> void:
	if _lod_meshes.is_empty():
		return
	var available_index := mini(index, _lod_meshes.size() - 1)
	if _active_lod == available_index:
		return
	_active_lod = available_index
	_terrain.mesh = _lod_meshes[available_index]


func _update_lighting() -> void:
	var sun := get_tree().get_first_node_in_group("sun") as Node3D
	if sun == null:
		return
	var direction := (sun.global_position - global_position).normalized()
	if surface_style == "terrain":
		_surface_material.set_shader_parameter("sun_direction", direction)
	if _ocean_material:
		_ocean_material.set_shader_parameter("planet_center", global_position)
		_ocean_material.set_shader_parameter("sun_direction", direction)
	if _atmosphere_material:
		_atmosphere_material.set_shader_parameter("planet_center", global_position)
		_atmosphere_material.set_shader_parameter("sun_direction", direction)


func _request_next_lod() -> void:
	if _next_lod_request >= _lod_resolutions.size() or _height_generator == null:
		return
	var topology := _topology_for(_lod_resolutions[_next_lod_request])
	_height_generator.request(topology.directions)


func _poll_terrain_generation() -> void:
	if _height_generator == null:
		return
	if _pending_resolution >= 0 and _height_generator.has_shading_result():
		var shading_data: PackedFloat32Array = _height_generator.take_shading_result()
		var mesh := _build_mesh_from_factors(_pending_resolution, _pending_factors, shading_data)
		_save_cached_mesh(mesh, "terrain", _pending_resolution)
		_lod_meshes.append(mesh)
		_pending_factors = PackedFloat32Array()
		_pending_resolution = -1
		_next_lod_request += 1
		_set_lod(_active_lod if _active_lod >= 0 else 0)
		_request_next_lod()
		return
	if _pending_resolution >= 0 or not _height_generator.has_result():
		return
	_pending_factors = _height_generator.take_result()
	_pending_resolution = _lod_resolutions[_next_lod_request]
	var topology := _topology_for(_pending_resolution)
	_height_generator.request_shading(topology.directions)


func _build_cpu_mesh(resolution: int) -> ArrayMesh:
	var topology := _topology_for(resolution)
	var directions: PackedVector3Array = topology.directions
	var factors := PackedFloat32Array()
	factors.resize(directions.size())
	for index in directions.size():
		factors[index] = _height_generator.sample_factor(directions[index])
	return _build_mesh_from_factors(resolution, factors, PackedFloat32Array())


func _load_cached_mesh(purpose: String, resolution: int) -> ArrayMesh:
	var path := _mesh_cache_path(purpose, resolution)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ArrayMesh


func _save_cached_mesh(mesh: ArrayMesh, purpose: String, resolution: int) -> void:
	var directory := ProjectSettings.globalize_path("user://planet_mesh_cache")
	DirAccess.make_dir_recursive_absolute(directory)
	ResourceSaver.save(mesh, _mesh_cache_path(purpose, resolution), ResourceSaver.FLAG_COMPRESS)


func _mesh_cache_path(purpose: String, resolution: int) -> String:
	return "user://planet_mesh_cache/v%d_%s_%s_%d_%d_%d.res" % [
		MESH_CACHE_VERSION,
		purpose,
		body_kind,
		rng_seed,
		int(round(radius * 1000.0)),
		resolution,
	]


func _restore_terrain_properties(mesh: ArrayMesh) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	if vertices.is_empty() or uv.size() != vertices.size() or uv2.size() != vertices.size():
		return
	var shading_data := PackedFloat32Array()
	shading_data.resize(vertices.size() * 4)
	var minimum_factor := vertices[0].length() / radius
	var maximum_factor := minimum_factor
	for index in vertices.size():
		var factor := vertices[index].length() / radius
		minimum_factor = minf(minimum_factor, factor)
		maximum_factor = maxf(maximum_factor, factor)
		var offset := index * 4
		shading_data[offset] = uv[index].x
		shading_data[offset + 1] = uv[index].y
		shading_data[offset + 2] = uv2[index].x
		shading_data[offset + 3] = uv2[index].y
	_terrain_height_minmax = Vector2(minimum_factor, maximum_factor)
	_has_terrain_height_minmax = true
	_set_terrain_properties(shading_data)


func _build_mesh_from_factors(resolution: int, factors: PackedFloat32Array, shading_data: PackedFloat32Array) -> ArrayMesh:
	var topology := _topology_for(resolution)
	var directions: PackedVector3Array = topology.directions
	assert(factors.size() == directions.size())
	assert(shading_data.is_empty() or shading_data.size() == directions.size() * 4)
	if not _has_terrain_height_minmax and not shading_data.is_empty():
		var minimum_factor := factors[0]
		var maximum_factor := factors[0]
		for factor in factors:
			minimum_factor = minf(minimum_factor, factor)
			maximum_factor = maxf(maximum_factor, factor)
		_terrain_height_minmax = Vector2(minimum_factor, maximum_factor)
		_has_terrain_height_minmax = true
	var indices := PackedInt32Array()
	indices.append_array(topology.indices)
	var shaped_vertices := PackedVector3Array()
	var terrain_uv := PackedVector2Array()
	var terrain_uv2 := PackedVector2Array()
	for index in directions.size():
		var direction := directions[index]
		var factor := factors[index]
		shaped_vertices.append(direction * radius * factor)
		if not shading_data.is_empty():
			var offset := index * 4
			terrain_uv.append(Vector2(shading_data[offset], shading_data[offset + 1]))
			terrain_uv2.append(Vector2(shading_data[offset + 2], shading_data[offset + 3]))
	_orient_clockwise(shaped_vertices, indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = shaped_vertices
	var normals := _calculate_normals(shaped_vertices, indices)
	var tangents := PackedFloat32Array()
	tangents.resize(normals.size() * 4)
	for index in normals.size():
		var normal := normals[index]
		var offset := index * 4
		tangents[offset] = -normal.z
		tangents[offset + 1] = 0.0
		tangents[offset + 2] = normal.x
		tangents[offset + 3] = 1.0
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	if not shading_data.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = terrain_uv
		arrays[Mesh.ARRAY_TEX_UV2] = terrain_uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if not shading_data.is_empty():
		_set_terrain_properties(shading_data)
	return mesh


static func _topology_for(resolution: int) -> Dictionary:
	if _topology_cache.has(resolution):
		return _topology_cache[resolution]
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
	var topology := {"directions": vertices, "indices": indices}
	_topology_cache[resolution] = topology
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


static func _calculate_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for index in normals.size():
		normals[index] = Vector3.ZERO
	for index in range(0, indices.size(), 3):
		var a := indices[index]
		var b := indices[index + 1]
		var c := indices[index + 2]
		var face_normal := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		if face_normal.dot(vertices[a] + vertices[b] + vertices[c]) < 0.0:
			face_normal = -face_normal
		normals[a] += face_normal
		normals[b] += face_normal
		normals[c] += face_normal
	for index in normals.size():
		normals[index] = normals[index].normalized()
	return normals


func _set_terrain_properties(shading_data: PackedFloat32Array) -> void:
	if surface_style != "terrain":
		return
	_surface_material.set_shader_parameter("body_kind", 1 if _is_moon_profile() else 0)
	_surface_material.set_shader_parameter("planet_radius", radius)
	_surface_material.set_shader_parameter("height_min_max", _terrain_height_minmax)
	_surface_material.set_shader_parameter("ocean_level", 1.0 + ocean_level / radius)
	_surface_material.set_shader_parameter("earth_noise", EarthNoiseTexture)
	_surface_material.set_shader_parameter("moon_noise", MoonNoiseTexture)
	_surface_material.set_shader_parameter("crater_ejecta", CraterEjectaTexture)
	_surface_material.set_shader_parameter("moon_normal_flat", MoonFlatNormalTexture)
	_surface_material.set_shader_parameter("moon_normal_steep", MoonSteepNormalTexture)
	_surface_material.set_shader_parameter("shore_low", Color(0.98039216, 1.0, 0.6666667))
	_surface_material.set_shader_parameter("shore_high", Color(0.9528302, 0.90580887, 0.38203096))
	_surface_material.set_shader_parameter("flat_low_a", Color(0.7898985, 0.85882354, 0.0))
	_surface_material.set_shader_parameter("flat_high_a", Color(0.19073083, 0.4627451, 0.0))
	_surface_material.set_shader_parameter("flat_low_b", Color(0.58431375, 0.85882354, 0.0))
	_surface_material.set_shader_parameter("flat_high_b", Color(0.19215687, 0.4627451, 0.0))
	_surface_material.set_shader_parameter("steep_low", Color(0.5294118, 0.49019608, 0.1882353))
	_surface_material.set_shader_parameter("steep_high", Color(0.14901961, 0.06666667, 0.0))
	_surface_material.set_shader_parameter("earth_test_params", Vector4(-0.36, -0.05, 0.38, 0.0))
	_surface_material.set_shader_parameter("moon_primary_a", Color(1.0, 1.0, 1.0))
	_surface_material.set_shader_parameter("moon_secondary_a", Color(0.735849, 0.735849, 0.735849))
	_surface_material.set_shader_parameter("moon_primary_b", Color(0.1792453, 0.1792453, 0.1792453))
	_surface_material.set_shader_parameter("moon_secondary_b", Color(0.0, 0.0, 0.0))
	_surface_material.set_shader_parameter("moon_ejecta", Color(1.0, 0.96323127, 0.9386792))
	_surface_material.set_shader_parameter("moon_biome_blend_strength", 1.37)
	_surface_material.set_shader_parameter("moon_biome_warp_strength", 6.08)
	_surface_material.set_shader_parameter("moon_random_biome_values", Vector4(-4.41, 0.0, -1.18, 5.65))
	_apply_reference_palette()
	var biome_sum := 0.0
	for index in range(3, shading_data.size(), 4):
		biome_sum += shading_data[index]
	_surface_material.set_shader_parameter("moon_average_biome_noise", biome_sum / maxf(float(shading_data.size() / 4), 1.0))


func _apply_reference_palette() -> void:
	match body_kind:
		"cyclops", "alien":
			_surface_material.set_shader_parameter("shore_low", Color(0.7208405, 0.5613208, 1.0))
			_surface_material.set_shader_parameter("shore_high", Color(0.7208405, 0.5613208, 1.0))
			_surface_material.set_shader_parameter("flat_low_a", Color(0.6037736, 0.26556534, 0.21929511))
			_surface_material.set_shader_parameter("flat_high_a", Color(0.1643025, 0.0074759563, 0.5283019))
			_surface_material.set_shader_parameter("flat_low_b", Color(0.69101536, 0.36765754, 0.9622642))
			_surface_material.set_shader_parameter("flat_high_b", Color(0.110119045, 0.0, 0.2264151))
			_surface_material.set_shader_parameter("steep_low", Color(0.50084054, 0.19624422, 0.8490566))
			_surface_material.set_shader_parameter("steep_high", Color.WHITE)
		"tumbling_bean":
			_surface_material.set_shader_parameter("moon_primary_a", Color(0.15864186, 0.18783918, 0.21698111))
			_surface_material.set_shader_parameter("moon_secondary_a", Color(0.38274297, 0.4439998, 0.5754717))
			_surface_material.set_shader_parameter("moon_primary_b", Color(0.039215688, 0.40392157, 0.3080389))
			_surface_material.set_shader_parameter("moon_secondary_b", Color(0.43867922, 1.0, 0.9953623))
			_surface_material.set_shader_parameter("moon_ejecta", Color.WHITE)
		"watchful_eye":
			_surface_material.set_shader_parameter("moon_primary_a", Color(0.10012459, 0.13390097, 0.16981131))
			_surface_material.set_shader_parameter("moon_secondary_a", Color(0.28635636, 0.41927588, 0.6132076))
			_surface_material.set_shader_parameter("moon_primary_b", Color(0.18867922, 0.036489844, 0.061920755))
			_surface_material.set_shader_parameter("moon_secondary_b", Color(0.6981132, 0.55138284, 0.5433428))
			_surface_material.set_shader_parameter("moon_ejecta", Color(1.0, 0.96236044, 0.8915094))


func _is_moon_profile() -> bool:
	return body_kind == "moon" or body_kind == "tumbling_bean" or body_kind == "watchful_eye"


func _height_for(direction: Vector3) -> float:
	return radius * (_height_generator.sample_factor(direction.normalized()) - 1.0)
