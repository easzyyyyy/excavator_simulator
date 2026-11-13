@tool
class_name Excavator
extends Node3D
## Machine root. Reads the operator controls, drives the swing, the three arm
## functions and the two tracks through the hydraulic system, rests the machine on the
## terrain, and poses the node hierarchy: Undercarriage > Turret > (Cab, Head, Boom >
## Stick > Bucket). The bucket digs, carries and drops the terrain soil, drawn falling with
## the dust it raises.
##
## Every step the arm loads decide what the planned motion does: gravity and the soil
## against the bucket load each cylinder, a cylinder whose load needs more than the relief
## pressure stalls, and when the ground holds the bucket more firmly than the machine
## weighs on one edge of its tracks, the machine turns up about that edge instead of the
## bucket sinking in, as fast as the moment left over from its weight can swing it.
##
## The root transform is the machine on the ground: origin on the track bottom
## plane under the swing axis. Its initial transform in the scene is the start place.

const SPEED_SMOOTHING_TIME := 0.25
const DEFAULT_SOIL := preload("res://data/common_earth.tres")
## Passes over the loads when a stalled cylinder changes the motion.
const LOAD_PASSES := 3
## Bucket drop used to test whether the ground holds a lifted machine up (m).
const TIP_PROBE := 0.002
## Time over which the soil resistance against a cylinder may ease off while the bucket
## stays in the ground.
const SOIL_HOLD_TIME := 0.15

@export var params: MachineParams:
	set(value):
		params = value
		if is_node_ready():
			_rebuild()

## Ground to drive on. Without one the machine stands on a flat plane at y = 0.
@export var terrain_path: NodePath

## Draws the prepared 3D model instead of the placeholder primitives.
@export var use_model := false:
	set(value):
		use_model = value
		if is_node_ready():
			_rebuild()

@onready var undercarriage: Node3D = $Undercarriage
@onready var turret: Node3D = $Undercarriage/Turret
@onready var cab: Node3D = $Undercarriage/Turret/Cab
@onready var head: Node3D = $Undercarriage/Turret/Head
@onready var boom: Node3D = $Undercarriage/Turret/Boom
@onready var stick: Node3D = $Undercarriage/Turret/Boom/Stick
@onready var bucket: Node3D = $Undercarriage/Turret/Boom/Stick/Bucket

var controls := ControlInput.new()
var hydraulics := HydraulicSystem.new()
var statics := ArmStatics.new()
var swing_joint: SwingDrive = hydraulics.swing
var boom_joint: HydraulicCylinder = hydraulics.boom
var stick_joint: HydraulicCylinder = hydraulics.stick
var bucket_joint: HydraulicCylinder = hydraulics.bucket
var travel := TrackDrive.new()
var ground := GroundSupport.new()
var bucket_soil := BucketSoil.new()
var terrain: Terrain
## Ground speed measured from the body motion, smoothed, in m/s.
var measured_speed := 0.0

var _visual: ExcavatorPrimitives = ExcavatorPrimitives.new()
var _load_visual: BucketLoadVisual
var _fall_visual: SoilFallVisual
var _start_position := Vector3.ZERO
var _start_heading := 0.0
## Soil torque last resisting each moving cylinder (N m) and the direction it moved.
var _soil_hold := Vector3.ZERO
var _soil_hold_direction := Vector3.ZERO


func _ready() -> void:
	_start_position = position
	_start_heading = rotation.y
	if not terrain_path.is_empty():
		terrain = get_node_or_null(terrain_path) as Terrain
	_rebuild()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or params == null:
		return
	controls.poll()
	hydraulics.update_spools(controls, delta)
	hydraulics.plan()
	var swing_resistance := _resolve_loads(delta)
	hydraulics.finish(statics.swing_inertia(_frames(), load_mass()), swing_resistance, delta)
	travel.step(controls.left_track, controls.right_track, delta)
	_drive(delta)
	_apply_pose()
	bucket_soil.step(terrain, bucket.global_transform, delta)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _load_visual == null:
		return
	_load_visual.refresh(bucket_soil)
	_fall_visual.update(bucket_soil, terrain)


