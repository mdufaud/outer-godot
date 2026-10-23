class_name Ship
extends RigidBody3D

const SeatScript := preload("res://game/ship/seat.gd")
const THRUST_ACCEL := 40.0
const BOOST_MULT := 5.0
const BRAKE_ACCEL := 45.0
const BRAKE_SPEED_GAIN := 1.5
const ASSIST_GAIN := 4.0
const ASSIST_SPEED := 20.0
const LANDING_SPEED := 3.0
const LANDING_SLOWDOWN := 0.4
const LEVEL_ALTITUDE := 40.0
const LEVEL_RATE := 1.5
const PITCH_YAW_RATE := 2.2
const ROLL_RATE := 2.5
const RATE_RESPONSE := 8.0
const MAX_ANGULAR_ACCEL := 10.0
const MOUSE_SENS := 0.0025
const IDLE_ANGULAR_DAMP := 3.0
const AUTOPILOT_SPEED := 450.0
const AUTOPILOT_ACCEL := 120.0
const AUTOPILOT_DECEL := 40.0
const AUTOPILOT_GAIN := 4.0
const AUTOPILOT_TURN_RATE := 2.0
const AUTOPILOT_ARRIVAL_SPEED := 1.5
const AUTOPILOT_ARRIVAL_SLACK := 5.0
const AUTOPILOT_MIN_ALTITUDE := 40.0
const OBSTACLE_CLEARANCE := 1.6
const LEG_TOP_Y := -1.0
const LEG_SPLAY := 1.5
const LEG_DEPTH := 2.6
const HULL_RADIUS := 2.3
const HULL_CENTER := Vector3(0.0, 0.6, 0.0)
const FEET: Array[Vector3] = [Vector3(-2.55, -2.6, -1.95), Vector3(-2.55, -2.6, 1.95), Vector3(2.55, -2.6, -1.95), Vector3(2.55, -2.6, 1.95)]
const WATER_HALF_HEIGHT := 2.7
const WATER_BUOYANCY := 1.15
const WATER_LINEAR_DRAG := 2.0
const WATER_ANGULAR_DRAG := 1.5
const HARD_LANDING_SPEED := 6.0
const CCD_SPEED := 15.0
# Quaternius "Spaceship_BarbaraTheBee" (Ultimate Space Kit, CC0). Model faces +Z,
# rotated PI so the glass dome looks down ship -Z (Godot forward). Hull is
# single-sided: from the pilot camera inside, backfaces cull away and the view
# through the dome is unobstructed.
const MODEL_SCENE := preload("res://assets/models/spaceship_pod.glb")

var pilot: Player = null
var cockpit_cam: Camera3D
var chase_cam: Camera3D
var exit_pos := Vector3(3.0, -1.6, 0.0)
var autopilot_target: CelestialBody = null
var assist_active := false
var boosting := false

var dark_mat: StandardMaterial3D
var _thrusters: Array[GPUParticles3D] = []
var _hatch_pivot: Node3D
var _hatch_target := -1.15
var _chase_view := false
var _mouse_delta := Vector2.ZERO
var _look_rate := Vector2.ZERO
var _had_ground_contact := false
var _frame_body: CelestialBody = null
var _frame_velocity := Vector3.ZERO
var _fast_time_enabled := false
var _follow_body: CelestialBody = null
var _follow_offset := Vector3.ZERO
var _stored_linear_velocity := Vector3.ZERO
var _stored_angular_velocity := Vector3.ZERO
@onready var gravity_service: GravityService = get_node("/root/Gravity")
@onready var touch_service: TouchService = get_node("/root/Touch")


