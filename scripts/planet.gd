extends AnimatableBody3D

const PlanetQualityScript := preload("res://scripts/planet_quality.gd")
const PlanetHeightGeneratorScript := preload("res://scripts/planet_height_generator.gd")
const AtmosphereLutScript := preload("res://scripts/atmosphere_lut.gd")
const CyclopsGeometryScript := preload("res://scripts/cyclops_geometry.gd")
const EarthNoiseTexture := preload("res://assets/planet_textures/earth_noise.png")
const MoonNoiseTexture := preload("res://assets/planet_textures/moon_noise.png")
const CraterEjectaTexture := preload("res://assets/planet_textures/crater_ejecta_ray.png")
const MoonFlatNormalTexture := preload("res://assets/planet_textures/moon_normal_flat.png")
const MoonSteepNormalTexture := preload("res://assets/planet_textures/moon_normal_steep.png")
const OceanWaveATexture := preload("res://assets/ocean_textures/wave_a.png")
const OceanWaveBTexture := preload("res://assets/ocean_textures/wave_b.png")
const OceanFoamTexture := preload("res://assets/ocean_textures/water_foam.png")
const BlueNoiseTexture := preload("res://assets/planet_textures/blue_noise.png")
const CyclopsRockShader := preload("res://shaders/cyclops_rock.gdshader")
const MESH_CACHE_VERSION := 15
const WATCHFUL_EYE_DIRECTION := Vector3(0.0, 0.18, 1.0)
const OCEAN_FOAM_COLOR := Color(0.92, 0.98, 1.0)
const TORNADO_COUNT := 14
const STORM_CONTACT_COUNT := 9
const LANDING_ROCK_COUNT := 5
# Angular and dimensionless storm quantities; every storm *length* lives in CyclopsGeometryScript.
const STORM_MOTION_SCALE := 0.5
const STORM_MIN_SEPARATION := 0.453786
const STORM_ROCK_MIN_SEPARATION := 0.383972
# Storm grab, in surface gravities, and the catch radius as a multiple of the funnel radius.
const STORM_LIFT_GRAVITY_SCALE := 3.2
const STORM_POLAR_LIFT_SCALE := 1.3
const STORM_SWIRL_GRAVITY_SCALE := 1.7
const STORM_SUCTION_GRAVITY_SCALE := 0.7
const STORM_CATCH_MARGIN := 1.4
const STORM_LIFT_RELEASE_FRACTION := 0.85
const POLAR_TORNADO_WIDTH_SCALE := 2.25
const ATMOSPHERE_DITHER_STRENGTH := 0.3
const ATMOSPHERE_DITHER_SCALE := 3.89
const ATMOSPHERE_SCATTERING_POINTS := 10

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
@export var ocean_swell_height := 0.0
@export var ocean_swell_wavelength := 40.0
@export var ocean_swell_speed := 0.6
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
var _ocean_params := PackedFloat32Array()
var _atmosphere_params := PackedFloat32Array()
var _atmosphere_lut: RefCounted
var _atmosphere_lut_bound := false
var _height_generator: RefCounted
var _height_generator_initialized := false
var _storm_interior: Node3D
var _storm_orbits: Array[Node3D] = []
var _storm_rigs: Array[Skeleton3D] = []
var _storm_contacts: Array[Area3D] = []
var _storm_funnel_materials: Array[ShaderMaterial] = []
var _storm_glows: Array[GeometryInstance3D] = []
var _storm_lights: Array[OmniLight3D] = []
var _storm_elapsed := 0.0
var _storm_visibility := 0.0
var _storm_states: Array[Dictionary] = []
var _landing_rock_directions: Array[Vector3] = []
var _landing_rock_radii: Array[float] = []
var _lod_resolutions: Array[int] = []
var _active_lod := -1
var _terrain_height_minmax := Vector2.ONE
var _eye_basis := Basis.IDENTITY
var _collision_shape: CollisionShape3D
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
	_build_landing_rocks()
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
	_update_storms(delta)


func get_surface_radius_towards(direction: Vector3) -> float:
	return _core_radius() + _height_for(direction.normalized())


func sea_level() -> float:
	return radius + ocean_level


func get_water_depth(position_value: Vector3) -> float:
	if not has_ocean:
		return -INF
	return sea_level() - position_value.distance_to(global_position)


func get_storm_deck_gap() -> float:
	return CyclopsGeometryScript.deck_gap(sea_level())


func get_storm_deck_center() -> float:
	return CyclopsGeometryScript.deck_center(sea_level())


func get_storm_deck_inner_radius() -> float:
	return CyclopsGeometryScript.deck_inner_radius(sea_level())


func get_storm_deck_outer_radius() -> float:
	return CyclopsGeometryScript.deck_outer_radius(sea_level())


func get_storm_cloud_transition(position_value: Vector3) -> float:
	if body_kind != "cyclops":
		return 0.0
	return CyclopsGeometryScript.cloud_transition(sea_level(), position_value.distance_to(global_position))


