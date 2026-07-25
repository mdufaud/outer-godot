extends AnimatableBody3D

const PlanetQualityScript := preload("res://scripts/planet_quality.gd")
const PlanetHeightGeneratorScript := preload("res://scripts/planet_height_generator.gd")
const AtmosphereLutScript := preload("res://scripts/atmosphere_lut.gd")
const EarthNoiseTexture := preload("res://assets/planet_textures/earth_noise.png")
const MoonNoiseTexture := preload("res://assets/planet_textures/moon_noise.png")
const CraterEjectaTexture := preload("res://assets/planet_textures/crater_ejecta_ray.png")
const MoonFlatNormalTexture := preload("res://assets/planet_textures/moon_normal_flat.png")
const MoonSteepNormalTexture := preload("res://assets/planet_textures/moon_normal_steep.png")
const OceanWaveATexture := preload("res://assets/ocean_textures/wave_a.png")
const OceanWaveBTexture := preload("res://assets/ocean_textures/wave_b.png")
const OceanFoamTexture := preload("res://assets/ocean_textures/water_foam.png")
const BlueNoiseTexture := preload("res://assets/planet_textures/blue_noise.png")
const MESH_CACHE_VERSION := 8

static var _topology_cache: Dictionary = {}
static var _topology_mutex := Mutex.new()

@export_enum("earth", "moon", "alien", "mirage", "shattered", "moat", "fiery_twin", "icey_twin", "cyclops", "tumbling_bean", "watchful_eye", "asteroid", "glacier") var body_kind := "earth"
@export_enum("terrain", "lava", "ice") var surface_style := "terrain"
@export var radius := 46.0
@export var core_radius := 0.0
@export var surface_gravity := 12.0
@export var influence_scale := 30.0
@export var rng_seed := 1337
# Tangential vertex jitter as a fraction of the radius; 0 keeps a clean sphere.
@export var perturb_strength := 0.0
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
@export var ocean_foam_scale := 1.4
@export var ocean_foam_distance := 0.9
@export var ocean_refraction_strength := 0.003
@export var underwater_tint := Color(0.1, 0.4, 0.5)
@export var underwater_darkness := 0.45
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
var _storm_interior: Node3D
var _storm_orbits: Array[Node3D] = []
var _storm_shell_radius := 0.0
var _lod_resolutions: Array[int] = []
var _active_lod := -1
var _terrain_height_minmax := Vector2.ONE
var _boot_jobs: Array[Dictionary] = []
var _collision_ready := false
var _collider_peak_radius := 0.0


func _ready() -> void:
	add_to_group("celestial_body")
	collision_layer = 2
	influence_radius = radius * influence_scale
	_height_generator = PlanetHeightGeneratorScript.new(body_kind, rng_seed)
	_build_terrain()
	_build_collision()
	_build_ocean()
	_build_atmosphere()
	_build_storm_system()
	for job in _boot_jobs:
		if job.phase == "topology":
			_height_generator.initialize()
			_height_generator_initialized = true
			break
	Gravity.register(self)


func _exit_tree() -> void:
	if _height_generator != null and _height_generator_initialized:
		_height_generator.shutdown()
	if _atmosphere_lut != null:
		_atmosphere_lut.shutdown()
	Gravity.unregister(self)


func _process(delta: float) -> void:
	_poll_boot()
	_poll_atmosphere_lut()
	_update_lod()
	_update_lighting()
	_update_atmosphere_visibility()
	_update_storms(delta)


func get_surface_radius_towards(direction: Vector3) -> float:
	return _core_radius() + _height_for(direction.normalized())


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


func get_boot_status() -> Dictionary:
	var status := {
		"progress": get_boot_progress(),
		"ready": is_boot_ready(),
		"stage": "ready" if is_boot_ready() else "waiting",
	}
	if not _boot_jobs.is_empty():
		var job: Dictionary = _boot_jobs[0]
		status.stage = String(job.phase)
		status.job = String(job.kind)
		status.resolution = int(job.resolution)
		status.remaining_jobs = _boot_jobs.size()
	elif has_atmosphere and not _atmosphere_lut_bound:
		status.stage = "atmosphere LUT: %s" % String(_atmosphere_lut.get_status())
	return status


