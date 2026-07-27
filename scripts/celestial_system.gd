extends Node

const ORBIT_PARENTS := {
	"Terra": "Sun",
	"Luna": "Terra",
	"Twins": "Sun",
	"Cyclops": "Sun",
	"Tumbling Bean": "Cyclops",
	"Watchful Eye": "Cyclops",
	"Mirage": "Sun",
}
const TWIN_NAMES := ["Fiery Twin", "Icey Twin"]
const TWIN_ENTRY := "Twins"
const FAST_FORWARD_MULTIPLIER := 60.0
const MAX_SUBSTEP := 1.0 / 120.0
const MIN_SEPARATION := 0.01
# Bodies weigh several percent of the sun, so undamped cross-pulls wreck the
# system within hours. Hierarchy pairs keep their full pull, the rest is damped.
const PERTURBATION_SCALE := 0.1

var bodies: Array = []
var _positions := PackedFloat64Array()
var _velocities := PackedFloat64Array()
var _pair_mu: Array[PackedFloat64Array] = []
# Simulated entry index per body, so the twin pair can share a single entry.
var _entry_of_body: Array[int] = []
var _twin_bodies: Array[Node3D] = []
var _twin_entry := -1
var _twin_offsets: Array[Vector3] = []
var _twin_angular_speed := 0.0
var _twin_angle := 0.0
var _time_multiplier := 1.0


func _ready() -> void:
	add_to_group("celestial_system")
	add_to_group("origin_shift_listener")
	process_physics_priority = -100
	var names: Array[String] = []
	var mu: Array[float] = []
	var positions: Array[Vector3] = []
	for body in get_tree().get_nodes_in_group("celestial_body"):
		bodies.append(body)
		var body_name := String(body.name)
		var body_mu := float(body.call("get_gravitational_parameter"))
		if body_name in TWIN_NAMES:
			_twin_bodies.append(body)
			_entry_of_body.append(-1)
			continue
		_entry_of_body.append(names.size())
		names.append(body_name)
		positions.append(body.global_position)
		mu.append(body_mu)
	_setup_twin_entry(names, positions, mu)
	_positions = pack_state(positions)
	_velocities = pack_state(compute_initial_velocities(names, positions, mu))
	_pair_mu = build_pair_mu(names, mu)
	_publish_states()


func _physics_process(delta: float) -> void:
	if _pair_mu.size() < 2:
		return
	var scaled_delta := delta * _time_multiplier
	var steps := maxi(1, int(ceil(scaled_delta / MAX_SUBSTEP)))
	var step := scaled_delta / float(steps)
	for i in steps:
		step_simulation(_positions, _velocities, _pair_mu, step)
	_twin_angle = fposmod(_twin_angle + _twin_angular_speed * scaled_delta, TAU)
	_publish_states()


func apply_origin_shift(offset: Vector3) -> void:
	for index in range(0, _positions.size(), 3):
		_positions[index] += offset.x
		_positions[index + 1] += offset.y
		_positions[index + 2] += offset.z


func set_fast_forward_enabled(enabled: bool) -> void:
	_time_multiplier = FAST_FORWARD_MULTIPLIER if enabled else 1.0
	get_tree().call_group("fast_time_affected", "set_fast_time_enabled", enabled)


func is_fast_forward_enabled() -> bool:
	return _time_multiplier != 1.0


# The twins sit at roughly half their mutual Hill radius: an integrated binary
# gets torn apart by the sun within hours, so only their barycenter is
# simulated and the pair spins around it at the two-body circular rate.
func _setup_twin_entry(names: Array[String], positions: Array[Vector3], mu: Array[float]) -> void:
	if _twin_bodies.size() != 2:
		return
	var first_mu: float = _twin_bodies[0].call("get_gravitational_parameter")
	var second_mu: float = _twin_bodies[1].call("get_gravitational_parameter")
	var total_mu := first_mu + second_mu
	var first_position: Vector3 = _twin_bodies[0].global_position
	var second_position: Vector3 = _twin_bodies[1].global_position
	var barycenter := (first_position * first_mu + second_position * second_mu) / total_mu
	var separation := first_position.distance_to(second_position)
	_twin_entry = names.size()
	names.append(TWIN_ENTRY)
	positions.append(barycenter)
	mu.append(total_mu)
	_twin_offsets = [first_position - barycenter, second_position - barycenter]
	_twin_angular_speed = sqrt(total_mu / (separation * separation * separation))
	for index in bodies.size():
		if bodies[index] in _twin_bodies:
			_entry_of_body[index] = _twin_entry


