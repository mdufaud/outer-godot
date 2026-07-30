extends Node3D

const SHIP_SCENE := preload("res://game/ship/ship.tscn")
const SUN_SCENE := preload("res://game/sun/sun.tscn")
const SOLAR_SYSTEM_MANIFEST := preload("res://game/celestial/solar_system_manifest.gd")
const PLANET_EFFECTS := preload("res://game/rendering/planet_effects.gd")
const StarsShader := preload("res://game/rendering/shaders/stars.gdshader")

const GALLERY_COLUMNS := 3
const GALLERY_COLUMN_SPACING := 520.0
const GALLERY_ROW_SPACING := 360.0
const SUN_DIRECTION := Vector3(0.0, 0.0, 1.0)

@export var capture_directory := "user://planet_gallery"
@export var capture_warmup_frames := 30

var _planets: Array[Node3D] = []
var _camera: Camera3D
var _ship: RigidBody3D
var _sun: Node3D
var _sun_light: DirectionalLight3D
var _sky_material: ShaderMaterial
var _planet_effects: CompositorEffect
var _status_label: Label
var _help_label: Label
var _selected_index := 0
var _gallery_distance_scale := 1.0
var _cockpit_mode := false
var _ship_day := true
var _fast_mode := false
var _capture_queue: Array[Dictionary] = []
var _capture_item: Dictionary = {}
var _capture_wait_frames := -1
var _auto_capture := false


class GalleryClock extends Node:
    var fast_forward_enabled := false

    func _ready() -> void:
        add_to_group("celestial_system")

    func set_fast_forward_enabled(enabled: bool) -> void:
        fast_forward_enabled = enabled
        get_tree().call_group("fast_time_affected", "set_fast_time_enabled", enabled)

    func is_fast_forward_enabled() -> bool:
        return fast_forward_enabled


func _ready() -> void:
    var configured_directory := OS.get_environment("PLANET_GALLERY_CAPTURE_DIR")
    if not configured_directory.is_empty():
        capture_directory = configured_directory
    _build_environment()
    _build_sun()
    _build_camera()
    _build_planets()
    _build_ship()
    _build_ui()
    _parse_user_args()
    _apply_gallery_camera()
    _update_status()


func _process(_delta: float) -> void:
    _update_sky_and_light()
    _update_status()
    _process_capture_queue()
    if _camera != null:
        _planet_effects.update_from_bodies(
            _camera.global_position, get_tree().get_nodes_in_group("celestial_body"))


func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    match event.keycode:
        KEY_RIGHT:
            _select_planet(_selected_index + 1)
        KEY_LEFT:
            _select_planet(_selected_index - 1)
        KEY_PLUS, KEY_EQUAL:
            _gallery_distance_scale = clampf(_gallery_distance_scale - 0.2, 0.55, 2.5)
            if not _cockpit_mode:
                _apply_gallery_camera()
        KEY_MINUS, KEY_UNDERSCORE:
            _gallery_distance_scale = clampf(_gallery_distance_scale + 0.2, 0.55, 2.5)
            if not _cockpit_mode:
                _apply_gallery_camera()
        KEY_C:
            _set_cockpit_mode(not _cockpit_mode)
        KEY_D:
            if _cockpit_mode:
                _ship_day = not _ship_day
                _place_ship()
        KEY_F:
            _set_fast_mode(not _fast_mode)
        KEY_P:
            _queue_selected_capture()
        KEY_G:
            _queue_all_captures()
        KEY_ESCAPE:
            _set_cockpit_mode(false)


func _build_environment() -> void:
    var environment := Environment.new()
    var sky := Sky.new()
    _sky_material = ShaderMaterial.new()
    _sky_material.shader = StarsShader
    sky.sky_material = _sky_material
    environment.background_mode = Environment.BG_SKY
    environment.sky = sky
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.12, 0.16, 0.24)
    environment.ambient_light_energy = 0.2
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment.glow_enabled = true
    environment.glow_intensity = 1.15
    environment.glow_strength = 1.1
    environment.glow_bloom = 0.18
    environment.glow_hdr_threshold = 1.0
    environment.glow_hdr_scale = 2.0
    environment.glow_hdr_luminance_cap = 12.0
    var world_environment := WorldEnvironment.new()
    world_environment.environment = environment
    _planet_effects = PLANET_EFFECTS.new()
    var compositor := Compositor.new()
    compositor.compositor_effects = [_planet_effects]
    world_environment.compositor = compositor
    add_child(world_environment)


