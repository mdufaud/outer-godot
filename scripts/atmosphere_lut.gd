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
var _status := "queued"
var _error := ""
var _status_mutex := Mutex.new()


func initialize(atmosphere_radius_ratio: float, density_falloff: float) -> void:
	_shared_refcount += 1
	_set_status("waiting for render thread")
	RenderingServer.call_on_render_thread(_initialize_render.bind(atmosphere_radius_ratio, density_falloff))


func get_status() -> String:
	_status_mutex.lock()
	var result := _status
	_status_mutex.unlock()
	return result


func get_error() -> String:
	_status_mutex.lock()
	var result := _error
	_status_mutex.unlock()
	return result


func _set_status(value: String, error_message := "") -> void:
	_status_mutex.lock()
	_status = value
	_error = error_message
	_status_mutex.unlock()


func shutdown() -> void:
	_shared_refcount -= 1
	RenderingServer.call_on_render_thread(_shutdown_render)


func _initialize_render(atmosphere_radius_ratio: float, density_falloff: float) -> void:
	_set_status("initializing rendering device")
	_rendering_device = RenderingServer.get_rendering_device()
	if _rendering_device == null:
		_set_status("failed", "Atmosphere LUT generation requires Forward+ or Mobile rendering.")
		return
	if not _shared_shader.is_valid():
		_set_status("compiling compute shader")
		var source := RDShaderSource.new()
		source.source_compute = FileAccess.get_file_as_string(SHADER_PATH)
		var spirv := _rendering_device.shader_compile_spirv_from_source(source, true)
		if not spirv.compile_error_compute.is_empty():
			push_error(spirv.compile_error_compute)
			_set_status("failed", spirv.compile_error_compute)
			return
		_shared_shader = _rendering_device.shader_create_from_spirv(spirv)
		_shared_pipeline = _rendering_device.compute_pipeline_create(_shared_shader)
	_set_status("dispatching compute shader")
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
	_set_status("reading GPU result")
	var bytes := _rendering_device.buffer_get_data(_buffer)
	texture = ImageTexture.create_from_image(Image.create_from_data(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RF, bytes))
	_set_status("ready")


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