func _ready() -> void:
	add_to_group("fast_time_affected")
	collision_mask |= 2
	mass = 8.0
	# Project damping brakes against absolute space, i.e. against the 32 m/s orbit.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = IDLE_ANGULAR_DAMP
	linear_damp = 0.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 6
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.8, 0)

	dark_mat = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.22, 0.22, 0.25)
	dark_mat.roughness = 0.8

	var model: Node3D = MODEL_SCENE.instantiate()
	model.rotation.y = PI
	add_child(model)

	# body collision: one sphere around the pod core (wings/antennae stay ghost)
	var body_col := CollisionShape3D.new()
	var body_shape := SphereShape3D.new()
	body_shape.radius = HULL_RADIUS
	body_col.shape = body_shape
	body_col.position = HULL_CENTER
	add_child(body_col)

	for foot in FEET:
		_leg(foot)

	_build_cockpit()
	_build_thrusters()

	cockpit_cam = Camera3D.new()
	cockpit_cam.position = Vector3(0, 1.0, -1.4)
	cockpit_cam.far = 8000.0
	add_child(cockpit_cam)
	var chase_arm := SpringArm3D.new()
	chase_arm.position = Vector3(0.0, 2.5, 0.0)
	chase_arm.rotation.x = deg_to_rad(-12.0)
	chase_arm.spring_length = 16.0
	chase_arm.margin = 0.5
	chase_arm.collision_mask = 2
	add_child(chase_arm)
	chase_cam = Camera3D.new()
	chase_cam.far = 8000.0
	chase_arm.add_child(chase_cam)
	var celestial_system := get_tree().get_first_node_in_group("celestial_system") as CelestialSystem
	if celestial_system != null:
		set_fast_time_enabled(celestial_system.is_fast_forward_enabled())


func _process(delta: float) -> void:
	if _hatch_pivot != null:
		_hatch_pivot.rotation.z = lerp_angle(_hatch_pivot.rotation.z, _hatch_target, clampf(delta * 4.5, 0.0, 1.0))
	if pilot == null:
		return
	# Mouse motion lands once per rendered frame but forces run at 120 Hz: turn it
	# into a rate here so every physics tick of the frame steers the same.
	var look := _mouse_delta + touch_service.look_delta
	_mouse_delta = Vector2.ZERO
	touch_service.look_delta = Vector2.ZERO
	_look_rate = look * MOUSE_SENS / maxf(delta, 0.001)


func _physics_process(delta: float) -> void:
	# The planet node still holds last tick's position here; its collider already
	# moved by one step of orbital velocity.
	if _follow_body != null and is_instance_valid(_follow_body):
		global_position = _follow_body.global_position + _follow_body.orbital_velocity * delta + _follow_offset
	# CCD sweeps in absolute space: on a planet orbiting at 40 m/s it drags a
	# landed ship across the ground. Sweep only when flying fast over the planet.
	var frame_velocity := _frame_body.orbital_velocity if is_instance_valid(_frame_body) else Vector3.ZERO
	var fast := (linear_velocity - frame_velocity).length() > CCD_SPEED
	if continuous_cd != fast:
		continuous_cd = fast


func _build_cockpit() -> void:
	# dashboard sits low under the dome so it eats only the bottom sliver of view
	_box(Vector3(1.6, 0.35, 0.5), Vector3(0, 0.1, -1.7))
	_box(Vector3(0.8, 0.5, 0.8), Vector3(0, -0.4, -0.9))          # seat base
	_box(Vector3(0.8, 0.9, 0.2), Vector3(0, 0.2, -0.45))          # seat back

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 1.6, -1.0)
	lamp.omni_range = 4.0
	lamp.light_energy = 1.5
	add_child(lamp)

	# boarding hatch zone at the nose, reachable from the ground
	var seat := Area3D.new()
	seat.set_script(SeatScript)
	var seat_col := CollisionShape3D.new()
	var seat_shape := BoxShape3D.new()
	seat_shape.size = Vector3(2.5, 2.5, 1.5)
	seat_col.shape = seat_shape
	seat.add_child(seat_col)
	seat.position = Vector3(0, -1.0, -2.0)
	add_child(seat)
	seat.ship = self
	_hatch_pivot = Node3D.new()
	_hatch_pivot.position = Vector3(1.55, 0.75, -0.55)
	add_child(_hatch_pivot)
	var hatch := MeshInstance3D.new()
	var hatch_mesh := BoxMesh.new()
	hatch_mesh.size = Vector3(0.12, 1.35, 1.55)
	hatch_mesh.material = dark_mat
	hatch.mesh = hatch_mesh
	hatch.position = Vector3(0.0, 0.62, 0.0)
	_hatch_pivot.add_child(hatch)