func get_storm_sky_occlusion(position_value: Vector3) -> float:
	if body_kind != "cyclops":
		return 0.0
	return CyclopsGeometryScript.sky_occlusion(sea_level(), position_value.distance_to(global_position))


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
	if body_kind == "watchful_eye" and next_velocity.length_squared() > 0.000001:
		var travel_direction := next_velocity.normalized()
		var up := Vector3.UP if absf(travel_direction.y) < 0.98 else Vector3.RIGHT
		var eye_to_forward := Basis(Quaternion(WATCHFUL_EYE_DIRECTION.normalized(), Vector3.BACK))
		_eye_basis = Basis.looking_at(-travel_direction, up) * eye_to_forward
		# AnimatableBody3D reverts a rotation written on itself, so the mesh and
		# the collider are turned instead; both must stay in sync.
		if _terrain != null:
			_terrain.basis = _eye_basis
		if _collision_shape != null:
			_collision_shape.basis = _eye_basis


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
		return global_position + unit_direction * (sea_level() + clearance)
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
			score -= _height_generator.sample_shading_data(_eye_basis.inverse() * direction).w * 0.1
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
	_terrain.basis = _eye_basis
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
		job.faces = faces
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
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(job.faces)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.basis = _eye_basis
		add_child(collision)
		_collision_shape = collision
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
	var foam_distance := ocean_foam_distance
	var refraction_strength := ocean_refraction_strength
	var swell_height := ocean_swell_height
	if quality_profile == "mobile_low":
		foam_distance = ocean_foam_distance * 0.65
		refraction_strength = 0.0
		swell_height = 0.0
	var ambient_color := Color(0.0, 0.0, 0.0)
	var ambient_strength := 0.0
	var sky_diffusion := 0.0
	if body_kind == "cyclops":
		ambient_color = Color(0.02, 0.08, 0.075)
		ambient_strength = 0.24
		sky_diffusion = 0.34
	_ocean_params = PackedFloat32Array([
		global_position.x, global_position.y, global_position.z, get_ocean_effect_radius(),
		0.0, 1.0, 0.0, radius,
		ocean_shallow_color.r, ocean_shallow_color.g, ocean_shallow_color.b, ocean_depth_multiplier,
		ocean_deep_color.r, ocean_deep_color.g, ocean_deep_color.b, ocean_alpha_multiplier,
		ocean_specular_color.r, ocean_specular_color.g, ocean_specular_color.b, ocean_smoothness,
		ambient_color.r, ambient_color.g, ambient_color.b, ambient_strength,
		OCEAN_FOAM_COLOR.r, OCEAN_FOAM_COLOR.g, OCEAN_FOAM_COLOR.b, sky_diffusion,
		ocean_wave_strength, ocean_wave_scale, ocean_wave_speed, refraction_strength,
		ocean_foam_scale, foam_distance, 1.0 if body_kind == "cyclops" else 0.0, 0.0,
		underwater_tint.r, underwater_tint.g, underwater_tint.b, underwater_darkness,
		swell_height, ocean_swell_wavelength, ocean_swell_speed, 0.0,
	])
	for index in STORM_CONTACT_COUNT:
		_ocean_params.append_array(PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))


func _build_atmosphere() -> void:
	if not has_atmosphere:
		return
	var scattering := Vector3(
		pow(400.0 / atmosphere_wavelengths.x, 4.0),
		pow(400.0 / atmosphere_wavelengths.y, 4.0),
		pow(400.0 / atmosphere_wavelengths.z, 4.0)
	) * atmosphere_scattering_strength
	_atmosphere_params = PackedFloat32Array([
		global_position.x, global_position.y, global_position.z, radius,
		radius * (1.0 + atmosphere_scale), atmosphere_density_falloff, atmosphere_intensity, ATMOSPHERE_DITHER_STRENGTH,
		0.0, 1.0, 0.0, ATMOSPHERE_DITHER_SCALE,
		scattering.x, scattering.y, scattering.z, float(ATMOSPHERE_SCATTERING_POINTS),
		atmosphere_color.r, atmosphere_color.g, atmosphere_color.b, get_ocean_effect_radius(),
	])
	_atmosphere_lut = AtmosphereLutScript.new()
	_atmosphere_lut.initialize(1.0 + atmosphere_scale, atmosphere_density_falloff)


func get_ocean_effect_radius() -> float:
	return sea_level() + 0.03 if has_ocean else 0.0


func get_ocean_effect_params() -> PackedFloat32Array:
	_refresh_effect_transform_params()
	return _ocean_params


func get_atmosphere_effect_params() -> PackedFloat32Array:
	_refresh_effect_transform_params()
	return _atmosphere_params


func get_atmosphere_lut_texture() -> Texture2D:
	return _atmosphere_lut.texture if _atmosphere_lut_bound else null


func _build_landing_rocks() -> void:
	if body_kind != "cyclops":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed * 6211 + 203
	var material := ShaderMaterial.new()
	material.shader = CyclopsRockShader
	var ocean_radius := sea_level()
	for index in LANDING_ROCK_COUNT:
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
		_landing_rock_directions.append(direction)
		_landing_rock_radii.append(rock_radius)


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
		for existing in _landing_rock_directions:
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


func _surface_basis(direction: Vector3, roll: float) -> Basis:
	var reference := Vector3.UP if absf(direction.y) < 0.92 else Vector3.FORWARD
	var tangent := reference.cross(direction).normalized()
	var bitangent := tangent.cross(direction).normalized()
	return Basis(tangent, direction, bitangent).rotated(direction, roll)


func _build_storm_system() -> void:
	if body_kind != "cyclops":
		return
	# One opaque shell: cull_disabled means it already flips from exterior cloud ball to interior
	# ceiling when the camera crosses it, and the screen tint is opaque at that crossing.
	var cloud_shell := MeshInstance3D.new()
	cloud_shell.name = "StormCloudShell"
	var cloud_mesh := SphereMesh.new()
	cloud_mesh.radius = get_storm_deck_center()
	cloud_mesh.height = cloud_mesh.radius * 2.0
	cloud_mesh.radial_segments = 96
	cloud_mesh.rings = 48
	var cloud_material := ShaderMaterial.new()
	cloud_material.shader = preload("res://shaders/tornado.gdshader")
	cloud_shell.mesh = cloud_mesh
	cloud_shell.material_override = cloud_material
	cloud_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cloud_shell)
	_initialize_storm_states()


