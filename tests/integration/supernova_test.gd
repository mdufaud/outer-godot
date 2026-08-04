extends SceneTree

const SupernovaScript := preload("res://game/sun/supernova.gd")
const SUN_RADIUS := 345.0
const CYCLOPS_DISTANCE := 11456.53

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_wave_radius()
	_test_contact()
	if failures.is_empty():
		print("Supernova tests passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_wave_radius() -> void:
	_expect(is_equal_approx(SupernovaScript.wave_radius_at(0.0, SUN_RADIUS), SUN_RADIUS), "Wave must not move before ignition")
	_expect(is_equal_approx(SupernovaScript.wave_radius_at(1.5, SUN_RADIUS), SUN_RADIUS), "Wave must stay put through the collapse")
	_expect(is_equal_approx(SupernovaScript.wave_radius_at(11.6, SUN_RADIUS), 5945.0), "Wave speed changed")
	_expect(SupernovaScript.wave_radius_at(20.0, SUN_RADIUS) < CYCLOPS_DISTANCE, "Wave reaches Cyclops too early")
	_expect(SupernovaScript.wave_radius_at(24.0, SUN_RADIUS) > CYCLOPS_DISTANCE, "Wave never reaches Cyclops")
	_expect(is_equal_approx(SupernovaScript.wave_radius_at(600.0, SUN_RADIUS), 13000.0), "Wave must stop growing at the system edge")


func _test_contact() -> void:
	var observer := Vector3(100.0, 0.0, 0.0)
	_expect(not SupernovaScript.has_contact(observer, Vector3.ZERO, 99.0), "Front short of the observer must not kill")
	_expect(SupernovaScript.has_contact(observer, Vector3.ZERO, 101.0), "Front past the observer must kill")
	_expect(SupernovaScript.has_contact(observer, Vector3(60.0, 0.0, 0.0), 41.0), "Contact must be measured from the sun, not the origin")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
