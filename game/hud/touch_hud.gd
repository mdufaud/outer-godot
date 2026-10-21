class_name TouchHud
extends Control

class TouchButton extends RefCounted:
	var label: String
	var action: StringName
	var tap: Callable
	var column: int
	var row: int


const BW := 78.0
const BH := 78.0
const GAP := 14.0
const MARGIN := 22.0
const HIT_PAD := 7.0
const ICON_SIZE := 28.0
const CAPTION_SIZE := 13.0
const MENU_SIZE := 52.0
const STICK_AREA := Rect2(0.0, 0.35, 0.45, 0.65)
const STICK_SIZE := 184.0
const STICK_TIP := 76.0
const ACCENT := Color(0.40, 0.78, 1.0)

var main: Main

var _piloting := false
var _buttons: Array[TouchButton] = []
var _button_touches: Dictionary[int, TouchButton] = {}
var _look_touches: Dictionary[int, Vector2] = {}
var _stick: VirtualJoystick
var _scale := 1.0
var _font: Font
@onready var touch_service: TouchService = get_node("/root/Touch")


func _ready() -> void:
	add_to_group("touch_hud")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_stick = VirtualJoystick.new()
	_stick.name = "MoveStick"
	_stick.action_left = &"move_left"
	_stick.action_right = &"move_right"
	_stick.action_up = &"move_forward"
	_stick.action_down = &"move_back"
	_stick.joystick_mode = VirtualJoystick.JOYSTICK_DYNAMIC
	_stick.visibility_mode = VirtualJoystick.VISIBILITY_ALWAYS
	_stick.initial_offset_ratio = Vector2(0.4, 0.62)
	add_child(_stick)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_rebuild()


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_scale = touch_service.ui_scale(size)
	_stick.position = STICK_AREA.position * size
	_stick.size = STICK_AREA.size * size
	_stick.joystick_size = STICK_SIZE * _scale
	_stick.tip_size = STICK_TIP * _scale
	_stick.add_theme_stylebox_override("normal_joystick", _circle(Color(0.08, 0.20, 0.34, 0.30), Color(ACCENT, 0.45)))
	_stick.add_theme_stylebox_override("pressed_joystick", _circle(Color(0.08, 0.20, 0.34, 0.46), Color(ACCENT, 0.75)))
	_stick.add_theme_stylebox_override("normal_tip", _circle(Color(ACCENT, 0.40), Color(0.78, 0.93, 1.0, 0.6)))
	_stick.add_theme_stylebox_override("pressed_tip", _circle(Color(ACCENT, 0.65), Color(0.78, 0.93, 1.0, 0.9)))
	queue_redraw()


func _circle(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(maxi(1, roundi(2.0 * _scale)))
	style.set_corner_radius_all(roundi(STICK_SIZE * _scale))
	style.anti_aliasing = true
	return style


func _process(_delta: float) -> void:
	if main.player.piloting != _piloting:
		_piloting = main.player.piloting
		_rebuild()


func _rebuild() -> void:
	_release_all_holds()
	_buttons.clear()
	if _piloting:
		_add_button("Up", &"jump", Callable(), 0, 1)
		_add_button("Down", &"sprint", Callable(), 0, 0)
		_add_button("Brake", &"brake", Callable(), 1, 0)
		_add_button("Roll R", &"roll_right", Callable(), 2, 0)
		_add_button("Roll L", &"roll_left", Callable(), 2, 1)
		_add_button("Exit", &"", _exit_ship, 1, 1)
		_add_button("Map", &"", _toggle_map, 1, 2)
	else:
		_add_button("Jump", &"jump", Callable(), 0, 0)
		_add_button("Sprint", &"sprint", Callable(), 0, 1)
		_add_button("Interact", &"", _interact, 1, 0)
		_add_button("Respawn", &"", _respawn, 1, 1)
		_add_button("Map", &"", _toggle_map, 1, 2)
	queue_redraw()


func _add_button(label: String, action: StringName, tap: Callable, column: int, row: int) -> void:
	var button := TouchButton.new()
	button.label = label
	button.action = action
	button.tap = tap
	button.column = column
	button.row = row
	_buttons.append(button)


func _button_rect(button: TouchButton) -> Rect2:
	var w := BW * _scale
	var h := BH * _scale
	var gap := GAP * _scale
	var margin := MARGIN * _scale
	var x := size.x - margin - (button.column + 1) * w - button.column * gap
	var y := size.y - margin - (button.row + 1) * h - button.row * gap
	return Rect2(x, y, w, h)


func _menu_rect() -> Rect2:
	var side := MENU_SIZE * _scale
	var margin := MARGIN * _scale
	return Rect2(size.x - margin - side, margin, side, side)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.index, event.position)
		else:
			_on_release(event.index)
	elif event is InputEventScreenDrag and _look_touches.has(event.index):
		touch_service.look_delta += event.position - _look_touches[event.index]
		_look_touches[event.index] = event.position


