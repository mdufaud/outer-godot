extends CanvasLayer

const BonificationMathScript := preload("res://game/shared/bonification_math.gd")
const HudGlobeScript := preload("res://game/hud/hud_globe.gd")
const GravityServiceScript := preload("res://game/celestial/gravity.gd")
const TouchServiceScript := preload("res://game/input/touch.gd")

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
var teleport_menu: Button
var teleport_dropdown: PanelContainer
var planet_buttons: Array[Button] = []
var debug_buttons: Array[Button] = []
var gravity_button: Button
var orbit_button: Button
var supernova_button: Button
var navigation_overlay: NavigationOverlay
var globe: Control
var planet_markers_visible := false
var celestial_bodies: Array[Node3D] = []
var gravity_debug_visible := false
var _dropdown_open := false
var _selected_planet_name := ""
var locked_body: Node3D
var aimed_body: Node3D
var ui_scale := 1.0
@onready var gravity_service: GravityService = get_node("/root/Gravity")
@onready var touch_service: TouchService = get_node("/root/Touch")

const HINT_FOOT := "Left stick move · Right stick look · A jump · LT sprint/descend · B brake · X interact · View map · Y respawn"
const HINT_SHIP := "Left stick thrust · Right stick steer · A/LT up/down · RT/B brake · LB/RB roll · R3 lock · Menu/View map · X exit"
const MARKER_MARGIN := 42.0
const SHIP_COLOR := Color(0.35, 0.85, 1.0, 0.9)
const PLANET_COLOR := Color(1.0, 0.82, 0.42, 0.82)
const UI_PANEL_COLOR := Color(0.025, 0.045, 0.10, 0.94)
const UI_BORDER_COLOR := Color(0.22, 0.55, 0.86, 0.65)
const UI_ACCENT_COLOR := Color(0.35, 0.82, 1.0)
const TARGET_COLOR := Color(0.35, 0.92, 1.0, 0.95)
const AIM_COLOR := Color(1.0, 0.82, 0.38, 0.75)
const LOCK_ANGLE := deg_to_rad(30.0)
const GRAVITY_COLORS := [
	Color(1.0, 0.4, 0.3, 0.9),
	Color(0.4, 0.85, 1.0, 0.9),
	Color(0.65, 1.0, 0.45, 0.9),
	Color(0.9, 0.55, 1.0, 0.9),
	Color(1.0, 0.78, 0.3, 0.9),
]


func _ready() -> void:
	add_to_group("hud")
	ui_scale = touch_service.ui_scale(get_viewport().get_visible_rect().size)
	tracked_ship = get_parent().get("ship")
	for body in get_tree().get_nodes_in_group("celestial_body"):
		if body is Node3D:
			celestial_bodies.append(body)
	_build_navigation_overlay()
	_build_globe()

	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.add_theme_font_size_override("font_size", _px(22))
	add_child(crosshair)

	prompt_label = Label.new()
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position.y -= 120.0 * ui_scale
	prompt_label.add_theme_font_size_override("font_size", _px(20))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(prompt_label)

	info_label = Label.new()
	info_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	info_label.position = Vector2(16, 16) * ui_scale
	info_label.add_theme_font_size_override("font_size", _px(18))
	add_child(info_label)

	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position.y -= 40
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_label.modulate = Color(1, 1, 1, 0.5)
	hint_label.text = HINT_FOOT
	hint_label.visible = not touch_service.is_touch_ui()
	add_child(hint_label)
	_build_teleport_menu()
	_build_gravity_debug_panel()
	get_viewport().size_changed.connect(layout_panels)
	layout_panels.call_deferred()


func _px(value: float) -> int:
	return int(roundf(value * ui_scale))


func _build_navigation_overlay() -> void:
	navigation_overlay = NavigationOverlay.new()
	navigation_overlay.name = "NavigationOverlay"
	navigation_overlay.hud = self
	navigation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	navigation_overlay.position = Vector2.ZERO
	navigation_overlay.size = get_viewport().get_visible_rect().size
	add_child(navigation_overlay)


func _build_globe() -> void:
	globe = HudGlobeScript.new()
	globe.name = "HudGlobe"
	globe.hud = self
	globe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(globe)


