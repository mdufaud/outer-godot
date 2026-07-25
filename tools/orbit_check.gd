extends SceneTree

# Long-run stability check for the N-body solar system.
#   godot --headless --path . -s tools/orbit_check.gd
#   HOURS=24 godot --headless --path . -s tools/orbit_check.gd
# Reports, per body, the min/max distance to the sun and, per pair, the closest
# surface-to-surface gap reached. A negative gap means a collision: move the
# body, change its radius, or space the orbits further apart.

const CelestialSystem := preload("res://scripts/celestial_system.gd")
const SolarSystemContentScript := preload("res://scripts/solar_system_content.gd")

const SUN_RADIUS := 345.0
const SUN_SURFACE_GRAVITY := 50.0
const STEP := 1.0 / 120.0
const SAMPLE_INTERVAL := 60


func _init() -> void:
	var hours := 6.0
	if not OS.get_environment("HOURS").is_empty():
		hours = float(OS.get_environment("HOURS"))

	var names: Array[String] = ["Sun"]
	var positions: Array[Vector3] = [Vector3.ZERO]
	var mu: Array[float] = [SUN_SURFACE_GRAVITY * SUN_RADIUS * SUN_RADIUS]
	var radii: Array[float] = [SUN_RADIUS]
	var twin_positions: Array[Vector3] = []
	var twin_mu: Array[float] = []
	var twin_radii: Array[float] = []

	for definition in SolarSystemContentScript.get_body_definitions():
		var radius: float = definition.data.radius
		var body_mu: float = float(definition.data.gravity) * radius * radius
		if String(definition.name) in CelestialSystem.TWIN_NAMES:
			twin_positions.append(definition.position)
			twin_mu.append(body_mu)
			twin_radii.append(radius)
			continue
		names.append(definition.name)
		positions.append(definition.position)
		mu.append(body_mu)
		radii.append(radius)

	if twin_positions.size() == 2:
		# The twins run as a rigid binary, so they enter as one barycentre whose
		# radius covers the whole pair.
		var total_mu: float = twin_mu[0] + twin_mu[1]
		var barycenter: Vector3 = (twin_positions[0] * twin_mu[0] + twin_positions[1] * twin_mu[1]) / total_mu
		names.append(CelestialSystem.TWIN_ENTRY)
		positions.append(barycenter)
		mu.append(total_mu)
		radii.append(maxf(
			barycenter.distance_to(twin_positions[0]) + twin_radii[0],
			barycenter.distance_to(twin_positions[1]) + twin_radii[1]
		))
		var separation: float = twin_positions[0].distance_to(twin_positions[1])
		var pair_gap: float = separation - twin_radii[0] - twin_radii[1]
		print("twin binary: separation %.1f, fixed surface gap %.1f" % [separation, pair_gap])
		if pair_gap <= 0.0:
			print("  ERROR: twins overlap at rest")

	var state := CelestialSystem.pack_state(positions)
	var velocities := CelestialSystem.pack_state(CelestialSystem.compute_initial_velocities(names, positions, mu))
	var pair_mu := CelestialSystem.build_pair_mu(names, mu)

	var start_distance: Array[float] = []
	var min_solar: Array[float] = []
	var max_solar: Array[float] = []
	for i in names.size():
		var distance: float = positions[i].distance_to(positions[0])
		start_distance.append(distance)
		min_solar.append(distance)
		max_solar.append(distance)

	var min_gap := {}
	var steps := int(hours * 3600.0 / STEP)
	for s in steps:
		CelestialSystem.step_simulation(state, velocities, pair_mu, STEP)
		if s % SAMPLE_INTERVAL != 0:
			continue
		var sun_position := CelestialSystem.read_state(state, 0)
		for i in names.size():
			var body_position := CelestialSystem.read_state(state, i)
			var solar: float = body_position.distance_to(sun_position)
			min_solar[i] = minf(min_solar[i], solar)
			max_solar[i] = maxf(max_solar[i], solar)
			for j in range(i + 1, names.size()):
				var key := "%s | %s" % [names[i], names[j]]
				var gap: float = body_position.distance_to(CelestialSystem.read_state(state, j)) - radii[i] - radii[j]
				min_gap[key] = minf(min_gap.get(key, INF), gap)

	print("--- %.1f h simulated, %d bodies ---" % [hours, names.size()])
	var unstable := false
	for i in names.size():
		var drift: float = 0.0
		if start_distance[i] > 0.0:
			drift = (max_solar[i] - min_solar[i]) / start_distance[i] * 100.0
		if drift > 40.0:
			unstable = true
		print("%-16s start=%9.1f min=%9.1f max=%9.1f swing=%5.1f%%" % [
			names[i], start_distance[i], min_solar[i], max_solar[i], drift
		])
	print("--- closest surface gaps ---")
	var keys := min_gap.keys()
	keys.sort_custom(func(a, b): return min_gap[a] < min_gap[b])
	for key in keys.slice(0, 8):
		var gap: float = min_gap[key]
		if gap < 0.0:
			unstable = true
		print("%-36s %10.1f%s" % [key, gap, "  COLLISION" if gap < 0.0 else ""])
	print("VERDICT: %s" % ("UNSTABLE" if unstable else "stable"))
	quit(1 if unstable else 0)
