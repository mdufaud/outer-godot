extends RefCounted

const SHADER_PATH := "res://shaders/planet_height.comp"
const SHADING_SHADER_PATH := "res://shaders/planet_shading.comp"
const PERTURB_SHADER_PATH := "res://shaders/planet_perturb.comp"
const PERTURB_SCALE := 50.0
const WORKGROUP_SIZE := 256

static var _shared_pipelines: Dictionary = {}
static var _shared_refcount := 0
const EARTH := 0
const MOON := 1
const ALIEN := 2
const SHATTERED := 3
const MOAT := 4
const ASTEROID := 5
const GLACIER := 6

var _body_kind := EARTH
var _profile := "earth"
var _seed := 0
var _settings: Array[Vector4] = []
var _craters: Array[Dictionary] = []
var _crater_cells: Dictionary = {}
var _crater_cell_size := 0.0
var _settings_bytes := PackedByteArray()
var _crater_bytes := PackedByteArray()
var _shading_settings: Array[Vector4] = []
var _moon_points: Array[Vector4] = []
var _ejecta_craters: Array[Vector4] = []
var _shading_settings_bytes := PackedByteArray()
var _moon_points_bytes := PackedByteArray()
var _ejecta_craters_bytes := PackedByteArray()
var _state := {"initialized": false, "busy": false, "error": "", "result": PackedFloat32Array(), "shading_result": PackedFloat32Array(), "perturb_result": PackedVector3Array()}
var _pending_positions := PackedByteArray()
var _pending_count := 0
var _pending_shading_positions := PackedByteArray()
var _pending_shading_count := 0
var _pending_perturb_positions := PackedByteArray()
var _pending_perturb_count := 0
var _pending_perturb_strength := 0.0

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _settings_buffer := RID()
var _crater_buffer := RID()
var _positions_buffer := RID()
var _heights_buffer := RID()
var _uniform_set := RID()
var _perturb_shader := RID()
var _perturb_pipeline := RID()
var _perturb_in_buffer := RID()
var _perturb_out_buffer := RID()
var _perturb_uniform_set := RID()
var _shading_shader := RID()
var _shading_pipeline := RID()
var _shading_settings_buffer := RID()
var _moon_points_buffer := RID()
var _ejecta_craters_buffer := RID()
var _shading_positions_buffer := RID()
var _shading_data_buffer := RID()
var _shading_uniform_set := RID()


func _init(body_kind: String, seed: int) -> void:
	_profile = body_kind
	match body_kind:
		"moon", "tumbling_bean", "watchful_eye":
			_body_kind = MOON
		"alien", "cyclops", "mirage":
			_body_kind = ALIEN
		"shattered", "icey_twin":
			_body_kind = SHATTERED
		"moat", "fiery_twin":
			_body_kind = MOAT
		"asteroid":
			_body_kind = ASTEROID
		"glacier":
			_body_kind = GLACIER
		_:
			_body_kind = EARTH
	_seed = seed
	_build_settings()


func initialize() -> void:
	_shared_refcount += 1
	RenderingServer.call_on_render_thread(_initialize_render)


func shutdown() -> void:
	_shared_refcount -= 1
	RenderingServer.call_on_render_thread(_free_render)


func request(directions: PackedVector3Array) -> bool:
	if _state.busy:
		return false
	var positions := directions.to_byte_array()
	if not _state.initialized:
		_pending_positions = positions
		_pending_count = directions.size()
		return true
	_state.busy = true
	RenderingServer.call_on_render_thread(_generate_render.bind(positions, directions.size()))
	return true


func has_result() -> bool:
	return not _state.result.is_empty()


func take_result() -> PackedFloat32Array:
	var result: PackedFloat32Array = _state.result
	_state.result = PackedFloat32Array()
	return result


func request_shading(directions: PackedVector3Array) -> bool:
	if _state.busy:
		return false
	var positions := directions.to_byte_array()
	if not _state.initialized:
		_pending_shading_positions = positions
		_pending_shading_count = directions.size()
		return true
	_state.busy = true
	RenderingServer.call_on_render_thread(_generate_shading_render.bind(positions, directions.size()))
	return true


func request_perturb(points: PackedVector3Array, strength: float) -> bool:
	if _state.busy:
		return false
	var positions := points.to_byte_array()
	if not _state.initialized:
		_pending_perturb_positions = positions
		_pending_perturb_count = points.size()
		_pending_perturb_strength = strength
		return true
	_state.busy = true
	RenderingServer.call_on_render_thread(_generate_perturb_render.bind(positions, points.size(), strength))
	return true


func has_perturb_result() -> bool:
	return not _state.perturb_result.is_empty()


func take_perturb_result() -> PackedVector3Array:
	var result: PackedVector3Array = _state.perturb_result
	_state.perturb_result = PackedVector3Array()
	return result


func has_shading_result() -> bool:
	return not _state.shading_result.is_empty()


func take_shading_result() -> PackedFloat32Array:
	var result: PackedFloat32Array = _state.shading_result
	_state.shading_result = PackedFloat32Array()
	return result


func get_error() -> String:
	return _state.error


func sample_factor(direction: Vector3) -> float:
	match _body_kind:
		MOON:
			return _moon_factor(direction)
		ALIEN:
			return _alien_factor(direction)
		SHATTERED:
			return _shattered_factor(direction)
		MOAT:
			return _moat_factor(direction)
		ASTEROID:
			return _asteroid_factor(direction)
		GLACIER:
			return _glacier_factor(direction)
		_:
			return _earth_factor(direction)


func sample_shading_data(direction: Vector3) -> Vector4:
	if _body_kind == MOON:
		return _moon_shading_data(direction)
	return _earth_shading_data(direction)


