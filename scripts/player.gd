extends CharacterBody3D

const WALK_SPEED := 7.0
const SPRINT_MULT := 1.8
const JUMP_SPEED := 6.36 # half jump height (v/sqrt(2))
const JETPACK_ACCEL := 40.0
const JETPACK_BRAKE := 20.0
const JETPACK_DRAG := 1.5
const SWIM_ACCEL := 10.0
const SWIM_DRAG := 3.0
const PLAYER_HALF_HEIGHT := 0.8
const GROUND_COLLISION_MARGIN := 0.35
const GROUND_SNAP_DISTANCE := 0.5
const GROUND_LERP := 10.0
const FLOOR_MAX_ANGLE := 65.0
const MOUSE_SENS := 0.002
const ALIGN_SPEED := 8.0

var up_dir := Vector3.UP
var piloting := false
var frame_source: Node3D = null
var frame_velocity := Vector3.ZERO

@onready var camera: Camera3D = $Camera3D
@onready var ray: RayCast3D = $Camera3D/RayCast3D
@onready var collider: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	collision_mask |= 2
	safe_margin = 0.05
	floor_snap_length = GROUND_SNAP_DISTANCE
	floor_max_angle = deg_to_rad(FLOOR_MAX_ANGLE)
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	platform_floor_layers = 0
	platform_wall_layers = 0
	if not Touch.is_touch_ui():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if piloting:
		return
	if event is InputEventMouseButton and event.pressed and not Touch.is_touch_ui() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_object_local(Vector3.UP, -event.relative.x * MOUSE_SENS)
		camera.rotate_x(-event.relative.y * MOUSE_SENS)
		camera.rotation.x = clampf(camera.rotation.x, -1.5, 1.5)
	elif event.is_action_pressed("interact"):
		_try_interact()
		get_viewport().set_input_as_handled()


func _try_interact() -> void:
	var target := ray.get_collider()
	if target and target.has_method("interact"):
		target.interact(self)


func _physics_process(delta: float) -> void:
	if piloting:
		return
	if Touch.look_delta != Vector2.ZERO:
		rotate_object_local(Vector3.UP, -Touch.look_delta.x * MOUSE_SENS)
		camera.rotate_x(-Touch.look_delta.y * MOUSE_SENS)
		camera.rotation.x = clampf(camera.rotation.x, -1.5, 1.5)
		Touch.look_delta = Vector2.ZERO
	var gravity: Vector3 = Gravity.get_gravity(global_position)
	var reference_source := Gravity.get_nearest_surface(global_position)
	if reference_source == null:
		reference_source = Gravity.get_strongest(global_position)
	var reference_velocity := Vector3.ZERO
	var relative_gravity := gravity
	if reference_source != null:
		reference_velocity = reference_source.get("orbital_velocity")
		relative_gravity = Gravity.get_relative_gravity(global_position, reference_source)
	if relative_gravity.length_squared() > 0.0001:
		up_dir = -relative_gravity.normalized()
	_align_to_up(delta)
	up_direction = up_dir

	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var speed := WALK_SPEED * (SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
	var previous_frame_velocity := reference_velocity
	if reference_source == frame_source:
		previous_frame_velocity = frame_velocity
	frame_source = reference_source
	frame_velocity = reference_velocity
	var relative_velocity := velocity - previous_frame_velocity
	var grounded := is_on_floor()
	var water_depth := -INF
	if reference_source != null and reference_source.has_method("get_water_depth"):
		water_depth = reference_source.get_water_depth(global_position)
	var swimming := water_depth > 0.2
	var movement_basis := global_basis if grounded and not swimming else camera.global_basis
	var wish_dir := movement_basis * Vector3(input_2d.x, 0.0, input_2d.y)

	if swimming:
		var swim_dir := wish_dir + up_dir * Input.get_axis("sprint", "jump")
		relative_velocity *= exp(-SWIM_DRAG * delta)
		relative_velocity += swim_dir.limit_length(1.0) * SWIM_ACCEL * delta
		var submerged := clampf((water_depth + PLAYER_HALF_HEIGHT) / (PLAYER_HALF_HEIGHT * 2.0), 0.0, 1.0)
		relative_gravity *= 1.0 - submerged
	elif grounded:
		var v_vert := up_dir * maxf(relative_velocity.dot(up_dir), 0.0)
		var v_horiz := relative_velocity - v_vert
		v_horiz = v_horiz.lerp(wish_dir * speed, clampf(GROUND_LERP * delta, 0.0, 1.0))
		if Input.is_action_just_pressed("jump"):
			v_vert += up_dir * JUMP_SPEED
		relative_velocity = v_horiz + v_vert
	else:
		relative_velocity *= exp(-JETPACK_DRAG * delta)
		relative_velocity += wish_dir * JETPACK_ACCEL * delta
		relative_velocity += up_dir * Input.get_axis("sprint", "jump") * JETPACK_ACCEL * delta
		if Input.is_action_pressed("brake"):
			relative_velocity = relative_velocity.move_toward(Vector3.ZERO, JETPACK_BRAKE * delta)

	var target_velocity := relative_velocity + reference_velocity + relative_gravity * delta
	velocity = target_velocity
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
	frame_source = null
	if not value:
		_update_prompt()


func reset(t: Transform3D, inherited_velocity := Vector3.ZERO) -> void:
	global_transform = t
	velocity = inherited_velocity
	frame_source = null
	camera.rotation = Vector3.ZERO
	var gravity: Vector3 = Gravity.get_gravity(global_position)
	if gravity.length_squared() > 0.0001:
		up_dir = -gravity.normalized()


func ensure_surface_clearance(clearance := GROUND_COLLISION_MARGIN) -> void:
	var source := Gravity.get_nearest_surface(global_position)
	if source != null and _ground_clearance(source) < clearance:
		_place_above_surface(source, clearance)


func _surface_radius(source: Node3D, direction: Vector3) -> float:
	if source.has_method("get_collider_surface_radius"):
		return source.get_collider_surface_radius(direction)
	return source.get_surface_radius_towards(direction)


func _ground_clearance(source: Node3D) -> float:
	if source == null or not source.has_method("get_surface_radius_towards"):
		return INF
	var direction := global_position - source.global_position
	if direction.length_squared() < 0.0001:
		return INF
	return direction.length() - _surface_radius(source, direction.normalized()) - PLAYER_HALF_HEIGHT


func _place_above_surface(source: Node3D, clearance := GROUND_COLLISION_MARGIN) -> void:
	if source == null or not source.has_method("get_surface_radius_towards"):
		return
	var direction := global_position - source.global_position
	if direction.length_squared() < 0.0001:
		return
	var unit_direction := direction.normalized()
	var surface_radius := _surface_radius(source, unit_direction)
	global_position = source.global_position + unit_direction * (surface_radius + PLAYER_HALF_HEIGHT + clearance)


func _update_prompt() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var target := ray.get_collider()
	if not piloting and target and target.has_method("interact"):
		hud.set_prompt(target.prompt_text)
	else:
		hud.set_prompt("")
