extends PlanetBody

const ShapeProfileScript := preload("res://game/planets/shared/planet_shape_profile.gd")
const DreadPulseScript := preload("res://game/planets/watchful_eye/dread_pulse.gd")
const CometTrailScript := preload("res://game/planets/watchful_eye/comet_trail.gd")


func _ready() -> void:
	super._ready()
	var dread := DreadPulseScript.new()
	dread.name = "WatchfulEyeDread"
	dread.target = self
	add_child(dread)
	var comet := CometTrailScript.new()
	comet.name = "WatchfulEyeTrail"
	comet.target = self
	comet.sun = get_tree().get_first_node_in_group("sun")
	add_child(comet)


func configure_planet(config: PlanetConfig) -> void:
	config.body_id = &"Watchful Eye"
	config.shape_profile = ShapeProfileScript.WATCHFUL_EYE
	config.surface.material_profile = ShapeProfileScript.WATCHFUL_EYE
	config.radius = 20.7
	config.surface_gravity = 8.0
	config.rng_seed = 7
	config.ocean.enabled = false
	config.atmosphere.enabled = false
