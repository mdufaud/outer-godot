extends SceneTree

const LeviathanScript := preload("res://game/leviathan/leviathan.gd")
const SUN_RADIUS := 345.0
const CYCLOPS_DISTANCE := 11456.53
const TERRA_DISTANCE := 5633.62
const MIRAGE_DISTANCE := 1487.5

var failures: Array[String] = []

class SilentRoar:
	extends LeviathanRoar

	func roar() -> void:
		pass

	func set_dread(_value: float) -> void:
		pass

	func thunder(_intensity: float = 1.0) -> void:
		pass


# A sun that only holds a position: the real one builds meshes and joins the Gravity autoload.
class InertSun:
	extends Sun

	func _ready() -> void:
		add_to_group("sun")

	func _exit_tree() -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_presence()
	_test_distance()
	_test_fast_then_slow()
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


# Ten seconds of the lantern alone, ten more with the red eyes beside it, then
# the body fades in.
func _test_presence() -> void:
	_expect(is_equal_approx(LeviathanScript.lure_glow_at(0.0), 0.0), "The lantern must light up after the summon, not before")
	_expect(is_equal_approx(LeviathanScript.lure_glow_at(5.0), 1.0), "The lantern must show first")
	_expect(is_equal_approx(LeviathanScript.eye_glow_at(9.9), 0.0), "The eyes must stay dark while the lantern is alone")
	_expect(is_equal_approx(LeviathanScript.presence_at(9.9), 0.0), "The body must stay hidden while the lantern is alone")
	_expect(is_equal_approx(LeviathanScript.eye_glow_at(15.0), 1.0), "The eyes must open after ten seconds")
	_expect(is_equal_approx(LeviathanScript.lure_glow_at(15.0), 1.0), "The lantern must stay lit beside the eyes")
	_expect(is_equal_approx(LeviathanScript.presence_at(19.9), 0.0), "The body must stay hidden while only the eyes and lantern show")
	_expect(LeviathanScript.presence_at(24.5) > 0.0, "Must be fading in halfway through the fade")
	_expect(LeviathanScript.presence_at(24.5) < 1.0, "Must not be fully solid halfway through the fade")
	_expect(is_equal_approx(LeviathanScript.presence_at(29.0), 1.0), "Must be solid once the fade ends")
	_expect(is_equal_approx(LeviathanScript.presence_at(600.0), 1.0), "Presence must not overshoot")


func _test_distance() -> void:
	for feed: float in [MIRAGE_DISTANCE, TERRA_DISTANCE, CYCLOPS_DISTANCE]:
		_expect(is_equal_approx(LeviathanScript.distance_at(0.0, feed), LeviathanScript.START_DISTANCE), "Must hold station while fading in")
		_expect(is_equal_approx(LeviathanScript.distance_at(LeviathanScript.HOLD_DURATION, feed), LeviathanScript.START_DISTANCE), "Must not move before the fade completes")
		var end_time := LeviathanScript.HOLD_DURATION + LeviathanScript.dive_duration(feed)
		var previous := LeviathanScript.START_DISTANCE
		var second := LeviathanScript.HOLD_DURATION + 1.0
		while second < end_time:
			var distance := LeviathanScript.distance_at(second, feed)
			_expect(distance < previous, "Approach must close in at %.0f s for a player %.0f from the sun" % [second, feed])
			previous = distance
			second += 1.0
		# The maw front carries on past the sun, or the sun sits in the teeth with
		# the throat that eats it still a throat's depth short of it.
		var ending := LeviathanScript.distance_at(end_time, feed)
		_expect(ending < -SUN_RADIUS, "The dive must carry the sun past the fangs, ended at %.0f" % ending)
		# Pivot z of a body the maw front has passed is how far the front is past it,
		# and the throat box is measured from its own centre a throat's depth back.
		_expect(LeviathanScript.in_throat(Vector3(0.0, 0.0, -ending - LeviathanScript.THROAT_DEPTH), SUN_RADIUS),
			"The sun must end up inside the throat, not in front of it")
		_expect(is_equal_approx(LeviathanScript.distance_at(end_time + 600.0, feed), ending), "The dive must stop once it is over")


