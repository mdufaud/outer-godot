class_name SolarSystemManifest
extends RefCounted

const CelestialEntryScript := preload("res://game/celestial/celestial_entry.gd")
const TerraScene := preload("res://game/planets/terra/terra.tscn")
const LunaScene := preload("res://game/planets/luna/luna.tscn")
const MirageScene := preload("res://game/planets/mirage/mirage.tscn")
const FieryTwinScene := preload("res://game/planets/fiery_twin/fiery_twin.tscn")
const IceyTwinScene := preload("res://game/planets/icey_twin/icey_twin.tscn")
const CyclopsScene := preload("res://game/planets/cyclops/cyclops.tscn")
const TumblingBeanScene := preload("res://game/planets/tumbling_bean/tumbling_bean.tscn")
const WatchfulEyeScene := preload("res://game/planets/watchful_eye/watchful_eye.tscn")


static func get_entries() -> Array[CelestialEntry]:
	return [
		CelestialEntryScript.new(&"Terra", TerraScene, Vector3(5633.62, 0.0, 0.0), &"sun"),
		CelestialEntryScript.new(&"Luna", LunaScene, Vector3(5416.27, 0.0, 0.0), &"terra"),
		CelestialEntryScript.new(&"Mirage", MirageScene, Vector3(0.0, 0.0, -1487.5), &"sun"),
		CelestialEntryScript.new(&"Fiery Twin", FieryTwinScene, Vector3(2537.59, 0.0, 109.48), &"sun", &"twins"),
		CelestialEntryScript.new(&"Icey Twin", IceyTwinScene, Vector3(2998.74, 0.0, 0.0), &"sun", &"twins"),
		CelestialEntryScript.new(&"Cyclops", CyclopsScene, Vector3(11456.53, 0.0, 0.0), &"sun"),
		CelestialEntryScript.new(&"Tumbling Bean", TumblingBeanScene, Vector3(11078.87, 0.0, 0.0), &"cyclops"),
		CelestialEntryScript.new(&"Watchful Eye", WatchfulEyeScene, Vector3(10676.6, 0.0, 0.0), &"cyclops"),
	]