func _initialize_render() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		_state.error = "Planet height generation requires Forward+ or Mobile rendering."
		return
	var height_pipeline := _shared_pipeline(SHADER_PATH)
	if height_pipeline.has("error"):
		_state.error = height_pipeline.error
		return
	_shader = height_pipeline.shader
	_pipeline = height_pipeline.pipeline
	_settings_buffer = _rd.storage_buffer_create(_settings_bytes.size(), _settings_bytes)
	var crater_data := _crater_bytes
	if crater_data.is_empty():
		crater_data.resize(32)
	_crater_buffer = _rd.storage_buffer_create(crater_data.size(), crater_data)
	var shading_pipeline := _shared_pipeline(SHADING_SHADER_PATH)
	if shading_pipeline.has("error"):
		_state.error = shading_pipeline.error
		return
	_shading_shader = shading_pipeline.shader
	_shading_pipeline = shading_pipeline.pipeline
	_shading_settings_buffer = _rd.storage_buffer_create(_shading_settings_bytes.size(), _shading_settings_bytes)
	var point_data := _moon_points_bytes
	if point_data.is_empty():
		point_data.resize(16)
	_moon_points_buffer = _rd.storage_buffer_create(point_data.size(), point_data)
	var ejecta_data := _ejecta_craters_bytes
	if ejecta_data.is_empty():
		ejecta_data.resize(16)
	_ejecta_craters_buffer = _rd.storage_buffer_create(ejecta_data.size(), ejecta_data)
	var perturb_pipeline := _shared_pipeline(PERTURB_SHADER_PATH)
	if perturb_pipeline.has("error"):
		_state.error = perturb_pipeline.error
		return
	_perturb_shader = perturb_pipeline.shader
	_perturb_pipeline = perturb_pipeline.pipeline
	_state.initialized = true
	if _pending_count > 0:
		var positions := _pending_positions
		var count := _pending_count
		_pending_positions = PackedByteArray()
		_pending_count = 0
		_state.busy = true
		_generate_render(positions, count)
	elif _pending_shading_count > 0:
		var shading_positions := _pending_shading_positions
		var shading_count := _pending_shading_count
		_pending_shading_positions = PackedByteArray()
		_pending_shading_count = 0
		_state.busy = true
		_generate_shading_render(shading_positions, shading_count)
	elif _pending_perturb_count > 0:
		var perturb_positions := _pending_perturb_positions
		var perturb_count := _pending_perturb_count
		var perturb_strength := _pending_perturb_strength
		_pending_perturb_positions = PackedByteArray()
		_pending_perturb_count = 0
		_pending_perturb_strength = 0.0
		_state.busy = true
		_generate_perturb_render(perturb_positions, perturb_count, perturb_strength)


func _shared_pipeline(path: String) -> Dictionary:
	if _shared_pipelines.has(path):
		return _shared_pipelines[path]
	var source := RDShaderSource.new()
	source.source_compute = FileAccess.get_file_as_string(path)
	var spirv := _rd.shader_compile_spirv_from_source(source, true)
	if not spirv.compile_error_compute.is_empty():
		return {"error": spirv.compile_error_compute}
	var shader := _rd.shader_create_from_spirv(spirv)
	var entry := {"shader": shader, "pipeline": _rd.compute_pipeline_create(shader)}
	_shared_pipelines[path] = entry
	return entry


func _generate_render(positions: PackedByteArray, count: int) -> void:
	_release_request_resources()
	_positions_buffer = _rd.storage_buffer_create(positions.size(), positions)
	_heights_buffer = _rd.storage_buffer_create(count * 4)
	_uniform_set = _rd.uniform_set_create([
		_buffer_uniform(_positions_buffer, 0),
		_buffer_uniform(_heights_buffer, 1),
		_buffer_uniform(_crater_buffer, 2),
		_buffer_uniform(_settings_buffer, 3),
	], _shader, 0)
	var constants := PackedInt32Array([count, _body_kind, _craters.size(), 0]).to_byte_array()
	var command_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(command_list, _pipeline)
	_rd.compute_list_bind_uniform_set(command_list, _uniform_set, 0)
	_rd.compute_list_set_push_constant(command_list, constants, constants.size())
	_rd.compute_list_dispatch(command_list, ceili(float(count) / float(WORKGROUP_SIZE)), 1, 1)
	_rd.compute_list_end()
	var result := _rd.buffer_get_data(_heights_buffer).to_float32_array()
	_release_request_resources()
	_state.busy = false
	_state.result = result


func _generate_perturb_render(positions: PackedByteArray, count: int, strength: float) -> void:
	_release_perturb_request_resources()
	_perturb_in_buffer = _rd.storage_buffer_create(positions.size(), positions)
	_perturb_out_buffer = _rd.storage_buffer_create(positions.size())
	_perturb_uniform_set = _rd.uniform_set_create([
		_buffer_uniform(_perturb_in_buffer, 0),
		_buffer_uniform(_perturb_out_buffer, 1),
	], _perturb_shader, 0)
	var constants := PackedInt32Array([count, 0, 0, 0]).to_byte_array()
	constants.append_array(PackedFloat32Array([strength, PERTURB_SCALE, float(_seed % 1024), 0.0]).to_byte_array())
	var command_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(command_list, _perturb_pipeline)
	_rd.compute_list_bind_uniform_set(command_list, _perturb_uniform_set, 0)
	_rd.compute_list_set_push_constant(command_list, constants, constants.size())
	_rd.compute_list_dispatch(command_list, ceili(float(count) / float(WORKGROUP_SIZE)), 1, 1)
	_rd.compute_list_end()
	var result := _rd.buffer_get_data(_perturb_out_buffer).to_float32_array()
	_release_perturb_request_resources()
	var points := PackedVector3Array()
	points.resize(count)
	for index in count:
		points[index] = Vector3(result[index * 3], result[index * 3 + 1], result[index * 3 + 2])
	_state.busy = false
	_state.perturb_result = points


