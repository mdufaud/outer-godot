extends SceneTree

const CAPTURE_PATH := "user://cyclops_probe%s.png"


func _initialize() -> void:
	change_scene_to_file("res://game/bootstrap/main.tscn")
	await process_frame
	await process_frame
	var root_node := current_scene
	# The screen overlays only exist once main.gd finishes booting, so waiting a fixed frame count
	# captures a frame with no cloud tint at all.
	var boot_frames := 0
	while not bool(root_node.get("_loaded")):
		await process_frame
		boot_frames += 1
		if boot_frames > 6000:
			printerr("main.tscn never finished booting")
			quit(1)
			return
	for wait_frame in 30:
		await process_frame
	var cyclops: Node3D = root_node.find_child("Cyclops", true, false)
	if cyclops == null:
		printerr("Cyclops not found")
		quit(1)
		return
	var sea_level: float = float(cyclops.call("sea_level"))
	var deck_gap: float = float(cyclops.call("get_storm_deck_gap"))
	var camera := Camera3D.new()
	camera.far = 20000.0
	root_node.add_child(camera)
	camera.current = true
	# ALTITUDE is a fraction of the sea-to-deck gap, so the framing holds at any planet size.
	var altitude_fraction := float(OS.get_environment("ALTITUDE")) if OS.has_environment("ALTITUDE") else 0.26
	var camera_radius := sea_level + deck_gap * altitude_fraction
	print("sea %.2f deck %.2f..%.2f camera %.2f" % [
		sea_level,
		float(cyclops.call("get_storm_deck_inner_radius")),
		float(cyclops.call("get_storm_deck_outer_radius")),
		camera_radius,
	])
	var up_direction := Vector3.UP
	# Cyclops orbits, so the camera has to be re-aimed every frame or it drifts out of the deck
	# before the capture and the measured altitude is a lie.
	for wait_frame in 90:
		up_direction = (Vector3.ZERO - cyclops.global_position).normalized()
		var side := up_direction.cross(Vector3(0.0, 1.0, 0.0)).normalized()
		if side.length() < 0.5:
			side = up_direction.cross(Vector3(1.0, 0.0, 0.0)).normalized()
		var origin := cyclops.global_position + up_direction * camera_radius
		# LOOK=down aims at the planet for exterior shots; the default tangential aim frames the
		# tornadoes and the deck ceiling from below.
		if OS.get_environment("LOOK") == "down":
			camera.look_at_from_position(origin, cyclops.global_position, side)
		else:
			var pitch := float(OS.get_environment("PITCH")) if OS.has_environment("PITCH") else 0.9
			camera.look_at_from_position(origin, origin + side * 4.0 + up_direction * pitch, up_direction)
		await process_frame
	print("tint %.4f occlusion %.4f overlay %s" % [
		float(cyclops.call("get_storm_cloud_transition", camera.global_position)),
		float(cyclops.call("get_storm_sky_occlusion", camera.global_position)),
		str((root_node.get("_transition_tint") as ColorRect).visible if root_node.get("_transition_tint") != null else "missing"),
	])
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	var capture_path := CAPTURE_PATH % OS.get_environment("NAME")
	image.save_png(ProjectSettings.globalize_path(capture_path))
	var centre := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	var sky := image.get_pixel(image.get_width() / 2, int(image.get_height() * 0.2))
	var sea := image.get_pixel(image.get_width() / 2, int(image.get_height() * 0.8))
	print("saved: %s" % ProjectSettings.globalize_path(capture_path))
	print("sky   : %.4f %.4f %.4f" % [sky.r, sky.g, sky.b])
	print("centre: %.4f %.4f %.4f" % [centre.r, centre.g, centre.b])
	print("sea   : %.4f %.4f %.4f" % [sea.r, sea.g, sea.b])
	quit(0)
