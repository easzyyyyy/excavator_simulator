@tool
class_name GroundSupport
extends RefCounted
## Rests the machine on the ground and carries it along.
##
## Each track touches the ground along its bottom run, between the idler and
## sprocket centres, and around the lower front of the idler and rear of the
## sprocket. Every station is sampled on both shoe edges and the shoe centre.
##
## The track bottoms form one rigid plane. Its rest pose is the lowest centre of
## mass that keeps every support point on or above the ground. With one height per
## track line and a common pitch slope, the rest pitch is the slope of the upper
## convex hull of the weighted Minkowski sum of both track profiles, read under the
## centre of mass. Poses that clear the ground form a convex set, so the body can
## move straight toward its rest pose without touching the ground on the way:
## rising ground pushes it just enough to clear, falling ground lets it accelerate
## toward rest instead of jumping there. This is a static model, not a physics body.
##
## The bucket pressed against the ground can lift the machine: the whole body then turns
## about one edge of its track footprint (the rear or front idler and sprocket line, or
## the outer shoe edge of one track) by the tip angle, on top of the rest pose.

const STATION_SPACING := 0.25
const ARC_ANGLES_DEG := [30.0, 60.0, 90.0]
const SHOE_EDGE_MARGIN := 0.05
## Penetration that counts as the ground pushing the body, which stops its fall.
const PUSH_TOLERANCE := 0.001
const CLEAR_PASSES := 4

## Footprint edges the machine can be lifted about.
enum Edge { REAR, FRONT, LEFT, RIGHT }
## Half angle of the counterweight arc around the tail, and its sample count.
const TAIL_HALF_ANGLE_DEG := 60.0
const TAIL_SAMPLES := 9

## Machine root: on the track bottom plane, under the swing axis.
var position := Vector3.ZERO
## Rotation about +Y in radians, 0 faces -Z. Not wrapped.
var heading := 0.0
## Slope of the track bottom plane: height change per metre along world x and z.
var gradient := Vector2.ZERO
## Lift of the machine about one footprint edge (rad, not negative), the edge it turns
## about, and how fast it turns (rad/s, positive lifting).
var tip_angle := 0.0
var tip_edge := Edge.REAR
var tip_speed := 0.0

var _half_gauge := 1.19
var _half_extent := 2.2
var _settle_acceleration := 3.0
var _fall_speed := 0.0
## Per Edge, in root space: a point of the edge on the track bottom plane, and the
## horizontal direction toward the side that lifts.
var _edge_points: Array[Vector3] = []
var _edge_lifts: Array[Vector3] = []
var _tail_radius := 2.83
var _tail_clearance := 1.05

## Stations ordered rear to front: forward position and height above the track bottom.
var _station_u := PackedFloat32Array()
var _station_lift := PackedFloat32Array()
var _lateral := PackedFloat32Array()

## Per track line, rebuilt every step: horizontal forward coordinate of each station
## relative to the root, and the ground height the line must clear there.
var _left_u := PackedFloat32Array()
var _left_y := PackedFloat32Array()
var _right_u := PackedFloat32Array()
var _right_y := PackedFloat32Array()


func setup(params: MachineParams) -> void:
	_half_gauge = params.track_gauge * 0.5
	_settle_acceleration = params.settle_acceleration
	var half_contact := params.track_contact_length * 0.5
	var end_radius := (params.track_length - params.track_contact_length) * 0.5
	_half_extent = half_contact + end_radius
	var edge := params.shoe_width * 0.5 - SHOE_EDGE_MARGIN
	_lateral = PackedFloat32Array([-edge, 0.0, edge])
	var outer := _half_gauge + edge
	_edge_points = [Vector3(0.0, 0.0, half_contact), Vector3(0.0, 0.0, -half_contact),
			Vector3(-outer, 0.0, 0.0), Vector3(outer, 0.0, 0.0)]
	_edge_lifts = [Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT]
	_tail_radius = params.tail_swing_radius
	_tail_clearance = params.counterweight_clearance

	_station_u.clear()
	_station_lift.clear()
	for i in range(ARC_ANGLES_DEG.size() - 1, -1, -1):
		var angle := deg_to_rad(ARC_ANGLES_DEG[i])
		_add_station(-half_contact - end_radius * sin(angle), end_radius * (1.0 - cos(angle)))
	var intervals := ceili(params.track_contact_length / STATION_SPACING)
	for i in intervals + 1:
		_add_station(-half_contact + params.track_contact_length * i / intervals, 0.0)
	for degrees in ARC_ANGLES_DEG:
		var angle := deg_to_rad(degrees)
		_add_station(half_contact + end_radius * sin(angle), end_radius * (1.0 - cos(angle)))
	_left_u.resize(_station_u.size())
	_left_y.resize(_station_u.size())
	_right_u.resize(_station_u.size())
	_right_y.resize(_station_u.size())


