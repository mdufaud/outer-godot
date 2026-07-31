class_name PlanetBody
extends AnimatableBody3D

const PlanetConfigScript := preload("res://game/planets/shared/planet_config.gd")
const PlanetDefaultsScript := preload("res://game/planets/shared/planet_defaults.gd")
const PlanetShapeProfileScript := preload("res://game/planets/shared/planet_shape_profile.gd")
const PlanetQualityScript := preload("res://game/planets/shared/planet_quality.gd")
const PlanetHeightGeneratorScript := preload("res://game/planets/shared/planet_generator.gd")
const PlanetTopologyScript := preload("res://game/planets/shared/planet_topology.gd")
const PlanetCacheScript := preload("res://game/planets/shared/planet_cache.gd")
const AtmosphereLutScript := preload("res://game/planets/shared/atmosphere_lut.gd")
const GravityServiceScript := preload("res://game/celestial/gravity.gd")
const EarthNoiseTexture := preload("res://assets/shared/planet_textures/earth_noise.png")
const MoonNoiseTexture := preload("res://assets/shared/planet_textures/moon_noise.png")
const CraterEjectaTexture := preload("res://assets/shared/planet_textures/crater_ejecta_ray.png")
const MoonFlatNormalTexture := preload("res://assets/shared/planet_textures/moon_normal_flat.png")
const MoonSteepNormalTexture := preload("res://assets/shared/planet_textures/moon_normal_steep.png")
const OceanWaveATexture := preload("res://assets/shared/ocean_textures/wave_a.png")
const OceanWaveBTexture := preload("res://assets/shared/ocean_textures/wave_b.png")
const OceanFoamTexture := preload("res://assets/shared/ocean_textures/water_foam.png")
const BlueNoiseTexture := preload("res://assets/shared/planet_textures/blue_noise.png")
const LavaShader := preload("res://game/planets/shared/shaders/lava.gdshader")
const IceShader := preload("res://game/planets/shared/shaders/ice.gdshader")
const ProceduralPlanetShader := preload("res://game/planets/shared/shaders/procedural_planet.gdshader")
const WATCHFUL_EYE_DIRECTION := Vector3(0.0, 0.18, 1.0)
const OCEAN_FOAM_COLOR := Color(0.92, 0.98, 1.0)
const ATMOSPHERE_DITHER_STRENGTH := 0.3
const ATMOSPHERE_DITHER_SCALE := 3.89
const ATMOSPHERE_SCATTERING_POINTS := 10
const MAX_WEATHER_CONTACTS := 9

var config: PlanetConfig
var body_id: StringName = &"Planet"
var quality_override: StringName = &""
var shape_profile := PlanetShapeProfileScript.EARTH
var surface_style: StringName = &"terrain"
var radius := 0.0
var core_radius := 0.0
var surface_gravity := 0.0
var influence_scale := 30.0
var rng_seed := 0
var perturb_strength := 0.0
var quality_profile: StringName = &"desktop_high"
var has_ocean := false
var ocean_level := 0.0
var ocean_shallow_color := Color.WHITE
var ocean_deep_color := Color.BLACK
var ocean_wave_strength := 0.0
var ocean_wave_scale := 1.0
var ocean_wave_speed := 0.0
var ocean_smoothness := 0.0
var ocean_depth_multiplier := 1.0
var ocean_alpha_multiplier := 1.0
var ocean_specular_color := Color.WHITE
var ocean_foam_scale := 1.0
var ocean_foam_distance := 0.0
var ocean_refraction_strength := 0.0
var ocean_swell_height := 0.0
var ocean_swell_wavelength := 1.0
var ocean_swell_speed := 0.0
var underwater_tint := Color(0.1, 0.4, 0.5)
var underwater_darkness := 0.45
var has_atmosphere := false
var atmosphere_color := Color.WHITE
var atmosphere_scale := 0.0
var atmosphere_density_falloff := 1.0
var atmosphere_wavelengths := Vector3.ONE
var atmosphere_scattering_strength := 0.0
var atmosphere_intensity := 0.0
var material_profile := PlanetShapeProfileScript.EARTH
var weather_enabled := false
var weather_contact_count := 0
var shore_color := Color(0.66, 0.58, 0.36)
var land_low_color := Color(0.13, 0.34, 0.12)
var land_high_color := Color(0.35, 0.24, 0.12)

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
var _rock_feature: Node
var _weather_feature: Node
var _lod_resolutions: Array[int] = []
var _active_lod := -1
var _terrain_height_minmax := Vector2.ONE
var _eye_basis := Basis.IDENTITY
var _collision_shape: CollisionShape3D
var _boot_jobs: Array[Dictionary] = []
var _collision_ready := false
var _collider_peak_radius := 0.0
@onready var gravity_service: GravityService = get_node("/root/Gravity")


