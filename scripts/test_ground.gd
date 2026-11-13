@tool
class_name TestGround
extends RefCounted
## Test ground for driving checks, around the start position (machine at the
## origin, facing -Z). The work area in front and the truck on the right stay flat.
##
## Left (-X): a 35 % ramp up to a plateau, left by a 70 % slope (the published
## gradeability). Behind (+Z): a 25 % side bank to drive along. Front right: a
## rounded mound.

const RAMP_FOOT_X := -10.0
const RAMP_TOP_X := -20.0
const PLATEAU_END_X := -28.0
const PLATEAU_HEIGHT := 3.5
const RAMP_SLOPE := 0.35
const DESCENT_SLOPE := 0.70
const RAMP_HALF_WIDTH := 6.0

const BANK_FOOT_Z := 18.0
const BANK_SLOPE := 0.25
const BANK_HEIGHT := 2.0
const BANK_TOP_END_Z := 30.0
const BANK_X_RANGE := Vector2(-4.0, 22.0)

const MOUND_CENTER := Vector2(16.0, -18.0)
const MOUND_RADIUS := 5.0
const MOUND_HEIGHT := 1.5


static func build(terrain: Terrain) -> void:
	terrain.apply(Rect2(-36.0, -11.0, 27.0, 22.0), ramp_height)
	terrain.apply(Rect2(-8.0, 16.0, 34.0, 18.0), bank_height)
	terrain.apply(Rect2(MOUND_CENTER - Vector2.ONE * MOUND_RADIUS, Vector2.ONE * MOUND_RADIUS * 2.0), mound_height)


## Ramp profile along -X, with 1:1 side slopes beyond the running width.
static func ramp_height(x: float, z: float, current: float) -> float:
	var profile := 0.0
	if x <= RAMP_FOOT_X and x > RAMP_TOP_X:
		profile = (RAMP_FOOT_X - x) * RAMP_SLOPE
	elif x <= RAMP_TOP_X and x > PLATEAU_END_X:
		profile = PLATEAU_HEIGHT
	elif x <= PLATEAU_END_X:
		profile = PLATEAU_HEIGHT - (PLATEAU_END_X - x) * DESCENT_SLOPE
	var side := maxf(absf(z) - RAMP_HALF_WIDTH, 0.0)
	return maxf(current, maxf(profile - side, 0.0))


## Bank rising along +Z, flat top, 1:1 back slope and 1:1 ends.
static func bank_height(x: float, z: float, current: float) -> float:
	var profile := 0.0
	if z > BANK_FOOT_Z:
		profile = minf((z - BANK_FOOT_Z) * BANK_SLOPE, BANK_HEIGHT)
	if z > BANK_TOP_END_Z:
		profile = BANK_HEIGHT - (z - BANK_TOP_END_Z)
	var ends := maxf(BANK_X_RANGE.x - x, 0.0) + maxf(x - BANK_X_RANGE.y, 0.0)
	return maxf(current, maxf(profile - ends, 0.0))


static func mound_height(x: float, z: float, current: float) -> float:
	var r := Vector2(x, z).distance_to(MOUND_CENTER)
	if r >= MOUND_RADIUS:
		return current
	return maxf(current, MOUND_HEIGHT * 0.5 * (1.0 + cos(PI * r / MOUND_RADIUS)))
