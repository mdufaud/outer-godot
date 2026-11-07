class_name Hud
extends CanvasLayer

const HudGlobeScript := preload("res://game/hud/hud_globe.gd")

class NavigationOverlay extends Control:
	var hud: Hud


	func _process(_delta: float) -> void:
		queue_redraw()


	func _draw() -> void:
		hud.draw_navigation(self)


class Marker extends RefCounted:
	var label: String
	var position: Vector2
	var distance: float
	var color: Color
	var direction := Vector2.ZERO


const TEXT_COLOR := Color(0.90, 0.96, 1.0)
const MUTED_COLOR := Color(0.60, 0.72, 0.84)
const ACCENT_COLOR := Color(0.42, 0.86, 1.0)
const DANGER_COLOR := Color(1.0, 0.42, 0.32)
const PANEL_COLOR := Color(0.02, 0.04, 0.08, 0.74)
const SHIP_COLOR := Color(0.35, 0.85, 1.0, 0.9)
const PLANET_COLOR := Color(1.0, 0.82, 0.42, 0.85)
const TARGET_COLOR := Color(0.35, 0.92, 1.0, 0.95)
const AIM_COLOR := Color(1.0, 0.82, 0.38, 0.75)
const MARKER_MARGIN := 42.0
const LOCK_ANGLE := deg_to_rad(30.0)
const HINT_HOLD_MS := 10000
const HINT_RESTING_ALPHA := 0.35
const GRAVITY_COLORS := [
	Color(1.0, 0.4, 0.3, 0.9),
	Color(0.4, 0.85, 1.0, 0.9),
	Color(0.65, 1.0, 0.45, 0.9),
	Color(0.9, 0.55, 1.0, 0.9),
	Color(1.0, 0.78, 0.3, 0.9),
]
const FLASH_MS := 2200
const HINTS_FOOT_KEYS := [["WASD", "Move"], ["Space", "Jump · jetpack"], ["Shift", "Sprint"], ["E", "Interact"], ["T", "Call ship"], ["Tab", "Map"], ["R", "Respawn"], ["Esc", "Menu"]]
const HINTS_SHIP_KEYS := [["WASD", "Thrust"], ["Space/Ctrl", "Up · down"], ["Shift", "Boost"], ["Mouse", "Steer"], ["Z/C", "Roll"], ["X", "Brake · match"], ["LMB", "Lock"], ["T", "Autopilot"], ["V", "Camera"], ["E", "Exit"], ["Esc", "Menu"]]
const HINTS_FOOT_PAD := [["LS", "Move"], ["RS", "Look"], ["A", "Jump"], ["LT", "Sprint"], ["X", "Interact"], ["Y", "Call ship"], ["View", "Map"], ["Start", "Menu"]]
const HINTS_SHIP_PAD := [["LS", "Thrust"], ["RS", "Steer"], ["A/B", "Up · down"], ["LT", "Boost"], ["LB/RB", "Roll"], ["RT", "Brake · match"], ["R3", "Lock"], ["Y", "Autopilot"], ["L3", "Camera"], ["X", "Exit"], ["Start", "Menu"]]

var ship: Ship = null
var tracked_ship: Ship = null
var player: Player = null
var celestial_bodies: Array[CelestialBody] = []
var planet_markers_visible := false
var gravity_debug_visible := false
var locked_body: CelestialBody
var aimed_body: CelestialBody
var ui_scale := 1.0

var _root: Control
var _overlay: NavigationOverlay
var _globe: HudGlobe
var _readout: PanelContainer
var _readout_title: Label
var _readout_values: Array[Label] = []
var _readout_vertical_row: Array[Label] = []
var _readout_status: Label
var _flash: Label
var _flash_text := ""
var _flash_until := 0
var _prompt: HBoxContainer
var _prompt_key: Label
var _prompt_text: Label
var _hints_bar: PanelContainer
var _hints: HBoxContainer
var _menu: Control
var _menu_first_button: Button
var _planet_buttons: Dictionary = {}
var _fast_time_button: Button
var _gravity_button: Button
var _supernova_button: Button
var _leviathan_button: Button
var _graphics_buttons: Dictionary = {}
var _fps_label: Label
var _gamepad := false
var _prompt_action := ""
var _selected_planet: StringName = &""
var _hints_shown_at := 0
@onready var gravity_service: GravityService = get_node("/root/Gravity")
@onready var touch_service: TouchService = get_node("/root/Touch")


