extends Node3D

const SunFXScript := preload("res://game/sun/sun_fx.gd")
const GravityServiceScript := preload("res://game/celestial/gravity.gd")
const SupernovaScript := preload("res://game/sun/supernova.gd")
const SunShader := preload("res://game/sun/shaders/sun.gdshader")
const CoronaShader := preload("res://game/sun/shaders/corona.gdshader")

const BASE_EMISSION := 9.0

@export var radius := 120.0
@export var surface_gravity := 0.2
@export var death_radius := 180.0

var influence_radius := 2600.0
var orbital_velocity := Vector3.ZERO
var supernova: Supernova
@onready var gravity_service: GravityService = get_node("/root/Gravity")


func _ready() -> void:
	add_to_group("sun")
	add_to_group("celestial_body")
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	var mat := ShaderMaterial.new()
	mat.shader = SunShader
	mat.set_shader_parameter("pulse_enabled", SunFXScript.PULSE)
	mat.set_shader_parameter("emission_strength", BASE_EMISSION)
	sphere.material = mat
	mesh.mesh = sphere
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

	var visuals: Array[Node3D] = [mesh]
	if SunFXScript.HALO:
		var corona := MeshInstance3D.new()
		var corona_quad := QuadMesh.new()
		var corona_scale := 4.0
		corona_quad.size = Vector2.ONE * radius * 2.0 * corona_scale
		var corona_mat := ShaderMaterial.new()
		corona_mat.shader = CoronaShader
		corona_mat.render_priority = 10
		corona_mat.set_shader_parameter("disk_radius", 1.0 / corona_scale)
		corona_mat.set_shader_parameter("pulse_enabled", SunFXScript.PULSE)
		corona_mat.set_shader_parameter("god_rays_enabled", SunFXScript.GOD_RAYS)
		corona_mat.set_shader_parameter("prominences_enabled", SunFXScript.PROMINENCES)
		corona_mat.set_shader_parameter("chromatic_band_enabled", SunFXScript.CHROMATIC_BAND)
		corona_mat.set_shader_parameter("embers_enabled", SunFXScript.EMBERS)
		corona_quad.material = corona_mat
		corona.mesh = corona_quad
		corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		corona.extra_cull_margin = radius * corona_scale
		add_child(corona)
		visuals.append(corona)

	var death_zone := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = death_radius
	col.shape = shape
	death_zone.add_child(col)
	death_zone.body_entered.connect(_on_body_entered)
	add_child(death_zone)

	supernova = SupernovaScript.new()
	supernova.name = "Supernova"
	add_child(supernova)
	supernova.setup(visuals, mesh, radius, BASE_EMISSION)
	gravity_service.register(self)


func _exit_tree() -> void:
	gravity_service.unregister(self)


func detonate() -> void:
	supernova.detonate()


func is_exploding() -> bool:
	return supernova != null and supernova.is_active()


func get_gravitational_parameter() -> float:
	return surface_gravity * radius * radius


func set_orbital_state(next_position: Vector3, next_velocity: Vector3) -> void:
	global_position = next_position
	orbital_velocity = next_velocity


func _on_body_entered(_body: Node3D) -> void:
	var main := get_tree().current_scene
	if main and main.has_method("respawn"):
		main.respawn()