func _generate_shading_render(positions: PackedByteArray, count: int) -> void:
	_release_shading_request_resources()
	_shading_positions_buffer = _rd.storage_buffer_create(positions.size(), positions)
	_shading_data_buffer = _rd.storage_buffer_create(count * 16)
	_shading_uniform_set = _rd.uniform_set_create([
		_buffer_uniform(_shading_positions_buffer, 0),
		_buffer_uniform(_shading_data_buffer, 1),
		_buffer_uniform(_shading_settings_buffer, 2),
		_buffer_uniform(_moon_points_buffer, 3),
		_buffer_uniform(_ejecta_craters_buffer, 4),
	], _shading_shader, 0)
	var shading_kind := MOON if _body_kind == MOON else EARTH
	var constants := PackedInt32Array([count, shading_kind, _moon_points.size(), _ejecta_craters.size()]).to_byte_array()
	var command_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(command_list, _shading_pipeline)
	_rd.compute_list_bind_uniform_set(command_list, _shading_uniform_set, 0)
	_rd.compute_list_set_push_constant(command_list, constants, constants.size())
	_rd.compute_list_dispatch(command_list, ceili(float(count) / float(WORKGROUP_SIZE)), 1, 1)
	_rd.compute_list_end()
	var result := _rd.buffer_get_data(_shading_data_buffer).to_float32_array()
	_release_shading_request_resources()
	_state.busy = false
	_state.shading_result = result


func _free_render() -> void:
	if _rd == null:
		return
	_release_request_resources()
	_release_shading_request_resources()
	_release_perturb_request_resources()
	for resource in [_ejecta_craters_buffer, _moon_points_buffer, _shading_settings_buffer, _crater_buffer, _settings_buffer]:
		if resource.is_valid():
			_rd.free_rid(resource)
	_ejecta_craters_buffer = RID()
	_moon_points_buffer = RID()
	_shading_settings_buffer = RID()
	_shading_pipeline = RID()
	_shading_shader = RID()
	_crater_buffer = RID()
	_settings_buffer = RID()
	_perturb_pipeline = RID()
	_perturb_shader = RID()
	_pipeline = RID()
	_shader = RID()
	_state.initialized = false
	if _shared_refcount <= 0:
		for entry in _shared_pipelines.values():
			for resource in [entry.pipeline, entry.shader]:
				if resource.is_valid():
					_rd.free_rid(resource)
		_shared_pipelines.clear()


func _release_request_resources() -> void:
	if _rd == null:
		return
	if _uniform_set.is_valid() and _rd.uniform_set_is_valid(_uniform_set):
		_rd.free_rid(_uniform_set)
	for resource in [_heights_buffer, _positions_buffer]:
		if resource.is_valid():
			_rd.free_rid(resource)
	_uniform_set = RID()
	_heights_buffer = RID()
	_positions_buffer = RID()


func _release_perturb_request_resources() -> void:
	if _rd == null:
		return
	if _perturb_uniform_set.is_valid() and _rd.uniform_set_is_valid(_perturb_uniform_set):
		_rd.free_rid(_perturb_uniform_set)
	for resource in [_perturb_out_buffer, _perturb_in_buffer]:
		if resource.is_valid():
			_rd.free_rid(resource)
	_perturb_uniform_set = RID()
	_perturb_out_buffer = RID()
	_perturb_in_buffer = RID()


func _release_shading_request_resources() -> void:
	if _rd == null:
		return
	if _shading_uniform_set.is_valid() and _rd.uniform_set_is_valid(_shading_uniform_set):
		_rd.free_rid(_shading_uniform_set)
	for resource in [_shading_data_buffer, _shading_positions_buffer]:
		if resource.is_valid():
			_rd.free_rid(resource)
	_shading_uniform_set = RID()
	_shading_data_buffer = RID()
	_shading_positions_buffer = RID()


func _buffer_uniform(resource: RID, binding: int) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(resource)
	return uniform


func _build_settings() -> void:
	_settings.resize(20)
	for index in _settings.size():
		_settings[index] = Vector4.ZERO
	var random := DotNetRandom.new(_seed)
	match _body_kind:
		EARTH:
			_set_simple_noise(0, random, 6, 0.5, 2.0, 1.0, 2.64, 0.0)
			_set_simple_noise(3, random, 3, 0.55, 1.66, 1.09, 1.0, 0.02)
			_set_ridge_noise(6, random, 5, 0.5, 4.0, 1.5, 8.7, 2.18, 0.8, 0.09, 1.0)
			_settings[9] = Vector4(5.0, 1.36, 0.5, 1.0)
		MOON:
			_build_moon_settings(random)
		ALIEN:
			_set_simple_noise(0, random, 4, 0.6, 2.0, 1.0, 1.0, 0.0)
			_set_ridge_noise(6, random, 5, 0.5, 2.0, 1.38, 10.0, 2.0, -1.64, 0.0, 2.0)
			_set_simple_noise(3, random, 4, 0.5, 2.0, 1.0, 1.0, 0.0)
			_set_simple_noise(9, random, 4, 0.5, 0.2, 0.6, 1.0, 0.0)
			_settings[17] = Vector4(103.03, 0.0, 210.9, 0.0)
			_settings[18] = Vector4(5.0, 1.5, 0.3, 3.19)
			_build_craters(30, Vector2(0.04, 0.41), 0.13, 1.6, Vector2(0.4, 1.5), 0.6, 0)
		SHATTERED:
			_set_simple_noise(0, random, 3, 0.5, 2.0, 0.62, 8.64, 0.0)
			_set_ridge_noise(3, random, 3, 1.0, 2.0, 3.33, -1.6, 12.0, 4.1, 0.0, 1.0)
			_set_ridge_noise(6, random, 5, 0.57, 2.0, 1.0, 1.86, 2.03, 1.37, -1.33, 1.0)
			_set_simple_noise(9, random, 4, 0.5, 2.0, 1.0, 40.88, 0.0)
			_settings[18] = Vector4(0.27, 0.0, 0.0, 0.0)
			_build_craters(200, Vector2(0.015, 0.1), 0.14, 1.09, Vector2(0.4, 1.0), 0.769, 0)
		MOAT:
			_set_simple_noise(0, random, 8, 0.5, 2.0, 1.0, 2.5, 0.0)
			_settings[18] = Vector4(4.35, 2.26, 0.8, 217.66)
			_build_craters(400, Vector2(0.01, 0.1), 0.13, 1.6, Vector2(0.4, 1.5), 0.6, 0)
		ASTEROID:
			_settings[0] = Vector4(8.0, 1.35, 0.78, 4.5)
			_settings[1] = Vector4(3.4, -0.35, 0.0, 0.0)
		GLACIER:
			_settings[0] = Vector4(8.0, 2.1, 0.55, 3.6)
			_settings[1] = Vector4(1.8, 0.0, 0.0, 0.0)
	var values := PackedFloat32Array()
	values.resize(_settings.size() * 4)
	for index in _settings.size():
		var offset := index * 4
		var setting := _settings[index]
		values[offset] = setting.x
		values[offset + 1] = setting.y
		values[offset + 2] = setting.z
		values[offset + 3] = setting.w
	_settings_bytes = values.to_byte_array()
	_build_shading_settings()