func _build_teleport_menu() -> void:
	teleport_root = Control.new()
	teleport_root.name = "PlanetTeleportRoot"
	teleport_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(teleport_root)
	teleport_panel = PanelContainer.new()
	teleport_panel.name = "PlanetTeleportPanel"
	teleport_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	teleport_panel.z_index = 10
	teleport_panel.add_theme_stylebox_override("panel", _panel_style())
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", _px(6))
	var title := Label.new()
	title.text = "PLANET NAVIGATION"
	title.add_theme_font_size_override("font_size", _px(11))
	title.add_theme_color_override("font_color", Color(0.62, 0.78, 0.95))
	content.add_child(title)
	var label := Label.new()
	label.text = "Teleport to planet"
	label.add_theme_font_size_override("font_size", _px(14))
	content.add_child(label)
	teleport_menu = Button.new()
	teleport_menu.name = "PlanetTeleportMenu"
	teleport_menu.text = "Choose planet"
	teleport_menu.custom_minimum_size = Vector2(0.0, 40.0 * ui_scale)
	teleport_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	teleport_menu.focus_mode = Control.FOCUS_NONE
	teleport_menu.add_theme_font_size_override("font_size", _px(14))
	_apply_button_theme(teleport_menu, UI_ACCENT_COLOR)
	_make_ui_button(teleport_menu)
	teleport_menu.pressed.connect(_toggle_planet_dropdown)
	content.add_child(teleport_menu)
	teleport_panel.add_child(content)
	teleport_root.add_child(teleport_panel)

	teleport_dropdown = PanelContainer.new()
	teleport_dropdown.name = "PlanetTeleportDropdown"
	teleport_dropdown.mouse_filter = Control.MOUSE_FILTER_PASS
	teleport_dropdown.z_index = 20
	teleport_dropdown.add_theme_stylebox_override("panel", _panel_style())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.name = "PlanetList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", _px(5))
	planet_buttons.clear()
	for body in celestial_bodies:
		if not body.has_method("get_surface_radius_towards"):
			continue
		var planet_button := Button.new()
		planet_button.name = "%sButton" % body.name.replace(" ", "")
		planet_button.text = body.name
		planet_button.custom_minimum_size = Vector2(0.0, 42.0 * ui_scale)
		planet_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		planet_button.toggle_mode = true
		planet_button.focus_mode = Control.FOCUS_NONE
		planet_button.add_theme_font_size_override("font_size", _px(14))
		_apply_button_theme(planet_button, Color(0.45, 0.72, 1.0))
		_make_ui_button(planet_button)
		planet_button.pressed.connect(_on_planet_selected.bind(StringName(body.name)))
		list.add_child(planet_button)
		planet_buttons.append(planet_button)
	scroll.add_child(list)
	teleport_dropdown.add_child(scroll)
	teleport_root.add_child(teleport_dropdown)
	teleport_dropdown.visible = false


func _build_gravity_debug_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "GravityDebugPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", _panel_style())
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", _px(7))
	var title := Label.new()
	title.text = "DEBUG TOOLS"
	title.add_theme_font_size_override("font_size", _px(11))
	title.add_theme_color_override("font_color", Color(0.62, 0.78, 0.95))
	content.add_child(title)
	var buttons := GridContainer.new()
	buttons.columns = 2
	buttons.add_theme_constant_override("h_separation", _px(6))
	buttons.add_theme_constant_override("v_separation", _px(5))
	gravity_button = Button.new()
	gravity_button.name = "GravityDebugToggle"
	gravity_button.text = "Gravity: OFF"
	gravity_button.toggle_mode = true
	gravity_button.custom_minimum_size = Vector2(0.0, 38.0 * ui_scale)
	gravity_button.focus_mode = Control.FOCUS_NONE
	gravity_button.add_theme_font_size_override("font_size", _px(13))
	_apply_button_theme(gravity_button, Color(1.0, 0.50, 0.36))
	_make_ui_button(gravity_button)
	gravity_button.toggled.connect(_on_gravity_debug_toggled)
	buttons.add_child(gravity_button)
	orbit_button = Button.new()
	orbit_button.name = "OrbitFastForwardToggle"
	orbit_button.text = "Fast time: OFF"
	orbit_button.toggle_mode = true
	orbit_button.custom_minimum_size = Vector2(0.0, 38.0 * ui_scale)
	orbit_button.focus_mode = Control.FOCUS_NONE
	orbit_button.add_theme_font_size_override("font_size", _px(13))
	_apply_button_theme(orbit_button, Color(0.55, 0.78, 1.0))
	_make_ui_button(orbit_button)
	orbit_button.toggled.connect(_on_orbit_fast_forward_toggled)
	buttons.add_child(orbit_button)
	supernova_button = Button.new()
	supernova_button.name = "SupernovaTrigger"
	supernova_button.text = "Supernova"
	supernova_button.custom_minimum_size = Vector2(0.0, 38.0 * ui_scale)
	supernova_button.focus_mode = Control.FOCUS_NONE
	supernova_button.add_theme_font_size_override("font_size", _px(13))
	_apply_button_theme(supernova_button, Color(1.0, 0.35, 0.25))
	_make_ui_button(supernova_button)
	supernova_button.pressed.connect(_on_supernova_pressed)
	buttons.add_child(supernova_button)
	content.add_child(buttons)
	panel.add_child(content)
	teleport_root.add_child(panel)
	debug_buttons = [gravity_button, orbit_button, supernova_button]


