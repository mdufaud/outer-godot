extends RigidBody3D

const THRUST_ACCEL := 22.0
const BRAKE_ACCEL := 28.0
const TORQUE := 26.0
const MOUSE_TORQUE := 0.015

var pilot: Node3D = null
var mouse_delta := Vector2.ZERO
var cockpit_cam: Camera3D
var exit_pos := Vector3(0.9, 1.0, -0.6)

var hull_mat: StandardMaterial3D
var dark_mat: StandardMaterial3D
var glass_mat: StandardMaterial3D


func _ready() -> void:
	mass = 8.0
	angular_damp = 3.0
	linear_damp = 0.0
	can_sleep = false
	continuous_cd = true
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.4, 0)

	hull_mat = StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.75, 0.45, 0.2)
	hull_mat.roughness = 0.6
	hull_mat.metallic = 0.3
	dark_mat = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.25, 0.25, 0.28)
	dark_mat.roughness = 0.8
	glass_mat = StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.6, 0.8, 1.0, 0.25)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.1

	_build_hull()
	_build_interior()

	cockpit_cam = Camera3D.new()
	cockpit_cam.position = Vector3(0, 1.55, -1.45)
	cockpit_cam.far = 8000.0
	add_child(cockpit_cam)


func _build_hull() -> void:
	# Interior: x [-2, 2], y [0, 2.6], z [-2.5, 2.5]. Origin = floor top center.
	_panel(Vector3(4.4, 0.2, 5.4), Vector3(0, -0.1, 0), dark_mat)      # floor
	_panel(Vector3(4.4, 0.2, 5.4), Vector3(0, 2.7, 0), hull_mat)       # roof
	_panel(Vector3(0.2, 2.6, 5.4), Vector3(-2.1, 1.3, 0), hull_mat)    # left wall
	_panel(Vector3(0.2, 2.6, 5.4), Vector3(2.1, 1.3, 0), hull_mat)     # right wall
	# front wall (-z) with window
	_panel(Vector3(4.4, 0.8, 0.2), Vector3(0, 0.4, -2.6), hull_mat)
	_panel(Vector3(4.4, 0.4, 0.2), Vector3(0, 2.4, -2.6), hull_mat)
	_panel(Vector3(0.4, 1.4, 0.2), Vector3(-2.0, 1.5, -2.6), hull_mat)
	_panel(Vector3(0.4, 1.4, 0.2), Vector3(2.0, 1.5, -2.6), hull_mat)
	_panel(Vector3(3.6, 1.4, 0.1), Vector3(0, 1.5, -2.6), glass_mat)   # window
	# back wall (+z) with open doorway (width 1.2, height 2.0)
	_panel(Vector3(1.5, 2.6, 0.2), Vector3(-1.35, 1.3, 2.6), hull_mat)
	_panel(Vector3(1.5, 2.6, 0.2), Vector3(1.35, 1.3, 2.6), hull_mat)
	_panel(Vector3(1.2, 0.6, 0.2), Vector3(0, 2.3, 2.6), hull_mat)     # lintel
	# landing legs
	for x in [-1.6, 1.6]:
		for z in [-1.8, 1.8]:
			_leg(Vector3(x, -0.95, z))
	# rear thrusters (cosmetic)
	for x in [-1.0, 1.0]:
		var t := MeshInstance3D.new()
		var t_mesh := CylinderMesh.new()
		t_mesh.top_radius = 0.35
		t_mesh.bottom_radius = 0.5
		t_mesh.height = 0.8
		t_mesh.material = dark_mat
		t.mesh = t_mesh
		t.position = Vector3(x, 0.6, 3.0)
		t.rotation.x = -PI / 2
		add_child(t)


func _build_interior() -> void:
	_panel(Vector3(0.8, 0.5, 0.8), Vector3(0, 0.25, -1.7), dark_mat)   # seat base
	_panel(Vector3(0.8, 0.8, 0.2), Vector3(0, 0.9, -1.25), dark_mat)   # seat back
	_panel(Vector3(2.4, 0.15, 0.6), Vector3(0, 1.0, -2.2), dark_mat)   # console

	var seat := Area3D.new()
	seat.set_script(preload("res://scripts/seat.gd"))
	var seat_col := CollisionShape3D.new()
	var seat_shape := BoxShape3D.new()
	seat_shape.size = Vector3(1.2, 1.6, 1.2)
	seat_col.shape = seat_shape
	seat.add_child(seat_col)
	seat.position = Vector3(0, 0.9, -1.7)
	add_child(seat)
	seat.ship = self


func _panel(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh.mesh = box
	mesh.position = pos
	add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	add_child(col)


func _leg(pos: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.18
	cyl.height = 1.5
	cyl.material = dark_mat
	mesh.mesh = cyl
	mesh.position = pos
	add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.18
	shape.height = 1.5
	col.shape = shape
	col.position = pos
	add_child(col)


func _unhandled_input(event: InputEvent) -> void:
	if pilot == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_delta += event.relative
	elif event.is_action_pressed("interact"):
		exit_pilot()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	state.apply_central_force(Gravity.get_gravity(global_position) * mass)
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

	var rot_input := Vector3(
		clampf(-mouse_delta.y * MOUSE_TORQUE, -2.0, 2.0),
		clampf(-mouse_delta.x * MOUSE_TORQUE, -2.0, 2.0),
		Input.get_axis("roll_right", "roll_left")
	)
	mouse_delta = Vector2.ZERO
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
	var t := global_transform
	t.origin = to_global(exit_pos)
	pilot.global_transform = Transform3D(global_basis.orthonormalized(), t.origin)
	pilot.set_piloting(false)
	pilot.velocity = linear_velocity
	pilot = null
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set_ship(null)


func reset(t: Transform3D) -> void:
	if pilot != null:
		exit_pilot()
	global_transform = t
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
