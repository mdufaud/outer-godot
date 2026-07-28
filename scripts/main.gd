extends Node3D

const PLANET_SCENE := preload("res://scenes/planet.tscn")
const SHIP_SCENE := preload("res://scenes/ship.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SUN_SCENE := preload("res://scenes/sun.tscn")
const HUD_SCENE := preload("res://scenes/hud.tscn")
const CameraShakeScript := preload("res://scripts/camera_shake.gd")
const BonificationMathScript := preload("res://scripts/bonification_math.gd")
const SolarSystemContentScript := preload("res://scripts/solar_system_content.gd")
const FloatingOriginScript := preload("res://scripts/floating_origin.gd")
const PlanetEffectsScript := preload("res://scripts/planet_effects.gd")
const SunFXScript := preload("res://scripts/sun_fx.gd")

const SUN_RADIUS := 345.0
const SUN_SURFACE_GRAVITY := 50.0
const PLAYER_SPAWN_CLEARANCE := 3.0
const BOOT_STALL_WARNING_MS := 10000
const BOOT_TIMEOUT_MS := 180000

var player: CharacterBody3D
var ship: RigidBody3D
var ship_spawn: Transform3D
var earth: Node3D
var moon: Node3D
var spawn_direction := Vector3.UP
var sun: Node3D
var sun_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var _loading_layer: CanvasLayer
var _loading_root: Control
var _loading_label: Label
var _loading_progress: ProgressBar
var _feedback_root: Control
var _underwater_strength := 0.0
var _sky_material: ShaderMaterial
var _planet_effects: CompositorEffect
var _camera_shake: Node
var _ocean_audio: AudioStreamPlayer
var _wind_audio: AudioStreamPlayer
var _dread_pulse: Node
var _was_underwater := false
var _was_in_atmosphere := false
var _feedback_initialized := false
var _transition_tint: ColorRect
var _transition_strength := 0.0
var _loaded := false
var _boot_started_ms := 0
var _boot_last_change_ms := 0
var _boot_last_warning_ms := 0
var _boot_last_snapshot := ""


func _ready() -> void:
	_boot_started_ms = Time.get_ticks_msec()
	_boot_last_change_ms = _boot_started_ms
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

	var spawned_bodies := {}
	for definition in get_body_definitions():
		_log_boot("Creating body %s" % definition.name)
		var body := _spawn_body(definition.name, definition.position, definition.data)
		spawned_bodies[definition.name] = body
		_loading_label.text = "Preparing %s…" % definition.name
		await get_tree().process_frame
	earth = spawned_bodies["Terra"]
	moon = spawned_bodies["Luna"]
	if spawned_bodies.has("Watchful Eye"):
		_dread_pulse = preload("res://scripts/dread_pulse.gd").new()
		_dread_pulse.name = "WatchfulEyeDread"
		_dread_pulse.target = spawned_bodies["Watchful Eye"]
		add_child(_dread_pulse)
		var comet_trail := preload("res://scripts/comet_trail.gd").new()
		comet_trail.name = "WatchfulEyeTrail"
		comet_trail.target = spawned_bodies["Watchful Eye"]
		comet_trail.sun = sun
		add_child(comet_trail)
	if spawned_bodies.has("Mirage"):
		var mirage_ring := preload("res://scripts/asteroid_ring.gd").new()
		mirage_ring.name = "MirageRing"
		spawned_bodies["Mirage"].add_child(mirage_ring)
	_log_boot("Waiting for %d bodies" % spawned_bodies.size())
	if not await _wait_for_bodies(spawned_bodies.values()):
		return

	_log_boot("Creating orbital system")
	var celestial_system := preload("res://scripts/celestial_system.gd").new()
	celestial_system.name = "CelestialSystem"
	add_child(celestial_system)

	var player_direction: Vector3 = earth.call("get_sunlit_spawn_direction", sun.global_position)
	spawn_direction = earth.call("get_nearby_land_direction", player_direction)
	var earth_velocity: Vector3 = earth.get("orbital_velocity")
	_log_boot("Spawning ship and player")
	ship = SHIP_SCENE.instantiate()
	ship.position = earth.call("get_landing_point", spawn_direction, 2.8)
	add_child(ship)
	ship.linear_velocity = earth_velocity

	player = PLAYER_SCENE.instantiate()
	add_child(player)
	spawn_on_planet(earth)
	_build_feedback_overlay()
	_build_environment_feedback()

	add_child(HUD_SCENE.instantiate())
	if Touch.is_touch_ui():
		var layer := CanvasLayer.new()
		layer.layer = 2
		add_child(layer)
		var touch := preload("res://scripts/touch_hud.gd").new()
		touch.main = self
		layer.add_child(touch)
	var floating_origin := FloatingOriginScript.new()
	floating_origin.name = "FloatingOrigin"
	add_child(floating_origin)
	_loaded = true
	_log_boot("Boot complete")
	get_viewport().size_changed.disconnect(_resize_loading_screen)
	_loading_layer.queue_free()
	_loading_root = null


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	_update_lighting(camera)
	_update_sky(camera)
	_update_planet_effects(camera)
	_update_underwater_state(delta, camera)
	_update_environment_feedback(delta, camera)


func _update_planet_effects(camera: Camera3D) -> void:
	if _planet_effects == null:
		return
	if camera == null:
		_planet_effects.clear()
		return
	_planet_effects.update_from_bodies(camera.global_position, get_tree().get_nodes_in_group("celestial_body"))


func _build_feedback_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
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
	_transition_tint = ColorRect.new()
	var transition_material := ShaderMaterial.new()
	transition_material.shader = preload("res://shaders/environment_transition.gdshader")
	_transition_tint.material = transition_material
	_transition_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition_tint.visible = false
	_feedback_root.add_child(_transition_tint)
	_ocean_audio = AudioStreamPlayer.new()
	_ocean_audio.stream = preload("res://assets/audio/ocean_waves.wav")
	_ocean_audio.volume_linear = 0.0
	add_child(_ocean_audio)
	_set_stream_loop(_ocean_audio.stream)
	_ocean_audio.play()
	_wind_audio = AudioStreamPlayer.new()
	_wind_audio.stream = preload("res://assets/audio/wind.wav")
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
		var source: Node3D = Gravity.get_nearest_surface(camera.global_position)
		if source == null:
			source = Gravity.get_strongest(camera.global_position)
		if source != null and source.has_method("get_water_depth"):
			target_strength = underwater_effect_target(float(source.get_water_depth(camera.global_position)))
	_underwater_strength = move_toward(_underwater_strength, target_strength, delta * 2.8)


func _update_environment_feedback(delta: float, camera: Camera3D) -> void:
	if camera == null or _ocean_audio == null:
		return
	var source := Gravity.get_nearest_surface(camera.global_position)
	if source == null:
		source = Gravity.get_strongest(camera.global_position)
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
	_transition_tint.visible = _transition_strength > 0.001
	(_transition_tint.material as ShaderMaterial).set_shader_parameter("strength", _transition_strength)


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
	var source := Gravity.get_nearest_surface(camera.global_position)
	if source == null:
		source = Gravity.get_strongest(camera.global_position)
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
	_sky_material.set_shader_parameter("sun_direction", (sun.global_position - camera.global_position).normalized())
	var source := Gravity.get_nearest_surface(camera.global_position)
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


func _build_loading_screen() -> void:
	_loading_layer = CanvasLayer.new()
	_loading_layer.layer = 100
	add_child(_loading_layer)
	_loading_root = Control.new()
	_loading_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_root.size = get_viewport().get_visible_rect().size
	_loading_layer.add_child(_loading_root)
	get_viewport().size_changed.connect(_resize_loading_screen)
	var background := ColorRect.new()
	background.color = Color(0.008, 0.012, 0.035)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_root.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_root.add_child(center)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(440.0, 0.0)
	content.add_theme_constant_override("separation", 18)
	center.add_child(content)
	var title := Label.new()
	title.text = "OUTER GODOT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	content.add_child(title)
	_loading_label = Label.new()
	_loading_label.text = "Initializing…"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_color_override("font_color", Color(0.65, 0.75, 1.0))
	content.add_child(_loading_label)
	_loading_progress = ProgressBar.new()
	_loading_progress.show_percentage = true
	_loading_progress.value = 0.0
	content.add_child(_loading_progress)


func _resize_loading_screen() -> void:
	if _loading_root != null:
		_loading_root.size = get_viewport().get_visible_rect().size


func _wait_for_bodies(bodies: Array) -> bool:
	while true:
		var progress := 0.0
		var ready_count := 0
		var pending: Array[String] = []
		var snapshot_parts: Array[String] = []
		for body in bodies:
			var generator_error := String(body.call("get_generator_error"))
			if not generator_error.is_empty():
				var body_error := "%s: %s" % [body.name, generator_error]
				_loading_label.text = body_error
				push_error("[BOOT] %s" % body_error)
				return false
			var status: Dictionary = body.call("get_boot_status")
			progress += float(status.progress)
			snapshot_parts.append("%s=%s@%.1f" % [body.name, status.stage, float(status.progress) * 100.0])
			if bool(status.ready):
				ready_count += 1
			else:
				pending.append("%s: %s" % [body.name, status.stage])
		_loading_progress.value = progress / float(bodies.size()) * 100.0
		var pending_label := pending[0] if not pending.is_empty() else "finalizing"
		_loading_label.text = "Generating — %d/%d ready — %s" % [ready_count, bodies.size(), pending_label]
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
			_loading_label.text = timeout_message
			push_error("[BOOT +%d ms] %s" % [now - _boot_started_ms, timeout_message])
			return false
		if ready_count == bodies.size():
			return true
		await get_tree().process_frame
	return false


func _log_boot(message: String) -> void:
	print("[BOOT +%d ms] %s" % [Time.get_ticks_msec() - _boot_started_ms, message])


func _spawn_body(body_name: String, position_value: Vector3, data: Dictionary) -> Node3D:
	var body := PLANET_SCENE.instantiate()
	body.name = body_name
	var requested_quality := OS.get_environment("PLANET_QUALITY")
	if requested_quality.is_empty():
		requested_quality = "mobile_low" if RenderingServer.get_current_rendering_method() == "mobile" else "desktop_high"
	if requested_quality not in ["desktop_high", "desktop_medium", "mobile_low"]:
		requested_quality = "desktop_high"
	body.set("quality_profile", requested_quality)
	var property_map := {
		"body_kind": "body_kind",
		"surface_style": "surface_style",
		"radius": "radius",
		"core_radius": "core_radius",
		"gravity": "surface_gravity",
		"seed": "rng_seed",
		"perturb_strength": "perturb_strength",
		"ocean": "has_ocean",
		"ocean_level": "ocean_level",
		"ocean_shallow_color": "ocean_shallow_color",
		"ocean_deep_color": "ocean_deep_color",
		"ocean_wave_strength": "ocean_wave_strength",
		"ocean_wave_scale": "ocean_wave_scale",
		"ocean_wave_speed": "ocean_wave_speed",
		"ocean_smoothness": "ocean_smoothness",
		"ocean_depth_multiplier": "ocean_depth_multiplier",
		"ocean_alpha_multiplier": "ocean_alpha_multiplier",
		"ocean_specular_color": "ocean_specular_color",
		"ocean_foam_scale": "ocean_foam_scale",
		"ocean_foam_distance": "ocean_foam_distance",
		"ocean_refraction_strength": "ocean_refraction_strength",
		"underwater_tint": "underwater_tint",
		"underwater_darkness": "underwater_darkness",
		"atmosphere": "has_atmosphere",
		"atmosphere_color": "atmosphere_color",
		"atmosphere_scale": "atmosphere_scale",
		"atmosphere_density_falloff": "atmosphere_density_falloff",
		"atmosphere_wavelengths": "atmosphere_wavelengths",
		"atmosphere_scattering_strength": "atmosphere_scattering_strength",
		"atmosphere_intensity": "atmosphere_intensity",
		"shore_color": "shore_color",
		"land_low_color": "land_low_color",
		"land_high_color": "land_high_color",
	}
	for key in property_map:
		if data.has(key):
			body.set(property_map[key], data[key])
	body.position = position_value
	add_child(body)
	return body


static func get_body_definitions() -> Array[Dictionary]:
	return SolarSystemContentScript.get_body_definitions()


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = preload("res://shaders/stars.gdshader")
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
	_planet_effects = PlanetEffectsScript.new()
	var compositor := Compositor.new()
	compositor.compositor_effects = [_planet_effects]
	world_env.compositor = compositor
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
	elif event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func respawn() -> void:
	var player_direction: Vector3 = earth.call("get_sunlit_spawn_direction", sun.global_position)
	spawn_direction = earth.call("get_nearby_land_direction", player_direction)
	var earth_velocity: Vector3 = earth.get("orbital_velocity")
	ship_spawn = Transform3D(Basis.IDENTITY, earth.call("get_landing_point", spawn_direction, 2.8))
	ship.reset(ship_spawn, earth_velocity)
	spawn_on_planet(earth)


func spawn_on_planet(body: Node3D) -> bool:
	if body == null or not body.has_method("get_sunlit_spawn_direction"):
		return false
	if ship != null and ship.pilot == player:
		ship.exit_pilot()
	var direction: Vector3 = body.call("get_sunlit_spawn_direction", sun.global_position)
	var position_value: Vector3 = body.call("get_landing_point", direction, PLAYER_SPAWN_CLEARANCE)
	var x_axis := -Vector3.BACK.cross(direction)
	if x_axis.length_squared() < 0.001:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	var basis := Basis(x_axis, direction, x_axis.cross(direction)).orthonormalized()
	var body_velocity: Vector3 = body.get("orbital_velocity")
	player.reset(Transform3D(basis, position_value), body_velocity)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("set_selected_planet"):
		hud.set_selected_planet(body.name)
	return true


func spawn_on_planet_named(body_name: StringName) -> bool:
	for body in get_tree().get_nodes_in_group("celestial_body"):
		if body.name == body_name and body.has_method("get_surface_radius_towards"):
			return spawn_on_planet(body)
	return false
