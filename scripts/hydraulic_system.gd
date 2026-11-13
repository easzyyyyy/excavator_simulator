@tool
class_name HydraulicSystem
extends RefCounted
## Engine, pumps and the four functions they drive: boom, stick and bucket cylinders and
## the swing motor.
##
## Flow: each function asks for the flow of the speed its spool opening sets, at most the
## rated pump flow (the reference boom raise time needs a little more than the Cat pumps
## give). When the functions together ask for more than the rated flow, each gets the same
## share of what it asks, so three functions at once run clearly slower than one.
##
## Power: the pumps draw at most pump_power_kw. Once pressure times flow reaches it, every
## function slows by the same factor. A function whose load needs more than the relief
## pressure stalls: its flow goes over the relief valve at full pressure, which still
## takes power, and the other functions slow down.
##
## Engine: its speed rises from idle toward working speed while a lever is moved, falls
## back when the levers return, and sags with the power the pumps draw.
##
## A physics step: update_spools(), plan(), then the loads decide stalled and pressure on
## each cylinder, then finish().

var boom := HydraulicCylinder.new()
var stick := HydraulicCylinder.new()
var bucket := HydraulicCylinder.new()
var swing := SwingDrive.new()
## Boom, stick and bucket, in that order.
var cylinders: Array[HydraulicCylinder] = [boom, stick, bucket]

var engine_rpm := 1000.0
## Pump power drawn in the last step (W) and highest function pressure (Pa).
var power := 0.0
var pump_pressure := 0.0
## Share of the flow each function asks for that the pumps give, from the flow limit and
## from the power limit.
var flow_share := 1.0
var power_share := 1.0

var params: MachineParams
var _rated_flow := 0.0
var _max_power := 0.0
var _demand := 0.0
var _base_rpm := 1000.0
var _lug_rpm := 0.0
## Rod speeds (m/s) and swing speed (deg/s) after the flow share.
var _planned := PackedFloat32Array([0.0, 0.0, 0.0])
var _swing_target := 0.0


func setup(p_params: MachineParams) -> void:
	params = p_params
	var p := params
	var relief := p.relief_pressure_mpa * 1.0e6
	boom.setup(func(a: float) -> float: return ArmGeometry.boom_cylinder_length(p, a),
			p.boom_min_deg, p.boom_max_deg, p.boom_cyl_bore, p.boom_cyl_rod, p.boom_cyl_count,
			p.boom_raise_rod_speed, p.boom_lower_rod_speed, p.joint_accel_time, p.joint_decel_time,
			p.cushion_length, p.cushion_speed_factor, relief)
	stick.setup(func(a: float) -> float: return ArmGeometry.stick_cylinder_length(p, a),
			p.stick_min_deg, p.stick_max_deg, p.stick_cyl_bore, p.stick_cyl_rod, 1,
			p.stick_out_rod_speed, p.stick_in_rod_speed, p.joint_accel_time, p.joint_decel_time,
			p.cushion_length, p.cushion_speed_factor, relief)
	bucket.setup(func(a: float) -> float: return ArmGeometry.bucket_linkage(p, a).get("cylinder_length", NAN),
			p.bucket_min_deg, p.bucket_max_deg, p.bucket_cyl_bore, p.bucket_cyl_rod, 1,
			p.bucket_dump_rod_speed, p.bucket_curl_rod_speed, p.joint_accel_time, p.joint_decel_time,
			p.cushion_length, p.cushion_speed_factor, relief)
	swing.setup(p)
	_rated_flow = p.pump_flow_lpm / 60000.0
	_max_power = p.pump_power_kw * 1000.0
	engine_rpm = p.engine_idle_rpm
	_base_rpm = engine_rpm
	_lug_rpm = 0.0


func stop() -> void:
	for cylinder in cylinders:
		cylinder.stop()
	swing.stop()
	_planned = PackedFloat32Array([0.0, 0.0, 0.0])
	_swing_target = 0.0


func update_spools(controls: ControlInput, delta: float) -> void:
	boom.update_spool(controls.boom, delta)
	stick.update_spool(controls.stick, delta)
	bucket.update_spool(controls.bucket, delta)
	swing.update_spool(controls.swing, delta)
	_demand = maxf(maxf(absf(controls.swing), absf(controls.boom)), maxf(absf(controls.stick), absf(controls.bucket)))


## Shares the pump flow between the functions for this step.
func plan() -> void:
	var asked := 0.0
	for i in 3:
		asked += minf(cylinders[i].flow(cylinders[i].free_speed()), _rated_flow)
	asked += minf(swing.flow(swing.free_speed()), _rated_flow)
	flow_share = minf(1.0, _rated_flow / asked) if asked > 0.0 else 1.0
	for i in 3:
		_planned[i] = cylinders[i].free_speed() * flow_share
	_swing_target = swing.free_speed() * flow_share


## Rod speed a cylinder would move at this step without load (m/s).
func planned_speed(index: int) -> float:
	return _planned[index]


func swing_target() -> float:
	return _swing_target


## Applies the power limit and moves every function. The loads must have set pressure and
## stalled on each cylinder; swing_inertia and swing_resistance come from the arm pose and
## the soil.
func finish(swing_inertia: float, swing_resistance: float, delta: float) -> void:
	power = 0.0
	pump_pressure = 0.0
	var flows := PackedFloat32Array([0.0, 0.0, 0.0])
	for i in 3:
		var cylinder := cylinders[i]
		flows[i] = minf(cylinder.flow(_planned[i]), _rated_flow * flow_share)
		var working_pressure := cylinder.relief_pressure if cylinder.stalled else cylinder.pressure
		if not is_zero_approx(_planned[i]):
			power += working_pressure * flows[i]
			pump_pressure = maxf(pump_pressure, working_pressure)
	var swing_flow := minf(swing.flow(_swing_target), _rated_flow * flow_share)
	power += swing.pressure() * swing_flow
	power_share = minf(1.0, _max_power / power) if power > 0.0 else 1.0
	power = minf(power, _max_power)

	for i in 3:
		var cylinder := cylinders[i]
		cylinder.advance(0.0 if cylinder.stalled else _planned[i] * power_share * cylinder.speed_share, delta)
	swing.advance(_swing_target * power_share, swing_inertia, swing_resistance, delta)
	_update_engine(delta)


## True when a function is held by its relief valve: stalled under load or driven into its
## end stop.
func relief_open(controls: ControlInput) -> bool:
	var commands := [controls.boom, controls.stick, controls.bucket]
	for i in 3:
		if cylinders[i].relieving(commands[i]):
			return true
	return swing.stalled


## Share of the pump power drawn, for the engine and the sound.
func load_fraction() -> float:
	return power / _max_power if _max_power > 0.0 else 0.0


## 0 at idle, 1 at working speed.
func revs_fraction() -> float:
	return clampf((engine_rpm - params.engine_idle_rpm) / (params.engine_working_rpm - params.engine_idle_rpm), 0.0, 1.0)


func _update_engine(delta: float) -> void:
	var p := params
	var target := lerpf(p.engine_idle_rpm, p.engine_working_rpm, _demand)
	var time := p.engine_rev_up_time if target > _base_rpm else p.engine_rev_down_time
	_base_rpm = move_toward(_base_rpm, target, (p.engine_working_rpm - p.engine_idle_rpm) * delta / maxf(time, 0.001))
	_lug_rpm = lerpf(_lug_rpm, p.engine_lug_rpm * load_fraction(), 1.0 - exp(-delta / maxf(p.engine_lug_time, 0.001)))
	engine_rpm = _base_rpm - _lug_rpm
