extends RefCounted

# The contract every planet must honour, stated as relations between its own numbers so it holds at
# any size: a body you can stand on, whose gravity pulls towards its centre and dies out at its
# influence edge, whose terrain is finite and reproducible, and whose ocean (if any) leaves a
# reachable landing spot.

const TestWorldScript := preload("res://tests/shared/test_world.gd")
const PlanetGeneratorScript := preload("res://game/planets/shared/planet_generator.gd")

# Degenerate or runaway terrain: a factor near zero collapses the planet into its core, a huge one
# turns it into a spike ball. Deformed bodies legitimately sit far from 1.0, so the window is wide.
const MIN_HEIGHT_FACTOR := 0.1
const MAX_HEIGHT_FACTOR := 3.0


static func run(tree: SceneTree, config: PlanetConfig, report: RefCounted, label: String) -> void:
	var body := TestWorldScript.spawn_body(tree, config)
	var directions := TestWorldScript.sphere_directions()
	_test_config_sanity(config, report, label)
	_test_terrain(body, config, report, label)
	_test_determinism(config, report, label)
	_test_ocean(body, directions, report, label)
	_test_gravity(body, report, label)
	_test_landing(body, directions, report, label)
	body.queue_free()


static func _test_config_sanity(config: PlanetConfig, report: RefCounted, label: String) -> void:
	report.expect(config.radius > 0.0, "%s: radius must be positive" % label)
	report.expect(config.surface_gravity > 0.0, "%s: surface gravity must be positive" % label)
	report.expect(config.core_radius >= 0.0 and config.core_radius < config.radius, "%s: core radius must sit inside the planet" % label)
	report.expect(config.influence_scale > 1.0, "%s: influence radius must reach past the surface" % label)


static func _test_terrain(body: PlanetBody, config: PlanetConfig, report: RefCounted, label: String) -> void:
	var generator := PlanetGeneratorScript.new(config.shape_profile, config.rng_seed)
	var lowest := INF
	var highest := -INF
	for direction in TestWorldScript.sphere_directions():
		var factor: float = generator.sample_factor(direction)
		if not is_finite(factor):
			report.expect(false, "%s: terrain height is not finite towards %v" % [label, direction])
			return
		lowest = minf(lowest, factor)
		highest = maxf(highest, factor)
		var surface_radius := body.get_surface_radius_towards(direction)
		report.expect(surface_radius > 0.0, "%s: surface collapsed to the centre towards %v" % [label, direction])
	report.expect(lowest > MIN_HEIGHT_FACTOR, "%s: terrain collapses into the core (lowest factor %f)" % [label, lowest])
	report.expect(highest < MAX_HEIGHT_FACTOR, "%s: terrain spikes out of the planet (highest factor %f)" % [label, highest])
	report.expect(highest > lowest, "%s: terrain is a perfect sphere" % label)


static func _test_determinism(config: PlanetConfig, report: RefCounted, label: String) -> void:
	var direction := Vector3(0.31, 0.62, -0.72).normalized()
	# Reproducibility, not seed sensitivity: some profiles carry their own internal seeds and ignore
	# the configured one. What every planet owes is the same shape on every run, because the mesh
	# cache, the collider and the orbit placement all assume it.
	var first := PlanetGeneratorScript.new(config.shape_profile, config.rng_seed)
	var second := PlanetGeneratorScript.new(config.shape_profile, config.rng_seed)
	for direction_value in [direction, Vector3.UP, Vector3(-0.8, 0.1, 0.6).normalized()]:
		report.expect(is_equal_approx(first.sample_factor(direction_value), second.sample_factor(direction_value)), "%s: the same seed produced two different worlds" % label)


