class_name PlanetQuality
extends RefCounted

const PROFILES := {
	"desktop_high": {"lod": [300, 100, 50], "collision": 100},
	"desktop_medium": {"lod": [150, 50, 25], "collision": 50},
	"mobile_low": {"lod": [60, 24, 12], "collision": 20},
}


# Tier subdivisions are tuned for a planet this size: smaller bodies keep its facet size with fewer
# subdivisions, larger ones stay capped at the tier.
const REFERENCE_RADIUS := 46.0


static func get_profile(profile_name: String) -> Dictionary:
	return PROFILES.get(profile_name, PROFILES["desktop_high"])


# LOD1 and LOD2 only show a planet small on screen, so they stay fixed; the close mesh and the
# collider are what the player walks on, so they follow the radius, floored at the next coarser level.
static func get_resolutions(profile_name: String, radius: float) -> Dictionary:
	var profile := get_profile(profile_name)
	var near := int(profile.lod[0])
	var middle := int(profile.lod[1])
	var far := int(profile.lod[2])
	var scale := minf(radius / REFERENCE_RADIUS, 1.0)
	return {
		"lod": [maxi(ceili(near * scale), middle), middle, far],
		"collision": maxi(ceili(int(profile.collision) * scale), far),
	}