func _build_thrusters() -> void:
	for x in [-0.72, 0.72]:
		var particles := GPUParticles3D.new()
		particles.amount = 28
		particles.lifetime = 0.38
		particles.randomness = 0.45
		particles.position = Vector3(x, 0.15, 1.65)
		var process_material := ParticleProcessMaterial.new()
		process_material.direction = Vector3(0.0, 0.0, 1.0)
		process_material.spread = 8.0
		process_material.initial_velocity_min = 3.5
		process_material.initial_velocity_max = 7.0
		process_material.gravity = Vector3.ZERO
		process_material.scale_min = 0.12
		process_material.scale_max = 0.28
		process_material.color = Color(0.25, 0.75, 1.0, 0.85)
		particles.process_material = process_material
		var quad := QuadMesh.new()
		quad.size = Vector2(0.32, 0.32)
		var flame_material := StandardMaterial3D.new()
		flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame_material.albedo_color = Color(0.18, 0.62, 1.0, 0.8)
		flame_material.emission_enabled = true
		flame_material.emission = Color(0.08, 0.42, 1.0)
		flame_material.emission_energy_multiplier = 4.0
		quad.material = flame_material
		particles.draw_pass_1 = quad
		particles.emitting = false
		add_child(particles)
		_thrusters.append(particles)


