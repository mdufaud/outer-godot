extends SceneTree

# Frame-cost probe: boots main.tscn, flies the ship to Cyclops on autopilot, then measures
# fixed views with each costly feature switched off in turn. Needs a real GPU:
#   tools/probe_launch.sh perf_probe
#   PROBE_SCREEN=2880x1920 tools/probe_launch.sh perf_probe

const BOOT_TIMEOUT_FRAMES := 20000
const WARMUP_FRAMES := 30
const SAMPLE_FRAMES := 180
const TRIP_SEGMENT_FRAMES := 120
const TRIP_MAX_SEGMENTS := 30
const VARIANTS: Array[StringName] = [&"base", &"full_scale",&"no_ocean", &"no_atmosphere", &"no_effects", &"no_shadows", &"no_ssao", &"no_glow", &"half_scale", &"no_sky", &"no_storms", &"no_cloud_shell", &"no_rain", &"no_hud", &"no_terrain", &"no_fxaa", &"bare"]
const COMPUTE_SHADERS: Array[String] = [
	"res://game/planets/shared/shaders/planet_height.comp",
	"res://game/planets/shared/shaders/planet_perturb.comp",
	"res://game/planets/shared/shaders/planet_shading.comp",
	"res://game/planets/shared/shaders/atmosphere_lut.comp",
]

var main: Main
var effects: PlanetEffects
var environment: Environment
var _viewport_rid: RID
var _effects_ms := 0.0
var _camera: Camera3D
var _storms: CyclopsStorms
var _process_begin := 0
var _physics_begin := 0
var _physics_pending := false
var _frame_process_usec := 0
var _frame_physics_usec := 0


# Brackets every node callback: the first clock runs before all others, the last after.
class FrameClock extends Node:
	var probe
	var last := false

	func _init(next_probe, is_last: bool) -> void:
		probe = next_probe
		last = is_last
		process_priority = 1000000 if is_last else -1000000
		process_physics_priority = process_priority

	func _process(_delta: float) -> void:
		probe.stamp_process(last)

	func _physics_process(_delta: float) -> void:
		probe.stamp_physics(last)


func _initialize() -> void:
	if RenderingServer.get_rendering_device() == null:
		print("[probe] no RenderingDevice, nothing measured")
		print("[probe] done")
		quit(1)
		return
	_run()


func _run() -> void:
	await process_frame
	root.mode = Window.MODE_FULLSCREEN
	_measure_shader_compiles()
	var boot_start := Time.get_ticks_msec()
	change_scene_to_file("res://game/bootstrap/main.tscn")
	await process_frame
	await process_frame
	main = current_scene as Main
	for _frame in BOOT_TIMEOUT_FRAMES:
		if main.is_loaded():
			break
		await process_frame
	if not main.is_loaded():
		print("[probe] boot timeout")
		print("[probe] done")
		quit(1)
		return
	print("[probe] boot %d ms, window %s, %s, %s" % [
		Time.get_ticks_msec() - boot_start, root.size, main.graphics.option_text(&"render_scale"), main.graphics.option_text(&"preset")])
	_viewport_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	var world_environment := _find_world_environment(main)
	environment = world_environment.environment
	effects = world_environment.compositor.compositor_effects[0] as PlanetEffects
	root.add_child(FrameClock.new(self, false))
	root.add_child(FrameClock.new(self, true))
	_camera = Camera3D.new()
	_camera.far = main.player.camera.far
	_camera.fov = main.player.camera.fov
	main.add_child(_camera)

	var cyclops := main.get_body(&"Cyclops")
	for child in cyclops.get_children():
		if child is CyclopsStorms:
			_storms = child as CyclopsStorms
	await _ticks(120)
	# PROBE_SCENE=cyclops_walk skips the trip and the space views.
	var walk_only := OS.get_environment("PROBE_SCENE") == "cyclops_walk"
	if not walk_only:
		_print_row("terra_walk", await _sample(SAMPLE_FRAMES))
		await _autopilot_trip(cyclops)
		await _bisect("cyclops_cockpit")
		main.ship.exit_pilot()
	main.spawn_on_planet(cyclops)
	await _ticks(240)
	main.player.camera.make_current()
	await _bisect("cyclops_walk")
	if not walk_only:
		await _bisect_view("space_to_sun", cyclops, 0.0)
		await _bisect_view("space_to_cyclops", cyclops, PI)
	print("[probe] done")
	quit(0)


func _measure_shader_compiles() -> void:
	var rd := RenderingServer.get_rendering_device()
	for path in COMPUTE_SHADERS:
		var text := FileAccess.get_file_as_string(path)
		var source := RDShaderSource.new()
		source.source_compute = text
		var start := Time.get_ticks_usec()
		rd.shader_compile_spirv_from_source(source, true)
		var raw_ms := float(Time.get_ticks_usec() - start) / 1000.0
		ShaderCache.compile(rd, path.get_file().get_basename(), text)
		start = Time.get_ticks_usec()
		ShaderCache.compile(rd, path.get_file().get_basename(), text)
		var cached_ms := float(Time.get_ticks_usec() - start) / 1000.0
		print("[probe] compile %s: glslang %.1f ms, ShaderCache hit %.2f ms" % [path.get_file(), raw_ms, cached_ms])


