class_name CyclopsStorms
extends Node3D

const GeometryScript := preload("res://game/planets/cyclops/cyclops_geometry.gd")
const TORNADO_COUNT := 14
const STORM_MOTION_SCALE := 0.5
const STORM_MIN_SEPARATION := 0.453786
const STORM_ROCK_MIN_SEPARATION := 0.383972
const STORM_LIFT_GRAVITY_SCALE := 3.2
const STORM_POLAR_LIFT_SCALE := 1.3
const STORM_SWIRL_GRAVITY_SCALE := 1.7
const STORM_SUCTION_GRAVITY_SCALE := 0.7
const STORM_CATCH_MARGIN := 1.4
const STORM_LIFT_RELEASE_FRACTION := 0.85
const POLAR_TORNADO_WIDTH_SCALE := 2.25

var body: PlanetBody
var _storm_interior: Node3D
var _storm_orbits: Array[Node3D] = []
var _storm_rigs: Array[Skeleton3D] = []
var _storm_contacts: Array[Area3D] = []
var _storm_funnel_materials: Array[ShaderMaterial] = []
var _storm_glows: Array[GeometryInstance3D] = []
var _storm_lights: Array[OmniLight3D] = []
var _storm_elapsed := 0.0
var _storm_visibility := 0.0
var _storm_states: Array[Dictionary] = []


func setup(next_body: PlanetBody) -> void:
	body = next_body


func _ready() -> void:
	_build_storm_system()


func _process(delta: float) -> void:
	_update_storms(delta)


func get_contacts() -> Array[Area3D]:
	return _storm_contacts


func get_visibility() -> float:
	return _storm_visibility


func get_environment_force(world_position: Vector3) -> Vector3:
	return _get_storm_push(world_position)


func _surface_basis(direction: Vector3, roll: float) -> Basis:
	var reference := Vector3.UP if absf(direction.y) < 0.92 else Vector3.FORWARD
	var tangent := reference.cross(direction).normalized()
	var bitangent := tangent.cross(direction).normalized()
	return Basis(tangent, direction, bitangent).rotated(direction, roll)


func _build_storm_system() -> void:
	if not body.weather_enabled or body.config.weather.cloud_shader == null:
		return
	# One opaque shell: cull_disabled means it already flips from exterior cloud ball to interior
	# ceiling when the camera crosses it, and the screen tint is opaque at that crossing.
	var cloud_shell := MeshInstance3D.new()
	cloud_shell.name = "StormCloudShell"
	var cloud_mesh := SphereMesh.new()
	cloud_mesh.radius = body.get_weather_deck_center()
	cloud_mesh.height = cloud_mesh.radius * 2.0
	cloud_mesh.radial_segments = 96
	cloud_mesh.rings = 48
	var cloud_material := ShaderMaterial.new()
	cloud_material.shader = body.config.weather.cloud_shader
	cloud_shell.mesh = cloud_mesh
	cloud_shell.material_override = cloud_material
	cloud_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cloud_shell)
	_initialize_storm_states()


func _initialize_storm_states() -> void:
	if not _storm_states.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = body.rng_seed * 3571 + 91
	_storm_states.append(_make_storm_state(rng, Vector3.UP, true, POLAR_TORNADO_WIDTH_SCALE, 0, "NorthPolarTornado"))
	_storm_states.append(_make_storm_state(rng, Vector3.DOWN, true, POLAR_TORNADO_WIDTH_SCALE, 0, "SouthPolarTornado"))
	for index in TORNADO_COUNT:
		var state := _make_storm_state(rng, Vector3.FORWARD, false, 1.0, rng.randi_range(0, 3), "TornadoOrbit%d" % index)
		state.direction = _choose_storm_direction(float(state.crown_radius), float(state.contact_radius), rng)
		var direction: Vector3 = state.direction
		var drift := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		)
		drift = (drift - direction * drift.dot(direction)).normalized()
		state.velocity = drift * rng.randf_range(0.012, 0.022) * STORM_MOTION_SCALE
		state.wander_axis = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		state.wander_phase = rng.randf_range(0.0, TAU)
		_storm_states.append(state)


