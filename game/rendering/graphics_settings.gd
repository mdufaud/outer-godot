class_name GraphicsSettings
extends RefCounted

# Player-facing graphics options, saved to user:// and applied to the root viewport, the world
# environment and the sun. Defaults reproduce the project settings and the hand-tuned look.

const PATH := "user://graphics.cfg"
const SECTION := "graphics"
const RENDER_SCALES: Array[float] = [1.0, 0.77, 0.67, 0.59, 0.5]
const SHADOW_NAMES: Array[String] = ["High", "Low", "Off"]
const SHADOWS_HIGH := 0
const SHADOWS_LOW := 1
const SHADOWS_OFF := 2

var render_scale_index := 0
var shadows := SHADOWS_HIGH
var ambient_occlusion := true
var glow := true
var fxaa: bool = ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa") != Viewport.SCREEN_SPACE_AA_DISABLED
var vsync: bool = ProjectSettings.get_setting("display/window/vsync/vsync_mode") != DisplayServer.VSYNC_DISABLED
var show_fps := false


func load_saved() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	render_scale_index = clampi(file.get_value(SECTION, "render_scale_index", render_scale_index), 0, RENDER_SCALES.size() - 1)
	shadows = clampi(file.get_value(SECTION, "shadows", shadows), SHADOWS_HIGH, SHADOWS_OFF)
	ambient_occlusion = file.get_value(SECTION, "ambient_occlusion", ambient_occlusion)
	glow = file.get_value(SECTION, "glow", glow)
	fxaa = file.get_value(SECTION, "fxaa", fxaa)
	vsync = file.get_value(SECTION, "vsync", vsync)
	show_fps = file.get_value(SECTION, "show_fps", show_fps)


func save() -> void:
	var file := ConfigFile.new()
	file.set_value(SECTION, "render_scale_index", render_scale_index)
	file.set_value(SECTION, "shadows", shadows)
	file.set_value(SECTION, "ambient_occlusion", ambient_occlusion)
	file.set_value(SECTION, "glow", glow)
	file.set_value(SECTION, "fxaa", fxaa)
	file.set_value(SECTION, "vsync", vsync)
	file.set_value(SECTION, "show_fps", show_fps)
	file.save(PATH)


func render_scale() -> float:
	return RENDER_SCALES[render_scale_index]


func render_scale_label() -> String:
	return "Native" if render_scale_index == 0 else "%d%%" % roundi(render_scale() * 100.0)


func apply(viewport: Viewport, environment: Environment, sun_light: DirectionalLight3D) -> void:
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	viewport.scaling_3d_scale = render_scale()
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if environment != null:
		environment.ssao_enabled = ambient_occlusion
		environment.glow_enabled = glow
	if sun_light != null:
		sun_light.shadow_enabled = shadows != SHADOWS_OFF
		sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if shadows == SHADOWS_HIGH else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		var atlas: int = ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")
		RenderingServer.directional_shadow_atlas_set_size(atlas if shadows == SHADOWS_HIGH else atlas / 2, ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits"))