func _initialize_storm_states() -> void:
	if not _storm_states.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed * 3571 + 91
	_storm_states.append(_make_storm_state(rng, Vector3.UP, true, POLAR_TORNADO_WIDTH_SCALE, 0, "NorthPolarTornado"))
	_storm_states.append(_make_storm_state(rng, Vector3.DOWN, true, POLAR_TORNADO_WIDTH_SCALE, 0, "SouthPolarTornado"))
	for index in TORNADO_COUNT:
		var state := _make_storm_state(rng, Vector3.FORWARD, false, 1.0, rng.randi_range(0, 3), "TornadoOrbit%d" % index)
		state.direction = _choose_storm_direction(float(state.crown_radius), float(state.contact_radius), rng)
		var direction: Vector3 = state.direction
		var drift := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		)
		drift = (drift - direction * drift.dot(direction)).normalized()
		state.velocity = drift * rng.randf_range(0.012, 0.022) * STORM_MOTION_SCALE
		state.wander_axis = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		state.wander_phase = rng.randf_range(0.0, TAU)
		_storm_states.append(state)


func _make_storm_state(rng: RandomNumberGenerator, direction: Vector3, is_static: bool, width_scale: float, shape_kind: int, state_name: String) -> Dictionary:
	# The funnel spans the sea-to-deck gap by construction: its foot is pinned to sea_level() and
	# its crown always lands inside the deck, whatever the planet size.
	var funnel_height := CyclopsGeometryScript.funnel_height(sea_level(), rng.randf())
	var width := funnel_height * width_scale
	var crown_range := CyclopsGeometryScript.CROWN_RADIUS_RANGE
	var trunk_range := CyclopsGeometryScript.TRUNK_RADIUS_RANGE
	var base_range := CyclopsGeometryScript.BASE_RADIUS_RANGE
	var crown_radius := rng.randf_range(crown_range.x, crown_range.y) * width
	var roll := rng.randf_range(0.0, TAU)
	var phase := rng.randf_range(0.0, TAU)
	var base_radius := rng.randf_range(base_range.x, base_range.y) * width
	var trunk_radius := rng.randf_range(trunk_range.x, trunk_range.y) * width
	var shape_seed := 0.0 if is_static else rng.randf_range(0.0, 100.0)
	var bend_scale := 0.0 if is_static else rng.randf_range(0.85, 1.75)
	var bend_speed := 1.0 if is_static else rng.randf_range(0.72, 1.38)
	var sway_strength := 1.0 if is_static else rng.randf_range(0.8, 1.45)
	var pulse_strength := 0.0 if is_static else rng.randf_range(0.06, 0.16)
	return {
		"name": state_name,
		"direction": direction,
		"static": is_static,
		"shape_kind": shape_kind,
		"roll": roll,
		"phase": phase,
		"shape_seed": shape_seed,
		"bend_scale": bend_scale,
		"bend_speed": bend_speed,
		"sway_strength": sway_strength,
		"pulse_strength": pulse_strength,
		"funnel_height": funnel_height,
		"base_radius": base_radius,
		"trunk_radius": trunk_radius,
		"crown_radius": crown_radius,
		"contact_radius": crown_radius * CyclopsGeometryScript.CONTACT_RADIUS_RATIO,
		"velocity": Vector3.ZERO,
		"wander_axis": Vector3.RIGHT,
		"wander_phase": 0.0,
		"orbit": null,
		"contact": null,
	}


func _choose_storm_direction(crown_radius: float, contact_radius: float, rng: RandomNumberGenerator) -> Vector3:
	var best := Vector3.FORWARD
	var best_clearance := -INF
	for _attempt in 512:
		var candidate := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		var clearance := INF
		for state in _storm_states:
			var required := _storm_minimum_angle(crown_radius, float(state.crown_radius))
			clearance = minf(clearance, candidate.angle_to(state.direction) - required)
		for rock_index in _landing_rock_directions.size():
			var required := _storm_rock_minimum_angle(contact_radius, _landing_rock_radii[rock_index])
			clearance = minf(clearance, candidate.angle_to(_landing_rock_directions[rock_index]) - required)
		if clearance > best_clearance:
			best = candidate
			best_clearance = clearance
	return best


func _storm_minimum_angle(first_radius: float, second_radius: float) -> float:
	var margin := sea_level() * CyclopsGeometryScript.SEPARATION_MARGIN_RATIO
	var footprint := clampf((first_radius + second_radius + margin) / get_storm_deck_center(), 0.0, 0.95)
	return maxf(STORM_MIN_SEPARATION, asin(footprint))


func _storm_rock_minimum_angle(contact_radius: float, rock_radius: float) -> float:
	var margin := sea_level() * CyclopsGeometryScript.SEPARATION_MARGIN_RATIO
	var footprint := clampf((contact_radius + rock_radius + margin) / sea_level(), 0.0, 0.95)
	return maxf(STORM_ROCK_MIN_SEPARATION, asin(footprint))