func set_orbital_state(next_position: Vector3, next_velocity: Vector3) -> void:
	global_position = next_position
	orbital_velocity = next_velocity


func get_collider_surface_radius(direction: Vector3) -> float:
	# The analytic sample_factor runs in float64 while the mesh comes from the
	# float32 compute shader, so they disagree by metres on high frequency
	# terrain. Placement must use the shape bodies actually collide against.
	var unit_direction := direction.normalized()
	var fallback := get_surface_radius_towards(unit_direction)
	if not _collision_ready or not is_inside_tree():
		return fallback
	var space := get_world_3d().direct_space_state
	if space == null:
		return fallback
	# Start clear of the highest peak: deformed bodies such as Tumbling Bean
	# reach well past twice their nominal radius, and backface_collision would
	# make a ray that starts inside the mesh report the far wall.
	var query := PhysicsRayQueryParameters3D.create(
		global_position + unit_direction * (_collider_peak_radius + 1.0),
		global_position
	)
	query.collision_mask = collision_layer
	var hit := space.intersect_ray(query)
	if hit.is_empty() or hit.collider != self:
		return fallback
	return global_position.distance_to(hit.position)


func get_landing_point(direction: Vector3, clearance := 0.0) -> Vector3:
	var unit_direction := direction.normalized()
	if body_kind == "cyclops" and has_ocean:
		return global_position + unit_direction * (radius + ocean_level + clearance)
	return global_position + unit_direction * (get_collider_surface_radius(unit_direction) + clearance)


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
		if has_ocean and _height_for(direction) <= _ocean_level_above_core() + 0.7:
			continue
		var score := light
		if _is_moon_profile():
			score -= _height_generator.sample_shading_data(direction).w * 0.1
		if score <= best_score:
			continue
		if has_ocean and _collider_height_for(direction) <= _ocean_level_above_core() + 0.7:
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
		if not has_ocean or _height_for(direction) > _ocean_level_above_core() + 0.7:
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
		if origin.angle_to(direction) * _core_radius() >= 8.0 and _collider_height_for(direction) > _ocean_level_above_core() + 0.7:
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
	for resolution in _lod_resolutions:
		_boot_jobs.append({"kind": "lod", "resolution": resolution, "phase": "topology"})


func _build_collision() -> void:
	var profile := PlanetQualityScript.get_profile(quality_profile)
	var resolution := int(profile.collision)
	var job := {"kind": "collision", "resolution": resolution, "phase": "topology"}
	_collision_mesh = _load_cached_mesh("collision", resolution)
	if _collision_mesh != null:
		job.mesh = _collision_mesh
		job.phase = "build"
	_boot_jobs.push_front(job)