func _on_gravity_debug_toggled(enabled: bool) -> void:
	gravity_debug_visible = enabled
	if gravity_button != null:
		gravity_button.text = "Gravity: ON" if enabled else "Gravity: OFF"


func _on_orbit_fast_forward_toggled(enabled: bool) -> void:
	if orbit_button != null:
		orbit_button.text = "Fast time: ON" if enabled else "Fast time: OFF"
	var celestial_system := get_tree().get_first_node_in_group("celestial_system")
	if celestial_system != null:
		celestial_system.set_fast_forward_enabled(enabled)


func _on_supernova_pressed() -> void:
	var sun := get_tree().get_first_node_in_group("sun")
	if sun != null and sun.has_method("detonate"):
		sun.detonate()


func layout_panels() -> void:
	if teleport_root == null:
		return
	teleport_root.position = Vector2.ZERO
	teleport_root.size = get_viewport().get_visible_rect().size
	if navigation_overlay != null:
		navigation_overlay.size = teleport_root.size
	var viewport_size := teleport_root.size
	var margin := 16.0 * ui_scale
	if globe != null:
		globe.size = Vector2(180.0, 190.0) * ui_scale
		globe.position = Vector2(margin, viewport_size.y - globe.size.y - margin)
	var width := clampf(viewport_size.x * 0.22, 236.0 * ui_scale, 286.0 * ui_scale)
	width = minf(width, maxf(216.0, viewport_size.x - margin * 2.0))
	teleport_panel.anchor_left = 1.0
	teleport_panel.anchor_right = 1.0
	teleport_panel.anchor_top = 0.0
	teleport_panel.anchor_bottom = 0.0
	teleport_panel.offset_left = -width - margin
	teleport_panel.offset_top = margin
	teleport_panel.offset_right = -margin
	teleport_panel.offset_bottom = margin + teleport_panel.get_combined_minimum_size().y
	var debug_top := teleport_panel.offset_bottom + 12.0 * ui_scale
	var debug_panel := teleport_root.get_node_or_null("GravityDebugPanel") as PanelContainer
	if debug_panel != null:
		debug_panel.anchor_left = 1.0
		debug_panel.anchor_right = 1.0
		debug_panel.anchor_top = 0.0
		debug_panel.anchor_bottom = 0.0
		debug_panel.offset_left = -width - margin
		debug_panel.offset_top = debug_top
		debug_panel.offset_right = -margin
		debug_panel.offset_bottom = debug_top + debug_panel.get_combined_minimum_size().y
	if teleport_dropdown != null:
		teleport_dropdown.anchor_left = 1.0
		teleport_dropdown.anchor_right = 1.0
		teleport_dropdown.anchor_top = 0.0
		teleport_dropdown.anchor_bottom = 0.0
		teleport_dropdown.offset_left = -width - margin
		teleport_dropdown.offset_top = debug_top
		teleport_dropdown.offset_right = -margin
		var wanted := minf(370.0 * ui_scale, maxf(176.0 * ui_scale, viewport_size.y * 0.52))
		teleport_dropdown.offset_bottom = minf(teleport_dropdown.offset_top + wanted, _panel_bottom_limit(viewport_size, margin))


