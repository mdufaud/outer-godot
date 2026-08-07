extends Node3D

const SHIP_SCENE := preload("res://game/ship/ship.tscn")
const PLAYER_SCENE := preload("res://game/player/player.tscn")
const SUN_SCENE := preload("res://game/sun/sun.tscn")
const HUD_SCENE := preload("res://game/hud/hud.tscn")
const TouchHudScript := preload("res://game/hud/touch_hud.gd")
const LoadingScreenScript := preload("res://game/bootstrap/loading_screen.gd")
const SpawnControllerScript := preload("res://game/bootstrap/spawn_controller.gd")
const EnvironmentControllerScript := preload("res://game/bootstrap/environment_controller.gd")
const CameraShakeScript := preload("res://game/rendering/camera_shake.gd")
const EnvironmentTransitionShader := preload("res://game/rendering/shaders/environment_transition.gdshader")
const StarsShader := preload("res://game/rendering/shaders/stars.gdshader")
const OceanWavesAudio := preload("res://assets/audio/ocean_waves.wav")
const WindAudio := preload("res://assets/audio/wind.wav")
const BonificationMathScript := preload("res://game/shared/bonification_math.gd")
const SolarSystemManifestScript := preload("res://game/celestial/solar_system_manifest.gd")
const CelestialSystemScript := preload("res://game/celestial/celestial_system.gd")
const GravityServiceScript := preload("res://game/celestial/gravity.gd")
const TouchServiceScript := preload("res://game/input/touch.gd")
const PlanetBodyScript := preload("res://game/planets/shared/planet_body.gd")
const FloatingOriginScript := preload("res://game/celestial/floating_origin.gd")
const SunFXScript := preload("res://game/sun/sun_fx.gd")
const LeviathanScript := preload("res://game/leviathan/leviathan.gd")

const SUN_RADIUS := 345.0
const SUN_SURFACE_GRAVITY := 50.0
const SUN_GLOW_FADE_NEAR_RADII := 12.0
const SUN_GLOW_FADE_FAR_RADII := 24.0
const BOOT_STALL_WARNING_MS := 10000
const BOOT_TIMEOUT_MS := 180000

var player: CharacterBody3D
var ship: RigidBody3D
var earth: PlanetBody
var moon: PlanetBody
var sun: Node3D
var sun_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var _loading_screen: LoadingScreen
var _feedback_root: Control
var _underwater_strength := 0.0
var _sky_material: ShaderMaterial
var _environment_controller: EnvironmentController
var _camera_shake: Node
var _ocean_audio: AudioStreamPlayer
var _wind_audio: AudioStreamPlayer
var _dread_pulse: Node
var _was_underwater := false
var _was_in_atmosphere := false
var _feedback_initialized := false
var _transition_tint: ColorRect
var _transition_strength := 0.0
var _cloud_transition_strength := 0.0
var _rain_overlay: ColorRect
var _rain_strength := 0.0
var _loaded := false
var _boot_started_ms := 0
var _boot_last_change_ms := 0
var _boot_last_warning_ms := 0
var _boot_last_snapshot := ""
var _bodies_by_id: Dictionary = {}
var _spawn_controller: SpawnController
@onready var gravity_service: GravityService = get_node("/root/Gravity")
@onready var touch_service: TouchService = get_node("/root/Touch")


func _ready() -> void:
	_boot_started_ms = Time.get_ticks_msec()
	_boot_last_change_ms = _boot_started_ms
	_spawn_controller = SpawnControllerScript.new()
	_spawn_controller.setup(self)
	add_child(_spawn_controller)
	_environment_controller = EnvironmentControllerScript.new()
	_environment_controller.setup(self)
	add_child(_environment_controller)
	_build_loading_screen()
	_log_boot("Loading screen ready; renderer=%s" % RenderingServer.get_current_rendering_method())
	_boot.call_deferred()


