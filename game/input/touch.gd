class_name TouchService
extends Node

var look_delta := Vector2.ZERO


func is_touch_ui() -> bool:
	return (
		OS.has_feature("mobile")
		or OS.get_environment("FORCE_TOUCH_UI") == "1"
	)


# UI design units are authored for a 1280x720 desktop window. On touch devices the
# same pixel sizes are physically tiny, so scale them by screen density, capped so
# the controls never eat more than their share of a short viewport.
func ui_scale(viewport_size: Vector2) -> float:
	if not is_touch_ui():
		return 1.0
	var dpi := float(DisplayServer.screen_get_dpi())
	var density := 1.0 if dpi <= 0.0 else dpi / 160.0
	var short_side := minf(viewport_size.x, viewport_size.y)
	return clampf(minf(density, short_side / 560.0), 1.0, 3.0)
