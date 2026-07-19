extends Node

var look_delta := Vector2.ZERO


func is_touch_ui() -> bool:
	return (
		OS.has_feature("mobile")
		or OS.get_environment("FORCE_TOUCH_UI") == "1"
	)