func _boot() -> void:
	await get_tree().process_frame
	_log_boot("Building environment")
	_build_environment()
	_log_boot("Creating Sun")
	sun = SUN_SCENE.instantiate()
	sun.position = Vector3.ZERO
	sun.set("radius", SUN_RADIUS)
	sun.set("surface_gravity", SUN_SURFACE_GRAVITY)
	add_child(sun)

	var entries: Array[CelestialEntry] = SolarSystemManifestScript.get_entries()
	var spawned_bodies: Dictionary = {}
	var spawned_body_list: Array[PlanetBody] = []
	for entry in entries:
		_log_boot("Creating body %s" % entry.body_id)
		var body: PlanetBody = _spawn_body(entry)
		spawned_bodies[entry.body_id] = body
		spawned_body_list.append(body)
		_loading_screen.set_status("Preparing %s…" % entry.body_id)
		await get_tree().process_frame
	_bodies_by_id = spawned_bodies
	earth = spawned_bodies[&"Terra"] as PlanetBody
	moon = spawned_bodies[&"Luna"] as PlanetBody
	_log_boot("Waiting for %d bodies" % spawned_bodies.size())
	if not await _wait_for_bodies(spawned_body_list):
		return

	_log_boot("Creating orbital system")
	var celestial_system := CelestialSystemScript.new()
	celestial_system.name = "CelestialSystem"
	celestial_system.configure(entries, spawned_bodies, sun)
	add_child(celestial_system)

	var player_direction: Vector3 = earth.get_sunlit_spawn_direction(sun.global_position)
	var spawn_direction: Vector3 = earth.get_nearby_land_direction(player_direction)
	var earth_velocity: Vector3 = earth.orbital_velocity
	_log_boot("Spawning ship and player")
	ship = SHIP_SCENE.instantiate()
	ship.position = earth.get_landing_point(spawn_direction, 2.8)
	add_child(ship)
	ship.linear_velocity = earth_velocity

	player = PLAYER_SCENE.instantiate()
	add_child(player)
	spawn_on_planet(earth)
	_build_feedback_overlay()
	_build_environment_feedback()

	add_child(HUD_SCENE.instantiate())
	if touch_service.is_touch_ui():
		var layer := CanvasLayer.new()
		layer.layer = 2
		add_child(layer)
		var touch := TouchHudScript.new()
		touch.main = self
		layer.add_child(touch)
	var floating_origin := FloatingOriginScript.new()
	floating_origin.name = "FloatingOrigin"
	add_child(floating_origin)
	var leviathan := LeviathanScript.new()
	leviathan.name = "Leviathan"
	add_child(leviathan)
	# The ambience already mixes against a dread factor; the leviathan is what
	# finally drives it, so the wind and the ocean die when it shows up.
	_dread_pulse = leviathan
	_loaded = true
	_log_boot("Boot complete")
	_loading_screen.finish()
	_loading_screen = null


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	_update_lighting(camera)
	_update_sky(camera)
	_update_planet_effects(camera)
	_update_underwater_state(delta, camera)
	_update_environment_feedback(delta, camera)


func _update_planet_effects(camera: Camera3D) -> void:
	_environment_controller.update(camera)


func _build_feedback_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var back_buffer := BackBufferCopy.new()
	back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	layer.add_child(back_buffer)
	_feedback_root = Control.new()
	_feedback_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback_root.size = get_viewport().get_visible_rect().size
	layer.add_child(_feedback_root)
	get_viewport().size_changed.connect(_resize_feedback_overlay)


func _resize_feedback_overlay() -> void:
	if _feedback_root != null:
		_feedback_root.size = get_viewport().get_visible_rect().size


