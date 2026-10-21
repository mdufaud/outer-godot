class_name EnvironmentController
extends Node

const PlanetEffectsScript := preload("res://game/rendering/planet_effects.gd")

var _planet_effects: PlanetEffects
var _environment: Environment


# Only an HDR display gets HDR output: requesting it also switches 2D to linear
# blending, which would lighten every translucent overlay on SDR screens.
func _ready() -> void:
	var window := get_window()
	if DisplayServer.window_is_hdr_output_supported(window.get_window_id()):
		window.use_hdr_2d = true
		window.hdr_output_requested = true
	window.output_max_linear_value_changed.connect(_apply_tonemap)


func attach_to(world_environment: WorldEnvironment) -> void:
	_planet_effects = PlanetEffectsScript.new()
	var compositor := Compositor.new()
	compositor.compositor_effects = [_planet_effects]
	world_environment.compositor = compositor
	_environment = world_environment.environment
	_apply_tonemap(get_window().get_output_max_linear_value())


# Filmic clamps to SDR, so an HDR display only gets its headroom through AgX.
func _apply_tonemap(output_max_linear_value: float) -> void:
	if _environment != null:
		_environment.tonemap_mode = Environment.TONE_MAPPER_AGX if output_max_linear_value > 1.0 else Environment.TONE_MAPPER_FILMIC


func update(camera: Camera3D) -> void:
	if _planet_effects == null:
		return
	if camera == null:
		_planet_effects.clear()
		return
	_planet_effects.update_from_bodies(camera.global_position, get_tree().get_nodes_in_group("celestial_body"))
