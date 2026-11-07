class_name GraphicsSettings
extends RefCounted

# Player-facing graphics options, saved to user:// and applied to the root viewport, the world
# environment and the sun. Defaults reproduce the project settings and the hand-tuned look.

const PATH := "user://graphics.cfg"
const SECTION := "graphics"
const OPTIONS: Array[StringName] = [&"preset", &"render_scale", &"anti_aliasing", &"shadows", &"ambient_occlusion", &"indirect_light", &"glow", &"planet_detail", &"vsync", &"fps_limit", &"show_fps"]
const RENDER_SCALE_AUTO := 0.0
const RENDER_SCALES: Array[float] = [RENDER_SCALE_AUTO, 0.5, 0.59, 0.67, 0.77, 1.0, 1.25, 1.5]
# Auto keeps the 3D pass near this many pixels, never above native: an integrated GPU fills a
# 3K laptop screen at about 17 fps on Cyclops.
const AUTO_PIXELS_INTEGRATED := 1920 * 1080
const AUTO_PIXELS_DISCRETE := 3840 * 2160
const AA_OFF := 0
const AA_FXAA := 1
const AA_MSAA_2X := 2
const AA_MSAA_4X := 3
const AA_NAMES: Array[String] = ["Off", "FXAA", "MSAA 2x", "MSAA 4x"]
const SHADOWS_OFF := 0
const SHADOWS_LOW := 1
const SHADOWS_HIGH := 2
const SHADOWS_ULTRA := 3
const SHADOW_NAMES: Array[String] = ["Off", "Low", "High", "Ultra"]
const AO_OFF := 0
const AO_ON := 1
const AO_HIGH := 2
const AO_NAMES: Array[String] = ["Off", "On", "High"]
const PLANET_PROFILES: Array[StringName] = [&"desktop_medium", &"desktop_high"]
const PLANET_DETAIL_NAMES: Array[String] = ["Medium", "High"]
const FPS_LIMITS: Array[int] = [0, 30, 60, 120, 144]
const PRESET_NAMES: Array[String] = ["Low", "Medium", "High", "Ultra"]
const PRESETS: Array[Dictionary] = [
	{"render_scale": 0.67, "anti_aliasing": AA_FXAA, "shadows": SHADOWS_OFF, "ambient_occlusion": AO_OFF, "indirect_light": false, "glow": false, "planet_detail": 0},
	{"render_scale": 0.77, "anti_aliasing": AA_FXAA, "shadows": SHADOWS_LOW, "ambient_occlusion": AO_ON, "indirect_light": false, "glow": true, "planet_detail": 1},
	{"render_scale": RENDER_SCALE_AUTO, "anti_aliasing": AA_FXAA, "shadows": SHADOWS_HIGH, "ambient_occlusion": AO_ON, "indirect_light": false, "glow": true, "planet_detail": 1},
	{"render_scale": 1.25, "anti_aliasing": AA_MSAA_2X, "shadows": SHADOWS_ULTRA, "ambient_occlusion": AO_HIGH, "indirect_light": true, "glow": true, "planet_detail": 1},
]

var render_scale := RENDER_SCALE_AUTO
var anti_aliasing: int = AA_FXAA if ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa") != Viewport.SCREEN_SPACE_AA_DISABLED else AA_OFF
var shadows := SHADOWS_HIGH
var ambient_occlusion := AO_ON
var indirect_light := false
var glow := true
var planet_detail := 1
var vsync: bool = ProjectSettings.get_setting("display/window/vsync/vsync_mode") != DisplayServer.VSYNC_DISABLED
var fps_limit := 0
var show_fps := false
# Planet meshes are built once at boot, so a detail change waits for the next launch.
var booted_planet_detail := -1
var _applied_scale := 1.0


