extends CharacterBody3D

const PlanetBodyScript := preload("res://game/planets/shared/planet_body.gd")
const GravityServiceScript := preload("res://game/celestial/gravity.gd")
const TouchServiceScript := preload("res://game/input/touch.gd")

const WALK_SPEED := 5.5
const SPRINT_MULT := 1.5
const JUMP_SPEED_MIN := 4.0
const JUMP_HOLD_ACCEL := 12.0
const JUMP_HOLD_TIME := 0.28
const JETPACK_ACCEL := 30.0
const JETPACK_BRAKE := 20.0
const JETPACK_DRAG := 1.5
const SWIM_DRAG := 2.0
const WATER_JETPACK_ACCEL := 20.0
const WATER_BUOYANCY := 1.05
const STICK_TO_GROUND_SPEED := 0.5
const PLAYER_HALF_HEIGHT := 0.8
const GROUND_COLLISION_MARGIN := 0.35
const GROUND_SNAP_DISTANCE := 0.5
const GROUND_PROBE_DISTANCE := 0.2
const GROUND_LERP := 10.0
const FLOOR_MAX_ANGLE := 65.0
const MOUSE_SENS := 0.002
const ALIGN_SPEED_GROUND := 10.0
const ALIGN_FADE_ALTITUDE := 1.5
const FREE_LOOK_ROLL_SPEED := 1.8

var up_dir := Vector3.UP
var piloting := false
var frame_source: Node3D = null
var frame_velocity := Vector3.ZERO
var frame_position := Vector3.ZERO
var celestial_system: Node = null
var _fast_time_enabled := false
var _fast_time_on_surface := false
var _stored_velocity := Vector3.ZERO
var _jump_hold_time := -1.0
var _jetpack_armed := true
var _free_look := false

@onready var camera: Camera3D = $Camera3D
@onready var ray: RayCast3D = $Camera3D/RayCast3D
@onready var collider: CollisionShape3D = $CollisionShape3D
@onready var gravity_service: GravityService = get_node("/root/Gravity")
@onready var touch_service: TouchService = get_node("/root/Touch")


func _ready() -> void:
	add_to_group("fast_time_affected")
	add_to_group("origin_shift_listener")
	collision_mask |= 2
	safe_margin = 0.05
	floor_snap_length = GROUND_SNAP_DISTANCE
	floor_max_angle = deg_to_rad(FLOOR_MAX_ANGLE)
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	platform_floor_layers = 0
	platform_wall_layers = 0
	celestial_system = get_tree().get_first_node_in_group("celestial_system")
	if celestial_system != null:
		set_fast_time_enabled(celestial_system.is_fast_forward_enabled())
	if not touch_service.is_touch_ui():
		call_deferred("_capture_mouse_when_focused")


func _capture_mouse_when_focused() -> void:
	var window := get_window()
	if window.has_focus():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		window.focus_entered.connect(_capture_mouse_when_focused, CONNECT_ONE_SHOT)


func _unhandled_input(event: InputEvent) -> void:
	if piloting:
		return
	if event is InputEventMouseButton and event.pressed and not touch_service.is_touch_ui() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("is_mouse_over_ui") and hud.is_mouse_over_ui(event.position):
			get_viewport().set_input_as_handled()
			return
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative)
	elif event.is_action_pressed("interact"):
		_try_interact()
		get_viewport().set_input_as_handled()


# Aligned to a surface the body owns the yaw and the camera the pitch, so the
# horizon stays level. Weightless there is no horizon to keep: the body takes
# both axes plus roll, and the transfers below hand the pitch back and forth
# without the view ever jumping.
func _apply_look(look: Vector2) -> void:
	rotate_object_local(Vector3.UP, -look.x * MOUSE_SENS)
	if _free_look:
		rotate_object_local(Vector3.RIGHT, -look.y * MOUSE_SENS)
		return
	camera.rotate_x(-look.y * MOUSE_SENS)
	camera.rotation.x = clampf(camera.rotation.x, -1.5, 1.5)


func _set_free_look(enabled: bool) -> void:
	if enabled == _free_look:
		return
	_free_look = enabled
	if enabled:
		rotate_object_local(Vector3.RIGHT, camera.rotation.x)
		camera.rotation.x = 0.0
	else:
		var pitch := asin(clampf((-global_basis.z).dot(up_dir), -1.0, 1.0))
		rotate_object_local(Vector3.RIGHT, -pitch)
		camera.rotation.x = clampf(pitch, -1.5, 1.5)


func _try_interact() -> void:
	var target := ray.get_collider()
	if target and target.has_method("interact"):
		target.interact(self)