func _build_sun() -> void:
    _sun = SUN_SCENE.instantiate()
    _sun.name = "GallerySun"
    _sun.position = SUN_DIRECTION * 100000.0
    _sun.set("radius", 345.0)
    _sun.set("surface_gravity", 50.0)
    add_child(_sun)
    _sun_light = DirectionalLight3D.new()
    _sun_light.light_energy = 1.2
    _sun_light.shadow_enabled = true
    _sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
    _sun_light.directional_shadow_max_distance = 5000.0
    _sun_light.shadow_bias = 0.16
    _sun_light.shadow_normal_bias = 0.1
    add_child(_sun_light)


func _build_camera() -> void:
    _camera = Camera3D.new()
    _camera.name = "GalleryCamera"
    _camera.fov = 55.0
    _camera.near = 0.05
    _camera.far = 200000.0
    add_child(_camera)
    _camera.current = true


func _build_planets() -> void:
    var entries: Array[CelestialEntry] = SOLAR_SYSTEM_MANIFEST.get_entries()
    for index in entries.size():
        var entry: CelestialEntry = entries[index]
        var body: PlanetBody = entry.scene.instantiate()
        body.name = String(entry.body_id)
        body.quality_override = StringName(_quality_profile())
        body.position = _gallery_position(index)
        add_child(body)
        _planets.append(body)
        _add_planet_label(body, String(entry.body_id), body.radius)


func _quality_profile() -> String:
    var requested := OS.get_environment("PLANET_QUALITY")
    if requested in ["desktop_high", "desktop_medium", "mobile_low"]:
        return requested
    return "desktop_medium"


func _gallery_position(index: int) -> Vector3:
    var column := index % GALLERY_COLUMNS
    var row := index / GALLERY_COLUMNS
    return Vector3(
        (float(column) - 1.0) * GALLERY_COLUMN_SPACING,
        (1.0 - float(row)) * GALLERY_ROW_SPACING,
        0.0
    )


func _add_planet_label(body: Node3D, body_name: String, body_radius: float) -> void:
    var label := Label3D.new()
    label.text = body_name
    label.position = Vector3.UP * body_radius * 1.5
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.font_size = 64
    label.modulate = Color(0.75, 0.88, 1.0)
    label.outline_size = 8
    body.add_child(label)


func _build_ship() -> void:
    var clock := GalleryClock.new()
    clock.name = "GalleryClock"
    add_child(clock)
    _ship = SHIP_SCENE.instantiate()
    _ship.name = "TestShip"
    add_child(_ship)
    var interior_material: StandardMaterial3D = _ship.get("dark_mat")
    interior_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    _ship.freeze = true
    _place_ship()


func _build_ui() -> void:
    var layer := CanvasLayer.new()
    layer.layer = 10
    add_child(layer)
    var root := Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(root)
    var panel := ColorRect.new()
    panel.position = Vector2(18.0, 18.0)
    panel.size = Vector2(560.0, 154.0)
    panel.color = Color(0.015, 0.025, 0.06, 0.82)
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(panel)
    _status_label = Label.new()
    _status_label.position = Vector2(34.0, 30.0)
    _status_label.add_theme_font_size_override("font_size", 20)
    root.add_child(_status_label)
    _help_label = Label.new()
    _help_label.position = Vector2(18.0, 680.0)
    _help_label.add_theme_font_size_override("font_size", 16)
    _help_label.add_theme_color_override("font_color", Color(0.68, 0.78, 0.94))
    _help_label.text = "←/→ planet   +/- distance   C cockpit   D day/night   F fast   P shot   G all shots   Esc gallery"
    root.add_child(_help_label)
    get_viewport().size_changed.connect(_resize_ui)


func _resize_ui() -> void:
    if _help_label != null:
        _help_label.position = Vector2(18.0, get_viewport().get_visible_rect().size.y - 40.0)


