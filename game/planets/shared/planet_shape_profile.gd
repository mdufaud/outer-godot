class_name PlanetShapeProfile
extends RefCounted

const EARTH := 0
const MOON := 1
const ALIEN := 2
const SHATTERED := 3
const MOAT := 4
const ASTEROID := 5
const GLACIER := 6
const MIRAGE := 7
const FIERY_TWIN := 8
const ICEY_TWIN := 9
const CYCLOPS := 10
const TUMBLING_BEAN := 11
const WATCHFUL_EYE := 12


static func height_kind(profile_id: int) -> int:
	match profile_id:

		MOON, TUMBLING_BEAN, WATCHFUL_EYE:
			return MOON
		ALIEN, CYCLOPS:
			return ALIEN
		MIRAGE:
			return MIRAGE
		SHATTERED, ICEY_TWIN:
			return SHATTERED
		MOAT, FIERY_TWIN:
			return MOAT
		ASTEROID:
			return ASTEROID
		GLACIER:
			return GLACIER
		_:
			return EARTH
