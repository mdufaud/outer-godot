extends Node

# Approach dread for the intruder body: everything else goes quiet and a single
# low pulse repeats, louder and closer together the nearer the camera gets.

const SAMPLE_RATE := 22050
const PULSE_LENGTH := 2.6
const START_FREQUENCY := 44.0
const END_FREQUENCY := 31.0
const FAR_RANGE := 1800.0
const NEAR_RANGE := 40.0
const FAR_INTERVAL := 8.5
const NEAR_INTERVAL := 5.0
const MAX_VOLUME := 0.85
const MIN_AUDIBLE := 0.02

var target: Node3D

var _player: AudioStreamPlayer
var _timer := 0.0
var _proximity := 0.0


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.stream = _build_pulse_stream()
	_player.volume_linear = 0.0
	_player.bus = "Master"
	add_child(_player)


# 0 far away, 1 at the surface. Used to duck the rest of the ambience.
func get_dread_factor() -> float:
	return _proximity


func _process(delta: float) -> void:
	if target == null or not target.is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance := camera.global_position.distance_to(target.global_position)
	var raw := clampf((FAR_RANGE - distance) / (FAR_RANGE - NEAR_RANGE), 0.0, 1.0)
	_proximity = move_toward(_proximity, raw * raw, delta * 0.5)
	if _proximity < MIN_AUDIBLE:
		_timer = 0.0
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = lerpf(FAR_INTERVAL, NEAR_INTERVAL, _proximity)
	_player.volume_linear = _proximity * MAX_VOLUME
	_player.play()


# Sine glide down with a slow attack and a long tail, plus a quiet harmonic so
# the pulse still reads on speakers that cannot push the fundamental.
func _build_pulse_stream() -> AudioStreamWAV:
	var frames := int(PULSE_LENGTH * float(SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phase := 0.0
	var harmonic_phase := 0.0
	for index in frames:
		var t := float(index) / float(frames)
		var frequency := lerpf(START_FREQUENCY, END_FREQUENCY, t)
		phase += TAU * frequency / float(SAMPLE_RATE)
		harmonic_phase += TAU * frequency * 2.0 / float(SAMPLE_RATE)
		var attack := clampf(t / 0.12, 0.0, 1.0)
		var decay := pow(1.0 - t, 2.2)
		var envelope := attack * decay
		var sample := sin(phase) * 0.86 + sin(harmonic_phase) * 0.14
		data.encode_s16(index * 2, int(clampf(sample * envelope, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
