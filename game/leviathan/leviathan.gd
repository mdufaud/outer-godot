class_name Leviathan
extends Node3D

# Scripted end of the world: something enormous fades in at the back of the
# galaxy, stares, then dives through the system maw-first and eats it.
#
# The devour front mirrors the supernova blast: the supernova sweeps a shell
# outwards from the sun and destroys what it passes, this sweeps a shell inwards
# and does the same, so the system is eaten outermost body first.

const LeviathanModel := preload("res://assets/models/leviathan_rigged.scn")
const AbyssSkinShader := preload("res://game/leviathan/shaders/abyss_skin.gdshader")
const MawStormShader := preload("res://game/leviathan/shaders/maw_storm.gdshader")
const RoarScript := preload("res://game/leviathan/leviathan_roar.gd")

const STATE_DORMANT := 0
const STATE_FADE_IN := 1
const STATE_APPROACH := 2
const STATE_BLACKOUT := 3

const BODY_LENGTH := 32000.0

# Landmarks measured off the imported model with tools/leviathan_shot.gd. In its
# own space the maw faces +Z, the tail fangs sweep back to -Z, +Y is the crown
# and the lantern hangs forward of the snout on its stalk.
const MODEL_LENGTH := 250.4336
const MODEL_MAW_Z := 100.0
const MODEL_STORM_CENTRE := Vector3(0.0, 45.0, 25.0)
const MODEL_STORM_HALF_EXTENTS := Vector3(30.0, 32.0, 60.0)
const MODEL_LURE := Vector3(0.0, 118.5, 125.0)

# The model's own origin sits at the bottom of the head, so the height of the
# storm is the height of the line running down the middle of the throat. Pivot
# space is measured off that line and not off the origin: the creature travels
# along its own gullet, so anything it is aimed at goes down it rather than
# under the chin.
const MODEL_THROAT_Y := MODEL_STORM_CENTRE.y

# Pivot space is the model turned to lead with the maw, scaled to BODY_LENGTH
# and shifted so the middle of the maw front sits at the origin: -Z leads, +Z
# runs back down the throat, which is the direction the storm shader raymarches
# its funnel.
const MODEL_SCALE := BODY_LENGTH / MODEL_LENGTH
const STORM_HALF_EXTENTS := MODEL_STORM_HALF_EXTENTS * MODEL_SCALE
# The throat sits this far back from the maw front, so the dive has to carry on
# past the sun by the same amount or the sun ends up held in the teeth forever
# instead of going down the throat.
const THROAT_DEPTH := (MODEL_MAW_Z - MODEL_STORM_CENTRE.z) * MODEL_SCALE

const START_DISTANCE := 42000.0
const DEVOUR_START_DISTANCE := 12000.0
const FADE_IN_DURATION := 9.0
const TRAVEL_DURATION := 30.0
const BLACKOUT_DURATION := 2.5
const DRAW_DISTANCE := 60000.0
const ROAR_INTERVAL := 7.5
# Only a fallback heading: summon() replaces it with one that puts the player
# between the creature and the sun.
const APPROACH_DIRECTION := Vector3(0.42, 0.28, -0.86)
# The jaw stays shut for the first stretch of the dive and opens once, on the way
# into the system. It never shuts again: the gape is what the system falls into.
const MAW_OPEN_START := 0.25
const MAW_OPEN_END := 0.5

var _state := STATE_DORMANT
var _elapsed := 0.0
var _blackout_elapsed := 0.0
var _roar_timer := 0.0
var _body_material := ShaderMaterial.new()
var _storm_material := ShaderMaterial.new()
var _body_pivot: Node3D
var _visual: Node3D
var _rig: LeviathanRig
var _lure_light: OmniLight3D
var _storm: MeshInstance3D
var _storm_light: OmniLight3D
var _storm_flash := 0.0
var _storm_timer := 0.0
var _storm_rng := RandomNumberGenerator.new()
var _blackout: ColorRect
var _roar: Node
var _camera_far := {}
var _direction := APPROACH_DIRECTION.normalized()
var _up_hint := Vector3.UP