## Puts the machine at a ground position and heading, directly in its rest pose.
func place(terrain: Terrain, ground_position: Vector2, p_heading: float, center_of_mass: Vector3) -> void:
	heading = p_heading
	gradient = Vector2.ZERO
	position = Vector3(ground_position.x, _ground(terrain, ground_position.x, ground_position.y), ground_position.y)
	_fall_speed = 0.0
	clear_tip()
	# The sampled footprint depends on the tilt, so converge over a few passes.
	for i in 4:
		settle(terrain, center_of_mass, 0.0, true)


## One travel step: the tracks move the machine, slipping on slopes beyond the
## gradeability, then the body settles on the ground at its new place.
func advance(terrain: Terrain, travel: TrackDrive, center_of_mass: Vector3, delta: float) -> void:
	move(travel.forward_speed() * travel.traction(forward_slope()) * delta, travel.yaw_rate() * delta)
	settle(terrain, center_of_mass, delta)


## Moves along the track plane and turns about the vertical.
func move(distance: float, yaw_delta: float) -> void:
	heading += yaw_delta
	var forward := Vector2(-sin(heading), -cos(heading))
	var slope := gradient.dot(forward)
	var horizontal := distance / sqrt(1.0 + slope * slope)
	position += Vector3(forward.x * horizontal, slope * horizontal, forward.y * horizontal)


## Updates height and tilt for the current ground. center_of_mass is in undercarriage space.
func settle(terrain: Terrain, center_of_mass: Vector3, delta: float, instant := false) -> void:
	var basis := body_basis()
	var right_h := Vector3(cos(heading), 0.0, -sin(heading))
	var forward_h := Vector3(-sin(heading), 0.0, -cos(heading))
	var roll := gradient.dot(Vector2(right_h.x, right_h.z))
	var pitch := gradient.dot(Vector2(forward_h.x, forward_h.z))
	var stretch := sqrt(1.0 + roll * roll + pitch * pitch)
	var left_x := _sample_line(terrain, -1.0, basis, right_h, forward_h, roll, stretch, _left_u, _left_y)
	var right_x := _sample_line(terrain, 1.0, basis, right_h, forward_h, roll, stretch, _right_u, _right_y)
	var span := right_x - left_x
	var com := basis * center_of_mass
	var weight := clampf((com.dot(right_h) - left_x) / span, 0.0, 1.0)
	var com_u := com.dot(forward_h)

	# States are Vector3(left line height, right line height, pitch slope).
	var slope := _rest_slope(_upper_hull(_left_u, _left_y), _upper_hull(_right_u, _right_y), weight, com_u, pitch)
	var rest := Vector3(_line_height(_left_u, _left_y, slope), _line_height(_right_u, _right_y, slope), slope)
	var current := Vector3(position.y + roll * left_x, position.y + roll * right_x, pitch)

	if instant:
		current = rest
		_fall_speed = 0.0
	else:
		current = _clear_ground(current)
		current = _fall(current, rest, delta)

	var new_roll := (current.y - current.x) / span
	position.y = current.x - new_roll * left_x
	gradient = Vector2(right_h.x, right_h.z) * new_roll + Vector2(forward_h.x, forward_h.z) * current.z


func body_basis() -> Basis:
	var forward_h := Vector3(-sin(heading), 0.0, -cos(heading))
	var slope := gradient.dot(Vector2(forward_h.x, forward_h.z))
	var up := Vector3(-gradient.x, 1.0, -gradient.y).normalized()
	var forward := (forward_h + Vector3.UP * slope).normalized()
	return Basis(forward.cross(up), up, -forward)


## The machine as it stands: rest pose on the tracks, then lifted about the tip edge.
func body_transform() -> Transform3D:
	return rest_transform() * tip_transform(tip_edge, tip_angle)


## The rest pose on the tracks, before any lift.
func rest_transform() -> Transform3D:
	return Transform3D(body_basis(), position)


## Root space rotation lifting the machine by an angle about an edge.
func tip_transform(edge: Edge, angle: float) -> Transform3D:
	if angle == 0.0:
		return Transform3D.IDENTITY
	var rotation := Basis(tip_axis(edge), angle)
	return Transform3D(rotation, _edge_points[edge] - rotation * _edge_points[edge])


