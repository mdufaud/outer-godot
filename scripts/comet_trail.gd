extends Node3D

# Interloper style plume: short, thick and welded to the body, pointing away
# from the sun. Not a long history streak, the shape is rebuilt every frame from
# the body radius so it always reads as gas boiling off the surface.

const TrailShader := preload("res://shaders/comet_trail.gdshader")

const SEGMENTS := 26
const LENGTH_SCALE := 7.5
const HEAD_WIDTH := 1.05
const BELLY_WIDTH := 1.9
const BELLY_POSITION := 0.28
const TAIL_WIDTH := 0.55
const VELOCITY_BEND := 0.22

var target: Node3D
var sun: Node3D

var _mesh := ImmediateMesh.new()
var _material := ShaderMaterial.new()


func _ready() -> void:
	_material.shader = TrailShader
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3.ONE * -100000.0, Vector3.ONE * 200000.0)
	add_child(instance)


func _process(_delta: float) -> void:
	if target == null or not target.is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	# Vertices are written in world space, so the node must stay at the origin
	# even when the floating origin moves every root child.
	global_position = Vector3.ZERO
	_mesh.clear_surfaces()
	_draw_plume(camera.global_position)


func _draw_plume(camera_position: Vector3) -> void:
	var origin := target.global_position
	var radius := float(target.get("radius")) if target.get("radius") != null else 20.0
	var sun_position := sun.global_position if sun != null and sun.is_inside_tree() else Vector3.ZERO
	var axis := (origin - sun_position).normalized()
	if axis.length_squared() < 0.5:
		axis = Vector3.FORWARD
	# A little of the travel direction bends the plume so it trails the body
	# instead of sitting perfectly radial.
	var velocity: Variant = target.get("orbital_velocity")
	if velocity is Vector3 and (velocity as Vector3).length() > 0.001:
		axis = (axis - (velocity as Vector3).normalized() * VELOCITY_BEND).normalized()
	var length := radius * LENGTH_SCALE
	# Start inside the body so the plume never shows a gap at the surface.
	var start := origin - axis * (radius * 0.35)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
	for index in SEGMENTS + 1:
		var along := float(index) / float(SEGMENTS)
		var centre := start + axis * (length * along)
		var side := axis.cross(centre - camera_position)
		if side.length_squared() < 0.0001:
			side = axis.cross(Vector3.UP)
		side = side.normalized()
		var width := radius * _width_profile(along)
		var fade := pow(1.0 - along, 1.35)
		_add_pair(centre, side * width, along, fade)
	_mesh.surface_end()


# Narrow at the surface, bulging just behind it, then tapering out.
func _width_profile(along: float) -> float:
	if along < BELLY_POSITION:
		return lerpf(HEAD_WIDTH, BELLY_WIDTH, along / BELLY_POSITION)
	var rest := (along - BELLY_POSITION) / (1.0 - BELLY_POSITION)
	return lerpf(BELLY_WIDTH, TAIL_WIDTH, pow(rest, 0.75))


func _add_pair(centre: Vector3, offset: Vector3, along: float, fade: float) -> void:
	var color := Color(1.0, 1.0, 1.0, maxf(fade, 0.0))
	_mesh.surface_set_color(color)
	_mesh.surface_set_uv(Vector2(along, 0.0))
	_mesh.surface_add_vertex(centre - offset)
	_mesh.surface_set_color(color)
	_mesh.surface_set_uv(Vector2(along, 1.0))
	_mesh.surface_add_vertex(centre + offset)
