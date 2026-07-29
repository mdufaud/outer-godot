extends SceneTree

const CAPTURE_PATH := "user://cyclops_probe.png"


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	var root_node := current_scene
	for wait_frame in 240:
		await process_frame
	var cyclops: Node3D = root_node.find_child("Cyclops", true, false)
	if cyclops == null:
		printerr("Cyclops not found")
		quit(1)
		return
	var sea_level: float = float(cyclops.get("radius")) + float(cyclops.get("ocean_level"))
	var to_sun := (Vector3.ZERO - cyclops.global_position).normalized()
	var up_direction := to_sun
	var camera := Camera3D.new()
	camera.far = 20000.0
	root_node.add_child(camera)
	var origin := cyclops.global_position + up_direction * (sea_level + 12.0)
	var side := up_direction.cross(Vector3(0.0, 1.0, 0.0)).normalized()
	if side.length() < 0.5:
		side = up_direction.cross(Vector3(1.0, 0.0, 0.0)).normalized()
	camera.global_position = origin
	var pitch := float(OS.get_environment("PITCH")) if OS.has_environment("PITCH") else 0.9
	camera.look_at_from_position(origin, origin + side * 4.0 + up_direction * pitch, up_direction)
	camera.current = true
	for wait_frame in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(CAPTURE_PATH))
	var centre := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	var sky := image.get_pixel(image.get_width() / 2, int(image.get_height() * 0.2))
	var sea := image.get_pixel(image.get_width() / 2, int(image.get_height() * 0.8))
	print("saved: %s" % ProjectSettings.globalize_path(CAPTURE_PATH))
	print("sun dot: %f" % up_direction.dot(to_sun))
	print("sky   : %.4f %.4f %.4f" % [sky.r, sky.g, sky.b])
	print("centre: %.4f %.4f %.4f" % [centre.r, centre.g, centre.b])
	print("sea   : %.4f %.4f %.4f" % [sea.r, sea.g, sea.b])
	quit(0)
