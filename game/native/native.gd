class_name Native
extends RefCounted

static var enabled := OS.get_environment("NATIVE_KERNELS") != "0"


static func kernel(name: StringName) -> Object:
	if not enabled or not ClassDB.class_exists(name):
		return null
	return ClassDB.instantiate(name)