# It comes from the back of the universe fast, then slows down well before the
# player so they watch the maw close on them.
func _test_fast_then_slow() -> void:
	for feed: float in [MIRAGE_DISTANCE, TERRA_DISTANCE, CYCLOPS_DISTANCE]:
		var rush_start := LeviathanScript.HOLD_DURATION
		var early_speed := (LeviathanScript.distance_at(rush_start, feed) - LeviathanScript.distance_at(rush_start + 3.0, feed)) / 3.0
		_expect(early_speed > LeviathanScript.FEED_SPEED * 5.0, "The rush must be fast far out, %.0f m/s for a player %.0f out" % [early_speed, feed])
		var step := 0.05
		var elapsed := rush_start
		var slow_since := -1.0
		while elapsed < rush_start + LeviathanScript.dive_duration(feed):
			var distance := LeviathanScript.distance_at(elapsed, feed)
			var speed := (LeviathanScript.distance_at(elapsed - step, feed) - distance) / step
			if slow_since < 0.0 and speed <= LeviathanScript.FEED_SPEED * 1.01:
				slow_since = elapsed
			# The player sits on the dive line `feed` from the sun.
			if LeviathanScript.in_throat(Vector3(0.0, 0.0, -(distance - feed) - LeviathanScript.THROAT_DEPTH), 0.0):
				_expect(speed <= LeviathanScript.FEED_SPEED * 1.01, "The maw must be slow when it takes the player, %.0f m/s" % speed)
				_expect(slow_since >= 0.0 and elapsed - slow_since >= 10.0,
					"The player must watch the slow approach for at least 10 s, got %.1f s" % (elapsed - slow_since))
				break
			elapsed += step


func _test_maw() -> void:
	_expect(is_equal_approx(LeviathanScript.maw_open_at(LeviathanScript.START_DISTANCE), 0.0), "The maw must stay shut during the fade")
	_expect(LeviathanScript.maw_open_at(LeviathanScript.DEVOUR_START_DISTANCE) > 0.5, "The maw must be open before the first bite")
	_expect(is_equal_approx(LeviathanScript.maw_open_at(LeviathanScript.END_DISTANCE), 1.0), "The maw must be wide open at the sun")
	# The jaw only ever opens. Shutting it again mid dive was the mouth chewing
	# on empty space with the whole system still out in front of it.
	var previous := LeviathanScript.maw_open_at(LeviathanScript.START_DISTANCE)
	for step in range(1, 301):
		var distance := lerpf(LeviathanScript.START_DISTANCE, LeviathanScript.END_DISTANCE, float(step) / 300.0)
		var open := LeviathanScript.maw_open_at(distance)
		_expect(open >= previous - 0.0001, "The jaw must never shut again once it starts opening, saw %.3f after %.3f" % [open, previous])
		previous = open
	# The empty back of the galaxy is crossed with the mouth still shut, or it opens
	# while the creature is still a silhouette.
	_expect(LeviathanScript.maw_open_at(LeviathanScript.START_DISTANCE * 0.65) < 0.05,
		"The maw must still be shut a third of the way in")
	# Whoever is eaten first, the gape must already be wide.
	_expect(LeviathanScript.maw_open_at(CYCLOPS_DISTANCE - LeviathanScript.THROAT_DEPTH + LeviathanScript.STORM_HALF_EXTENTS.z) > 0.99,
		"The maw must be wide open before it reaches a player at Cyclops")


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
		var eyes := 0
		var bulb := 0
		if arrays[Mesh.ARRAY_COLOR] != null:
			for mask in arrays[Mesh.ARRAY_COLOR] as PackedColorArray:
				eyes += int(mask.r > 0.5)
				bulb += int(mask.g > 0.5)
		_expect(eyes > 0 and bulb > 0,
			"The bake must mask the eyes and the lantern bulb for the staged arrival, saw %d and %d" % [eyes, bulb])
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
	var sun := InertSun.new()
	root.add_child(sun)
	var original_roar: Node = leviathan._roar
	leviathan._roar = SilentRoar.new()
	original_roar.free()
	leviathan._feed_distance = TERRA_DISTANCE
	leviathan._elapsed = LeviathanScript.HOLD_DURATION + LeviathanScript.dive_duration(TERRA_DISTANCE) * 0.6
	leviathan._direction = Vector3.FORWARD
	var initial_distance := LeviathanScript.distance_at(leviathan._elapsed, TERRA_DISTANCE)
	var initial_position := sun.global_position + leviathan._direction * initial_distance
	leviathan._place_body(initial_position, initial_position - leviathan._direction * LeviathanScript.BODY_LENGTH, Vector3.UP)
	leviathan._visual.visible = true
	leviathan._storm.visible = true
	leviathan._start_blackout()
	leviathan._update_blackout(LeviathanScript.BLACKOUT_DURATION * 0.5)
	_expect(leviathan._visual.visible, "The leviathan must stay visible during the blackout")
	_expect(leviathan._storm.visible, "The maw storm must stay visible during the blackout")
	_expect(leviathan._elapsed > LeviathanScript.HOLD_DURATION + LeviathanScript.dive_duration(TERRA_DISTANCE) * 0.6,
		"The leviathan must keep advancing during the blackout")
	_expect(not leviathan.global_position.is_equal_approx(initial_position),
		"The leviathan position must keep changing during the blackout")
	_expect(leviathan._blackout.color.a < 1.0, "The blackout must not be complete halfway through")
	sun.free()
	leviathan._roar.free()
	leviathan.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
