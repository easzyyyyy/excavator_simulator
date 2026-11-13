@tool
class_name HydraulicCylinder
extends RefCounted
## One arm function driven by a double-acting cylinder.
##
## The cylinder length is the state and the joint angle follows from the linkage
## geometry, so a constant rod speed turns the joint faster where the cylinder has a
## short lever. The operator command opens the spool, which ramps and passes through
## neutral before reversing. The rod moves at the speed the spool opening sets, reduced
## by the pump flow share, slowed in the end-of-stroke cushion, and stopped when the
## load needs more than the relief pressure.
##
## Commands and speeds are positive toward positive joint angles (boom up, stick out,
## bucket dump), whichever way the cylinder moves. Forces are positive when the cylinder
## pushes (extends).

const TABLE_STEP_DEG := 0.25

var angle_deg := 0.0
var length := 0.0
## Joint speed from the last step.
var speed_deg_s := 0.0
## Rod speed along the joint direction (m/s) from the last step.
var rod_speed := 0.0
## Spool opening in [-1, 1].
var spool := 0.0
## Pressure on the side the pump feeds for the current motion or held load (Pa).
var pressure := 0.0
## The load needs more than the relief pressure: the relief valve passes the flow.
var stalled := false
## Share of the planned speed the rod keeps while it pushes the machine up through the
## ground harder than it can: the relief valve passes the rest of the flow.
var speed_share := 1.0

var min_deg := 0.0
var max_deg := 0.0
## Full-spool rod speeds toward positive and negative angles (m/s).
var positive_speed := 0.0
var negative_speed := 0.0
var cap_area := 0.0
var rod_area := 0.0
var relief_pressure := 35.0e6
## Spool travel rates, full opening per second.
var spool_accel_rate := 1.0
var spool_decel_rate := 1.0
## Stroke distance over which the cushion slows the rod, and the speed left at the end.
var cushion_length := 0.0
var cushion_factor := 1.0

var _angles := PackedFloat32Array()
var _lengths := PackedFloat32Array()
## +1 when the cylinder extends toward positive angles, -1 when it retracts.
var _extension_sign := 1.0


## length_at(angle_deg) gives the pin-to-pin length; it must be monotonic over the range.
## Several cylinders side by side act as one with their areas added.
func setup(length_at: Callable, p_min_deg: float, p_max_deg: float, bore: float, rod: float, count: int,
		p_positive_speed: float, p_negative_speed: float, accel_time: float, decel_time: float,
		p_cushion_length: float, p_cushion_factor: float, p_relief_pressure: float) -> void:
	min_deg = p_min_deg
	max_deg = p_max_deg
	positive_speed = p_positive_speed
	negative_speed = p_negative_speed
	cap_area = PI * bore * bore * 0.25 * count
	rod_area = cap_area - PI * rod * rod * 0.25 * count
	spool_accel_rate = 1.0 / maxf(accel_time, 0.001)
	spool_decel_rate = 1.0 / maxf(decel_time, 0.001)
	cushion_length = p_cushion_length
	cushion_factor = p_cushion_factor
	relief_pressure = p_relief_pressure
	_angles.clear()
	_lengths.clear()
	var steps := ceili((max_deg - min_deg) / TABLE_STEP_DEG)
	for i in steps + 1:
		var angle := lerpf(min_deg, max_deg, float(i) / steps)
		_angles.append(angle)
		_lengths.append(length_at.call(angle))
	_extension_sign = 1.0 if _lengths[steps] > _lengths[0] else -1.0
	set_angle(clampf(angle_deg, min_deg, max_deg))


func set_angle(p_angle_deg: float) -> void:
	angle_deg = clampf(p_angle_deg, min_deg, max_deg)
	length = length_at_angle(angle_deg)
	speed_deg_s = 0.0
	rod_speed = 0.0


func stop() -> void:
	spool = 0.0
	speed_deg_s = 0.0
	rod_speed = 0.0
	stalled = false
	speed_share = 1.0


func shortest() -> float:
	return minf(_lengths[0], _lengths[_lengths.size() - 1])


func longest() -> float:
	return maxf(_lengths[0], _lengths[_lengths.size() - 1])


func length_at_angle(p_angle_deg: float) -> float:
	var position := clampf((p_angle_deg - min_deg) / (max_deg - min_deg), 0.0, 1.0) * (_angles.size() - 1)
	var i := mini(int(position), _angles.size() - 2)
	return lerpf(_lengths[i], _lengths[i + 1], position - i)


func angle_at_length(p_length: float) -> float:
	var low := 0
	var high := _lengths.size() - 1
	# Search on the table ordered by increasing length.
	var increasing := _extension_sign > 0.0
	if (p_length <= _lengths[low]) == increasing:
		return _angles[low]
	if (p_length >= _lengths[high]) == increasing:
		return _angles[high]
	while high - low > 1:
		var middle := (low + high) / 2
		if (_lengths[middle] < p_length) == increasing:
			low = middle
		else:
			high = middle
	var span := _lengths[high] - _lengths[low]
	var t := (p_length - _lengths[low]) / span if absf(span) > 1e-9 else 0.0
	return lerpf(_angles[low], _angles[high], t)


