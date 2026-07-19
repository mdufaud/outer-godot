extends Node3D

const PLANET_SCENE := preload("res://scenes/planet.tscn")
const SHIP_SCENE := preload("res://scenes/ship.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SUN_SCENE := preload("res://scenes/sun.tscn")
const HUD_SCENE := preload("res://scenes/hud.tscn")
const SolarSystemContentScript := preload("res://scripts/solar_system_content.gd")

const SUN_RADIUS := 345.0
const SUN_SURFACE_GRAVITY := 50.0
const PLAYER_SPAWN_CLEARANCE := 3.0

var player: CharacterBody3D
var ship: RigidBody3D
var ship_spawn: Transform3D
var earth: Node3D
var moon: Node3D
var spawn_direction := Vector3.UP
var sun: Node3D
var sun_light: DirectionalLight3D
var _loading_layer: CanvasLayer
var _loading_root: Control
var _loading_label: Label
var _loading_progress: ProgressBar
var _loaded := false


func _ready() -> void:
	_build_loading_screen()
	_boot.call_deferred()


func _boot() -> void:
	await get_tree().process_frame
	_build_environment()
	sun = SUN_SCENE.instantiate()
	sun.position = Vector3.ZERO
	sun.set("radius", SUN_RADIUS)
	sun.set("surface_gravity", SUN_SURFACE_GRAVITY)
	add_child(sun)

	var spawned_bodies := {}
	for definition in get_body_definitions():
		var body := _spawn_body(definition.name, definition.position, definition.data)
		spawned_bodies[definition.name] = body
		_loading_label.text = "Preparing %s…" % definition.name
		await get_tree().process_frame
	earth = spawned_bodies["Terra"]
	moon = spawned_bodies["Luna"]
	await _wait_for_bodies(spawned_bodies.values())

	_balance_sun_velocity(sun)
	var celestial_system := preload("res://scripts/celestial_system.gd").new()
	celestial_system.name = "CelestialSystem"
	add_child(celestial_system)

	var player_direction: Vector3 = earth.call("get_sunlit_spawn_direction", sun.global_position)
	spawn_direction = earth.call("get_nearby_land_direction", player_direction)
	var earth_velocity: Vector3 = earth.get("orbital_velocity")
	ship = SHIP_SCENE.instantiate()
	ship.position = earth.call("get_landing_point", spawn_direction, 2.8)
	add_child(ship)
	ship.linear_velocity = earth_velocity

	player = PLAYER_SCENE.instantiate()
	add_child(player)
	spawn_on_planet(earth)

	add_child(HUD_SCENE.instantiate())
	if Touch.is_touch_ui():
		var layer := CanvasLayer.new()
		layer.layer = 2
		add_child(layer)
		var touch := preload("res://scripts/touch_hud.gd").new()
		touch.main = self
		layer.add_child(touch)
	_loaded = true
	get_viewport().size_changed.disconnect(_resize_loading_screen)
	_loading_layer.queue_free()
	_loading_root = null


func _process(_delta: float) -> void:
	if sun_light != null and earth != null:
		sun_light.global_position = sun.global_position
		sun_light.look_at(earth.global_position, Vector3.UP)


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


func _wait_for_bodies(bodies: Array) -> void:
	while true:
		var progress := 0.0
		var ready_count := 0
		for body in bodies:
			var generator_error := String(body.call("get_generator_error"))
			if not generator_error.is_empty():
				_loading_label.text = generator_error
				push_error(generator_error)
				return
			progress += float(body.call("get_boot_progress"))
			if body.call("is_boot_ready"):
				ready_count += 1
		_loading_progress.value = progress / float(bodies.size()) * 100.0
		_loading_label.text = "Generating solar system — %d/%d bodies ready" % [ready_count, bodies.size()]
		if ready_count == bodies.size():
			return
		await get_tree().process_frame


func _spawn_body(body_name: String, position_value: Vector3, data: Dictionary) -> Node3D:
	var body := PLANET_SCENE.instantiate()
	body.name = body_name
	var property_map := {
		"body_kind": "body_kind",
		"surface_style": "surface_style",
		"radius": "radius",
		"gravity": "surface_gravity",
		"seed": "rng_seed",
		"velocity": "initial_velocity",
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


func _balance_sun_velocity(sun: Node) -> void:
	var momentum := Vector3.ZERO
	for body in get_tree().get_nodes_in_group("celestial_body"):
		if body == sun:
			continue
		var body_mu := float(body.call("get_gravitational_parameter"))
		var body_velocity: Vector3 = body.get("orbital_velocity")
		momentum += body_mu * body_velocity
	var sun_mu := float(sun.call("get_gravitational_parameter"))
	sun.set("orbital_velocity", -momentum / sun_mu)


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/stars.gdshader")
	sky.sky_material = sky_mat
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
	add_child(world_env)
	sun_light = DirectionalLight3D.new()
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
