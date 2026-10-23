class_name SpawnController
extends Node

const PLAYER_SPAWN_CLEARANCE := 3.0
const SHIP_SITE_MIN_ARC := 8.0
const SHIP_SITE_MAX_ARC := 25.0
const SHIP_SITE_MAX_ANGLE := 1.0
const SHIP_SITE_ATTEMPTS := 192
const SHIP_BELLY_RISE := 0.6
const SHIP_BELLY_PENALTY := 2.0
const SHIP_DROP_MARGIN := 0.2
const SHIP_HOVER_HEIGHT := 12.0
const SHIP_SEA_MARGIN := 0.7
const RECALL_MIN_DISTANCE := 25.0

var main: Main


func setup(next_main: Main) -> void:
	main = next_main


func respawn() -> void:
	var earth := main.earth
	if earth == null or main.sun == null or main.ship == null:
		return
	spawn_on_planet(earth)
	place_ship(earth)


func place_ship(body: PlanetBody) -> void:
	var player_position := main.player.global_position
	main.ship.place(find_ship_site(body, player_position - body.global_position, player_position), body)


func recall_ship() -> void:
	var player := main.player
	var ship := main.ship
	if ship == null or player.piloting:
		return
	var gravity_service := get_node("/root/Gravity") as GravityService
	var body := gravity_service.get_nearest_surface(player.global_position)
	var message := "Ship called"
	if body == null or not player.is_on_floor():
		message = "Need solid ground to call the ship"
	elif ship.global_position.distance_to(player.global_position) < RECALL_MIN_DISTANCE:
		message = "The ship is right here"
	else:
		place_ship(body)
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if hud != null:
		hud.flash(message)


# The flattest dry spot 8-25 m of arc away: four feet as level as possible and the
# belly clear of the ground between them, nose turned towards face_point.
func find_ship_site(body: PlanetBody, origin_direction: Vector3, face_point: Vector3) -> Transform3D:
	var origin := origin_direction.normalized()
	var tangent := origin.cross(Vector3.UP)
	if tangent.length_squared() < 0.001:
		tangent = origin.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var core_radius := body.get_core_radius()
	var rng := RandomNumberGenerator.new()
	rng.seed = body.rng_seed * 1543 + 29
	var best := Transform3D()
	var best_score := INF
	for _attempt in SHIP_SITE_ATTEMPTS:
		var angle := minf(rng.randf_range(SHIP_SITE_MIN_ARC, SHIP_SITE_MAX_ARC) / core_radius, SHIP_SITE_MAX_ANGLE)
		var up := origin.rotated(tangent.rotated(origin, rng.randf_range(0.0, TAU)), angle)
		var basis := upright_basis(up, face_point - body.global_position)
		var lowest := INF
		var highest := -INF
		var ground: Array[Vector3] = []
		for foot in Ship.FEET:
			var direction := up * core_radius + basis.x * foot.x + basis.z * foot.z
			var foot_radius := body.get_collider_surface_radius(direction)
			ground.append(direction.normalized() * foot_radius)
			lowest = minf(lowest, foot_radius)
			highest = maxf(highest, foot_radius)
		if body.has_ocean and lowest <= body.sea_level() + SHIP_SEA_MARGIN:
			continue
		var belly := up * body.get_collider_surface_radius(up)
		var score := highest - lowest + maxf(belly.length() - lowest - SHIP_BELLY_RISE, 0.0) * SHIP_BELLY_PENALTY
		if score >= best_score:
			continue
		best_score = score
		# Stand on the plane through the four feet so they all touch at once,
		# instead of landing on one or two and slowly tipping onto the rest.
		var normal := (ground[3] - ground[0]).cross(ground[1] - ground[2]).normalized()
		if normal.dot(up) < 0.0:
			normal = -normal
		var center := (ground[0] + ground[1] + ground[2] + ground[3]) * 0.25
		var twist := 0.0
		for point in ground:
			twist = maxf(twist, (point - center).dot(normal))
		var height := maxf(Ship.LEG_DEPTH + twist, (belly - center).dot(normal) + Ship.HULL_RADIUS - Ship.HULL_CENTER.y)
		var tilted := upright_basis(normal, face_point - body.global_position)
		var site_origin := center + normal * (height + SHIP_DROP_MARGIN)
		# Tilting slid the feet sideways over rough ground: lift any that now dig in.
		var sink := 0.0
		for foot in Ship.FEET:
			var foot_offset := site_origin + tilted * foot
			sink = maxf(sink, body.get_collider_surface_radius(foot_offset) - foot_offset.length())
		best = Transform3D(tilted, body.global_position + site_origin + normal * sink)
	if best_score < INF:
		return best
	var fallback := origin.rotated(tangent, minf(SHIP_SITE_MIN_ARC / core_radius, SHIP_SITE_MAX_ANGLE))
	var ground := maxf(body.get_collider_surface_radius(fallback), body.sea_level() if body.has_ocean else 0.0)
	return Transform3D(upright_basis(fallback, face_point - body.global_position), body.global_position + fallback * (ground + SHIP_HOVER_HEIGHT))


static func upright_basis(up: Vector3, toward: Vector3) -> Basis:
	var forward := toward - up * up.dot(toward)
	if forward.length_squared() < 0.0001:
		forward = up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD)
	var back := -forward.normalized()
	return Basis(up.cross(back), up, back).orthonormalized()


func spawn_on_planet(body: PlanetBody) -> bool:
	var player := main.player
	var ship := main.ship
	var sun := main.sun
	if body == null or player == null or sun == null:
		return false
	if ship != null and ship.pilot == player:
		ship.exit_pilot()
	var direction: Vector3 = body.get_sunlit_spawn_direction(sun.global_position)
	var position_value: Vector3 = body.get_landing_point(direction, PLAYER_SPAWN_CLEARANCE)
	var x_axis := -Vector3.BACK.cross(direction)
	if x_axis.length_squared() < 0.001:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	var basis := Basis(x_axis, direction, x_axis.cross(direction)).orthonormalized()
	player.reset(Transform3D(basis, position_value), body.orbital_velocity)
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if hud != null:
		hud.set_selected_planet(body.body_id)
	return true