func _build_storm_interior() -> void:
	if _storm_interior != null:
		return
	_storm_interior = Node3D.new()
	_storm_interior.name = "StormInterior"
	add_child(_storm_interior)
	var storm_rng := RandomNumberGenerator.new()
	storm_rng.seed = rng_seed * 3571 + 1901
	for index in _storm_states.size():
		var state: Dictionary = _storm_states[index]
		var shape_kind := int(state.shape_kind)
		var orbit := Node3D.new()
		orbit.name = String(state.name)
		orbit.basis = _storm_basis_for_direction(state.direction, float(state.roll))
		orbit.set_meta("shape_kind", shape_kind)
		orbit.set_meta("static", bool(state.static))
		_storm_interior.add_child(orbit)
		var funnel_height := float(state.funnel_height)
		var funnel_root := Node3D.new()
		funnel_root.name = "Tornado"
		funnel_root.position = Vector3(sea_level() + funnel_height * 0.5, 0.0, 0.0)
		funnel_root.rotation_degrees.z = -90.0
		orbit.add_child(funnel_root)
		var base_phase := float(state.phase)
		var shape_seed := float(state.shape_seed)
		var randomize_shape := not bool(state.static)
		var base_radius := float(state.base_radius)
		var trunk_radius := float(state.trunk_radius)
		var crown_radius := float(state.crown_radius)
		var skeleton := Skeleton3D.new()
		skeleton.name = "TornadoRig"
		skeleton.set_meta("phase", base_phase)
		skeleton.set_meta("static", bool(state.static))
		skeleton.set_meta("funnel_height", funnel_height)
		var bend_scale: float = [0.18, 0.42, 0.78, 1.0][shape_kind] if bool(state.static) else float(state.bend_scale) * [0.7, 0.9, 1.1, 1.25][shape_kind]
		skeleton.set_meta("bend_scale", bend_scale)
		skeleton.set_meta("bend_speed", float(state.bend_speed))
		for bone_index in 3:
			skeleton.add_bone(["Lower", "Middle", "Crown"][bone_index])
			var bone_height := lerpf(-funnel_height * 0.5, funnel_height * 0.5, float(bone_index) * 0.5)
			skeleton.set_bone_rest(bone_index, Transform3D(Basis.IDENTITY, Vector3(0.0, bone_height, 0.0)))
		funnel_root.add_child(skeleton)
		var funnel_mesh := _build_tornado_mesh(funnel_height, base_radius, trunk_radius, crown_radius, base_phase, shape_kind, shape_seed, randomize_shape)
		var skirt_mesh := _build_storm_skirt_mesh(funnel_height, base_radius, base_phase, shape_kind, shape_seed, randomize_shape)
		var skin := skeleton.create_skin_from_rest_transforms()
		for layer in 3:
			var funnel := MeshInstance3D.new()
			funnel.name = ["DenseCore", "ChurningMist", "OuterVapour"][layer]
			var funnel_material := ShaderMaterial.new()
			funnel_material.shader = load("res://shaders/tornado_funnel.gdshader")
			funnel_material.set_shader_parameter("phase", base_phase + float(layer) * 1.93)
			funnel_material.set_shader_parameter("layer_offset", float(layer) * 0.72)
			funnel_material.set_shader_parameter("radial_scale", 1.0 + float(layer) * 0.1)
			funnel_material.set_shader_parameter("shape_seed", shape_seed)
			funnel_material.set_shader_parameter("shape_change_amount", 0.0 if bool(state.static) else 1.0)
			funnel_material.set_shader_parameter("sway_strength", float(state.sway_strength))
			funnel_material.set_shader_parameter("pulse_strength", float(state.pulse_strength))
			var base_opacity: float = [0.96, 0.5, 0.26][layer]
			funnel_material.set_meta("base_opacity", base_opacity)
			funnel_material.set_shader_parameter("opacity", base_opacity * _storm_visibility)
			funnel.mesh = funnel_mesh
			funnel.skin = skin
			funnel.skeleton = NodePath("..")
			funnel.material_override = funnel_material
			funnel.custom_aabb = AABB(
				Vector3(-crown_radius * 1.5, -funnel_height * 0.6, -crown_radius * 1.5),
				Vector3(crown_radius * 3.0, funnel_height * 1.2, crown_radius * 3.0)
			)
			funnel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			skeleton.add_child(funnel)
			_storm_funnel_materials.append(funnel_material)
			var skirt := MeshInstance3D.new()
			skirt.name = ["SkirtCore", "SkirtMist", "SkirtVapour"][layer]
			skirt.mesh = skirt_mesh
			skirt.position.y = -funnel_height * 0.5
			skirt.material_override = funnel_material
			skirt.custom_aabb = AABB(
				Vector3(-base_radius * 5.0, -funnel_height * CyclopsGeometryScript.ACTIVE_BAND_RATIO, -base_radius * 5.0),
				Vector3(base_radius * 10.0, funnel_height * 0.35, base_radius * 10.0)
			)
			skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			funnel_root.add_child(skirt)
		var contact := Area3D.new()
		contact.name = "WaterDisplacementVolume"
		contact.position.y = -funnel_height * 0.5 + funnel_height * 0.009
		contact.collision_layer = 0
		contact.collision_mask = 0
		contact.monitoring = false
		contact.set_meta("radius", float(state.contact_radius))
		var contact_shape := CollisionShape3D.new()
		var contact_cylinder := CylinderShape3D.new()
		contact_cylinder.radius = float(state.contact_radius)
		contact_cylinder.height = funnel_height * 0.048
		contact_shape.shape = contact_cylinder
		contact.add_child(contact_shape)
		funnel_root.add_child(contact)
		_storm_orbits.append(orbit)
		_storm_rigs.append(skeleton)
		_storm_contacts.append(contact)
		state.orbit = orbit
		state.contact = contact
		_storm_states[index] = state
	_build_abyss_lights(storm_rng)
	_set_storm_visibility(_storm_visibility)


func _storm_basis_for_direction(direction: Vector3, roll: float) -> Basis:
	var reference := Vector3.UP if absf(direction.y) < 0.92 else Vector3.FORWARD
	var tangent := reference.cross(direction).normalized()
	var binormal := direction.cross(tangent).normalized()
	return Basis(direction, tangent, binormal).rotated(direction, roll)