func _publish_states() -> void:
	for index in bodies.size():
		var entry := _entry_of_body[index]
		if entry == _twin_entry and _twin_entry != -1:
			continue
		bodies[index].set_orbital_state(
			read_state(_positions, entry), read_state(_velocities, entry) * _time_multiplier
		)
	if _twin_entry == -1:
		return
	var barycenter := read_state(_positions, _twin_entry)
	var barycenter_velocity := read_state(_velocities, _twin_entry)
	for twin in _twin_bodies.size():
		var offset: Vector3 = _twin_offsets[twin].rotated(Vector3.UP, _twin_angle)
		var spin := Vector3.UP.cross(offset) * _twin_angular_speed
		_twin_bodies[twin].set_orbital_state(
			barycenter + offset, (barycenter_velocity + spin) * _time_multiplier
		)


# Semi-implicit Euler over the full body set: every body pulls every other one,
# so orbits are elliptical and moons drift instead of following fixed circles.
# State is packed float64 xyz triplets: Vector3 is float32, and at 11 km from
# the origin its rounding turns into metres of orbital drift over a long session.
# pair_mu[i][j] is the gravitational parameter body j shows to body i.
static func step_simulation(positions: PackedFloat64Array, velocities: PackedFloat64Array, pair_mu: Array[PackedFloat64Array], delta: float) -> void:
	var count := pair_mu.size()
	for i in count:
		var base := i * 3
		var x := positions[base]
		var y := positions[base + 1]
		var z := positions[base + 2]
		var acceleration_x := 0.0
		var acceleration_y := 0.0
		var acceleration_z := 0.0
		var row: PackedFloat64Array = pair_mu[i]
		for j in count:
			if i == j:
				continue
			var other := j * 3
			var dx := positions[other] - x
			var dy := positions[other + 1] - y
			var dz := positions[other + 2] - z
			var distance := sqrt(dx * dx + dy * dy + dz * dz)
			if distance < MIN_SEPARATION:
				continue
			var pull: float = row[j] / (distance * distance * distance)
			acceleration_x += dx * pull
			acceleration_y += dy * pull
			acceleration_z += dz * pull
		velocities[base] += acceleration_x * delta
		velocities[base + 1] += acceleration_y * delta
		velocities[base + 2] += acceleration_z * delta
	for i in positions.size():
		positions[i] += velocities[i] * delta


static func pack_state(values: Array[Vector3]) -> PackedFloat64Array:
	var packed := PackedFloat64Array()
	packed.resize(values.size() * 3)
	for i in values.size():
		packed[i * 3] = values[i].x
		packed[i * 3 + 1] = values[i].y
		packed[i * 3 + 2] = values[i].z
	return packed


static func read_state(packed: PackedFloat64Array, index: int) -> Vector3:
	var base := index * 3
	return Vector3(packed[base], packed[base + 1], packed[base + 2])


# A body feels its own ancestors at full strength and everything else damped.
# The sun defines the fixed simulation frame and therefore feels no pull.
static func build_pair_mu(names: Array[String], mu: Array[float]) -> Array[PackedFloat64Array]:
	var pair_mu: Array[PackedFloat64Array] = []
	for i in names.size():
		var row := PackedFloat64Array()
		row.resize(names.size())
		if names[i] == "Sun":
			pair_mu.append(row)
			continue
		var ancestors := _ancestors_of(names[i])
		for j in names.size():
			row[j] = mu[j] * (1.0 if names[j] in ancestors else PERTURBATION_SCALE)
		pair_mu.append(row)
	return pair_mu


static func _ancestors_of(body_name: String) -> Array[String]:
	var ancestors: Array[String] = []
	var current := body_name
	while ORBIT_PARENTS.has(current):
		current = ORBIT_PARENTS[current]
		ancestors.append(current)
	return ancestors


# The simulation only stays bounded if it starts from two-body circular states,
# so velocities are derived from the hierarchy instead of being authored.
static func compute_initial_velocities(names: Array[String], positions: Array[Vector3], mu: Array[float]) -> Array[Vector3]:
	var index_of := {}
	for i in names.size():
		index_of[names[i]] = i
	var velocities: Array[Vector3] = []
	velocities.resize(names.size())
	velocities.fill(Vector3.ZERO)

	for body_name in ORBIT_PARENTS:
		if not index_of.has(body_name):
			continue
		var chain: Array[String] = [body_name]
		var parent_name: String = ORBIT_PARENTS[body_name]
		while ORBIT_PARENTS.has(parent_name):
			chain.push_front(parent_name)
			parent_name = ORBIT_PARENTS[parent_name]
		for link in chain:
			var i: int = index_of[link]
			var parent: int = index_of[ORBIT_PARENTS[link]]
			velocities[i] = velocities[parent] + _circular_velocity(
				positions[i] - positions[parent], mu[parent]
			)

	return velocities


static func _circular_velocity(offset: Vector3, parent_mu: float) -> Vector3:
	var distance := offset.length()
	if distance < MIN_SEPARATION:
		return Vector3.ZERO
	var direction := Vector3.UP.cross(offset).normalized()
	return direction * sqrt(parent_mu / distance)