func _select_planet(index: int) -> void:
    if _planets.is_empty():
        return
    _selected_index = posmod(index, _planets.size())
    if not _cockpit_mode:
        _apply_gallery_camera()


func _apply_gallery_camera() -> void:
    if _planets.is_empty():
        return
    var planet := _planets[_selected_index]
    var center := planet.global_position
    var radius := float(planet.get("radius"))
    for other_planet in _planets:
        other_planet.visible = other_planet == planet
    var distance := (radius * 4.5 + 35.0) * _gallery_distance_scale
    _camera.global_position = center + Vector3(0.0, radius * 0.18, distance)
    _camera.look_at(center, Vector3.UP)
    _camera.current = true


func _set_cockpit_mode(enabled: bool) -> void:
    _cockpit_mode = enabled
    var cockpit_camera: Camera3D = _ship.get("cockpit_cam")
    if _cockpit_mode:
        _place_ship()
        _camera.current = false
        cockpit_camera.current = true
    else:
        cockpit_camera.current = false
        _apply_gallery_camera()


func _place_ship() -> void:
    if _ship == null or _planets.is_empty():
        return
    var terra: Node3D = _planet_by_name("Terra")
    if terra == null:
        return
    var direction := SUN_DIRECTION if _ship_day else -SUN_DIRECTION
    var radius := float(terra.get("radius"))
    _ship.global_position = terra.global_position + direction * (radius + 3.0)
    var up := Vector3.UP
    var forward := direction
    if absf(forward.dot(Vector3.UP)) > 0.98:
        up = Vector3.RIGHT
    _ship.global_basis = Basis.looking_at(forward, up)
    _ship.linear_velocity = Vector3.ZERO
    _ship.angular_velocity = Vector3.ZERO
    _ship.freeze = true
    var cockpit_camera: Camera3D = _ship.get("cockpit_cam")
    cockpit_camera.fov = 78.0
    cockpit_camera.look_at(cockpit_camera.global_position + direction * 8.0 + Vector3(0.0, -8.0, 0.0), Vector3.UP)
    cockpit_camera.current = _cockpit_mode


func _planet_by_name(body_name: String) -> Node3D:
    for planet in _planets:
        if planet.name == body_name:
            return planet
    return null


func _set_fast_mode(enabled: bool) -> void:
    _fast_mode = enabled
    var clock := get_tree().get_first_node_in_group("celestial_system")
    if clock != null:
        clock.set_fast_forward_enabled(enabled)
    if _ship != null:
        _ship.freeze = true


func _update_sky_and_light() -> void:
    var active_camera := get_viewport().get_camera_3d()
    if active_camera == null:
        return
    var sun_direction := (_sun.global_position - active_camera.global_position).normalized()
    _sun_light.global_position = active_camera.global_position
    _sun_light.look_at(active_camera.global_position + sun_direction, Vector3.UP)
    _sky_material.set_shader_parameter("camera_position", active_camera.global_position)
    _sky_material.set_shader_parameter("sun_direction", sun_direction)
    var daylight := 0.0
    if _cockpit_mode:
        var terra := _planet_by_name("Terra")
        var local_up := (active_camera.global_position - terra.global_position).normalized()
        daylight = smoothstep(-0.08, 0.25, local_up.dot(sun_direction))
    _sky_material.set_shader_parameter("daylight", daylight)
    _sky_material.set_shader_parameter("underwater_strength", 0.0)
    var ocean_spheres := PackedVector4Array()
    for planet in _planets:
        if bool(planet.get("has_ocean")) and ocean_spheres.size() < 8:
            ocean_spheres.append(Vector4(
                planet.global_position.x,
                planet.global_position.y,
                planet.global_position.z,
                float(planet.get("radius")) + float(planet.get("ocean_level"))
            ))
    _sky_material.set_shader_parameter("ocean_count", ocean_spheres.size())
    _sky_material.set_shader_parameter("ocean_spheres", ocean_spheres)


