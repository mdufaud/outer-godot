extends Node3D

@export var radius := 120.0
@export var surface_gravity := 20.0
@export var death_radius := 200.0

var influence_radius := 2000.0


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 96
	sphere.rings = 48
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/sun.gdshader")
	sphere.material = mat
	mesh.mesh = sphere
	add_child(mesh)

	var light := OmniLight3D.new()
	light.omni_range = 6000.0
	light.omni_attenuation = 1.2
	light.light_energy = 3.0
	light.shadow_enabled = false
	add_child(light)

	var death_zone := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = death_radius
	col.shape = shape
	death_zone.add_child(col)
	death_zone.body_entered.connect(_on_body_entered)
	add_child(death_zone)

	Gravity.register(self)


func _exit_tree() -> void:
	Gravity.unregister(self)


func _on_body_entered(_body: Node3D) -> void:
	var main := get_tree().current_scene
	if main and main.has_method("respawn"):
		main.respawn()
