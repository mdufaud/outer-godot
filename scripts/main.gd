extends Node3D

const PLANET_SCENE := preload("res://scenes/planet.tscn")
const SHIP_SCENE := preload("res://scenes/ship.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SUN_SCENE := preload("res://scenes/sun.tscn")
const HUD_SCENE := preload("res://scenes/hud.tscn")

const PLANETS := [
	{
		"name": "Terra", "pos": Vector3(800, 0, 0), "radius": 50.0,
		"gravity": 12.0, "color": Color(0.35, 0.6, 0.3), "props": "tree", "count": 60,
	},
	{
		"name": "Cinder", "pos": Vector3(-500, 0, 900), "radius": 35.0,
		"gravity": 16.0, "color": Color(0.65, 0.3, 0.2), "props": "rock", "count": 40,
	},
	{
		"name": "Glacia", "pos": Vector3(0, 300, -1600), "radius": 60.0,
		"gravity": 7.0, "color": Color(0.65, 0.75, 0.85), "props": "ice", "count": 50,
	},
	{
		"name": "Pebble", "pos": Vector3(950, 80, 250), "radius": 15.0,
		"gravity": 3.0, "color": Color(0.5, 0.5, 0.52), "props": "rock", "count": 12,
	},
]

var player: CharacterBody3D
var ship: RigidBody3D
var player_spawn: Transform3D
var ship_spawn: Transform3D


func _ready() -> void:
	_build_environment()

	var sun := SUN_SCENE.instantiate()
	add_child(sun)

	for data in PLANETS:
		var planet := PLANET_SCENE.instantiate()
		planet.name = data.name
		planet.radius = data.radius
		planet.surface_gravity = data.gravity
		planet.color = data.color
		planet.prop_kind = data.props
		planet.prop_count = data.count
		planet.rng_seed = hash(data.name)
		planet.position = data.pos
		add_child(planet)

	var terra: Vector3 = PLANETS[0].pos
	var terra_radius: float = PLANETS[0].radius

	ship = SHIP_SCENE.instantiate()
	ship.position = terra + Vector3(0, terra_radius + 1.75, 0)
	add_child(ship)
	ship_spawn = ship.global_transform

	player = PLAYER_SCENE.instantiate()
	var dir := Vector3(6, 50, 6).normalized()
	player.position = terra + dir * (terra_radius + 1.2)
	add_child(player)
	player_spawn = player.global_transform

	add_child(HUD_SCENE.instantiate())


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/stars.gdshader")
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.32, 0.4)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_bloom = 0.2
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("respawn"):
		respawn()
	elif event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func respawn() -> void:
	ship.reset(ship_spawn)
	player.reset(player_spawn)