func configure_planet(_config: PlanetConfig) -> void:
	pass


func create_planet_config() -> PlanetConfig:
	var next_config := PlanetDefaultsScript.create_config()
	configure_planet(next_config)
	return next_config


func _apply_config(next_config: PlanetConfig) -> void:
	config = next_config
	body_id = config.body_id
	shape_profile = config.shape_profile
	radius = config.radius
	core_radius = config.core_radius
	surface_gravity = config.surface_gravity
	influence_scale = config.influence_scale
	rng_seed = config.rng_seed
	perturb_strength = config.perturb_strength
	quality_profile = config.quality_profile
	surface_style = config.surface.style
	material_profile = config.surface.material_profile
	shore_color = config.surface.shore_color
	land_low_color = config.surface.land_low_color
	land_high_color = config.surface.land_high_color
	has_ocean = config.ocean.enabled
	ocean_level = config.ocean.level
	ocean_shallow_color = config.ocean.shallow_color
	ocean_deep_color = config.ocean.deep_color
	ocean_wave_strength = config.ocean.wave_strength
	ocean_wave_scale = config.ocean.wave_scale
	ocean_wave_speed = config.ocean.wave_speed
	ocean_smoothness = config.ocean.smoothness
	ocean_depth_multiplier = config.ocean.depth_multiplier
	ocean_alpha_multiplier = config.ocean.alpha_multiplier
	ocean_specular_color = config.ocean.specular_color
	ocean_foam_scale = config.ocean.foam_scale
	ocean_foam_distance = config.ocean.foam_distance
	ocean_refraction_strength = config.ocean.refraction_strength
	ocean_swell_height = config.ocean.swell_height
	ocean_swell_wavelength = config.ocean.swell_wavelength
	ocean_swell_speed = config.ocean.swell_speed
	underwater_tint = config.ocean.underwater_tint
	underwater_darkness = config.ocean.underwater_darkness
	has_atmosphere = config.atmosphere.enabled
	atmosphere_color = config.atmosphere.color
	atmosphere_scale = config.atmosphere.scale
	atmosphere_density_falloff = config.atmosphere.density_falloff
	atmosphere_wavelengths = config.atmosphere.wavelengths
	atmosphere_scattering_strength = config.atmosphere.scattering_strength
	atmosphere_intensity = config.atmosphere.intensity
	weather_enabled = config.weather.enabled
	weather_contact_count = config.weather.contact_count


func _ready() -> void:
	var next_config := create_planet_config()
	if not quality_override.is_empty():
		next_config.quality_profile = quality_override
	_apply_config(next_config)
	add_to_group("celestial_body")
	collision_layer = 2
	influence_radius = radius * influence_scale
	_height_generator = PlanetHeightGeneratorScript.new(shape_profile, rng_seed)
	_build_terrain()
	_build_collision()
	_build_ocean()
	_build_atmosphere()
	_build_optional_features()
	for job in _boot_jobs:
		if job.phase == "topology":
			_height_generator.initialize()
			_height_generator_initialized = true
			break
	gravity_service.register(self)