func _make_storm_state(rng: RandomNumberGenerator, direction: Vector3, is_static: bool, width_scale: float, shape_kind: int, state_name: String) -> Dictionary:
	# The funnel spans the sea-to-deck gap by construction: its foot is pinned to body.sea_level() and
	# its crown always lands inside the deck, whatever the planet size.
	var funnel_height: float = GeometryScript.funnel_height(body.sea_level(), rng.randf())
	var width: float = funnel_height * width_scale
	var crown_range: Vector2 = GeometryScript.CROWN_RADIUS_RANGE
	var trunk_range: Vector2 = GeometryScript.TRUNK_RADIUS_RANGE
	var base_range: Vector2 = GeometryScript.BASE_RADIUS_RANGE
	var crown_radius: float = rng.randf_range(crown_range.x, crown_range.y) * width
	var roll := rng.randf_range(0.0, TAU)
	var phase := rng.randf_range(0.0, TAU)
	var base_radius: float = rng.randf_range(base_range.x, base_range.y) * width
	var trunk_radius: float = rng.randf_range(trunk_range.x, trunk_range.y) * width
	var shape_seed := 0.0 if is_static else rng.randf_range(0.0, 100.0)
	var bend_scale := 0.0 if is_static else rng.randf_range(0.85, 1.75)
	var bend_speed := 1.0 if is_static else rng.randf_range(0.72, 1.38)
	var sway_strength := 1.0 if is_static else rng.randf_range(0.8, 1.45)
	var pulse_strength := 0.0 if is_static else rng.randf_range(0.06, 0.16)
	return {
		"name": state_name,
		"direction": direction,
		"static": is_static,
		"shape_kind": shape_kind,
		"roll": roll,
		"phase": phase,
		"shape_seed": shape_seed,
		"bend_scale": bend_scale,
		"bend_speed": bend_speed,
		"sway_strength": sway_strength,
		"pulse_strength": pulse_strength,
		"funnel_height": funnel_height,
		"base_radius": base_radius,
		"trunk_radius": trunk_radius,
		"crown_radius": crown_radius,
		"contact_radius": crown_radius * GeometryScript.CONTACT_RADIUS_RATIO,
		"velocity": Vector3.ZERO,
		"wander_axis": Vector3.RIGHT,
		"wander_phase": 0.0,
		"orbit": null,
		"contact": null,
	}


func _choose_storm_direction(crown_radius: float, contact_radius: float, rng: RandomNumberGenerator) -> Vector3:
	var best := Vector3.FORWARD
	var best_clearance := -INF
	for _attempt in 512:
		var candidate := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		var clearance := INF
		for state in _storm_states:
			var required := _storm_minimum_angle(crown_radius, float(state.crown_radius))
			clearance = minf(clearance, candidate.angle_to(state.direction) - required)
		for rock_index in body.get_landing_rock_directions().size():
			var required := _storm_rock_minimum_angle(contact_radius, body.get_landing_rock_radii()[rock_index])
			clearance = minf(clearance, candidate.angle_to(body.get_landing_rock_directions()[rock_index]) - required)
		if clearance > best_clearance:
			best = candidate
			best_clearance = clearance
	return best


func _storm_minimum_angle(first_radius: float, second_radius: float) -> float:
	var margin: float = body.sea_level() * GeometryScript.SEPARATION_MARGIN_RATIO
	var footprint := clampf((first_radius + second_radius + margin) / body.get_weather_deck_center(), 0.0, 0.95)
	return maxf(STORM_MIN_SEPARATION, asin(footprint))


func _storm_rock_minimum_angle(contact_radius: float, rock_radius: float) -> float:
	var margin: float = body.sea_level() * GeometryScript.SEPARATION_MARGIN_RATIO
	var footprint := clampf((contact_radius + rock_radius + margin) / body.sea_level(), 0.0, 0.95)
	return maxf(STORM_ROCK_MIN_SEPARATION, asin(footprint))


