extends CompositorEffect

# Ordered post-process chain for planetary oceans and atmospheres.
#
# Godot copies the back buffer once per frame before the transparent pass, so
# stacked full-screen quads reading hint_screen_texture overwrite each other
# instead of composing. Both reference projects solve this with an explicit
# ordered chain: SebLague blits materials far to near, ProceduralPlanetGodot
# chains SubViewports. This does the same with one compute pass per effect,
# ping-ponging between the color layer and a scratch texture.

const OceanShaderPath := "res://shaders/ocean_effect.glsl"
const AtmosphereShaderPath := "res://shaders/atmosphere_effect.glsl"
const BlitShaderPath := "res://shaders/blit_effect.glsl"
const OceanWaveATexture := preload("res://assets/ocean_textures/wave_a.png")
const OceanWaveBTexture := preload("res://assets/ocean_textures/wave_b.png")
const OceanFoamTexture := preload("res://assets/ocean_textures/water_foam.png")
const BlueNoiseTexture := preload("res://assets/planet_textures/blue_noise.png")

const MAX_BODIES := 16
const OCEAN_FLOATS := 36
const ATMOSPHERE_FLOATS := 20
const PUSH_CONSTANT_SIZE := 96
const WORKGROUP_SIZE := 8
const KIND_OCEAN := 0
const KIND_ATMOSPHERE := 1
const TEXTURE_CONTEXT := &"planet_effects"
const TEXTURE_NAME := &"scratch"

var display_oceans := true
var display_atmospheres := true

var _mutex := Mutex.new()
var _passes := PackedInt32Array()
var _ocean_data := PackedFloat32Array()
var _atmosphere_data := PackedFloat32Array()
var _lut_textures: Array[RID] = []
var _time := 0.0

var _initialized := false
var _shaders := {}
var _pipelines := {}
var _samplers := {}
var _ocean_buffer := RID()
var _atmosphere_buffer := RID()
var _uniform_sets := {}
var _uniform_set_key := ""
var _static_textures := {}


func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT


# Mirrors SebLague PlanetEffects.GetMaterials: bodies far to near.
func update_from_bodies(camera_position: Vector3, candidates: Array) -> void:
	var bodies: Array = []
	for body in candidates:
		if body.has_method("get_ocean_effect_params"):
			bodies.append(body)
	bodies.sort_custom(func(first, second):
		return _sort_distance(first, camera_position) > _sort_distance(second, camera_position))

	var passes := PackedInt32Array()
	var ocean_data := PackedFloat32Array()
	var atmosphere_data := PackedFloat32Array()
	var lut_textures: Array[RID] = []
	for body in bodies:
		if ocean_data.size() / OCEAN_FLOATS >= MAX_BODIES:
			break
		var ocean_params: PackedFloat32Array = body.get_ocean_effect_params()
		var ocean_index := -1
		var camera_underwater := false
		if display_oceans and not ocean_params.is_empty():
			ocean_index = ocean_data.size() / OCEAN_FLOATS
			ocean_data.append_array(ocean_params)
			camera_underwater = camera_position.distance_squared_to(Vector3(
				ocean_params[0], ocean_params[1], ocean_params[2])) < ocean_params[3] * ocean_params[3]
		if ocean_index >= 0 and not camera_underwater:
			passes.append(KIND_OCEAN)
			passes.append(ocean_index)
		var lut: Texture2D = body.get_atmosphere_lut_texture()
		if display_atmospheres and lut != null:
			var atmosphere_index := atmosphere_data.size() / ATMOSPHERE_FLOATS
			atmosphere_data.append_array(body.get_atmosphere_effect_params())
			lut_textures.append(RenderingServer.texture_get_rd_texture(lut.get_rid()))
			passes.append(KIND_ATMOSPHERE)
			passes.append(atmosphere_index)
		if ocean_index >= 0 and camera_underwater:
			passes.append(KIND_OCEAN)
			passes.append(ocean_index)

	_mutex.lock()
	_passes = passes
	_ocean_data = ocean_data
	_atmosphere_data = atmosphere_data
	_lut_textures = lut_textures
	_time = float(Time.get_ticks_msec()) * 0.001
	_mutex.unlock()


func clear() -> void:
	_mutex.lock()
	_passes = PackedInt32Array()
	_mutex.unlock()