func _exit_tree() -> void:
	if _height_generator != null and _height_generator_initialized:
		_height_generator.shutdown()
	if _atmosphere_lut != null:
		_atmosphere_lut.shutdown()
	gravity_service.unregister(self)


func _process(delta: float) -> void:
	_poll_boot()
	_poll_atmosphere_lut()
	_update_lod()
	_update_lighting()


func get_surface_radius_towards(direction: Vector3) -> float:
	return _core_radius() + _height_for(direction.normalized())


func sea_level() -> float:
	return radius + ocean_level


func get_core_radius() -> float:
	return _core_radius()


func get_water_depth(position_value: Vector3) -> float:
	if not has_ocean:
		return -INF
	return sea_level() - position_value.distance_to(global_position)


func _build_optional_features() -> void:
	if config.weather.rock_feature_script != null:
		_rock_feature = config.weather.rock_feature_script.new()
		_rock_feature.setup(self)
		add_child(_rock_feature)
	if weather_enabled and config.weather.feature_script != null:
		_weather_feature = config.weather.feature_script.new()
		_weather_feature.setup(self)
		add_child(_weather_feature)


func _weather_geometry() -> Script:
	return config.weather.geometry if config != null else null


func get_weather_deck_gap() -> float:
	if not weather_enabled or _weather_geometry() == null:
		return 0.0
	return _weather_geometry().deck_gap(sea_level())


func get_weather_deck_center() -> float:
	if not weather_enabled or _weather_geometry() == null:
		return 0.0
	return _weather_geometry().deck_center(sea_level())


func get_weather_deck_inner_radius() -> float:
	if not weather_enabled or _weather_geometry() == null:
		return 0.0
	return _weather_geometry().deck_inner_radius(sea_level())


func get_weather_deck_outer_radius() -> float:
	if not weather_enabled or _weather_geometry() == null:
		return 0.0
	return _weather_geometry().deck_outer_radius(sea_level())


func get_weather_cloud_transition(position_value: Vector3) -> float:
	if not weather_enabled:
		return 0.0
	return _weather_geometry().cloud_transition(sea_level(), position_value.distance_to(global_position))


func get_weather_sky_occlusion(position_value: Vector3) -> float:
	if not weather_enabled:
		return 0.0
	return _weather_geometry().sky_occlusion(sea_level(), position_value.distance_to(global_position))


func get_environment_force(world_position: Vector3) -> Vector3:
	if _weather_feature != null and _weather_feature.has_method("get_environment_force"):
		return _weather_feature.get_environment_force(world_position)
	return Vector3.ZERO


func has_weather_capability() -> bool:
	return weather_enabled


func get_weather_feedback(position_value: Vector3) -> Dictionary:
	return {
		"cloud_transition": get_weather_cloud_transition(position_value),
		"sky_occlusion": get_weather_sky_occlusion(position_value),
		"rain_strength": get_weather_rain_strength(position_value),
	}


func get_weather_rain_strength(position_value: Vector3) -> float:
	if not weather_enabled:
		return 0.0
	var camera_radius := position_value.distance_to(global_position)
	return 1.0 - smoothstep(get_weather_deck_inner_radius(), get_weather_deck_outer_radius(), camera_radius)


func get_weather_contacts() -> Array[Area3D]:
	if _weather_feature != null and _weather_feature.has_method("get_contacts"):
		return _weather_feature.get_contacts()
	return []


func get_weather_visibility() -> float:
	if _weather_feature != null and _weather_feature.has_method("get_visibility"):
		return float(_weather_feature.get_visibility())
	return 0.0


func get_landing_rock_directions() -> Array[Vector3]:
	if _rock_feature != null and _rock_feature.has_method("get_directions"):
		return _rock_feature.get_directions()
	return []


