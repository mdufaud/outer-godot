class_name PlanetQuality
extends RefCounted

const PROFILES := {
	"desktop_high": {"lod": [300, 100, 50], "collision": 100},
	"desktop_medium": {"lod": [150, 50, 25], "collision": 50},
	"mobile_low": {"lod": [60, 24, 12], "collision": 20},
}


static func get_profile(profile_name: String) -> Dictionary:
	return PROFILES.get(profile_name, PROFILES["desktop_high"])