## Point of an edge in root space.
func tip_pivot(edge: Edge) -> Vector3:
	return _edge_points[edge]


## Axis of an edge in root space: turning about it by a positive angle lifts its side.
func tip_axis(edge: Edge) -> Vector3:
	return _edge_lifts[edge].cross(Vector3.UP)


func clear_tip() -> void:
	tip_angle = 0.0
	tip_speed = 0.0


## Largest lift about an edge before the counterweight, behind the edge, reaches the track
## bottom plane (rad). Swing turns the tail around the undercarriage.
func max_tip_angle(edge: Edge, swing_deg: float) -> float:
	var limit := PI * 0.5
	var pivot := _edge_points[edge]
	var lift := _edge_lifts[edge]
	for i in TAIL_SAMPLES:
		var offset := lerpf(-TAIL_HALF_ANGLE_DEG, TAIL_HALF_ANGLE_DEG, float(i) / (TAIL_SAMPLES - 1))
		# The tail points backward (+Z) when the turret faces forward; positive swing turns right.
		var bearing := deg_to_rad(offset - swing_deg)
		var point := Vector3(sin(bearing), 0.0, cos(bearing)) * _tail_radius
		var behind := -(point - pivot).dot(lift)
		if behind > 0.0:
			limit = minf(limit, atan2(_tail_clearance, behind))
	return limit


## Lift about the tip edge in degrees.
func tip_deg() -> float:
	return rad_to_deg(tip_angle)


## Nose-up angle of the rest pose in degrees.
func pitch_deg() -> float:
	return rad_to_deg(atan(gradient.dot(Vector2(-sin(heading), -cos(heading)))))


## Side tilt of the rest pose in degrees, positive when the right track is higher.
func roll_deg() -> float:
	return rad_to_deg(atan(gradient.dot(Vector2(cos(heading), -sin(heading)))))


## Slope along the machine's forward direction (rise over run).
func forward_slope() -> float:
	return gradient.dot(Vector2(-sin(heading), -cos(heading)))


## World positions of every support point, for checks.
func support_points() -> PackedVector3Array:
	var result := PackedVector3Array()
	var xform := body_transform()
	for side in [-1.0, 1.0]:
		for k in _station_u.size():
			for lateral in _lateral:
				result.append(xform * Vector3(side * _half_gauge + lateral, _station_lift[k], -_station_u[k]))
	return result


## Deepest support point below the ground, 0 when all clear.
func max_penetration(terrain: Terrain) -> float:
	var deepest := 0.0
	for point in support_points():
		deepest = maxf(deepest, _ground(terrain, point.x, point.z) - point.y)
	return deepest


func _add_station(u: float, lift: float) -> void:
	_station_u.append(u)
	_station_lift.append(lift)


