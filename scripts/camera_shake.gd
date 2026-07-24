extends Node

var _strength := 0.0
var _duration := 0.0
var _elapsed := 0.0
var _camera: Camera3D


func shake(camera: Camera3D, strength: float, duration: float) -> void:
	_camera = camera
	_strength = maxf(_strength, strength)
	_duration = maxf(_duration, duration)
	_elapsed = 0.0


func _process(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	if _elapsed >= _duration:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		return
	_elapsed += delta
	var fade := 1.0 - clampf(_elapsed / maxf(_duration, 0.001), 0.0, 1.0)
	var phase := _elapsed * 47.0
	_camera.h_offset = sin(phase * 1.17) * _strength * fade
	_camera.v_offset = cos(phase * 0.93) * _strength * fade