func _poll_boot() -> void:
	if _boot_jobs.is_empty():
		return
	var job: Dictionary = _boot_jobs[0]
	match String(job.phase):
		"topology":
			job.task_id = WorkerThreadPool.add_task(_build_topology_task.bind(int(job.resolution)), false, "Topology %s %d" % [name, job.resolution])
			job.phase = "topology_wait"
		"topology_wait":
			if WorkerThreadPool.is_task_completed(int(job.task_id)):
				WorkerThreadPool.wait_for_task_completion(int(job.task_id))
				job.phase = "heights"
		"heights":
			if _height_generator.request(_topology_for(int(job.resolution)).directions):
				job.phase = "heights_wait"
		"heights_wait":
			if _height_generator.has_result():
				job.factors = _height_generator.take_result()
				if perturb_strength > 0.0:
					job.phase = "perturb"
				else:
					job.phase = "shading" if job.kind == "lod" else "build"
		"perturb":
			var directions: PackedVector3Array = _topology_for(int(job.resolution)).directions
			var factors: PackedFloat32Array = job.factors
			var points := PackedVector3Array()
			points.resize(directions.size())
			for index in directions.size():
				points[index] = directions[index] * factors[index]
			if _height_generator.request_perturb(points, perturb_strength):
				job.phase = "perturb_wait"
		"perturb_wait":
			if _height_generator.has_perturb_result():
				job.perturbed = _height_generator.take_perturb_result()
				job.phase = "shading" if job.kind == "lod" else "build"
		"shading":
			if _height_generator.request_shading(_topology_for(int(job.resolution)).directions):
				job.phase = "shading_wait"
		"shading_wait":
			if _height_generator.has_shading_result():
				job.shading = _height_generator.take_shading_result()
				job.phase = "build"
		"build":
			job.task_id = WorkerThreadPool.add_task(_run_build_job.bind(job), false, "Build %s %s" % [name, job.kind])
			job.phase = "build_wait"
		"build_wait":
			if WorkerThreadPool.is_task_completed(int(job.task_id)):
				WorkerThreadPool.wait_for_task_completion(int(job.task_id))
				_finish_build_job(job)
				_boot_jobs.pop_front()


static func _build_topology_task(resolution: int) -> void:
	_topology_for(resolution)


func _run_build_job(job: Dictionary) -> void:
	if job.kind == "collision":
		var mesh: ArrayMesh = job.get("mesh")
		if mesh == null:
			mesh = _build_mesh_from_factors(int(job.resolution), job.factors, PackedFloat32Array(), job.get("perturbed", PackedVector3Array()))
			_save_cached_mesh(mesh, "collision", int(job.resolution))
			job.mesh = mesh
			_collision_mesh = mesh
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var faces := PackedVector3Array()
		faces.resize(indices.size())
		for index in indices.size():
			faces[index] = vertices[indices[index]]
		# The terrain mesh is watertight and bodies always stay outside it.
		# Backface collision lets the solver depenetrate a capsule wedged in a
		# narrow notch towards the far side of a triangle, which catapults it.
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		job.shape = shape
		var peak := 0.0
		for vertex in vertices:
			peak = maxf(peak, vertex.length())
		job.peak = peak
		return
	var lod_mesh := _build_mesh_from_factors(int(job.resolution), job.factors, job.shading, job.get("perturbed", PackedVector3Array()))
	_save_cached_mesh(lod_mesh, "terrain", int(job.resolution))
	job.mesh = lod_mesh


func _finish_build_job(job: Dictionary) -> void:
	if job.kind == "collision":
		var collision := CollisionShape3D.new()
		collision.shape = job.shape
		add_child(collision)
		_collider_peak_radius = float(job.peak)
		_collision_ready = true
		return
	_lod_meshes.append(job.mesh)
	if _lod_meshes.size() == 1:
		_restore_terrain_properties(job.mesh)
		_set_lod(0)


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
	_ocean_material.set_shader_parameter("wave_normal_a", OceanWaveATexture)
	_ocean_material.set_shader_parameter("wave_normal_b", OceanWaveBTexture)
	_ocean_material.set_shader_parameter("foam_texture", OceanFoamTexture)
	_ocean_material.set_shader_parameter("foam_scale", ocean_foam_scale)
	_ocean_material.set_shader_parameter("foam_distance", ocean_foam_distance)
	_ocean_material.set_shader_parameter("refraction_strength", ocean_refraction_strength)
	if quality_profile == "mobile_low":
		_ocean_material.set_shader_parameter("foam_distance", ocean_foam_distance * 0.65)
		_ocean_material.set_shader_parameter("refraction_strength", 0.0)
	if body_kind == "cyclops":
		_ocean_material.set_shader_parameter("ambient_color", Color(0.08, 0.3, 0.29))
		_ocean_material.set_shader_parameter("ambient_strength", 0.24)
		_ocean_material.set_shader_parameter("sky_diffusion", 0.22)
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
	_atmosphere_material.set_shader_parameter("atmosphere_color", atmosphere_color)
	_atmosphere_material.set_shader_parameter("density_falloff", atmosphere_density_falloff)
	_atmosphere_material.set_shader_parameter("scattering_coefficients", Vector3(
		pow(400.0 / atmosphere_wavelengths.x, 4.0),
		pow(400.0 / atmosphere_wavelengths.y, 4.0),
		pow(400.0 / atmosphere_wavelengths.z, 4.0)
	) * atmosphere_scattering_strength)
	_atmosphere_material.set_shader_parameter("intensity", atmosphere_intensity)
	_atmosphere_material.set_shader_parameter("blue_noise", BlueNoiseTexture)
	_atmosphere_mesh.mesh = mesh
	_atmosphere_mesh.material_override = _atmosphere_material
	_atmosphere_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_atmosphere_mesh.custom_aabb = AABB(Vector3(-10000.0, -10000.0, -10000.0), Vector3(20000.0, 20000.0, 20000.0))
	_atmosphere_mesh.visible = false
	add_child(_atmosphere_mesh)
	_atmosphere_lut = AtmosphereLutScript.new()
	_atmosphere_lut.initialize(1.0 + atmosphere_scale, atmosphere_density_falloff)