static func _ground(terrain: Terrain, x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain != null else 0.0


## Samples one track line. Returns the line's horizontal right coordinate.
func _sample_line(terrain: Terrain, side: float, basis: Basis, right_h: Vector3, forward_h: Vector3,
		roll: float, stretch: float, out_u: PackedFloat32Array, out_y: PackedFloat32Array) -> float:
	var line_x := side * _half_gauge
	var reference := (basis * Vector3(line_x, 0.0, 0.0)).dot(right_h)
	for k in _station_u.size():
		var lift := _station_lift[k]
		var highest := -INF
		for j in _lateral.size():
			var offset := basis * Vector3(line_x + _lateral[j], lift, -_station_u[k])
			var ground := _ground(terrain, position.x + offset.x, position.z + offset.z)
			# Height the line must reach at its own reference, for this sample to clear.
			var needed := ground - lift * stretch - roll * (offset.dot(right_h) - reference)
			highest = maxf(highest, needed)
			if j == 1:
				out_u[k] = offset.dot(forward_h)
		out_y[k] = highest
	return reference


## Upper convex hull of (u, y) profile points, ordered by u.
static func _upper_hull(u: PackedFloat32Array, y: PackedFloat32Array) -> PackedVector2Array:
	var sorted := PackedVector2Array()
	for k in u.size():
		var p := Vector2(u[k], y[k])
		var i := sorted.size()
		sorted.append(p)
		while i > 0 and sorted[i - 1].x > p.x:
			sorted[i] = sorted[i - 1]
			i -= 1
		sorted[i] = p
	var hull := PackedVector2Array()
	for p in sorted:
		while hull.size() >= 2:
			var a := hull[hull.size() - 2]
			var b := hull[hull.size() - 1]
			if (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) >= 0.0:
				hull.remove_at(hull.size() - 1)
			else:
				break
		if not hull.is_empty() and p.x - hull[hull.size() - 1].x < 1e-6:
			if p.y > hull[hull.size() - 1].y:
				hull[hull.size() - 1] = p
			continue
		hull.append(p)
	return hull


## Pitch slope of the rest pose: walks the upper hull of (1 - w) left + w right, whose
## edges are both hulls' edges merged by decreasing slope, to the edge under com_u.
static func _rest_slope(left: PackedVector2Array, right: PackedVector2Array, w: float, com_u: float,
		previous: float) -> float:
	var x := (1.0 - w) * left[0].x + w * right[0].x
	var i := 0
	var j := 0
	var incoming := INF
	while i < left.size() - 1 or j < right.size() - 1:
		var left_slope := _edge_slope(left, i) if i < left.size() - 1 else -INF
		var right_slope := _edge_slope(right, j) if j < right.size() - 1 else -INF
		var slope: float
		var dx: float
		if left_slope >= right_slope:
			slope = left_slope
			dx = (1.0 - w) * (left[i + 1].x - left[i].x)
			i += 1
		else:
			slope = right_slope
			dx = w * (right[j + 1].x - right[j].x)
			j += 1
		if dx <= 1e-9:
			continue
		if x + dx > com_u:
			# Centre of mass right above a hull vertex: any slope between its two edges
			# is a rest pose, keep the current one when it is among them.
			if com_u - x < 1e-6 and incoming != INF:
				return clampf(previous, slope, incoming)
			return slope
		x += dx
		incoming = slope
	return incoming if incoming != INF else 0.0


static func _edge_slope(hull: PackedVector2Array, i: int) -> float:
	var d := hull[i + 1] - hull[i]
	return d.y / d.x


## Lowest line height that clears every station for this pitch slope.
static func _line_height(u: PackedFloat32Array, y: PackedFloat32Array, slope: float) -> float:
	var height := -INF
	for k in u.size():
		height = maxf(height, y[k] - slope * u[k])
	return height


## Lifts the state out of the ground with the smallest change. Each penetrating
## support point is cleared in turn, sharing the correction between lifting its
## track line and pitching: a point at the front end pivots the body on the rear end,
## a point under the swing axis lifts it straight up. A few passes settle points that
## disturb each other; any residue is removed by a plain lift.
func _clear_ground(current: Vector3) -> Vector3:
	var inverse_length_sq := 1.0 / (_half_extent * _half_extent)
	var deepest := 0.0
	for iteration in CLEAR_PASSES:
		var moved := false
		for line in 2:
			var u := _left_u if line == 0 else _right_u
			var y := _left_y if line == 0 else _right_y
			for k in u.size():
				var height := current.x if line == 0 else current.y
				var gap := height + current.z * u[k] - y[k]
				if gap >= 0.0:
					continue
				if iteration == 0:
					deepest = maxf(deepest, -gap)
				var share := -gap / (1.0 + u[k] * u[k] * inverse_length_sq)
				if line == 0:
					current.x += share
				else:
					current.y += share
				current.z += share * u[k] * inverse_length_sq
				moved = true
		if not moved:
			break
	var residue := _deepest_penetration(current)
	current += Vector3(residue, residue, 0.0)
	if deepest > PUSH_TOLERANCE:
		_fall_speed = 0.0
	return current


func _deepest_penetration(state: Vector3) -> float:
	var deepest := 0.0
	for k in _left_u.size():
		deepest = maxf(deepest, _left_y[k] - state.x - state.z * _left_u[k])
		deepest = maxf(deepest, _right_y[k] - state.y - state.z * _right_u[k])
	return deepest


## Largest vertical motion of a track end between two states.
func _pose_distance(a: Vector3, b: Vector3) -> float:
	return maxf(maxf(absf(b.x - a.x), absf(b.y - a.y)), absf(b.z - a.z) * _half_extent)


## Accelerates the state toward rest. Progress is measured as the largest vertical
## motion of a track end, so tipping over a crest takes time even though the centre
## of mass barely drops at first.
func _fall(current: Vector3, rest: Vector3, delta: float) -> Vector3:
	var distance := _pose_distance(current, rest)
	if distance <= 1e-6:
		_fall_speed = 0.0
		return rest
	_fall_speed += _settle_acceleration * delta
	var step := _fall_speed * delta
	if step >= distance:
		# Caught up: keep only the speed needed to follow a steadily sinking rest pose.
		_fall_speed = minf(_fall_speed, distance / maxf(delta, 1e-6))
		return rest
	return current.lerp(rest, step / distance)