func get_landing_rock_radii() -> Array[float]:
	if _rock_feature != null and _rock_feature.has_method("get_radii"):
		return _rock_feature.get_radii()
	return []


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
	if shape_profile == PlanetShapeProfileScript.WATCHFUL_EYE and next_velocity.length_squared() > 0.000001:
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
	# Start clear of the highest peak on deformed bodies.
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
	if weather_enabled and has_ocean:
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
			_surface_material.shader = LavaShader
			_surface_material.set_shader_parameter("base_color", Color(0.103773594, 0.058548227, 0.042586338))
			_surface_material.set_shader_parameter("glow_color", Color(1.0, 0.1909248, 0.0))
		"ice":
			_surface_material.shader = IceShader
			_surface_material.set_shader_parameter("base_color", Color(0.66245013, 0.58739763, 0.754717))
			_surface_material.set_shader_parameter("crack_color", Color(0.21960784, 0.2784314, 0.42352942))
		_:
			_surface_material.shader = ProceduralPlanetShader
	_terrain.material_override = _surface_material
	add_child(_terrain)
	var cached_meshes: Array[ArrayMesh] = []
	for resolution in _lod_resolutions:
		var cached_mesh := PlanetCacheScript.load_mesh("terrain", resolution, shape_profile, rng_seed, _core_radius(), perturb_strength)
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
	_collision_mesh = PlanetCacheScript.load_mesh("collision", resolution, shape_profile, rng_seed, _core_radius(), perturb_strength)
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
			if _height_generator.request(PlanetTopologyScript.build_for(int(job.resolution)).directions):
				job.phase = "heights_wait"
		"heights_wait":
			if _height_generator.has_result():
				job.factors = _height_generator.take_result()
				if perturb_strength > 0.0:
					job.phase = "perturb"
				else:
					job.phase = "shading" if job.kind == "lod" else "build"
		"perturb":
			var directions: PackedVector3Array = PlanetTopologyScript.build_for(int(job.resolution)).directions
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
			if _height_generator.request_shading(PlanetTopologyScript.build_for(int(job.resolution)).directions):
				job.phase = "shading_wait"
		"shading_wait":
			if _height_generator.has_shading_result():
				job.shading = _height_generator.take_shading_result()
				job.phase = "build"
		"build":
			job.spike_height_span = _height_generator.spike_height_span()
			job.task_id = WorkerThreadPool.add_task(_run_build_job.bind(job), false, "Build %s %s" % [name, job.kind])
			job.phase = "build_wait"
		"build_wait":
			if WorkerThreadPool.is_task_completed(int(job.task_id)):
				WorkerThreadPool.wait_for_task_completion(int(job.task_id))
				_finish_build_job(job)
				_boot_jobs.pop_front()


static func _build_topology_task(resolution: int) -> void:
	PlanetTopologyScript.build_for(resolution)


func _run_build_job(job: Dictionary) -> void:
	if job.kind == "collision":
		var mesh: ArrayMesh = job.get("mesh")
		if mesh == null:
			mesh = _build_mesh_from_factors(int(job.resolution), job.factors, PackedFloat32Array(), job.get("perturbed", PackedVector3Array()), float(job.get("spike_height_span", 0.0)))
			PlanetCacheScript.save_mesh(mesh, "collision", int(job.resolution), shape_profile, rng_seed, _core_radius(), perturb_strength)
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
	var lod_mesh := _build_mesh_from_factors(int(job.resolution), job.factors, job.shading, job.get("perturbed", PackedVector3Array()), float(job.get("spike_height_span", 0.0)))
	PlanetCacheScript.save_mesh(lod_mesh, "terrain", int(job.resolution), shape_profile, rng_seed, _core_radius(), perturb_strength)
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
	if weather_enabled:
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
		ocean_foam_scale, foam_distance, 1.0 if weather_enabled else 0.0, 0.0,
		underwater_tint.r, underwater_tint.g, underwater_tint.b, underwater_darkness,
		swell_height, ocean_swell_wavelength, ocean_swell_speed, 0.0,
	])
	for index in MAX_WEATHER_CONTACTS:
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
		var contacts := get_weather_contacts()
		var weather_visibility := get_weather_visibility()
		for index in weather_contact_count:
			var offset := 44 + index * 4
			if index < contacts.size() and is_instance_valid(contacts[index]):
				var contact := contacts[index]
				var contact_position := contact.global_position
				_ocean_params[offset] = contact_position.x
				_ocean_params[offset + 1] = contact_position.y
				_ocean_params[offset + 2] = contact_position.z
				_ocean_params[offset + 3] = float(contact.get_meta("radius")) * weather_visibility
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


