extends SceneTree

const CyclopsGeometryScript := preload("res://game/planets/cyclops/cyclops_geometry.gd")
const TestWorldScript := preload("res://tests/shared/test_world.gd")

const SAMPLE_COUNT := 200

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var reference := {}
	for configuration in _configurations():
		_test_configuration(configuration[0], configuration[1], configuration[2], reference)
	if failures.is_empty():
		print("Cyclops geometry tests passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


# radius / ocean_level / core_radius triples, all derived from whatever Cyclops is currently authored
# as: the authored size, double, half, and the ocean level moved on its own. Retuning the planet moves
# the whole set, so the geometry relations are what is under test, never the numbers.
func _configurations() -> Array:
	var config := TestWorldScript.authored_config(&"Cyclops")
	if config == null:
		_expect(false, "Cyclops is missing from the solar system definitions")
		return []
	return [
		[config.radius, config.ocean.level, config.core_radius],
		[config.radius * 2.0, config.ocean.level * 2.0, config.core_radius * 2.0],
		[config.radius * 0.5, config.ocean.level * 0.5, config.core_radius * 0.5],
		[config.radius, config.ocean.level * 0.25, config.core_radius],
		[config.radius, config.ocean.level * 3.0, config.core_radius],
	]


func _test_configuration(radius: float, ocean_level: float, core_radius: float, reference: Dictionary) -> void:
	var sea := radius + ocean_level
	var label := "radius %.2f / ocean_level %.2f" % [radius, ocean_level]
	var deck_gap := CyclopsGeometryScript.deck_gap(sea)
	var deck_center := CyclopsGeometryScript.deck_center(sea)
	var deck_thickness := CyclopsGeometryScript.deck_thickness(sea)
	var deck_inner := CyclopsGeometryScript.deck_inner_radius(sea)
	var deck_outer := CyclopsGeometryScript.deck_outer_radius(sea)

	_expect(is_equal_approx(deck_center, sea + deck_gap), "%s: deck centre is not the sea plus the deck gap" % label)
	_expect(is_equal_approx(deck_outer - deck_inner, deck_thickness), "%s: deck faces do not straddle the thickness" % label)
	_expect(deck_inner < deck_center and deck_center < deck_outer, "%s: deck faces are not ordered around the centre" % label)
	_expect(deck_inner > sea, "%s: the deck reaches down into the ocean" % label)
	_expect(deck_thickness < deck_gap, "%s: the deck is thicker than the room above the sea" % label)
	_expect(sea - core_radius > 0.0, "%s: the ocean has no depth over the core" % label)

	# The tint must be opaque exactly on the mesh and clear at both faces, so the exterior/interior
	# shading flip is never visible and nothing else is ever whited out.
	_expect(is_equal_approx(CyclopsGeometryScript.cloud_transition(sea, deck_center), 1.0), "%s: tint is not opaque on the deck mesh" % label)
	_expect(is_zero_approx(CyclopsGeometryScript.cloud_transition(sea, deck_inner)), "%s: tint lingers at the inner deck face" % label)
	_expect(is_zero_approx(CyclopsGeometryScript.cloud_transition(sea, deck_outer)), "%s: tint lingers at the outer deck face" % label)
	_expect(is_zero_approx(CyclopsGeometryScript.cloud_transition(sea, sea)), "%s: tint covers the sea surface" % label)
	_expect(is_zero_approx(CyclopsGeometryScript.cloud_transition(sea, deck_outer * 4.0)), "%s: tint covers deep space" % label)

	_expect(is_equal_approx(CyclopsGeometryScript.sky_occlusion(sea, sea), 1.0), "%s: stars are visible from under the deck" % label)
	_expect(is_zero_approx(CyclopsGeometryScript.sky_occlusion(sea, deck_outer)), "%s: stars stay occluded above the deck" % label)
	_expect(is_equal_approx(CyclopsGeometryScript.interior_visibility(sea, sea), 1.0), "%s: tornadoes are dimmed at sea level" % label)
	_expect(is_zero_approx(CyclopsGeometryScript.interior_visibility(sea, deck_center)), "%s: tornadoes stay lit on the deck mesh" % label)

	var full_visibility_radius := CyclopsGeometryScript.streaming_radius(sea, CyclopsGeometryScript.FULL_VISIBILITY_RATIO)
	var preload_radius := CyclopsGeometryScript.streaming_radius(sea, CyclopsGeometryScript.PRELOAD_RATIO)
	var fade_radius := CyclopsGeometryScript.streaming_radius(sea, CyclopsGeometryScript.FADE_RATIO)
	var unload_radius := CyclopsGeometryScript.streaming_radius(sea, CyclopsGeometryScript.UNLOAD_RATIO)
	_expect(deck_outer < full_visibility_radius, "%s: the full-visibility radius sits inside the deck" % label)
	_expect(full_visibility_radius < preload_radius, "%s: storms fade in before they are preloaded" % label)
	_expect(preload_radius <= fade_radius, "%s: storms fade out before they are preloaded" % label)
	_expect(fade_radius < unload_radius, "%s: storms unload before they have faded out" % label)

	# The sky/water invariant: the funnel foot is pinned to the sea, so its height alone decides
	# where the crown lands. It must reach into the deck and never pierce the mesh.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260730
	var minimum_height := INF
	var maximum_height := -INF
	for _index in SAMPLE_COUNT:
		var funnel_height := CyclopsGeometryScript.funnel_height(sea, rng.randf())
		_expect(sea + funnel_height < deck_center, "%s: funnel crown at %f pierces the deck mesh at %f" % [label, sea + funnel_height, deck_center])
		_expect(sea + funnel_height > deck_inner, "%s: funnel crown at %f falls short of the deck inner face at %f" % [label, sea + funnel_height, deck_inner])
		minimum_height = minf(minimum_height, funnel_height)
		maximum_height = maxf(maximum_height, funnel_height)

	# Ratio invariance: the same shape at every scale.
	var ratios := {
		"deck_center": deck_center / sea,
		"deck_thickness": deck_thickness / sea,
		"minimum_funnel_height": minimum_height / sea,
		"maximum_funnel_height": maximum_height / sea,
		"unload_radius": unload_radius / sea,
	}
	if reference.is_empty():
		reference.merge(ratios)
	else:
		for key in ratios:
			_expect(is_equal_approx(float(ratios[key]), float(reference[key])), "%s: %s ratio drifted to %f, expected %f" % [label, key, ratios[key], reference[key]])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
