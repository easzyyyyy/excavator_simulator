@tool
class_name ArmGeometry
extends RefCounted
## Planar kinematics of the excavator arm, shared by the simulation, the visuals
## and the tests. All points are side-plane Vector2(u, v) unless stated otherwise.


static func to_local(point: Vector2, x := 0.0) -> Vector3:
	return Vector3(x, point.y, -point.x)


static func boom_foot_2d(params: MachineParams) -> Vector2:
	return Vector2(-params.boom_foot.z, params.boom_foot.y)


## Arm pins in the turret side plane for the given joint angles.
static func arm_points(params: MachineParams, boom_deg: float, stick_deg: float, bucket_deg: float) -> Dictionary:
	var foot := boom_foot_2d(params)
	var boom_dir := Vector2.RIGHT.rotated(deg_to_rad(boom_deg))
	var stick_dir := Vector2.RIGHT.rotated(deg_to_rad(boom_deg + stick_deg))
	var bucket_dir := Vector2.RIGHT.rotated(deg_to_rad(boom_deg + stick_deg + bucket_deg))
	var nose := foot + boom_dir * params.boom_length
	var pin := nose + stick_dir * params.stick_length
	var tip := pin + bucket_dir * params.bucket_tip_radius
	return {"foot": foot, "nose": nose, "bucket_pin": pin, "tip": tip}


## Bucket pose in undercarriage space, as the scene hierarchy places the Bucket node:
## origin on the bucket pin, tooth tip along -Z at zero bucket angle.
static func bucket_transform(params: MachineParams, swing_deg: float, boom_deg: float, stick_deg: float,
		bucket_deg: float) -> Transform3D:
	var turret := Transform3D(Basis(Vector3.UP, -deg_to_rad(swing_deg)), Vector3.ZERO)
	var boom := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(boom_deg)), params.boom_foot)
	var stick := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(stick_deg)), Vector3(0.0, 0.0, -params.boom_length))
	var bucket := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(bucket_deg)), Vector3(0.0, 0.0, -params.stick_length))
	return turret * boom * stick * bucket


## Joint angles (boom, stick, bucket) putting the tooth tip at a turret side-plane point
## with the bucket pin-to-tip line at an absolute angle, boom nose above the pin line.
## Null when out of reach; joint limits are not checked.
static func pose_for_tip(params: MachineParams, tip: Vector2, bucket_absolute_deg: float) -> Variant:
	var foot := boom_foot_2d(params)
	var pin := tip - Vector2.RIGHT.rotated(deg_to_rad(bucket_absolute_deg)) * params.bucket_tip_radius
	var nose: Variant = circle_intersection_upper(foot, params.boom_length, pin, params.stick_length)
	if nose == null:
		return null
	var boom_deg := rad_to_deg(((nose as Vector2) - foot).angle())
	var stick_absolute := rad_to_deg((pin - (nose as Vector2)).angle())
	return Vector3(boom_deg, wrapf(stick_absolute - boom_deg, -180.0, 180.0),
			wrapf(bucket_absolute_deg - stick_absolute, -180.0, 180.0))


static func boom_cylinder_length(params: MachineParams, boom_deg: float) -> float:
	var rod_end := params.boom_cyl_rod_end.rotated(deg_to_rad(boom_deg))
	return rod_end.distance_to(params.boom_cyl_base)


static func stick_cylinder_length(params: MachineParams, stick_deg: float) -> float:
	var nose := Vector2(params.boom_length, 0.0)
	var rod_end := nose + params.stick_cyl_rod_end.rotated(deg_to_rad(stick_deg))
	return rod_end.distance_to(params.stick_cyl_base)


## Bucket linkage in the stick side plane. Returns an empty dictionary when the
## linkage cannot be assembled at this bucket angle.
static func bucket_linkage(params: MachineParams, bucket_deg: float) -> Dictionary:
	var pin := Vector2(params.stick_length, 0.0)
	var link_pin := pin + Vector2.RIGHT.rotated(deg_to_rad(bucket_deg + params.bucket_link_angle_deg)) \
			* params.bucket_link_radius
	var joint: Variant = circle_intersection_upper(params.rocker_pivot, params.rocker_length,
			link_pin, params.power_link_length)
	if joint == null:
		return {}
	return {
		"bucket_pin": pin,
		"bucket_link_pin": link_pin,
		"rocker_pivot": params.rocker_pivot,
		"joint": joint,
		"cylinder_length": (joint as Vector2).distance_to(params.bucket_cyl_base),
	}


## Intersection of two circles, choosing the solution with the larger v.
static func circle_intersection_upper(c1: Vector2, r1: float, c2: Vector2, r2: float) -> Variant:
	var d := c1.distance_to(c2)
	if d < 1e-6 or d > r1 + r2 or d < absf(r1 - r2):
		return null
	var a := (r1 * r1 - r2 * r2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(r1 * r1 - a * a, 0.0))
	var ex := (c2 - c1) / d
	var mid := c1 + ex * a
	var p1 := mid + Vector2(-ex.y, ex.x) * h
	var p2 := mid + Vector2(ex.y, -ex.x) * h
	return p1 if p1.y >= p2.y else p2


## Samples the joint space and returns the working envelope in metres, using the
## same conventions as manufacturer range diagrams.
static func working_envelope(params: MachineParams, step_deg := 1.0) -> Dictionary:
	var max_reach_ground := 0.0
	var max_depth := 0.0
	var max_cut := -INF
	var max_pin_height := -INF
	var boom := params.boom_min_deg
	while boom <= params.boom_max_deg + 1e-6:
		var stick := params.stick_min_deg
		while stick <= params.stick_max_deg + 1e-6:
			var base := arm_points(params, boom, stick, 0.0)
			max_pin_height = maxf(max_pin_height, base["bucket_pin"].y)
			var bucket := params.bucket_min_deg
			while bucket <= params.bucket_max_deg + 1e-6:
				var tip: Vector2 = arm_points(params, boom, stick, bucket)["tip"]
				max_depth = maxf(max_depth, -tip.y)
				max_cut = maxf(max_cut, tip.y)
				if absf(tip.y) < 0.03:
					max_reach_ground = maxf(max_reach_ground, tip.x)
				bucket += step_deg * 2.0
			stick += step_deg
		boom += step_deg
	return {
		"max_reach_ground": max_reach_ground,
		"max_dig_depth": max_depth,
		"max_cutting_height": max_cut,
		"max_loading_height": max_pin_height - params.bucket_tip_radius,
	}