func _build_storm_system() -> void:
	if body_kind != "cyclops":
		return
	var cloud_shell := MeshInstance3D.new()
	cloud_shell.name = "StormCloudShell"
	var cloud_mesh := SphereMesh.new()
	_storm_shell_radius = radius + ocean_level + 38.0
	cloud_mesh.radius = _storm_shell_radius
	cloud_mesh.height = cloud_mesh.radius * 2.0
	cloud_mesh.radial_segments = 96
	cloud_mesh.rings = 48
	var cloud_material := ShaderMaterial.new()
	cloud_material.shader = preload("res://shaders/tornado.gdshader")
	cloud_shell.mesh = cloud_mesh
	cloud_shell.material_override = cloud_material
	cloud_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cloud_shell)


func _build_storm_interior() -> void:
	if _storm_interior != null:
		return
	_storm_interior = Node3D.new()
	_storm_interior.name = "StormInterior"
	add_child(_storm_interior)
	var storm_rng := RandomNumberGenerator.new()
	storm_rng.seed = rng_seed * 3571 + 91
	for index in 6:
		var orbit := Node3D.new()
		orbit.name = "TornadoOrbit%d" % index
		orbit.rotation = Vector3(
			storm_rng.randf_range(-1.1, 1.1),
			storm_rng.randf_range(0.0, TAU),
			storm_rng.randf_range(-0.7, 0.7)
		)
		orbit.set_meta("speed", storm_rng.randf_range(0.035, 0.085) * (-1.0 if index % 2 else 1.0))
		_storm_interior.add_child(orbit)
		var funnel_height := storm_rng.randf_range(34.0, 37.5)
		var funnel_root := Node3D.new()
		funnel_root.name = "Tornado"
		funnel_root.position = Vector3(radius + ocean_level + funnel_height * 0.5, 0.0, 0.0)
		funnel_root.rotation_degrees.z = -90.0
		orbit.add_child(funnel_root)
		var base_phase := storm_rng.randf_range(0.0, TAU)
		for layer in 3:
			var funnel := MeshInstance3D.new()
			funnel.name = "CloudLayer%d" % layer
			var funnel_mesh := CylinderMesh.new()
			funnel_mesh.height = funnel_height * (1.0 - float(layer) * 0.035)
			funnel_mesh.bottom_radius = storm_rng.randf_range(0.7, 1.15) * (1.0 + float(layer) * 0.28)
			funnel_mesh.top_radius = storm_rng.randf_range(7.2, 10.8) * (1.0 + float(layer) * 0.18)
			funnel_mesh.radial_segments = 48
			funnel_mesh.rings = 24
			var funnel_material := ShaderMaterial.new()
			funnel_material.shader = load("res://shaders/tornado_funnel.gdshader")
			funnel_material.set_shader_parameter("phase", base_phase + float(layer) * 2.1)
			funnel_material.set_shader_parameter("layer_offset", float(layer) * 0.37)
			funnel_material.set_shader_parameter("opacity", 0.48 - float(layer) * 0.09)
			funnel.mesh = funnel_mesh
			funnel.material_override = funnel_material
			funnel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			funnel_root.add_child(funnel)
		for ring_index in 3:
			var spray := MeshInstance3D.new()
			spray.name = "SprayRing%d" % ring_index
			var spray_mesh := TorusMesh.new()
			spray_mesh.inner_radius = 1.5 + float(ring_index) * 1.35
			spray_mesh.outer_radius = spray_mesh.inner_radius + 0.65
			spray_mesh.rings = 48
			spray_mesh.ring_segments = 12
			var spray_material := ShaderMaterial.new()
			spray_material.shader = load("res://shaders/storm_spray.gdshader")
			spray_material.set_shader_parameter("phase", base_phase + float(ring_index) * 1.7)
			spray.mesh = spray_mesh
			spray.material_override = spray_material
			spray.position.y = -funnel_height * 0.5 + 0.35 + float(ring_index) * 0.28
			spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			funnel_root.add_child(spray)
		_storm_orbits.append(orbit)
	_build_abyss_lights(storm_rng)


