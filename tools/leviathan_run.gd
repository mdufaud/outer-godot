extends SceneTree

# Real-GPU capture of the leviathan sequence. Headless renders nothing, so this
# has to run with a window. Each capture waits for a drawn frame before pulling
# the viewport texture.
#
# It captures what the player actually sees. The previous version built its own
# camera eight thousand units under the throat, so every past capture framed a
# shot nobody plays and hid the arrival angle entirely. Pass "debug" as the
# first argument for the old free camera when inspecting anatomy instead.

const CAPTURES := {
	3.0: "res://tmp/leviathan_run_t03.png",
	9.0: "res://tmp/leviathan_run_t09.png",
	14.0: "res://tmp/leviathan_run_t14.png",
	20.0: "res://tmp/leviathan_run_t20.png",
	27.0: "res://tmp/leviathan_run_t27.png",
	34.0: "res://tmp/leviathan_run_t34.png",
	38.0: "res://tmp/leviathan_run_t38.png",
}
const STEP := 1.0 / 30.0

var _leviathan: Node
var _debug_camera: Camera3D
var _clock := 0.0
var _pending := []


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	change_scene_to_file("res://game/bootstrap/main.tscn")
	# The system builds itself over several frames, so wait for the creature to
	# actually register rather than assuming it is there on frame two.
	for attempt in 600:
		await process_frame
		_leviathan = get_first_node_in_group("leviathan")
		if _leviathan != null:
			break
	if _leviathan == null:
		push_error("No leviathan in the scene")
		quit(1)
		return
	for settle in 30:
		await process_frame
	_pending = CAPTURES.keys()
	_pending.sort()
	# Drive the sequence by hand so a capture lands on an exact story beat
	# instead of wherever the frame rate happens to put it.
	_leviathan.process_mode = Node.PROCESS_MODE_DISABLED
	if OS.get_cmdline_user_args().has("debug"):
		_place_debug_camera()
	_leviathan.call("summon")
	_run()


func _place_debug_camera() -> void:
	_debug_camera = Camera3D.new()
	_debug_camera.far = 120000.0
	_debug_camera.near = 50.0
	_debug_camera.fov = 62.0
	root.add_child(_debug_camera)


# The world runs on a floating origin, so the sun slides through global space as
# the player drifts. The shot has to be rebuilt from live positions every frame
# or it is left behind within seconds.
func _aim_debug_camera() -> void:
	if _debug_camera == null:
		return
	var direction: Vector3 = _leviathan.get("_direction")
	var maw: Vector3 = (_leviathan as Node3D).global_position
	_debug_camera.global_position = maw - direction * 8000.0 - Vector3.UP * 10000.0
	_debug_camera.look_at(maw + direction * 3000.0, Vector3.UP)
	_debug_camera.make_current()


func _run() -> void:
	while not _pending.is_empty():
		_leviathan.call("_process", STEP)
		_aim_debug_camera()
		_clock += STEP
		if _clock >= _pending[0]:
			var path: String = CAPTURES[_pending[0]]
			_pending.remove_at(0)
			await process_frame
			await process_frame
			var image := root.get_texture().get_image()
			image.save_png(ProjectSettings.globalize_path(path))
			print("captured ", path, " at t=", _clock,
				" maw_open=", _leviathan.call("maw_open_at", _clock),
				" on_screen=", _framing_report())
		else:
			await process_frame
	quit(0)


# A number, not an impression: how far off the screen centre the maw sits, in
# half-screens, and whether it is in front of the camera at all.
func _framing_report() -> String:
	var camera := root.get_camera_3d()
	if camera == null:
		return "no camera"
	var maw: Vector3 = (_leviathan as Node3D).global_position
	if camera.is_position_behind(maw):
		return "BEHIND"
	var screen := camera.unproject_position(maw)
	var size := root.get_visible_rect().size
	var offset := (screen - size * 0.5) / (size * 0.5)
	return "%.2f,%.2f" % [offset.x, offset.y]
