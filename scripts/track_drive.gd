@tool
class_name TrackDrive
extends RefCounted
## Two independent hydraulic track drives with skid steering.
##
## Each track speed ramps toward its lever command and brakes to zero before
## reversing. The machine moves at the mean track speed and turns at the speed
## difference over an effective gauge, wider than the real one because the tracks
## slip sideways while steering.

## Two-speed travel switch: false is the low range.
var high_speed := false
## Track speeds along the ground in m/s, positive toward the idlers (machine front).
var left_speed := 0.0
var right_speed := 0.0
## Distance run by each track, used to animate the shoes.
var left_distance := 0.0
var right_distance := 0.0

var _low_speed := 0.0
var _high_speed := 0.0
var _accel := 0.0
var _decel := 0.0
var _effective_gauge := 1.0
var _gradeability := 0.0
var _slip_range := 1.0


func setup(params: MachineParams) -> void:
	_low_speed = params.travel_speed_low_kmh / 3.6
	_high_speed = params.travel_speed_high_kmh / 3.6
	_accel = _high_speed / maxf(params.travel_accel_time, 0.001)
	_decel = _high_speed / maxf(params.travel_decel_time, 0.001)
	_effective_gauge = params.track_gauge * params.skid_steer_factor
	_gradeability = params.gradeability_deg
	_slip_range = maxf(params.slip_range_deg, 0.001)


func stop() -> void:
	left_speed = 0.0
	right_speed = 0.0


func max_speed() -> float:
	return _high_speed if high_speed else _low_speed


func step(left_command: float, right_command: float, delta: float) -> void:
	left_speed = _ramp(left_speed, clampf(left_command, -1.0, 1.0) * max_speed(), delta)
	right_speed = _ramp(right_speed, clampf(right_command, -1.0, 1.0) * max_speed(), delta)
	left_distance += left_speed * delta
	right_distance += right_speed * delta


## Speed of the machine centre along the ground, positive forward.
func forward_speed() -> float:
	return (left_speed + right_speed) * 0.5


## Turn rate about +Y in rad/s. A faster left track turns right, which is negative.
func yaw_rate() -> float:
	return (right_speed - left_speed) / _effective_gauge


## Share of the track motion that moves the machine: full up to the gradeability,
## fading to zero over the slip range. Only uphill motion slips.
func traction(forward_slope: float) -> float:
	var uphill := forward_slope * forward_speed()
	if uphill <= 0.0:
		return 1.0
	var slope_deg := rad_to_deg(atan(absf(forward_slope)))
	return clampf(1.0 - (slope_deg - _gradeability) / _slip_range, 0.0, 1.0)


func _ramp(speed: float, target: float, delta: float) -> float:
	if not is_zero_approx(speed) and signf(target) != signf(speed):
		return move_toward(speed, 0.0, _decel * delta)
	var rate := _accel if absf(target) > absf(speed) else _decel
	return move_toward(speed, target, rate * delta)
