extends Node

const ORBIT_PARENTS := {
	"Terra": "Sun",
	"Luna": "Terra",
	"Cyclops": "Sun",
	"Tumbling Bean": "Cyclops",
	"Watchful Eye": "Cyclops",
}
const TWIN_VARIATION := 0.025
const FAST_FORWARD_MULTIPLIER := 60.0

var bodies: Array = []
var _bodies_by_name := {}
var _orbits := {}
var _twin_orbit := {}
var _elapsed := 0.0
var _sun_start := Vector3.ZERO
var _sun_velocity := Vector3.ZERO
var _time_multiplier := 1.0


func _ready() -> void:
	add_to_group("celestial_system")
	process_physics_priority = -100
	for body in get_tree().get_nodes_in_group("celestial_body"):
		bodies.append(body)
		_bodies_by_name[String(body.name)] = body
	_initialize_orbits()


func _physics_process(delta: float) -> void:
	if _bodies_by_name.size() < 2:
		return
	_elapsed += delta * _time_multiplier
	_update_sun()
	_update_circular_orbit("Terra")
	_update_circular_orbit("Luna")
	_update_twins()
	_update_circular_orbit("Cyclops")
	_update_circular_orbit("Tumbling Bean")
	_update_circular_orbit("Watchful Eye")


func set_fast_forward_enabled(enabled: bool) -> void:
	_time_multiplier = FAST_FORWARD_MULTIPLIER if enabled else 1.0


func _initialize_orbits() -> void:
	var sun: Node3D = _bodies_by_name.get("Sun")
	if sun == null:
		return
	_sun_start = sun.global_position
	_sun_velocity = sun.get("orbital_velocity")
	for body_name in ORBIT_PARENTS:
		var body: Node3D = _bodies_by_name.get(body_name)
		var parent: Node3D = _bodies_by_name.get(ORBIT_PARENTS[body_name])
		if body == null or parent == null:
			continue
		var offset := body.global_position - parent.global_position
		var relative_velocity: Vector3 = body.get("orbital_velocity") - parent.get("orbital_velocity")
		_orbits[body_name] = {
			"offset": offset,
			"angular_speed": offset.cross(relative_velocity).y / maxf(offset.length_squared(), 0.01),
		}
	_initialize_twins(sun)


func _initialize_twins(sun: Node3D) -> void:
	var fiery: Node3D = _bodies_by_name.get("Fiery Twin")
	var icey: Node3D = _bodies_by_name.get("Icey Twin")
	if fiery == null or icey == null:
		return
	var fiery_mu := float(fiery.call("get_gravitational_parameter"))
	var icey_mu := float(icey.call("get_gravitational_parameter"))
	var total_mu := fiery_mu + icey_mu
	var barycenter := (fiery.global_position * fiery_mu + icey.global_position * icey_mu) / total_mu
	var barycenter_velocity: Vector3 = (
		fiery.get("orbital_velocity") * fiery_mu + icey.get("orbital_velocity") * icey_mu
	) / total_mu
	var solar_offset := barycenter - sun.global_position
	var solar_relative_velocity: Vector3 = barycenter_velocity - sun.get("orbital_velocity")
	var relative_offset := fiery.global_position - icey.global_position
	var relative_velocity: Vector3 = fiery.get("orbital_velocity") - icey.get("orbital_velocity")
	_twin_orbit = {
		"solar_offset": solar_offset,
		"solar_angular_speed": solar_offset.cross(solar_relative_velocity).y / maxf(solar_offset.length_squared(), 0.01),
		"fiery_offset": fiery.global_position - barycenter,
		"icey_offset": icey.global_position - barycenter,
		"binary_angular_speed": relative_offset.cross(relative_velocity).y / maxf(relative_offset.length_squared(), 0.01),
	}


func _update_sun() -> void:
	var sun: Node3D = _bodies_by_name.get("Sun")
	if sun != null:
		sun.set_orbital_state(_sun_start + _sun_velocity * _elapsed, _sun_velocity * _time_multiplier)


func _update_circular_orbit(body_name: String) -> void:
	if not _orbits.has(body_name):
		return
	var body: Node3D = _bodies_by_name[body_name]
	var parent: Node3D = _bodies_by_name[ORBIT_PARENTS[body_name]]
	var orbit: Dictionary = _orbits[body_name]
	var angular_speed: float = orbit.angular_speed
	var angle := fposmod(angular_speed * _elapsed, TAU)
	var offset: Vector3 = orbit.offset.rotated(Vector3.UP, angle)
	var velocity: Vector3 = parent.get("orbital_velocity") + Vector3.UP.cross(offset) * angular_speed * _time_multiplier
	body.set_orbital_state(parent.global_position + offset, velocity)


func _update_twins() -> void:
	if _twin_orbit.is_empty():
		return
	var sun: Node3D = _bodies_by_name["Sun"]
	var solar_speed: float = _twin_orbit.solar_angular_speed
	var solar_angle := fposmod(solar_speed * _elapsed, TAU)
	var barycenter_offset: Vector3 = _twin_orbit.solar_offset.rotated(Vector3.UP, solar_angle)
	var barycenter_position := sun.global_position + barycenter_offset
	var barycenter_velocity: Vector3 = sun.get("orbital_velocity") + Vector3.UP.cross(barycenter_offset) * solar_speed * _time_multiplier
	var binary_speed: float = _twin_orbit.binary_angular_speed
	var binary_angle := fposmod(binary_speed * _elapsed, TAU)
	var scale := 1.0 - TWIN_VARIATION + TWIN_VARIATION * cos(binary_angle)
	var scale_velocity := -TWIN_VARIATION * sin(binary_angle) * binary_speed
	_update_twin("Fiery Twin", _twin_orbit.fiery_offset, binary_angle, scale, scale_velocity, binary_speed, barycenter_position, barycenter_velocity)
	_update_twin("Icey Twin", _twin_orbit.icey_offset, binary_angle, scale, scale_velocity, binary_speed, barycenter_position, barycenter_velocity)


func _update_twin(
	body_name: String,
	initial_offset: Vector3,
	angle: float,
	scale: float,
	scale_velocity: float,
	angular_speed: float,
	barycenter_position: Vector3,
	barycenter_velocity: Vector3
) -> void:
	var body: Node3D = _bodies_by_name[body_name]
	var rotated_offset := initial_offset.rotated(Vector3.UP, angle)
	var offset := rotated_offset * scale
	var velocity := barycenter_velocity + (
		Vector3.UP.cross(rotated_offset) * angular_speed * scale + rotated_offset * scale_velocity
	) * _time_multiplier
	body.set_orbital_state(barycenter_position + offset, velocity)
