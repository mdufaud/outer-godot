extends SceneTree

const ReportScript := preload("res://tests/shared/test_report.gd")
const ContractScript := preload("res://tests/shared/planet_contract.gd")
const VariantsScript := preload("res://tests/shared/config_variants.gd")
const TestWorldScript := preload("res://tests/shared/test_world.gd")
const AsteroidRingScript := preload("res://game/planets/mirage/asteroid_ring.gd")
const PlanetGeneratorScript := preload("res://game/planets/shared/planet_generator.gd")

const BODY_ID := &"Mirage"

var report := ReportScript.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for variant in VariantsScript.build(BODY_ID):
		ContractScript.run(self, variant.config, report, "Mirage %s" % variant.label)
	_test_perturbed_shape()
	_test_ring()
	report.finish("Mirage tests", self)


# Mirage is the only body whose shape is perturbed on the GPU; the strength has to stay non-zero and
# the profile has to stay its own, otherwise it silently becomes a plain sphere.
func _test_perturbed_shape() -> void:
	var config := TestWorldScript.authored_config(BODY_ID)
	report.expect(config.perturb_strength > 0.0, "Mirage lost its shape perturbation")
	report.expect(not config.ocean.enabled, "Mirage grew an ocean")
	report.expect(config.atmosphere.enabled, "Mirage lost its haze")
	var mirage := PlanetGeneratorScript.new(config.shape_profile, config.rng_seed)
	var terra := TestWorldScript.authored_config(&"Terra")
	var earth := PlanetGeneratorScript.new(terra.shape_profile, terra.rng_seed)
	var direction := Vector3(0.44, -0.31, 0.84).normalized()
	report.expect(not is_equal_approx(mirage.sample_factor(direction), earth.sample_factor(direction)), "Mirage fell back to the Terra profile")


func _test_ring() -> void:
	var config := TestWorldScript.authored_config(BODY_ID)
	var body := TestWorldScript.spawn_body(self, config)
	var ring := AsteroidRingScript.new()
	ring.name = "MirageRing"
	body.add_child(ring)

	report.expect(AsteroidRingScript.INNER_RADIUS < AsteroidRingScript.OUTER_RADIUS, "The ring turned inside out")
	report.expect(AsteroidRingScript.DUST_FADE_NEAR < AsteroidRingScript.DUST_FADE_FAR, "The dust band fades in after it fades out")
	report.expect(AsteroidRingScript.DUST_FADE_FAR <= AsteroidRingScript.ROCK_VISIBILITY_DISTANCE, "The dust band finishes dissolving after the rocks are already gone")
	var peak := 0.0
	for direction in TestWorldScript.sphere_directions():
		peak = maxf(peak, body.get_surface_radius_towards(direction))
	report.expect(AsteroidRingScript.INNER_RADIUS > peak, "The ring passes through the planet (inner radius %f against a peak of %f)" % [AsteroidRingScript.INNER_RADIUS, peak])

	var bands: Array[Node3D] = []
	for child in ring.get_children():
		if child is Node3D and String(child.name).begins_with("Band"):
			bands.append(child)
	report.expect(bands.size() == AsteroidRingScript.BANDS, "The ring lost bands (%d of %d)" % [bands.size(), AsteroidRingScript.BANDS])

	# Per-instance placement lives in the rendering server, which the dummy headless renderer does not
	# store: the debris positions are checked in the GPU tier instead. Counts and shear are here.
	var speeds: Array[float] = []
	var rocks := 0
	for band in bands:
		speeds.append(float(band.get_meta("speed")))
		for child in band.get_children():
			var instance := child as MultiMeshInstance3D
			if instance == null:
				continue
			rocks += instance.multimesh.instance_count
			report.expect(instance.multimesh.mesh != null and instance.multimesh.mesh.get_surface_count() > 0, "A ring debris variant has no mesh")
	report.expect(rocks == AsteroidRingScript.BANDS * AsteroidRingScript.ROCK_VARIANTS * AsteroidRingScript.ROCKS_PER_BAND_VARIANT, "The ring debris count changed to %d" % rocks)
	# Kepler: the inner bands must lap the outer ones, that shear is the whole point of the bands.
	report.expect_decreasing(speeds, "The ring bands no longer shear against each other")
	body.queue_free()
