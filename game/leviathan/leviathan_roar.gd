extends Node

# Everything the leviathan sounds like, generated in code the same way the
# Watchful Eye pulse and the supernova boom are: a looping sub-bass drone that
# rises with its presence, and a roar fired on the beats that matter.
#
# The drone doubles as the ambience kill switch: main.gd already mixes the ocean
# and wind loops against a dread factor, so reporting 1.0 here silences them.

const SAMPLE_RATE := 22050
const DRONE_LENGTH := 6.0
const DRONE_BASE_FREQUENCY := 27.5
const ROAR_LENGTH := 4.4
const ROAR_START_FREQUENCY := 78.0
const ROAR_END_FREQUENCY := 19.0
const THUNDER_LENGTH := 1.15
const MAX_DRONE_VOLUME := 0.7
const MAX_ROAR_VOLUME := 1.0

var _drone: AudioStreamPlayer
var _roar: AudioStreamPlayer
var _thunder: AudioStreamPlayer
var _dread := 0.0


func _ready() -> void:
	_drone = AudioStreamPlayer.new()
	_drone.stream = _build_drone_stream()
	_drone.volume_linear = 0.0
	add_child(_drone)
	_roar = AudioStreamPlayer.new()
	_roar.stream = _build_roar_stream()
	_roar.volume_linear = MAX_ROAR_VOLUME
	add_child(_roar)
	_thunder = AudioStreamPlayer.new()
	_thunder.stream = _build_thunder_stream()
	add_child(_thunder)


# 0 silent, 1 the drone owns the mix. Read by main.gd to duck the ambience.
func get_dread_factor() -> float:
	return _dread


func set_dread(value: float) -> void:
	_dread = clampf(value, 0.0, 1.0)
	if _drone == null:
		return
	_drone.volume_linear = _dread * MAX_DRONE_VOLUME
	if _dread > 0.01 and not _drone.playing:
		_drone.play()
	elif _dread <= 0.01 and _drone.playing:
		_drone.stop()


func roar() -> void:
	if _roar != null:
		_roar.play()


func thunder(intensity: float = 1.0) -> void:
	if _thunder != null:
		_thunder.volume_linear = clampf(intensity, 0.0, 1.0) * 0.72
		_thunder.play()


func stop() -> void:
	set_dread(0.0)
	if _roar != null:
		_roar.stop()
	if _thunder != null:
		_thunder.stop()


# Two detuned sub sines beating against each other under a slow noise swell. The
# beat frequency is what makes it feel alive rather than like a test tone.
func _build_drone_stream() -> AudioStreamWAV:
	var frames := int(DRONE_LENGTH * float(SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 313377
	var phase := 0.0
	var beat_phase := 0.0
	var breath_phase := 0.0
	var rumble := 0.0
	for index in frames:
		var t := float(index) / float(frames)
		phase += TAU * DRONE_BASE_FREQUENCY / float(SAMPLE_RATE)
		beat_phase += TAU * (DRONE_BASE_FREQUENCY * 1.019) / float(SAMPLE_RATE)
		breath_phase += TAU * 0.22 / float(SAMPLE_RATE)
		rumble = lerpf(rumble, rng.randf_range(-1.0, 1.0), 0.012)
		var breath := 0.62 + 0.38 * sin(breath_phase)
		var sample := (sin(phase) * 0.55 + sin(beat_phase) * 0.45) * breath + rumble * 0.5
		# Crossfade the tail into the head so the loop seam is inaudible.
		var seam := clampf(t / 0.04, 0.0, 1.0) * clampf((1.0 - t) / 0.04, 0.0, 1.0)
		data.encode_s16(index * 2, int(clampf(sample * seam, -1.0, 1.0) * 32767.0))
	return _make_stream(data, AudioStreamWAV.LOOP_FORWARD)


# The roar itself: a pitch collapse from a scream down into infrasound, torn up
# by a fast ring modulation so it growls instead of whistling.
func _build_roar_stream() -> AudioStreamWAV:
	var frames := int(ROAR_LENGTH * float(SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6660001
	var phase := 0.0
	var growl_phase := 0.0
	var rasp := 0.0
	for index in frames:
		var t := float(index) / float(frames)
		var frequency := lerpf(ROAR_START_FREQUENCY, ROAR_END_FREQUENCY, sqrt(t))
		phase += TAU * frequency / float(SAMPLE_RATE)
		growl_phase += TAU * lerpf(31.0, 9.0, t) / float(SAMPLE_RATE)
		rasp = lerpf(rasp, rng.randf_range(-1.0, 1.0), 0.09)
		var attack := clampf(t / 0.09, 0.0, 1.0)
		var decay := pow(1.0 - t, 1.5)
		var growl := 0.55 + 0.45 * sin(growl_phase)
		var sample := sin(phase) * growl * 0.85 + rasp * 1.1 * growl
		data.encode_s16(index * 2, int(clampf(sample * attack * decay, -1.0, 1.0) * 32767.0))
	return _make_stream(data, AudioStreamWAV.LOOP_DISABLED)


func _build_thunder_stream() -> AudioStreamWAV:
	var frames := int(THUNDER_LENGTH * float(SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 972413
	var low_noise := 0.0
	var phase := 0.0
	for index in frames:
		var t := float(index) / float(frames)
		low_noise = lerpf(low_noise, rng.randf_range(-1.0, 1.0), 0.035)
		phase += TAU * lerpf(46.0, 24.0, t) / float(SAMPLE_RATE)
		var attack := clampf(t / 0.012, 0.0, 1.0)
		var decay := pow(1.0 - t, 2.2)
		var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 38.0)
		var sample := low_noise * 1.35 + sin(phase) * 0.42 + crack * 0.65
		data.encode_s16(index * 2, int(clampf(sample * attack * decay, -1.0, 1.0) * 32767.0))
	return _make_stream(data, AudioStreamWAV.LOOP_DISABLED)


func _make_stream(data: PackedByteArray, loop_mode: AudioStreamWAV.LoopMode) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = loop_mode
	if loop_mode == AudioStreamWAV.LOOP_FORWARD:
		stream.loop_end = data.size() / 2
	stream.data = data
	return stream
