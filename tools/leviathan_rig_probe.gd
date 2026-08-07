extends SceneTree

# Renders the baked rig through the same poses the sequence uses, so the jaw
# hinge and the swim wave can be checked without playing the whole devour.
#
# Run: godot --headless --script res://tools/leviathan_rig_probe.gd
# Output: tmp/leviathan_rig/*.png

const RIGGED := "res://assets/models/leviathan_rigged.scn"
const OUT_DIR := "res://tmp/leviathan_rig"

const BODY_CENTRE := Vector3(0.0, 60.0, 5.0)
const BODY_RADIUS := 150.0
const HEAD_CENTRE := Vector3(0.0, 55.0, 60.0)
const HEAD_RADIUS := 110.0

# name, camera direction, framing centre, framing radius, elapsed, maw_open
const SHOTS := [
	["jaw_shut", Vector3(-1.0, 0.0, 0.0), HEAD_CENTRE, HEAD_RADIUS, 0.0, 0.0],
	["jaw_half", Vector3(-1.0, 0.0, 0.0), HEAD_CENTRE, HEAD_RADIUS, 0.0, 0.5],
	["jaw_wide", Vector3(-1.0, 0.0, 0.0), HEAD_CENTRE, HEAD_RADIUS, 0.0, 1.0],
	["jaw_wide_three_quarter", Vector3(-0.7, 0.1, 0.7), HEAD_CENTRE, HEAD_RADIUS, 0.0, 1.0],
	["swim_0", Vector3(0.0, 1.0, 0.02), BODY_CENTRE, BODY_RADIUS, 0.0, 0.8],
	["swim_1", Vector3(0.0, 1.0, 0.02), BODY_CENTRE, BODY_RADIUS, 0.78, 0.8],
	["swim_2", Vector3(0.0, 1.0, 0.02), BODY_CENTRE, BODY_RADIUS, 1.56, 0.8],
	["swim_3", Vector3(0.0, 1.0, 0.02), BODY_CENTRE, BODY_RADIUS, 2.34, 0.8],
	["swim_side", Vector3(-1.0, 0.0, 0.0), BODY_CENTRE, BODY_RADIUS, 1.56, 0.8],
	["rest_side", Vector3(-1.0, 0.0, 0.0), BODY_CENTRE, BODY_RADIUS, 0.0, 0.0],
]

var _index := -1
var _camera: Camera3D
var _rig: LeviathanRig


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var visual := (load(RIGGED) as PackedScene).instantiate()
	root.add_child(visual)
	var skeleton := visual.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_rig = LeviathanRig.new(skeleton)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.9)
	env.ambient_light_energy = 1.2
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30.0, 150.0, 0.0)
	key.light_energy = 1.6
	root.add_child(key)

	_camera = Camera3D.new()
	_camera.far = 5000.0
	_camera.current = true
	root.add_child(_camera)

	RenderingServer.frame_post_draw.connect(_on_frame_drawn)


func _stage() -> void:
	var shot: Array = SHOTS[_index]
	_rig.apply(shot[4], shot[5], 1.0)
	var direction := (shot[1] as Vector3).normalized()
	var centre := shot[2] as Vector3
	_camera.position = centre + direction * (shot[3] as float) * 1.3
	_camera.look_at(centre, Vector3.UP if absf(direction.y) < 0.95 else Vector3.BACK)


func _on_frame_drawn() -> void:
	if _index < 0:
		_index = 0
		_stage()
		return
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, SHOTS[_index][0]]))
	_index += 1
	if _index >= SHOTS.size():
		RenderingServer.frame_post_draw.disconnect(_on_frame_drawn)
		quit()
		return
	_stage()