## Bucket tooth tip in the turret side plane (u forward from the swing axis, v height).
func tip_point() -> Vector2:
	return ArmGeometry.arm_points(params, boom_joint.angle_deg, stick_joint.angle_deg, bucket_joint.angle_deg)["tip"]


func reset_pose() -> void:
	hydraulics.stop()
	_soil_hold = Vector3.ZERO
	swing_joint.angle_deg = 0.0
	boom_joint.set_angle(params.rest_boom_deg)
	stick_joint.set_angle(params.rest_stick_deg)
	bucket_joint.set_angle(params.rest_bucket_deg)
	ground.clear_tip()
	transform = ground.body_transform()
	_apply_pose()
	bucket_soil.reset_motion()


## Puts the machine at rest on the ground at a horizontal position and heading.
func place(ground_position: Vector2, heading_rad: float) -> void:
	travel.stop()
	ground.place(terrain, ground_position, heading_rad, center_of_mass())
	measured_speed = 0.0
	transform = ground.body_transform()
	bucket_soil.reset_motion()


func return_to_start() -> void:
	place(Vector2(_start_position.x, _start_position.z), _start_heading)


## Centre of mass in undercarriage space, with the arm pose and the bucket load.
func center_of_mass() -> Vector3:
	return statics.center_of_mass(_frames(), load_mass())


## Mass of the soil in the bucket (kg).
func load_mass() -> float:
	return bucket_soil.load_mass() if bucket_soil.soil != null else 0.0


func set_pose(swing_deg: float, boom_deg: float, stick_deg: float, bucket_deg: float) -> void:
	hydraulics.stop()
	_soil_hold = Vector3.ZERO
	swing_joint.angle_deg = swing_deg
	boom_joint.set_angle(boom_deg)
	stick_joint.set_angle(stick_deg)
	bucket_joint.set_angle(bucket_deg)
	_apply_pose()
	bucket_soil.reset_motion()


## Poses the arm directly, as a scripted sequence does, and lets the bucket act on the
## ground as during one physics step.
func pose_and_dig(swing_deg: float, boom_deg: float, stick_deg: float, bucket_deg: float, delta: float) -> void:
	swing_joint.angle_deg = swing_deg
	boom_joint.set_angle(boom_deg)
	stick_joint.set_angle(stick_deg)
	bucket_joint.set_angle(bucket_deg)
	_apply_pose()
	bucket_soil.step(terrain, bucket.global_transform, delta)


func _rebuild() -> void:
	if params == null:
		return
	hydraulics.setup(params)
	statics.setup(params)
	travel.setup(params)
	ground.setup(params)
	bucket_soil.setup(params, terrain.soil if terrain != null else DEFAULT_SOIL)
	boom.position = params.boom_foot
	stick.position = Vector3(0, 0, -params.boom_length)
	bucket.position = Vector3(0, 0, -params.stick_length)
	head.position = params.eye_position
	ExcavatorModel.clear([undercarriage, turret, cab, boom, stick, bucket])
	if use_model:
		_visual = ExcavatorModel.new()
	else:
		_visual = ExcavatorPrimitives.new()
	_visual.build(params, undercarriage, turret, cab, boom, stick, bucket)
	var old_load := bucket.get_node_or_null("SoilLoad")
	if old_load:
		bucket.remove_child(old_load)
		old_load.free()
	_load_visual = BucketLoadVisual.new()
	bucket.add_child(_load_visual)
	if _fall_visual == null:
		_fall_visual = SoilFallVisual.new()
		add_child(_fall_visual)
	reset_pose()
	# In the editor the node keeps its scene transform.
	if not Engine.is_editor_hint():
		return_to_start()


func _frames() -> Array[Transform3D]:
	return statics.joint_frames(swing_joint.angle_deg, boom_joint.angle_deg, stick_joint.angle_deg, bucket_joint.angle_deg)