func _ready() -> void:
	add_to_group("leviathan")
	_storm_rng.seed = 745631
	_body_material.shader = AbyssSkinShader
	_body_material.set_shader_parameter("presence", 0.0)
	_body_material.set_shader_parameter("flash", 0.0)

	# Everything that belongs to the creature hangs off this pivot so the swim
	# drift turns the body, its storm and its lights as one piece. The root
	# transform itself is overwritten every frame by _place_body.
	_body_pivot = Node3D.new()
	_body_pivot.name = "LeviathanPivot"
	add_child(_body_pivot)

	_visual = LeviathanModel.instantiate()
	_visual.name = "LeviathanVisual"
	_visual.scale = Vector3.ONE * MODEL_SCALE
	# The model faces +Z and the placement aims the root's -Z at the sun, so the
	# half turn is what puts the maw at the front of the dive.
	_visual.rotation.y = PI
	_visual.position = Vector3(0.0, -MODEL_THROAT_Y, MODEL_MAW_Z) * MODEL_SCALE
	_visual.visible = false
	_body_pivot.add_child(_visual)
	var body := _body_mesh()
	assert(body != null)
	_configure_mesh_materials(body)
	var skeleton := _visual.find_children("*", "Skeleton3D", true, false)
	assert(not skeleton.is_empty())
	_rig = LeviathanRig.new(skeleton[0] as Skeleton3D)

	_storm_material.shader = MawStormShader
	_storm_material.set_shader_parameter("half_extents", STORM_HALF_EXTENTS)
	_storm_material.set_shader_parameter("visibility", 0.0)
	_storm_material.set_shader_parameter("flash", 0.0)
	var storm_box := BoxMesh.new()
	storm_box.size = STORM_HALF_EXTENTS * 2.0
	var storm_centre := model_to_pivot(MODEL_STORM_CENTRE)
	_storm = MeshInstance3D.new()
	_storm.name = "MawStorm"
	_storm.mesh = storm_box
	_storm.material_override = _storm_material
	_storm.position = storm_centre
	_storm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_storm.visible = false
	_body_pivot.add_child(_storm)

	_storm_light = OmniLight3D.new()
	_storm_light.name = "MawLightning"
	_storm_light.light_color = Color(0.52, 0.12, 1.0)
	_storm_light.light_energy = 0.0
	_storm_light.omni_range = 14000.0
	_storm_light.shadow_enabled = false
	_storm_light.position = Vector3(0.0, storm_centre.y, storm_centre.z * 0.35)
	_body_pivot.add_child(_storm_light)

	# The lantern is the other thing visible in the dark: it has to actually light
	# the snout, not just glow as an unlit dot.
	_lure_light = OmniLight3D.new()
	_lure_light.name = "LureLantern"
	_lure_light.light_color = Color(1.0, 0.74, 0.42)
	# Weak and short: enough to catch the snout and the nearest fangs, never
	# enough to light the skull and turn the void into a brown balloon.
	_lure_light.light_energy = 0.55
	_lure_light.omni_range = 4200.0
	_lure_light.omni_attenuation = 2.4
	_lure_light.shadow_enabled = false
	_lure_light.position = model_to_pivot(MODEL_LURE)
	_body_pivot.add_child(_lure_light)

	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_blackout = ColorRect.new()
	_blackout.color = Color(0.0, 0.0, 0.0, 0.0)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blackout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_blackout)

	_roar = RoarScript.new()
	_roar.name = "LeviathanRoar"
	add_child(_roar)


# Maps a point measured on the model into pivot space: the middle of the maw
# front at the origin with the throat running back down +Z.
static func model_to_pivot(point: Vector3) -> Vector3:
	return Vector3(-point.x, point.y - MODEL_THROAT_Y, MODEL_MAW_Z - point.z) * MODEL_SCALE


func _body_mesh() -> MeshInstance3D:
	var found := _visual.find_children("*", "MeshInstance3D", true, false)
	return found[0] as MeshInstance3D if not found.is_empty() else null