func _ready() -> void:
	add_to_group("hud")
	process_mode = Node.PROCESS_MODE_ALWAYS
	var main := get_parent() as Main
	if main != null:
		tracked_ship = main.ship
		player = main.player
	for body in get_tree().get_nodes_in_group("celestial_body"):
		if body is CelestialBody:
			celestial_bodies.append(body)
	_root = Control.new()
	_root.name = "HudRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_build()
	get_viewport().size_changed.connect(_rebuild)


func _rebuild() -> void:
	close_menu()
	_menu_first_button = null
	for child in _root.get_children():
		child.queue_free()
	_planet_buttons.clear()
	_graphics_buttons.clear()
	_readout_values.clear()
	_readout_vertical_row.clear()
	_build()


func _build() -> void:
	ui_scale = touch_service.ui_scale(get_viewport().get_visible_rect().size)
	_root.theme = _build_theme()
	_overlay = NavigationOverlay.new()
	_overlay.name = "NavigationOverlay"
	_overlay.hud = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_overlay)
	_globe = HudGlobeScript.new()
	_globe.name = "HudGlobe"
	_globe.hud = self
	_globe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_globe)
	_build_readout()
	_build_flash()
	_build_fps()
	_build_prompt()
	_build_hints()
	_build_menu()
	_refresh_hints()
	layout_panels()


func _px(value: float) -> int:
	return int(roundf(value * ui_scale))


func _build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = _px(14)
	theme.set_color("font_color", "Label", TEXT_COLOR)
	theme.set_stylebox("panel", "PanelContainer", _box(PANEL_COLOR, Color(ACCENT_COLOR, 0.22), 10.0, Vector2(14.0, 10.0)))
	theme.set_stylebox("normal", "Button", _box(Color(0.06, 0.12, 0.20, 0.85), Color(ACCENT_COLOR, 0.25), 8.0, Vector2(12.0, 8.0)))
	theme.set_stylebox("hover", "Button", _box(Color(0.10, 0.20, 0.32, 0.95), Color(ACCENT_COLOR, 0.7), 8.0, Vector2(12.0, 8.0)))
	theme.set_stylebox("pressed", "Button", _box(Color(0.12, 0.32, 0.46, 1.0), ACCENT_COLOR, 8.0, Vector2(12.0, 8.0)))
	theme.set_stylebox("hover_pressed", "Button", _box(Color(0.14, 0.36, 0.52, 1.0), ACCENT_COLOR, 8.0, Vector2(12.0, 8.0)))
	theme.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), Color(1.0, 1.0, 1.0, 0.9), 8.0, Vector2(12.0, 8.0), 2))
	theme.set_stylebox("disabled", "Button", _box(Color(0.04, 0.06, 0.10, 0.7), Color(MUTED_COLOR, 0.2), 8.0, Vector2(12.0, 8.0)))
	theme.set_color("font_color", "Button", TEXT_COLOR)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color(MUTED_COLOR, 0.6))
	return theme


func _box(fill: Color, border: Color, radius: float, padding: Vector2, border_width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(maxi(border_width, roundi(border_width * ui_scale)))
	style.set_corner_radius_all(_px(radius))
	style.content_margin_left = padding.x * ui_scale
	style.content_margin_right = padding.x * ui_scale
	style.content_margin_top = padding.y * ui_scale
	style.content_margin_bottom = padding.y * ui_scale
	return style


func _label(text: String, size: float, color := TEXT_COLOR) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _px(size))
	label.add_theme_color_override("font_color", color)
	return label