func _build_shading_settings() -> void:
	_shading_settings.resize(12)
	for index in _shading_settings.size():
		_shading_settings[index] = Vector4.ZERO
	var shading_seed := _seed
	match _profile:
		"fiery_twin", "cyclops":
			shading_seed = 10
		"icey_twin":
			shading_seed = -1587
		"tumbling_bean", "watchful_eye":
			shading_seed = 0
	var random := DotNetRandom.new(shading_seed)
	if _body_kind != MOON:
		var detail_warp_elevation := 5.0
		var detail_elevation := 1.0
		var large_elevation := 1.0
		var small_scale := 4.44
		var small_elevation := 0.52
		match _profile:
			"fiery_twin":
				detail_warp_elevation = 33.6
				detail_elevation = -1.25
				large_elevation = 1.0
				small_scale = 5.0
				small_elevation = 1.0
			"icey_twin":
				detail_warp_elevation = 17.1
				detail_elevation = 9.32
				large_elevation = -2.08
				small_scale = 6.34
				small_elevation = 1.0
			"cyclops":
				detail_warp_elevation = 18.72
				detail_elevation = -1.25
				large_elevation = 1.0
				small_scale = 5.0
				small_elevation = 1.0
		var detail_scale := 1.5 if _profile == "earth" else 0.89
		var detail_offset := Vector3.ZERO if _profile == "earth" else Vector3(1.35, 0.0, 0.0)
		_set_shading_simple_noise(3, random, 4, 0.5, 2.0, detail_scale, detail_elevation, 0.0, detail_offset)
		_set_shading_simple_noise(0, random, 4, 0.5, 2.0, 1.0 if _profile != "earth" else 2.96, detail_warp_elevation, 0.0)
		_set_shading_simple_noise(6, random, 4, 0.26 if _profile != "earth" else 0.5, 2.0, 0.425 if _profile != "earth" else 1.52, large_elevation, 0.0)
		_set_shading_simple_noise(9, random, 4 if _profile != "earth" else 5, 0.5 if _profile != "earth" else 0.65, 2.0 if _profile != "earth" else 4.13, small_scale, small_elevation, 0.0)
	else:
		_set_shading_simple_noise(0, random, 4, 0.5, 2.0, 1.875925, 1.1754117, 0.0)
		var detail_warp_elevation := 2.2643394
		if _profile == "watchful_eye":
			detail_warp_elevation = 6.4
		_set_shading_simple_noise(3, random, 4, 0.5, 2.0, 2.4969678, detail_warp_elevation, 0.0)
		if _profile == "watchful_eye":
			_set_shading_simple_noise(6, random, 5, 0.58, 2.7, 1.5, 1.4, 0.0)
		else:
			_set_shading_simple_noise(6, random, 4, 0.5, 2.34, 1.35, 1.43, 0.0)
		_build_moon_points(18 if _profile == "watchful_eye" else 32, shading_seed)
		_build_ejecta_craters(3 if _profile == "watchful_eye" else 2, 102 if _profile == "watchful_eye" else 0, 9.0 if _profile == "watchful_eye" else 11.0)
	_shading_settings_bytes = _pack_vector4_array(_shading_settings)
	_moon_points_bytes = _pack_vector4_array(_moon_points)
	_ejecta_craters_bytes = _pack_vector4_array(_ejecta_craters)


func _set_shading_simple_noise(index: int, random: DotNetRandom, layers: int, persistence: float, lacunarity: float, scale: float, elevation: float, vertical_shift: float, configured_offset := Vector3.ZERO) -> void:
	var offset := Vector3(random.value(), random.value(), random.value()) * random.value() * 10000.0 + configured_offset
	_shading_settings[index] = Vector4(offset.x, offset.y, offset.z, layers)
	_shading_settings[index + 1] = Vector4(persistence, lacunarity, scale, elevation)
	_shading_settings[index + 2] = Vector4(vertical_shift, 0.0, 0.0, 0.0)


func _build_moon_points(count: int, seed: int) -> void:
	var random := DotNetRandom.new(seed)
	for _index in count:
		var direction := _random_unit_direction(random)
		_moon_points.append(Vector4(direction.x, direction.y, direction.z, lerpf(0.001, 0.03, random.value())))


func _build_ejecta_craters(desired_count: int, seed: int, scale: float) -> void:
	var sorted_craters: Array[Dictionary] = []
	for crater in _craters:
		# Hand placed craters are far larger than the field ones, so their ejecta
		# rays would cover the whole body.
		if bool(crater.get("forced", false)):
			continue
		sorted_craters.append(crater)
	sorted_craters.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return float(first.radius) > float(second.radius))
	var pool_size := clampi(int(float(sorted_craters.size() - 1) * 0.2), 1, sorted_craters.size())
	sorted_craters.resize(pool_size)
	var random := DotNetRandom.new(seed)
	for index in range(sorted_craters.size() - 1):
		var swap_index := random.range_int(index, sorted_craters.size())
		var swap := sorted_craters[index]
		sorted_craters[index] = sorted_craters[swap_index]
		sorted_craters[swap_index] = swap
	for crater in sorted_craters:
		var centre: Vector3 = crater.centre
		var radius: float = crater.radius
		var overlaps := false
		for chosen in _ejecta_craters:
			if centre.distance_to(Vector3(chosen.x, chosen.y, chosen.z)) < (radius + chosen.w / scale) * scale * 0.5:
				overlaps = true
				break
		if not overlaps:
			_ejecta_craters.append(Vector4(centre.x, centre.y, centre.z, radius * scale))
		if _ejecta_craters.size() >= desired_count:
			break


