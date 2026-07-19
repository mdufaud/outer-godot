extends RefCounted

const SHADER_PATH := "res://shaders/atmosphere_lut.comp"
const TEXTURE_SIZE := 256
const WORKGROUP_SIZE := 8

static var _shared_shader := RID()
static var _shared_pipeline := RID()
static var _shared_refcount := 0

var texture: ImageTexture
var _rendering_device: RenderingDevice
var _buffer := RID()
var _uniform_set := RID()


func initialize(atmosphere_radius_ratio: float, density_falloff: float) -> void:
	_shared_refcount += 1
	RenderingServer.call_on_render_thread(_initialize_render.bind(atmosphere_radius_ratio, density_falloff))


func shutdown() -> void:
	_shared_refcount -= 1
	RenderingServer.call_on_render_thread(_shutdown_render)


func _initialize_render(atmosphere_radius_ratio: float, density_falloff: float) -> void:
	_rendering_device = RenderingServer.get_rendering_device()
	if _rendering_device == null:
		return
	if not _shared_shader.is_valid():
		var source := RDShaderSource.new()
		source.source_compute = FileAccess.get_file_as_string(SHADER_PATH)
		var spirv := _rendering_device.shader_compile_spirv_from_source(source, true)
		if not spirv.compile_error_compute.is_empty():
			push_error(spirv.compile_error_compute)
			return
		_shared_shader = _rendering_device.shader_create_from_spirv(spirv)
		_shared_pipeline = _rendering_device.compute_pipeline_create(_shared_shader)
	_buffer = _rendering_device.storage_buffer_create(TEXTURE_SIZE * TEXTURE_SIZE * 4)
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(_buffer)
	_uniform_set = _rendering_device.uniform_set_create([uniform], _shared_shader, 0)
	var constants := PackedFloat32Array([atmosphere_radius_ratio, density_falloff, 0.0, 0.0]).to_byte_array()
	constants.encode_u32(8, TEXTURE_SIZE)
	constants.encode_s32(12, 100)
	var command_list := _rendering_device.compute_list_begin()
	_rendering_device.compute_list_bind_compute_pipeline(command_list, _shared_pipeline)
	_rendering_device.compute_list_bind_uniform_set(command_list, _uniform_set, 0)
	_rendering_device.compute_list_set_push_constant(command_list, constants, constants.size())
	_rendering_device.compute_list_dispatch(command_list, TEXTURE_SIZE / WORKGROUP_SIZE, TEXTURE_SIZE / WORKGROUP_SIZE, 1)
	_rendering_device.compute_list_end()
	var bytes := _rendering_device.buffer_get_data(_buffer)
	texture = ImageTexture.create_from_image(Image.create_from_data(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RF, bytes))


func _shutdown_render() -> void:
	if _rendering_device == null:
		return
	if _uniform_set.is_valid() and _rendering_device.uniform_set_is_valid(_uniform_set):
		_rendering_device.free_rid(_uniform_set)
	if _buffer.is_valid():
		_rendering_device.free_rid(_buffer)
	if _shared_refcount <= 0:
		for resource in [_shared_pipeline, _shared_shader]:
			if resource.is_valid():
				_rendering_device.free_rid(resource)
		_shared_pipeline = RID()
		_shared_shader = RID()