## Loads on the arm for this step: gravity, and the soil against the bucket when the
## planned motion meets it. Decides which cylinders stall and how far the machine is lifted
## about a track edge. Returns the soil torque resisting the swing (N m).
func _resolve_loads(delta: float) -> float:
	var cylinders := hydraulics.cylinders
	var mass := load_mass()
	var angles := Vector3(boom_joint.angle_deg, stick_joint.angle_deg, bucket_joint.angle_deg)
	var frames := _frames()
	var body := ground.body_transform()
	var gravity := statics.gravity_torques(frames, mass, body.basis.inverse() * Vector3.DOWN * ArmStatics.GRAVITY)
	var from := body * frames[3]
	# A lifted machine is tested falling by its next fall step, at least a small probe.
	var probe := 0.0
	var fall_rate := 0.0
	if ground.tip_angle > 0.0:
		fall_rate = _tip_fall_rate(ground.tip_edge, frames, mass)
		var pivot := body * ground.tip_pivot(ground.tip_edge)
		var rise := (body.basis * ground.tip_axis(ground.tip_edge)).cross(from.origin - pivot).y
		var fall := (-minf(ground.tip_speed, 0.0) + fall_rate * delta) * delta
		probe = maxf(TIP_PROBE / maxf(rise, 0.5), fall)
	var stalled: Array[bool] = [false, false, false]
	# The swing is tested where the motor would take it this step, so that a turret at rest
	# pushed against the truck is held there rather than creeping in a step at a time.
	var swing_rate := rad_to_deg(swing_joint.max_torque / maxf(statics.swing_inertia(frames, mass), 1.0)) * delta
	var swing_speed := move_toward(swing_joint.speed_deg_s, hydraulics.swing_target(), swing_rate)
	var raw_torques := Vector3.ZERO
	var soil_torques := Vector3.ZERO
	var swing_torque := 0.0
	var raw_swing_torque := 0.0
	var soil := {}
	var support := {}
	for pass_index in LOAD_PASSES:
		var next := angles
		for i in 3:
			var arm := absf(cylinders[i].lever(angles[i]))
			if not stalled[i] and arm > 1e-6:
				next[i] += rad_to_deg(hydraulics.planned_speed(i) / arm) * delta
		var next_swing := swing_joint.angle_deg + swing_speed * delta
		var next_body := ground.rest_transform() * ground.tip_transform(ground.tip_edge, maxf(ground.tip_angle - probe, 0.0))
		var next_frames := statics.joint_frames(next_swing, next.x, next.y, next.z)
		soil = bucket_soil.resistance(terrain, from, next_body * next_frames[3])
		raw_torques = Vector3.ZERO
		soil_torques = Vector3.ZERO
		swing_torque = 0.0
		raw_swing_torque = 0.0
		support = {}
		if soil["contact"]:
			support = _lift_support(soil, next_body, next_frames, mass)
			# Once the soil holds the machine up, it pushes back no harder than the weight needs.
			var scale: float = 1.0 / support["ratio"] if support["ratio"] >= 1.0 else 1.0
			var force: Vector3 = soil["force"]
			var moment: Vector3 = soil["moment"]
			var axis := next_body.basis * next_frames[0].basis.x
			for i in 3:
				var pin := next_body * next_frames[i + 1].origin
				raw_torques[i] = (moment - pin.cross(force)).dot(axis)
			soil_torques = _held_soil_torques(raw_torques * scale, stalled, delta)
			raw_swing_torque = (moment - next_body.origin.cross(force)).dot(next_body.basis * Vector3.DOWN)
			swing_torque = raw_swing_torque * scale
		var changed := false
		for i in 3:
			var speed := hydraulics.planned_speed(i)
			if stalled[i] or is_zero_approx(speed):
				continue
			if cylinders[i].pressure_to_move(gravity[i] + soil_torques[i], signf(speed)) > cylinders[i].relief_pressure:
				stalled[i] = true
				changed = true
		if not changed:
			break

	var direction := signf(swing_joint.speed_deg_s)
	if is_zero_approx(swing_joint.speed_deg_s):
		direction = signf(hydraulics.swing_target())
	# The weakest of the moving cylinders and the swing motor limits how hard the machine is
	# pushed: 82 kN m of swing torque never tips 21 t, however hard the bucket meets something.
	var push_share := INF
	for i in 3:
		var speed := hydraulics.planned_speed(i)
		if not stalled[i] and not is_zero_approx(speed):
			push_share = minf(push_share, cylinders[i].push_share(gravity[i], raw_torques[i], signf(speed)))
	var swing_push := maxf(-raw_swing_torque * direction, 0.0)
	if swing_push > 0.0:
		push_share = minf(push_share, swing_joint.max_torque / swing_push)
	var lifting: bool = support.get("ratio", 0.0) * minf(push_share, 1.0) >= 1.0
	var speed_share := _update_tip(soil, support, push_share, probe, fall_rate, delta)
	for i in 3:
		var cylinder := cylinders[i]
		var speed := hydraulics.planned_speed(i)
		var torque := gravity[i] + soil_torques[i]
		if soil.get("contact", false) and not is_zero_approx(speed) and not stalled[i]:
			_soil_hold[i] = maxf(-soil_torques[i] * signf(speed), 0.0)
			_soil_hold_direction[i] = signf(speed)
		elif not stalled[i]:
			_soil_hold[i] = 0.0
		cylinder.stalled = stalled[i]
		cylinder.speed_share = 1.0
		if stalled[i]:
			cylinder.pressure = cylinder.relief_pressure
		elif speed_share < 1.0 and raw_torques[i] * signf(speed) < 0.0:
			cylinder.speed_share = speed_share
			cylinder.pressure = cylinder.relief_pressure
		elif is_zero_approx(speed):
			# A cylinder closed against its end stop leaves the load pushing into it to the stop.
			var into_stop := (torque > 0.0 and cylinder.angle_deg >= cylinder.max_deg - 1e-4) \
					or (torque < 0.0 and cylinder.angle_deg <= cylinder.min_deg + 1e-4)
			cylinder.pressure = 0.0 if into_stop else minf(cylinder.holding_pressure(torque), cylinder.relief_pressure)
		else:
			cylinder.pressure = cylinder.pressure_to_move(torque, signf(speed))
	# Soil or a truck holds the swing back in full unless it is lifting the machine.
	return maxf(-(swing_torque if lifting else raw_swing_torque) * direction, 0.0)


