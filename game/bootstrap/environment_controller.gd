class_name EnvironmentController
extends Node

const PlanetEffectsScript := preload("res://game/rendering/planet_effects.gd")

var _planet_effects: PlanetEffects


func attach_to(world_environment: WorldEnvironment) -> void:
	_planet_effects = PlanetEffectsScript.new()
	var compositor := Compositor.new()
	compositor.compositor_effects = [_planet_effects]
	world_environment.compositor = compositor


func update(camera: Camera3D) -> void:
	if _planet_effects == null:
		return
	if camera == null:
		_planet_effects.clear()
		return
	_planet_effects.update_from_bodies(camera.global_position, get_tree().get_nodes_in_group("celestial_body"))
