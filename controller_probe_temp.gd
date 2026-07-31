extends SceneTree

func _init() -> void:
	print("FEATURE steam_deck=%s" % OS.has_feature("steam_deck"))
	print("OVERRIDE viewport=%s x %s" % [ProjectSettings.get_setting_with_override("display/window/size/viewport_width"), ProjectSettings.get_setting_with_override("display/window/size/viewport_height")])
	print("OVERRIDE window=%s x %s" % [ProjectSettings.get_setting_with_override("display/window/size/window_width_override"), ProjectSettings.get_setting_with_override("display/window/size/window_height_override")])
	print("RUNTIME window=%s" % get_root().size)
	quit()
