extends SceneTree

# The Cyclops storms, stated as behaviour: every tornado stands from the water up into the cloud
# deck, they never overlap each other or the landing rocks, and the funnel that swallows the player
# lifts them along its axis and lets go under the crown. Nothing here depends on the authored radius
# or ocean level: the same run is repeated at other sizes.

const ReportScript := preload("res://tests/shared/test_report.gd")
const VariantsScript := preload("res://tests/shared/config_variants.gd")
const TestWorldScript := preload("res://tests/shared/test_world.gd")
const GeometryScript := preload("res://game/planets/cyclops/cyclops_geometry.gd")
const StormsScript := preload("res://game/planets/cyclops/cyclops_storms.gd")
const RocksScript := preload("res://game/planets/cyclops/cyclops_rocks.gd")

const BODY_ID := &"Cyclops"
const MOTION_STEPS := 600
const MOTION_DELTA := 1.0 / 60.0

var report := ReportScript.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for variant in VariantsScript.build(BODY_ID):
		var label := "Cyclops storms %s" % variant.label
		var body := TestWorldScript.spawn_body(self, variant.config)
		var rocks := RocksScript.new()
		rocks.setup(body)
		body.attach_rock_feature(rocks)
		var storms := StormsScript.new()
		storms.setup(body)
		body.attach_weather_feature(storms)
		var states: Array[Dictionary] = storms._storm_states

		_test_roster(body, states, report, label)
		_test_water_to_sky(body, states, label)
		_test_separation(body, storms, states, label, "at rest")
		for _step in MOTION_STEPS:
			storms._update_storm_motion(MOTION_DELTA)
		_test_separation(body, storms, states, label, "after drifting")
		_test_water_to_sky(body, states, "%s after drifting" % label)
		_test_force_field(body, storms, states, label)
		body.queue_free()
	_test_force_scales_with_gravity()
	report.finish("Cyclops storms tests", self)


func _test_roster(body: PlanetBody, states: Array[Dictionary], report_value: RefCounted, label: String) -> void:
	report_value.expect(states.size() == StormsScript.TORNADO_COUNT + 2, "%s: storm count changed to %d" % [label, states.size()])
	var polar: Array[Dictionary] = []
	var drifting: Array[Dictionary] = []
	for state in states:
		if bool(state.static):
			polar.append(state)
		else:
			drifting.append(state)
	report_value.expect(polar.size() == 2, "%s: the two polar tornadoes are gone" % label)
	report_value.expect(drifting.size() == StormsScript.TORNADO_COUNT, "%s: the drifting tornado count changed" % label)
	var polar_axes := 0
	for state in polar:
		if absf(absf((state.direction as Vector3).y) - 1.0) < 0.001:
			polar_axes += 1
		report_value.expect(is_zero_approx(float(state.bend_scale)), "%s: a polar tornado started bending" % label)
	report_value.expect(polar_axes == 2, "%s: the polar tornadoes left the poles" % label)
	var widest_drifting := 0.0
	for state in drifting:
		widest_drifting = maxf(widest_drifting, float(state.crown_radius))
	report_value.expect(float(polar[0].crown_radius) > widest_drifting, "%s: the polar tornadoes are no longer the wide ones" % label)
	report_value.expect(body.get_weather_deck_gap() > 0.0, "%s: there is no room between the sea and the deck" % label)


# The invariant that makes a Cyclops tornado read as a tornado: it stands on the water and its crown
# disappears into the cloud deck, at every planet size.
func _test_water_to_sky(body: PlanetBody, states: Array[Dictionary], label: String) -> void:
	var sea := body.sea_level()
	var deck_gap := body.get_weather_deck_gap()
	var deck_inner := body.get_weather_deck_inner_radius()
	var deck_center := body.get_weather_deck_center()
	for state in states:
		var height := float(state.funnel_height)
		var crown := sea + height
		if crown <= deck_inner:
			report.expect(false, "%s: a funnel crown at %f falls short of the deck at %f" % [label, crown, deck_inner])
			return
		if crown >= deck_center:
			report.expect(false, "%s: a funnel crown at %f pierces the deck mesh at %f" % [label, crown, deck_center])
			return
		if height < deck_gap * GeometryScript.FUNNEL_HEIGHT_RANGE.x:
			report.expect(false, "%s: a funnel only spans %f of the %f gap between water and sky" % [label, height, deck_gap])
			return
		var contact_radius := float(state.contact_radius)
		if contact_radius <= 0.0 or contact_radius >= float(state.crown_radius):
			report.expect(false, "%s: a funnel foot of %f is not narrower than its crown of %f" % [label, contact_radius, state.crown_radius])
			return