func _build_abyss_lights(storm_rng: RandomNumberGenerator) -> void:
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.albedo_color = Color(0.08, 0.8, 0.68)
	glow_material.emission_enabled = true
	glow_material.emission = Color(0.12, 1.0, 0.78)
	glow_material.emission_energy_multiplier = 2.2
	for index in 9:
		var direction := Vector3(
			storm_rng.randf_range(-1.0, 1.0),
			storm_rng.randf_range(-1.0, 1.0),
			storm_rng.randf_range(-1.0, 1.0)
		).normalized()
		var source := Node3D.new()
		source.name = "CoreGlow%d" % index
		source.position = direction * (_core_radius() + storm_rng.randf_range(2.0, 8.0))
		_storm_interior.add_child(source)
		var glow := MeshInstance3D.new()
		var glow_mesh := SphereMesh.new()
		glow_mesh.radius = storm_rng.randf_range(0.8, 1.8)
		glow_mesh.height = glow_mesh.radius * 2.0
		glow.mesh = glow_mesh
		glow.material_override = glow_material
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		source.add_child(glow)
		var light := OmniLight3D.new()
		light.light_color = Color(0.12, 0.95, 0.75)
		light.light_energy = storm_rng.randf_range(1.4, 2.3)
		light.omni_range = storm_rng.randf_range(24.0, 36.0)
		light.omni_attenuation = 1.35
		light.shadow_enabled = false
		source.add_child(light)


func _clear_storm_interior() -> void:
	if _storm_interior == null:
		return
	_storm_interior.queue_free()
	_storm_interior = null
	_storm_orbits.clear()


func _update_storms(delta: float) -> void:
	if body_kind != "cyclops":
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var inside_clouds := camera.global_position.distance_to(global_position) < _storm_shell_radius - 1.0
	if inside_clouds and _storm_interior == null:
		_build_storm_interior()
	elif not inside_clouds and _storm_interior != null:
		_clear_storm_interior()
	for orbit in _storm_orbits:
		orbit.rotate_y(float(orbit.get_meta("speed")) * delta)


func _poll_atmosphere_lut() -> void:
	if _atmosphere_lut_bound or _atmosphere_lut == null or _atmosphere_lut.texture == null:
		return
	_atmosphere_material.set_shader_parameter("baked_optical_depth", _atmosphere_lut.texture)
	_atmosphere_mesh.visible = true
	_atmosphere_lut_bound = true


func _update_atmosphere_visibility() -> void:
	if _atmosphere_mesh == null or not _atmosphere_lut_bound:
		return
	var camera := get_viewport().get_camera_3d()
	var camera_underwater := camera != null and has_ocean and get_water_depth(camera.global_position) > 0.0
	_atmosphere_mesh.visible = not camera_underwater


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


