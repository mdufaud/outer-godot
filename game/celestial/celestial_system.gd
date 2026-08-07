extends Node

const CelestialEntryScript := preload("res://game/celestial/celestial_entry.gd")

const FAST_FORWARD_MULTIPLIER := 60.0
const MAX_SUBSTEP := 1.0 / 120.0
const MIN_SEPARATION := 0.01
const PERTURBATION_SCALE := 0.1

var bodies: Array = []
var entries: Array[CelestialEntry] = []
var _body_by_id: Dictionary = {}
var _orbit_parents: Dictionary = {}
var _sim_ids: Array[StringName] = []
var _positions := PackedFloat64Array()
var _velocities := PackedFloat64Array()
var _pair_mu: Array[PackedFloat64Array] = []
var _entry_of_body: Array[int] = []
var _binary_bodies: Array[Node3D] = []
var _binary_entry := -1
var _binary_offsets: Array[Vector3] = []
var _binary_angular_speed := 0.0
var _binary_angle := 0.0
var _time_multiplier := 1.0


func configure(next_entries: Array[CelestialEntry], next_bodies: Dictionary, sun: Node3D) -> void:
	entries = next_entries
	_body_by_id = next_bodies.duplicate()
	_body_by_id[&"sun"] = sun


func _ready() -> void:
	add_to_group("celestial_system")
	add_to_group("origin_shift_listener")
	process_physics_priority = -100
	_initialize_simulation()


func _initialize_simulation() -> void:
	if entries.is_empty():
		return
	bodies.clear()
	_sim_ids.clear()
	_orbit_parents.clear()
	_entry_of_body.clear()
	_binary_bodies.clear()
	_binary_entry = -1

	var sun: Node3D = _body_by_id.get(&"sun")
	if sun != null:
		bodies.append(sun)
		_sim_ids.append(&"sun")

	var binary_groups: Dictionary = {}
	for entry in entries:
		var body: Node3D = _body_by_id.get(entry.body_id)
		if body == null:
			continue
		if entry.binary_group_id.is_empty():
			bodies.append(body)
			_sim_ids.append(entry.body_id.to_lower())
			_orbit_parents[entry.body_id.to_lower()] = entry.orbit_parent_id
		else:
			if not binary_groups.has(entry.binary_group_id):
				binary_groups[entry.binary_group_id] = []
			binary_groups[entry.binary_group_id].append({"entry": entry, "body": body})

	for group_id in binary_groups:
		var group: Array = binary_groups[group_id]
		if group.size() != 2:
			continue
		var first: Node3D = group[0].body
		var second: Node3D = group[1].body
		_binary_bodies = [first, second]
		var first_mu := float(first.call("get_gravitational_parameter"))
		var second_mu := float(second.call("get_gravitational_parameter"))
		var total_mu := first_mu + second_mu
		var barycenter := (first.global_position * first_mu + second.global_position * second_mu) / total_mu
		var separation := first.global_position.distance_to(second.global_position)
		_binary_entry = _sim_ids.size()
		_sim_ids.append(StringName(group_id))
		_orbit_parents[StringName(group_id)] = group[0].entry.orbit_parent_id
		_binary_offsets = [first.global_position - barycenter, second.global_position - barycenter]
		_binary_angular_speed = sqrt(total_mu / maxf(separation * separation * separation, MIN_SEPARATION))
		bodies.append(first)
		bodies.append(second)

	for body in bodies:
		_entry_of_body.append(_body_entry(body))

	var positions: Array[Vector3] = []
	var mu: Array[float] = []
	for sim_id in _sim_ids:
		if sim_id == &"sun":
			positions.append(Vector3.ZERO)
			mu.append(float(sun.call("get_gravitational_parameter")))
		elif _binary_entry == _sim_ids.find(sim_id):
			var binary_mu := 0.0
			for binary_body in _binary_bodies:
				binary_mu += float(binary_body.call("get_gravitational_parameter"))
			positions.append((_binary_bodies[0].global_position * float(_binary_bodies[0].call("get_gravitational_parameter")) + _binary_bodies[1].global_position * float(_binary_bodies[1].call("get_gravitational_parameter"))) / binary_mu)
			mu.append(binary_mu)
		else:
			var body: Node3D = _body_by_id.get(_entry_id_from_sim_id(sim_id))
			positions.append(body.global_position)
			mu.append(float(body.call("get_gravitational_parameter")))
	_positions = pack_state(positions)
	_velocities = pack_state(compute_initial_velocities(_sim_ids, positions, mu, _orbit_parents))
	_pair_mu = build_pair_mu(_sim_ids, mu, _orbit_parents)
	_publish_states()


func _body_entry(body: Node3D) -> int:
	if body == _body_by_id.get(&"sun"):
		return _sim_ids.find(&"sun")
	for entry in entries:
		if _body_by_id.get(entry.body_id) != body:
			continue
		if entry.binary_group_id.is_empty():
			return _sim_ids.find(entry.body_id.to_lower())
		return _binary_entry
	return -1


func _entry_id_from_sim_id(sim_id: StringName) -> StringName:
	for entry in entries:
		if entry.body_id.to_lower() == sim_id:
			return entry.body_id
	return sim_id


