extends Node3D

# Interloper style plume: a raymarched volume box welded to the body, +Z pointing
# away from the sun. The shape lives entirely in the shader, so the node only has
# to keep the box glued to the body and aimed downwind.

const TrailShader := preload("res://shaders/comet_trail.gdshader")

const LENGTH_SCALE := 22.0
const TAIL_RADIUS_SCALE := 6.0
const MOUTH_RADIUS_SCALE := 1.95
const HEAD_RADIUS_SCALE := 1.06
const COMA_RADIUS_SCALE := 2.5
# Room sunward of the body so the coma is not clipped by the box face.
const BACK_MARGIN_SCALE := 4.0
# Box walls sit well outside the cone envelope, which is soft-edged.
const BOX_PADDING := 1.5
const VELOCITY_BEND := 0.22
const DESKTOP_STEPS := 32
const TOUCH_STEPS := 18

var target: Node3D
var sun: Node3D

var _material := ShaderMaterial.new()
var _head_offset := 0.0


func _ready() -> void:
	var radius := float(target.get("radius")) if target != null and target.get("radius") != null else 20.0
	var length := radius * LENGTH_SCALE
	var tail_radius := radius * TAIL_RADIUS_SCALE
	var back_margin := radius * BACK_MARGIN_SCALE
	var half_extents := Vector3(tail_radius * BOX_PADDING, tail_radius * BOX_PADDING, (length + back_margin) * 0.5)
	_head_offset = -half_extents.z + back_margin

	_material.shader = TrailShader
	_material.set_shader_parameter("half_extents", half_extents)
	_material.set_shader_parameter("head_z", _head_offset)
	_material.set_shader_parameter("plume_length", length)
	_material.set_shader_parameter("body_radius", radius)
	_material.set_shader_parameter("coma_radius", radius * COMA_RADIUS_SCALE)
	_material.set_shader_parameter("head_radius", radius * HEAD_RADIUS_SCALE)
	_material.set_shader_parameter("mouth_radius", radius * MOUTH_RADIUS_SCALE)
	_material.set_shader_parameter("tail_radius", tail_radius)
	_material.set_shader_parameter("steps", TOUCH_STEPS if Touch.is_touch_ui() else DESKTOP_STEPS)

	var box := BoxMesh.new()
	box.size = half_extents * 2.0
	var instance := MeshInstance3D.new()
	instance.mesh = box
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _process(_delta: float) -> void:
	if target == null or not target.is_inside_tree():
		return
	var sun_position := sun.global_position if sun != null and sun.is_inside_tree() else Vector3.ZERO
	var axis := (target.global_position - sun_position).normalized()
	if axis.length_squared() < 0.5:
		axis = Vector3.FORWARD
	# A little of the travel direction bends the plume so it trails the body
	# instead of sitting perfectly radial.
	var velocity: Variant = target.get("orbital_velocity")
	if velocity is Vector3 and (velocity as Vector3).length() > 0.001:
		axis = (axis - (velocity as Vector3).normalized() * VELOCITY_BEND).normalized()
	var up := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	# The box points +Z downwind, and looking_at aims -Z, hence the negated axis.
	global_transform = Transform3D(Basis.looking_at(-axis, up), target.global_position - axis * _head_offset)