## The heightfield takes whole grid columns into the bucket before the cutting edge
## reaches them, so the soil torque on a cylinder can drop for a step or two in the middle
## of a cut. While the cylinder keeps moving the same way through the ground, its resisting
## torque only eases off over SOIL_HOLD_TIME.
func _held_soil_torques(torques: Vector3, stalled: Array[bool], delta: float) -> Vector3:
	var decay := exp(-delta / SOIL_HOLD_TIME)
	for i in 3:
		var direction := signf(hydraulics.planned_speed(i))
		if direction == 0.0 or stalled[i] or direction != _soil_hold_direction[i]:
			continue
		var held := _soil_hold[i] * decay
		if held > -torques[i] * direction:
			torques[i] = -held * direction
	return torques


## Track edge the soil reaction would lift the machine about, with the ratio of the
## reaction's lifting moment to the weight moment holding that edge down: 1 or more
## lifts the machine. A lifted machine keeps its edge.
func _lift_support(soil: Dictionary, next_body: Transform3D, next_frames: Array[Transform3D],
		mass: float) -> Dictionary:
	var center := next_body * statics.center_of_mass(next_frames, mass)
	var total := statics.total_mass(mass)
	var edges := [ground.tip_edge] if ground.tip_angle > 0.0 else GroundSupport.Edge.values()
	var best := {"ratio": 0.0}
	for edge in edges:
		var pivot := next_body * ground.tip_pivot(edge)
		var axis := next_body.basis * ground.tip_axis(edge)
		var held := ArmStatics.weight_moment(center, total, pivot, axis)
		var lifting: float = ((soil["moment"] as Vector3) - pivot.cross(soil["force"])).dot(axis)
		if held > 0.0 and lifting > 0.0 and lifting / held > best["ratio"]:
			best = {"ratio": lifting / held, "edge": edge, "pivot": pivot, "axis": axis}
	return best