func _build_environment_feedback() -> void:
	_camera_shake = CameraShakeScript.new()
	_camera_shake.add_to_group("camera_shake")
	add_child(_camera_shake)
	_rain_overlay = ColorRect.new()
	var rain_material := ShaderMaterial.new()
	var rain_shader: Shader
	for body_variant in get_tree().get_nodes_in_group("celestial_body"):
		var body := body_variant as PlanetBody
		if body != null and body.has_weather_capability() and body.config.weather.rain_shader != null:
			rain_shader = body.config.weather.rain_shader
			break
	rain_material.shader = rain_shader
	rain_material.set_shader_parameter("droplet_layers", 3 if RenderingServer.get_current_rendering_method() == "forward_plus" else 2)
	_rain_overlay.material = rain_material
	_rain_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rain_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rain_overlay.visible = false
	_feedback_root.add_child(_rain_overlay)
	_transition_tint = ColorRect.new()
	var transition_material := ShaderMaterial.new()
	transition_material.shader = EnvironmentTransitionShader
	_transition_tint.material = transition_material
	_transition_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition_tint.visible = false
	_feedback_root.add_child(_transition_tint)
	_ocean_audio = AudioStreamPlayer.new()
	_ocean_audio.stream = OceanWavesAudio
	_ocean_audio.volume_linear = 0.0
	add_child(_ocean_audio)
	_set_stream_loop(_ocean_audio.stream)
	_ocean_audio.play()
	_wind_audio = AudioStreamPlayer.new()
	_wind_audio.stream = WindAudio
	_wind_audio.volume_linear = 0.0
	add_child(_wind_audio)
	_set_stream_loop(_wind_audio.stream)
	_wind_audio.play()


func _set_stream_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD


func _update_underwater_state(delta: float, camera: Camera3D) -> void:
	var target_strength := 0.0
	if camera != null:
		var source: Node3D = gravity_service.get_nearest_surface(camera.global_position)
		if source == null:
			source = gravity_service.get_strongest(camera.global_position)
		if source != null and source.has_method("get_water_depth"):
			target_strength = underwater_effect_target(float(source.get_water_depth(camera.global_position)))
	_underwater_strength = move_toward(_underwater_strength, target_strength, delta * 2.8)


func _update_environment_feedback(delta: float, camera: Camera3D) -> void:
	if camera == null or _ocean_audio == null:
		return
	var source := gravity_service.get_nearest_surface(camera.global_position)
	if source == null:
		source = gravity_service.get_strongest(camera.global_position)
	var weather_source := _get_weather_source(camera.global_position)
	var water_depth := float(source.get_water_depth(camera.global_position)) if source != null and source.has_method("get_water_depth") else -INF
	var distance_to_surface := absf(water_depth) if is_finite(water_depth) else INF
	var ocean_target := 0.0
	if source != null and source.get("has_ocean") == true:
		ocean_target = clampf(1.0 - distance_to_surface / 18.0, 0.0, 1.0)
		if water_depth > 0.0:
			ocean_target = maxf(ocean_target, 0.45)
	var in_atmosphere := false
	var wind_target := 0.0
	if source != null and source.get("has_atmosphere") == true:
		var atmosphere_radius := float(source.get("radius")) * (1.0 + float(source.get("atmosphere_scale")))
		var distance_to_center := camera.global_position.distance_to(source.global_position)
		in_atmosphere = atmosphere_contains(camera.global_position, source.global_position, float(source.get("radius")), float(source.get("atmosphere_scale")))
		wind_target = clampf((atmosphere_radius - distance_to_center) / maxf(atmosphere_radius - float(source.get("radius")), 0.001), 0.0, 1.0)
		wind_target *= 1.0 - _underwater_strength
	var dread := float(_dread_pulse.call("get_dread_factor")) if _dread_pulse != null else 0.0
	var ambience := 1.0 - dread
	_ocean_audio.volume_linear = move_toward(_ocean_audio.volume_linear, ocean_target * 0.42 * ambience, delta * 0.6)
	_wind_audio.volume_linear = move_toward(_wind_audio.volume_linear, wind_target * 0.34 * ambience, delta * 0.6)
	var underwater := water_depth > 0.0
	if _feedback_initialized:
		if underwater != _was_underwater:
			_trigger_environment_transition(camera, Color(0.16, 0.58, 0.72), 0.035, 0.32)
		if in_atmosphere != _was_in_atmosphere:
			_trigger_environment_transition(camera, Color(0.55, 0.72, 1.0), 0.022, 0.45)
	else:
		_feedback_initialized = true
	_was_underwater = underwater
	_was_in_atmosphere = in_atmosphere
	_transition_strength = move_toward(_transition_strength, 0.0, delta * 1.8)
	var weather_feedback: Dictionary = weather_source.get_weather_feedback(camera.global_position) if weather_source != null else {}
	_cloud_transition_strength = float(weather_feedback.get("cloud_transition", 0.0))
	_transition_tint.visible = _transition_strength > 0.001 or _cloud_transition_strength > 0.001
	var transition_material := _transition_tint.material as ShaderMaterial
	transition_material.set_shader_parameter("strength", _transition_strength)
	transition_material.set_shader_parameter("cloud_strength", _cloud_transition_strength)
	var rain_target := 0.0
	if weather_source != null:
		rain_target = float(weather_feedback.get("rain_strength", 0.0)) * (1.0 - _underwater_strength)
	_rain_strength = move_toward(_rain_strength, rain_target, delta * 1.2)
	_rain_overlay.visible = _rain_strength > 0.001
	(_rain_overlay.material as ShaderMaterial).set_shader_parameter("strength", _rain_strength)