func _autopilot_trip(target: PlanetBody) -> void:
	main.ship.enter_pilot(main.player)
	await _ticks(60)
	var hud := get_first_node_in_group("hud") as Hud
	hud.locked_body = target
	main.ship.toggle_autopilot()
	for segment in TRIP_MAX_SEGMENTS:
		if main.ship.autopilot_target == null:
			break
		var stats := await _sample(TRIP_SEGMENT_FRAMES)
		var altitude := main.ship.global_position.distance_to(target.global_position) - target.radius
		_print_row("trip_%02d alt %6.0f" % [segment, altitude], stats)
	print("[probe] autopilot %s" % ("arrived" if main.ship.autopilot_target == null else "still flying"))


# Free camera outside Cyclops, looking at the sun (angle 0) or back at Cyclops (PI).
func _bisect_view(label: String, body: PlanetBody, angle: float) -> void:
	var to_sun := (main.sun.global_position - body.global_position).normalized()
	var side := to_sun.cross(Vector3.UP).normalized()
	var position := body.global_position + to_sun * body.radius * 6.0 + side * body.radius * 2.0 + Vector3.UP * body.radius
	_camera.global_position = position
	_camera.look_at(main.sun.global_position if angle == 0.0 else body.global_position, Vector3.UP)
	_camera.make_current()
	await _bisect(label)
	main.player.camera.make_current()


func _bisect(label: String) -> void:
	for variant in VARIANTS:
		_apply_variant(variant)
		await _ticks(WARMUP_FRAMES)
		_print_row("%s %s" % [label, variant], await _sample(SAMPLE_FRAMES))
	_apply_variant(&"base")


func _apply_variant(variant: StringName) -> void:
	main.apply_graphics()
	effects.display_oceans = variant != &"no_ocean" and variant != &"no_effects"
	effects.display_atmospheres = variant != &"no_atmosphere" and variant != &"no_effects"
	match variant:
		&"no_shadows":
			main.sun_light.shadow_enabled = false
		&"no_ssao":
			environment.ssao_enabled = false
		&"no_glow":
			environment.glow_enabled = false
		&"half_scale":
			root.scaling_3d_scale = 0.5
		&"full_scale":
			root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			root.scaling_3d_scale = 1.0
	environment.background_mode = Environment.BG_COLOR if variant == &"no_sky" else Environment.BG_SKY
	if _storms != null and _storms._storm_interior != null:
		_storms._storm_interior.visible = variant != &"no_storms"
	if _storms != null:
		(_storms.get_node("StormCloudShell") as Node3D).visible = variant != &"no_cloud_shell" and variant != &"bare"
	main._feedback_root.visible = variant != &"no_rain" and variant != &"bare"
	(get_first_node_in_group("hud") as Hud).visible = variant != &"no_hud" and variant != &"bare"
	main.get_body(&"Cyclops")._terrain.visible = variant != &"no_terrain"
	if variant == &"no_fxaa":
		root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	if variant == &"bare":
		effects.display_oceans = false
		effects.display_atmospheres = false
		environment.ssao_enabled = false
		environment.glow_enabled = false


func stamp_process(last: bool) -> void:
	var now := Time.get_ticks_usec()
	if last:
		_frame_process_usec = now - _process_begin
		return
	_process_begin = now
	_frame_physics_usec = now - _physics_begin if _physics_pending else 0
	_physics_pending = false


func stamp_physics(last: bool) -> void:
	if not last and not _physics_pending:
		_physics_begin = Time.get_ticks_usec()
		_physics_pending = true


func _sample(frames: int) -> Dictionary:
	var frame_ms := PackedFloat64Array()
	var sums := {"gpu": 0.0, "render_cpu": 0.0, "steps": 0.0, "effects": 0.0, "passes": 0.0, "draws": 0.0, "primitives": 0.0, "objects": 0.0, "cpu_process": 0.0, "cpu_physics": 0.0}
	var last_usec := Time.get_ticks_usec()
	var last_physics := Engine.get_physics_frames()
	for _frame in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - last_usec) / 1000.0)
		last_usec = now
		sums.steps += Engine.get_physics_frames() - last_physics
		last_physics = Engine.get_physics_frames()
		sums.gpu += RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid)
		sums.render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid)
		sums.effects += _effects_ms
		sums.cpu_process += float(_frame_process_usec) / 1000.0
		sums.cpu_physics += float(_frame_physics_usec) / 1000.0
		sums.passes += effects._passes.size() * 0.5
		sums.draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		sums.primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		sums.objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		RenderingServer.call_on_render_thread(_read_effects_timing)
	var result := {}
	for key in sums:
		result[key] = sums[key] / float(frames)
	var total := 0.0
	for value in frame_ms:
		total += value
	result.frame = total / float(frames)
	frame_ms.sort()
	result.p95 = frame_ms[int(frames * 0.95)]
	result.max = frame_ms[frames - 1]
	return result


func _read_effects_timing() -> void:
	_effects_ms = float(GpuTimings.read(RenderingServer.get_rendering_device(), "planet_effects_").get("total", 0.0))


func _print_row(label: String, stats: Dictionary) -> void:
	print("[probe] %-32s | frame %6.2f p95 %6.2f max %6.1f | gpu %6.2f fx %5.2f (%.1f) | cpu process %5.2f physics %5.2f (x%.1f) render %5.2f | draws %4.0f prims %8.0f" % [
		label, stats.frame, stats.p95, stats.max, stats.gpu, stats.effects, stats.passes,
		stats.cpu_process, stats.cpu_physics, stats.steps, stats.render_cpu, stats.draws, stats.primitives])


func _ticks(frames: int) -> void:
	for _frame in frames:
		await process_frame


func _find_world_environment(node: Node) -> WorldEnvironment:
	for child in node.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment
	return null