func _pack_vector4_array(values: Array[Vector4]) -> PackedByteArray:
	var packed := PackedFloat32Array()
	packed.resize(values.size() * 4)
	for index in values.size():
		var offset := index * 4
		var value := values[index]
		packed[offset] = value.x
		packed[offset + 1] = value.y
		packed[offset + 2] = value.z
		packed[offset + 3] = value.w
	return packed.to_byte_array()


func _set_simple_noise(index: int, random: DotNetRandom, layers: int, persistence: float, lacunarity: float, scale: float, elevation: float, vertical_shift: float, configured_offset := Vector3.ZERO) -> void:
	var offset := Vector3(random.value(), random.value(), random.value()) * random.value() * 10000.0 + configured_offset
	_settings[index] = Vector4(offset.x, offset.y, offset.z, layers)
	_settings[index + 1] = Vector4(persistence, lacunarity, scale, elevation)
	_settings[index + 2] = Vector4(vertical_shift, 0.0, 0.0, 0.0)


func _set_ridge_noise(index: int, random: DotNetRandom, layers: int, persistence: float, lacunarity: float, scale: float, elevation: float, power: float, gain: float, vertical_shift: float, smoothing: float, configured_offset := Vector3.ZERO) -> void:
	var offset := Vector3(random.value(), random.value(), random.value()) * random.value() * 10000.0 + configured_offset
	_settings[index] = Vector4(offset.x, offset.y, offset.z, layers)
	_settings[index + 1] = Vector4(persistence, lacunarity, scale, elevation)
	_settings[index + 2] = Vector4(power, gain, vertical_shift, smoothing)


func _build_moon_settings(random: DotNetRandom) -> void:
	match _profile:
		"tumbling_bean":
			_set_simple_noise(10, random, 4, 0.5, 2.0, 0.36, 25.0, 0.0, Vector3(3.0, 14.7, 0.0))
			_set_ridge_noise(13, random, 4, 0.42, 5.0, 1.0, -5.72, 2.0, 1.0, 0.0, 2.0)
			_set_ridge_noise(16, random, 4, 0.5, 2.0, 15.0, 0.0, 2.0, 1.0, 0.0, 0.0)
			_build_craters(3000, Vector2(0.012, 0.12), -0.16, 1.22, Vector2(0.4, 1.5), 0.742, 17801)
		"watchful_eye":
			# Kept smooth on purpose: high frequency relief buries the eye.
			_set_simple_noise(10, random, 4, 0.54, 2.0, 0.58, 3.4, 0.0, Vector3(3.0, 14.7, 0.0))
			_set_ridge_noise(13, random, 4, 0.48, 2.8, 2.4, 1.2, 2.4, 1.0, -0.8, 1.2)
			_set_ridge_noise(16, random, 5, 0.46, 2.2, 8.5, 0.35, 2.8, 1.0, -0.25, 0.45)
			_build_craters(40, Vector2(0.012, 0.1), 0.12, 0.72, Vector2(0.18, 0.75), 0.68, 17809, _eye_craters())
		_:
			_set_simple_noise(10, random, 4, 0.5, 2.0, 0.97, 0.0, 0.0)
			_set_ridge_noise(13, random, 4, 0.5, 5.0, 1.82, -2.84, 2.0, 0.5, 0.0, 3.0)
			_set_ridge_noise(16, random, 5, 0.5, 2.0, 2.0, 3.0, 0.5, 1.0, 0.0, 0.0)
			_build_craters(500, Vector2(0.01, 0.15), 0.42, 1.23, Vector2(0.4, 1.5), 0.675, 17801)


# The eye is the whole point of this body, so it is placed by hand instead of
# hoping the random crater field produces one: a wide smooth socket with a
# raised dome in the middle. A positive floor makes the crater formula bulge
# instead of dig, which is what gives the pupil.
const EYE_DIRECTION := Vector3(0.0, 0.18, 1.0)


func _eye_craters() -> Array[Dictionary]:
	var centre := EYE_DIRECTION.normalized()
	return [
		{"centre": centre, "radius": 0.75, "floor": -0.3, "smoothness": 0.55, "forced": true},
		{"centre": centre, "radius": 0.42, "floor": -0.22, "smoothness": 0.3, "forced": true},
		{"centre": centre, "radius": 0.22, "floor": 0.9, "smoothness": 0.18, "forced": true},
	]


func _build_craters(count: int, size_range: Vector2, rim_steepness: float, rim_width: float, smooth_range: Vector2, distribution: float, crater_seed: int, forced: Array[Dictionary] = []) -> void:
	var property_random := DotNetRandom.new(_seed)
	var direction_random := DotNetRandom.new(_seed + crater_seed)
	var values := PackedFloat32Array()
	values.resize((count + forced.size()) * 8)
	for index in forced.size():
		var crater: Dictionary = forced[index]
		_craters.append(crater.duplicate())
		var forced_offset := index * 8
		var centre_value: Vector3 = crater.centre
		values[forced_offset] = centre_value.x
		values[forced_offset + 1] = centre_value.y
		values[forced_offset + 2] = centre_value.z
		values[forced_offset + 3] = float(crater.radius)
		values[forced_offset + 4] = float(crater.floor)
		values[forced_offset + 5] = float(crater.smoothness)
	for index in count:
		var t := property_random.value_bias_lower(distribution)
		var size := lerpf(size_range.x, size_range.y, t)
		var floor_height := lerpf(-1.2, -0.2, clampf(t + property_random.value_bias_lower(0.3), 0.0, 1.0))
		var smoothness := lerpf(smooth_range.x, smooth_range.y, 1.0 - t)
		var centre := _random_unit_direction(direction_random)
		_craters.append({
			"centre": centre,
			"radius": size,
			"floor": floor_height,
			"smoothness": smoothness,
		})
		var offset := (forced.size() + index) * 8
		values[offset] = centre.x
		values[offset + 1] = centre.y
		values[offset + 2] = centre.z
		values[offset + 3] = size
		values[offset + 4] = floor_height
		values[offset + 5] = smoothness
	_settings[19] = Vector4(rim_steepness, rim_width, smooth_range.x, smooth_range.y)
	_crater_bytes = values.to_byte_array()
	_index_craters(rim_width)


