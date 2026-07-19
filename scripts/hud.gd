extends CanvasLayer

class NavigationOverlay extends Control:
	var hud: CanvasLayer


	func _process(_delta: float) -> void:
		queue_redraw()


	func _draw() -> void:
		hud.draw_navigation(self)


var ship: RigidBody3D = null
var tracked_ship: RigidBody3D = null
var prompt_label: Label
var info_label: Label
var hint_label: Label
var teleport_root: Control
var teleport_panel: PanelContainer
var teleport_menu: OptionButton
var navigation_overlay: NavigationOverlay
var planet_markers_visible := false
var celestial_bodies: Array[Node3D] = []
var gravity_debug_visible := false

const HINT_FOOT := "WASD walk/jetpack · Space/Shift ascend/descend · X brake · E interact · Tab markers · R respawn"
const HINT_SHIP := "WASD thrust · Space/Shift up/down · Mouse steer · Z/C roll · X brake · Tab markers · E exit"
const MARKER_MARGIN := 42.0
const SHIP_COLOR := Color(0.35, 0.85, 1.0, 0.9)
const PLANET_COLOR := Color(1.0, 0.82, 0.42, 0.82)
const GRAVITY_COLORS := [
	Color(1.0, 0.4, 0.3, 0.9),
	Color(0.4, 0.85, 1.0, 0.9),
	Color(0.65, 1.0, 0.45, 0.9),
	Color(0.9, 0.55, 1.0, 0.9),
	Color(1.0, 0.78, 0.3, 0.9),
]


func _ready() -> void:
	add_to_group("hud")
	tracked_ship = get_parent().get("ship")
	for body in get_tree().get_nodes_in_group("celestial_body"):
		if body is Node3D:
			celestial_bodies.append(body)
	_build_navigation_overlay()

	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.add_theme_font_size_override("font_size", 22)
	add_child(crosshair)

	prompt_label = Label.new()
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position.y -= 120
	prompt_label.add_theme_font_size_override("font_size", 20)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(prompt_label)

	info_label = Label.new()
	info_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	info_label.position = Vector2(16, 16)
	info_label.add_theme_font_size_override("font_size", 18)
	add_child(info_label)

	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position.y -= 40
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_label.modulate = Color(1, 1, 1, 0.5)
	hint_label.text = HINT_FOOT
	add_child(hint_label)
	_build_teleport_menu()
	_build_gravity_debug_panel()
	get_viewport().size_changed.connect(_layout_teleport_menu)
	_layout_teleport_menu.call_deferred()


func _build_navigation_overlay() -> void:
	navigation_overlay = NavigationOverlay.new()
	navigation_overlay.name = "NavigationOverlay"
	navigation_overlay.hud = self
	navigation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	navigation_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(navigation_overlay)


func _build_teleport_menu() -> void:
	teleport_root = Control.new()
	teleport_root.name = "PlanetTeleportRoot"
	teleport_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(teleport_root)
	teleport_panel = PanelContainer.new()
	teleport_panel.name = "PlanetTeleportPanel"
	teleport_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	teleport_panel.offset_left = -220.0
	teleport_panel.offset_top = 16.0
	teleport_panel.offset_right = -16.0
	teleport_panel.offset_bottom = 56.0
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Teleport to"
	row.add_child(label)
	teleport_menu = OptionButton.new()
	teleport_menu.name = "PlanetTeleportMenu"
	for body in celestial_bodies:
		if not body.has_method("get_surface_radius_towards"):
			continue
		teleport_menu.add_item(body.name)
		teleport_menu.set_item_metadata(teleport_menu.item_count - 1, StringName(body.name))
	teleport_menu.item_selected.connect(_on_planet_selected)
	row.add_child(teleport_menu)
	teleport_panel.add_child(row)
	teleport_root.add_child(teleport_panel)


func _build_gravity_debug_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "GravityDebugPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -330.0
	panel.offset_top = 68.0
	panel.offset_right = -16.0
	panel.modulate.a = 0.82
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = "DEBUG"
	title.add_theme_font_size_override("font_size", 11)
	title.modulate = Color(1.0, 1.0, 1.0, 0.65)
	content.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var gravity_button := Button.new()
	gravity_button.name = "GravityDebugToggle"
	gravity_button.text = "Show Gravity"
	gravity_button.toggle_mode = true
	gravity_button.focus_mode = Control.FOCUS_NONE
	gravity_button.add_theme_font_size_override("font_size", 11)
	gravity_button.toggled.connect(_on_gravity_debug_toggled)
	grid.add_child(gravity_button)
	var orbit_button := Button.new()
	orbit_button.name = "OrbitFastForwardToggle"
	orbit_button.text = "Toggle Fast Forward"
	orbit_button.toggle_mode = true
	orbit_button.focus_mode = Control.FOCUS_NONE
	orbit_button.add_theme_font_size_override("font_size", 11)
	orbit_button.toggled.connect(_on_orbit_fast_forward_toggled)
	grid.add_child(orbit_button)
	content.add_child(grid)
	panel.add_child(content)
	teleport_root.add_child(panel)


func _on_gravity_debug_toggled(enabled: bool) -> void:
	gravity_debug_visible = enabled


func _on_orbit_fast_forward_toggled(enabled: bool) -> void:
	var celestial_system := get_tree().get_first_node_in_group("celestial_system")
	if celestial_system != null:
		celestial_system.set_fast_forward_enabled(enabled)


func _layout_teleport_menu() -> void:
	if teleport_root == null:
		return
	teleport_root.position = Vector2.ZERO
	teleport_root.size = get_viewport().get_visible_rect().size
	if navigation_overlay != null:
		navigation_overlay.size = teleport_root.size


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB or event.physical_keycode == KEY_TAB:
			planet_markers_visible = not planet_markers_visible
			get_viewport().set_input_as_handled()