## Length change per radian of joint rotation at an angle (m/rad), signed.
func lever(p_angle_deg: float) -> float:
	var h := TABLE_STEP_DEG
	var a := clampf(p_angle_deg - h, min_deg, max_deg)
	var b := clampf(p_angle_deg + h, min_deg, max_deg)
	return (length_at_angle(b) - length_at_angle(a)) / deg_to_rad(b - a)


## Moves the spool toward the command, braking to neutral before any reversal.
func update_spool(command: float, delta: float) -> void:
	command = clampf(command, -1.0, 1.0)
	if not is_zero_approx(spool) and signf(command) != signf(spool):
		spool = move_toward(spool, 0.0, spool_decel_rate * delta)
	else:
		var rate := spool_accel_rate if absf(command) > absf(spool) else spool_decel_rate
		spool = move_toward(spool, command, rate * delta)


## Rod speed the spool asks for, along the joint direction, cushioned near the stroke end.
func free_speed() -> float:
	if is_zero_approx(spool):
		return 0.0
	var full := positive_speed if spool > 0.0 else negative_speed
	var speed := spool * full
	if cushion_length > 0.0:
		var goal := max_deg if spool > 0.0 else min_deg
		var distance := absf(length_at_angle(goal) - length)
		speed *= lerpf(cushion_factor, 1.0, clampf(distance / cushion_length, 0.0, 1.0))
	if (spool > 0.0 and angle_deg >= max_deg) or (spool < 0.0 and angle_deg <= min_deg):
		return 0.0
	return speed


## Area the pump feeds to move toward positive (direction > 0) or negative angles.
func inflow_area(direction: float) -> float:
	return cap_area if direction * _extension_sign > 0.0 else rod_area


## Flow a rod speed along the joint direction takes (m3/s).
func flow(speed: float) -> float:
	return absf(speed) * inflow_area(speed)


## Cylinder force (N, positive pushing) that balances an external torque about the joint
## (N m, positive toward positive angles).
func holding_force(external_torque: float) -> float:
	var arm := lever(angle_deg)
	return -external_torque / arm if absf(arm) > 1e-6 else 0.0


## Pressure the pump must supply to move toward a direction against an external torque:
## zero when the load itself drives the motion.
func pressure_to_move(external_torque: float, direction: float) -> float:
	var force := holding_force(external_torque)
	var along := force * direction * _extension_sign
	return maxf(along, 0.0) / inflow_area(direction)


## Share of an extra torque the cylinder can push against on top of a base torque, moving
## toward a direction, before the relief valve opens: 1 or more when it pushes through all
## of it, INF when the extra torque does not resist the motion.
func push_share(base_torque: float, extra_torque: float, direction: float) -> float:
	var sense := direction * _extension_sign
	var extra := holding_force(extra_torque) * sense
	if extra <= 0.0:
		return INF
	return maxf(relief_pressure * inflow_area(direction) - holding_force(base_torque) * sense, 0.0) / extra


## The relief valve passes flow for this command: the rod pushes its end stop, or a load
## stalls or slows it.
func relieving(command: float) -> bool:
	return pushing_limit(command) or ((stalled or speed_share < 1.0) and not is_zero_approx(command))


## Pressure holding an external torque with the spool closed (Pa).
func holding_pressure(external_torque: float) -> float:
	var force := holding_force(external_torque)
	return absf(force) / (cap_area if force > 0.0 else rod_area)


## Largest torque the cylinder applies about the joint toward a direction (N m).
func max_torque(direction: float) -> float:
	return relief_pressure * inflow_area(direction) * absf(lever(angle_deg))


## Moves the rod at a speed along the joint direction, stopping at the stroke ends.
func advance(speed: float, delta: float) -> void:
	var before := angle_deg
	length = clampf(length + speed * _extension_sign * delta, shortest(), longest())
	angle_deg = angle_at_length(length)
	if angle_deg >= max_deg or angle_deg <= min_deg:
		length = length_at_angle(angle_deg)
	speed_deg_s = (angle_deg - before) / delta if delta > 0.0 else 0.0
	rod_speed = speed if not is_equal_approx(angle_deg, before) else 0.0


func at_limit() -> bool:
	return is_equal_approx(angle_deg, max_deg) or is_equal_approx(angle_deg, min_deg)


## True when the command drives the joint into the end stop it rests against: the
## cylinder is bottomed out and the relief valve opens.
func pushing_limit(command: float) -> bool:
	if is_zero_approx(command):
		return false
	return angle_deg >= max_deg - 1e-4 if command > 0.0 else angle_deg <= min_deg + 1e-4


## Rod speed as a fraction of the full speed in the direction of motion.
func speed_fraction() -> float:
	var full := positive_speed if rod_speed >= 0.0 else negative_speed
	return absf(rod_speed) / full if full > 0.0 else 0.0