# Keep panels from growing under the on-screen touch controls.
func _panel_bottom_limit(viewport_size: Vector2, margin: float) -> float:
	var limit := viewport_size.y - margin
	var touch_hud := get_tree().get_first_node_in_group("touch_hud")
	if touch_hud != null and touch_hud.has_method("controls_top"):
		limit = minf(limit, touch_hud.controls_top() - margin)
	return limit


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and _handle_touch_ui(event.position):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("map") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_TAB or event.physical_keycode == KEY_TAB)):
		planet_markers_visible = not planet_markers_visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("lock_target") or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		if ship == null:
			return
		var over_ui := event is InputEventMouseButton and is_mouse_over_ui(event.position)
		if not over_ui:
			locked_body = null if locked_body == aimed_body else aimed_body
			get_viewport().set_input_as_handled()


func _on_planet_selected(body_name: StringName) -> void:
	var main := get_parent()
	if main.has_method("spawn_on_planet_id"):
		main.spawn_on_planet_id(body_name)
	set_selected_planet(body_name)
	_dropdown_open = true
	teleport_dropdown.visible = true


func _toggle_planet_dropdown() -> void:
	_set_planet_dropdown_open(not _dropdown_open)


func _set_planet_dropdown_open(open: bool) -> void:
	_dropdown_open = open
	teleport_dropdown.visible = open
	teleport_menu.text = "Hide planets" if open else "Choose planet"


func _handle_touch_ui(position_value: Vector2) -> bool:
	if teleport_menu != null and teleport_menu.get_global_rect().has_point(position_value):
		_toggle_planet_dropdown()
		return true
	if _dropdown_open:
		for button in planet_buttons:
			if button.get_global_rect().has_point(position_value):
				_on_planet_selected(StringName(button.text))
				return true
		if teleport_dropdown.get_global_rect().has_point(position_value):
			return true
	if gravity_button != null and gravity_button.get_global_rect().has_point(position_value):
		gravity_button.set_pressed_no_signal(not gravity_button.button_pressed)
		_on_gravity_debug_toggled(gravity_button.button_pressed)
		return true
	if orbit_button != null and orbit_button.get_global_rect().has_point(position_value):
		orbit_button.set_pressed_no_signal(not orbit_button.button_pressed)
		_on_orbit_fast_forward_toggled(orbit_button.button_pressed)
		return true
	if supernova_button != null and supernova_button.get_global_rect().has_point(position_value):
		_on_supernova_pressed()
		return true
	return false


func set_selected_planet(body_name: StringName) -> void:
	_selected_planet_name = String(body_name)
	if teleport_menu != null:
		teleport_menu.text = "Hide planets" if _dropdown_open else "Choose planet"
	for button in planet_buttons:
		button.set_pressed_no_signal(button.text == _selected_planet_name)


func is_touch_over_ui(position_value: Vector2) -> bool:
	if teleport_menu != null and teleport_menu.get_global_rect().has_point(position_value):
		return true
	if _dropdown_open and teleport_dropdown != null and teleport_dropdown.get_global_rect().has_point(position_value):
		return true
	for button in debug_buttons:
		if button.get_global_rect().has_point(position_value):
			return true
	return false


func is_mouse_over_ui(position_value: Vector2) -> bool:
	return is_touch_over_ui(position_value)


func _process(_delta: float) -> void:
	if ship == null:
		info_label.text = ""
		aimed_body = null
		locked_body = null
		return
	var camera := get_viewport().get_camera_3d()
	aimed_body = find_aimed_body(camera, celestial_bodies) if camera != null else null
	var speed := ship.linear_velocity.length()
	var altitude: float = gravity_service.get_altitude(ship.global_position)
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
	if aimed_body != null and aimed_body != locked_body:
		_draw_target(canvas, camera, aimed_body, false)
	if locked_body != null and is_instance_valid(locked_body):
		_draw_target(canvas, camera, locked_body, true)