# The creature ships as one skinned sheet with its own baked maps, so the shader
# borrows them off the imported material rather than duplicating the textures as
# preloads that a re-import could leave behind.
func _configure_mesh_materials(mesh_instance: MeshInstance3D) -> void:
	var source := mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
	assert(source != null)
	_body_material.set_shader_parameter("skin_albedo", source.albedo_texture)
	_body_material.set_shader_parameter("skin_normal", source.normal_texture)
	_body_material.set_shader_parameter("skin_glow", source.emission_texture)
	mesh_instance.set_surface_override_material(0, _body_material)


func summon() -> void:
	if _state != STATE_DORMANT:
		return
	_state = STATE_FADE_IN
	_elapsed = 0.0
	_roar_timer = ROAR_INTERVAL * 0.5
	_visual.visible = true
	var camera := get_viewport().get_camera_3d()
	var sun := get_tree().get_first_node_in_group("sun") as Node3D
	if camera != null and sun != null:
		_direction = spawn_direction(camera.global_position, sun.global_position)
	if camera != null:
		# Frozen at the summon. Reading the live camera every frame rolled the
		# whole creature with the player's aim, which read as the body being
		# dragged around by the cursor.
		_up_hint = camera.global_basis.y
	_roar.call("roar")


# The body always sits at START_DISTANCE from the sun, and the dive ends at the
# sun, so putting the spawn point straight out behind the player is what makes
# the dive line run through them. It rises dead ahead of wherever they stand,
# facing them because the maw is already aimed at the sun past their shoulder,
# then falls down that same line and takes them with it.
static func spawn_direction(player_position: Vector3, sun_position: Vector3) -> Vector3:
	var bearing := player_position - sun_position
	if bearing.length_squared() < 0.001:
		return APPROACH_DIRECTION.normalized()
	return bearing.normalized()


# Only meaningful before it starts eating: once a body is gone it stays gone.
func banish() -> void:
	if _state == STATE_DORMANT or is_devouring():
		return
	_reset_state()


func is_active() -> bool:
	return _state != STATE_DORMANT


func is_devouring() -> bool:
	return _state != STATE_DORMANT and distance_at(_elapsed) <= DEVOUR_START_DISTANCE


func get_dread_factor() -> float:
	return float(_roar.call("get_dread_factor")) if _roar != null else 0.0


static func presence_at(elapsed: float) -> float:
	return clampf(elapsed / FADE_IN_DURATION, 0.0, 1.0)


# Holds station at the back of the galaxy while it fades in, then falls inwards
# with an accelerating curve so the last stretch is the fastest. Measured to the
# maw front, which ends up a throat's depth past the sun: the run is over when
# the sun is swallowed, not when it touches the fangs.
static func distance_at(elapsed: float) -> float:
	if elapsed <= FADE_IN_DURATION:
		return START_DISTANCE
	var travel := clampf((elapsed - FADE_IN_DURATION) / TRAVEL_DURATION, 0.0, 1.0)
	return START_DISTANCE * pow(1.0 - travel, 2.0) - THROAT_DEPTH * travel


static func maw_open_at(elapsed: float) -> float:
	if elapsed <= FADE_IN_DURATION:
		return 0.0
	var travel := clampf((elapsed - FADE_IN_DURATION) / TRAVEL_DURATION, 0.0, 1.0)
	# It crosses half the way in with the mouth shut, then tears it open once and
	# holds it open. Anything that shuts the jaw again mid dive reads as the body
	# chewing on empty space long before there is anything in front of it.
	return smoothstep(MAW_OPEN_START, MAW_OPEN_END, travel)


# Nothing is eaten by proximity: a body dies when it is actually inside the
# throat, which is the same volume the storm shader raymarches its funnel
# through. The point is given in that box's own space.
static func in_throat(throat_point: Vector3, body_radius: float) -> bool:
	var limit := STORM_HALF_EXTENTS + Vector3.ONE * body_radius
	return (absf(throat_point.x) <= limit.x
		and absf(throat_point.y) <= limit.y
		and absf(throat_point.z) <= limit.z)


