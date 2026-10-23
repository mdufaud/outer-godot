extends SceneTree

# CPU cost and output hash of the planet height sampler, per body and backend.
#   godot-4.7 --headless --path . -s tools/perf_bench.gd
# The N-body integrator is timed by tools/orbit_check.gd.

const SolarSystemManifestScript := preload("res://game/celestial/solar_system_manifest.gd")
const PlanetGeneratorScript := preload("res://game/planets/shared/planet_generator.gd")

const SAMPLES := 2000


func _init() -> void:
	var directions := PackedVector3Array()
	for index in SAMPLES:
		var y := 1.0 - (float(index) + 0.5) / float(SAMPLES) * 2.0
		var radial := sqrt(1.0 - y * y)
		var angle := float(index) * PI * (3.0 - sqrt(5.0))
		directions.append(Vector3(cos(angle) * radial, y, sin(angle) * radial))

	var rows := {}
	for entry in SolarSystemManifestScript.get_entries():
		var body: PlanetBody = entry.scene.instantiate()
		var config: PlanetConfig = body.create_planet_config()
		rows[String(entry.body_id)] = [config.shape_profile, config.rng_seed]
		body.free()
	rows["glacier"] = [PlanetShapeProfile.GLACIER, 0]

	var native_enabled := Native.enabled
	var mismatch := false
	print("%-14s %-8s %12s %12s  %s" % ["body", "backend", "factor us", "shading us", "hash"])
	for label in rows:
		var hashes: Array[String] = []
		for backend in ["gdscript", "native"]:
			Native.enabled = backend == "native"
			if Native.enabled and not ClassDB.class_exists(&"PlanetSampler"):
				continue
			var generator = PlanetGeneratorScript.new(rows[label][0], rows[label][1])
			var values := PackedFloat64Array()
			var start := Time.get_ticks_usec()
			for direction in directions:
				values.append(generator.sample_factor(direction))
			var factor_us := float(Time.get_ticks_usec() - start) / float(SAMPLES)
			start = Time.get_ticks_usec()
			for direction in directions:
				var shading: Vector4 = generator.sample_shading_data(direction)
				values.append_array([shading.x, shading.y, shading.z, shading.w])
			var shading_us := float(Time.get_ticks_usec() - start) / float(SAMPLES)
			hashes.append(values.to_byte_array().hex_encode().sha256_text().left(16))
			print("%-14s %-8s %12.2f %12.2f  %s" % [label, backend, factor_us, shading_us, hashes[-1]])
		if hashes.size() == 2 and hashes[0] != hashes[1]:
			mismatch = true
			print("  MISMATCH: native differs from gdscript")
	Native.enabled = native_enabled
	quit(1 if mismatch else 0)