func _keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.add_theme_stylebox_override("panel", _box(Color(0.9, 0.96, 1.0, 0.10), Color(ACCENT_COLOR, 0.55), 5.0, Vector2(6.0, 1.0)))
	cap.add_child(_label(text, 12, Color.WHITE))
	return cap


func _build_readout() -> void:
	_readout = PanelContainer.new()
	_readout.name = "Readout"
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _px(4))
	_readout_title = _label("", 11, ACCENT_COLOR)
	column.add_child(_readout_title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", _px(14))
	grid.add_theme_constant_override("v_separation", _px(2))
	for caption in ["ALT", "SPD", "V/S"]:
		var name_label := _label(caption, 11, MUTED_COLOR)
		var value_label := _label("—", 16)
		grid.add_child(name_label)
		grid.add_child(value_label)
		_readout_values.append(value_label)
		if caption == "V/S":
			_readout_vertical_row = [name_label, value_label]
	column.add_child(grid)
	_readout_status = _label("", 11, ACCENT_COLOR)
	column.add_child(_readout_status)
	_readout.add_child(column)
	_root.add_child(_readout)


func _build_fps() -> void:
	_fps_label = _label("", 12, MUTED_COLOR)
	_fps_label.name = "Fps"
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps_label.position += Vector2(-18.0, 12.0) * ui_scale
	_root.add_child(_fps_label)


func _build_flash() -> void:
	_flash = _label(_flash_text, 18)
	_flash.name = "Flash"
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.add_theme_constant_override("outline_size", _px(4))
	_flash.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_flash.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_flash.position.y += 90.0 * ui_scale
	_flash.visible = Time.get_ticks_msec() < _flash_until
	_root.add_child(_flash)


func flash(text: String) -> void:
	_flash_text = text
	_flash_until = Time.get_ticks_msec() + FLASH_MS
	_flash.text = text
	_flash.visible = true


func _build_prompt() -> void:
	_prompt = HBoxContainer.new()
	_prompt.name = "Prompt"
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_constant_override("separation", _px(8))
	var cap := _keycap("E")
	_prompt_key = cap.get_child(0) as Label
	_prompt.add_child(cap)
	_prompt_text = _label("", 17)
	_prompt_text.add_theme_constant_override("outline_size", _px(4))
	_prompt_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_prompt.add_child(_prompt_text)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.position.y += 46.0 * ui_scale
	_root.add_child(_prompt)


func _build_hints() -> void:
	_hints_bar = PanelContainer.new()
	_hints_bar.name = "Hints"
	_hints_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints_bar.add_theme_stylebox_override("panel", _box(Color(0.01, 0.03, 0.06, 0.55), Color(ACCENT_COLOR, 0.12), 16.0, Vector2(14.0, 5.0)))
	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override("separation", _px(16))
	_hints_bar.add_child(_hints)
	_hints_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hints_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hints_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hints_bar.position.y -= 16.0 * ui_scale
	_hints_bar.visible = not touch_service.is_touch_ui()
	_root.add_child(_hints_bar)


func _build_menu() -> void:
	_menu = Control.new()
	_menu.name = "Menu"
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.02, 0.05, 0.10, 0.94), Color(ACCENT_COLOR, 0.35), 14.0, Vector2(22.0, 18.0)))
	panel.custom_minimum_size.x = 520.0 * ui_scale
	center.add_child(panel)
	# Phones scale the UI up to twice its size: past the screen height the menu scrolls.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", _px(10))
	scroll.add_child(column)

	var header := HBoxContainer.new()
	header.add_child(_label("OUTER GODOT", 22, ACCENT_COLOR))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var resume := _menu_button("Resume", close_menu)
	header.add_child(resume)
	column.add_child(header)

	column.add_child(_label("TRAVEL", 11, MUTED_COLOR))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", _px(8))
	grid.add_theme_constant_override("v_separation", _px(8))
	for body in celestial_bodies:
		var planet := body as PlanetBody
		if planet == null:
			continue
		var button := _menu_button(String(planet.body_id), _travel_to.bind(planet.body_id))
		button.toggle_mode = true
		button.button_pressed = planet.body_id == _selected_planet
		grid.add_child(button)
		_planet_buttons[planet.body_id] = button
		if _menu_first_button == null:
			_menu_first_button = button
	column.add_child(grid)

	column.add_child(_label("SIMULATION", 11, MUTED_COLOR))
	var simulation := HBoxContainer.new()
	simulation.add_theme_constant_override("separation", _px(8))
	_fast_time_button = _menu_button("Fast time", _on_fast_time_toggled)
	_fast_time_button.toggle_mode = true
	simulation.add_child(_fast_time_button)
	_gravity_button = _menu_button("Gravity vectors", _on_gravity_toggled)
	_gravity_button.toggle_mode = true
	_gravity_button.button_pressed = gravity_debug_visible
	simulation.add_child(_gravity_button)
	simulation.add_child(_menu_button("Respawn", _on_respawn_pressed))
	column.add_child(simulation)

	column.add_child(_label("EVENTS", 11, MUTED_COLOR))
	var events := HBoxContainer.new()
	events.add_theme_constant_override("separation", _px(8))
	_supernova_button = _menu_button("Supernova", _on_supernova_pressed)
	_supernova_button.add_theme_color_override("font_color", DANGER_COLOR)
	events.add_child(_supernova_button)
	_leviathan_button = _menu_button("Summon leviathan", _on_leviathan_pressed)
	_leviathan_button.add_theme_color_override("font_color", Color(1.0, 0.45, 0.62))
	events.add_child(_leviathan_button)
	column.add_child(events)

	var main := get_parent() as Main
	if main != null and main.graphics != null:
		column.add_child(_label("GRAPHICS", 11, MUTED_COLOR))
		var graphics := GridContainer.new()
		graphics.columns = 3
		graphics.add_theme_constant_override("h_separation", _px(8))
		graphics.add_theme_constant_override("v_separation", _px(8))
		_add_graphics_button(graphics, &"scale", _cycle_render_scale)
		_add_graphics_button(graphics, &"shadows", _cycle_shadows)
		_add_graphics_button(graphics, &"ambient_occlusion", func(on: bool) -> void: _change_graphics(func(settings: GraphicsSettings) -> void: settings.ambient_occlusion = on), "Ambient occlusion")
		_add_graphics_button(graphics, &"glow", func(on: bool) -> void: _change_graphics(func(settings: GraphicsSettings) -> void: settings.glow = on), "Glow")
		_add_graphics_button(graphics, &"fxaa", func(on: bool) -> void: _change_graphics(func(settings: GraphicsSettings) -> void: settings.fxaa = on), "FXAA")
		_add_graphics_button(graphics, &"vsync", func(on: bool) -> void: _change_graphics(func(settings: GraphicsSettings) -> void: settings.vsync = on), "VSync")
		_add_graphics_button(graphics, &"show_fps", func(on: bool) -> void: _change_graphics(func(settings: GraphicsSettings) -> void: settings.show_fps = on), "FPS counter")
		column.add_child(graphics)
		_refresh_graphics_buttons()

	column.add_child(_label("Esc · Start · B to close", 11, Color(MUTED_COLOR, 0.7)))
	scroll.custom_minimum_size.y = minf(column.get_combined_minimum_size().y, get_viewport().get_visible_rect().size.y - 80.0 * ui_scale)
	_root.add_child(_menu)