func _sort_distance(body: Node3D, camera_position: Vector3) -> float:
	return maxf(0.0, body.global_position.distance_to(camera_position) - float(body.get("radius")))


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or not _initialized:
		return
	_initialized = false
	var rendering_device := RenderingServer.get_rendering_device()
	if rendering_device == null:
		return
	# Uniform sets are dropped by the engine along with the render buffers they
	# reference, so only the resources owned outright are freed here.
	for group in [[_ocean_buffer, _atmosphere_buffer], _samplers.values(), _pipelines.values(), _shaders.values()]:
		for resource in group:
			if resource.is_valid():
				rendering_device.free_rid(resource)


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	var rendering_device := RenderingServer.get_rendering_device()
	if rendering_device == null:
		return

	_mutex.lock()
	var passes := _passes
	var ocean_data := _ocean_data
	var atmosphere_data := _atmosphere_data
	var lut_textures := _lut_textures
	var time := _time
	_mutex.unlock()

	if passes.is_empty():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	if not _initialize_resources(rendering_device):
		return

	var color := buffers.get_color_layer(0)
	var depth := buffers.get_depth_layer(0)
	var scratch := _scratch_texture(buffers, size)
	if not color.is_valid() or not depth.is_valid() or not scratch.is_valid():
		return
	_refresh_uniform_sets(rendering_device, color, depth, scratch, lut_textures)

	if not ocean_data.is_empty():
		rendering_device.buffer_update(_ocean_buffer, 0, ocean_data.size() * 4, ocean_data.to_byte_array())
	if not atmosphere_data.is_empty():
		rendering_device.buffer_update(_atmosphere_buffer, 0, atmosphere_data.size() * 4, atmosphere_data.to_byte_array())

	var scene_data := render_data.get_render_scene_data() as RenderSceneDataRD
	var camera_transform := scene_data.get_cam_transform()
	var inverse_view_projection := Projection(camera_transform) * scene_data.get_cam_projection().inverse()
	var groups_x := int(ceil(float(size.x) / float(WORKGROUP_SIZE)))
	var groups_y := int(ceil(float(size.y) / float(WORKGROUP_SIZE)))

	var pass_count := passes.size() / 2
	var reading_color := true
	var command_list := rendering_device.compute_list_begin()
	for pass_index in pass_count:
		var kind := passes[pass_index * 2]
		var body_index := passes[pass_index * 2 + 1]
		var shader_key := "ocean" if kind == KIND_OCEAN else "atmosphere"
		var push_constant := _build_push_constant(inverse_view_projection, camera_transform.origin, time, size, body_index)
		rendering_device.compute_list_bind_compute_pipeline(command_list, _pipelines[shader_key])
		rendering_device.compute_list_bind_uniform_set(command_list, _uniform_sets["%s_%d" % [shader_key, int(reading_color)]], 0)
		if kind == KIND_ATMOSPHERE:
			rendering_device.compute_list_bind_uniform_set(command_list, _uniform_sets["lut_%d" % body_index], 1)
		rendering_device.compute_list_set_push_constant(command_list, push_constant, push_constant.size())
		rendering_device.compute_list_dispatch(command_list, groups_x, groups_y, 1)
		rendering_device.compute_list_add_barrier(command_list)
		reading_color = not reading_color

	# An odd number of passes leaves the result in the scratch texture; the
	# color layer has no CAN_COPY_TO usage, so copy it back with a compute blit.
	if not reading_color:
		var blit_constant := PackedByteArray()
		blit_constant.resize(16)
		blit_constant.encode_s32(0, size.x)
		blit_constant.encode_s32(4, size.y)
		blit_constant.encode_s32(8, 0)
		blit_constant.encode_s32(12, 0)
		rendering_device.compute_list_bind_compute_pipeline(command_list, _pipelines["blit"])
		rendering_device.compute_list_bind_uniform_set(command_list, _uniform_sets["blit_0"], 0)
		rendering_device.compute_list_set_push_constant(command_list, blit_constant, blit_constant.size())
		rendering_device.compute_list_dispatch(command_list, groups_x, groups_y, 1)
		rendering_device.compute_list_add_barrier(command_list)
	rendering_device.compute_list_end()


