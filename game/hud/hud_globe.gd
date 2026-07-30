extends Control

const GravityServiceScript := preload("res://game/celestial/gravity.gd")
const GLOBE_RADIUS := 62.0
const LAT_STEPS := [-60.0, -30.0, 0.0, 30.0, 60.0]
const MERIDIAN_COUNT := 4
const ARC_SEGMENTS := 48
const TRAIL_LENGTH := 100.0
const TRAIL_SPACING := 4.0
const TELEPORT_JUMP := 50.0
const FACE_SMOOTH := 8.0

const GRID_COLOR := Color(0.58, 0.82, 1.0, 0.68)
const NORTH_COLOR := Color(1.0, 0.42, 0.34)
const SOUTH_COLOR := Color(0.42, 0.72, 1.0)
const PLAYER_COLOR := Color(0.45, 1.0, 0.70)

var hud
var main: Node3D
var player: CharacterBody3D
var _floating_origin: Node
var _origin_shift_total := Vector3.ZERO
var _body: Node3D
var _direction := Vector3.UP
var _face := Vector3.FORWARD
var _right := Vector3.RIGHT
var _latitude_degrees := 0.0
var _altitude := -1.0
var _trail: Array[Vector3] = []
var _trail_body: Node3D
var _last_sample_world := Vector3.ZERO
var _has_last_sample := false
var _latitude_rings: Array[PackedVector3Array] = []
@onready var gravity_service: GravityService = get_node("/root/Gravity")


func _ready() -> void:
	var hud_node := get_tree().get_first_node_in_group("hud")
	if hud_node != null:
		main = hud_node.get_parent() as Node3D
	if main != null:
		player = main.get("player") as CharacterBody3D
		_floating_origin = main.get_node_or_null("FloatingOrigin")
		if _floating_origin != null:
			_origin_shift_total = _floating_origin.get("total_shift")
	_precompute_latitude_rings()
	visible = false


func _process(delta: float) -> void:
	if hud == null or not is_instance_valid(player):
		visible = false
		return
	if player.piloting:
		visible = false
		return
	if _floating_origin == null and main != null:
		_floating_origin = main.get_node_or_null("FloatingOrigin")
	if _floating_origin != null:
		var shift_total: Vector3 = _floating_origin.get("total_shift")
		if not shift_total.is_equal_approx(_origin_shift_total):
			_origin_shift_total = shift_total
			queue_redraw()
			return
	var nearest := gravity_service.get_nearest_surface(player.global_position) as Node3D
	if nearest == null:
		visible = false
		_body = null
		return
	_body = nearest
	visible = hud.planet_markers_visible
	var offset := player.global_position - _body.global_position
	if offset.length_squared() < 0.0001:
		visible = false
		return
	_direction = offset.normalized()
	_update_view_frame(delta)
	_update_trail()
	_latitude_degrees = rad_to_deg(asin(clampf(_direction.dot(Vector3.UP), -1.0, 1.0)))
	_altitude = gravity_service.get_altitude(player.global_position)
	queue_redraw()


func _update_view_frame(delta: float) -> void:
	var target_face := _direction - Vector3.UP * _direction.dot(Vector3.UP)
	if target_face.length_squared() > 0.0001:
		target_face = target_face.normalized()
		_face = _face.slerp(target_face, 1.0 - exp(-FACE_SMOOTH * delta)).normalized()
	_right = Vector3.UP.cross(_face).normalized()


func _update_trail() -> void:
	var current := player.global_position - _body.global_position
	if _body != _trail_body:
		_trail.clear()
		_trail_body = _body
		_last_sample_world = current
		_has_last_sample = true
		return
	if not _has_last_sample:
		_last_sample_world = current
		_has_last_sample = true
		return
	var distance := current.distance_to(_last_sample_world)
	if distance > TELEPORT_JUMP:
		_trail.clear()
		_last_sample_world = current
		return
	if distance < TRAIL_SPACING:
		return
	_trail.append(_direction)
	_last_sample_world = current
	var maximum := int(TRAIL_LENGTH / TRAIL_SPACING)
	while _trail.size() > maximum:
		_trail.pop_front()


func _precompute_latitude_rings() -> void:
	_latitude_rings.clear()
	for latitude_value in LAT_STEPS:
		var latitude := deg_to_rad(float(latitude_value))
		var ring := PackedVector3Array()
		for segment in range(ARC_SEGMENTS + 1):
			var angle := TAU * float(segment) / float(ARC_SEGMENTS)
			var ring_radius := cos(latitude)
			ring.append(Vector3(ring_radius * cos(angle), -sin(latitude), ring_radius * sin(angle)))
		_latitude_rings.append(ring)


func _draw() -> void:
	if _body == null or hud == null:
		return
	var scale := float(hud.ui_scale)
	var radius := GLOBE_RADIUS * scale
	var center := Vector2(size.x * 0.5, radius + 16.0 * scale)
	draw_arc(center, radius, 0.0, TAU, ARC_SEGMENTS, GRID_COLOR, 1.5 * scale, true)
	_draw_latitudes(center, radius, scale)
	_draw_meridians(center, radius, scale)
	_draw_poles(center, radius, scale)
	_draw_trail(center, radius, scale)
	_draw_ship(center, radius, scale)
	_draw_player(center, radius, scale)
	_draw_label(center, radius, scale)