func get_generator_error() -> String:
	var height_error := String(_height_generator.get_error()) if _height_generator != null else ""
	if not height_error.is_empty():
		return height_error
	return String(_atmosphere_lut.get_error()) if _atmosphere_lut != null else ""


func _load_cached_mesh(purpose: String, resolution: int) -> ArrayMesh:
	var path := _mesh_cache_path(purpose, resolution)
	if not ResourceLoader.exists(path):
		return null
	var mesh := load(path) as ArrayMesh
	if mesh == null:
		return null
	if purpose == "terrain" and not mesh.has_meta("height_minmax"):
		return null
	return mesh


func _save_cached_mesh(mesh: ArrayMesh, purpose: String, resolution: int) -> void:
	var directory := ProjectSettings.globalize_path("user://planet_mesh_cache")
	DirAccess.make_dir_recursive_absolute(directory)
	ResourceSaver.save(mesh, _mesh_cache_path(purpose, resolution), ResourceSaver.FLAG_COMPRESS)


func _mesh_cache_path(purpose: String, resolution: int) -> String:
	var suffix := ""
	if perturb_strength > 0.0:
		suffix = "_p%d" % int(round(perturb_strength * 1000.0))
	return "user://planet_mesh_cache/v%d_%s_%s_%d_%d_%d%s.res" % [
		MESH_CACHE_VERSION,
		purpose,
		body_kind,
		rng_seed,
		int(round(_core_radius() * 1000.0)),
		resolution,
		suffix,
	]


func _restore_terrain_properties(mesh: ArrayMesh) -> void:
	_terrain_height_minmax = mesh.get_meta("height_minmax", Vector2.ONE)
	_set_terrain_properties(float(mesh.get_meta("average_biome", 0.0)))


func _build_mesh_from_factors(resolution: int, factors: PackedFloat32Array, shading_data: PackedFloat32Array, perturbed := PackedVector3Array()) -> ArrayMesh:
	var topology := _topology_for(resolution)
	var directions: PackedVector3Array = topology.directions
	assert(factors.size() == directions.size())
	assert(shading_data.is_empty() or shading_data.size() == directions.size() * 4)
	assert(perturbed.is_empty() or perturbed.size() == directions.size())
	var shaped_vertices := PackedVector3Array()
	shaped_vertices.resize(directions.size())
	if perturbed.is_empty():
		for index in directions.size():
			shaped_vertices[index] = directions[index] * (_core_radius() * factors[index])
	else:
		for index in directions.size():
			shaped_vertices[index] = perturbed[index] * _core_radius()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = shaped_vertices
	arrays[Mesh.ARRAY_INDEX] = topology.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if shading_data.is_empty():
		return mesh
	# SurfaceTool.generate_normals() welds and reorders vertices, which would
	# desynchronise the per-direction shading data assigned below.
	var normals := _compute_normals(shaped_vertices, topology.indices)
	var tangents := PackedFloat32Array()
	tangents.resize(normals.size() * 4)
	var terrain_uv := PackedVector2Array()
	var terrain_uv2 := PackedVector2Array()
	terrain_uv.resize(directions.size())
	terrain_uv2.resize(directions.size())
	var minimum_factor := factors[0]
	var maximum_factor := factors[0]
	var biome_sum := 0.0
	for index in directions.size():
		var offset := index * 4
		terrain_uv[index] = Vector2(shading_data[offset], shading_data[offset + 1])
		terrain_uv2[index] = Vector2(shading_data[offset + 2], shading_data[offset + 3])
		biome_sum += shading_data[offset + 3]
		minimum_factor = minf(minimum_factor, factors[index])
		maximum_factor = maxf(maximum_factor, factors[index])
		var normal := normals[index]
		tangents[offset] = -normal.z
		tangents[offset + 2] = normal.x
		tangents[offset + 3] = 1.0
	var final_arrays := []
	final_arrays.resize(Mesh.ARRAY_MAX)
	final_arrays[Mesh.ARRAY_VERTEX] = shaped_vertices
	final_arrays[Mesh.ARRAY_NORMAL] = normals
	final_arrays[Mesh.ARRAY_TANGENT] = tangents
	final_arrays[Mesh.ARRAY_TEX_UV] = terrain_uv
	final_arrays[Mesh.ARRAY_TEX_UV2] = terrain_uv2
	final_arrays[Mesh.ARRAY_INDEX] = topology.indices
	var final_mesh := ArrayMesh.new()
	final_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, final_arrays)
	final_mesh.set_meta("height_minmax", Vector2(minimum_factor, maximum_factor))
	final_mesh.set_meta("average_biome", biome_sum / maxf(float(directions.size()), 1.0))
	return final_mesh


