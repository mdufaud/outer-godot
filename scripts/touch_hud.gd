extends Control

var main: Node3D

const BW := 62.0
const BH := 52.0
const GAP := 6.0
const MARGIN := 16.0
const JOY_OFFSET := Vector2(94, -94)
const JOY_RADIUS := 64.0
const KNOB_RADIUS := 26.0
const HOLD_ACTIONS := [
	"move_forward", "move_back", "move_left", "move_right",
	"jump", "sprint", "brake", "roll_left", "roll_right",
]

var _piloting := false
var _buttons: Array = []
var _touches: Dictionary = {}
var _joy_knob := Vector2.ZERO
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	get_viewport().size_changed.connect(_fit)
	_fit()
	_rebuild()


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	queue_redraw()


func _process(_delta: float) -> void:
	var p: bool = main.player.piloting
	if p != _piloting:
		_piloting = p
		_rebuild()


func _joy_center() -> Vector2:
	return Vector2(JOY_OFFSET.x, size.y + JOY_OFFSET.y)


func _rebuild() -> void:
	_release_all_holds()
	_buttons.clear()
	if _piloting:
		_add_btn("Up", "jump", Callable(), 0, 0)
		_add_btn("Down", "sprint", Callable(), 0, 1)
		_add_btn("Brake", "brake", Callable(), 1, 0)
		_add_btn("Roll R", "roll_right", Callable(), 2, 0)
		_add_btn("Roll L", "roll_left", Callable(), 2, 1)
		_add_btn("Exit", "", _exit_ship, 1, 1)
		_add_btn("R", "", _respawn, 0, 2)
	else:
		_add_btn("Jump", "jump", Callable(), 0, 0)
		_add_btn("Sprint", "sprint", Callable(), 0, 1)
		_add_btn("E", "", _interact, 1, 0)
		_add_btn("R", "", _respawn, 1, 1)
	queue_redraw()


func _add_btn(label: String, action: String, tap: Callable, col: int, row: int) -> void:
	_buttons.append({"label": label, "action": action, "tap": tap, "col": col, "row": row})


func _btn_rect(b: Dictionary) -> Rect2:
	var x: float = size.x - MARGIN - (b.col + 1) * BW - b.col * GAP
	var y: float = size.y - MARGIN - (b.row + 1) * BH - b.row * GAP
	return Rect2(x, y, BW, BH)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.index, event.position)
		else:
			_on_release(event.index)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position)


func _on_press(index: int, pos: Vector2) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("is_touch_over_ui") and hud.is_touch_over_ui(pos):
		return
	for b in _buttons:
		if _btn_rect(b).has_point(pos):
			if b.action != "":
				Input.action_press(b.action)
			if b.tap.is_valid():
				b.tap.call()
			_touches[index] = {"kind": "button", "btn": b}
			return
	if pos.distance_to(_joy_center()) <= JOY_RADIUS * 1.4:
		_touches[index] = {"kind": "joy"}
		_update_joy(pos)
		return
	_touches[index] = {"kind": "look", "last": pos}


func _on_drag(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	if t.kind == "joy":
		_update_joy(pos)
	elif t.kind == "look":
		Touch.look_delta += pos - t.last
		t.last = pos


func _on_release(index: int) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	if t.kind == "button" and t.btn.action != "":
		Input.action_release(t.btn.action)
	elif t.kind == "joy":
		_joy_knob = Vector2.ZERO
		_apply_joy(Vector2.ZERO)
		queue_redraw()
	_touches.erase(index)


func _update_joy(pos: Vector2) -> void:
	var off := pos - _joy_center()
	if off.length() > JOY_RADIUS:
		off = off.normalized() * JOY_RADIUS
	_joy_knob = off
	_apply_joy(off / JOY_RADIUS)
	queue_redraw()


func _apply_joy(vec: Vector2) -> void:
	_set_axis("move_left", "move_right", vec.x)
	_set_axis("move_forward", "move_back", vec.y)


func _set_axis(neg: String, pos: String, v: float) -> void:
	if v > 0.001:
		Input.action_press(pos, v)
		Input.action_release(neg)
	elif v < -0.001:
		Input.action_press(neg, -v)
		Input.action_release(pos)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func _release_all_holds() -> void:
	for a in HOLD_ACTIONS:
		Input.action_release(a)
	for i in _touches.keys():
		if _touches[i].kind == "button":
			_touches.erase(i)


func _interact() -> void:
	if not _piloting:
		main.player._try_interact()


func _exit_ship() -> void:
	if _piloting:
		main.ship.exit_pilot()


func _respawn() -> void:
	main.respawn()


func _draw() -> void:
	var c := _joy_center()
	draw_circle(c, JOY_RADIUS, Color(0.08, 0.20, 0.34, 0.46))
	draw_arc(c, JOY_RADIUS, 0.0, TAU, 48, Color(0.40, 0.78, 1.0, 0.65), 2.0)
	draw_circle(c + _joy_knob, KNOB_RADIUS, Color(0.40, 0.78, 1.0, 0.62))
	draw_arc(c + _joy_knob, KNOB_RADIUS, 0.0, TAU, 32, Color(0.78, 0.93, 1.0, 0.75), 1.5)
	for b in _buttons:
		var r := _btn_rect(b)
		var accent := _button_accent(b.label)
		var fill := Color(accent, 0.22)
		draw_style_box(_touch_button_style(fill, accent), r)
		if _font:
			var icon := _button_icon(b.label)
			var icon_size := _font.get_string_size(icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
			var icon_at := r.position + Vector2((r.size.x - icon_size.x) * 0.5, 22.0)
			draw_string(_font, icon_at, icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.94, 0.98, 1.0, 0.98))
			var caption := _button_caption(b.label)
			var caption_size := _font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
			var caption_at := r.position + Vector2((r.size.x - caption_size.x) * 0.5, 42.0)
			draw_string(_font, caption_at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.82, 0.91, 1.0, 0.9))


func _button_icon(label: String) -> String:
	match label:
		"Jump", "Up":
			return "▲"
		"Sprint", "Down":
			return "▼"
		"E":
			return "✦"
		"R":
			return "↻"
		"Brake":
			return "■"
		"Roll R":
			return "↷"
		"Roll L":
			return "↶"
		"Exit":
			return "×"
	return "•"


func _button_caption(label: String) -> String:
	match label:
		"E":
			return "Interact"
		"R":
			return "Respawn"
	return label


func _button_accent(label: String) -> Color:
	if label in ["Jump", "Up", "Sprint", "Down"]:
		return Color(0.35, 0.82, 1.0)
	if label in ["E", "Exit"]:
		return Color(0.45, 1.0, 0.70)
	if label == "Brake":
		return Color(1.0, 0.56, 0.36)
	if label in ["R", "Roll R", "Roll L"]:
		return Color(1.0, 0.78, 0.36)
	return Color(0.65, 0.78, 1.0)


func _touch_button_style(fill: Color, accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(accent, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	return style
