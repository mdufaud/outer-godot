extends CharacterBody3D

const WALK_SPEED := 7.0
const SPRINT_MULT := 1.8
const JUMP_SPEED := 9.0
const JETPACK_ACCEL := 14.0
const GROUND_LERP := 10.0
const AIR_LERP := 2.0
const MOUSE_SENS := 0.002
const ALIGN_SPEED := 8.0

var up_dir := Vector3.UP
var piloting := false

@onready var camera: Camera3D = $Camera3D
@onready var ray: RayCast3D = $Camera3D/RayCast3D
@onready var collider: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if piloting:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_object_local(Vector3.UP, -event.relative.x * MOUSE_SENS)
		camera.rotate_x(-event.relative.y * MOUSE_SENS)
		camera.rotation.x = clampf(camera.rotation.x, -1.5, 1.5)
	elif event.is_action_pressed("interact"):
		var target := ray.get_collider()
		if target and target.has_method("interact"):
			target.interact(self)
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if piloting:
		return
	var gravity: Vector3 = Gravity.get_gravity(global_position)
	if gravity.length_squared() > 0.0001:
		up_dir = -gravity.normalized()
	_align_to_up(delta)
	up_direction = up_dir

	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := global_basis * Vector3(input_2d.x, 0.0, input_2d.y)
	var speed := WALK_SPEED * (SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)

	var v_vert := up_dir * velocity.dot(up_dir)
	var v_horiz := velocity - v_vert
	if is_on_floor():
		v_horiz = v_horiz.lerp(wish_dir * speed, clampf(GROUND_LERP * delta, 0.0, 1.0))
		if Input.is_action_just_pressed("jump"):
			v_vert += up_dir * JUMP_SPEED
	else:
		v_horiz = v_horiz.lerp(wish_dir * speed, clampf(AIR_LERP * delta, 0.0, 1.0))
		if Input.is_action_pressed("jump"):
			v_vert += up_dir * JETPACK_ACCEL * delta

	velocity = v_horiz + v_vert + gravity * delta
	move_and_slide()
	_update_prompt()


func _align_to_up(delta: float) -> void:
	if global_basis.y.angle_to(up_dir) < 0.001:
		return
	var target := global_basis
	target.y = up_dir
	target.x = -global_basis.z.cross(up_dir)
	if target.x.length_squared() < 0.0001:
		target.x = global_basis.x
	target = target.orthonormalized()
	global_basis = global_basis.slerp(target, clampf(ALIGN_SPEED * delta, 0.0, 1.0)).orthonormalized()


func set_piloting(value: bool) -> void:
	piloting = value
	visible = not value
	collider.disabled = value
	camera.current = not value
	velocity = Vector3.ZERO
	if not value:
		_update_prompt()


func reset(t: Transform3D) -> void:
	global_transform = t
	velocity = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	var gravity: Vector3 = Gravity.get_gravity(global_position)
	if gravity.length_squared() > 0.0001:
		up_dir = -gravity.normalized()


func _update_prompt() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var target := ray.get_collider()
	if not piloting and target and target.has_method("interact"):
		hud.set_prompt(target.prompt_text)
	else:
		hud.set_prompt("")