func _test_separation(body: PlanetBody, storms: Node, states: Array[Dictionary], label: String, stage: String) -> void:
	for first_index in states.size():
		for second_index in range(first_index + 1, states.size()):
			var first: Dictionary = states[first_index]
			var second: Dictionary = states[second_index]
			var required: float = storms._storm_minimum_angle(float(first.crown_radius), float(second.crown_radius))
			var angle: float = (first.direction as Vector3).angle_to(second.direction as Vector3)
			if angle < required - 0.0001:
				report.expect(false, "%s %s: two tornadoes overlap, %f apart with %f required" % [label, stage, angle, required])
				return
	var rock_directions := body.get_landing_rock_directions()
	var rock_radii := body.get_landing_rock_radii()
	for state in states:
		for rock_index in rock_directions.size():
			var required: float = storms._storm_rock_minimum_angle(float(state.contact_radius), rock_radii[rock_index])
			var angle: float = (state.direction as Vector3).angle_to(rock_directions[rock_index])
			if angle < required - 0.0001:
				report.expect(false, "%s %s: a tornado stands on a landing rock, %f apart with %f required" % [label, stage, angle, required])
				return


# A tornado swallows the player instead of walling them out: inside the funnel it sucks them towards
# the axis, spins them around it and lifts them, then drops the lift under the crown.
func _test_force_field(body: PlanetBody, storms: Node, states: Array[Dictionary], label: String) -> void:
	var sea := body.sea_level()
	var deck_gap := body.get_weather_deck_gap()
	for state in states:
		var axis: Vector3 = (state.direction as Vector3).normalized()
		var height := float(state.funnel_height)
		var tangent := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()

		report.expect(is_zero_approx(storms.get_environment_force(body.global_position + axis * (sea - deck_gap)).length()), "%s: a tornado still pulls deep under water" % label)
		report.expect(is_zero_approx(storms.get_environment_force(body.global_position + axis * (sea + height * 1.05)).length()), "%s: a tornado still pulls above its crown" % label)
		var catch_radius: float = lerpf(float(state.contact_radius), float(state.crown_radius), 0.5) * StormsScript.STORM_CATCH_MARGIN
		var outside := body.global_position + axis * (sea + height * 0.5) + tangent * catch_radius * 1.2
		report.expect(is_zero_approx(storms.get_environment_force(outside).length()), "%s: a tornado grabs from outside its catch radius" % label)

		var on_axis := body.global_position + axis * (sea + height * 0.5)
		var centre_force: Vector3 = storms.get_environment_force(on_axis)
		report.expect(centre_force.dot(axis) > 0.0, "%s: the funnel no longer lifts along its axis" % label)
		report.expect(centre_force.cross(axis).length() < centre_force.length() * 0.01, "%s: the middle of the funnel is not a clean updraft" % label)

		var wall := on_axis + tangent * catch_radius * 0.5
		var wall_force: Vector3 = storms.get_environment_force(wall)
		var inward := -tangent
		report.expect(wall_force.dot(inward) > 0.0, "%s: the funnel wall stopped sucking towards the axis" % label)
		report.expect(absf(wall_force.dot(axis.cross(inward).normalized())) > 0.0, "%s: the funnel wall stopped spinning" % label)

		var release: Vector3 = storms.get_environment_force(body.global_position + axis * (sea + height * 0.995))
		report.expect(release.dot(axis) < centre_force.dot(axis), "%s: the lift is not released under the crown" % label)


# Doubling the surface gravity must double the ride: the storm forces are written as multiples of it,
# so a heavier Cyclops still throws the player the same way.
func _test_force_scales_with_gravity() -> void:
	var base := _sampled_force(1.0)
	var heavy := _sampled_force(2.0)
	report.expect(base.length() > 0.0, "The storm force field went silent")
	report.expect_close(heavy.length(), base.length() * 2.0, base.length() * 0.001, "Storm force no longer scales with surface gravity")


func _sampled_force(gravity_scale: float) -> Vector3:
	var config := TestWorldScript.authored_config(BODY_ID)
	config.surface_gravity *= gravity_scale
	var body := TestWorldScript.spawn_body(self, config)
	var rocks := RocksScript.new()
	rocks.setup(body)
	body.attach_rock_feature(rocks)
	var storms := StormsScript.new()
	storms.setup(body)
	body.attach_weather_feature(storms)
	var state: Dictionary = storms._storm_states[0]
	var axis: Vector3 = (state.direction as Vector3).normalized()
	var force: Vector3 = storms.get_environment_force(body.global_position + axis * (body.sea_level() + float(state.funnel_height) * 0.4))
	body.queue_free()
	return force