## Turns the machine about its tip edge. The soil holding the bucket and the cylinders
## pushing on it lift the machine with what the weaker of the two holds beyond the weight,
## up to the speed the arm pushes the bucket down at. While the machine lags behind, soil
## that gives way lets the bucket sink, and cylinders that cannot push harder slow down to
## the machine: returns the share of their planned speed they keep. When the soil gives way
## or the bucket leaves it, the weight turns the machine back down.
func _update_tip(soil: Dictionary, support: Dictionary, push_share: float, probe: float, fall_rate: float,
		delta: float) -> float:
	var ratio: float = support.get("ratio", 0.0)
	var lifting := ratio * minf(push_share, 1.0)
	if ground.tip_angle <= 0.0 and lifting < 1.0:
		ground.tip_speed = 0.0
		return 1.0
	var edge: GroundSupport.Edge = support["edge"] if lifting >= 1.0 else ground.tip_edge
	if ground.tip_angle <= 0.0:
		fall_rate = _tip_fall_rate(edge, _frames(), load_mass())
	var speed := ground.tip_speed
	var share := 1.0
	if lifting >= 1.0:
		var pivot: Vector3 = support["pivot"]
		var rise: float = (support["axis"] as Vector3).cross((soil["deepest"] as Vector3) - pivot).y
		var follow: float = (soil["penetration"] / rise - probe) / delta if rise > 1e-3 else 0.0
		if speed < follow:
			speed = minf(speed + (lifting - 1.0) * fall_rate * delta, follow)
			if push_share < 1.0:
				share = clampf(speed / follow, 0.0, 1.0)
		else:
			speed = maxf(speed - fall_rate * delta, follow)
	else:
		speed -= (1.0 - lifting) * fall_rate * delta
	var angle := ground.tip_angle + speed * delta
	var limit := ground.max_tip_angle(edge, swing_joint.angle_deg)
	if angle <= 0.0:
		angle = 0.0
		speed = 0.0
	elif angle >= limit:
		angle = limit
		speed = minf(speed, 0.0)
	ground.tip_edge = edge
	ground.tip_angle = angle
	ground.tip_speed = speed
	return share


## Angular acceleration the weight alone gives the machine lifted about an edge (rad/s2).
func _tip_fall_rate(edge: GroundSupport.Edge, frames: Array[Transform3D], mass: float) -> float:
	var body := ground.body_transform()
	var pivot := ground.tip_pivot(edge)
	var axis := ground.tip_axis(edge)
	var weight := ArmStatics.weight_moment(body * statics.center_of_mass(frames, mass), statics.total_mass(mass),
			body * pivot, body.basis * axis)
	return maxf(weight, 0.0) / statics.tip_inertia(frames, mass, pivot, axis)


func _drive(delta: float) -> void:
	var previous := ground.position
	ground.advance(terrain, travel, center_of_mass(), delta)
	transform = ground.body_transform()
	var speed := previous.distance_to(ground.position) / delta
	measured_speed = lerpf(measured_speed, speed, 1.0 - exp(-delta / SPEED_SMOOTHING_TIME))


func _apply_pose() -> void:
	# Positive swing angle turns right, which is a negative rotation about +Y.
	turret.rotation.y = -deg_to_rad(swing_joint.angle_deg)
	boom.rotation.x = deg_to_rad(boom_joint.angle_deg)
	stick.rotation.x = deg_to_rad(stick_joint.angle_deg)
	bucket.rotation.x = deg_to_rad(bucket_joint.angle_deg)
	_visual.update(stick_joint.angle_deg, bucket_joint.angle_deg)
	_visual.update_operator(controls)
	_visual.update_tracks(travel.left_distance, travel.right_distance)
