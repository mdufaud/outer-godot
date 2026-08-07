extends SceneTree

# Leak repro for the shutdown errors the leviathan sequence produces. The
# creature is driven in coarse steps because everything it does is a function of
# its own clock, so a quarter second per frame reaches the blackout in eighty
# frames instead of eleven hundred.
#
#   godot --verbose -s tools/leviathan_leak.gd 2>&1 | grep -A40 "ObjectDB"
#
# It needs a real rendering device: headless never finishes the atmosphere LUT,
# so no body ever boots and the creature is never registered.

const STEP := 0.25
const END := 42.0

var _leviathan: Node


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	change_scene_to_file("res://game/bootstrap/main.tscn")
	for attempt in 900:
		await process_frame
		_leviathan = get_first_node_in_group("leviathan")
		if _leviathan != null:
			break
	if _leviathan == null:
		push_error("No leviathan in the scene")
		quit(1)
		return
	for settle in 10:
		await process_frame
	var before := get_nodes_in_group("celestial_body").size()
	_leviathan.process_mode = Node.PROCESS_MODE_DISABLED
	_leviathan.call("summon")
	var clock := 0.0
	# The blackout restarts the world, which takes the creature with it, so the
	# loop has to survive its own driver disappearing.
	while clock < END and is_instance_valid(_leviathan):
		_leviathan.call("_process", STEP)
		clock += STEP
		await process_frame
	# The blackout reloads the world. Quitting while that boot is still running
	# strands its coroutine, which is a leak of its own and would hide the one
	# being measured, so the restart has to finish first.
	for attempt in 900:
		await process_frame
		if get_nodes_in_group("celestial_body").size() >= before:
			break
	for settle in 30:
		await process_frame
	var after := get_nodes_in_group("celestial_body").size()
	print("Celestial bodies: %d before, %d after the restart" % [before, after])
	quit(0)