func _on_planet_selected(index: int) -> void:
	var main := get_parent()
	if main.has_method("spawn_on_planet_named"):
		main.spawn_on_planet_named(teleport_menu.get_item_metadata(index))
	teleport_menu.release_focus()


func set_selected_planet(body_name: StringName) -> void:
	for index in teleport_menu.item_count:
		if teleport_menu.get_item_metadata(index) == body_name:
			teleport_menu.select(index)
			return


func _process(_delta: float) -> void:
	if ship == null:
		info_label.text = ""
		return
	var speed := ship.linear_velocity.length()
	var altitude: float = Gravity.get_altitude(ship.global_position)
	var text := "Speed: %.1f m/s" % speed
	if altitude >= 0.0:
		text += "\nAltitude: %.0f m" % altitude
	info_label.text = text


func draw_navigation(canvas: Control) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	if is_instance_valid(tracked_ship):
		_draw_marker(canvas, camera, tracked_ship.global_position, "SHIP", SHIP_COLOR)
	for body in celestial_bodies:
		if not is_instance_valid(body):
			continue
		if planet_markers_visible or gravity_debug_visible and _has_active_gravity(body, camera.global_position):
			_draw_marker(canvas, camera, body.global_position, body.name, PLANET_COLOR)
	_draw_gravity_debug(canvas, camera)


func _draw_marker(canvas: Control, camera: Camera3D, world_position: Vector3, marker_name: String, color: Color) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var camera_position := camera.global_position
	var local_position := camera.to_local(world_position)
	var distance := camera_position.distance_to(world_position)
	var screen_position: Vector2
	var offscreen := camera.is_position_behind(world_position)
	if not offscreen:
		screen_position = camera.unproject_position(world_position)
		offscreen = (
			screen_position.x < MARKER_MARGIN or screen_position.x > viewport_size.x - MARKER_MARGIN
			or screen_position.y < MARKER_MARGIN or screen_position.y > viewport_size.y - MARKER_MARGIN
		)
	if offscreen:
		var direction := Vector2(local_position.x, -local_position.y)
		if local_position.z > 0.0:
			direction = -direction
		if direction.length_squared() < 0.001:
			direction = Vector2.UP
		screen_position = _clamp_to_screen(viewport_size * 0.5, direction.normalized(), viewport_size)
		_draw_chevron(canvas, screen_position, direction.normalized(), color)
	else:
		canvas.draw_arc(screen_position, 7.0, 0.0, TAU, 16, color, 1.4, true)
		canvas.draw_circle(screen_position, 1.8, color)
	var label := "%s  %s" % [marker_name, _format_distance(distance)]
	var label_position := screen_position + Vector2(11.0, -8.0)
	if label_position.x + label.length() * 7.0 > viewport_size.x - 8.0:
		label_position.x = screen_position.x - label.length() * 7.0 - 11.0
	canvas.draw_string(ThemeDB.fallback_font, label_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, color)


func _clamp_to_screen(center: Vector2, direction: Vector2, viewport_size: Vector2) -> Vector2:
	var limits := viewport_size * 0.5 - Vector2.ONE * MARKER_MARGIN
	var scale := minf(
		limits.x / maxf(absf(direction.x), 0.001),
		limits.y / maxf(absf(direction.y), 0.001)
	)
	return center + direction * scale


func _draw_chevron(canvas: Control, position_value: Vector2, direction: Vector2, color: Color) -> void:
	var side := direction.rotated(PI * 0.5)
	var tip := position_value + direction * 7.0
	var tail := position_value - direction * 6.0
	canvas.draw_polyline(PackedVector2Array([tail + side * 5.0, tip, tail - side * 5.0]), color, 1.5, true)


func _draw_gravity_debug(canvas: Control, camera: Camera3D) -> void:
	if not gravity_debug_visible:
		return
	var origin := get_viewport().get_visible_rect().size * 0.5
	var observer_position := camera.global_position
	var color_index := 0
	for body in celestial_bodies:
		if not is_instance_valid(body):
			continue
		var acceleration: Vector3 = Gravity.get_gravity_from(body, observer_position)
		if acceleration.length_squared() <= 0.0:
			continue
		var color: Color = GRAVITY_COLORS[color_index % GRAVITY_COLORS.size()]
		color_index += 1
		var camera_acceleration := camera.global_basis.inverse() * acceleration
		var direction := Vector2(camera_acceleration.x, -camera_acceleration.y)
		if direction.length_squared() < 0.0001:
			direction = Vector2.UP
		direction = direction.normalized()
		var length := clampf(42.0 + log(1.0 + acceleration.length()) * 20.0, 42.0, 105.0)
		var start := origin + direction.rotated(PI * 0.5) * float(color_index - 1) * 8.0
		var end := start + direction * length
		canvas.draw_line(start, end, color, 2.0, true)
		_draw_chevron(canvas, end, direction, color)
		var text := "%s  %.3f m/s²" % [body.name, acceleration.length()]
		canvas.draw_string(ThemeDB.fallback_font, end + Vector2(9.0, -7.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, color)


func _has_active_gravity(body: Node3D, observer_position: Vector3) -> bool:
	return Gravity.get_gravity_from(body, observer_position).length_squared() > 0.0


func _format_distance(distance: float) -> String:
	if distance >= 1000.0:
		return "%.1f km" % (distance / 1000.0)
	return "%.0f m" % distance


func set_prompt(text: String) -> void:
	prompt_label.text = text


func set_ship(value: RigidBody3D) -> void:
	ship = value
	hint_label.text = HINT_SHIP if ship else HINT_FOOT
	if ship:
		prompt_label.text = ""