func _draw_marker(canvas: Control, camera: Camera3D, world_position: Vector3, marker_name: String, color: Color) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var camera_position := camera.global_position
	var local_position := camera.to_local(world_position)
	var distance := camera_position.distance_to(world_position)
	var screen_position: Vector2
	var margin := MARKER_MARGIN * ui_scale
	var offscreen := camera.is_position_behind(world_position)
	if not offscreen:
		screen_position = camera.unproject_position(world_position)
		offscreen = (
			screen_position.x < margin or screen_position.x > viewport_size.x - margin
			or screen_position.y < margin or screen_position.y > viewport_size.y - margin
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
		canvas.draw_arc(screen_position, 7.0 * ui_scale, 0.0, TAU, 16, color, 1.4 * ui_scale, true)
		canvas.draw_circle(screen_position, 1.8 * ui_scale, color)
	var label := "%s  %s" % [marker_name, _format_distance(distance)]
	var label_width := label.length() * 7.0 * ui_scale
	var label_position := screen_position + Vector2(11.0, -8.0) * ui_scale
	if label_position.x + label_width > viewport_size.x - 8.0 * ui_scale:
		label_position.x = screen_position.x - label_width - 11.0 * ui_scale
	canvas.draw_string(ThemeDB.fallback_font, label_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _px(13), color)


func _clamp_to_screen(center: Vector2, direction: Vector2, viewport_size: Vector2) -> Vector2:
	var limits := viewport_size * 0.5 - Vector2.ONE * MARKER_MARGIN * ui_scale
	var scale := minf(
		limits.x / maxf(absf(direction.x), 0.001),
		limits.y / maxf(absf(direction.y), 0.001)
	)
	return center + direction * scale


func _draw_chevron(canvas: Control, position_value: Vector2, direction: Vector2, color: Color) -> void:
	var side := direction.rotated(PI * 0.5)
	var tip := position_value + direction * 7.0 * ui_scale
	var tail := position_value - direction * 6.0 * ui_scale
	canvas.draw_polyline(PackedVector2Array([tail + side * 5.0 * ui_scale, tip, tail - side * 5.0 * ui_scale]), color, 1.5 * ui_scale, true)


func _draw_gravity_debug(canvas: Control, camera: Camera3D) -> void:
	if not gravity_debug_visible:
		return
	var origin := get_viewport().get_visible_rect().size * 0.5
	var observer_position := camera.global_position
	var color_index := 0
	for body in celestial_bodies:
		if not is_instance_valid(body):
			continue
		var acceleration: Vector3 = gravity_service.get_gravity_from(body, observer_position)
		if acceleration.length_squared() <= 0.0:
			continue
		var color: Color = GRAVITY_COLORS[color_index % GRAVITY_COLORS.size()]
		color_index += 1
		var camera_acceleration := camera.global_basis.inverse() * acceleration
		var direction := Vector2(camera_acceleration.x, -camera_acceleration.y)
		if direction.length_squared() < 0.0001:
			direction = Vector2.UP
		direction = direction.normalized()
		var length := clampf(42.0 + log(1.0 + acceleration.length()) * 20.0, 42.0, 105.0) * ui_scale
		var start := origin + direction.rotated(PI * 0.5) * float(color_index - 1) * 8.0 * ui_scale
		var end := start + direction * length
		canvas.draw_line(start, end, color, 2.0 * ui_scale, true)
		_draw_chevron(canvas, end, direction, color)
		var text := "%s  %.3f m/s²" % [body.name, acceleration.length()]
		canvas.draw_string(ThemeDB.fallback_font, end + Vector2(9.0, -7.0) * ui_scale, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _px(12), color)


func _draw_target(canvas: Control, camera: Camera3D, body: Node3D, locked: bool) -> void:
	if camera.is_position_behind(body.global_position):
		return
	var center := camera.unproject_position(body.global_position)
	var radius := float(body.get("radius"))
	var edge := camera.unproject_position(body.global_position + camera.global_basis.x * radius)
	var ring_radius := clampf(center.distance_to(edge) * (1.12 if locked else 1.06), 13.0 * ui_scale, 260.0 * ui_scale)
	var color := TARGET_COLOR if locked else AIM_COLOR
	canvas.draw_arc(center, ring_radius, 0.0, TAU, 48, color, (2.2 if locked else 1.2) * ui_scale, true)
	if ship == null:
		return
	var direction := (body.global_position - camera.global_position).normalized()
	var surface_radius := radius
	if body.has_method("get_surface_radius_towards"):
		surface_radius = float(body.get_surface_radius_towards(-direction))
	var surface_distance := maxf(camera.global_position.distance_to(body.global_position) - surface_radius, 0.0)
	var relative := relative_velocity_components(ship.linear_velocity, body.get("orbital_velocity"), direction, camera.global_basis.y, camera.global_basis.x)
	var target_state := "LOCKED" if locked else "TARGET"
	var label := "%s  %s\nSurface %s\nApproach %+.1f m/s" % [body.name, target_state, _format_distance(surface_distance), relative.z]
	canvas.draw_multiline_string(ThemeDB.fallback_font, center + Vector2(ring_radius + 12.0 * ui_scale, -8.0 * ui_scale), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _px(14), -1, color)
	_draw_velocity_indicator(canvas, center, ring_radius, Vector2.RIGHT, relative.x, color)
	_draw_velocity_indicator(canvas, center, ring_radius, Vector2.UP, relative.y, color)


func _draw_velocity_indicator(canvas: Control, center: Vector2, ring_radius: float, axis: Vector2, velocity: float, color: Color) -> void:
	if absf(velocity) < 0.15 or color.a <= 0.01:
		return
	var direction := axis * signf(velocity)
	var start := center + direction * ring_radius
	var length := clampf(absf(velocity) * 0.75, 10.0, 170.0) * ui_scale
	var end := start + direction * length
	canvas.draw_line(start, end, color, 2.4 * ui_scale, true)
	_draw_chevron(canvas, end, direction, color)


static func relative_velocity_components(ship_velocity: Vector3, body_velocity: Vector3, direction_to_body: Vector3, camera_up: Vector3, camera_right: Vector3) -> Vector3:
	return BonificationMathScript.relative_velocity_components(ship_velocity, body_velocity, direction_to_body, camera_up, camera_right)


static func ray_sphere_distance(center: Vector3, radius: float, origin: Vector3, direction: Vector3) -> float:
	return BonificationMathScript.ray_sphere_distance(center, radius, origin, direction)


static func find_aimed_body(camera: Camera3D, bodies: Array[Node3D]) -> Node3D:
	var best: Node3D
	var nearest := INF
	var direction := -camera.global_basis.z
	for body in bodies:
		if not is_instance_valid(body):
			continue
		var hit := ray_sphere_distance(body.global_position, float(body.get("radius")), camera.global_position, direction)
		if hit < nearest:
			nearest = hit
			best = body
	if best != null:
		return best
	var best_angle := LOCK_ANGLE
	for body in bodies:
		if not is_instance_valid(body):
			continue
		var offset := body.global_position - camera.global_position
		if offset.length_squared() < 0.0001:
			continue
		var angle := direction.angle_to(offset)
		if angle < best_angle:
			best_angle = angle
			best = body
	return best


func _has_active_gravity(body: Node3D, observer_position: Vector3) -> bool:
	return gravity_service.get_gravity_from(body, observer_position).length_squared() > 0.0


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
	else:
		locked_body = null
		aimed_body = null


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI_PANEL_COLOR
	style.border_color = UI_BORDER_COLOR
	style.set_border_width_all(_px(1))
	style.set_corner_radius_all(_px(12))
	style.content_margin_left = 12.0 * ui_scale
	style.content_margin_top = 10.0 * ui_scale
	style.content_margin_right = 12.0 * ui_scale
	style.content_margin_bottom = 10.0 * ui_scale
	return style


func _apply_button_theme(button: Button, accent: Color) -> void:
	button.add_theme_stylebox_override("normal", _button_style(Color(0.05, 0.10, 0.20, 0.94), accent.darkened(0.25), 0.5))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.10, 0.20, 0.34, 0.98), accent, 0.85))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.16, 0.32, 0.48, 1.0), accent.lightened(0.1), 1.0))
	button.add_theme_stylebox_override("focus", _button_style(Color(0.10, 0.20, 0.34, 0.98), accent, 0.95))
	button.add_theme_color_override("font_color", Color(0.88, 0.95, 1.0))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)


func _make_ui_button(button: Button) -> void:
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.gui_input.connect(_consume_ui_pointer.bind(button))


func _consume_ui_pointer(event: InputEvent, button: Button) -> void:
	if event is InputEventMouseButton:
		button.accept_event()


func _button_style(fill: Color, border: Color, border_alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(border, border_alpha)
	style.set_border_width_all(_px(1))
	style.set_corner_radius_all(_px(9))
	style.content_margin_left = 10.0 * ui_scale
	style.content_margin_top = 7.0 * ui_scale
	style.content_margin_right = 10.0 * ui_scale
	style.content_margin_bottom = 7.0 * ui_scale
	return style