func _get_weather_source(camera_position: Vector3) -> PlanetBody:
	var nearest: PlanetBody = null
	var nearest_distance := INF
	for body in get_tree().get_nodes_in_group("celestial_body"):
		if not is_instance_valid(body) or not body.has_method("has_weather_capability") or not body.has_weather_capability():
			continue
		var distance := (body as Node3D).global_position.distance_squared_to(camera_position)
		if distance < nearest_distance:
			nearest = body as PlanetBody
			nearest_distance = distance
	return nearest


func _trigger_environment_transition(camera: Camera3D, tint: Color, shake_strength: float, duration: float) -> void:
	_transition_strength = 1.0
	var material := _transition_tint.material as ShaderMaterial
	material.set_shader_parameter("tint", tint)
	_camera_shake.shake(camera, shake_strength, duration)


func trigger_camera_shake(strength: float, duration: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null and _camera_shake != null:
		_camera_shake.shake(camera, strength, duration)


static func underwater_effect_target(depth: float) -> float:
	return BonificationMathScript.underwater_effect_target(depth)


static func atmosphere_contains(position_value: Vector3, center: Vector3, body_radius: float, atmosphere_scale: float) -> bool:
	return BonificationMathScript.atmosphere_contains(position_value, center, body_radius, atmosphere_scale)


func _update_lighting(camera: Camera3D) -> void:
	if camera == null or sun == null or sun_light == null:
		return
	var ray_direction := (camera.global_position - sun.global_position).normalized()
	var up := Vector3.UP
	if absf(ray_direction.dot(up)) > 0.98:
		up = Vector3.RIGHT
	sun_light.global_position = camera.global_position
	sun_light.look_at(camera.global_position + ray_direction, up)
	var source := gravity_service.get_nearest_surface(camera.global_position)
	if source == null:
		source = gravity_service.get_strongest(camera.global_position)
	if source == null or source == sun:
		fill_light.light_energy = 0.0
		return
	var to_body := (source.global_position - camera.global_position).normalized()
	var direct_visibility := maxf(to_body.dot(-ray_direction), 0.0)
	fill_light.global_position = camera.global_position
	fill_light.look_at(source.global_position, up)
	fill_light.light_energy = 0.08 + (1.0 - direct_visibility) * 0.10


func _update_sky(camera: Camera3D) -> void:
	if camera == null or _sky_material == null or sun == null:
		return
	_sky_material.set_shader_parameter("camera_position", camera.global_position)
	var camera_to_sun := sun.global_position - camera.global_position
	_sky_material.set_shader_parameter("sun_direction", camera_to_sun.normalized())
	# The fake distant sun and the real exploding mesh must not overlap once the supernova
	# pushes the camera far plane past the sun.
	var glow_strength := 0.0 if bool(sun.call("is_exploding")) else distant_sun_glow_strength(camera_to_sun.length(), float(sun.get("radius")))
	_sky_material.set_shader_parameter("sun_glow_strength", glow_strength)
	var weather_source := _get_weather_source(camera.global_position)
	var weather_feedback: Dictionary = weather_source.get_weather_feedback(camera.global_position) if weather_source != null else {}
	var storm_occlusion := float(weather_feedback.get("sky_occlusion", 0.0))
	_sky_material.set_shader_parameter("storm_occlusion", storm_occlusion)
	var source := gravity_service.get_nearest_surface(camera.global_position)
	var water_depth := float(source.get_water_depth(camera.global_position)) if source != null and source.has_method("get_water_depth") else -INF
	var sky_occlusion := 1.0 if water_depth > 0.0 else 0.0
	_sky_material.set_shader_parameter("underwater_strength", sky_occlusion)
	var spheres := PackedVector4Array()
	for body in get_tree().get_nodes_in_group("celestial_body"):
		if body != sun and body.get("has_ocean") == true and spheres.size() < 8:
			spheres.append(Vector4(body.global_position.x, body.global_position.y, body.global_position.z, float(body.get("radius")) + float(body.get("ocean_level"))))
	_sky_material.set_shader_parameter("ocean_count", spheres.size())
	_sky_material.set_shader_parameter("ocean_spheres", spheres)
	var daylight := 0.0
	if source != null and source != sun:
		var local_up := (camera.global_position - source.global_position).normalized()
		var local_sun := (sun.global_position - source.global_position).normalized()
		var atmosphere_limit := float(source.get("radius")) * (1.0 + float(source.get("atmosphere_scale"))) if source.get("has_atmosphere") == true else float(source.get("radius")) * 1.05
		if camera.global_position.distance_to(source.global_position) < atmosphere_limit:
			daylight = smoothstep(-0.08, 0.25, local_up.dot(local_sun))
	_sky_material.set_shader_parameter("daylight", daylight * (1.0 - sky_occlusion))


static func distant_sun_glow_strength(distance_to_center: float, sun_radius: float) -> float:
	return smoothstep(sun_radius * SUN_GLOW_FADE_NEAR_RADII, sun_radius * SUN_GLOW_FADE_FAR_RADII, distance_to_center)


func _build_loading_screen() -> void:
	_loading_screen = LoadingScreenScript.new()
	add_child(_loading_screen)
	_loading_screen.setup()

func _wait_for_bodies(bodies: Array[PlanetBody]) -> bool:
	while true:
		var progress := 0.0
		var ready_count := 0
		var pending: Array[String] = []
		var snapshot_parts: Array[String] = []
		for body in bodies:
			var generator_error := body.get_generator_error()
			if not generator_error.is_empty():
				var body_error := "%s: %s" % [body.name, generator_error]
				_loading_screen.set_status(body_error)
				push_error("[BOOT] %s" % body_error)
				return false
			var status: Dictionary = body.get_boot_status()
			progress += float(status.progress)
			snapshot_parts.append("%s=%s@%.1f" % [body.name, status.stage, float(status.progress) * 100.0])
			if bool(status.ready):
				ready_count += 1
			else:
				pending.append("%s: %s" % [body.name, status.stage])
		_loading_screen.set_progress(progress / float(bodies.size()) * 100.0)
		var pending_label := pending[0] if not pending.is_empty() else "finalizing"
		_loading_screen.set_status("Generating — %d/%d ready — %s" % [ready_count, bodies.size(), pending_label])
		var snapshot := " | ".join(snapshot_parts)
		var now := Time.get_ticks_msec()
		if snapshot != _boot_last_snapshot:
			_boot_last_snapshot = snapshot
			_boot_last_change_ms = now
			_log_boot(snapshot)
		elif now - _boot_last_change_ms >= BOOT_STALL_WARNING_MS and now - _boot_last_warning_ms >= BOOT_STALL_WARNING_MS:
			_boot_last_warning_ms = now
			push_warning("[BOOT +%d ms] No loading change for %d ms; pending: %s" % [now - _boot_started_ms, now - _boot_last_change_ms, "; ".join(pending)])
		if now - _boot_started_ms >= BOOT_TIMEOUT_MS:
			var timeout_message := "Solar system loading timed out; pending: %s" % "; ".join(pending)
			_loading_screen.set_status(timeout_message)
			push_error("[BOOT +%d ms] %s" % [now - _boot_started_ms, timeout_message])
			return false
		if ready_count == bodies.size():
			return true
		await get_tree().process_frame
	return false


func _log_boot(message: String) -> void:
	print("[BOOT +%d ms] %s" % [Time.get_ticks_msec() - _boot_started_ms, message])


func _spawn_body(entry: CelestialEntry) -> PlanetBody:
	var body: PlanetBody = entry.scene.instantiate()
	body.name = String(entry.body_id)
	var requested_quality := OS.get_environment("PLANET_QUALITY")
	if requested_quality.is_empty():
		requested_quality = "mobile_low" if RenderingServer.get_current_rendering_method() == "mobile" else "desktop_high"
	if requested_quality not in ["desktop_high", "desktop_medium", "mobile_low"]:
		requested_quality = "desktop_high"
	body.quality_override = StringName(requested_quality)
	body.position = entry.initial_position
	add_child(body)
	return body


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = StarsShader
	_sky_material.set_shader_parameter("sun_glow_enabled", SunFXScript.DISTANT_GLOW)
	_sky_material.set_shader_parameter("sun_pulse_enabled", SunFXScript.PULSE)
	sky.sky_material = _sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.16, 0.24)
	env.ambient_light_energy = 0.2
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 1.15
	env.glow_strength = 1.1
	env.glow_bloom = 0.18
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 12.0
	env.ssao_enabled = true
	env.ssao_intensity = 1.4
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_environment_controller.attach_to(world_env)
	add_child(world_env)
	sun_light = DirectionalLight3D.new()
	sun_light.light_color = Color(1.0, 0.84, 0.64)
	sun_light.light_energy = 1.2
	sun_light.shadow_enabled = true
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun_light.directional_shadow_max_distance = 150.0
	sun_light.directional_shadow_split_1 = 0.06666667
	sun_light.directional_shadow_split_2 = 0.2
	sun_light.directional_shadow_split_3 = 0.46666667
	sun_light.directional_shadow_pancake_size = 10.0
	sun_light.shadow_bias = 0.16
	sun_light.shadow_normal_bias = 0.1
	add_child(sun_light)
	fill_light = DirectionalLight3D.new()
	fill_light.light_color = Color(0.38, 0.5, 0.68)
	fill_light.light_energy = 0.0
	fill_light.shadow_enabled = false
	add_child(fill_light)


func _unhandled_input(event: InputEvent) -> void:
	if not _loaded:
		return
	if event.is_action_pressed("respawn"):
		respawn()
	elif event.is_action_pressed("ui_cancel") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func respawn() -> void:
	_spawn_controller.respawn()


func spawn_on_planet(body: PlanetBody) -> bool:
	return _spawn_controller.spawn_on_planet(body)


# A destroyed body must not survive in the lookups, or teleporting and respawning
# would hand out freed instances.
func forget_body(body: Node3D) -> void:
	for body_id in _bodies_by_id.keys():
		if _bodies_by_id[body_id] == body:
			_bodies_by_id.erase(body_id)
	if earth == body:
		earth = null
	if moon == body:
		moon = null


func spawn_on_planet_id(body_name: StringName) -> bool:
	return _spawn_controller.spawn_on_planet_id(body_name)
