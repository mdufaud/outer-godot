extends SceneTree

# Ship maths and landing-site choice without a renderer: the site search runs on the analytic
# surface here, the GPU tier checks it against the real collider.

const ReportScript := preload("res://tests/shared/test_report.gd")
const TestWorldScript := preload("res://tests/shared/test_world.gd")
const SpawnControllerScript := preload("res://game/bootstrap/spawn_controller.gd")

var report := ReportScript.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_autopilot_speed()
	_test_closest_on_segment()
	_test_upright_basis()
	var spawn: SpawnController = SpawnControllerScript.new()
	_test_sites(spawn, &"Luna")
	_test_sites(spawn, &"Terra")
	spawn.free()
	report.finish("Ship tests", self)


func _test_autopilot_speed() -> void:
	report.expect(Ship.autopilot_speed(0.0) == 0.0 and Ship.autopilot_speed(-10.0) == 0.0, "The autopilot must hold still on and inside the arrival shell")
	var previous := 0.0
	for step in range(1, 400):
		var remaining := float(step) * 25.0
		var speed := Ship.autopilot_speed(remaining)
		report.expect(speed >= previous, "The autopilot sped up while getting closer at %f m" % remaining)
		report.expect(speed * speed <= 2.0 * Ship.AUTOPILOT_DECEL * remaining + 0.001, "The autopilot cannot stop on the shell from %f m" % remaining)
		previous = speed
	report.expect_close(Ship.autopilot_speed(1.0e7), Ship.AUTOPILOT_SPEED, 0.001, "Far away the autopilot must cruise at its top speed")


func _test_closest_on_segment() -> void:
	var from := Vector3(-10.0, 0.0, 0.0)
	var to := Vector3(10.0, 0.0, 0.0)
	report.expect(Ship.closest_on_segment(from, to, Vector3(3.0, 5.0, 0.0)).is_equal_approx(Vector3(3.0, 0.0, 0.0)), "The closest point must be the projection inside the segment")
	report.expect(Ship.closest_on_segment(from, to, Vector3(-30.0, 2.0, 0.0)).is_equal_approx(from), "The closest point must clamp to the start")
	report.expect(Ship.closest_on_segment(from, to, Vector3(30.0, 2.0, 0.0)).is_equal_approx(to), "The closest point must clamp to the end")


func _test_upright_basis() -> void:
	var ups: Array[Vector3] = [Vector3.UP, Vector3(0.3, -0.8, 0.5).normalized(), Vector3.RIGHT]
	for up in ups:
		var toward := Vector3(1.0, 2.0, -3.0)
		var basis := SpawnController.upright_basis(up, toward)
		report.expect(basis.is_equal_approx(basis.orthonormalized()) and basis.determinant() > 0.99, "The ship basis for %v is not a rotation" % up)
		report.expect(basis.y.is_equal_approx(up), "The ship does not stand along %v" % up)
		var flat := (toward - up * up.dot(toward)).normalized()
		report.expect((-basis.z).dot(flat) > 0.999, "The ship nose does not face the target on %v" % up)
		var degenerate := SpawnController.upright_basis(up, up * 5.0)
		report.expect(degenerate.y.is_equal_approx(up) and degenerate.determinant() > 0.99, "Facing straight up broke the ship basis on %v" % up)


func _test_sites(spawn: SpawnController, body_id: StringName) -> void:
	var body := TestWorldScript.spawn_body(self, TestWorldScript.authored_config(body_id))
	var directions := TestWorldScript.sphere_directions(24)
	var landed := 0
	for direction in directions:
		var face := body.global_position + direction * body.radius * 3.0
		var site := spawn.find_ship_site(body, direction, face)
		var up := (site.origin - body.global_position).normalized()
		var arc := direction.angle_to(up) * body.get_core_radius()
		var altitude := site.origin.distance_to(body.global_position) - body.get_surface_radius_towards(up)
		report.expect(arc >= SpawnController.SHIP_SITE_MIN_ARC * 0.99 or arc >= SpawnController.SHIP_SITE_MAX_ANGLE * body.get_core_radius() * 0.99, "%s: the ship landed %f m from the player" % [body_id, arc])
		report.expect(site.basis.y.dot(up) > 0.95, "%s: the ship site is tilted (up dot %f)" % [body_id, site.basis.y.dot(up)])
		report.expect((-site.basis.z).dot((face - site.origin).normalized()) > 0.0, "%s: the ship turns its back on the player" % body_id)
		report.expect(altitude > Ship.HULL_RADIUS - Ship.HULL_CENTER.y, "%s: the ship hull is buried (%f m)" % [body_id, altitude])
		if altitude > SpawnController.SHIP_HOVER_HEIGHT * 0.5:
			report.expect(site.origin.distance_to(body.global_position) > body.sea_level(), "%s: the fallback hover is under water" % body_id)
			continue
		landed += 1
		for foot in Ship.FEET:
			var foot_offset := site * foot - body.global_position
			report.expect(foot_offset.length() > body.get_surface_radius_towards(foot_offset) - 0.05, "%s: a ship foot starts inside the ground" % body_id)
			report.expect(not body.has_ocean or foot_offset.length() > body.sea_level(), "%s: a ship foot stands in the sea" % body_id)
	report.expect(landed >= directions.size() * 3 / 4, "%s: only %d of %d spawn directions found dry land for the ship" % [body_id, landed, directions.size()])
	body.queue_free()
