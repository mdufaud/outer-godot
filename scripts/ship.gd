extends RigidBody3D

const THRUST_ACCEL := 40.0
const BRAKE_ACCEL := 45.0
const TORQUE := 26.0
const MOUSE_TORQUE := 0.06
const WATER_HALF_HEIGHT := 2.7
const WATER_BUOYANCY := 1.15
const WATER_LINEAR_DRAG := 2.0
const WATER_ANGULAR_DRAG := 1.5
const GROUND_LEVEL_TORQUE := 18.0
const HARD_LANDING_SPEED := 6.0
# Quaternius "Spaceship_BarbaraTheBee" (Ultimate Space Kit, CC0). Model faces +Z,
# rotated PI so the glass dome looks down ship -Z (Godot forward). Hull is
# single-sided: from the pilot camera inside, backfaces cull away and the view
# through the dome is unobstructed.
const MODEL_PATH := "res://assets/models/spaceship_pod.glb"

var pilot: Node3D = null
var mouse_delta := Vector2.ZERO
var cockpit_cam: Camera3D
var exit_pos := Vector3(3.0, -1.6, 0.0)

var dark_mat: StandardMaterial3D
var _thrusters: Array[GPUParticles3D] = []
var _hatch_pivot: Node3D
var _hatch_target := -1.15
var _had_ground_contact := false
var _fast_time_enabled := false
var _stored_linear_velocity := Vector3.ZERO
var _stored_angular_velocity := Vector3.ZERO


func _ready() -> void:
	add_to_group("fast_time_affected")
	collision_mask |= 2
	mass = 8.0
	angular_damp = 3.0
	linear_damp = 0.0
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.8, 0)

	dark_mat = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.22, 0.22, 0.25)
	dark_mat.roughness = 0.8

	var model: Node3D = (load(MODEL_PATH) as PackedScene).instantiate()
	model.rotation.y = PI
	add_child(model)

	# body collision: one sphere around the pod core (wings/antennae stay ghost)
	var body_col := CollisionShape3D.new()
	var body_shape := SphereShape3D.new()
	body_shape.radius = 2.3
	body_col.shape = body_shape
	body_col.position = Vector3(0, 0.6, 0)
	add_child(body_col)

	for x in [-1.7, 1.7]:
		for z in [-1.3, 1.3]:
			_leg(Vector3(x, -1.0, z))

	_build_cockpit()
	_build_thrusters()

	cockpit_cam = Camera3D.new()
	cockpit_cam.position = Vector3(0, 1.0, -1.4)
	cockpit_cam.far = 8000.0
	add_child(cockpit_cam)
	var celestial_system := get_tree().get_first_node_in_group("celestial_system")
	if celestial_system != null:
		set_fast_time_enabled(celestial_system.is_fast_forward_enabled())


func _process(delta: float) -> void:
	if _hatch_pivot != null:
		_hatch_pivot.rotation.z = lerp_angle(_hatch_pivot.rotation.z, _hatch_target, clampf(delta * 4.5, 0.0, 1.0))


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
	seat.set_script(preload("res://scripts/seat.gd"))
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


func _leg(top: Vector3) -> void:
	# Outer Wilds style: legs splay outward from the belly to the ground
	var foot := Vector3(top.x * 1.5, -2.6, top.z * 1.5)
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
		mouse_delta += event.relative
	elif event.is_action_pressed("interact"):
		exit_pilot()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var gravity: Vector3 = Gravity.get_gravity(global_position)
	state.apply_central_force(gravity * mass)
	var source := Gravity.get_nearest_surface(global_position)
	if source != null and source.has_method("get_water_depth"):
		var water_depth: float = source.get_water_depth(global_position)
		var submerged := clampf((water_depth + WATER_HALF_HEIGHT) / (WATER_HALF_HEIGHT * 2.0), 0.0, 1.0)
		if submerged > 0.0:
			state.apply_central_force(-gravity * mass * submerged * WATER_BUOYANCY)
			var source_velocity: Vector3 = source.get("orbital_velocity")
			state.apply_central_force(-(state.linear_velocity - source_velocity) * mass * WATER_LINEAR_DRAG * submerged)
			state.apply_torque(-state.angular_velocity * mass * WATER_ANGULAR_DRAG * submerged)
	var ground_contact := state.get_contact_count() > 0 and source != null
	if ground_contact:
		var local_up := (global_position - source.global_position).normalized()
		var level_axis := global_basis.y.cross(local_up)
		state.apply_torque(level_axis * GROUND_LEVEL_TORQUE * mass - state.angular_velocity * mass * 2.5)
		if not _had_ground_contact:
			var source_velocity: Vector3 = source.get("orbital_velocity")
			var impact_speed := absf((state.linear_velocity - source_velocity).dot(local_up))
			if impact_speed >= HARD_LANDING_SPEED:
				var main := get_tree().current_scene
				if main != null and main.has_method("trigger_camera_shake"):
					main.trigger_camera_shake(clampf(impact_speed * 0.006, 0.035, 0.10), 0.42)
	_had_ground_contact = ground_contact
	if pilot == null:
		_set_thrusters(false)
		return

	var thrust := Vector3(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("sprint", "jump"),
		Input.get_axis("move_forward", "move_back")
	)
	if thrust.length_squared() > 0.0:
		state.apply_central_force(global_basis * thrust.limit_length(1.0) * THRUST_ACCEL * mass)
	_set_thrusters(thrust.length_squared() > 0.01)

	if Input.is_action_pressed("brake") and state.linear_velocity.length() > 0.3:
		state.apply_central_force(-state.linear_velocity.normalized() * BRAKE_ACCEL * mass)

	var look := mouse_delta + Touch.look_delta
	mouse_delta = Vector2.ZERO
	Touch.look_delta = Vector2.ZERO
	var rot_input := Vector3(
		clampf(-look.y * MOUSE_TORQUE, -6.0, 6.0),
		clampf(-look.x * MOUSE_TORQUE, -6.0, 6.0),
		Input.get_axis("roll_right", "roll_left")
	)
	if rot_input.length_squared() > 0.0:
		state.apply_torque(global_basis * rot_input * TORQUE * mass)


func set_fast_time_enabled(enabled: bool) -> void:
	if enabled == _fast_time_enabled:
		return
	_fast_time_enabled = enabled
	if enabled:
		_stored_linear_velocity = linear_velocity
		_stored_angular_velocity = angular_velocity
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze = true
		_set_thrusters(false)
	else:
		freeze = false
		linear_velocity = _stored_linear_velocity
		angular_velocity = _stored_angular_velocity


func enter_pilot(player: Node3D) -> void:
	if pilot != null:
		return
	pilot = player
	_hatch_target = 0.0
	player.set_piloting(true)
	cockpit_cam.current = true
	mouse_delta = Vector2.ZERO
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
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
	_hatch_target = -1.15
	_set_thrusters(false)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set_ship(null)


func reset(t: Transform3D, inherited_velocity := Vector3.ZERO) -> void:
	if pilot != null:
		exit_pilot()
	global_transform = t
	linear_velocity = inherited_velocity
	angular_velocity = Vector3.ZERO


func _set_thrusters(enabled: bool) -> void:
	for thruster in _thrusters:
		thruster.emitting = enabled