func _index_craters(rim_width: float) -> void:
	if _craters.is_empty():
		return
	for crater in _craters:
		var influence := float(crater.radius) * maxf(1.0 + rim_width, sqrt(1.0 + float(crater.smoothness)))
		crater.influence = influence
		_crater_cell_size = maxf(_crater_cell_size, influence)
	if _craters.size() < 1000 and _crater_cell_size >= 0.75:
		_crater_cell_size = 0.0
		return
	for index in _craters.size():
		var cell := _crater_cell(_craters[index].centre)
		if not _crater_cells.has(cell):
			_crater_cells[cell] = []
		_crater_cells[cell].append(index)


func _crater_cell(position: Vector3) -> Vector3i:
	return Vector3i(
		floori((position.x + 1.0) / _crater_cell_size),
		floori((position.y + 1.0) / _crater_cell_size),
		floori((position.z + 1.0) / _crater_cell_size)
	)


func _random_unit_direction(random: DotNetRandom) -> Vector3:
	var y := random.value() * 2.0 - 1.0
	var angle := random.value() * TAU
	var radial := sqrt(maxf(0.0, 1.0 - y * y))
	return Vector3(cos(angle) * radial, y, sin(angle) * radial)


func _earth_factor(position: Vector3) -> float:
	var continent := _simple_noise(position, 0)
	var earth := _settings[9]
	continent = _smooth_max(continent, -earth.y, earth.z)
	if continent < 0.0:
		continent *= 1.0 + earth.x
	var ridge := _smoothed_ridge_noise(position, 6)
	var mask := _blend(0.0, earth.w, _simple_noise(position, 3))
	return 1.0 + continent * 0.01 + ridge * 0.01 * mask


func _moon_factor(position: Vector3) -> float:
	var shape := _simple_noise(position, 10)
	var ridge := _smoothed_ridge_noise(position, 13)
	var ridge2 := _smoothed_ridge_noise(position, 16)
	return 1.0 + _crater_depth(position) + (shape + ridge + ridge2) * 0.01


func _alien_factor(position: Vector3) -> float:
	var warp := Vector3(
		_simple_noise(position, 9),
		_simple_noise(position - Vector3.ONE * 100.0, 9),
		_simple_noise(position + Vector3.ONE * 100.0, 9)
	) * 0.01
	var config := _settings[18]
	var parameters := _settings[17]
	var continent := _simple_noise(position + warp * parameters.x, 0)
	continent = _smooth_max(continent, -config.y, config.z)
	if continent < 0.0:
		continent *= 1.0 + config.x
	var ridge := _smoothed_ridge_noise(position + warp * parameters.y, 6)
	var mask := _blend(0.0, config.w, _simple_noise(position + warp * parameters.z, 3))
	return 1.0 + continent * 0.01 + ridge * 0.01 * mask + _crater_depth(position)


func _shattered_factor(position: Vector3) -> float:
	var warp := Vector3(
		_simple_noise(position, 9),
		_simple_noise(position - Vector3.ONE * 100.0, 9),
		_simple_noise(position + Vector3.ONE * 100.0, 9)
	) * 0.01
	var continent := _simple_noise(position + warp, 0)
	continent = _smooth_min(continent, _settings[18].x, _settings[18].y)
	return 1.0 + (continent + _smoothed_ridge_noise(position, 3) + _smoothed_ridge_noise(position, 6)) * 0.01 + _crater_depth(position)


func _moat_factor(position: Vector3) -> float:
	var config := _settings[18]
	var continent := _simple_noise(position, 0)
	continent *= 1.0 + continent / config.y * config.x
	if continent < 0.0:
		continent *= 1.0 + config.w * absf(continent)
	return 1.0 + continent * 0.01 + _crater_depth(position)


func _asteroid_factor(position: Vector3) -> float:
	var shape := _settings[0]
	var terrain := _settings[1]
	var surface_radius := 18.0
	for _iteration in 4:
		var noise := _ridged_fbm(position * surface_radius, int(shape.x), shape.y, shape.z, shape.w)
		surface_radius = 18.0 - (noise - terrain.y) * terrain.x
	return surface_radius / 18.0


func _glacier_factor(position: Vector3) -> float:
	var shape := _settings[0]
	var terrain := _settings[1]
	var surface_radius := 24.0
	for _iteration in 4:
		var noise := _ridged_fbm(position * surface_radius, int(shape.x), shape.y, shape.z, shape.w)
		surface_radius = 24.0 - (noise - terrain.y) * terrain.x
	return surface_radius / 24.0


func _ridged_fbm(position: Vector3, layers: int, lacunarity: float, persistence: float, scale: float) -> float:
	var noise := 0.0
	var frequency := scale / 100.0
	var amplitude := 1.0
	for _layer in layers:
		var value := 1.0 - absf(_simplex_noise(position * frequency) * 2.0 - 1.0)
		noise += value * amplitude
		amplitude *= persistence
		frequency *= lacunarity
	return noise


func _earth_shading_data(position: Vector3) -> Vector4:
	var large_noise := _shading_simple_noise(position, 6)
	var small_noise := _shading_simple_noise(position, 9)
	var detail_warp := _shading_simple_noise(position, 0)
	var detail_noise := _shading_simple_noise(position + Vector3.ONE * detail_warp * 0.1, 3)
	return Vector4(large_noise, detail_noise, small_noise, 0.0)


func _moon_shading_data(position: Vector3) -> Vector4:
	var domain_warp := Vector3(
		_shading_simple_noise(position, 0),
		_shading_simple_noise(position + Vector3.ONE * 100.0, 0),
		_shading_simple_noise(position - Vector3.ONE * 100.0, 0)
	)
	var detail_warp := _shading_simple_noise(position, 3)
	var detail_noise := _shading_simple_noise(position + Vector3.ONE * detail_warp * 0.1, 6)
	var sphere_noise := INF
	for point in _moon_points:
		sphere_noise = minf(sphere_noise, (position + domain_warp * 0.1).distance_to(Vector3(point.x, point.y, point.z)) / point.w)
	var ejecta_uv := Vector2.ONE
	var closest := 999.0
	for crater in _ejecta_craters:
		var centre := Vector3(crater.x, crater.y, crater.z)
		var scaled_distance := position.distance_to(centre) / crater.w
		if scaled_distance < closest:
			closest = scaled_distance
			var crater_forward := centre.cross(Vector3.UP).normalized()
			var forward := position.cross(centre).normalized()
			var angle_sign := signf(centre.dot(forward.cross(crater_forward)))
			ejecta_uv = Vector2(acos(clampf(crater_forward.dot(forward), -1.0, 1.0)) * angle_sign, scaled_distance)
	return Vector4(ejecta_uv.x, ejecta_uv.y, detail_noise, sphere_noise)