func _build_tornado_mesh(funnel_height: float, base_radius: float, trunk_radius: float, crown_radius: float, phase: float, shape_kind: int, shape_seed: float, randomize_shape: bool) -> ArrayMesh:
	const RADIAL_SEGMENTS := 64
	const HEIGHT_SEGMENTS := 48
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	for ring in HEIGHT_SEGMENTS + 1:
		var height_fraction := float(ring) / float(HEIGHT_SEGMENTS)
		var body_blend := smoothstep(0.0, 0.56, height_fraction)
		var crown_blend := smoothstep(0.67, 0.94, height_fraction)
		if shape_kind == 1:
			body_blend = smoothstep(0.28, 0.82, height_fraction)
			crown_blend = smoothstep(0.78, 0.97, height_fraction)
		elif shape_kind == 0:
			body_blend = smoothstep(0.0, 0.42, height_fraction)
			crown_blend = smoothstep(0.72, 0.95, height_fraction)
		var body_radius := lerpf(base_radius, trunk_radius, body_blend)
		var profile_radius := lerpf(body_radius, crown_radius, crown_blend)
		var centre := _tornado_centre_offset(height_fraction, funnel_height, phase, shape_kind, shape_seed, randomize_shape)
		var lower_weight := clampf(1.0 - height_fraction * 2.0, 0.0, 1.0)
		var middle_weight := 1.0 - absf(height_fraction - 0.5) * 2.0
		var upper_weight := clampf(height_fraction * 2.0 - 1.0, 0.0, 1.0)
		var weight_sum := maxf(lower_weight + middle_weight + upper_weight, 0.0001)
		lower_weight /= weight_sum
		middle_weight /= weight_sum
		upper_weight /= weight_sum
		for segment in RADIAL_SEGMENTS + 1:
			var radial_fraction := float(segment) / float(RADIAL_SEGMENTS)
			var angle := radial_fraction * TAU
			var broad_lobe := sin(angle * 2.0 + height_fraction * 8.0 + phase) * lerpf(0.025, 0.11, crown_blend)
			var fine_lobe := sin(angle * 7.0 - height_fraction * 19.0 + phase * 2.3) * 0.045
			var vertical_bulge := 0.0
			if randomize_shape:
				broad_lobe = sin(angle * lerpf(1.5, 3.5, _tornado_shape_random(shape_seed, 4.0)) + height_fraction * lerpf(5.0, 12.0, _tornado_shape_random(shape_seed, 5.0)) + phase) * lerpf(0.035, 0.16, crown_blend)
				fine_lobe = sin(angle * lerpf(5.0, 10.0, _tornado_shape_random(shape_seed, 6.0)) - height_fraction * lerpf(14.0, 27.0, _tornado_shape_random(shape_seed, 7.0)) + phase * 2.3) * lerpf(0.025, 0.075, _tornado_shape_random(shape_seed, 8.0))
				vertical_bulge = sin(height_fraction * lerpf(2.0, 4.5, _tornado_shape_random(shape_seed, 9.0)) * PI + shape_seed) * lerpf(0.03, 0.11, _tornado_shape_random(shape_seed, 10.0))
			var ring_radius := profile_radius * (1.0 + broad_lobe + fine_lobe + vertical_bulge)
			var radial := Vector3(cos(angle), 0.0, sin(angle))
			vertices.append(Vector3(centre.x, (height_fraction - 0.5) * funnel_height, centre.y) + radial * ring_radius)
			normals.append(radial)
			colors.append(Color(lower_weight, middle_weight, upper_weight, crown_blend))
			uvs.append(Vector2(radial_fraction, height_fraction))
			bones.append_array(PackedInt32Array([0, 1, 2, 0]))
			weights.append_array(PackedFloat32Array([lower_weight, middle_weight, upper_weight, 0.0]))
	for ring in HEIGHT_SEGMENTS:
		for segment in RADIAL_SEGMENTS:
			var first := ring * (RADIAL_SEGMENTS + 1) + segment
			var next := first + RADIAL_SEGMENTS + 1
			indices.append_array(PackedInt32Array([first, next, first + 1, first + 1, next, next + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _tornado_shape_random(shape_seed: float, channel: float) -> float:
	return fposmod(sin(shape_seed * 12.9898 + channel * 78.233) * 43758.5453, 1.0)


# Coefficients are fractions of the funnel height, applied once at the end.
func _tornado_centre_offset(height_fraction: float, funnel_height: float, phase: float, shape_kind: int, shape_seed: float, randomize_shape: bool) -> Vector2:
	var centre := Vector2.ZERO
	match shape_kind:
		0:
			centre = Vector2(sin(height_fraction * 5.0), cos(height_fraction * 4.0)) * height_fraction * 0.005
		1:
			centre = Vector2(sin(height_fraction * 6.2), cos(height_fraction * 4.7)) * height_fraction * height_fraction * 0.032
		2:
			centre = Vector2(smoothstep(0.0, 1.0, height_fraction) * 0.162, sin(height_fraction * PI) * 0.032)
		3:
			centre = Vector2(sin(height_fraction * TAU) * 0.184, sin(height_fraction * PI) * 0.026)
	if randomize_shape:
		var irregular_frequency := lerpf(1.7, 3.8, _tornado_shape_random(shape_seed, 0.0))
		var irregular_amplitude := lerpf(0.017, 0.069, _tornado_shape_random(shape_seed, 1.0))
		var irregular := Vector2(
			sin(height_fraction * PI * irregular_frequency + shape_seed),
			cos(height_fraction * PI * (irregular_frequency * 0.73) + shape_seed * 1.37)
		) * pow(height_fraction, 1.25) * irregular_amplitude
		centre += irregular
	return centre.rotated(phase) * funnel_height


# Flared foot for the funnel: same shader, same UV.y scale and same lateral drift,
# so it reads as the funnel surface widening into the sea rather than a second effect.
func _build_storm_skirt_mesh(funnel_height: float, base_radius: float, phase: float, shape_kind: int, shape_seed: float, randomize_shape: bool) -> ArrayMesh:
	const RADIAL_SEGMENTS := 64
	const HEIGHT_SEGMENTS := 14
	var skirt_height := funnel_height * 0.3
	var flare_radius := base_radius * 2.2
	var base_centre := _tornado_centre_offset(0.0, funnel_height, phase, shape_kind, shape_seed, randomize_shape)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring in HEIGHT_SEGMENTS + 1:
		var ring_fraction := float(ring) / float(HEIGHT_SEGMENTS)
		var height_fraction := ring_fraction * skirt_height / funnel_height
		var profile_radius := lerpf(base_radius * 1.02, flare_radius, pow(1.0 - ring_fraction, 2.8))
		var centre := _tornado_centre_offset(height_fraction, funnel_height, phase, shape_kind, shape_seed, randomize_shape) - base_centre
		for segment in RADIAL_SEGMENTS + 1:
			var radial_fraction := float(segment) / float(RADIAL_SEGMENTS)
			var angle := radial_fraction * TAU
			var broad_lobe := sin(angle * 2.0 + height_fraction * 8.0 + phase) * 0.025
			var fine_lobe := sin(angle * 7.0 - height_fraction * 19.0 + phase * 2.3) * 0.045
			var ring_radius := profile_radius * (1.0 + broad_lobe + fine_lobe)
			var radial := Vector3(cos(angle), 0.0, sin(angle))
			vertices.append(Vector3(centre.x, ring_fraction * skirt_height, centre.y) + radial * ring_radius)
			normals.append(radial)
			colors.append(Color(1.0, 0.0, 0.0, 0.0))
			uvs.append(Vector2(radial_fraction, height_fraction))
	for ring in HEIGHT_SEGMENTS:
		for segment in RADIAL_SEGMENTS:
			var first := ring * (RADIAL_SEGMENTS + 1) + segment
			var next := first + RADIAL_SEGMENTS + 1
			indices.append_array(PackedInt32Array([first, next, first + 1, first + 1, next, next + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_abyss_lights(storm_rng: RandomNumberGenerator) -> void:
	var ocean_radius := sea_level()
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
		source.position = direction * (_core_radius() * storm_rng.randf_range(1.028, 1.110))
		_storm_interior.add_child(source)
		var glow := MeshInstance3D.new()
		var glow_mesh := SphereMesh.new()
		glow_mesh.radius = storm_rng.randf_range(0.005, 0.011) * ocean_radius
		glow_mesh.height = glow_mesh.radius * 2.0
		glow.mesh = glow_mesh
		glow.material_override = glow_material
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.transparency = 1.0 - _storm_visibility
		source.add_child(glow)
		_storm_glows.append(glow)
		var light := OmniLight3D.new()
		light.light_color = Color(0.12, 0.95, 0.75)
		var base_energy := storm_rng.randf_range(1.4, 2.3)
		light.set_meta("base_energy", base_energy)
		light.light_energy = base_energy * _storm_visibility
		light.omni_range = storm_rng.randf_range(0.145, 0.218) * ocean_radius
		light.omni_attenuation = 1.35
		light.shadow_enabled = false
		source.add_child(light)
		_storm_lights.append(light)


func _clear_storm_interior() -> void:
	if _storm_interior == null:
		return
	for index in _storm_states.size():
		var state: Dictionary = _storm_states[index]
		state.orbit = null
		state.contact = null
		_storm_states[index] = state
	_storm_interior.queue_free()
	_storm_interior = null
	_storm_orbits.clear()
	_storm_rigs.clear()
	_storm_contacts.clear()
	_storm_funnel_materials.clear()
	_storm_glows.clear()
	_storm_lights.clear()
	_storm_visibility = 0.0


# A tornado swallows whoever comes close instead of walling them out: the funnel sucks the player
# towards its axis, spins them around it and lifts them along it, then releases the lift under the
# crown so the ride ends as a ballistic throw.
func get_storm_push(world_position: Vector3) -> Vector3:
	if body_kind != "cyclops" or _storm_states.is_empty():
		return Vector3.ZERO
	var offset := world_position - global_position
	if offset.length_squared() < 0.0001:
		return Vector3.ZERO
	var ocean_radius := sea_level()
	var deck_gap := get_storm_deck_gap()
	var result := Vector3.ZERO
	for state in _storm_states:
		var axis := (global_basis * (state.direction as Vector3)).normalized()
		var along_axis := offset.dot(axis)
		var axial_height := along_axis - ocean_radius
		var funnel_height := float(state.funnel_height)
		if axial_height < -deck_gap * CyclopsGeometryScript.ACTIVE_BAND_RATIO or axial_height > funnel_height:
			continue
		var lateral := offset - axis * along_axis
		var height_fraction := clampf(axial_height / funnel_height, 0.0, 1.0)
		var catch_radius := lerpf(float(state.contact_radius), float(state.crown_radius), height_fraction) * STORM_CATCH_MARGIN
		var lateral_distance := lateral.length()
		if lateral_distance >= catch_radius:
			continue
		var radial_fraction := lateral_distance / catch_radius
		var grip := 1.0 - smoothstep(0.35, 1.0, radial_fraction)
		var lift_fade := 1.0 - smoothstep(STORM_LIFT_RELEASE_FRACTION, 1.0, height_fraction)
		var lift_scale := STORM_POLAR_LIFT_SCALE if bool(state.static) else 1.0
		result += axis * surface_gravity * STORM_LIFT_GRAVITY_SCALE * lift_scale * grip * lift_fade
		if lateral_distance <= 0.001:
			continue
		# Suction and swirl have no defined direction on the axis, and both fade to nothing there so
		# the middle of the funnel is a clean updraft.
		var inward := -lateral / lateral_distance
		var wall_fraction := minf(radial_fraction / 0.35, 1.0)
		result += inward * surface_gravity * STORM_SUCTION_GRAVITY_SCALE * grip * wall_fraction
		result += axis.cross(inward) * surface_gravity * STORM_SWIRL_GRAVITY_SCALE * grip * wall_fraction
	return result


func _set_storm_visibility(value: float) -> void:
	_storm_visibility = clampf(value, 0.0, 1.0)
	for material in _storm_funnel_materials:
		material.set_shader_parameter("opacity", float(material.get_meta("base_opacity")) * _storm_visibility)
	for glow in _storm_glows:
		glow.transparency = 1.0 - _storm_visibility
	for light in _storm_lights:
		light.light_energy = float(light.get_meta("base_energy")) * _storm_visibility


func _update_storm_motion(delta: float) -> void:
	for index in _storm_states.size():
		var state: Dictionary = _storm_states[index]
		if bool(state.static):
			continue
		var direction: Vector3 = state.direction
		var velocity: Vector3 = state.velocity
		var wander_axis: Vector3 = state.wander_axis
		var wander := wander_axis - direction * wander_axis.dot(direction)
		if wander.length_squared() < 0.0001:
			wander = direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT)
		velocity += wander.normalized() * sin(_storm_elapsed * 0.37 + float(state.wander_phase)) * 0.0025 * delta
		velocity -= direction * velocity.dot(direction)
		velocity = velocity.limit_length(0.025 * STORM_MOTION_SCALE)
		state.direction = (direction + velocity * delta).normalized()
		state.velocity = velocity
		_storm_states[index] = state
	for _iteration in 3:
		for first_index in _storm_states.size():
			for second_index in range(first_index + 1, _storm_states.size()):
				_enforce_storm_pair_separation(first_index, second_index)
		for state_index in _storm_states.size():
			var state: Dictionary = _storm_states[state_index]
			if bool(state.static):
				continue
			var direction: Vector3 = state.direction
			for rock_index in _landing_rock_directions.size():
				var required := _storm_rock_minimum_angle(float(state.contact_radius), _landing_rock_radii[rock_index])
				var angle := direction.angle_to(_landing_rock_directions[rock_index])
				if angle < required:
					direction = _move_direction_away(direction, _landing_rock_directions[rock_index], required - angle)
			state.direction = direction
			_storm_states[state_index] = state
	for index in _storm_states.size():
		var state: Dictionary = _storm_states[index]
		if not bool(state.static):
			var direction: Vector3 = state.direction
			var velocity: Vector3 = state.velocity
			state.velocity = (velocity - direction * velocity.dot(direction)) * 0.998
			_storm_states[index] = state
		var orbit: Node3D = state.orbit as Node3D
		if is_instance_valid(orbit):
			orbit.basis = _storm_basis_for_direction(state.direction, float(state.roll))


func _enforce_storm_pair_separation(first_index: int, second_index: int) -> void:
	var first: Dictionary = _storm_states[first_index]
	var second: Dictionary = _storm_states[second_index]
	var first_direction: Vector3 = first.direction
	var second_direction: Vector3 = second.direction
	var required := _storm_minimum_angle(float(first.crown_radius), float(second.crown_radius))
	var angle := first_direction.angle_to(second_direction)
	if angle >= required or (bool(first.static) and bool(second.static)):
		return
	var correction := required - angle
	if bool(first.static):
		second.direction = _move_direction_away(second_direction, first_direction, correction)
	elif bool(second.static):
		first.direction = _move_direction_away(first_direction, second_direction, correction)
	else:
		first.direction = _move_direction_away(first_direction, second_direction, correction * 0.5)
		second.direction = _move_direction_away(second_direction, first_direction, correction * 0.5)
	_storm_states[first_index] = first
	_storm_states[second_index] = second


func _move_direction_away(direction: Vector3, anchor: Vector3, angle: float) -> Vector3:
	var current_angle := direction.angle_to(anchor)
	var away := direction * cos(current_angle) - anchor
	if away.length_squared() < 0.0001:
		away = direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT)
	return (direction * cos(angle) + away.normalized() * sin(angle)).normalized()


func _update_storms(delta: float) -> void:
	if body_kind != "cyclops":
		return
	_storm_elapsed += delta
	_update_storm_motion(delta)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var camera_distance := camera.global_position.distance_to(global_position)
	var ocean_radius := sea_level()
	var preload_radius := CyclopsGeometryScript.streaming_radius(ocean_radius, CyclopsGeometryScript.PRELOAD_RATIO)
	var full_visibility_radius := CyclopsGeometryScript.streaming_radius(ocean_radius, CyclopsGeometryScript.FULL_VISIBILITY_RATIO)
	var fade_radius := CyclopsGeometryScript.streaming_radius(ocean_radius, CyclopsGeometryScript.FADE_RATIO)
	var unload_radius := CyclopsGeometryScript.streaming_radius(ocean_radius, CyclopsGeometryScript.UNLOAD_RATIO)
	var loaded_visibility := 1.0 - smoothstep(full_visibility_radius, fade_radius, camera_distance)
	var visibility := loaded_visibility * CyclopsGeometryScript.interior_visibility(ocean_radius, camera_distance)
	if camera_distance <= preload_radius and _storm_interior == null:
		_set_storm_visibility(visibility)
		_build_storm_interior()
	elif camera_distance > unload_radius and _storm_interior != null:
		_clear_storm_interior()
	if _storm_interior != null:
		_set_storm_visibility(visibility)
	for rig_index in _storm_rigs.size():
		var rig := _storm_rigs[rig_index]
		var phase := float(rig.get_meta("phase"))
		var bend_scale := float(rig.get_meta("bend_scale"))
		var bend_speed := float(rig.get_meta("bend_speed"))
		var funnel_height := float(rig.get_meta("funnel_height"))
		for bone_index in 3:
			var height_weight := float(bone_index + 1) / 3.0
			var churn := _storm_elapsed * (1.15 + height_weight * 0.72) * STORM_MOTION_SCALE * bend_speed + phase + float(bone_index) * 1.8
			if bool(rig.get_meta("static")):
				var tilt := Vector3(sin(churn * 0.43), 0.0, cos(churn * 0.37)) * (0.025 + height_weight * 0.055) * bend_scale
				var twist := Quaternion(Vector3.UP, sin(churn * 0.53) * (0.08 + height_weight * 0.15) * bend_scale)
				rig.set_bone_pose_rotation(bone_index, Basis.from_euler(tilt).get_rotation_quaternion() * twist)
				var rest_position := rig.get_bone_rest(bone_index).origin
				rig.set_bone_pose_position(bone_index, rest_position + Vector3(sin(churn * 0.71), 0.0, cos(churn * 0.57)) * height_weight * 0.007 * bend_scale * funnel_height)
				continue
			var secondary_churn := _storm_elapsed * 0.19 * bend_speed + phase * 1.7 + float(bone_index) * 0.9
			var tilt := Vector3(sin(churn * 0.43) + sin(secondary_churn) * 0.45, 0.0, cos(churn * 0.37) + cos(secondary_churn * 0.83) * 0.4) * (0.04 + height_weight * 0.085) * bend_scale
			var twist := Quaternion(Vector3.UP, sin(churn * 0.53) * (0.1 + height_weight * 0.18) * bend_scale)
			rig.set_bone_pose_rotation(bone_index, Basis.from_euler(tilt).get_rotation_quaternion() * twist)
			var rest_position := rig.get_bone_rest(bone_index).origin
			var sway := Vector3(sin(churn * 0.71) + sin(secondary_churn * 1.13) * 0.65, 0.0, cos(churn * 0.57) + cos(secondary_churn) * 0.6)
			rig.set_bone_pose_position(bone_index, rest_position + sway * height_weight * 0.016 * bend_scale * funnel_height)


func _poll_atmosphere_lut() -> void:
	if _atmosphere_lut_bound or _atmosphere_lut == null or _atmosphere_lut.texture == null:
		return
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


func _refresh_effect_transform_params() -> void:
	var direction := Vector3.UP
	var sun := get_tree().get_first_node_in_group("sun") as Node3D
	if sun != null:
		direction = (sun.global_position - global_position).normalized()
	if not _ocean_params.is_empty():
		_ocean_params[0] = global_position.x
		_ocean_params[1] = global_position.y
		_ocean_params[2] = global_position.z
		_ocean_params[4] = direction.x
		_ocean_params[5] = direction.y
		_ocean_params[6] = direction.z
		for index in STORM_CONTACT_COUNT:
			var offset := 44 + index * 4
			if index < _storm_contacts.size() and is_instance_valid(_storm_contacts[index]):
				var contact := _storm_contacts[index]
				var contact_position := contact.global_position
				_ocean_params[offset] = contact_position.x
				_ocean_params[offset + 1] = contact_position.y
				_ocean_params[offset + 2] = contact_position.z
				_ocean_params[offset + 3] = float(contact.get_meta("radius")) * _storm_visibility
			else:
				_ocean_params[offset + 3] = 0.0
	if not _atmosphere_params.is_empty():
		_atmosphere_params[0] = global_position.x
		_atmosphere_params[1] = global_position.y
		_atmosphere_params[2] = global_position.z
		_atmosphere_params[8] = direction.x
		_atmosphere_params[9] = direction.y
		_atmosphere_params[10] = direction.z


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
	# Spires stand far above the crust, so leaving them in the range would squash
	# every crust colour into the bottom of the shading ramp.
	maximum_factor -= _height_generator.spike_height_span()
	final_mesh.set_meta("height_minmax", Vector2(minimum_factor, maxf(maximum_factor, minimum_factor + 0.0001)))
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
			_surface_material.set_shader_parameter("moon_smoothness_a", 0.42)
			_surface_material.set_shader_parameter("moon_smoothness_b", 0.16)
			_surface_material.set_shader_parameter("moon_smoothness_ejecta", 0.55)
			_surface_material.set_shader_parameter("moon_specular", 0.6)
			_surface_material.set_shader_parameter("eye_strength", 1.0)
			_surface_material.set_shader_parameter("eye_direction", WATCHFUL_EYE_DIRECTION.normalized())
			_surface_material.set_shader_parameter("eye_sclera_radius", 0.6)
			_surface_material.set_shader_parameter("eye_iris_radius", 0.3)
			_surface_material.set_shader_parameter("eye_pupil_radius", 0.12)
			_surface_material.set_shader_parameter("eye_sclera_color", Color(0.88, 0.95, 1.0))
			_surface_material.set_shader_parameter("eye_iris_color", Color(0.07, 0.24, 0.34))
			_surface_material.set_shader_parameter("eye_pupil_color", Color(0.01, 0.02, 0.035))
			_surface_material.set_shader_parameter("eye_glow", 0.12)


func _is_moon_profile() -> bool:
	return body_kind == "moon" or body_kind == "tumbling_bean" or body_kind == "watchful_eye"


func _collider_height_for(direction: Vector3) -> float:
	return get_collider_surface_radius(direction) - _core_radius()


func _height_for(direction: Vector3) -> float:
	var local_direction := _eye_basis.inverse() * direction.normalized()
	return _core_radius() * (_height_generator.sample_factor(local_direction) - 1.0)


func _core_radius() -> float:
	return radius if core_radius <= 0.0 else core_radius


func _ocean_level_above_core() -> float:
	return sea_level() - _core_radius()
