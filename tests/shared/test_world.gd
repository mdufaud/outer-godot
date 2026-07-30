extends RefCounted

# Boots planets for tests: reads a body's authored config from the manifest, then puts a non-booting
# copy of it in the tree. No test ever hardcodes an authored number, so retuning a planet in its own
# script is picked up here automatically.

const ManifestScript := preload("res://game/celestial/solar_system_manifest.gd")
const TestBodyScript := preload("res://tests/shared/test_body.gd")
const GravityScript := preload("res://game/celestial/gravity.gd")

const SAMPLE_COUNT := 512


static func get_entry(body_id: StringName) -> CelestialEntry:
	for entry in ManifestScript.get_entries():
		if entry.body_id == body_id:
			return entry
	return null


static func authored_config(body_id: StringName) -> PlanetConfig:
	var entry := get_entry(body_id)
	if entry == null:
		return null
	var body: PlanetBody = entry.scene.instantiate()
	var config: PlanetConfig = body.create_planet_config()
	body.free()
	return config


static func spawn_body(tree: SceneTree, config: PlanetConfig) -> PlanetBody:
	var body: PlanetBody = TestBodyScript.new()
	body.name = "TestBody%d" % tree.root.get_child_count()
	tree.root.add_child(body)
	body.apply(config)
	return body


static func spawn_gravity(body: PlanetBody) -> GravityService:
	var gravity := GravityScript.new()
	gravity.register(body)
	return gravity


# Evenly spread directions, so terrain coverage never depends on a lucky sample.
static func sphere_directions(count := SAMPLE_COUNT) -> Array[Vector3]:
	var directions: Array[Vector3] = []
	var golden_angle := PI * (3.0 - sqrt(5.0))
	for index in count:
		var y := 1.0 - 2.0 * (float(index) + 0.5) / float(count)
		var radial := sqrt(maxf(0.0, 1.0 - y * y))
		var angle := golden_angle * float(index)
		directions.append(Vector3(cos(angle) * radial, y, sin(angle) * radial))
	return directions