func _physics_process(delta: float) -> void:
	if _pair_mu.size() < 2:
		return
	var scaled_delta := delta * _time_multiplier
	var steps := maxi(1, int(ceil(scaled_delta / MAX_SUBSTEP)))
	var step := scaled_delta / float(steps)
	for _index in steps:
		step_simulation(_positions, _velocities, _pair_mu, step)
	_binary_angle = fposmod(_binary_angle + _binary_angular_speed * scaled_delta, TAU)
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


# Bodies can be destroyed mid-flight by the leviathan. Their slot keeps orbiting
# in the integrator arrays — resizing those would mean rebuilding every pair mass
# and ancestor chain in flight for no visible gain — but nothing may be written
# to a freed node.
func _publish_states() -> void:
	for index in bodies.size():
		var entry := _entry_of_body[index]
		if entry < 0:
			continue
		if entry == _binary_entry:
			continue
		if not is_instance_valid(bodies[index]):
			continue
		bodies[index].set_orbital_state(read_state(_positions, entry), read_state(_velocities, entry) * _time_multiplier)
	if _binary_entry == -1:
		return
	var barycenter := read_state(_positions, _binary_entry)
	var barycenter_velocity := read_state(_velocities, _binary_entry)
	for index in _binary_bodies.size():
		if not is_instance_valid(_binary_bodies[index]):
			continue
		var offset: Vector3 = _binary_offsets[index].rotated(Vector3.UP, _binary_angle)
		var spin := Vector3.UP.cross(offset) * _binary_angular_speed
		_binary_bodies[index].set_orbital_state(barycenter + offset, (barycenter_velocity + spin) * _time_multiplier)


static func step_simulation(positions: PackedFloat64Array, velocities: PackedFloat64Array, pair_mu: Array[PackedFloat64Array], delta: float) -> void:
	var count := pair_mu.size()
	for i in count:
		var base := i * 3
		var x := positions[base]
		var y := positions[base + 1]
		var z := positions[base + 2]
		var acceleration := Vector3.ZERO
		var row: PackedFloat64Array = pair_mu[i]
		for j in count:
			if i == j:
				continue
			var other := j * 3
			var delta_position := Vector3(positions[other] - x, positions[other + 1] - y, positions[other + 2] - z)
			var distance := delta_position.length()
			if distance < MIN_SEPARATION:
				continue
			acceleration += delta_position * row[j] / (distance * distance * distance)
		velocities[base] += acceleration.x * delta
		velocities[base + 1] += acceleration.y * delta
		velocities[base + 2] += acceleration.z * delta
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


static func build_pair_mu(ids: Array[StringName], mu: Array[float], orbit_parents: Dictionary = {}) -> Array[PackedFloat64Array]:
	var pair_mu: Array[PackedFloat64Array] = []
	for i in ids.size():
		var row := PackedFloat64Array()
		row.resize(ids.size())
		if ids[i] == &"sun":
			pair_mu.append(row)
			continue
		var ancestors := _ancestors_of(ids[i], orbit_parents)
		for j in ids.size():
			row[j] = mu[j] * (1.0 if ids[j] in ancestors else PERTURBATION_SCALE)
		pair_mu.append(row)
	return pair_mu


static func _ancestors_of(body_id: StringName, orbit_parents: Dictionary) -> Array[StringName]:
	var ancestors: Array[StringName] = []
	var current := body_id
	while orbit_parents.has(current):
		current = orbit_parents[current]
		ancestors.append(current)
	return ancestors


static func compute_initial_velocities(ids: Array[StringName], positions: Array[Vector3], mu: Array[float], orbit_parents: Dictionary = {}) -> Array[Vector3]:
	var index_of := {}
	for i in ids.size():
		index_of[ids[i]] = i
	var velocities: Array[Vector3] = []
	velocities.resize(ids.size())
	velocities.fill(Vector3.ZERO)
	for body_id in orbit_parents:
		if not index_of.has(body_id) or not index_of.has(orbit_parents[body_id]):
			continue
		var body_index: int = index_of[body_id]
		var parent_index: int = index_of[orbit_parents[body_id]]
		velocities[body_index] = velocities[parent_index] + _circular_velocity(
			positions[body_index] - positions[parent_index], mu[parent_index]
		)
	return velocities


static func _circular_velocity(offset: Vector3, parent_mu: float) -> Vector3:
	var distance := offset.length()
	if distance < MIN_SEPARATION:
		return Vector3.ZERO
	return Vector3.UP.cross(offset).normalized() * sqrt(parent_mu / distance)


func total_energy() -> float:
	if _positions.is_empty() or _sim_ids.is_empty():
		return 0.0
	var energy := 0.0
	for index in _sim_ids.size():
		var velocity := read_state(_velocities, index)
		var mass_mu := 1.0
		if index < _pair_mu.size():
			for value in _pair_mu[index]:
				mass_mu = maxf(mass_mu, value)
		energy += 0.5 * mass_mu * velocity.length_squared()
		for other in range(index + 1, _sim_ids.size()):
			var distance := read_state(_positions, index).distance_to(read_state(_positions, other))
			if distance > MIN_SEPARATION:
				energy -= mass_mu * maxf(_pair_mu[other][index], 0.0) / distance
	return energy