func _restore_terrain_properties(mesh: ArrayMesh) -> void:
	_terrain_height_minmax = mesh.get_meta("height_minmax", Vector2.ONE)
	_set_terrain_properties(float(mesh.get_meta("average_biome", 0.0)))


func _build_mesh_from_factors(resolution: int, factors: PackedFloat32Array, shading_data: PackedFloat32Array, perturbed := PackedVector3Array(), spike_height_span := 0.0) -> ArrayMesh:
	var topology := PlanetTopologyScript.build_for(resolution)
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
	var normals := PlanetTopologyScript.compute_normals(shaped_vertices, topology.indices)
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
	maximum_factor -= spike_height_span
	final_mesh.set_meta("height_minmax", Vector2(minimum_factor, maxf(maximum_factor, minimum_factor + 0.0001)))
	final_mesh.set_meta("average_biome", biome_sum / maxf(float(directions.size()), 1.0))
	return final_mesh


func _set_terrain_properties(average_biome: float) -> void:
	if surface_style != "terrain":
		return
	_surface_material.set_shader_parameter("planet_radius", radius)
	_surface_material.set_shader_parameter("height_min_max", _terrain_height_minmax)
	if material_profile == PlanetShapeProfileScript.ASTEROID:
		_surface_material.set_shader_parameter("material_profile", 2)
		_surface_material.set_shader_parameter("asteroid_col_flat", Color(0.38, 0.35, 0.32))
		_surface_material.set_shader_parameter("asteroid_col_flat_deep", Color(0.19, 0.17, 0.16))
		_surface_material.set_shader_parameter("asteroid_col_steep", Color(0.28, 0.26, 0.25))
		_surface_material.set_shader_parameter("asteroid_col_steep_deep", Color(0.12, 0.11, 0.11))
		_surface_material.set_shader_parameter("asteroid_col_ambient", Color(0.30, 0.29, 0.30))
		_surface_material.set_shader_parameter("asteroid_height_min", radius * 2.0 / 3.0)
		_surface_material.set_shader_parameter("asteroid_height_max", radius * 4.0 / 3.0)
		_surface_material.set_shader_parameter("asteroid_height_bands", 4.0)
		return
	if material_profile == PlanetShapeProfileScript.GLACIER:
		_surface_material.set_shader_parameter("material_profile", 3)
		_surface_material.set_shader_parameter("glacier_col_flat", Color(0.86, 0.92, 0.97))
		_surface_material.set_shader_parameter("glacier_col_flat_deep", Color(0.42, 0.58, 0.72))
		_surface_material.set_shader_parameter("glacier_col_steep", Color(0.55, 0.62, 0.70))
		_surface_material.set_shader_parameter("glacier_col_steep_deep", Color(0.22, 0.30, 0.42))
		_surface_material.set_shader_parameter("glacier_col_ambient", Color(0.42, 0.50, 0.60))
		_surface_material.set_shader_parameter("glacier_height_min", _terrain_height_minmax.x)
		_surface_material.set_shader_parameter("glacier_height_max", _terrain_height_minmax.y)
		_surface_material.set_shader_parameter("glacier_height_bands", 9.0)
		return
	if material_profile == PlanetShapeProfileScript.CYCLOPS:
		_surface_material.set_shader_parameter("material_profile", 4)
		_surface_material.set_shader_parameter("core_emission_color", Color(0.08, 1.0, 0.72))
		return
	_surface_material.set_shader_parameter("material_profile", 1 if _is_moon_profile() else 0)
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
	if not _is_moon_profile() and material_profile not in [PlanetShapeProfileScript.ALIEN, PlanetShapeProfileScript.CYCLOPS, PlanetShapeProfileScript.MIRAGE]:
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
	match material_profile:
		PlanetShapeProfileScript.CYCLOPS, PlanetShapeProfileScript.ALIEN:
			_surface_material.set_shader_parameter("shore_low", Color(0.7208405, 0.5613208, 1.0))
			_surface_material.set_shader_parameter("shore_high", Color(0.7208405, 0.5613208, 1.0))
			_surface_material.set_shader_parameter("flat_low_a", Color(0.6037736, 0.26556534, 0.21929511))
			_surface_material.set_shader_parameter("flat_high_a", Color(0.1643025, 0.0074759563, 0.5283019))
			_surface_material.set_shader_parameter("flat_low_b", Color(0.69101536, 0.36765754, 0.9622642))
			_surface_material.set_shader_parameter("flat_high_b", Color(0.110119045, 0.0, 0.2264151))
			_surface_material.set_shader_parameter("steep_low", Color(0.50084054, 0.19624422, 0.8490566))
			_surface_material.set_shader_parameter("steep_high", Color.WHITE)
		PlanetShapeProfileScript.MIRAGE:
			_surface_material.set_shader_parameter("shore_low", Color(0.93, 0.82, 0.6))
			_surface_material.set_shader_parameter("shore_high", Color(0.85, 0.68, 0.44))
			_surface_material.set_shader_parameter("flat_low_a", Color(0.82, 0.6, 0.34))
			_surface_material.set_shader_parameter("flat_high_a", Color(0.6, 0.32, 0.14))
			_surface_material.set_shader_parameter("flat_low_b", Color(0.74, 0.5, 0.28))
			_surface_material.set_shader_parameter("flat_high_b", Color(0.46, 0.22, 0.1))
			_surface_material.set_shader_parameter("steep_low", Color(0.42, 0.26, 0.16))
			_surface_material.set_shader_parameter("steep_high", Color(0.2, 0.1, 0.06))
		PlanetShapeProfileScript.TUMBLING_BEAN:
			_surface_material.set_shader_parameter("moon_primary_a", Color(0.15864186, 0.18783918, 0.21698111))
			_surface_material.set_shader_parameter("moon_secondary_a", Color(0.38274297, 0.4439998, 0.5754717))
			_surface_material.set_shader_parameter("moon_primary_b", Color(0.039215688, 0.40392157, 0.3080389))
			_surface_material.set_shader_parameter("moon_secondary_b", Color(0.43867922, 1.0, 0.9953623))
			_surface_material.set_shader_parameter("moon_ejecta", Color.WHITE)
		PlanetShapeProfileScript.WATCHFUL_EYE:
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
	return material_profile in [PlanetShapeProfileScript.MOON, PlanetShapeProfileScript.TUMBLING_BEAN, PlanetShapeProfileScript.WATCHFUL_EYE]


func _collider_height_for(direction: Vector3) -> float:
	return get_collider_surface_radius(direction) - _core_radius()


func _height_for(direction: Vector3) -> float:
	var local_direction := _eye_basis.inverse() * direction.normalized()
	return _core_radius() * (_height_generator.sample_factor(local_direction) - 1.0)


func _core_radius() -> float:
	return radius if core_radius <= 0.0 else core_radius


func _ocean_level_above_core() -> float:
	return sea_level() - _core_radius()