func _box(size: Vector3, pos: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = dark_mat
	mesh.mesh = box
	mesh.position = pos
	add_child(mesh)


func _leg(foot: Vector3) -> void:
	# Outer Wilds style: legs splay outward from the belly to the ground
	var top := Vector3(foot.x / LEG_SPLAY, LEG_TOP_Y, foot.z / LEG_SPLAY)
	var mid := (top + foot) * 0.5
	var axis := foot - top
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.14
	cyl.height = axis.length()
	cyl.material = dark_mat
	mesh.mesh = cyl
	mesh.position = mid
	# cylinder Y axis -> leg direction
	var y := axis.normalized()
	var x := y.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < 0.5:
		x = y.cross(Vector3.RIGHT).normalized()
	mesh.basis = Basis(x, y, x.cross(y)).orthonormalized()
	add_child(mesh)

	var pad := MeshInstance3D.new()
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 0.3
	pad_mesh.bottom_radius = 0.35
	pad_mesh.height = 0.15
	pad_mesh.material = dark_mat
	pad.mesh = pad_mesh
	pad.position = foot + Vector3(0, 0.07, 0)
	add_child(pad)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.14
	shape.height = axis.length()
	col.shape = shape
	col.position = mid
	col.basis = mesh.basis
	add_child(col)
	var pad_col := CollisionShape3D.new()
	var pad_shape := CylinderShape3D.new()
	pad_shape.radius = 0.35
	pad_shape.height = 0.15
	pad_col.shape = pad_shape
	pad_col.position = pad.position
	add_child(pad_col)


func _unhandled_input(event: InputEvent) -> void:
	if pilot == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += event.relative
	elif event.is_action_pressed("interact"):
		exit_pilot()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ship_command"):
		toggle_autopilot()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ship_camera"):
		toggle_camera()
		get_viewport().set_input_as_handled()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# GravityService does not pull planets the way the orbit integrator does (the
	# sun's influence ends before Terra), so ride the reference body's real
	# acceleration plus the pull relative to its centre, like the player.
	var gravity := gravity_service.get_gravity(global_position)
	var reference := gravity_service.get_reference_body(global_position)
	var relative_gravity := gravity
	var frame_acceleration := Vector3.ZERO
	if reference != null:
		relative_gravity = gravity - gravity_service.get_gravity_at_body(reference)
		frame_acceleration = gravity_service.get_gravity_at_body(reference)
		if reference == _frame_body:
			frame_acceleration = (reference.orbital_velocity - _frame_velocity) / state.step
		_frame_velocity = reference.orbital_velocity
	_frame_body = reference
	state.apply_central_force((relative_gravity + frame_acceleration) * mass)

	var surface := gravity_service.get_nearest_surface(global_position)
	if surface != null:
		var water_depth := surface.get_water_depth(global_position)
		var submerged := clampf((water_depth + WATER_HALF_HEIGHT) / (WATER_HALF_HEIGHT * 2.0), 0.0, 1.0)
		if submerged > 0.0:
			state.apply_central_force(-relative_gravity * mass * submerged * WATER_BUOYANCY)
			state.apply_central_force(-(state.linear_velocity - surface.orbital_velocity) * mass * WATER_LINEAR_DRAG * submerged)
			state.apply_torque(-state.angular_velocity * mass * WATER_ANGULAR_DRAG * submerged)
	var ground_contact := state.get_contact_count() > 0 and surface != null
	if ground_contact and not _had_ground_contact:
		var local_up := (global_position - surface.global_position).normalized()
		var impact_speed := absf((state.linear_velocity - surface.orbital_velocity).dot(local_up))
		if impact_speed >= HARD_LANDING_SPEED:
			var main := get_tree().current_scene as Main
			if main != null:
				main.trigger_camera_shake(clampf(impact_speed * 0.006, 0.035, 0.10), 0.42)
	_had_ground_contact = ground_contact
	if pilot == null:
		assist_active = false
		boosting = false
		_set_thrusters(false)
		return

	var thrust := Vector3(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("descend", "jump"),
		Input.get_axis("move_forward", "move_back")
	).limit_length(1.0)
	var braking := Input.is_action_pressed("brake")
	var roll := Input.get_axis("roll_right", "roll_left")
	boosting = Input.is_action_pressed("sprint")
	var power := BOOST_MULT if boosting else 1.0
	var basis := state.transform.basis

	if autopilot_target != null and (not is_instance_valid(autopilot_target) or thrust != Vector3.ZERO or braking or roll != 0.0):
		_stop_autopilot("Autopilot off")
	if autopilot_target != null:
		assist_active = false
		boosting = false
		_fly_autopilot(state, gravity)
		_set_thrusters(true)
		return

	# Assist: sideways and vertical drift relative to the planet is killed and the
	# ship hovers; forward momentum coasts unless it is a slow creep. Out in deep
	# space it is plain Newton.
	assist_active = surface != null
	var acceleration := basis * thrust * THRUST_ACCEL * power
	if assist_active:
		if not braking:
			var local_velocity := basis.inverse() * (state.linear_velocity - surface.orbital_velocity)
			var vertical_speed := ASSIST_SPEED * power
			if thrust.y < 0.0:
				vertical_speed = minf(vertical_speed, maxf(LANDING_SPEED, _altitude_above(surface) * LANDING_SLOWDOWN))
			var correction := (Vector2(thrust.x * ASSIST_SPEED * power - local_velocity.x, thrust.y * vertical_speed - local_velocity.y) * ASSIST_GAIN).limit_length(THRUST_ACCEL * power)
			var forward := thrust.z * THRUST_ACCEL * power
			if thrust.z == 0.0 and absf(local_velocity.z) < ASSIST_SPEED:
				forward = clampf(-local_velocity.z * ASSIST_GAIN, -THRUST_ACCEL, THRUST_ACCEL)
			acceleration = basis * Vector3(correction.x, correction.y, forward)
		if not ground_contact:
			acceleration -= relative_gravity
	if braking:
		var match_body := _match_body(reference)
		var relative_velocity := state.linear_velocity - (match_body.orbital_velocity if match_body != null else Vector3.ZERO)
		var brake := maxf(BRAKE_ACCEL * power, relative_velocity.length() * BRAKE_SPEED_GAIN)
		if relative_velocity.length() <= brake * state.step:
			acceleration -= relative_velocity / state.step
		else:
			acceleration -= relative_velocity.normalized() * brake
	state.apply_central_force(acceleration * mass)
	_set_thrusters(thrust.length_squared() > 0.01 or braking)

	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	var rate := Vector3(
		clampf(-_look_rate.y - stick.y * PITCH_YAW_RATE, -PITCH_YAW_RATE, PITCH_YAW_RATE),
		clampf(-_look_rate.x - stick.x * PITCH_YAW_RATE, -PITCH_YAW_RATE, PITCH_YAW_RATE),
		roll * ROLL_RATE
	)
	var target_rate := basis * rate
	if assist_active and rate.x == 0.0 and rate.z == 0.0 and _altitude_above(surface) < LEVEL_ALTITUDE:
		target_rate += basis.y.cross((global_position - surface.global_position).normalized()) * LEVEL_RATE
	if rate != Vector3.ZERO or not ground_contact:
		_steer(state, target_rate)


func _steer(state: PhysicsDirectBodyState3D, target_rate: Vector3) -> void:
	var correction := ((target_rate - state.angular_velocity) * RATE_RESPONSE).limit_length(MAX_ANGULAR_ACCEL)
	state.apply_torque(state.inverse_inertia_tensor.inverse() * correction)


func _fly_autopilot(state: PhysicsDirectBodyState3D, gravity: Vector3) -> void:
	var target := autopilot_target
	var relative_velocity := state.linear_velocity - target.orbital_velocity
	var arrival := _arrival_radius(target)
	if global_position.distance_to(target.global_position) - arrival < AUTOPILOT_ARRIVAL_SLACK and relative_velocity.length() < AUTOPILOT_ARRIVAL_SPEED:
		_stop_autopilot("Arrived at %s" % target.name)
		return
	var remaining := global_position.distance_to(target.global_position) - arrival
	var desired := (_autopilot_aim(target) - global_position).normalized() * autopilot_speed(remaining)
	var correction := ((desired - relative_velocity) * AUTOPILOT_GAIN).limit_length(AUTOPILOT_ACCEL)
	var target_pull := gravity - gravity_service.get_gravity_at_body(target)
	state.apply_central_force((correction - target_pull) * mass)
	var heading := desired if desired.length_squared() > 1.0 else target.global_position - global_position
	var nose := -state.transform.basis.z
	_steer(state, (nose.cross(heading.normalized()) * AUTOPILOT_TURN_RATE).limit_length(PITCH_YAW_RATE))


# Straight at the target unless a body sits on the way: then round the nearest one.
func _autopilot_aim(target: CelestialBody) -> Vector3:
	var aim := target.global_position
	var nearest := INF
	for node in get_tree().get_nodes_in_group("celestial_body"):
		var body := node as CelestialBody
		if body == null or body == target:
			continue
		var closest := closest_on_segment(global_position, target.global_position, body.global_position)
		var offset := closest - body.global_position
		var clearance := body.get_surface_radius_towards(offset) * OBSTACLE_CLEARANCE
		if offset.length() >= clearance or global_position.distance_to(closest) >= nearest:
			continue
		nearest = global_position.distance_to(closest)
		if offset.length_squared() < 0.0001:
			offset = (target.global_position - global_position).cross(Vector3.UP)
		aim = body.global_position + offset.normalized() * clearance * 1.2
	return aim


# Fast as allowed, yet slow enough to stop on the arrival shell.
static func autopilot_speed(remaining: float) -> float:
	if remaining <= 0.0:
		return 0.0
	return minf(AUTOPILOT_SPEED, sqrt(2.0 * AUTOPILOT_DECEL * remaining))


static func closest_on_segment(from: Vector3, to: Vector3, point: Vector3) -> Vector3:
	var path := to - from
	return from + path * clampf((point - from).dot(path) / maxf(path.length_squared(), 0.0001), 0.0, 1.0)


func toggle_autopilot() -> void:
	if autopilot_target != null:
		_stop_autopilot("Autopilot off")
		return
	var hud := _hud()
	var target := hud.get_target_body() if hud != null else null
	var sun := get_tree().get_first_node_in_group("sun") as Sun
	if target == null or target == sun:
		_flash("Aim at a planet first")
		return
	if global_position.distance_to(target.global_position) <= _arrival_radius(target):
		_flash("Already at %s" % target.name)
		return
	autopilot_target = target
	_flash("Autopilot to %s" % target.name)


func _stop_autopilot(message: String) -> void:
	autopilot_target = null
	_flash(message)


func toggle_camera() -> void:
	_chase_view = not _chase_view
	if pilot != null:
		(chase_cam if _chase_view else cockpit_cam).current = true


func _arrival_radius(target: CelestialBody) -> float:
	return target.get_surface_radius_towards(global_position - target.global_position) + maxf(AUTOPILOT_MIN_ALTITUDE, target.radius * 0.8)


func _altitude_above(surface: PlanetBody) -> float:
	var offset := global_position - surface.global_position
	return offset.length() - surface.get_surface_radius_towards(offset) - LEG_DEPTH


func _match_body(reference: CelestialBody) -> CelestialBody:
	var hud := _hud()
	if hud != null and is_instance_valid(hud.locked_body):
		return hud.locked_body
	return reference


func _hud() -> Hud:
	return get_tree().get_first_node_in_group("hud") as Hud


func _flash(message: String) -> void:
	var hud := _hud()
	if hud != null:
		hud.flash(message)


func set_fast_time_enabled(enabled: bool) -> void:
	if enabled == _fast_time_enabled:
		return
	_fast_time_enabled = enabled
	if enabled:
		# A landed ship rides its planet through fast time; anything else waits in place.
		_follow_body = gravity_service.get_nearest_surface(global_position) if _had_ground_contact else null
		var base_velocity := _follow_body.orbital_velocity if _follow_body != null else Vector3.ZERO
		if _follow_body != null:
			_follow_offset = global_position - _follow_body.global_position
		_stored_linear_velocity = linear_velocity - base_velocity
		_stored_angular_velocity = angular_velocity
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze = true
		_set_thrusters(false)
	else:
		freeze = false
		var base_velocity := _follow_body.orbital_velocity if is_instance_valid(_follow_body) else Vector3.ZERO
		linear_velocity = base_velocity + _stored_linear_velocity
		angular_velocity = _stored_angular_velocity
		_follow_body = null
		_frame_body = null


func enter_pilot(player: Player) -> void:
	if pilot != null:
		return
	pilot = player
	_hatch_target = 0.0
	player.set_piloting(true)
	(chase_cam if _chase_view else cockpit_cam).current = true
	_mouse_delta = Vector2.ZERO
	_look_rate = Vector2.ZERO
	angular_damp = 0.0
	var hud := _hud()
	if hud != null:
		hud.set_ship(self)


func exit_pilot() -> void:
	if pilot == null:
		return
	var exit_world := to_global(exit_pos)
	pilot.global_transform = Transform3D(global_basis.orthonormalized(), exit_world)
	pilot.set_piloting(false)
	pilot.up_dir = global_basis.y.normalized()
	pilot.velocity = linear_velocity + angular_velocity.cross(exit_world - global_position)
	pilot.ensure_surface_clearance(0.35)
	pilot = null
	autopilot_target = null
	assist_active = false
	boosting = false
	angular_damp = IDLE_ANGULAR_DAMP
	_hatch_target = -1.15
	_set_thrusters(false)
	var hud := _hud()
	if hud != null:
		hud.set_ship(null)


func place(target_transform: Transform3D, body: CelestialBody) -> void:
	if pilot != null:
		exit_pilot()
	autopilot_target = null
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, target_transform)
	global_transform = target_transform
	linear_velocity = body.orbital_velocity
	angular_velocity = Vector3.ZERO
	_frame_body = null
	_had_ground_contact = false
	if _fast_time_enabled:
		_follow_body = body
		_follow_offset = target_transform.origin - body.global_position
		_stored_linear_velocity = Vector3.ZERO
		_stored_angular_velocity = Vector3.ZERO


func _set_thrusters(enabled: bool) -> void:
	for thruster in _thrusters:
		thruster.emitting = enabled