func _build_storm_interior() -> void:
	if _storm_interior != null:
		return
	_storm_interior = Node3D.new()
	_storm_interior.name = "StormInterior"
	add_child(_storm_interior)
	var storm_rng := RandomNumberGenerator.new()
	storm_rng.seed = body.rng_seed * 3571 + 1901
	for index in _storm_states.size():
		var state: Dictionary = _storm_states[index]
		var shape_kind := int(state.shape_kind)
		var orbit := Node3D.new()
		orbit.name = String(state.name)
		orbit.basis = _storm_basis_for_direction(state.direction, float(state.roll))
		orbit.set_meta("shape_kind", shape_kind)
		orbit.set_meta("static", bool(state.static))
		_storm_interior.add_child(orbit)
		var funnel_height := float(state.funnel_height)
		var funnel_root := Node3D.new()
		funnel_root.name = "Tornado"
		funnel_root.position = Vector3(body.sea_level() + funnel_height * 0.5, 0.0, 0.0)
		funnel_root.rotation_degrees.z = -90.0
		orbit.add_child(funnel_root)
		var base_phase := float(state.phase)
		var shape_seed := float(state.shape_seed)
		var randomize_shape := not bool(state.static)
		var base_radius := float(state.base_radius)
		var trunk_radius := float(state.trunk_radius)
		var crown_radius := float(state.crown_radius)
		var skeleton := Skeleton3D.new()
		skeleton.name = "TornadoRig"
		skeleton.set_meta("phase", base_phase)
		skeleton.set_meta("static", bool(state.static))
		skeleton.set_meta("funnel_height", funnel_height)
		var bend_scale: float = [0.18, 0.42, 0.78, 1.0][shape_kind] if bool(state.static) else float(state.bend_scale) * [0.7, 0.9, 1.1, 1.25][shape_kind]
		skeleton.set_meta("bend_scale", bend_scale)
		skeleton.set_meta("bend_speed", float(state.bend_speed))
		for bone_index in 3:
			skeleton.add_bone(["Lower", "Middle", "Crown"][bone_index])
			var bone_height := lerpf(-funnel_height * 0.5, funnel_height * 0.5, float(bone_index) * 0.5)
			skeleton.set_bone_rest(bone_index, Transform3D(Basis.IDENTITY, Vector3(0.0, bone_height, 0.0)))
		funnel_root.add_child(skeleton)
		var funnel_mesh := _build_tornado_mesh(funnel_height, base_radius, trunk_radius, crown_radius, base_phase, shape_kind, shape_seed, randomize_shape)
		var skirt_mesh := _build_storm_skirt_mesh(funnel_height, base_radius, base_phase, shape_kind, shape_seed, randomize_shape)
		var skin := skeleton.create_skin_from_rest_transforms()
		for layer in 3:
			var funnel := MeshInstance3D.new()
			funnel.name = ["DenseCore", "ChurningMist", "OuterVapour"][layer]
			var funnel_material := ShaderMaterial.new()
			funnel_material.shader = body.config.weather.funnel_shader
			funnel_material.set_shader_parameter("phase", base_phase + float(layer) * 1.93)
			funnel_material.set_shader_parameter("layer_offset", float(layer) * 0.72)
			funnel_material.set_shader_parameter("radial_scale", 1.0 + float(layer) * 0.1)
			funnel_material.set_shader_parameter("shape_seed", shape_seed)
			funnel_material.set_shader_parameter("shape_change_amount", 0.0 if bool(state.static) else 1.0)
			funnel_material.set_shader_parameter("sway_strength", float(state.sway_strength))
			funnel_material.set_shader_parameter("pulse_strength", float(state.pulse_strength))
			var base_opacity: float = [0.96, 0.5, 0.26][layer]
			funnel_material.set_meta("base_opacity", base_opacity)
			funnel_material.set_shader_parameter("opacity", base_opacity * _storm_visibility)
			funnel.mesh = funnel_mesh
			funnel.skin = skin
			funnel.skeleton = NodePath("..")
			funnel.material_override = funnel_material
			funnel.custom_aabb = AABB(
				Vector3(-crown_radius * 1.5, -funnel_height * 0.6, -crown_radius * 1.5),
				Vector3(crown_radius * 3.0, funnel_height * 1.2, crown_radius * 3.0)
			)
			funnel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			skeleton.add_child(funnel)
			_storm_funnel_materials.append(funnel_material)
			var skirt := MeshInstance3D.new()
			skirt.name = ["SkirtCore", "SkirtMist", "SkirtVapour"][layer]
			skirt.mesh = skirt_mesh
			skirt.position.y = -funnel_height * 0.5
			skirt.material_override = funnel_material
			skirt.custom_aabb = AABB(
				Vector3(-base_radius * 5.0, -funnel_height * GeometryScript.ACTIVE_BAND_RATIO, -base_radius * 5.0),
				Vector3(base_radius * 10.0, funnel_height * 0.35, base_radius * 10.0)
			)
			skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			funnel_root.add_child(skirt)
		var contact := Area3D.new()
		contact.name = "WaterDisplacementVolume"
		contact.position.y = -funnel_height * 0.5 + funnel_height * 0.009
		contact.collision_layer = 0
		contact.collision_mask = 0
		contact.monitoring = false
		contact.set_meta("radius", float(state.contact_radius))
		var contact_shape := CollisionShape3D.new()
		var contact_cylinder := CylinderShape3D.new()
		contact_cylinder.radius = float(state.contact_radius)
		contact_cylinder.height = funnel_height * 0.048
		contact_shape.shape = contact_cylinder
		contact.add_child(contact_shape)
		funnel_root.add_child(contact)
		_storm_orbits.append(orbit)
		_storm_rigs.append(skeleton)
		_storm_contacts.append(contact)
		state.orbit = orbit
		state.contact = contact
		_storm_states[index] = state
	_build_abyss_lights(storm_rng)
	_set_storm_visibility(_storm_visibility)


