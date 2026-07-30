class_name PlanetCache
extends RefCounted

const VERSION := 15


static func load_mesh(purpose: String, resolution: int, shape_profile: int, rng_seed: int, core_radius: float, perturb_strength: float) -> ArrayMesh:
	var cache_path := path(purpose, resolution, shape_profile, rng_seed, core_radius, perturb_strength)
	if not ResourceLoader.exists(cache_path):
		return null
	var mesh := load(cache_path) as ArrayMesh
	if mesh == null:
		return null
	if purpose == "terrain" and not mesh.has_meta("height_minmax"):
		return null
	return mesh


static func save_mesh(mesh: ArrayMesh, purpose: String, resolution: int, shape_profile: int, rng_seed: int, core_radius: float, perturb_strength: float) -> void:
	var directory := ProjectSettings.globalize_path("user://planet_mesh_cache")
	DirAccess.make_dir_recursive_absolute(directory)
	ResourceSaver.save(mesh, path(purpose, resolution, shape_profile, rng_seed, core_radius, perturb_strength), ResourceSaver.FLAG_COMPRESS)


static func path(purpose: String, resolution: int, shape_profile: int, rng_seed: int, core_radius: float, perturb_strength: float) -> String:
	var suffix := ""
	if perturb_strength > 0.0:
		suffix = "_p%d" % int(round(perturb_strength * 1000.0))
	return "user://planet_mesh_cache/v%d_%s_%s_%d_%d_%d%s.res" % [
		VERSION,
		purpose,
		shape_profile,
		rng_seed,
		int(round(core_radius * 1000.0)),
		resolution,
		suffix,
	]
