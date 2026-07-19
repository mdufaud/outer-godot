extends RigidBody3D

const THRUST_ACCEL := 40.0
const BRAKE_ACCEL := 45.0
const TORQUE := 26.0
const MOUSE_TORQUE := 0.06
const WATER_HALF_HEIGHT := 2.7
const WATER_BUOYANCY := 1.15
const WATER_LINEAR_DRAG := 2.0
const WATER_ANGULAR_DRAG := 1.5
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


func _ready() -> void:
	collision_mask |= 2
	mass = 8.0
	angular_damp = 3.0
	linear_damp = 0.0
	can_sleep = false
	continuous_cd = true
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

	cockpit_cam = Camera3D.new()
	cockpit_cam.position = Vector3(0, 1.0, -1.4)
	cockpit_cam.far = 8000.0
	add_child(cockpit_cam)


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
	if pilot == null:
		return

	var thrust := Vector3(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("sprint", "jump"),
		Input.get_axis("move_forward", "move_back")
	)
	if thrust.length_squared() > 0.0:
		state.apply_central_force(global_basis * thrust.limit_length(1.0) * THRUST_ACCEL * mass)

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


func enter_pilot(player: Node3D) -> void:
	if pilot != null:
		return
	pilot = player
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
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set_ship(null)


func reset(t: Transform3D, inherited_velocity := Vector3.ZERO) -> void:
	if pilot != null:
		exit_pilot()
	global_transform = t
	linear_velocity = inherited_velocity
	angular_velocity = Vector3.ZERO