func load_saved() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	render_scale = _nearest_scale(float(file.get_value(SECTION, "render_scale", render_scale)))
	anti_aliasing = clampi(int(file.get_value(SECTION, "anti_aliasing", anti_aliasing)), AA_OFF, AA_MSAA_4X)
	shadows = clampi(int(file.get_value(SECTION, "shadows", shadows)), SHADOWS_OFF, SHADOWS_ULTRA)
	ambient_occlusion = clampi(int(file.get_value(SECTION, "ambient_occlusion", ambient_occlusion)), AO_OFF, AO_HIGH)
	indirect_light = bool(file.get_value(SECTION, "indirect_light", indirect_light))
	glow = bool(file.get_value(SECTION, "glow", glow))
	planet_detail = clampi(int(file.get_value(SECTION, "planet_detail", planet_detail)), 0, PLANET_PROFILES.size() - 1)
	vsync = bool(file.get_value(SECTION, "vsync", vsync))
	fps_limit = int(file.get_value(SECTION, "fps_limit", fps_limit))
	if fps_limit not in FPS_LIMITS:
		fps_limit = 0
	show_fps = bool(file.get_value(SECTION, "show_fps", show_fps))


func save() -> void:
	var file := ConfigFile.new()
	file.set_value(SECTION, "render_scale", render_scale)
	file.set_value(SECTION, "anti_aliasing", anti_aliasing)
	file.set_value(SECTION, "shadows", shadows)
	file.set_value(SECTION, "ambient_occlusion", ambient_occlusion)
	file.set_value(SECTION, "indirect_light", indirect_light)
	file.set_value(SECTION, "glow", glow)
	file.set_value(SECTION, "planet_detail", planet_detail)
	file.set_value(SECTION, "vsync", vsync)
	file.set_value(SECTION, "fps_limit", fps_limit)
	file.set_value(SECTION, "show_fps", show_fps)
	file.save(PATH)


static func _nearest_scale(value: float) -> float:
	var best := 1.0
	for scale in RENDER_SCALES:
		if absf(scale - value) < absf(best - value):
			best = scale
	return best


static func auto_render_scale(size: Vector2i) -> float:
	var discrete := RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU
	var budget := AUTO_PIXELS_DISCRETE if discrete else AUTO_PIXELS_INTEGRATED
	return minf(_nearest_scale(sqrt(float(budget) / float(maxi(size.x * size.y, 1)))), 1.0)


static func _forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


func planet_profile() -> StringName:
	booted_planet_detail = planet_detail
	return PLANET_PROFILES[planet_detail]


func current_preset() -> int:
	for index in PRESETS.size():
		var preset := PRESETS[index]
		if is_equal_approx(render_scale, preset.render_scale) and anti_aliasing == preset.anti_aliasing and shadows == preset.shadows \
				and ambient_occlusion == preset.ambient_occlusion and indirect_light == preset.indirect_light \
				and glow == preset.glow and planet_detail == preset.planet_detail:
			return index
	return -1


func _apply_preset(index: int) -> void:
	var preset := PRESETS[index]
	render_scale = preset.render_scale
	anti_aliasing = preset.anti_aliasing
	shadows = preset.shadows
	glow = preset.glow
	if _forward_plus():
		ambient_occlusion = preset.ambient_occlusion
		indirect_light = preset.indirect_light
		planet_detail = preset.planet_detail


# Screen-space AO and bounce light only exist in Forward+; Mobile builds its planets on its own tier.
func is_supported(option: StringName) -> bool:
	if option in [&"ambient_occlusion", &"indirect_light", &"planet_detail"]:
		return _forward_plus()
	return true


func cycle(option: StringName) -> void:
	match option:
		&"preset":
			_apply_preset((current_preset() + 1) % PRESETS.size())
		&"render_scale":
			render_scale = RENDER_SCALES[(RENDER_SCALES.find(render_scale) + 1) % RENDER_SCALES.size()]
		&"anti_aliasing":
			anti_aliasing = (anti_aliasing + 1) % AA_NAMES.size()
		&"shadows":
			shadows = (shadows + 1) % SHADOW_NAMES.size()
		&"ambient_occlusion":
			ambient_occlusion = (ambient_occlusion + 1) % AO_NAMES.size()
		&"indirect_light":
			indirect_light = not indirect_light
		&"glow":
			glow = not glow
		&"planet_detail":
			planet_detail = (planet_detail + 1) % PLANET_PROFILES.size()
		&"vsync":
			vsync = not vsync
		&"fps_limit":
			fps_limit = FPS_LIMITS[(FPS_LIMITS.find(fps_limit) + 1) % FPS_LIMITS.size()]
		&"show_fps":
			show_fps = not show_fps