func _process(delta: float) -> void:
	if _state == STATE_DORMANT:
		return
	if _state == STATE_BLACKOUT:
		_update_blackout(delta)
		return
	_elapsed += delta
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_extend_camera_far(camera)
	var sun := get_tree().get_first_node_in_group("sun") as Node3D
	if sun == null:
		return

	var presence := presence_at(_elapsed)
	var distance := distance_at(_elapsed)
	var maw_open := maw_open_at(_elapsed)
	_body_material.set_shader_parameter("presence", presence)
	_update_rig(presence, maw_open)
	_update_storm(delta, maw_open)
	_roar.call("set_dread", presence)
	if _state == STATE_FADE_IN and _elapsed > FADE_IN_DURATION:
		_state = STATE_APPROACH

	var maw_position := sun.global_position + _direction * distance
	# Aimed down the heading rather than at the sun itself: past the sun the two
	# stop agreeing, and aiming at it would spin the creature round to face what
	# it already has in its mouth.
	_place_body(maw_position, maw_position - _direction * BODY_LENGTH, _up_hint)
	_devour(sun)
	# Whichever the throat closes on first ends the run: the player is on the
	# dive line, the sun is at the end of it.
	if _throat_holds(sun.global_position, _body_radius(sun)) or _player_eaten(camera):
		_start_blackout()
		return

	_roar_timer -= delta
	if _roar_timer <= 0.0:
		_roar_timer = ROAR_INTERVAL
		_roar.call("roar")
	if camera != null:
		var closeness := clampf(1.0 - distance / START_DISTANCE, 0.0, 1.0)
		_shake(pow(closeness, 3.0) * 0.05)


func _update_storm(delta: float, maw_open: float) -> void:
	_storm_flash = maxf(_storm_flash - delta * (7.0 + _storm_flash * 12.0), 0.0)
	if maw_open > 0.08:
		_storm_timer -= delta
		if _storm_timer <= 0.0:
			_storm_flash = _storm_rng.randf_range(0.72, 1.0)
			_storm_timer = _storm_rng.randf_range(0.45, 1.6)
			_roar.call("thunder", _storm_flash)
	else:
		_storm_timer = 0.0
	# The vortex only exists once there is a mouth to see it through.
	_storm.visible = maw_open > 0.02
	_storm_material.set_shader_parameter("visibility", maw_open)
	_storm_material.set_shader_parameter("flash", _storm_flash)
	_body_material.set_shader_parameter("flash", _storm_flash)
	_storm_light.light_energy = _storm_flash * maw_open * 3.2


func _update_rig(presence: float, maw_open: float) -> void:
	# Slow roll and yaw off the aimed heading: it swims towards the system rather
	# than being dragged at it on a rail.
	_body_pivot.rotation = Vector3(
		sin(_elapsed * 0.19) * 0.035,
		sin(_elapsed * 0.23) * 0.045,
		sin(_elapsed * 0.31) * 0.060
	) * smoothstep(0.0, 1.0, presence)
	# The bite beats in maw_open_at drive the jaw hinge and the storm in the
	# throat off the same curve, so the vortex flares as the mouth tears open.
	_rig.apply(_elapsed, maw_open, presence)
	_lure_light.position = model_to_pivot(_rig.lantern_position(MODEL_LURE))


# The maw leads and the tail trails behind it, and it is pointed at the sun for
# the whole sequence: the system is what it came for. The roll is the screen up
# the player had when they summoned it: the mandible drops along the body's -Y,
# so aligning that Y with the screen up is what keeps the gape opening downwards
# instead of rolling edge on and reading as a smooth shell. It is a frozen hint
# rather than the live camera, or aiming turns the creature.
func _place_body(maw_position: Vector3, target_position: Vector3, up_hint: Vector3) -> void:
	var forward := target_position - maw_position
	if forward.length_squared() < 0.001:
		forward = _direction
	forward = forward.normalized()
	var up := up_hint
	if up.length_squared() < 0.001 or absf(up.normalized().dot(forward)) > 0.98:
		up = Vector3.UP if absf(forward.y) < 0.9 else Vector3.RIGHT
	# The box points -Z at the maw, which is what looking_at aims.
	var basis := Basis.looking_at(forward, up)
	global_transform = Transform3D(basis, maw_position)


