extends PlanetBody

const ShapeProfileScript := preload("res://game/planets/shared/planet_shape_profile.gd")
const AsteroidRingScript := preload("res://game/planets/mirage/asteroid_ring.gd")


func _ready() -> void:
	super._ready()
	var ring := AsteroidRingScript.new()
	ring.name = "MirageRing"
	add_child(ring)


func configure_planet(config: PlanetConfig) -> void:
	config.body_id = &"Mirage"
	config.shape_profile = ShapeProfileScript.MIRAGE
	config.surface.material_profile = ShapeProfileScript.MIRAGE
	config.radius = 34.0
	config.surface_gravity = 7.0
	config.rng_seed = 4711
	config.perturb_strength = 0.03
	config.ocean.enabled = false
	config.atmosphere.scale = 0.42
	config.atmosphere.density_falloff = 3.2
	config.atmosphere.wavelengths = Vector3(460.0, 540.0, 700.0)
	config.atmosphere.scattering_strength = 24.0
	config.atmosphere.intensity = 0.3