func option_text(option: StringName) -> String:
	match option:
		&"preset":
			var preset := current_preset()
			return "Preset: %s" % (PRESET_NAMES[preset] if preset >= 0 else "Custom")
		&"render_scale":
			if render_scale == RENDER_SCALE_AUTO:
				return "Scale: Auto (%d%%)" % roundi(_applied_scale * 100.0)
			return "Scale: %d%%" % roundi(render_scale * 100.0)
		&"anti_aliasing":
			return "AA: %s" % AA_NAMES[anti_aliasing]
		&"shadows":
			return "Shadows: %s" % SHADOW_NAMES[shadows]
		&"ambient_occlusion":
			return "AO: %s" % AO_NAMES[ambient_occlusion]
		&"indirect_light":
			return "Bounce light: %s" % _on_off(indirect_light)
		&"glow":
			return "Glow: %s" % _on_off(glow)
		&"planet_detail":
			var pending := booted_planet_detail >= 0 and planet_detail != booted_planet_detail
			return "Planets: %s%s" % [PLANET_DETAIL_NAMES[planet_detail], " (restart)" if pending else ""]
		&"vsync":
			return "VSync: %s" % _on_off(vsync)
		&"fps_limit":
			return "FPS cap: %s" % ("Off" if fps_limit == 0 else str(fps_limit))
		&"show_fps":
			return "FPS counter: %s" % _on_off(show_fps)
	return String(option)


static func _on_off(value: bool) -> String:
	return "On" if value else "Off"


func apply_render_scale(viewport: Viewport) -> void:
	_applied_scale = auto_render_scale(Vector2i(viewport.get_visible_rect().size)) if render_scale == RENDER_SCALE_AUTO else render_scale
	# FSR only upscales; above native the viewport supersamples and filters down.
	# Bilinear first: FSR with a scale still above 1 warns on every switch.
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = _applied_scale
	if _applied_scale < 1.0:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR


func apply(viewport: Viewport, environment: Environment, sun_light: DirectionalLight3D) -> void:
	apply_render_scale(viewport)
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if anti_aliasing == AA_FXAA else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.msaa_3d = Viewport.MSAA_4X if anti_aliasing == AA_MSAA_4X else (Viewport.MSAA_2X if anti_aliasing == AA_MSAA_2X else Viewport.MSAA_DISABLED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_limit
	if environment != null:
		environment.ssao_enabled = ambient_occlusion != AO_OFF
		environment.ssil_enabled = indirect_light
		environment.glow_enabled = glow
		var high_ao := ambient_occlusion == AO_HIGH
		RenderingServer.environment_set_ssao_quality(
			RenderingServer.ENV_SSAO_QUALITY_HIGH if high_ao else ProjectSettings.get_setting("rendering/environment/ssao/quality"),
			false if high_ao else ProjectSettings.get_setting("rendering/environment/ssao/half_size"),
			ProjectSettings.get_setting("rendering/environment/ssao/adaptive_target"),
			ProjectSettings.get_setting("rendering/environment/ssao/blur_passes"),
			ProjectSettings.get_setting("rendering/environment/ssao/fadeout_from"),
			ProjectSettings.get_setting("rendering/environment/ssao/fadeout_to"))
	if sun_light != null:
		sun_light.shadow_enabled = shadows != SHADOWS_OFF
		sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if shadows == SHADOWS_LOW else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		var atlas: int = ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")
		if shadows == SHADOWS_LOW:
			atlas = int(atlas * 0.5)
		elif shadows == SHADOWS_ULTRA:
			atlas *= 2
		RenderingServer.directional_shadow_atlas_set_size(atlas, ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits"))
		var filter: int = ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality")
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH if shadows == SHADOWS_ULTRA else filter)