func _throat_holds(world_point: Vector3, body_radius: float) -> bool:
	return in_throat(_storm.global_transform.affine_inverse() * world_point, body_radius)


func _player_eaten(camera: Camera3D) -> bool:
	return camera != null and _throat_holds(camera.global_position, 0.0)


# Not every member of the group carries one: the ring debris has no radius, and
# a missing one only means the body is eaten when its centre crosses the fangs.
func _body_radius(body: Node3D) -> float:
	var value: Variant = body.get("radius")
	return float(value) if value is float or value is int else 0.0


func _devour(sun: Node3D) -> void:
	var main := get_tree().current_scene
	for node in get_tree().get_nodes_in_group("celestial_body"):
		var body := node as Node3D
		if body == null or body == sun or not is_instance_valid(body):
			continue
		if not _throat_holds(body.global_position, _body_radius(body)):
			continue
		if main != null and main.has_method("forget_body"):
			main.forget_body(body)
		body.queue_free()
		_roar.call("roar")
		_shake(0.09)


func _start_blackout() -> void:
	_state = STATE_BLACKOUT
	_blackout_elapsed = 0.0
	_roar.call("roar")


func _update_blackout(delta: float) -> void:
	_blackout_elapsed += delta
	_elapsed += delta
	var sun := get_tree().get_first_node_in_group("sun") as Node3D
	if sun != null:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			_extend_camera_far(camera)
		var presence := presence_at(_elapsed)
		var distance := distance_at(_elapsed)
		var maw_open := maw_open_at(_elapsed)
		_body_material.set_shader_parameter("presence", presence)
		_update_rig(presence, maw_open)
		_update_storm(delta, maw_open)
		var maw_position := sun.global_position + _direction * distance
		_place_body(maw_position, maw_position - _direction * BODY_LENGTH, _up_hint)
	_blackout.color.a = clampf(_blackout_elapsed / BLACKOUT_DURATION, 0.0, 1.0)
	_roar.call("set_dread", 1.0)
	if _blackout_elapsed >= BLACKOUT_DURATION:
		_visual.visible = false
		_storm.visible = false
		_state = STATE_DORMANT
		get_tree().reload_current_scene()


func _reset_state() -> void:
	_state = STATE_DORMANT
	_elapsed = 0.0
	_blackout_elapsed = 0.0
	_visual.visible = false
	_storm.visible = false
	_blackout.color.a = 0.0
	_body_material.set_shader_parameter("presence", 0.0)
	_body_material.set_shader_parameter("flash", 0.0)
	_body_pivot.rotation = Vector3.ZERO
	_rig.rest()
	_lure_light.position = model_to_pivot(MODEL_LURE)
	_storm_material.set_shader_parameter("visibility", 0.0)
	_storm_material.set_shader_parameter("flash", 0.0)
	_storm_light.light_energy = 0.0
	_storm_flash = 0.0
	_storm_timer = 0.0
	_roar.call("stop")
	_restore_cameras()


func _shake(strength: float) -> void:
	if strength <= 0.0:
		return
	var main := get_tree().current_scene
	if main != null and main.has_method("trigger_camera_shake"):
		main.trigger_camera_shake(strength, 0.25)


# Both cameras stop at 8000 units, which is inside the system. The creature
# starts five times further out, so the far plane has to open up while it is on
# screen, exactly like the supernova shell does.
func _extend_camera_far(camera: Camera3D) -> void:
	if _camera_far.has(camera):
		return
	_camera_far[camera] = camera.far
	camera.far = DRAW_DISTANCE


func _restore_cameras() -> void:
	for camera in _camera_far:
		if is_instance_valid(camera):
			camera.far = _camera_far[camera]
	_camera_far.clear()
