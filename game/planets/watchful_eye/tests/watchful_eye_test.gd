extends SceneTree

const ReportScript := preload("res://tests/shared/test_report.gd")
const ContractScript := preload("res://tests/shared/planet_contract.gd")
const VariantsScript := preload("res://tests/shared/config_variants.gd")
const TestWorldScript := preload("res://tests/shared/test_world.gd")
const PlanetGeneratorScript := preload("res://game/planets/shared/planet_generator.gd")

const BODY_ID := &"Watchful Eye"

var report := ReportScript.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for variant in VariantsScript.build(BODY_ID):
		ContractScript.run(self, variant.config, report, "Watchful Eye %s" % variant.label)
		_test_eye(variant.config, "Watchful Eye %s" % variant.label)
	report.finish("Watchful Eye tests", self)


func _test_eye(config: PlanetConfig, label: String) -> void:
	report.expect(not config.ocean.enabled, "%s: the eye grew an ocean" % label)
	report.expect(not config.atmosphere.enabled, "%s: the eye grew an atmosphere" % label)
	var body := TestWorldScript.spawn_body(self, config)
	var eye_direction: Vector3 = PlanetBody.WATCHFUL_EYE_DIRECTION.normalized()
	var directions := TestWorldScript.sphere_directions()
	var total := 0.0
	var socket_floor := INF
	for direction in directions:
		var surface_radius := body.get_surface_radius_towards(direction)
		total += surface_radius
		# The socket is a wide crater centred on the eye, so the whole cap around it must be sunken.
		if direction.dot(eye_direction) > 0.9:
			socket_floor = minf(socket_floor, surface_radius)
	var mean := total / float(directions.size())
	var eye_radius := body.get_surface_radius_towards(eye_direction)

	report.expect(eye_radius < mean, "%s: the eye socket is no longer a pit (%f against a mean of %f)" % [label, eye_radius, mean])
	report.expect(socket_floor < mean, "%s: the cap around the eye is no longer sunken" % label)
	var generator := PlanetGeneratorScript.new(config.shape_profile, config.rng_seed)
	report.expect(generator.spike_height_span() > 0.0, "%s: the spike field is flat" % label)

	# The eye watches where it is going: aiming it along a travel direction must put the socket in
	# front of the body, with the same depth it has in its own local frame.
	var travel := Vector3(0.2, -0.4, 0.9).normalized()
	body.set_orbital_state(Vector3(1000.0, 0.0, 0.0), travel * 12.0)
	report.expect_close(body.get_surface_radius_towards(travel), eye_radius, config.radius * 0.001, "%s: the eye stopped facing its travel direction" % label)
	report.expect(body.get_surface_radius_towards(-travel) > body.get_surface_radius_towards(travel), "%s: the eye socket ended up behind the body" % label)
	body.queue_free()