static func _compute_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
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


static func _topology_for(resolution: int) -> Dictionary:
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


func _set_terrain_properties(average_biome: float) -> void:
	if surface_style != "terrain":
		return
	_surface_material.set_shader_parameter("planet_radius", radius)
	_surface_material.set_shader_parameter("height_min_max", _terrain_height_minmax)
	if body_kind == "asteroid":
		_surface_material.set_shader_parameter("body_kind", 2)
		_surface_material.set_shader_parameter("asteroid_col_flat", Color(0.38, 0.35, 0.32))
		_surface_material.set_shader_parameter("asteroid_col_flat_deep", Color(0.19, 0.17, 0.16))
		_surface_material.set_shader_parameter("asteroid_col_steep", Color(0.28, 0.26, 0.25))
		_surface_material.set_shader_parameter("asteroid_col_steep_deep", Color(0.12, 0.11, 0.11))
		_surface_material.set_shader_parameter("asteroid_col_ambient", Color(0.30, 0.29, 0.30))
		_surface_material.set_shader_parameter("asteroid_height_min", radius * 2.0 / 3.0)
		_surface_material.set_shader_parameter("asteroid_height_max", radius * 4.0 / 3.0)
		_surface_material.set_shader_parameter("asteroid_height_bands", 4.0)
		return
	if body_kind == "glacier":
		_surface_material.set_shader_parameter("body_kind", 3)
		_surface_material.set_shader_parameter("glacier_col_flat", Color(0.86, 0.92, 0.97))
		_surface_material.set_shader_parameter("glacier_col_flat_deep", Color(0.42, 0.58, 0.72))
		_surface_material.set_shader_parameter("glacier_col_steep", Color(0.55, 0.62, 0.70))
		_surface_material.set_shader_parameter("glacier_col_steep_deep", Color(0.22, 0.30, 0.42))
		_surface_material.set_shader_parameter("glacier_col_ambient", Color(0.42, 0.50, 0.60))
		_surface_material.set_shader_parameter("glacier_height_min", _terrain_height_minmax.x)
		_surface_material.set_shader_parameter("glacier_height_max", _terrain_height_minmax.y)
		_surface_material.set_shader_parameter("glacier_height_bands", 9.0)
		return
	if body_kind == "cyclops":
		_surface_material.set_shader_parameter("body_kind", 4)
		_surface_material.set_shader_parameter("cyclops_core_color", Color(0.08, 1.0, 0.72))
		return
	_surface_material.set_shader_parameter("body_kind", 1 if _is_moon_profile() else 0)
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
	_apply_ice_caps()
	_apply_fresnel()
	_surface_material.set_shader_parameter("moon_average_biome_noise", average_biome)