func _storm_basis_for_direction(direction: Vector3, roll: float) -> Basis:
	var reference := Vector3.UP if absf(direction.y) < 0.92 else Vector3.FORWARD
	var tangent := reference.cross(direction).normalized()
	var binormal := direction.cross(tangent).normalized()
	return Basis(direction, tangent, binormal).rotated(direction, roll)


func _build_tornado_mesh(funnel_height: float, base_radius: float, trunk_radius: float, crown_radius: float, phase: float, shape_kind: int, shape_seed: float, randomize_shape: bool) -> ArrayMesh:
	const RADIAL_SEGMENTS := 64
	const HEIGHT_SEGMENTS := 48
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	for ring in HEIGHT_SEGMENTS + 1:
		var height_fraction := float(ring) / float(HEIGHT_SEGMENTS)
		var body_blend := smoothstep(0.0, 0.56, height_fraction)
		var crown_blend := smoothstep(0.67, 0.94, height_fraction)
		if shape_kind == 1:
			body_blend = smoothstep(0.28, 0.82, height_fraction)
			crown_blend = smoothstep(0.78, 0.97, height_fraction)
		elif shape_kind == 0:
			body_blend = smoothstep(0.0, 0.42, height_fraction)
			crown_blend = smoothstep(0.72, 0.95, height_fraction)
		var body_radius := lerpf(base_radius, trunk_radius, body_blend)
		var profile_radius := lerpf(body_radius, crown_radius, crown_blend)
		var centre := _tornado_centre_offset(height_fraction, funnel_height, phase, shape_kind, shape_seed, randomize_shape)
		var lower_weight := clampf(1.0 - height_fraction * 2.0, 0.0, 1.0)
		var middle_weight := 1.0 - absf(height_fraction - 0.5) * 2.0
		var upper_weight := clampf(height_fraction * 2.0 - 1.0, 0.0, 1.0)
		var weight_sum := maxf(lower_weight + middle_weight + upper_weight, 0.0001)
		lower_weight /= weight_sum
		middle_weight /= weight_sum
		upper_weight /= weight_sum
		for segment in RADIAL_SEGMENTS + 1:
			var radial_fraction := float(segment) / float(RADIAL_SEGMENTS)
			var angle := radial_fraction * TAU
			var broad_lobe := sin(angle * 2.0 + height_fraction * 8.0 + phase) * lerpf(0.025, 0.11, crown_blend)
			var fine_lobe := sin(angle * 7.0 - height_fraction * 19.0 + phase * 2.3) * 0.045
			var vertical_bulge := 0.0
			if randomize_shape:
				broad_lobe = sin(angle * lerpf(1.5, 3.5, _tornado_shape_random(shape_seed, 4.0)) + height_fraction * lerpf(5.0, 12.0, _tornado_shape_random(shape_seed, 5.0)) + phase) * lerpf(0.035, 0.16, crown_blend)
				fine_lobe = sin(angle * lerpf(5.0, 10.0, _tornado_shape_random(shape_seed, 6.0)) - height_fraction * lerpf(14.0, 27.0, _tornado_shape_random(shape_seed, 7.0)) + phase * 2.3) * lerpf(0.025, 0.075, _tornado_shape_random(shape_seed, 8.0))
				vertical_bulge = sin(height_fraction * lerpf(2.0, 4.5, _tornado_shape_random(shape_seed, 9.0)) * PI + shape_seed) * lerpf(0.03, 0.11, _tornado_shape_random(shape_seed, 10.0))
			var ring_radius := profile_radius * (1.0 + broad_lobe + fine_lobe + vertical_bulge)
			var radial := Vector3(cos(angle), 0.0, sin(angle))
			vertices.append(Vector3(centre.x, (height_fraction - 0.5) * funnel_height, centre.y) + radial * ring_radius)
			normals.append(radial)
			colors.append(Color(lower_weight, middle_weight, upper_weight, crown_blend))
			uvs.append(Vector2(radial_fraction, height_fraction))
			bones.append_array(PackedInt32Array([0, 1, 2, 0]))
			weights.append_array(PackedFloat32Array([lower_weight, middle_weight, upper_weight, 0.0]))
	for ring in HEIGHT_SEGMENTS:
		for segment in RADIAL_SEGMENTS:
			var first := ring * (RADIAL_SEGMENTS + 1) + segment
			var next := first + RADIAL_SEGMENTS + 1
			indices.append_array(PackedInt32Array([first, next, first + 1, first + 1, next, next + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _tornado_shape_random(shape_seed: float, channel: float) -> float:
	return fposmod(sin(shape_seed * 12.9898 + channel * 78.233) * 43758.5453, 1.0)


# Coefficients are fractions of the funnel height, applied once at the end.
func _tornado_centre_offset(height_fraction: float, funnel_height: float, phase: float, shape_kind: int, shape_seed: float, randomize_shape: bool) -> Vector2:
	var centre := Vector2.ZERO
	match shape_kind:
		0:
			centre = Vector2(sin(height_fraction * 5.0), cos(height_fraction * 4.0)) * height_fraction * 0.005
		1:
			centre = Vector2(sin(height_fraction * 6.2), cos(height_fraction * 4.7)) * height_fraction * height_fraction * 0.032
		2:
			centre = Vector2(smoothstep(0.0, 1.0, height_fraction) * 0.162, sin(height_fraction * PI) * 0.032)
		3:
			centre = Vector2(sin(height_fraction * TAU) * 0.184, sin(height_fraction * PI) * 0.026)
	if randomize_shape:
		var irregular_frequency := lerpf(1.7, 3.8, _tornado_shape_random(shape_seed, 0.0))
		var irregular_amplitude := lerpf(0.017, 0.069, _tornado_shape_random(shape_seed, 1.0))
		var irregular := Vector2(
			sin(height_fraction * PI * irregular_frequency + shape_seed),
			cos(height_fraction * PI * (irregular_frequency * 0.73) + shape_seed * 1.37)
		) * pow(height_fraction, 1.25) * irregular_amplitude
		centre += irregular
	return centre.rotated(phase) * funnel_height


# Flared foot for the funnel: same shader, same UV.y scale and same lateral drift,
# so it reads as the funnel surface widening into the sea rather than a second effect.
func _build_storm_skirt_mesh(funnel_height: float, base_radius: float, phase: float, shape_kind: int, shape_seed: float, randomize_shape: bool) -> ArrayMesh:
	const RADIAL_SEGMENTS := 64
	const HEIGHT_SEGMENTS := 14
	var skirt_height := funnel_height * 0.3
	var flare_radius := base_radius * 2.2
	var base_centre := _tornado_centre_offset(0.0, funnel_height, phase, shape_kind, shape_seed, randomize_shape)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring in HEIGHT_SEGMENTS + 1:
		var ring_fraction := float(ring) / float(HEIGHT_SEGMENTS)
		var height_fraction := ring_fraction * skirt_height / funnel_height
		var profile_radius := lerpf(base_radius * 1.02, flare_radius, pow(1.0 - ring_fraction, 2.8))
		var centre := _tornado_centre_offset(height_fraction, funnel_height, phase, shape_kind, shape_seed, randomize_shape) - base_centre
		for segment in RADIAL_SEGMENTS + 1:
			var radial_fraction := float(segment) / float(RADIAL_SEGMENTS)
			var angle := radial_fraction * TAU
			var broad_lobe := sin(angle * 2.0 + height_fraction * 8.0 + phase) * 0.025
			var fine_lobe := sin(angle * 7.0 - height_fraction * 19.0 + phase * 2.3) * 0.045
			var ring_radius := profile_radius * (1.0 + broad_lobe + fine_lobe)
			var radial := Vector3(cos(angle), 0.0, sin(angle))
			vertices.append(Vector3(centre.x, ring_fraction * skirt_height, centre.y) + radial * ring_radius)
			normals.append(radial)
			colors.append(Color(1.0, 0.0, 0.0, 0.0))
			uvs.append(Vector2(radial_fraction, height_fraction))
	for ring in HEIGHT_SEGMENTS:
		for segment in RADIAL_SEGMENTS:
			var first := ring * (RADIAL_SEGMENTS + 1) + segment
			var next := first + RADIAL_SEGMENTS + 1
			indices.append_array(PackedInt32Array([first, next, first + 1, first + 1, next, next + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_abyss_lights(storm_rng: RandomNumberGenerator) -> void:
	var ocean_radius: float = body.sea_level()
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.albedo_color = Color(0.08, 0.8, 0.68)
	glow_material.emission_enabled = true
	glow_material.emission = Color(0.12, 1.0, 0.78)
	glow_material.emission_energy_multiplier = 2.2
	for index in 9:
		var direction := Vector3(
			storm_rng.randf_range(-1.0, 1.0),
			storm_rng.randf_range(-1.0, 1.0),
			storm_rng.randf_range(-1.0, 1.0)
		).normalized()
		var source := Node3D.new()
		source.name = "CoreGlow%d" % index
		source.position = direction * (body.get_core_radius() * storm_rng.randf_range(1.028, 1.110))
		_storm_interior.add_child(source)
		var glow := MeshInstance3D.new()
		var glow_mesh := SphereMesh.new()
		glow_mesh.radius = storm_rng.randf_range(0.005, 0.011) * ocean_radius
		glow_mesh.height = glow_mesh.radius * 2.0
		glow.mesh = glow_mesh
		glow.material_override = glow_material
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.transparency = 1.0 - _storm_visibility
		source.add_child(glow)
		_storm_glows.append(glow)
		var light := OmniLight3D.new()
		light.light_color = Color(0.12, 0.95, 0.75)
		var base_energy := storm_rng.randf_range(1.4, 2.3)
		light.set_meta("base_energy", base_energy)
		light.light_energy = base_energy * _storm_visibility
		light.omni_range = storm_rng.randf_range(0.145, 0.218) * ocean_radius
		light.omni_attenuation = 1.35
		light.shadow_enabled = false
		source.add_child(light)
		_storm_lights.append(light)


func _clear_storm_interior() -> void:
	if _storm_interior == null:
		return
	for index in _storm_states.size():
		var state: Dictionary = _storm_states[index]
		state.orbit = null
		state.contact = null
		_storm_states[index] = state
	_storm_interior.queue_free()
	_storm_interior = null
	_storm_orbits.clear()
	_storm_rigs.clear()
	_storm_contacts.clear()
	_storm_funnel_materials.clear()
	_storm_glows.clear()
	_storm_lights.clear()
	_storm_visibility = 0.0


# A tornado swallows whoever comes close instead of walling them out: the funnel sucks the player
# towards its axis, spins them around it and lifts them along it, then releases the lift under the
# crown so the ride ends as a ballistic throw.
func _get_storm_push(world_position: Vector3) -> Vector3:
	if not body.weather_enabled or _storm_states.is_empty():
		return Vector3.ZERO
	var offset := world_position - body.global_position
	if offset.length_squared() < 0.0001:
		return Vector3.ZERO
	var ocean_radius := body.sea_level()
	var deck_gap := body.get_weather_deck_gap()
	var result := Vector3.ZERO
	for state in _storm_states:
		var axis := (body.global_basis * (state.direction as Vector3)).normalized()
		var along_axis := offset.dot(axis)
		var axial_height := along_axis - ocean_radius
		var funnel_height := float(state.funnel_height)
		if axial_height < -deck_gap * GeometryScript.ACTIVE_BAND_RATIO or axial_height > funnel_height:
			continue
		var lateral := offset - axis * along_axis
		var height_fraction := clampf(axial_height / funnel_height, 0.0, 1.0)
		var catch_radius := lerpf(float(state.contact_radius), float(state.crown_radius), height_fraction) * STORM_CATCH_MARGIN
		var lateral_distance := lateral.length()
		if lateral_distance >= catch_radius:
			continue
		var radial_fraction := lateral_distance / catch_radius
		var grip := 1.0 - smoothstep(0.35, 1.0, radial_fraction)
		var lift_fade := 1.0 - smoothstep(STORM_LIFT_RELEASE_FRACTION, 1.0, height_fraction)
		var lift_scale := STORM_POLAR_LIFT_SCALE if bool(state.static) else 1.0
		result += axis * body.surface_gravity * STORM_LIFT_GRAVITY_SCALE * lift_scale * grip * lift_fade
		if lateral_distance <= 0.001:
			continue
		# Suction and swirl have no defined direction on the axis, and both fade to nothing there so
		# the middle of the funnel is a clean updraft.
		var inward := -lateral / lateral_distance
		var wall_fraction := minf(radial_fraction / 0.35, 1.0)
		result += inward * body.surface_gravity * STORM_SUCTION_GRAVITY_SCALE * grip * wall_fraction
		result += axis.cross(inward) * body.surface_gravity * STORM_SWIRL_GRAVITY_SCALE * grip * wall_fraction
	return result


func _set_storm_visibility(value: float) -> void:
	_storm_visibility = clampf(value, 0.0, 1.0)
	for material in _storm_funnel_materials:
		material.set_shader_parameter("opacity", float(material.get_meta("base_opacity")) * _storm_visibility)
	for glow in _storm_glows:
		glow.transparency = 1.0 - _storm_visibility
	for light in _storm_lights:
		light.light_energy = float(light.get_meta("base_energy")) * _storm_visibility


func _update_storm_motion(delta: float) -> void:
	for index in _storm_states.size():
		var state: Dictionary = _storm_states[index]
		if bool(state.static):
			continue
		var direction: Vector3 = state.direction
		var velocity: Vector3 = state.velocity
		var wander_axis: Vector3 = state.wander_axis
		var wander := wander_axis - direction * wander_axis.dot(direction)
		if wander.length_squared() < 0.0001:
			wander = direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT)
		velocity += wander.normalized() * sin(_storm_elapsed * 0.37 + float(state.wander_phase)) * 0.0025 * delta
		velocity -= direction * velocity.dot(direction)
		velocity = velocity.limit_length(0.025 * STORM_MOTION_SCALE)
		state.direction = (direction + velocity * delta).normalized()
		state.velocity = velocity
		_storm_states[index] = state
	for _iteration in 3:
		for first_index in _storm_states.size():
			for second_index in range(first_index + 1, _storm_states.size()):
				_enforce_storm_pair_separation(first_index, second_index)
		for state_index in _storm_states.size():
			var state: Dictionary = _storm_states[state_index]
			if bool(state.static):
				continue
			var direction: Vector3 = state.direction
			for rock_index in body.get_landing_rock_directions().size():
				var required := _storm_rock_minimum_angle(float(state.contact_radius), body.get_landing_rock_radii()[rock_index])
				var angle := direction.angle_to(body.get_landing_rock_directions()[rock_index])
				if angle < required:
					direction = _move_direction_away(direction, body.get_landing_rock_directions()[rock_index], required - angle)
			state.direction = direction
			_storm_states[state_index] = state
	for index in _storm_states.size():
		var state: Dictionary = _storm_states[index]
		if not bool(state.static):
			var direction: Vector3 = state.direction
			var velocity: Vector3 = state.velocity
			state.velocity = (velocity - direction * velocity.dot(direction)) * 0.998
			_storm_states[index] = state
		var orbit: Node3D = state.orbit as Node3D
		if is_instance_valid(orbit):
			orbit.basis = _storm_basis_for_direction(state.direction, float(state.roll))


func _enforce_storm_pair_separation(first_index: int, second_index: int) -> void:
	var first: Dictionary = _storm_states[first_index]
	var second: Dictionary = _storm_states[second_index]
	var first_direction: Vector3 = first.direction
	var second_direction: Vector3 = second.direction
	var required := _storm_minimum_angle(float(first.crown_radius), float(second.crown_radius))
	var angle := first_direction.angle_to(second_direction)
	if angle >= required or (bool(first.static) and bool(second.static)):
		return
	var correction := required - angle
	if bool(first.static):
		second.direction = _move_direction_away(second_direction, first_direction, correction)
	elif bool(second.static):
		first.direction = _move_direction_away(first_direction, second_direction, correction)
	else:
		first.direction = _move_direction_away(first_direction, second_direction, correction * 0.5)
		second.direction = _move_direction_away(second_direction, first_direction, correction * 0.5)
	_storm_states[first_index] = first
	_storm_states[second_index] = second


func _move_direction_away(direction: Vector3, anchor: Vector3, angle: float) -> Vector3:
	var current_angle := direction.angle_to(anchor)
	var away := direction * cos(current_angle) - anchor
	if away.length_squared() < 0.0001:
		away = direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT)
	return (direction * cos(angle) + away.normalized() * sin(angle)).normalized()


func _update_storms(delta: float) -> void:
	if not body.weather_enabled:
		return
	_storm_elapsed += delta
	_update_storm_motion(delta)
	var camera := body.get_viewport().get_camera_3d()
	if camera == null:
		return
	var camera_distance := camera.global_position.distance_to(body.global_position)
	var ocean_radius := body.sea_level()
	var preload_radius: float = GeometryScript.streaming_radius(ocean_radius, GeometryScript.PRELOAD_RATIO)
	var full_visibility_radius: float = GeometryScript.streaming_radius(ocean_radius, GeometryScript.FULL_VISIBILITY_RATIO)
	var fade_radius: float = GeometryScript.streaming_radius(ocean_radius, GeometryScript.FADE_RATIO)
	var unload_radius: float = GeometryScript.streaming_radius(ocean_radius, GeometryScript.UNLOAD_RATIO)
	var loaded_visibility := 1.0 - smoothstep(full_visibility_radius, fade_radius, camera_distance)
	var visibility: float = loaded_visibility * GeometryScript.interior_visibility(ocean_radius, camera_distance)
	if camera_distance <= preload_radius and _storm_interior == null:
		_set_storm_visibility(visibility)
		_build_storm_interior()
	elif camera_distance > unload_radius and _storm_interior != null:
		_clear_storm_interior()
	if _storm_interior != null:
		_set_storm_visibility(visibility)
	for rig_index in _storm_rigs.size():
		var rig := _storm_rigs[rig_index]
		var phase := float(rig.get_meta("phase"))
		var bend_scale := float(rig.get_meta("bend_scale"))
		var bend_speed := float(rig.get_meta("bend_speed"))
		var funnel_height := float(rig.get_meta("funnel_height"))
		for bone_index in 3:
			var height_weight := float(bone_index + 1) / 3.0
			var churn := _storm_elapsed * (1.15 + height_weight * 0.72) * STORM_MOTION_SCALE * bend_speed + phase + float(bone_index) * 1.8
			if bool(rig.get_meta("static")):
				var tilt := Vector3(sin(churn * 0.43), 0.0, cos(churn * 0.37)) * (0.025 + height_weight * 0.055) * bend_scale
				var twist := Quaternion(Vector3.UP, sin(churn * 0.53) * (0.08 + height_weight * 0.15) * bend_scale)
				rig.set_bone_pose_rotation(bone_index, Basis.from_euler(tilt).get_rotation_quaternion() * twist)
				var rest_position := rig.get_bone_rest(bone_index).origin
				rig.set_bone_pose_position(bone_index, rest_position + Vector3(sin(churn * 0.71), 0.0, cos(churn * 0.57)) * height_weight * 0.007 * bend_scale * funnel_height)
				continue
			var secondary_churn := _storm_elapsed * 0.19 * bend_speed + phase * 1.7 + float(bone_index) * 0.9
			var tilt := Vector3(sin(churn * 0.43) + sin(secondary_churn) * 0.45, 0.0, cos(churn * 0.37) + cos(secondary_churn * 0.83) * 0.4) * (0.04 + height_weight * 0.085) * bend_scale
			var twist := Quaternion(Vector3.UP, sin(churn * 0.53) * (0.1 + height_weight * 0.18) * bend_scale)
			rig.set_bone_pose_rotation(bone_index, Basis.from_euler(tilt).get_rotation_quaternion() * twist)
			var rest_position := rig.get_bone_rest(bone_index).origin
			var sway := Vector3(sin(churn * 0.71) + sin(secondary_churn * 1.13) * 0.65, 0.0, cos(churn * 0.57) + cos(secondary_churn) * 0.6)
			rig.set_bone_pose_position(bone_index, rest_position + sway * height_weight * 0.016 * bend_scale * funnel_height)