func _update_status() -> void:
    if _status_label == null:
        return
    var selected_name := "Terra" if _cockpit_mode else (String(_planets[_selected_index].name) if not _planets.is_empty() else "loading")
    var ready_count := 0
    for planet in _planets:
        if planet.has_method("is_boot_ready") and bool(planet.call("is_boot_ready")):
            ready_count += 1
    var mode := "COCKPIT" if _cockpit_mode else "GALLERY"
    var submode := "day" if _ship_day else "night"
    var capture := "idle"
    if not _capture_item.is_empty():
        capture = "capturing %s" % String(_capture_item.tag)
    elif not _capture_queue.is_empty():
        capture = "%d queued" % _capture_queue.size()
    _status_label.text = "PLANET GALLERY  |  %s\nSelected: %s  |  ready: %d/%d\nShip: %s  |  fast: %s  |  capture: %s" % [
        mode,
        selected_name,
        ready_count,
        _planets.size(),
        submode,
        "ON" if _fast_mode else "OFF",
        capture,
    ]


func _parse_user_args() -> void:
    var args := OS.get_cmdline_user_args()
    if "--capture-all" in args:
        _queue_all_captures(true)


func _queue_selected_capture() -> void:
    _capture_queue.append({"kind": "planet", "index": _selected_index, "tag": _planet_tag(_selected_index)})


func _queue_all_captures(auto_quit := false) -> void:
    _capture_queue.clear()
    for index in _planets.size():
        _capture_queue.append({"kind": "planet", "index": index, "tag": _planet_tag(index)})
    _capture_queue.append({"kind": "ship", "day": true, "fast": false, "tag": "ship_day"})
    _capture_queue.append({"kind": "ship", "day": false, "fast": false, "tag": "ship_night"})
    _capture_queue.append({"kind": "ship", "day": true, "fast": true, "tag": "ship_day_fast"})
    _auto_capture = auto_quit


func _planet_tag(index: int) -> String:
    return "planet_%02d_%s" % [index + 1, String(_planets[index].name).to_lower().replace(" ", "_")]


func _process_capture_queue() -> void:
    if _capture_item.is_empty():
        if _capture_queue.is_empty() or not _all_planets_ready():
            return
        _capture_item = _capture_queue.pop_front()
        _apply_capture_item(_capture_item)
        _capture_wait_frames = capture_warmup_frames
        return
    if _capture_wait_frames > 0:
        _capture_wait_frames -= 1
        return
    if _capture_wait_frames == 0:
        _capture_wait_frames = -1
        var tag := String(_capture_item.tag)
        RenderingServer.frame_post_draw.connect(Callable(self, "_save_capture").bind(tag), CONNECT_ONE_SHOT)


func _apply_capture_item(item: Dictionary) -> void:
    var kind := String(item.kind)
    if kind == "planet":
        _selected_index = int(item.index)
        _cockpit_mode = false
        _apply_gallery_camera()
        return
    _cockpit_mode = true
    var terra := _planet_by_name("Terra")
    for planet in _planets:
        planet.visible = planet == terra
    _ship_day = bool(item.day)
    _set_fast_mode(bool(item.fast))
    _place_ship()
    _camera.current = false
    var cockpit_camera: Camera3D = _ship.get("cockpit_cam")
    cockpit_camera.current = true


func _all_planets_ready() -> bool:
    if _planets.size() != SOLAR_SYSTEM_MANIFEST.get_entries().size():
        return false
    for planet in _planets:
        if not planet.has_method("is_boot_ready") or not bool(planet.call("is_boot_ready")):
            return false
        if not String(planet.call("get_generator_error")).is_empty():
            return false
    return true


func _save_capture(tag: String) -> void:
    var directory := ProjectSettings.globalize_path(capture_directory)
    DirAccess.make_dir_recursive_absolute(directory)
    var path := "%s/%s.png" % [directory, tag]
    var image := get_viewport().get_texture().get_image()
    var error := image.save_png(path)
    if error != OK:
        push_error("Capture failed for %s: %s" % [tag, error_string(error)])
    else:
        print("SHOT %s saved: %s" % [tag, path])
    _capture_item.clear()
    if _capture_queue.is_empty() and _auto_capture:
        print("PROBE DONE")
        get_tree().quit()
