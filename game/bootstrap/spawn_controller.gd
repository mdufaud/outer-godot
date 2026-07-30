class_name SpawnController
extends Node

const PLAYER_SPAWN_CLEARANCE := 3.0

var main: Node3D


func setup(next_main: Node3D) -> void:
	main = next_main


func respawn() -> void:
	var earth := main.get("earth") as PlanetBody
	var sun := main.get("sun") as Node3D
	var ship := main.get("ship") as RigidBody3D
	if earth == null or sun == null or ship == null:
		return
	var player_direction: Vector3 = earth.get_sunlit_spawn_direction(sun.global_position)
	var spawn_direction: Vector3 = earth.get_nearby_land_direction(player_direction)
	var earth_velocity: Vector3 = earth.get("orbital_velocity")
	var ship_spawn := Transform3D(Basis.IDENTITY, earth.get_landing_point(spawn_direction, 2.8))
	ship.reset(ship_spawn, earth_velocity)
	spawn_on_planet(earth)


func spawn_on_planet(body: PlanetBody) -> bool:
	var player := main.get("player") as CharacterBody3D
	var ship := main.get("ship") as RigidBody3D
	var sun := main.get("sun") as Node3D
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
	var body_velocity: Vector3 = body.get("orbital_velocity")
	player.reset(Transform3D(basis, position_value), body_velocity)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("set_selected_planet"):
		hud.set_selected_planet(body.body_id)
	return true


func spawn_on_planet_id(body_id: StringName) -> bool:
	var bodies: Dictionary = main.get("_bodies_by_id")
	var body := bodies.get(body_id) as PlanetBody
	return spawn_on_planet(body) if body != null else false
