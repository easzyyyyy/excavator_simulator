class_name SiteLighting
extends Node
## Daylight on the site from the time of day. The sun position comes from the site latitude
## and the date; the sun colour and strength, the sky and the ambient light follow the sun
## height, from dawn to dusk.
##
## The hour is clock time, summer time in France: the sun follows solar time, clock_offset
## earlier. The site faces north along -Z, east is +X.

const HIGH_LIGHT := Color(1.0, 0.96, 0.9)
const LOW_LIGHT := Color(1.0, 0.58, 0.32)
const DAY_SKY_TOP := Color(0.32, 0.5, 0.78)
const DAY_HORIZON := Color(0.72, 0.78, 0.84)
const DUSK_SKY_TOP := Color(0.14, 0.18, 0.34)
const DUSK_HORIZON := Color(0.86, 0.56, 0.4)

@export var sun_path: NodePath
@export var environment_path: NodePath
## Middle of France.
@export var latitude_deg := 46.0
## 11 September.
@export var day_of_year := 254
## Clock time minus solar time (h): UTC+2 in summer, less 8 min for a site 2 deg east.
@export var clock_offset := 1.87
@export var hour := 12.0
## Hour change per key press (h).
@export var step := 0.5
## Sun strength with the sun high.
@export var sun_energy := 1.2
## Time kept before sunrise and after sunset (h).
@export var twilight := 0.5

var _sun: DirectionalLight3D
var _environment: Environment


func _ready() -> void:
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	var world := get_node_or_null(environment_path) as WorldEnvironment
	_environment = world.environment if world != null else null
	apply()


## Moves the time of day by a number of steps, within dawn and dusk.
func change_hour(steps: int) -> void:
	hour = clampf(hour + steps * step, sunrise() - twilight, sunset() + twilight)
	apply()


## Sun declination for the date (deg), Cooper's approximation.
func declination_deg() -> float:
	return -23.44 * cos(deg_to_rad(360.0 / 365.0 * (day_of_year + 10)))


## Sun height above the horizon at a clock hour (deg).
func sun_elevation_deg(clock_hour: float) -> float:
	return rad_to_deg(asin(clampf(sun_direction(clock_hour).y, -1.0, 1.0)))


## World direction toward the sun at a clock hour.
func sun_direction(clock_hour: float) -> Vector3:
	var latitude := deg_to_rad(latitude_deg)
	var declination := deg_to_rad(declination_deg())
	var hour_angle := deg_to_rad(15.0 * (clock_hour - clock_offset - 12.0))
	# East, north and up components of the direction toward the sun.
	var east := -cos(declination) * sin(hour_angle)
	var north := sin(declination) * cos(latitude) - cos(declination) * cos(hour_angle) * sin(latitude)
	var up := sin(declination) * sin(latitude) + cos(declination) * cos(hour_angle) * cos(latitude)
	return Vector3(east, up, -north).normalized()


func sunrise() -> float:
	return 12.0 + clock_offset - _half_day_hours()


func sunset() -> float:
	return 12.0 + clock_offset + _half_day_hours()


func label() -> String:
	var minutes := roundi(hour * 60.0)
	return "%d h %02d" % [minutes / 60, minutes % 60]


func apply() -> void:
	var toward := sun_direction(hour)
	var elevation := rad_to_deg(asin(clampf(toward.y, -1.0, 1.0)))
	var high := smoothstep(0.0, 25.0, elevation)
	var dusk := 1.0 - smoothstep(-4.0, 15.0, elevation)
	if _sun != null:
		# The light shines along its -Z axis, away from the sun.
		_sun.global_basis = Basis.looking_at(-toward, Vector3.UP if absf(toward.y) < 0.999 else Vector3.BACK)
		_sun.light_color = LOW_LIGHT.lerp(HIGH_LIGHT, high)
		_sun.light_energy = sun_energy * smoothstep(-3.0, 8.0, elevation)
		_sun.shadow_enabled = elevation > -3.0
	if _environment == null:
		return
	var horizon := DAY_HORIZON.lerp(DUSK_HORIZON, dusk)
	var sky := _environment.sky.sky_material as ProceduralSkyMaterial if _environment.sky != null else null
	if sky != null:
		sky.sky_top_color = DAY_SKY_TOP.lerp(DUSK_SKY_TOP, dusk)
		sky.sky_horizon_color = horizon
		sky.ground_horizon_color = horizon
		sky.sky_energy_multiplier = lerpf(0.3, 1.0, smoothstep(-6.0, 12.0, elevation))
	_environment.fog_light_color = horizon


## Half the time the sun spends above the horizon (h).
func _half_day_hours() -> float:
	var cos_hour_angle := -tan(deg_to_rad(latitude_deg)) * tan(deg_to_rad(declination_deg()))
	return rad_to_deg(acos(clampf(cos_hour_angle, -1.0, 1.0))) / 15.0