func _add_graphics_button(grid: GridContainer, key: StringName, action: Callable, text := "") -> void:
	var button := _menu_button(text, action)
	button.toggle_mode = not text.is_empty()
	grid.add_child(button)
	_graphics_buttons[key] = button


func _refresh_graphics_buttons() -> void:
	var main := get_parent() as Main
	if main == null or main.graphics == null or _graphics_buttons.is_empty():
		return
	var settings := main.graphics
	(_graphics_buttons[&"scale"] as Button).text = "Render scale: %s" % settings.render_scale_label()
	(_graphics_buttons[&"shadows"] as Button).text = "Shadows: %s" % GraphicsSettings.SHADOW_NAMES[settings.shadows]
	(_graphics_buttons[&"ambient_occlusion"] as Button).set_pressed_no_signal(settings.ambient_occlusion)
	(_graphics_buttons[&"glow"] as Button).set_pressed_no_signal(settings.glow)
	(_graphics_buttons[&"fxaa"] as Button).set_pressed_no_signal(settings.fxaa)
	(_graphics_buttons[&"vsync"] as Button).set_pressed_no_signal(settings.vsync)
	(_graphics_buttons[&"show_fps"] as Button).set_pressed_no_signal(settings.show_fps)


func _change_graphics(change: Callable) -> void:
	var main := get_parent() as Main
	if main == null or main.graphics == null:
		return
	change.call(main.graphics)
	main.graphics.save()
	main.apply_graphics()
	_refresh_graphics_buttons()


