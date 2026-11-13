@tool
class_name ArmStatics
extends RefCounted
## Mass properties of the machine for an arm pose and a bucket load: centre of mass,
## gravity torques about the arm joints, inertia about the swing axis, and the weight
## moment that holds the machine down on one edge of its tracks and the inertia it turns
## about that edge with.
##
## The boom, stick and bucket are point masses at their centres from MachineParams, the
## load sits at the centroid of the bucket profile. The rest of the machine is one mass,
## placed so that the whole machine has params.center_of_mass with the arm at rest; it
## turns with the swing, which is exact for the upper structure and neutral for the
## undercarriage centred on the swing axis.
##
## Positions are in the machine root space (undercarriage), torques in N m.

const GRAVITY := 9.81

var params: MachineParams
var _fixed_mass := 0.0
## Centre of the rest of the machine in turret space.
var _fixed_center := Vector3.ZERO
var _load_center := Vector2.ZERO


func setup(p_params: MachineParams) -> void:
	params = p_params
	var p := params
	_load_center = Vector2.ZERO
	for point in p.bucket_profile:
		_load_center += point / p.bucket_profile.size()
	_fixed_mass = p.operating_mass - p.boom_mass - p.stick_mass - p.bucket_mass
	var frames := joint_frames(0.0, p.rest_boom_deg, p.rest_stick_deg, p.rest_bucket_deg)
	var moment := p.center_of_mass * p.operating_mass
	var masses := [p.boom_mass, p.stick_mass, p.bucket_mass]
	var centers := part_centers(frames)
	for i in 3:
		moment -= centers[i] * masses[i]
	_fixed_center = moment / _fixed_mass


## Turret, boom, stick and bucket frames in root space; each origin is the joint pin.
func joint_frames(swing_deg: float, boom_deg: float, stick_deg: float, bucket_deg: float) -> Array[Transform3D]:
	var turret := Transform3D(Basis(Vector3.UP, -deg_to_rad(swing_deg)), Vector3.ZERO)
	var boom := turret * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(boom_deg)), params.boom_foot)
	var stick := boom * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(stick_deg)), Vector3(0.0, 0.0, -params.boom_length))
	var bucket := stick * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(bucket_deg)), Vector3(0.0, 0.0, -params.stick_length))
	return [turret, boom, stick, bucket]


## Centres of the boom, stick, bucket and bucket load in root space.
func part_centers(frames: Array[Transform3D]) -> Array[Vector3]:
	var p := params
	return [
		frames[1] * ArmGeometry.to_local(p.boom_mass_center),
		frames[2] * ArmGeometry.to_local(p.stick_mass_center),
		frames[3] * ArmGeometry.to_local(p.bucket_mass_center),
		frames[3] * ArmGeometry.to_local(_load_center),
	]


func total_mass(load_mass: float) -> float:
	return params.operating_mass + load_mass


func center_of_mass(frames: Array[Transform3D], load_mass: float) -> Vector3:
	var p := params
	var centers := part_centers(frames)
	var moment := (frames[0] * _fixed_center) * _fixed_mass
	moment += centers[0] * p.boom_mass + centers[1] * p.stick_mass + centers[2] * p.bucket_mass
	moment += centers[3] * load_mass
	return moment / total_mass(load_mass)


## Gravity torques about the boom, stick and bucket pins, positive toward positive angles.
## gravity is the gravity acceleration in root space.
func gravity_torques(frames: Array[Transform3D], load_mass: float, gravity: Vector3) -> Vector3:
	var p := params
	var centers := part_centers(frames)
	var masses := [p.boom_mass, p.stick_mass, p.bucket_mass, load_mass]
	var axis := frames[0].basis.x
	var torques := Vector3.ZERO
	for joint in 3:
		var pin := frames[joint + 1].origin
		for part in range(joint, 4):
			torques[joint] += ((centers[part] - pin).cross(gravity * masses[part])).dot(axis)
	return torques


## Moment of inertia of everything the swing turns (kg m2), times swing_inertia_scale.
## The boom and stick add their length as slender bars.
func swing_inertia(frames: Array[Transform3D], load_mass: float) -> float:
	var p := params
	var centers := part_centers(frames)
	var masses := [p.boom_mass, p.stick_mass, p.bucket_mass, load_mass]
	var inertia := p.upper_swing_inertia
	for i in 4:
		inertia += masses[i] * (centers[i].x * centers[i].x + centers[i].z * centers[i].z)
	for bar in [[1, p.boom_mass, p.boom_length], [2, p.stick_mass, p.stick_length]]:
		var along: Vector3 = frames[bar[0]].basis.z
		var horizontal := Vector2(along.x, along.z).length()
		inertia += bar[1] * bar[2] * bar[2] * horizontal * horizontal / 12.0
	return inertia * p.swing_inertia_scale


## Moment of inertia of the whole machine about a horizontal root space axis through a
## pivot (kg m2): the body's own inertia, plus every mass at its distance from the axis.
func tip_inertia(frames: Array[Transform3D], load_mass: float, pivot: Vector3, axis: Vector3) -> float:
	var p := params
	var centers := part_centers(frames)
	var points := [frames[0] * _fixed_center, centers[0], centers[1], centers[2], centers[3]]
	var masses := [_fixed_mass, p.boom_mass, p.stick_mass, p.bucket_mass, load_mass]
	var inertia := p.body_pitch_inertia * axis.x * axis.x + p.body_roll_inertia * axis.z * axis.z
	for i in 5:
		var offset: Vector3 = points[i] - pivot
		inertia += masses[i] * (offset - axis * offset.dot(axis)).length_squared()
	return inertia


## Weight moment (N m) about a horizontal axis through pivot that resists lifting the
## side the axis turns up, for a machine centre of mass and mass in world space.
static func weight_moment(center: Vector3, mass: float, pivot: Vector3, axis: Vector3) -> float:
	return -((center - pivot).cross(Vector3.DOWN * GRAVITY * mass)).dot(axis)
