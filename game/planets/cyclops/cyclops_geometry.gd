extends RefCounted

# Every Cyclops storm dimension derives from the sea radius, so resizing the planet or moving its
# ocean level rescales the cloud deck, the tornadoes and the streaming radii together.
# Altitude of the deck centre above the sea, and the deck thickness, both over the sea radius.
const DECK_ALTITUDE_RATIO := 0.28
const DECK_THICKNESS_RATIO := 0.04
# Streaming radii, measured outwards from the deck centre, as multiples of the sea radius.
const FULL_VISIBILITY_RATIO := 1.09
const PRELOAD_RATIO := 1.94
const FADE_RATIO := 1.94
const UNLOAD_RATIO := 2.18
# How far below the sea a tornado still grabs the player, as a fraction of the deck gap.
const ACTIVE_BAND_RATIO := 0.043
# Storm placement margin, as a fraction of the sea radius.
const SEPARATION_MARGIN_RATIO := 0.036
# Funnel height as a fraction of the deck gap: strictly under 1 so no crown ever pierces the deck
# mesh, and high enough that every crown reaches into the deck and is hidden from outside.
const FUNNEL_HEIGHT_RANGE := Vector2(0.93, 0.99)
# Funnel radii as fractions of its own height, so shortening the deck also slims the tornadoes.
const CROWN_RADIUS_RANGE := Vector2(0.66, 0.82)
const TRUNK_RADIUS_RANGE := Vector2(0.267, 0.329)
const BASE_RADIUS_RANGE := Vector2(0.137, 0.188)
const CONTACT_RADIUS_RATIO := 0.78


# Vertical room between the sea and the cloud deck: the tornadoes span exactly this.
static func deck_gap(sea_radius: float) -> float:
	return sea_radius * DECK_ALTITUDE_RATIO


static func deck_center(sea_radius: float) -> float:
	return sea_radius + deck_gap(sea_radius)


static func deck_thickness(sea_radius: float) -> float:
	return sea_radius * DECK_THICKNESS_RATIO


static func deck_inner_radius(sea_radius: float) -> float:
	return deck_center(sea_radius) - deck_thickness(sea_radius) * 0.5


static func deck_outer_radius(sea_radius: float) -> float:
	return deck_center(sea_radius) + deck_thickness(sea_radius) * 0.5


# Peaks at 1.0 on the deck mesh itself, so the screen tint is fully opaque exactly where the shell
# flips from exterior cloud ball to interior ceiling, and clears at both deck faces.
static func cloud_transition(sea_radius: float, camera_radius: float) -> float:
	var half_thickness := deck_thickness(sea_radius) * 0.5
	var depth_into_deck := absf(camera_radius - deck_center(sea_radius))
	return 1.0 - clampf(depth_into_deck / maxf(half_thickness, 0.001), 0.0, 1.0)


static func sky_occlusion(sea_radius: float, camera_radius: float) -> float:
	return 1.0 - smoothstep(deck_center(sea_radius), deck_outer_radius(sea_radius), camera_radius)


# Tornadoes reach full opacity where the deck tint has finished clearing.
static func interior_visibility(sea_radius: float, camera_radius: float) -> float:
	return 1.0 - smoothstep(deck_inner_radius(sea_radius), deck_center(sea_radius), camera_radius)


static func streaming_radius(sea_radius: float, ratio: float) -> float:
	return deck_center(sea_radius) + sea_radius * ratio


static func funnel_height(sea_radius: float, height_roll: float) -> float:
	return deck_gap(sea_radius) * lerpf(FUNNEL_HEIGHT_RANGE.x, FUNNEL_HEIGHT_RANGE.y, height_roll)
