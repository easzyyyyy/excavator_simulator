@tool
class_name SwingDrive
extends RefCounted
## Swing motor turning the upper structure and the arm.
##
## The spool sets the speed the motor aims for. The motor torque, capped at the swing
## relief pressure, accelerates and brakes the rotating mass, whose inertia grows with the
## reach and the bucket load: the turret gathers speed slowly, and once the lever is
## released it coasts on while the crossover reliefs brake it. Soil against the bucket
## slows the swing and stops it when it takes the whole motor torque.
##
## Positive angles and speeds turn right.

var angle_deg := 0.0
var speed_deg_s := 0.0
## Spool opening in [-1, 1].
var spool := 0.0
## Motor torque used in the last step over the relief torque.
var torque_fraction := 0.0
## The lever asks for motion that the soil holds back.
var stalled := false

var max_speed_deg_s := 67.5
## Motor torque at the swing relief pressure (N m).
var max_torque := 82000.0
var relief_pressure := 27.5e6
## Motor flow at full speed (m3/s): the displacement that gives the relief torque at the
## relief pressure, turning at full speed.
var full_flow := 0.0
var spool_accel_rate := 1.0
var spool_decel_rate := 1.0


func setup(params: MachineParams) -> void:
	max_speed_deg_s = params.swing_speed_deg_s()
	max_torque = params.swing_torque_knm * 1000.0
	relief_pressure = params.swing_relief_pressure_mpa * 1.0e6
	full_flow = max_torque / relief_pressure * deg_to_rad(max_speed_deg_s)
	spool_accel_rate = 1.0 / maxf(params.joint_accel_time, 0.001)
	spool_decel_rate = 1.0 / maxf(params.joint_decel_time, 0.001)


func stop() -> void:
	spool = 0.0
	speed_deg_s = 0.0
	torque_fraction = 0.0
	stalled = false


func update_spool(command: float, delta: float) -> void:
	command = clampf(command, -1.0, 1.0)
	if not is_zero_approx(spool) and signf(command) != signf(spool):
		spool = move_toward(spool, 0.0, spool_decel_rate * delta)
	else:
		var rate := spool_accel_rate if absf(command) > absf(spool) else spool_decel_rate
		spool = move_toward(spool, command, rate * delta)


## Speed the spool asks for (deg/s).
func free_speed() -> float:
	return spool * max_speed_deg_s


## Flow the motor takes to turn at a speed (m3/s).
func flow(speed: float) -> float:
	return absf(speed) / max_speed_deg_s * full_flow


## One step toward a target speed with this inertia (kg m2) against a soil torque (N m,
## not negative) that opposes the motion.
func advance(target_deg_s: float, inertia: float, resisting_torque: float, delta: float) -> void:
	inertia = maxf(inertia, 1.0)
	var motor_rate := rad_to_deg(max_torque / inertia) * delta
	var speed := move_toward(speed_deg_s, target_deg_s, motor_rate)
	var used := absf(speed - speed_deg_s) / motor_rate if motor_rate > 0.0 else 0.0
	if resisting_torque > 0.0:
		# The soil only slows the motion down, it never drives the turret back.
		speed = move_toward(speed, 0.0, rad_to_deg(resisting_torque / inertia) * delta)
		used = minf(used + resisting_torque / max_torque, 1.0)
	stalled = not is_zero_approx(target_deg_s) and resisting_torque >= max_torque and absf(speed) < 1e-3
	torque_fraction = 1.0 if stalled else used
	speed_deg_s = speed
	angle_deg += speed * delta


## Motor pressure from the last step (Pa).
func pressure() -> float:
	return torque_fraction * relief_pressure


func speed_fraction() -> float:
	return absf(speed_deg_s) / max_speed_deg_s