func _cycle_render_scale() -> void:
	_change_graphics(func(settings: GraphicsSettings) -> void:
		settings.render_scale_index = (settings.render_scale_index + 1) % GraphicsSettings.RENDER_SCALES.size())


func _cycle_shadows() -> void:
	_change_graphics(func(settings: GraphicsSettings) -> void:
		settings.shadows = (settings.shadows + 1) % GraphicsSettings.SHADOW_NAMES.size())


func _menu_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 38.0 * ui_scale
	button.focus_mode = Control.FOCUS_ALL
	if action.get_argument_count() == 1:
		button.toggled.connect(action)
	else:
		button.pressed.connect(action)
	return button


func layout_panels() -> void:
	if _readout == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var margin := 18.0 * ui_scale
	_readout.position = Vector2(margin, margin)
	_globe.size = Vector2(180.0, 190.0) * ui_scale
	if touch_service.is_touch_ui():
		_globe.position = Vector2(margin, margin + _readout.get_combined_minimum_size().y + margin)
	else:
		_globe.position = Vector2(margin, viewport_size.y - _globe.size.y - margin)


func is_menu_open() -> bool:
	return _menu != null and _menu.visible


func open_menu() -> void:
	if is_menu_open():
		return
	_refresh_menu()
	_menu.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _gamepad and _menu_first_button != null:
		_menu_first_button.grab_focus()


func close_menu() -> void:
	if not is_menu_open():
		return
	_menu.visible = false
	get_tree().paused = false
	if not touch_service.is_touch_ui():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle_menu() -> void:
	if is_menu_open():
		close_menu()
	else:
		open_menu()


func _refresh_menu() -> void:
	for body_id in _planet_buttons:
		var button: Button = _planet_buttons[body_id]
		button.set_pressed_no_signal(body_id == _selected_planet)
	var celestial_system := get_tree().get_first_node_in_group("celestial_system") as CelestialSystem
	_fast_time_button.set_pressed_no_signal(celestial_system != null and celestial_system.is_fast_forward_enabled())
	_gravity_button.set_pressed_no_signal(gravity_debug_visible)
	var sun := get_tree().get_first_node_in_group("sun") as Sun
	_supernova_button.disabled = sun == null or sun.is_exploding()
	var leviathan := get_tree().get_first_node_in_group("leviathan") as Leviathan
	var active := leviathan != null and leviathan.is_active()
	var devouring := leviathan != null and leviathan.is_devouring()
	_leviathan_button.text = "Leviathan feeding" if devouring else ("Banish leviathan" if active else "Summon leviathan")
	_leviathan_button.disabled = leviathan == null or devouring


func _travel_to(body_id: StringName) -> void:
	var main := get_parent() as Main
	if main != null:
		main.spawn_on_planet_id(body_id)
	set_selected_planet(body_id)
	close_menu()


func _on_fast_time_toggled(enabled: bool) -> void:
	var celestial_system := get_tree().get_first_node_in_group("celestial_system") as CelestialSystem
	if celestial_system != null:
		celestial_system.set_fast_forward_enabled(enabled)


func _on_gravity_toggled(enabled: bool) -> void:
	gravity_debug_visible = enabled


func _on_respawn_pressed() -> void:
	var main := get_parent() as Main
	close_menu()
	if main != null:
		main.respawn()