func _apply_ice_caps() -> void:
	var strength := 0.0
	if not _is_moon_profile() and body_kind not in ["alien", "cyclops", "mirage"]:
		strength = 1.0
	_surface_material.set_shader_parameter("ice_cap_strength", strength)
	_surface_material.set_shader_parameter("ice_cap_color", Color.WHITE)
	_surface_material.set_shader_parameter("ice_cap_start", 0.94)
	_surface_material.set_shader_parameter("ice_cap_blend", 0.03)
	_surface_material.set_shader_parameter("ice_cap_noise_a", 3.0)
	_surface_material.set_shader_parameter("ice_cap_noise_b", 2.87)
	_surface_material.set_shader_parameter("ice_cap_highlight", 1.2)
	_surface_material.set_shader_parameter("ice_cap_specular", 0.704)
	_surface_material.set_shader_parameter("earth_noise_scale", 10.0)
	_surface_material.set_shader_parameter("earth_noise_scale_detail", 50.0)


func _apply_fresnel() -> void:
	var color := Color(1.0, 0.90105057, 0.6650944)
	var near_strength := 0.0
	var far_strength := 0.0
	if _is_moon_profile():
		near_strength = 1.0
		far_strength = 9.2
	_surface_material.set_shader_parameter("fresnel_color", color)
	_surface_material.set_shader_parameter("fresnel_strength_near", near_strength)
	_surface_material.set_shader_parameter("fresnel_strength_far", far_strength)
	_surface_material.set_shader_parameter("fresnel_power", 12.0)


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
		"mirage":
			_surface_material.set_shader_parameter("shore_low", Color(0.93, 0.82, 0.6))
			_surface_material.set_shader_parameter("shore_high", Color(0.85, 0.68, 0.44))
			_surface_material.set_shader_parameter("flat_low_a", Color(0.82, 0.6, 0.34))
			_surface_material.set_shader_parameter("flat_high_a", Color(0.6, 0.32, 0.14))
			_surface_material.set_shader_parameter("flat_low_b", Color(0.74, 0.5, 0.28))
			_surface_material.set_shader_parameter("flat_high_b", Color(0.46, 0.22, 0.1))
			_surface_material.set_shader_parameter("steep_low", Color(0.42, 0.26, 0.16))
			_surface_material.set_shader_parameter("steep_high", Color(0.2, 0.1, 0.06))
		"tumbling_bean":
			_surface_material.set_shader_parameter("moon_primary_a", Color(0.15864186, 0.18783918, 0.21698111))
			_surface_material.set_shader_parameter("moon_secondary_a", Color(0.38274297, 0.4439998, 0.5754717))
			_surface_material.set_shader_parameter("moon_primary_b", Color(0.039215688, 0.40392157, 0.3080389))
			_surface_material.set_shader_parameter("moon_secondary_b", Color(0.43867922, 1.0, 0.9953623))
			_surface_material.set_shader_parameter("moon_ejecta", Color.WHITE)
		"watchful_eye":
			_surface_material.set_shader_parameter("moon_primary_a", Color(0.72, 0.88, 0.94))
			_surface_material.set_shader_parameter("moon_secondary_a", Color(0.22, 0.48, 0.62))
			_surface_material.set_shader_parameter("moon_primary_b", Color(0.055, 0.075, 0.085))
			_surface_material.set_shader_parameter("moon_secondary_b", Color(0.42, 0.64, 0.70))
			_surface_material.set_shader_parameter("moon_ejecta", Color(0.88, 0.97, 1.0))
			_surface_material.set_shader_parameter("moon_biome_blend_strength", 0.5)
			_surface_material.set_shader_parameter("moon_biome_warp_strength", 5.0)
			_surface_material.set_shader_parameter("moon_random_biome_values", Vector4(-2.1, 0.35, -2.8, 4.2))


func _is_moon_profile() -> bool:
	return body_kind == "moon" or body_kind == "tumbling_bean" or body_kind == "watchful_eye"


func _collider_height_for(direction: Vector3) -> float:
	return get_collider_surface_radius(direction) - _core_radius()


func _height_for(direction: Vector3) -> float:
	return _core_radius() * (_height_generator.sample_factor(direction.normalized()) - 1.0)


func _core_radius() -> float:
	return radius if core_radius <= 0.0 else core_radius


func _ocean_level_above_core() -> float:
	return radius + ocean_level - _core_radius()