func _physics_process(delta: float) -> void:
	if piloting:
		return
	if touch_service.look_delta != Vector2.ZERO:
		_apply_look(touch_service.look_delta)
		touch_service.look_delta = Vector2.ZERO
	if _fast_time_enabled and not _fast_time_on_surface:
		velocity = Vector3.ZERO
		frame_source = null
		frame_velocity = Vector3.ZERO
		_update_prompt()
		return
	var gravity := gravity_service.get_gravity(global_position)
	var surface_source := gravity_service.get_nearest_surface(global_position)
	var reference_source := surface_source
	if reference_source == null:
		reference_source = gravity_service.get_strongest(global_position)
	var reference_velocity := Vector3.ZERO
	var relative_gravity := gravity
	if reference_source != null:
		reference_velocity = reference_source.get("orbital_velocity")
		relative_gravity = gravity - gravity_service.get_gravity_at_body(reference_source)
	if surface_source != null and relative_gravity.length_squared() > 0.0001:
		up_dir = -relative_gravity.normalized()
	# Feet are only forced towards the ground near the ground. High above a body,
	# or between two of them, the player keeps whatever orientation they flew in
	# with instead of being snapped the moment they cross an influence sphere.
	var align_rate := 0.0
	if surface_source != null:
		var fade_span := maxf(float(surface_source.get("radius")) * ALIGN_FADE_ALTITUDE, 1.0)
		var altitude_ratio := clampf(_ground_clearance(surface_source) / fade_span, 0.0, 1.0)
		align_rate = ALIGN_SPEED_GROUND * (1.0 - smoothstep(0.15, 1.0, altitude_ratio))
	_set_free_look(align_rate <= 0.0)
	if _free_look:
		var roll := Input.get_axis("roll_right", "roll_left")
		if roll != 0.0:
			rotate_object_local(Vector3.BACK, roll * FREE_LOOK_ROLL_SPEED * delta)
	_align_to_up(delta, align_rate)
	up_direction = up_dir

	var input_2d := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var speed := WALK_SPEED * (SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
	# The jump press is consumed by the jump itself: holding it only stretches the
	# same leap. The jetpack needs a fresh press, so it can never fire on takeoff.
	var jump_pressed := Input.is_action_pressed("jump")
	if not jump_pressed:
		_jetpack_armed = true
		_jump_hold_time = -1.0
	var previous_frame_velocity := reference_velocity
	var frame_offset := Vector3.ZERO
	if reference_source != null and reference_source == frame_source:
		previous_frame_velocity = frame_velocity
		frame_offset = reference_source.global_position - frame_position
	frame_source = reference_source
	frame_velocity = reference_velocity
	if reference_source != null:
		frame_position = reference_source.global_position
	var relative_velocity := velocity - previous_frame_velocity
	var vertical_speed := relative_velocity.dot(up_dir)
	var environment_force := Vector3.ZERO
	if reference_source != null and reference_source.has_method("get_environment_force"):
		environment_force = reference_source.get_environment_force(global_position)
	var environment_lift := environment_force.dot(up_dir)
	var grounded := is_on_floor()
	if not grounded and surface_source != null and vertical_speed <= JUMP_SPEED_MIN * 0.5:
		grounded = _ground_clearance(surface_source) <= GROUND_PROBE_DISTANCE
	# An updraft stronger than gravity rips the player off the ground: the walk lerp and the floor
	# snap would otherwise eat the whole lift and the tornado would only feel like a wall.
	if environment_lift > relative_gravity.length():
		grounded = false
	var water_depth := -INF
	if reference_source != null and reference_source.has_method("get_water_depth"):
		water_depth = reference_source.get_water_depth(global_position)
	var swimming := water_depth > 0.2
	var movement_basis := global_basis if grounded and not swimming else camera.global_basis
	var wish_dir := movement_basis * Vector3(input_2d.x, 0.0, input_2d.y)
	if swimming:
		var swim_target := wish_dir.limit_length(1.0) * WALK_SPEED
		relative_velocity = relative_velocity.lerp(swim_target, 1.0 - exp(-SWIM_DRAG * delta))
		relative_velocity += up_dir * Input.get_axis("sprint", "jump") * WATER_JETPACK_ACCEL * delta
		var submerged := clampf((water_depth + PLAYER_HALF_HEIGHT) / (PLAYER_HALF_HEIGHT * 2.0), 0.0, 1.0)
		relative_gravity *= 1.0 - submerged * WATER_BUOYANCY
	elif grounded:
		var v_vert := up_dir * relative_velocity.dot(up_dir)
		var v_horiz := relative_velocity - v_vert
		v_horiz = v_horiz.lerp(wish_dir * speed, clampf(GROUND_LERP * delta, 0.0, 1.0))
		if Input.is_action_just_pressed("jump"):
			v_vert += up_dir * JUMP_SPEED_MIN
			_jump_hold_time = 0.0
			_jetpack_armed = false
		else:
			v_vert -= up_dir * STICK_TO_GROUND_SPEED
		relative_velocity = v_horiz + v_vert
	else:
		# Vacuum keeps momentum: only an atmosphere drags, and only as thick as it
		# actually is. Killing speed is the brake's job, not a hidden drag term.
		var air_density := _atmosphere_density(surface_source)
		if air_density > 0.0:
			relative_velocity *= exp(-JETPACK_DRAG * air_density * delta)
		var thrust_up := global_basis.y if _free_look else up_dir
		if not _free_look:
			wish_dir -= thrust_up * wish_dir.dot(thrust_up)
		var jetpack_up := 0.0
		if _jetpack_armed and jump_pressed:
			jetpack_up += 1.0
		if Input.is_action_pressed("sprint"):
			jetpack_up -= 1.0
		relative_velocity += (wish_dir.limit_length(1.0) + thrust_up * jetpack_up) * JETPACK_ACCEL * delta
		if _jump_hold_time >= 0.0 and jump_pressed and _jump_hold_time < JUMP_HOLD_TIME and relative_velocity.dot(up_dir) > 0.0:
			relative_velocity += up_dir * JUMP_HOLD_ACCEL * delta
			_jump_hold_time += delta
		else:
			_jump_hold_time = -1.0
		if Input.is_action_pressed("brake"):
			relative_velocity = relative_velocity.move_toward(Vector3.ZERO, JETPACK_BRAKE * delta)
	relative_velocity += environment_force * delta

	# CharacterBody3D judges floor snap, slope and collision sweeps against
	# `velocity` in world space, and Terra alone orbits at 32 u/s. Feeding the
	# frame velocity in there made the jump die on the pole facing the travel
	# direction and overshoot on the opposite one. Ride the body with an exact
	# position offset instead, and move only the relative velocity.
	global_position += frame_offset
	velocity = relative_velocity + relative_gravity * delta
	move_and_slide()
	# Snap only keeps contact while walking on a moving body: never let it catch
	# a fall, or the last centimeters feel magnetic.
	if grounded and not swimming and environment_lift <= 0.0 and absf(vertical_speed) < STICK_TO_GROUND_SPEED * 2.0 and not Input.is_action_just_pressed("jump"):
		apply_floor_snap()
	velocity += reference_velocity
	_update_prompt()


func apply_origin_shift(offset: Vector3) -> void:
	frame_position += offset


func set_fast_time_enabled(enabled: bool) -> void:
	if enabled == _fast_time_enabled:
		return
	_fast_time_enabled = enabled
	if enabled:
		_stored_velocity = velocity
		var surface_source := gravity_service.get_nearest_surface(global_position)
		_fast_time_on_surface = surface_source != null and _ground_clearance(surface_source) <= GROUND_PROBE_DISTANCE
		if _fast_time_on_surface:
			frame_source = surface_source
			frame_velocity = surface_source.get("orbital_velocity")
			frame_position = surface_source.global_position
		else:
			velocity = Vector3.ZERO
			frame_source = null
			frame_velocity = Vector3.ZERO
	else:
		if not _fast_time_on_surface:
			velocity = _stored_velocity
		_fast_time_on_surface = false


func _align_to_up(delta: float, rate: float) -> void:
	if rate <= 0.0 or global_basis.y.angle_to(up_dir) < 0.001:
		return
	# Project the current facing onto the tangent plane. Looking straight along
	# `up_dir` that projection vanishes, so fall back on the old up axis: nose
	# down, the body keeps turning instead of stalling until the view drifts.
	var back := global_basis.z - up_dir * up_dir.dot(global_basis.z)
	if back.length_squared() < 0.0001:
		back = global_basis.y - up_dir * up_dir.dot(global_basis.y)
	if back.length_squared() < 0.0001:
		back = global_basis.x - up_dir * up_dir.dot(global_basis.x)
	back = back.normalized()
	var target := Basis(up_dir.cross(back), up_dir, back).orthonormalized()
	global_basis = global_basis.slerp(target, clampf(rate * delta, 0.0, 1.0)).orthonormalized()


func _atmosphere_density(source: Node3D) -> float:
	if source == null or not bool(source.get("has_atmosphere")):
		return 0.0
	var thickness := float(source.get("radius")) * float(source.get("atmosphere_scale"))
	if thickness <= 0.0:
		return 0.0
	return clampf(1.0 - _ground_clearance(source) / thickness, 0.0, 1.0)


func set_piloting(value: bool) -> void:
	piloting = value
	visible = not value
	collider.disabled = value
	camera.current = not value
	velocity = Vector3.ZERO
	frame_source = null
	_jump_hold_time = -1.0
	_jetpack_armed = true
	_free_look = false
	if not value:
		_update_prompt()


func reset(t: Transform3D, inherited_velocity := Vector3.ZERO) -> void:
	global_transform = t
	velocity = inherited_velocity
	frame_source = null
	camera.rotation = Vector3.ZERO
	_jump_hold_time = -1.0
	_jetpack_armed = true
	_free_look = false
	var gravity: Vector3 = gravity_service.get_gravity(global_position)
	if gravity.length_squared() > 0.0001:
		up_dir = -gravity.normalized()


func ensure_surface_clearance(clearance := GROUND_COLLISION_MARGIN) -> void:
	var source := gravity_service.get_nearest_surface(global_position)
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