func _on_supernova_pressed() -> void:
	var sun := get_tree().get_first_node_in_group("sun") as Sun
	if sun != null:
		sun.detonate()
	close_menu()


# Summons on the first press, sends it back on the second — but only while it is
# still approaching. Once it starts eating there is no calling it off.
func _on_leviathan_pressed() -> void:
	var leviathan := get_tree().get_first_node_in_group("leviathan") as Leviathan
	if leviathan == null:
		return
	if leviathan.is_active():
		leviathan.banish()
	else:
		leviathan.summon()
	close_menu()


func set_selected_planet(body_id: StringName) -> void:
	_selected_planet = body_id
	if is_menu_open():
		_refresh_menu()


func is_touch_over_ui(_position_value: Vector2) -> bool:
	return is_menu_open()


func is_mouse_over_ui(position_value: Vector2) -> bool:
	return is_touch_over_ui(position_value)


func _input(event: InputEvent) -> void:
	var gamepad_event := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5)
	if (gamepad_event or event is InputEventKey or event is InputEventMouseButton) and gamepad_event != _gamepad:
		_gamepad = gamepad_event
		_refresh_hints()
		if _gamepad and is_menu_open() and get_viewport().gui_get_focus_owner() == null and _menu_first_button != null:
			_menu_first_button.grab_focus()
	if event.is_action_pressed("menu") or (is_menu_open() and event.is_action_pressed("ui_cancel")):
		toggle_menu()
		get_viewport().set_input_as_handled()
		return
	if is_menu_open():
		return
	if event.is_action_pressed("map") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB):
		planet_markers_visible = not planet_markers_visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("lock_target") or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		if ship == null:
			return
		locked_body = null if locked_body == aimed_body else aimed_body
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	aimed_body = find_aimed_body(camera, celestial_bodies) if ship != null and camera != null else null
	if ship == null:
		locked_body = null
	if _flash.visible and Time.get_ticks_msec() >= _flash_until:
		_flash.visible = false
	_update_readout()
	var main := get_parent() as Main
	_fps_label.visible = main != null and main.graphics != null and main.graphics.show_fps
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	var held := Time.get_ticks_msec() - _hints_shown_at < HINT_HOLD_MS
	_hints_bar.modulate.a = move_toward(_hints_bar.modulate.a, 1.0 if held else HINT_RESTING_ALPHA, delta * 1.5)


func _update_readout() -> void:
	var subject: Node3D = ship if ship != null else player
	if subject == null or not is_instance_valid(subject):
		_readout.visible = false
		return
	var reference := gravity_service.get_reference_body(subject.global_position)
	_readout.visible = reference != null
	if reference == null:
		return
	var velocity := ship.linear_velocity if ship != null else player.velocity
	var relative := velocity - reference.orbital_velocity
	var up := (subject.global_position - reference.global_position).normalized()
	_readout_title.text = String(reference.name).to_upper()
	var altitude := gravity_service.get_altitude(subject.global_position)
	_readout_values[0].text = _format_distance(maxf(altitude, 0.0))
	_readout_values[1].text = "%.1f m/s" % relative.length()
	var vertical := relative.dot(up)
	_readout_values[2].text = "%+.1f m/s" % (vertical if absf(vertical) >= 0.05 else 0.0)
	for node in _readout_vertical_row:
		node.visible = ship != null
	_readout_status.text = _ship_status()
	_readout_status.visible = not _readout_status.text.is_empty()


func _ship_status() -> String:
	if ship == null:
		return ""
	var parts: Array[String] = []
	var target := ship.autopilot_target
	if is_instance_valid(target):
		var offset := ship.global_position - target.global_position
		parts.append("AUTOPILOT → %s  %s" % [target.name, _format_distance(maxf(offset.length() - target.get_surface_radius_towards(offset), 0.0))])
	elif ship.assist_active:
		parts.append("ASSIST")
	if ship.boosting:
		parts.append("BOOST")
	return "  ·  ".join(parts)


func get_target_body() -> CelestialBody:
	return locked_body if is_instance_valid(locked_body) else aimed_body


