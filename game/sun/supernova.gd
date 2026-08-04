class_name Supernova
extends Node3D

const SupernovaShader := preload("res://game/sun/shaders/supernova.gdshader")

const COLLAPSE_DURATION := 1.6
const WAVE_SPEED := 560.0
const WAVE_MAX_RADIUS := 13000.0
const COLLAPSE_MIN_SCALE := 0.35
const COLLAPSE_EMISSION := 26.0
const WAVE_DRAW_DISTANCE := 16000.0
const IGNITION_DURATION := 1.2
const BOOM_SAMPLE_RATE := 22050
const BOOM_LENGTH := 5.0

var _elapsed := -1.0
var _sun_visuals: Array[Node3D] = []
var _sun_mesh: MeshInstance3D
var _sun_radius := 1.0
var _sun_emission := 0.0
var _shell: MeshInstance3D
var _shell_material: ShaderMaterial
var _camera_far := {}
var _flash: ColorRect
var _boom: AudioStreamPlayer
var _ignited := false
var _destroyed: Array[Node3D] = []


func setup(sun_visuals: Array[Node3D], sun_mesh: MeshInstance3D, sun_radius: float, sun_emission: float) -> void:
	_sun_visuals = sun_visuals
	_sun_mesh = sun_mesh
	_sun_radius = sun_radius
	_sun_emission = sun_emission


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	_shell_material = ShaderMaterial.new()
	_shell_material.shader = SupernovaShader
	sphere.material = _shell_material
	_shell = MeshInstance3D.new()
	_shell.mesh = sphere
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shell.visible = false
	add_child(_shell)

	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_flash = ColorRect.new()
	_flash.color = Color(0.80, 0.90, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_flash)

	_boom = AudioStreamPlayer.new()
	_boom.stream = _build_boom_stream()
	add_child(_boom)


func detonate() -> void:
	if _elapsed >= 0.0:
		return
	_elapsed = 0.0


func is_active() -> bool:
	return _elapsed >= 0.0


func wave_radius() -> float:
	return wave_radius_at(_elapsed, _sun_radius)


static func wave_radius_at(elapsed: float, sun_radius: float) -> float:
	if elapsed < COLLAPSE_DURATION:
		return sun_radius
	return minf(sun_radius + WAVE_SPEED * (elapsed - COLLAPSE_DURATION), WAVE_MAX_RADIUS)


static func has_contact(observer_position: Vector3, sun_position: Vector3, radius: float) -> bool:
	return observer_position.distance_to(sun_position) <= radius


func reset_state() -> void:
	_elapsed = -1.0
	_ignited = false
	_shell.visible = false
	_flash.color.a = 0.0
	_restore_cameras()
	_restore_bodies()
	for visual in _sun_visuals:
		if is_instance_valid(visual):
			visual.visible = true
	if _sun_mesh != null:
		_sun_mesh.scale = Vector3.ONE
		_set_sun_emission(_sun_emission)


func _process(delta: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += delta
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_extend_camera_far(camera)
	if _elapsed < COLLAPSE_DURATION:
		_update_collapse()
		return
	if not _ignited:
		_ignite()
	var radius := wave_radius_at(_elapsed, _sun_radius)
	# Everything the front has passed is gone: no planet may show through the wall of light.
	_destroy_swallowed_bodies(radius)
	var ignition := clampf(1.0 - (_elapsed - COLLAPSE_DURATION) / IGNITION_DURATION, 0.0, 1.0)
	_flash.color.a = pow(ignition, 2.2)
	_shell.visible = true
	_shell.scale = Vector3.ONE * radius
	_shell_material.set_shader_parameter("wave_progress", clampf(radius / WAVE_MAX_RADIUS, 0.0, 1.0))
	_shell_material.set_shader_parameter("ignition", ignition)
	if camera == null:
		return
	var distance := camera.global_position.distance_to(global_position)
	_shake(maxf(clampf(1.0 - (distance - radius) / 2500.0, 0.0, 1.0) * 0.05, ignition * 0.18))
	if has_contact(camera.global_position, global_position, radius):
		var main := get_tree().current_scene
		if main != null and main.has_method("respawn"):
			main.respawn()
		reset_state()


# The blast itself: white-out, low boom, hard shake, and the sun body is gone for good.
func _ignite() -> void:
	_ignited = true
	for visual in _sun_visuals:
		if is_instance_valid(visual):
			visual.visible = false
	_boom.play()


func _destroy_swallowed_bodies(radius: float) -> void:
	for node in get_tree().get_nodes_in_group("celestial_body"):
		var body := node as Node3D
		if body == null or body == get_parent() or not body.visible:
			continue
		if body.global_position.distance_to(global_position) <= radius:
			body.visible = false
			_destroyed.append(body)


func _restore_bodies() -> void:
	for body in _destroyed:
		if is_instance_valid(body):
			body.visible = true
	_destroyed.clear()


func _update_collapse() -> void:
	var ratio := clampf(_elapsed / COLLAPSE_DURATION, 0.0, 1.0)
	if _sun_mesh != null:
		_sun_mesh.scale = Vector3.ONE * lerpf(1.0, COLLAPSE_MIN_SCALE, ratio)
		_set_sun_emission(lerpf(_sun_emission, COLLAPSE_EMISSION, ratio))
	_shake(ratio * 0.04)


func _set_sun_emission(value: float) -> void:
	var material := _sun_mesh.mesh.surface_get_material(0) as ShaderMaterial
	if material != null:
		material.set_shader_parameter("emission_strength", value)


func _shake(strength: float) -> void:
	if strength <= 0.0:
		return
	var main := get_tree().current_scene
	if main != null and main.has_method("trigger_camera_shake"):
		main.trigger_camera_shake(strength, 0.2)


# The sky shader fakes the distant sun because both cameras stop at 8000 units, but the
# real shell has to stay visible all the way out to Cyclops.
func _extend_camera_far(camera: Camera3D) -> void:
	if _camera_far.has(camera):
		return
	_camera_far[camera] = camera.far
	camera.far = WAVE_DRAW_DISTANCE


func _restore_cameras() -> void:
	for camera in _camera_far:
		if is_instance_valid(camera):
			camera.far = _camera_far[camera]
	_camera_far.clear()


# Sine punch gliding down under a low-passed noise roar, long tail. Same procedural
# approach as the Watchful Eye dread pulse.
func _build_boom_stream() -> AudioStreamWAV:
	var frames := int(BOOM_LENGTH * float(BOOM_SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 951753
	var phase := 0.0
	var rumble := 0.0
	for index in frames:
		var t := float(index) / float(frames)
		var frequency := lerpf(64.0, 21.0, sqrt(t))
		phase += TAU * frequency / float(BOOM_SAMPLE_RATE)
		rumble = lerpf(rumble, rng.randf_range(-1.0, 1.0), 0.05)
		var attack := clampf(t / 0.003, 0.0, 1.0)
		var decay := pow(1.0 - t, 1.8)
		var sample := sin(phase) * 0.6 + rumble * 1.8
		data.encode_s16(index * 2, int(clampf(sample * attack * decay, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = BOOM_SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