func _simple_noise(position: Vector3, index: int) -> float:
	var first := _settings[index]
	var second := _settings[index + 1]
	var third := _settings[index + 2]
	var sum := 0.0
	var amplitude := 1.0
	var frequency := second.z
	var offset := Vector3(first.x, first.y, first.z)
	for _layer in int(first.w):
		sum += _simplex_noise(position * frequency + offset) * amplitude
		amplitude *= second.x
		frequency *= second.y
	return sum * second.w + third.x


func _shading_simple_noise(position: Vector3, index: int) -> float:
	var first := _shading_settings[index]
	var second := _shading_settings[index + 1]
	var third := _shading_settings[index + 2]
	var sum := 0.0
	var amplitude := 1.0
	var frequency := second.z
	var offset := Vector3(first.x, first.y, first.z)
	for _layer in int(first.w):
		sum += _simplex_noise(position * frequency + offset) * amplitude
		amplitude *= second.x
		frequency *= second.y
	return sum * second.w + third.x


func _smoothed_ridge_noise(position: Vector3, index: int) -> float:
	var settings := _settings[index + 2]
	var normal := position.normalized()
	var axis_a := normal.cross(Vector3.UP)
	var axis_b := normal.cross(axis_a)
	var offset := settings.w * 0.01
	return (
		_ridge_noise(position, index)
		+ _ridge_noise(position - axis_a * offset, index)
		+ _ridge_noise(position + axis_a * offset, index)
		+ _ridge_noise(position - axis_b * offset, index)
		+ _ridge_noise(position + axis_b * offset, index)
	) * 0.2


func _ridge_noise(position: Vector3, index: int) -> float:
	var first := _settings[index]
	var second := _settings[index + 1]
	var third := _settings[index + 2]
	var sum := 0.0
	var amplitude := 1.0
	var frequency := second.z
	var weight := 1.0
	var offset := Vector3(first.x, first.y, first.z)
	for _layer in int(first.w):
		var value := 1.0 - absf(_simplex_noise(position * frequency + offset))
		value = pow(absf(value), third.x)
		value *= weight
		weight = clampf(value * third.y, 0.0, 1.0)
		sum += value * amplitude
		amplitude *= second.x
		frequency *= second.y
	return sum * second.w + third.z


func _crater_depth(position: Vector3) -> float:
	var settings := _settings[19]
	var height := 0.0
	if _crater_cells.is_empty():
		for crater in _craters:
			height += _crater_contribution(position, crater, settings)
		return height
	var centre_cell := _crater_cell(position)
	var candidate_indices: Array[int] = []
	for x in range(centre_cell.x - 1, centre_cell.x + 2):
		for y in range(centre_cell.y - 1, centre_cell.y + 2):
			for z in range(centre_cell.z - 1, centre_cell.z + 2):
				candidate_indices.append_array(_crater_cells.get(Vector3i(x, y, z), []))
	candidate_indices.sort()
	for index in candidate_indices:
		var crater := _craters[index]
		if position.distance_to(crater.centre) <= float(crater.influence):
			height += _crater_contribution(position, crater, settings)
	return height


func _crater_contribution(position: Vector3, crater: Dictionary, settings: Vector4) -> float:
	var centre: Vector3 = crater.centre
	var radius: float = crater.radius
	var distance := position.distance_to(centre) / maxf(radius, 0.0001)
	var cavity := distance * distance - 1.0
	var rim_x := minf(distance - 1.0 - settings.y, 0.0)
	var rim := settings.x * rim_x * rim_x
	var crater_shape := _smooth_max(cavity, float(crater.floor), float(crater.smoothness))
	crater_shape = _smooth_min(crater_shape, rim, float(crater.smoothness))
	return crater_shape * radius


func _smooth_min(a: float, b: float, smoothing: float) -> float:
	var k := maxf(0.0001, smoothing)
	var h := clampf((b - a + k) / (2.0 * k), 0.0, 1.0)
	return a * h + b * (1.0 - h) - k * h * (1.0 - h)


func _smooth_max(a: float, b: float, smoothing: float) -> float:
	var k := minf(-0.0001, -smoothing)
	var h := clampf((b - a + k) / (2.0 * k), 0.0, 1.0)
	return a * h + b * (1.0 - h) - k * h * (1.0 - h)


func _blend(start_height: float, blend_distance: float, height: float) -> float:
	return smoothstep(start_height - blend_distance * 0.5, start_height + blend_distance * 0.5, height)


