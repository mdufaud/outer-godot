extends Control

var main: Node3D

const BW := 120.0
const BH := 96.0
const GAP := 16.0
const MARGIN := 24.0
const JOY_OFFSET := Vector2(160, -160)
const JOY_RADIUS := 110.0
const KNOB_RADIUS := 46.0
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
	draw_circle(c, JOY_RADIUS, Color(1, 1, 1, 0.08))
	draw_arc(c, JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 2.0)
	draw_circle(c + _joy_knob, KNOB_RADIUS, Color(1, 1, 1, 0.25))
	for b in _buttons:
		var r := _btn_rect(b)
		draw_rect(r, Color(1, 1, 1, 0.12), true)
		draw_rect(r, Color(1, 1, 1, 0.3), false, 2.0)
		if _font:
			var ts := _font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
			var at := r.position + Vector2((r.size.x - ts.x) * 0.5, r.size.y * 0.5 + 8.0)
			draw_string(_font, at, b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.85))
