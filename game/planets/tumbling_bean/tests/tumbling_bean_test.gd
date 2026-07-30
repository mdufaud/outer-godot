extends SceneTree

const ReportScript := preload("res://tests/shared/test_report.gd")
const ContractScript := preload("res://tests/shared/planet_contract.gd")
const VariantsScript := preload("res://tests/shared/config_variants.gd")
const TestWorldScript := preload("res://tests/shared/test_world.gd")

const BODY_ID := &"Tumbling Bean"

var report := ReportScript.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for variant in VariantsScript.build(BODY_ID):
		ContractScript.run(self, variant.config, report, "Tumbling Bean %s" % variant.label)
	_test_deformed_asteroid()
	report.finish("Tumbling Bean tests", self)


# The bean is the deformed body of the system: it must stay markedly lumpier than the earth-like
# planet, because both the collider placement and the orbit clearance rely on that.
func _test_deformed_asteroid() -> void:
	var config := TestWorldScript.authored_config(BODY_ID)
	report.expect(not config.ocean.enabled, "Tumbling Bean grew an ocean")
	report.expect(config.atmosphere.enabled, "Tumbling Bean lost its dust atmosphere")
	report.expect(_relief(config) > _relief(TestWorldScript.authored_config(&"Terra")), "Tumbling Bean is no longer lumpier than Terra")
	var body := TestWorldScript.spawn_body(self, config)
	report.expect(body.get_surface_radius_towards(Vector3.UP) > 0.0, "Tumbling Bean has no surface at its pole")
	body.queue_free()


# Peak-to-valley spread over the mean radius: a shape measure, free of the planet's size.
func _relief(config: PlanetConfig) -> float:
	var body := TestWorldScript.spawn_body(self, config)
	var lowest := INF
	var highest := -INF
	var total := 0.0
	var directions := TestWorldScript.sphere_directions()
	for direction in directions:
		var surface_radius := body.get_surface_radius_towards(direction)
		lowest = minf(lowest, surface_radius)
		highest = maxf(highest, surface_radius)
		total += surface_radius
	body.queue_free()
	return (highest - lowest) / (total / float(directions.size()))