func draw_navigation(canvas: Control) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_draw_crosshair(canvas)
	var markers: Array[Marker] = []
	if is_instance_valid(tracked_ship) and ship == null:
		markers.append(_marker(camera, tracked_ship.global_position, "SHIP", SHIP_COLOR))
	for body in celestial_bodies:
		if not is_instance_valid(body):
			continue
		if planet_markers_visible or gravity_debug_visible and _has_active_gravity(body, camera.global_position):
			markers.append(_marker(camera, body.global_position, String(body.name), PLANET_COLOR))
	_draw_markers(canvas, markers)
	_draw_gravity_debug(canvas, camera)
	if aimed_body != null and aimed_body != locked_body:
		_draw_target(canvas, camera, aimed_body, false)
	if locked_body != null and is_instance_valid(locked_body):
		_draw_target(canvas, camera, locked_body, true)


func _draw_crosshair(canvas: Control) -> void:
	if is_menu_open():
		return
	var center := canvas.size * 0.5
	var color := Color(1.0, 1.0, 1.0, 0.75)
	canvas.draw_circle(center, 1.6 * ui_scale, color)
	for axis: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		canvas.draw_line(center + axis * 5.0 * ui_scale, center + axis * 10.0 * ui_scale, Color(color, 0.5), 1.2 * ui_scale, true)


func _marker(camera: Camera3D, world_position: Vector3, label: String, color: Color) -> Marker:
	var marker := Marker.new()
	marker.label = label
	marker.color = color
	marker.distance = camera.global_position.distance_to(world_position)
	var viewport_size := get_viewport().get_visible_rect().size
	var margin := MARKER_MARGIN * ui_scale
	var behind := camera.is_position_behind(world_position)
	if not behind:
		marker.position = camera.unproject_position(world_position)
		var inside := Rect2(Vector2.ONE * margin, viewport_size - Vector2.ONE * margin * 2.0).has_point(marker.position)
		if inside:
			return marker
	var local_position := camera.to_local(world_position)
	var direction := Vector2(local_position.x, -local_position.y)
	if local_position.z > 0.0:
		direction = -direction
	if direction.length_squared() < 0.001:
		direction = Vector2.UP
	marker.direction = direction.normalized()
	marker.position = _clamp_to_screen(viewport_size * 0.5, marker.direction, viewport_size)
	return marker


# Nearest first: a label that would land on one already drawn keeps its symbol
# but drops its text, so bodies lined up behind each other stay readable.
func _draw_markers(canvas: Control, markers: Array[Marker]) -> void:
	markers.sort_custom(func(a: Marker, b: Marker) -> bool: return a.distance < b.distance)
	var font := ThemeDB.fallback_font
	var font_size := _px(13)
	var taken: Array[Rect2] = []
	for marker in markers:
		if marker.direction == Vector2.ZERO:
			canvas.draw_arc(marker.position, 7.0 * ui_scale, 0.0, TAU, 20, marker.color, 1.4 * ui_scale, true)
			canvas.draw_circle(marker.position, 1.8 * ui_scale, marker.color)
		else:
			_draw_chevron(canvas, marker.position, marker.direction, marker.color)
		var text := "%s  %s" % [marker.label, _format_distance(marker.distance)]
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var origin := marker.position + Vector2(12.0, 4.0) * ui_scale
		if origin.x + text_size.x > canvas.size.x - 8.0 * ui_scale:
			origin.x = marker.position.x - text_size.x - 12.0 * ui_scale
		var rect := Rect2(origin - Vector2(0.0, text_size.y * 0.75), text_size).grow(2.0 * ui_scale)
		if taken.any(func(other: Rect2) -> bool: return other.intersects(rect)):
			continue
		taken.append(rect)
		canvas.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _px(4), Color(0, 0, 0, 0.55))
		canvas.draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, marker.color)


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
	canvas.draw_polyline(PackedVector2Array([tail + side * 5.0 * ui_scale, tip, tail - side * 5.0 * ui_scale]), color, 1.6 * ui_scale, true)