func _draw_latitudes(center: Vector2, radius: float, scale: float) -> void:
	for index in range(_latitude_rings.size()):
		var projected := PackedVector2Array()
		var depths := PackedFloat32Array()
		for point in _latitude_rings[index]:
			projected.append(center + Vector2(point.x, point.y) * radius)
			depths.append(point.z)
		var width := (1.5 if is_zero_approx(float(LAT_STEPS[index])) else 0.9) * scale
		_draw_depth_curve(projected, depths, width)


func _draw_meridians(center: Vector2, radius: float, scale: float) -> void:
	var face_angle := atan2(_face.x, _face.z)
	for meridian in range(MERIDIAN_COUNT):
		var longitude := float(meridian) * PI / float(MERIDIAN_COUNT)
		var relative := longitude - face_angle
		var projected := PackedVector2Array()
		var depths := PackedFloat32Array()
		for segment in range(ARC_SEGMENTS + 1):
			var angle := TAU * float(segment) / float(ARC_SEGMENTS)
			projected.append(center + Vector2(sin(relative) * cos(angle), -sin(angle)) * radius)
			depths.append(cos(relative) * cos(angle))
		_draw_depth_curve(projected, depths, 0.9 * scale)


func _draw_depth_curve(points: PackedVector2Array, depths: PackedFloat32Array, width: float) -> void:
	var far_color := Color(GRID_COLOR, GRID_COLOR.a * 0.24)
	var near_color := GRID_COLOR
	for near_pass in [false, true]:
		var color := near_color if near_pass else far_color
		for index in range(points.size() - 1):
			var is_near := (depths[index] + depths[index + 1]) * 0.5 > 0.0
			if is_near == near_pass:
				draw_line(points[index], points[index + 1], color, width, true)


func _project(direction: Vector3, center: Vector2, radius: float) -> Vector2:
	return center + Vector2(direction.dot(_right), -direction.dot(Vector3.UP)) * radius


func _draw_poles(center: Vector2, radius: float, scale: float) -> void:
	var font := ThemeDB.fallback_font
	var north := center + Vector2.UP * radius
	var south := center + Vector2.DOWN * radius
	draw_line(north + Vector2.LEFT * 5.0 * scale, north + Vector2.RIGHT * 5.0 * scale, NORTH_COLOR, 2.0 * scale, true)
	draw_string(font, north + Vector2(8.0, 5.0) * scale, "N", HORIZONTAL_ALIGNMENT_LEFT, -1.0, hud._px(13), NORTH_COLOR)
	draw_line(south + Vector2.LEFT * 5.0 * scale, south + Vector2.RIGHT * 5.0 * scale, SOUTH_COLOR, 2.0 * scale, true)
	draw_string(font, south + Vector2(8.0, 5.0) * scale, "S", HORIZONTAL_ALIGNMENT_LEFT, -1.0, hud._px(13), SOUTH_COLOR)


func _draw_trail(center: Vector2, radius: float, scale: float) -> void:
	for index in range(_trail.size()):
		var direction := _trail[index]
		if direction.dot(_face) <= 0.0:
			continue
		var age := float(index + 1) / float(_trail.size())
		var color := Color(PLAYER_COLOR, lerpf(0.16, 0.72, age))
		draw_circle(_project(direction, center, radius), 1.6 * scale, color)


func _draw_player(center: Vector2, radius: float, scale: float) -> void:
	var position_value := _project(_direction, center, radius)
	draw_circle(position_value, 3.2 * scale, PLAYER_COLOR)
	draw_arc(position_value, 6.0 * scale, 0.0, TAU, 20, Color(PLAYER_COLOR, 0.82), 1.3 * scale, true)


func _draw_ship(center: Vector2, radius: float, scale: float) -> void:
	if main == null:
		return
	var ship := main.get("ship") as Node3D
	if not is_instance_valid(ship) or gravity_service.get_nearest_surface(ship.global_position) != _body:
		return
	var ship_offset := ship.global_position - _body.global_position
	if ship_offset.length_squared() < 0.0001:
		return
	var ship_direction := ship_offset.normalized()
	var position_value := _project(ship_direction, center, radius)
	var color: Color = hud.SHIP_COLOR
	if ship_direction.dot(_face) <= 0.0:
		color.a *= 0.32
	var diamond := PackedVector2Array([
		position_value + Vector2.UP * 5.0 * scale,
		position_value + Vector2.RIGHT * 5.0 * scale,
		position_value + Vector2.DOWN * 5.0 * scale,
		position_value + Vector2.LEFT * 5.0 * scale,
	])
	draw_colored_polygon(diamond, Color(color, color.a * 0.28))
	draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), color, 1.2 * scale, true)
	var distance_text: String = hud._format_distance(player.global_position.distance_to(ship.global_position))
	draw_string(ThemeDB.fallback_font, position_value + Vector2(7.0, -6.0) * scale, "SHIP  %s" % distance_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, hud._px(10), color)


func _draw_label(center: Vector2, radius: float, scale: float) -> void:
	var text := "%s\nLat %+.0f°" % [_body.name, _latitude_degrees]
	if _altitude >= 0.0:
		text += "  Alt %.0f m" % _altitude
	var color := Color(0.72, 0.88, 1.0, 0.9)
	draw_multiline_string(ThemeDB.fallback_font, Vector2(0.0, center.y + radius + 20.0 * scale), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, hud._px(12), 2, color)