func _build_push_constant(inverse_view_projection: Projection, camera_position: Vector3, time: float, size: Vector2i, body_index: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(PUSH_CONSTANT_SIZE)
	var columns := [inverse_view_projection.x, inverse_view_projection.y, inverse_view_projection.z, inverse_view_projection.w]
	for column in 4:
		var vector: Vector4 = columns[column]
		bytes.encode_float(column * 16 + 0, vector.x)
		bytes.encode_float(column * 16 + 4, vector.y)
		bytes.encode_float(column * 16 + 8, vector.z)
		bytes.encode_float(column * 16 + 12, vector.w)
	bytes.encode_float(64, camera_position.x)
	bytes.encode_float(68, camera_position.y)
	bytes.encode_float(72, camera_position.z)
	bytes.encode_float(76, time)
	bytes.encode_s32(80, size.x)
	bytes.encode_s32(84, size.y)
	bytes.encode_s32(88, body_index)
	bytes.encode_s32(92, 0)
	return bytes


func _scratch_texture(buffers: RenderSceneBuffersRD, size: Vector2i) -> RID:
	if buffers.has_texture(TEXTURE_CONTEXT, TEXTURE_NAME):
		return buffers.get_texture(TEXTURE_CONTEXT, TEXTURE_NAME)
	return buffers.create_texture(
		TEXTURE_CONTEXT, TEXTURE_NAME,
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT,
		RenderingDevice.TEXTURE_SAMPLES_1,
		size, 1, 1, true, false)


func _initialize_resources(rendering_device: RenderingDevice) -> bool:
	if _initialized:
		return true
	for entry in [["ocean", OceanShaderPath], ["atmosphere", AtmosphereShaderPath], ["blit", BlitShaderPath]]:
		var shader_file := load(entry[1]) as RDShaderFile
		if shader_file == null:
			push_error("planet_effects: cannot load %s" % entry[1])
			return false
		var spirv := shader_file.get_spirv()
		if not spirv.compile_error_compute.is_empty():
			push_error("planet_effects: %s: %s" % [entry[1], spirv.compile_error_compute])
			return false
		var shader := rendering_device.shader_create_from_spirv(spirv)
		_shaders[entry[0]] = shader
		_pipelines[entry[0]] = rendering_device.compute_pipeline_create(shader)
	_samplers["screen"] = _create_sampler(rendering_device, RenderingDevice.SAMPLER_FILTER_LINEAR, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE, false)
	_samplers["depth"] = _create_sampler(rendering_device, RenderingDevice.SAMPLER_FILTER_NEAREST, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE, false)
	_samplers["repeat"] = _create_sampler(rendering_device, RenderingDevice.SAMPLER_FILTER_LINEAR, RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT, true)
	_ocean_buffer = rendering_device.storage_buffer_create(MAX_BODIES * OCEAN_FLOATS * 4)
	_atmosphere_buffer = rendering_device.storage_buffer_create(MAX_BODIES * ATMOSPHERE_FLOATS * 4)
	for entry in [["wave_a", OceanWaveATexture], ["wave_b", OceanWaveBTexture], ["foam", OceanFoamTexture], ["blue_noise", BlueNoiseTexture]]:
		_static_textures[entry[0]] = RenderingServer.texture_get_rd_texture((entry[1] as Texture2D).get_rid())
	_initialized = true
	return true


func _create_sampler(rendering_device: RenderingDevice, filter: int, repeat_mode: int, mipmaps: bool) -> RID:
	var state := RDSamplerState.new()
	state.min_filter = filter
	state.mag_filter = filter
	state.repeat_u = repeat_mode
	state.repeat_v = repeat_mode
	state.repeat_w = repeat_mode
	if mipmaps:
		state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		state.max_lod = 16.0
	return rendering_device.sampler_create(state)


func _refresh_uniform_sets(rendering_device: RenderingDevice, color: RID, depth: RID, scratch: RID, lut_textures: Array[RID]) -> void:
	var key := "%s|%s|%s|%s" % [color, depth, scratch, lut_textures]
	if key == _uniform_set_key:
		return
	_free_uniform_sets(rendering_device)
	_uniform_set_key = key
	# reading_color == true means color is the source and scratch the destination.
	for reading_color in [true, false]:
		var source := color if reading_color else scratch
		var destination := scratch if reading_color else color
		var suffix := int(reading_color)
		_uniform_sets["ocean_%d" % suffix] = rendering_device.uniform_set_create([
			_sampler_uniform(0, "screen", source),
			_image_uniform(1, destination),
			_sampler_uniform(2, "depth", depth),
			_sampler_uniform(3, "repeat", _static_textures["wave_a"]),
			_sampler_uniform(4, "repeat", _static_textures["wave_b"]),
			_sampler_uniform(5, "repeat", _static_textures["foam"]),
			_buffer_uniform(6, _ocean_buffer),
		], _shaders["ocean"], 0)
		_uniform_sets["atmosphere_%d" % suffix] = rendering_device.uniform_set_create([
			_sampler_uniform(0, "screen", source),
			_image_uniform(1, destination),
			_sampler_uniform(2, "depth", depth),
			_sampler_uniform(3, "repeat", _static_textures["blue_noise"]),
			_buffer_uniform(4, _atmosphere_buffer),
		], _shaders["atmosphere"], 0)
	_uniform_sets["blit_0"] = rendering_device.uniform_set_create([
		_sampler_uniform(0, "screen", scratch),
		_image_uniform(1, color),
	], _shaders["blit"], 0)
	for index in lut_textures.size():
		var lut: RID = lut_textures[index]
		if not lut.is_valid():
			continue
		_uniform_sets["lut_%d" % index] = rendering_device.uniform_set_create([
			_sampler_uniform(0, "screen", lut),
		], _shaders["atmosphere"], 1)


func _sampler_uniform(binding: int, sampler_key: String, texture: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = binding
	uniform.add_id(_samplers[sampler_key])
	uniform.add_id(texture)
	return uniform


func _image_uniform(binding: int, texture: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(texture)
	return uniform


func _buffer_uniform(binding: int, buffer: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)
	return uniform


func _free_uniform_sets(rendering_device: RenderingDevice) -> void:
	for set_rid in _uniform_sets.values():
		if set_rid.is_valid() and rendering_device.uniform_set_is_valid(set_rid):
			rendering_device.free_rid(set_rid)
	_uniform_sets.clear()
	_uniform_set_key = ""