func _draw_gravity_debug(canvas: Control, camera: Camera3D) -> void:
	if not gravity_debug_visible:
		return
	var origin := canvas.size * 0.5
	var observer_position := camera.global_position
	var color_index := 0
	for body in celestial_bodies:
		if not is_instance_valid(body):
			continue
		var acceleration := gravity_service.get_gravity_from(body, observer_position)
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


func _draw_target(canvas: Control, camera: Camera3D, body: CelestialBody, locked: bool) -> void:
	if camera.is_position_behind(body.global_position):
		return
	var center := camera.unproject_position(body.global_position)
	var edge := camera.unproject_position(body.global_position + camera.global_basis.x * body.radius)
	var ring_radius := clampf(center.distance_to(edge) * (1.12 if locked else 1.06), 13.0 * ui_scale, 260.0 * ui_scale)
	var color := TARGET_COLOR if locked else AIM_COLOR
	canvas.draw_arc(center, ring_radius, 0.0, TAU, 48, color, (2.2 if locked else 1.2) * ui_scale, true)
	if ship == null:
		return
	var direction := (body.global_position - camera.global_position).normalized()
	var surface_radius := body.get_surface_radius_towards(-direction)
	var surface_distance := maxf(camera.global_position.distance_to(body.global_position) - surface_radius, 0.0)
	var relative := BonificationMath.relative_velocity_components(ship.linear_velocity, body.orbital_velocity, direction, camera.global_basis.y, camera.global_basis.x)
	var label := "%s  %s\nSurface %s\nApproach %+.1f m/s" % [body.name, "LOCKED" if locked else "TARGET", _format_distance(surface_distance), relative.z]
	var origin := center + Vector2(ring_radius + 12.0 * ui_scale, -8.0 * ui_scale)
	canvas.draw_multiline_string_outline(ThemeDB.fallback_font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _px(14), -1, _px(4), Color(0, 0, 0, 0.55))
	canvas.draw_multiline_string(ThemeDB.fallback_font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _px(14), -1, color)
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


static func find_aimed_body(camera: Camera3D, bodies: Array[CelestialBody]) -> CelestialBody:
	var best: CelestialBody
	var nearest := INF
	var direction := -camera.global_basis.z
	for body in bodies:
		if not is_instance_valid(body):
			continue
		var hit := BonificationMath.ray_sphere_distance(body.global_position, body.radius, camera.global_position, direction)
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


func _has_active_gravity(body: CelestialBody, observer_position: Vector3) -> bool:
	return gravity_service.get_gravity_from(body, observer_position).length_squared() > 0.0


func _format_distance(distance: float) -> String:
	if distance >= 1000.0:
		return "%.1f km" % (distance / 1000.0)
	return "%.0f m" % distance


func set_prompt(text: String) -> void:
	_prompt_action = text
	_refresh_prompt()


func _refresh_prompt() -> void:
	_prompt.visible = not _prompt_action.is_empty()
	_prompt_text.text = _prompt_action
	_prompt_key.text = "✦" if touch_service.is_touch_ui() else ("X" if _gamepad else "E")


func _refresh_hints() -> void:
	_refresh_prompt()
	for child in _hints.get_children():
		_hints.remove_child(child)
		child.queue_free()
	var hints: Array = (HINTS_SHIP_PAD if _gamepad else HINTS_SHIP_KEYS) if ship != null else (HINTS_FOOT_PAD if _gamepad else HINTS_FOOT_KEYS)
	for hint: Array in hints:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", _px(5))
		chip.add_child(_keycap(hint[0]))
		var text := _label(hint[1], 12, Color(TEXT_COLOR, 0.85))
		text.add_theme_constant_override("outline_size", _px(3))
		text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
		chip.add_child(text)
		_hints.add_child(chip)
	_hints_shown_at = Time.get_ticks_msec()
	_hints_bar.modulate.a = 1.0


func set_ship(value: Ship) -> void:
	ship = value
	if ship != null:
		_prompt_action = ""
	else:
		locked_body = null
		aimed_body = null
	_refresh_hints()
