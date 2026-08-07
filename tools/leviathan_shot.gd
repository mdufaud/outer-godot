extends SceneTree

# Turntable screenshots of the leviathan model, used to check orientation and
# how the imported mesh actually reads before it is wired into the sequence.

const MODEL := "res://assets/models/leviathan.glb"
const OUT_DIR := "res://tmp/leviathan"

const VIEWS := [
	["front", Vector3(0.0, 0.0, -1.0)],
	["back", Vector3(0.0, 0.0, 1.0)],
	["left", Vector3(-1.0, 0.0, 0.0)],
	["right", Vector3(1.0, 0.0, 0.0)],
	["top", Vector3(0.0, 1.0, 0.01)],
	["bottom", Vector3(0.0, -1.0, 0.01)],
	["three_quarter", Vector3(-0.8, 0.35, -0.6)],
	["under_front", Vector3(-0.35, -0.55, -0.75)],
]

var _index := -1
var _camera: Camera3D
var _visual: Node3D
var _centre := Vector3.ZERO
var _radius := 1.0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_visual = (load(MODEL) as PackedScene).instantiate()
	root.add_child(_visual)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.8)
	env.ambient_light_energy = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, 145.0, 0.0)
	key.light_energy = 2.0
	root.add_child(key)

	_camera = Camera3D.new()
	_camera.current = true
	root.add_child(_camera)

	RenderingServer.frame_post_draw.connect(_on_frame_drawn)


func _all_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_all_meshes(child))
	return found


func _measure() -> void:
	var aabb := AABB()
	var first := true
	for node in _all_meshes(_visual):
		var box := node.global_transform * node.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
		print("mesh %s surfaces=%d" % [node.name, node.mesh.get_surface_count()])
		for surface in node.mesh.get_surface_count():
			print("  surface %d material=%s" % [surface, node.mesh.surface_get_material(surface)])
	_centre = aabb.get_center()
	_radius = aabb.size.length() * 0.5
	print("world aabb position=%s size=%s centre=%s" % [aabb.position, aabb.size, _centre])
	_camera.far = _radius * 20.0


func _aim() -> void:
	var direction: Vector3 = (VIEWS[_index][1] as Vector3).normalized()
	_camera.position = _centre + direction * _radius * 1.7
	_camera.look_at(_centre, Vector3.UP if absf(direction.y) < 0.95 else Vector3.BACK)


func _on_frame_drawn() -> void:
	if _index < 0:
		_measure()
		_index = 0
		_aim()
		return
	var image := root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, VIEWS[_index][0]]))
	_index += 1
	if _index >= VIEWS.size():
		RenderingServer.frame_post_draw.disconnect(_on_frame_drawn)
		quit()
		return
	_aim()