func _simplex_noise(position: Vector3) -> float:
	var lattice := _floor_vector3(position + Vector3.ONE * (position.x + position.y + position.z) / 3.0)
	var corner0 := position - lattice + Vector3.ONE * (lattice.x + lattice.y + lattice.z) / 6.0
	var greater := Vector3(
		_step(corner0.y, corner0.x),
		_step(corner0.z, corner0.y),
		_step(corner0.x, corner0.z)
	)
	var lower := Vector3.ONE - greater
	var corner1 := _minimum_vector3(greater, Vector3(lower.z, lower.x, lower.y))
	var corner2 := _maximum_vector3(greater, Vector3(lower.z, lower.x, lower.y))
	var position1 := corner0 - corner1 + Vector3.ONE / 6.0
	var position2 := corner0 - corner2 + Vector3.ONE / 3.0
	var position3 := corner0 - Vector3.ONE * 0.5
	lattice = _mod289_vector3(lattice)
	var permutations := _permute_vector4(_permute_vector4(_permute_vector4(
		Vector4(lattice.z, lattice.z + corner1.z, lattice.z + corner2.z, lattice.z + 1.0)
	) + Vector4(lattice.y, lattice.y + corner1.y, lattice.y + corner2.y, lattice.y + 1.0)
	) + Vector4(lattice.x, lattice.x + corner1.x, lattice.x + corner2.x, lattice.x + 1.0))
	var hashes := permutations - _floor_vector4(permutations / 49.0) * 49.0
	var x_index := _floor_vector4(hashes / 7.0)
	var y_index := _floor_vector4(hashes - x_index * 7.0)
	var x := (x_index * 2.0 + Vector4(0.5, 0.5, 0.5, 0.5)) / 7.0 - Vector4.ONE
	var y := (y_index * 2.0 + Vector4(0.5, 0.5, 0.5, 0.5)) / 7.0 - Vector4.ONE
	var h := Vector4.ONE - _abs_vector4(x) - _abs_vector4(y)
	var base0 := Vector4(x.x, x.y, y.x, y.y)
	var base1 := Vector4(x.z, x.w, y.z, y.w)
	var sign0 := _floor_vector4(base0) * 2.0 + Vector4.ONE
	var sign1 := _floor_vector4(base1) * 2.0 + Vector4.ONE
	var selector := -_step_vector4(h, Vector4.ZERO)
	var adjusted0 := Vector4(base0.x, base0.z, base0.y, base0.w) + Vector4(sign0.x, sign0.z, sign0.y, sign0.w) * Vector4(selector.x, selector.x, selector.y, selector.y)
	var adjusted1 := Vector4(base1.x, base1.z, base1.y, base1.w) + Vector4(sign1.x, sign1.z, sign1.y, sign1.w) * Vector4(selector.z, selector.z, selector.w, selector.w)
	var gradient0 := Vector3(adjusted0.x, adjusted0.y, h.x)
	var gradient1 := Vector3(adjusted0.z, adjusted0.w, h.y)
	var gradient2 := Vector3(adjusted1.x, adjusted1.y, h.z)
	var gradient3 := Vector3(adjusted1.z, adjusted1.w, h.w)
	var normalization := Vector4(
		1.79284291400159 - gradient0.length_squared() * 0.85373472095314,
		1.79284291400159 - gradient1.length_squared() * 0.85373472095314,
		1.79284291400159 - gradient2.length_squared() * 0.85373472095314,
		1.79284291400159 - gradient3.length_squared() * 0.85373472095314
	)
	gradient0 *= normalization.x
	gradient1 *= normalization.y
	gradient2 *= normalization.z
	gradient3 *= normalization.w
	var attenuation := _maximum_vector4(Vector4(
		0.6 - corner0.length_squared(),
		0.6 - position1.length_squared(),
		0.6 - position2.length_squared(),
		0.6 - position3.length_squared()
	), Vector4.ZERO)
	attenuation *= attenuation
	attenuation *= attenuation
	return 42.0 * _dot_vector4(attenuation, Vector4(
		corner0.dot(gradient0),
		position1.dot(gradient1),
		position2.dot(gradient2),
		position3.dot(gradient3)
	))


func _floor_vector3(value: Vector3) -> Vector3:
	return Vector3(floor(value.x), floor(value.y), floor(value.z))


func _minimum_vector3(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))


func _maximum_vector3(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))


func _mod289_vector3(value: Vector3) -> Vector3:
	return value - _floor_vector3(value / 289.0) * 289.0


func _floor_vector4(value: Vector4) -> Vector4:
	return Vector4(floor(value.x), floor(value.y), floor(value.z), floor(value.w))


func _abs_vector4(value: Vector4) -> Vector4:
	return Vector4(absf(value.x), absf(value.y), absf(value.z), absf(value.w))


func _maximum_vector4(a: Vector4, b: Vector4) -> Vector4:
	return Vector4(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z), maxf(a.w, b.w))


func _permute_vector4(value: Vector4) -> Vector4:
	var transformed := Vector4(
		(value.x * 34.0 + 1.0) * value.x,
		(value.y * 34.0 + 1.0) * value.y,
		(value.z * 34.0 + 1.0) * value.z,
		(value.w * 34.0 + 1.0) * value.w
	)
	return transformed - _floor_vector4(transformed / 289.0) * 289.0


func _step(edge: float, value: float) -> float:
	return 0.0 if value < edge else 1.0


func _step_vector4(edge: Vector4, value: Vector4) -> Vector4:
	return Vector4(
		_step(edge.x, value.x),
		_step(edge.y, value.y),
		_step(edge.z, value.z),
		_step(edge.w, value.w)
	)


func _dot_vector4(a: Vector4, b: Vector4) -> float:
	return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w


class DotNetRandom:
	const MBIG := 2147483647
	const MSEED := 161803398
	var _seed_array := PackedInt64Array()
	var _inext := 0
	var _inextp := 21

	func _init(seed: int) -> void:
		_seed_array.resize(56)
		var subtraction: int = abs(seed)
		if seed == -2147483648:
			subtraction = MBIG
		var mj: int = MSEED - subtraction
		_seed_array[55] = mj
		var mk: int = 1
		for index in range(1, 55):
			var target := (21 * index) % 55
			_seed_array[target] = mk
			mk = mj - mk
			if mk < 0:
				mk += MBIG
			mj = int(_seed_array[target])
		for _iteration in 4:
			for index in range(1, 56):
				var target := 1 + (index + 30) % 55
				_seed_array[index] -= _seed_array[target]
				if _seed_array[index] < 0:
					_seed_array[index] += MBIG

	func value() -> float:
		_inext += 1
		if _inext >= 56:
			_inext = 1
		_inextp += 1
		if _inextp >= 56:
			_inextp = 1
		var value := int(_seed_array[_inext] - _seed_array[_inextp])
		if value == MBIG:
			value -= 1
		if value < 0:
			value += MBIG
		_seed_array[_inext] = value
		return float(value) / float(MBIG)

	func range_int(minimum: int, maximum: int) -> int:
		return minimum + int(floor(value() * float(maximum - minimum)))

	func value_bias_lower(strength: float) -> float:
		var sample := value()
		if strength >= 1.0:
			return 0.0
		var k := clampf(1.0 - strength, 0.0, 1.0)
		k = k * k * k - 1.0
		return clampf((sample + sample * k) / (sample * k + 1.0), 0.0, 1.0)
