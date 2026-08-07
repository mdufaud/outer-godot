extends SceneTree

const LeviathanScript := preload("res://game/leviathan/leviathan.gd")
const SUN_RADIUS := 345.0
const CYCLOPS_DISTANCE := 11456.53
const TERRA_DISTANCE := 5633.62
const MIRAGE_DISTANCE := 1487.5

var failures: Array[String] = []

class SilentRoar:
	extends Node

	func roar() -> void:
		pass

	func set_dread(_value: float) -> void:
		pass

	func thunder(_intensity: float = 1.0) -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_presence()
	_test_distance()
	_test_maw()
	_test_throat_contact()
	_test_spawn_direction()
	_test_aim_holds_the_sun()
	_test_visual_contract()
	_test_blackout_keeps_leviathan_visible()
	if failures.is_empty():
		print("Leviathan tests passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_presence() -> void:
	_expect(is_equal_approx(LeviathanScript.presence_at(0.0), 0.0), "Must be invisible before it is summoned")
	_expect(LeviathanScript.presence_at(LeviathanScript.FADE_IN_DURATION * 0.5) > 0.0, "Must be fading in halfway through the fade")
	_expect(LeviathanScript.presence_at(LeviathanScript.FADE_IN_DURATION * 0.5) < 1.0, "Must not be fully solid halfway through the fade")
	_expect(is_equal_approx(LeviathanScript.presence_at(LeviathanScript.FADE_IN_DURATION), 1.0), "Must be solid once the fade ends")
	_expect(is_equal_approx(LeviathanScript.presence_at(600.0), 1.0), "Presence must not overshoot")


func _test_distance() -> void:
	_expect(is_equal_approx(LeviathanScript.distance_at(0.0), LeviathanScript.START_DISTANCE), "Must hold station while fading in")
	_expect(is_equal_approx(LeviathanScript.distance_at(LeviathanScript.FADE_IN_DURATION), LeviathanScript.START_DISTANCE), "Must not move before the fade completes")
	var previous := LeviathanScript.START_DISTANCE
	for step in range(1, 31):
		var distance := LeviathanScript.distance_at(LeviathanScript.FADE_IN_DURATION + float(step))
		_expect(distance < previous, "Approach must close in at second %d" % step)
		previous = distance
	# The maw front carries on past the sun, or the sun sits in the teeth with
	# the throat that eats it still a throat's depth short of it.
	var ending := LeviathanScript.distance_at(
		LeviathanScript.FADE_IN_DURATION + LeviathanScript.TRAVEL_DURATION)
	_expect(ending < -SUN_RADIUS, "The dive must carry the sun past the fangs, ended at %.0f" % ending)
	# Pivot z of a body the maw front has passed is how far the front is past it,
	# and the throat box is measured from its own centre a throat's depth back.
	_expect(LeviathanScript.in_throat(Vector3(0.0, 0.0, -ending - LeviathanScript.THROAT_DEPTH), SUN_RADIUS),
		"The sun must end up inside the throat, not in front of it")
	_expect(is_equal_approx(LeviathanScript.distance_at(600.0), ending), "The dive must stop once it is over")


func _test_maw() -> void:
	_expect(is_equal_approx(LeviathanScript.maw_open_at(0.0), 0.0), "The maw must stay shut during the fade")
	_expect(is_equal_approx(LeviathanScript.maw_open_at(LeviathanScript.FADE_IN_DURATION), 0.0), "The maw must stay shut until the approach starts")
	var devour_time := _time_at_distance(LeviathanScript.DEVOUR_START_DISTANCE)
	_expect(LeviathanScript.maw_open_at(devour_time) > 0.5, "The maw must be open before the first bite")
	_expect(is_equal_approx(LeviathanScript.maw_open_at(LeviathanScript.FADE_IN_DURATION + LeviathanScript.TRAVEL_DURATION), 1.0), "The maw must be wide open at the sun")
	# The jaw only ever opens. Shutting it again mid dive was the mouth chewing
	# on empty space with the whole system still out in front of it.
	var previous := LeviathanScript.maw_open_at(LeviathanScript.FADE_IN_DURATION)
	for step in range(1, 301):
		var open := LeviathanScript.maw_open_at(
			LeviathanScript.FADE_IN_DURATION + LeviathanScript.TRAVEL_DURATION * float(step) / 300.0)
		_expect(open >= previous - 0.0001, "The jaw must never shut again once it starts opening, saw %.3f after %.3f" % [open, previous])
		previous = open
	# Half the dive is crossed with the mouth still shut, or it opens while the
	# creature is still a silhouette at the back of the galaxy.
	_expect(LeviathanScript.maw_open_at(
		LeviathanScript.FADE_IN_DURATION + LeviathanScript.TRAVEL_DURATION * 0.2) < 0.05,
		"The maw must still be shut a fifth of the way in")


# Nothing dies at arm's length: the body has to be inside the throat box, and
# the throat is well behind the maw front.
func _test_throat_contact() -> void:
	var half := LeviathanScript.STORM_HALF_EXTENTS
	_expect(LeviathanScript.in_throat(Vector3.ZERO, 0.0), "The middle of the throat must swallow")
	_expect(not LeviathanScript.in_throat(Vector3(half.x * 1.2, 0.0, 0.0), 0.0),
		"A body off to the side of the head must survive")
	_expect(not LeviathanScript.in_throat(Vector3(0.0, 0.0, half.z * 1.2), 0.0),
		"A body the throat has not reached yet must survive")
	# A planet is eaten when its surface enters the fangs, not when its centre does.
	_expect(LeviathanScript.in_throat(Vector3(half.x + 100.0, 0.0, 0.0), 200.0),
		"A body whose surface is inside the throat must be eaten")
	_expect(not LeviathanScript.in_throat(Vector3(half.x + 300.0, 0.0, 0.0), 200.0),
		"A radius must not stretch the throat past its own size")


# The player has to be on the dive line: the creature rises behind them, so what
# they see is it coming down their own bearing at the sun past their shoulder.
func _test_spawn_direction() -> void:
	var sun := Vector3(120.0, -40.0, 60.0)
	var bearings: Array[Vector3] = [
		Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
		Vector3(0.6, 0.5, 0.62), Vector3(-0.3, -0.8, 0.52),
	]
	for bearing in bearings:
		for offset: float in [TERRA_DISTANCE, CYCLOPS_DISTANCE, MIRAGE_DISTANCE]:
			var player := sun + bearing.normalized() * offset
			var direction := LeviathanScript.spawn_direction(player, sun)
			_expect(is_equal_approx(direction.length(), 1.0), "The spawn heading must be a unit vector")
			var spawn := sun + direction * LeviathanScript.START_DISTANCE
			_expect(is_equal_approx((spawn - sun).length(), LeviathanScript.START_DISTANCE),
				"The spawn point must sit on the start sphere")
			# Player between the creature and the sun, and the dive line through them.
			_expect((spawn - player).normalized().dot((player - sun).normalized()) > 0.999,
				"The creature must rise directly behind the player")
			var miss := Geometry3D.get_closest_point_to_segment(player, spawn, sun).distance_to(player)
			_expect(miss < 1.0, "The dive must run through the player, missed by %.1f" % miss)
	# A player sitting on the sun has no bearing to spawn behind.
	_expect(is_equal_approx(LeviathanScript.spawn_direction(sun, sun).length(), 1.0),
		"A degenerate bearing must still give a unit heading")


# The head is pointed at the sun by the transform itself, not by an aim curve, so
# the only way to state the contract is to place the body and read where its maw
# ended up looking.
func _test_aim_holds_the_sun() -> void:
	var leviathan := LeviathanScript.new()
	root.add_child(leviathan)
	var sun := Vector3(120.0, -40.0, 60.0)
	var offsets: Array[Vector3] = [
		Vector3(0.0, 0.0, 42000.0), Vector3(-9000.0, 3000.0, 1200.0), Vector3(400.0, 0.0, 0.0)]
	for offset in offsets:
		var maw := sun + offset
		leviathan._place_body(maw, sun, Vector3.UP)
		# The model points -Z out of the maw.
		var aim := -leviathan.global_basis.z
		_expect(aim.dot((sun - maw).normalized()) > 0.999,
			"The maw must point at the sun from %s" % offset)
		_expect(leviathan.global_position.is_equal_approx(maw), "The body must sit where it was placed")
	leviathan.free()


# The creature is an imported sheet with baked maps, and every landmark the
# sequence hangs on it is a number measured off that mesh. Swapping the model
# without remeasuring is the failure this catches: it leaves the storm hanging
# outside the face and the lantern buried in the skull, both of which still run.
func _test_visual_contract() -> void:
	var leviathan := LeviathanScript.new()
	root.add_child(leviathan)
	var body := leviathan._body_mesh()
	_expect(body != null, "The imported anglerfish body must exist")
	if body != null:
		_expect(body.mesh.get_surface_count() == 1, "The anglerfish must import as a single surface")
		var arrays := body.mesh.surface_get_arrays(0)
		_expect((arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() > 0,
			"The anglerfish must carry the UVs its baked skin is painted in")
		_expect(arrays[Mesh.ARRAY_TANGENT] != null,
			"The anglerfish must carry tangents or its normal map is meaningless")
		for parameter in [&"skin_albedo", &"skin_normal", &"skin_glow"]:
			_expect(leviathan._body_material.get_shader_parameter(parameter) != null,
				"The skin shader must be handed the baked %s map" % parameter)

		var to_pivot := leviathan._body_pivot.global_transform.affine_inverse()
		var bounds: AABB = to_pivot * (body.global_transform * body.get_aabb())
		_expect(absf(bounds.size.z - LeviathanScript.BODY_LENGTH) < LeviathanScript.BODY_LENGTH * 0.02,
			"MODEL_LENGTH must match the mesh, saw %.0f against %.0f"
				% [bounds.size.z, LeviathanScript.BODY_LENGTH])
		# Pivot -Z leads the dive, so the lantern hangs out ahead of the maw and
		# the storm sits back inside the throat behind it.
		_expect(leviathan._lure_light.position.z < 0.0,
			"The lantern must hang in front of the maw, saw z=%.0f" % leviathan._lure_light.position.z)
		_expect(leviathan._lure_light.position.z > bounds.position.z,
			"The lantern must sit on its stalk rather than out beyond the model")
		var storm := AABB(
			leviathan._storm.position - LeviathanScript.STORM_HALF_EXTENTS,
			LeviathanScript.STORM_HALF_EXTENTS * 2.0)
		_expect(storm.position.z > 0.0,
			"The storm must stay behind the maw front, saw z=%.0f" % storm.position.z)
		_expect(bounds.encloses(storm), "The storm must raymarch inside the head, not around it")
	for overlay in leviathan.find_children("*", "ColorRect", true, false):
		var color_rect := overlay as ColorRect
		_expect(color_rect.color.r < 0.1 or color_rect.color.g >= color_rect.color.r, "The leviathan must not create a red full-screen flash")
	leviathan.free()


func _test_blackout_keeps_leviathan_visible() -> void:
	var leviathan := LeviathanScript.new()
	root.add_child(leviathan)
	var sun := Node3D.new()
	sun.add_to_group("sun")
	root.add_child(sun)
	var original_roar: Node = leviathan._roar
	leviathan._roar = SilentRoar.new()
	original_roar.free()
	leviathan._elapsed = LeviathanScript.FADE_IN_DURATION + LeviathanScript.TRAVEL_DURATION * 0.6
	leviathan._direction = Vector3.FORWARD
	var initial_distance := LeviathanScript.distance_at(leviathan._elapsed)
	var initial_position := sun.global_position + leviathan._direction * initial_distance
	leviathan._place_body(initial_position, initial_position - leviathan._direction * LeviathanScript.BODY_LENGTH, Vector3.UP)
	leviathan._visual.visible = true
	leviathan._storm.visible = true
	leviathan._start_blackout()
	leviathan._update_blackout(LeviathanScript.BLACKOUT_DURATION * 0.5)
	_expect(leviathan._visual.visible, "The leviathan must stay visible during the blackout")
	_expect(leviathan._storm.visible, "The maw storm must stay visible during the blackout")
	_expect(leviathan._elapsed > LeviathanScript.FADE_IN_DURATION + LeviathanScript.TRAVEL_DURATION * 0.6,
		"The leviathan must keep advancing during the blackout")
	_expect(not leviathan.global_position.is_equal_approx(initial_position),
		"The leviathan position must keep changing during the blackout")
	_expect(leviathan._blackout.color.a < 1.0, "The blackout must not be complete halfway through")
	sun.free()
	leviathan._roar.free()
	leviathan.free()


func _time_at_distance(distance: float) -> float:
	var elapsed := LeviathanScript.FADE_IN_DURATION
	while elapsed < LeviathanScript.FADE_IN_DURATION + LeviathanScript.TRAVEL_DURATION:
		if LeviathanScript.distance_at(elapsed) <= distance:
			return elapsed
		elapsed += 0.05
	return elapsed


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
