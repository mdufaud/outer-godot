extends PlanetBody

# A planet that lives in the scene tree without booting: `_ready` is neutralised so no mesh, no
# collider and no Gravity autoload are needed, while every pure behaviour of PlanetBody
# (sea level, deck geometry, landing, terrain sampling) answers exactly as in the real game.
# Mesh and collider behaviour is the GPU tier's job, not this one's.

const PlanetGeneratorScript := preload("res://game/planets/shared/planet_generator.gd")


func _ready() -> void:
	pass


func _process(_delta: float) -> void:
	pass


func apply(config_value: PlanetConfig) -> void:
	_apply_config(config_value)
	influence_radius = radius * influence_scale
	_height_generator = PlanetGeneratorScript.new(shape_profile, rng_seed)


# Weather and rock features are nodes the real planet builds in `_build_optional_features`; tests
# that need them attach them through here so PlanetBody's public accessors keep working.
func attach_rock_feature(feature: Node) -> void:
	_rock_feature = feature
	add_child(feature)


func attach_weather_feature(feature: Node) -> void:
	_weather_feature = feature
	add_child(feature)