static func _test_ocean(body: PlanetBody, directions: Array[Vector3], report: RefCounted, label: String) -> void:
	if not body.has_ocean:
		for direction in directions:
			if body.get_water_depth(body.global_position + direction * body.radius) != -INF:
				report.expect(false, "%s: a dry planet reports water towards %v" % [label, direction])
				return
		return
	var sea := body.sea_level()
	report.expect(body.get_water_depth(body.global_position + Vector3.UP * (sea - 1.0)) > 0.0, "%s: no water just below the sea surface" % label)
	report.expect(body.get_water_depth(body.global_position + Vector3.UP * (sea + 1.0)) < 0.0, "%s: water reported above the sea surface" % label)
	var wet := 0
	var deepest := INF
	for direction in directions:
		var surface_radius := body.get_surface_radius_towards(direction)
		deepest = minf(deepest, surface_radius)
		if surface_radius < sea:
			wet += 1
	report.expect(deepest < sea, "%s: the sea bed is above the sea everywhere, there is no water" % label)
	if body.weather_enabled:
		# A storm world is drowned by design: its only dry ground is the landing rocks.
		report.expect(wet == directions.size(), "%s: the storm ocean no longer covers the whole planet (%d of %d)" % [label, wet, directions.size()])
	else:
		report.expect(wet > 0, "%s: the ocean has no water anywhere" % label)
		report.expect(wet < directions.size(), "%s: the ocean drowned the whole planet" % label)


static func _test_gravity(body: PlanetBody, report: RefCounted, label: String) -> void:
	var gravity := TestWorldScript.spawn_gravity(body)
	var direction := Vector3(0.4, 0.7, 0.6).normalized()
	var surface_radius := body.get_surface_radius_towards(direction)
	var inside: Vector3 = gravity.get_gravity(body.global_position + direction * surface_radius * 0.99)
	var outside: Vector3 = gravity.get_gravity(body.global_position + direction * surface_radius * 1.01)
	report.expect_close(inside.length(), body.surface_gravity, body.surface_gravity * 0.05, "%s: gravity below the surface is not the surface gravity" % label)
	report.expect_close(outside.length(), inside.length(), body.surface_gravity * 0.05, "%s: gravity jumps across the surface" % label)
	report.expect(inside.normalized().dot(-direction) > 0.999, "%s: gravity does not point at the centre" % label)
	var magnitudes: Array[float] = []
	for step in 24:
		var distance: float = lerpf(surface_radius, body.influence_radius, (float(step) + 1.0) / 24.0)
		magnitudes.append(gravity.get_gravity(body.global_position + direction * distance).length())
	report.expect_decreasing(magnitudes, "%s: gravity does not fall off with distance" % label)
	report.expect(is_zero_approx(gravity.get_gravity(body.global_position + direction * body.influence_radius * 1.01).length()), "%s: gravity reaches past the influence radius" % label)
	report.expect(is_finite(gravity.get_gravity(body.global_position).length()), "%s: gravity is undefined at the centre" % label)


static func _test_landing(body: PlanetBody, directions: Array[Vector3], report: RefCounted, label: String) -> void:
	var clearance := 3.0
	for direction in directions:
		var landing := body.get_landing_point(direction, clearance)
		var altitude := body.global_position.distance_to(landing)
		# A storm world lands on its ocean, every other world lands on the ground it collides with.
		var floor_radius: float = body.sea_level() if body.weather_enabled and body.has_ocean else body.get_surface_radius_towards(direction)
		if absf(altitude - (floor_radius + clearance)) > 0.001:
			report.expect(false, "%s: landing point towards %v is %f, not %f above the ground at %f" % [label, direction, altitude, clearance, floor_radius])
			return
		report.expect(direction.dot((landing - body.global_position).normalized()) > 0.999, "%s: landing point towards %v drifted off its direction" % [label, direction])
	var sun_position := body.global_position + Vector3(1.0, 0.3, 0.2).normalized() * body.influence_radius * 40.0
	var sunlit := body.get_sunlit_spawn_direction(sun_position)
	report.expect(sunlit.dot((sun_position - body.global_position).normalized()) > 0.0, "%s: the spawn spot faces away from the sun" % label)
	if body.has_ocean and not body.weather_enabled:
		report.expect(body.get_surface_radius_towards(sunlit) > body.sea_level(), "%s: the spawn spot is under water" % label)
		var nearby := body.get_nearby_land_direction(sunlit)
		report.expect(body.get_surface_radius_towards(nearby) > body.sea_level(), "%s: the nearby landing spot is under water" % label)
		report.expect(sunlit.angle_to(nearby) < 0.5, "%s: the nearby landing spot is not nearby" % label)