func _on_press(index: int, pos: Vector2) -> void:
	if _menu_rect().grow(HIT_PAD * _scale).has_point(pos):
		var hud := get_tree().get_first_node_in_group("hud") as Hud
		if hud != null:
			hud.open_menu()
		return
	for button in _buttons:
		if _button_rect(button).grow(HIT_PAD * _scale).has_point(pos):
			if not button.action.is_empty():
				Input.action_press(button.action)
			if button.tap.is_valid():
				button.tap.call()
			_button_touches[index] = button
			queue_redraw()
			return
	# The stick handles its own touches through the GUI.
	if _stick.get_global_rect().has_point(pos):
		return
	_look_touches[index] = pos


func _on_release(index: int) -> void:
	if _button_touches.has(index):
		var button := _button_touches[index]
		if not button.action.is_empty():
			Input.action_release(button.action)
		_button_touches.erase(index)
		queue_redraw()
	_look_touches.erase(index)


func _notification(what: int) -> void:
	# A finger lifted while the app is in the background never sends its release.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_all_holds()
		_look_touches.clear()


func _release_all_holds() -> void:
	for button in _button_touches.values():
		if not button.action.is_empty():
			Input.action_release(button.action)
	_button_touches.clear()


func _interact() -> void:
	if not _piloting:
		main.player._try_interact()


func _exit_ship() -> void:
	if _piloting:
		main.ship.exit_pilot()


func _respawn() -> void:
	main.respawn()


func _toggle_map() -> void:
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if hud != null:
		hud.planet_markers_visible = not hud.planet_markers_visible


func _draw() -> void:
	var menu := _menu_rect()
	draw_style_box(_button_style(Color(0.08, 0.16, 0.26, 0.55), Color(ACCENT, 0.7)), menu)
	_draw_centered(menu, "☰", ICON_SIZE * 0.85, 0.6)
	for button in _buttons:
		var rect := _button_rect(button)
		var accent := _button_accent(button.label)
		var held := _button_touches.values().has(button)
		draw_style_box(_button_style(Color(accent, 0.42 if held else 0.22), Color(accent, 1.0 if held else 0.72)), rect)
		_draw_centered(rect, _button_icon(button.label), ICON_SIZE, 0.55)
		_draw_centered(rect, button.label, CAPTION_SIZE, 0.85)


func _draw_centered(rect: Rect2, text: String, font_size: float, height: float) -> void:
	var pixels := int(font_size * _scale)
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	draw_string(_font, rect.position + Vector2((rect.size.x - width) * 0.5, rect.size.y * height), text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, Color(0.94, 0.98, 1.0, 0.95))


func _button_icon(label: String) -> String:
	match label:
		"Jump", "Up":
			return "▲"
		"Sprint", "Down":
			return "▼"
		"Interact":
			return "✦"
		"Respawn":
			return "↻"
		"Brake":
			return "■"
		"Roll R":
			return "↷"
		"Roll L":
			return "↶"
		"Exit":
			return "×"
		"Map":
			return "◍"
	return "•"


func _button_accent(label: String) -> Color:
	if label in ["Jump", "Up", "Sprint", "Down"]:
		return Color(0.35, 0.82, 1.0)
	if label in ["Interact", "Exit"]:
		return Color(0.45, 1.0, 0.70)
	if label == "Brake":
		return Color(1.0, 0.56, 0.36)
	if label in ["Respawn", "Roll R", "Roll L"]:
		return Color(1.0, 0.78, 0.36)
	return Color(0.65, 0.85, 1.0)


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(maxi(1, roundi(_scale)))
	style.set_corner_radius_all(roundi(12.0 * _scale))
	return style
