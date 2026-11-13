@tool
class_name BucketSoil
extends RefCounted
## Soil carried by the bucket, and how the bucket cuts, pushes and drops soil.
##
## The bucket is a convex prism: MachineParams.bucket_profile across bucket_width. Its
## closing edge, from the tooth tip back to the rim near the pin, is the opening.
##
## Every physics step, each grid column where the ground rises into the prism loses the
## soil above the prism bottom. Seen from the bucket, each slice of that soil came in
## across one face. Across the opening it fills the bucket, up to the heaped capacity;
## across the back, bottom or side plates, or when the bucket is full, it is pushed onto
## the free columns ahead in the direction the bucket moves, in thin layers from the
## nearest one on. Only the bucket touches the ground.
##
## The load settles under gravity. It fills the bucket from the bottom and may heap over
## the opening no steeper than the soil's bucket heap angle; when the bucket tilts, what
## it can no longer hold pours over the lowest open part of the rim onto the ground, or into
## a structure standing under it, such as a truck body.
## Ground standing in front of the opening holds the load in while digging.
##
## The bucket only cuts while it moves: a bucket at rest, or one whose pose jumped (the
## machine was placed, the arm reset), leaves the ground it overlaps as it is. Moving or
## not, loose soil around does not slide into the space the prism fills
## (Terrain.set_ceilings()), so soil pushed out of the way stays out of it.
##
## Structures standing on the terrain (the truck) push back on the bucket as rigid bodies,
## added to the same resistance: see DumpTruck.push_bucket().
##
## Resistance: before a motion is made, resistance() tells how hard the soil pushes back.
## Points spread over the prism faces, below the ground surface and moving into it, each
## resist over their area seen along the motion. The teeth, and the opening of a bucket
## with room, cut: the cutting resistance opposes the motion. The plates, and the opening of
## a full bucket, push soil square to the face, plus friction along it: with the passive
## pressure for a face looking sideways, the bearing capacity for a face looking down.
## Every resistance grows with the soil standing above the point, and loose soil resists
## less. The force depends on the direction of the motion and on how deep the bucket is,
## not on its speed, and it grows smoothly as the bucket goes in.
##
## Materials: the load keeps the share of each terrain material it took in and pours out
## in the same shares. Resistance reads the material where each sample point is: the ground
## in place, or the material most present in the loose soil there. The heap angle and the
## pour time are the first material's, the same for every soil so far.
##
## Bucket volumes are loose volumes (m3); the terrain counts bank volumes.

const MAX_PUSH_STEPS := 24
## Thickest layer of pushed soil laid on one point in one step (m): more goes on the next
## points ahead, so that pushing builds a berm rather than a spike.
const PUSH_LAYER := 0.1
## Bucket displacement over one step beyond which the pose jumped rather than moved.
const MAX_STEP_MOTION := 1.0
## Height of the slices a column of soil met by the bucket is classified in.
const LAYER_HEIGHT := 0.15
const MAX_LAYERS := 4
## How far outside the opening the ground is probed to tell whether it holds the load in.
const OPENING_PROBE_OFFSET := 0.08
const OPENING_PROBES := 9
## Landing points across the bucket width for soil pouring out.
const SPILL_POINTS := 5
const LEVEL_ITERATIONS := 24
## Spacing of the resistance sample points over the bucket faces (m).
const SAMPLE_SPACING := 0.2
## Fill short of the heaped capacity under which the opening still cuts (m3).
const ROOM_MARGIN := 0.001
## Time over which the pour rate is smoothed for drawing the falling soil (s).
const POUR_SMOOTHING := 0.1
## Thinnest crossing of a vertical line through the prism that counts as inside it (m).
const MIN_SPAN := 0.001
## Height above the ground under which the prism holds back loose soil sliding in (m):
## higher, one step of sliding cannot reach it.
const CEILING_REACH := 0.5

var params: MachineParams
## The first material: heap angle and pour time.
var soil: SoilParams
## Loose soil in the bucket (m3).
var fill := 0.0
## Since the last clear, loose soil (m3) the bucket took in from the ground, poured
## back onto it, and pushed along it (pushed soil may be counted again at every step).
var removed := 0.0
var deposited := 0.0
var pushed := 0.0
## Soil pouring out of the bucket, for drawing it: loose volume per second smoothed over
## POUR_SMOOTHING, the world point in the middle of the rim it pours over, the world
## direction across the bucket, and how far across the opening it pours over (m).
var pour_rate := 0.0
var pour_point := Vector3.ZERO
var pour_across := Vector3.RIGHT
var pour_spread := 0.0

## Materials of the ground the bucket works, the share of each in the load (summing to
## one), and the tangent of each one's friction on steel.
var _materials: Array[SoilParams] = []
var _load_shares := PackedFloat64Array([1.0])
var _friction_tangents := PackedFloat64Array()
var _profile := PackedVector2Array()
## Prism faces in bucket local space (x, v, -u): outward normals and offsets. Profile
## edges first, the opening last among them, then the two side plates.
var _normals: Array[Vector3] = []
var _offsets := PackedFloat64Array()
var _opening_face := 0
## Profile edge ending at the tooth tip: the teeth and the cutting edge.
var _tooth_face := 0
var _opening_normal := Vector2.ZERO
var _half_width := 0.6
var _struck_area := 0.0
var _centre := Vector3.ZERO
var _previous := Transform3D.IDENTITY
var _has_previous := false
## Resistance samples in bucket local space: position, outward normal, face area each one
## stands for, face index, and the two half sides of the face patch around the point.
var _sample_points := PackedVector3Array()
var _sample_normals := PackedVector3Array()
var _sample_areas := PackedFloat32Array()
var _sample_faces := PackedInt32Array()
var _sample_sides_a := PackedVector3Array()
var _sample_sides_b := PackedVector3Array()


func setup(p_params: MachineParams, p_soil: SoilParams) -> void:
	params = p_params
	soil = p_soil
	_materials = [p_soil]
	_load_shares = PackedFloat64Array([1.0])
	_friction_tangents = PackedFloat64Array([tan(deg_to_rad(p_soil.plate_friction_deg))])
	_profile = params.bucket_profile
	_half_width = params.bucket_width * 0.5
	var count := _profile.size()
	var centroid := Vector2.ZERO
	for point in _profile:
		centroid += point / count
	_centre = Vector3(0.0, centroid.y, -centroid.x)
	_normals.clear()
	_offsets.clear()
	for i in count:
		var a := _profile[i]
		var edge := _profile[(i + 1) % count] - a
		var normal := Vector2(edge.y, -edge.x).normalized()
		if normal.dot(a - centroid) < 0.0:
			normal = -normal
		_normals.append(Vector3(0.0, normal.y, -normal.x))
		_offsets.append(normal.dot(a))
	_opening_face = count - 1
	_tooth_face = count - 2
	_opening_normal = Vector2(-_normals[_opening_face].z, _normals[_opening_face].y)
	_normals.append(Vector3.RIGHT)
	_offsets.append(_half_width)
	_normals.append(Vector3.LEFT)
	_offsets.append(_half_width)
	_struck_area = polygon_area(_profile)
	_build_samples(centroid)


## Forgets the previous pose: call after the machine or the arm jumped.
func reset_motion() -> void:
	_has_previous = false


## Empties the bucket and restarts the counters.
func clear() -> void:
	fill = 0.0
	_load_shares.fill(0.0)
	_load_shares[0] = 1.0
	removed = 0.0
	deposited = 0.0
	pushed = 0.0
	pour_rate = 0.0
	_has_previous = false


## Loose volume of each material in the bucket (m3).
func load_volumes() -> PackedFloat64Array:
	var volumes := _load_shares.duplicate()
	for m in volumes.size():
		volumes[m] *= fill
	return volumes


## Mass of the load (kg).
func load_mass() -> float:
	var mass := 0.0
	for m in _load_shares.size():
		mass += fill * _load_shares[m] * material_params(m).loose_density
	return mass


## Load counted as ground in place (m3), the way the terrain counts its volume.
func bank_fill() -> float:
	var bank := 0.0
	for m in _load_shares.size():
		bank += fill * _load_shares[m] / (1.0 + material_params(m).swell())
	return bank


## Material with the largest share of the load.
func load_material() -> int:
	var best := 0
	for m in _load_shares.size():
		if _load_shares[m] > _load_shares[best]:
			best = m
	return best


func material_params(material: int) -> SoilParams:
	if material >= 0 and material < _materials.size() and _materials[material] != null:
		return _materials[material]
	return soil


## Cuts, fills and spills for one physics step with the bucket at this world pose.
func step(terrain: Terrain, bucket_transform: Transform3D, delta: float) -> void:
	var jump := _has_previous and bucket_transform.origin.distance_to(_previous.origin) >= MAX_STEP_MOTION
	var moved := _has_previous and not jump and not bucket_transform.is_equal_approx(_previous)
	var poured := 0.0
	if terrain != null:
		_use_materials(terrain)
		if moved:
			_cut(terrain, bucket_transform)
		_hold_back(terrain, bucket_transform)
		poured = _spill(terrain, bucket_transform, delta)
	if delta > 0.0:
		pour_rate = lerpf(pour_rate, poured / delta, 1.0 - exp(-delta / POUR_SMOOTHING))
	_previous = bucket_transform
	_has_previous = true


## Soil resistance to moving the bucket from one world pose to another, leaving the ground
## as it is. Returns "contact" (the motion pushes into soil), "force" on the bucket (N),
## its "moment" about the world origin (N m), and how much deeper the bucket sinks into the
## ground over the motion, "penetration" (m), at the world point "deepest".
func resistance(terrain: Terrain, from: Transform3D, to: Transform3D) -> Dictionary:
	var result := {"contact": false, "force": Vector3.ZERO, "moment": Vector3.ZERO, "penetration": 0.0,
			"deepest": Vector3.ZERO}
	if terrain == null or from.is_equal_approx(to):
		return result
	_use_materials(terrain)
	for structure in terrain.structures:
		if structure.has_method("push_bucket"):
			structure.push_bucket(self, from, to, result)
	var corners := _corners(to)
	var bounds := _bounds(to)
	# A bucket clear of the ground around its footprint meets no soil, whatever lies ahead.
	var margin := Vector3(terrain.cell_size, 0.0, terrain.cell_size)
	var highest := _highest_ground(terrain, bounds[0] - margin, bounds[1] + margin)
	if bounds[0].y >= highest:
		return result
	var room := fill < max_fill() - ROOM_MARGIN
	var force := Vector3.ZERO
	var moment := Vector3.ZERO
	for s in _sample_points.size():
		var local := _sample_points[s]
		var point := to * local
		if point.y - SAMPLE_SPACING >= highest:
			continue
		var before := from * local
		var motion := point - before
		var distance := motion.length()
		if distance < 1e-7:
			continue
		var direction := motion / distance
		var normal := to.basis * _sample_normals[s]
		var facing := normal.dot(direction)
		if facing <= 0.0:
			continue
		# The ground a face moves into is also read ahead along the motion: one cell, so that
		# the columns just cut behind a face do not lower it between two grid rows, and, when
		# the motion has a real sideways part, beyond the front of the bucket, since the
		# heightfield takes the whole column above the bucket as soon as the bucket is under it.
		var ground := terrain.height_at(point.x, point.z)
		var ahead := point
		var sideways := Vector2(direction.x, direction.z).length()
		if sideways > 1e-3:
			var along := Vector2(direction.x, direction.z) / sideways
			var front := -INF
			for corner in corners:
				front = maxf(front, corner.x * along.x + corner.z * along.y)
			var behind := maxf(front - (point.x * along.x + point.z * along.y), 0.0)
			var distance_ahead := sideways * terrain.cell_size + smoothstep(0.2, 0.5, sideways) * behind
			ahead += Vector3(along.x, 0.0, along.y) * distance_ahead
		var ahead_ground := terrain.height_at(ahead.x, ahead.z)
		var read := point
		if ahead_ground > ground:
			read = ahead
		var loose_depth := terrain.loose_at(read.x, read.z)
		var depth := maxf(ground, ahead_ground) - point.y
		# Share of the patch around the point below the ground, from the depths at its top and
		# bottom ends: the force grows smoothly as a face goes in across the surface, and a face
		# pressed on the ground its own cut left in shape bears in full.
		var side_a := to.basis * _sample_sides_a[s]
		var side_b := to.basis * _sample_sides_b[s]
		var rise := side_a * signf(side_a.y) + side_b * signf(side_b.y)
		var immersed := float(depth > 0.0)
		if rise.y > 1e-6:
			var top_depth := _depth_at(terrain, point + rise, ahead - point)
			var bottom_depth := _depth_at(terrain, point - rise, ahead - point)
			if (top_depth > 0.0) != (bottom_depth > 0.0):
				immersed = maxf(top_depth, bottom_depth) / absf(top_depth - bottom_depth)
			else:
				immersed = float(bottom_depth > 0.0)
		if immersed <= 0.0:
			continue
		result["contact"] = true
		# How far the point goes down into the ground over the motion.
		var sink := minf(before.y - point.y, depth)
		if sink > result["penetration"]:
			result["penetration"] = sink
			result["deepest"] = point
		var cutting := (_sample_faces[s] == _opening_face and room) or _sample_faces[s] == _tooth_face
		var in_loose := maxf(depth, 0.0) <= loose_depth
		var material_index := terrain.loose_material_at(read.x, read.z) if in_loose else terrain.material_at(read.x, read.z)
		var material := material_params(material_index)
		var pressure := material.cutting_resistance
		# The soil standing around the bucket weighs on the ground it works in.
		var overburden := material.overburden_factor * material.bank_density * ArmStatics.GRAVITY \
				* maxf(highest - point.y, 0.0) / 1000.0
		if not cutting:
			# A plate looking sideways pushes the soil ahead of it up to the surface, one looking
			# down presses the soil under it.
			var down := maxf(-normal.y, 0.0)
			pressure = lerpf(material.passive_pressure, material.bearing_capacity, down * down)
		pressure += overburden
		if in_loose:
			pressure *= material.loose_resistance_ratio
		var magnitude := 1000.0 * pressure * _sample_areas[s] * immersed * facing
		var push := direction * -magnitude
		if not cutting:
			# A plate pushes the soil square to itself and slides along it with friction.
			var slide := direction - normal * facing
			var slide_length := slide.length()
			push = normal * -magnitude
			if slide_length > 1e-6:
				push -= slide * (_friction_tangents[material_index] * magnitude / slide_length)
		force += push
		moment += point.cross(push)
	result["force"] += force
	result["moment"] += moment
	return result


func sample_count() -> int:
	return _sample_points.size()


## Resistance sample point in bucket local space, and the face area it stands for (m2).
func sample_point(sample: int) -> Vector3:
	return _sample_points[sample]


func sample_area(sample: int) -> float:
	return _sample_areas[sample]


## How deep a bucket local point is inside the prism (m, negative outside), and the face it
## is nearest to.
func prism_depth(local: Vector3) -> Vector2:
	var depth := INF
	var face := 0
	for f in _normals.size():
		var inside := _offsets[f] - _normals[f].dot(local)
		if inside < depth:
			depth = inside
			face = f
	return Vector2(depth, face)


## Outward normal of a prism face in bucket local space.
func face_normal(face: int) -> Vector3:
	return _normals[face]


## Box around the prism at a pose, in the space of that transform.
func bounds_at(xform: Transform3D) -> AABB:
	var box := AABB(xform * Vector3(-_half_width, _profile[0].y, -_profile[0].x), Vector3.ZERO)
	for corner in _corners(xform):
		box = box.expand(corner)
	return box


## Volume inside the profile below the opening (m3).
func struck_capacity() -> float:
	return _struck_area * params.bucket_width


## Struck capacity plus a heap of this slope over the opening (m3). 45 deg gives the
## SAE J296 heaped rating.
func heaped_capacity(heap_angle_deg: float) -> float:
	return struck_capacity() + _level_heap(heap_angle_deg)


## Most loose soil the bucket takes in while digging.
func max_fill() -> float:
	return heaped_capacity(soil.bucket_heap_angle_deg)


## Loose volume the bucket holds at this orientation with the whole opening free (m3).
func retained_capacity(bucket_basis: Basis) -> float:
	var up := _profile_up(bucket_basis)
	if up == Vector2.ZERO:
		return 0.0
	return _held_area(up, _tip(), _rim(), INF) * params.bucket_width + _tilted_heap(up)


## Load shape for rendering, in the bucket side plane: convex pieces of the profile under
## the soil surface, and the ridge height of the heap over the opening.
func load_shape(bucket_basis: Basis) -> Dictionary:
	var shape := {"pieces": [], "heap": 0.0}
	var up := _profile_up(bucket_basis)
	if fill <= 0.0 or up == Vector2.ZERO:
		return shape
	var area := fill / params.bucket_width
	var full_area := _held_area(up, _tip(), _rim(), INF)
	if area >= full_area:
		shape["pieces"] = _held_pieces(up, _tip(), _rim(), INF)
		var heap := minf(fill - full_area * params.bucket_width, _tilted_heap(up))
		shape["heap"] = heap / _roof_volume_per_height()
		return shape
	var low := INF
	var high := -INF
	for point in _profile:
		low = minf(low, point.dot(up))
		high = maxf(high, point.dot(up))
	for i in LEVEL_ITERATIONS:
		var level := (low + high) * 0.5
		if _held_area(up, _tip(), _rim(), level) < area:
			low = level
		else:
			high = level
	shape["pieces"] = _held_pieces(up, _tip(), _rim(), (low + high) * 0.5)
	return shape


## Heap footprint over the opening for rendering: the opening corners are the tip and rim
## across the width; the ridge runs along the longer side, inset by half the shorter.
func heap_ridge_inset() -> float:
	return minf(_tip().distance_to(_rim()), params.bucket_width) * 0.5


func opening_normal() -> Vector2:
	return _opening_normal


static func polygon_area(polygon: PackedVector2Array) -> float:
	var twice := 0.0
	var count := polygon.size()
	for i in count:
		twice += polygon[i].cross(polygon[(i + 1) % count])
	return absf(twice) * 0.5


## Part of a convex polygon where point.dot(normal) <= offset.
static func clip(polygon: PackedVector2Array, normal: Vector2, offset: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var count := polygon.size()
	for i in count:
		var p := polygon[i]
		var q := polygon[(i + 1) % count]
		var dp := p.dot(normal) - offset
		var dq := q.dot(normal) - offset
		if dp <= 0.0:
			result.append(p)
		if (dp <= 0.0) != (dq <= 0.0):
			result.append(p + (q - p) * (dp / (dp - dq)))
	return result


func _tip() -> Vector2:
	return _profile[_profile.size() - 1]


func _rim() -> Vector2:
	return _profile[0]


## Resistance sample points: a grid over each profile face across the bucket width, and
## over the profile on both side plates.
func _build_samples(centroid: Vector2) -> void:
	_sample_points.clear()
	_sample_normals.clear()
	_sample_areas.clear()
	_sample_faces.clear()
	_sample_sides_a.clear()
	_sample_sides_b.clear()
	var width := params.bucket_width
	var across := maxi(ceili(width / SAMPLE_SPACING), 1)
	var half_across := Vector3(width / across * 0.5, 0.0, 0.0)
	var count := _profile.size()
	for i in count:
		var a := _profile[i]
		var b := _profile[(i + 1) % count]
		var along := maxi(ceili(a.distance_to(b) / SAMPLE_SPACING), 1)
		var area := a.distance_to(b) / along * width / across
		var step := (b - a) / along * 0.5
		var half_along := Vector3(0.0, step.y, -step.x)
		for j in along:
			var point := a.lerp(b, (j + 0.5) / along)
			for k in across:
				_add_sample(Vector3(lerpf(-_half_width, _half_width, (k + 0.5) / across), point.y, -point.x), i, area,
						half_along, half_across)
	var low := Vector2.INF
	var high := -Vector2.INF
	for point in _profile:
		low = low.min(point)
		high = high.max(point)
	var columns := maxi(ceili((high.x - low.x) / SAMPLE_SPACING), 1)
	var rows := maxi(ceili((high.y - low.y) / SAMPLE_SPACING), 1)
	var plate := PackedVector2Array()
	for j in columns:
		for k in rows:
			var point := Vector2(lerpf(low.x, high.x, (j + 0.5) / columns), lerpf(low.y, high.y, (k + 0.5) / rows))
			if _inside_profile(point):
				plate.append(point)
	if plate.is_empty():
		plate.append(centroid)
	var half_u := Vector3(0.0, 0.0, -(high.x - low.x) / columns * 0.5)
	var half_v := Vector3(0.0, (high.y - low.y) / rows * 0.5, 0.0)
	for side in 2:
		var x := _half_width if side == 0 else -_half_width
		for point in plate:
			_add_sample(Vector3(x, point.y, -point.x), count + side, _struck_area / plate.size(), half_u, half_v)


func _add_sample(point: Vector3, face: int, area: float, side_a: Vector3, side_b: Vector3) -> void:
	_sample_points.append(point)
	_sample_normals.append(_normals[face])
	_sample_areas.append(area)
	_sample_faces.append(face)
	_sample_sides_a.append(side_a)
	_sample_sides_b.append(side_b)


func _inside_profile(point: Vector2) -> bool:
	for i in _profile.size():
		if Vector2(-_normals[i].z, _normals[i].y).dot(point) > _offsets[i]:
			return false
	return true


## Depth of a world point below the ground, read there and a shift further along.
func _depth_at(terrain: Terrain, point: Vector3, shift: Vector3) -> float:
	return maxf(terrain.height_at(point.x, point.z), terrain.height_at(point.x + shift.x, point.z + shift.z)) - point.y


## Highest ground point around a world box: bilinear heights never exceed the grid points.
func _highest_ground(terrain: Terrain, low: Vector3, high: Vector3) -> float:
	var origin := terrain.world_origin()
	var cell := terrain.cell_size
	var from_x := clampi(floori((low.x - origin.x) / cell), 0, terrain.cells)
	var to_x := clampi(ceili((high.x - origin.x) / cell), 0, terrain.cells)
	var from_z := clampi(floori((low.z - origin.y) / cell), 0, terrain.cells)
	var to_z := clampi(ceili((high.z - origin.y) / cell), 0, terrain.cells)
	var highest := -INF
	for iz in range(from_z, to_z + 1):
		for ix in range(from_x, to_x + 1):
			highest = maxf(highest, terrain.point_height(ix, iz))
	return highest


## World bounding box corners (lowest, highest) of the prism at a pose.
func _bounds(xform: Transform3D) -> Array[Vector3]:
	var low := Vector3.INF
	var high := -Vector3.INF
	for corner in _corners(xform):
		low = low.min(corner)
		high = high.max(corner)
	return [low, high]


## World positions of the prism corners at a pose.
func _corners(xform: Transform3D) -> PackedVector3Array:
	var corners := PackedVector3Array()
	for point in _profile:
		for x in [-_half_width, _half_width]:
			corners.append(xform * Vector3(x, point.y, -point.x))
	return corners


func _cut(terrain: Terrain, xform: Transform3D) -> void:
	var bounds := _bounds(xform)
	var low: Vector3 = bounds[0]
	var high: Vector3 = bounds[1]
	var origin := terrain.world_origin()
	var cell := terrain.cell_size
	var from_x := clampi(ceili((low.x - origin.x) / cell), 0, terrain.cells)
	var to_x := clampi(floori((high.x - origin.x) / cell), 0, terrain.cells)
	var from_z := clampi(ceili((low.z - origin.y) / cell), 0, terrain.cells)
	var to_z := clampi(floori((high.z - origin.y) / cell), 0, terrain.cells)
	var inverse := xform.affine_inverse()
	var previous_inverse := _previous.affine_inverse()
	var up_local := inverse.basis * Vector3.UP
	var taken := PackedFloat64Array()
	taken.resize(_load_shares.size())
	var pushes := []
	for iz in range(from_z, to_z + 1):
		for ix in range(from_x, to_x + 1):
			var height := terrain.point_height(ix, iz)
			if height <= low.y:
				continue
			var at := terrain.point_position(ix, iz)
			var span := _column_span(inverse, up_local, at.x, at.y)
			if span.x >= span.y or height <= span.x:
				continue
			var top := minf(height, span.y)
			var layers := clampi(ceili((top - span.x) / LAYER_HEIGHT), 1, MAX_LAYERS)
			taken.fill(0.0)
			var total := terrain.remove_above(ix, iz, span.x, taken)
			if total <= 0.0:
				continue
			var share := total / layers
			for layer in layers:
				var middle := Vector3(at.x, lerpf(span.x, top, (layer + 0.5) / layers), at.y)
				var inside := inverse * middle
				var face := _entry_face(inside, previous_inverse * middle - inside, -up_local)
				var volume := share
				if face == _opening_face:
					var accepted := clampf(max_fill() - fill, 0.0, volume)
					_add_load(taken, accepted / total)
					removed += accepted
					volume -= accepted
				if volume > 0.0:
					pushes.append([at, middle, inside, face, volume, taken.duplicate(), volume / total])
	var laid := {}
	for push in pushes:
		var direction := _push_direction(xform, push[1], push[2], push[3])
		_lay_pushed(terrain, inverse, up_local, push[0], direction, push[5], push[6], laid)
		pushed += push[4]


## Marks the columns the prism fills on the terrain, down to its lowest point in each,
## where that is near enough the ground for loose soil to slide in.
func _hold_back(terrain: Terrain, xform: Transform3D) -> void:
	var bounds := _bounds(xform)
	var low: Vector3 = bounds[0]
	var high: Vector3 = bounds[1]
	var origin := terrain.world_origin()
	var cell := terrain.cell_size
	var from_x := clampi(ceili((low.x - origin.x) / cell), 0, terrain.cells)
	var to_x := clampi(floori((high.x - origin.x) / cell), 0, terrain.cells)
	var from_z := clampi(ceili((low.z - origin.y) / cell), 0, terrain.cells)
	var to_z := clampi(floori((high.z - origin.y) / cell), 0, terrain.cells)
	var inverse := xform.affine_inverse()
	var up_local := inverse.basis * Vector3.UP
	var indices := PackedInt32Array()
	var lowest := PackedFloat32Array()
	for iz in range(from_z, to_z + 1):
		for ix in range(from_x, to_x + 1):
			if terrain.point_height(ix, iz) + CEILING_REACH < low.y:
				continue
			var at := terrain.point_position(ix, iz)
			var span := _column_span(inverse, up_local, at.x, at.y)
			if span.x < span.y and span.x < terrain.point_height(ix, iz) + CEILING_REACH:
				indices.append(iz * terrain.points + ix)
				lowest.append(span.x)
	terrain.set_ceilings(indices, lowest)


## Adds loose soil to the load: volumes (m3) per material, times scale.
func _add_load(volumes: PackedFloat64Array, scale: float) -> void:
	var added := 0.0
	for m in volumes.size():
		added += volumes[m] * scale
	if added <= 0.0:
		return
	var total := fill + added
	for m in _load_shares.size():
		var volume := volumes[m] * scale if m < volumes.size() else 0.0
		_load_shares[m] = (_load_shares[m] * fill + volume) / total
	fill = total


## Takes the materials of the ground being worked, keeping the load's shares.
func _use_materials(terrain: Terrain) -> void:
	if _materials == terrain.materials and _load_shares.size() == terrain.material_count():
		return
	_materials = terrain.materials
	_load_shares.resize(terrain.material_count())
	_friction_tangents.resize(terrain.material_count())
	for m in terrain.material_count():
		_friction_tangents[m] = tan(deg_to_rad(material_params(m).plate_friction_deg))


## World heights (lowest, highest) where the vertical line at x, z crosses the prism.
## Empty (lowest above highest) when the line misses the prism or only grazes it: a line
## along an edge would otherwise go in and out with rounding from one step to the next.
func _column_span(inverse: Transform3D, up_local: Vector3, x: float, z: float) -> Vector2:
	var start := inverse * Vector3(x, 0.0, z)
	var lowest := -INF
	var highest := INF
	for f in _normals.size():
		var normal := _normals[f]
		var rate := normal.dot(up_local)
		var gap := _offsets[f] - normal.dot(start)
		if absf(rate) < 1e-9:
			if gap < 0.0:
				return Vector2(INF, -INF)
			continue
		if rate > 0.0:
			highest = minf(highest, gap / rate)
		else:
			lowest = maxf(lowest, gap / rate)
	if highest - lowest < MIN_SPAN:
		return Vector2(INF, -INF)
	return Vector2(lowest, highest)


## Face crossed first when leaving the prism from a local point along a direction.
func _entry_face(inside: Vector3, direction: Vector3, fallback: Vector3) -> int:
	if direction.length_squared() < 1e-12:
		direction = fallback
	var best := -1
	var nearest := INF
	for f in _normals.size():
		var rate := _normals[f].dot(direction)
		if rate <= 1e-12:
			continue
		var distance := (_offsets[f] - _normals[f].dot(inside)) / rate
		if distance < nearest:
			nearest = distance
			best = f
	return best


## Horizontal direction soil is pushed: the way the bucket moves there, or away from the
## face that met it when the bucket moves mostly vertically.
func _push_direction(xform: Transform3D, world_point: Vector3, local_point: Vector3, face: int) -> Vector2:
	var motion := world_point - _previous * local_point
	var along_ground := Vector2(motion.x, motion.z)
	if along_ground.length() > 1e-5 and along_ground.length() > 0.25 * motion.length():
		return along_ground.normalized()
	var normal := xform.basis * _normals[face] if face >= 0 else Vector3.ZERO
	var outward := Vector2(normal.x, normal.z)
	if outward.length() > 0.2:
		return outward.normalized()
	var centre := xform * _centre
	var away := Vector2(world_point.x - centre.x, world_point.z - centre.z)
	return away.normalized() if away.length() > 1e-4 else Vector2.RIGHT


## Lays soil pushed from a start position on the grid points along a direction whose
## ground stays below the prism: volumes (m3) per material times scale, never up into the
## prism, and with what this step already laid there (thickness per grid index in laid) at
## most PUSH_LAYER thick on each point. What is left is shared by the points found clear of
## the prism, or goes on the last point found when none is.
func _lay_pushed(terrain: Terrain, inverse: Transform3D, up_local: Vector3, start: Vector2,
		direction: Vector2, volumes: PackedFloat64Array, scale: float, laid: Dictionary) -> void:
	var total := 0.0
	for volume in volumes:
		total += volume * scale
	if total <= 0.0:
		return
	var area := terrain.cell_size * terrain.cell_size
	var last := terrain.nearest_point(start.x, start.y)
	var target := last
	var clear: Array[Vector2i] = []
	var done := 0.0
	for k in range(1, MAX_PUSH_STEPS + 1):
		var probe := start + direction * terrain.cell_size * 0.5 * k
		var point := terrain.nearest_point(probe.x, probe.y)
		if point == last:
			continue
		last = point
		var at := terrain.point_position(point.x, point.y)
		var span := _column_span(inverse, up_local, at.x, at.y)
		var height := terrain.point_height(point.x, point.y)
		if span.x < span.y and height > span.x:
			continue
		target = point
		var index := point.y * terrain.points + point.x
		var room: float = PUSH_LAYER - laid.get(index, 0.0)
		if span.x < span.y:
			room = minf(room, span.x - height)
		else:
			clear.append(point)
		var share := minf(room * area / total, 1.0 - done)
		if share > 0.0:
			terrain.add_loose_parts(point.x, point.y, volumes, scale * share)
			laid[index] = laid.get(index, 0.0) + share * total / area
			done += share
		if done >= 1.0 - 1e-9:
			return
	if clear.is_empty():
		clear.append(target)
	for point in clear:
		terrain.add_loose_parts(point.x, point.y, volumes, scale * (1.0 - done) / clear.size())


## Pours what the bucket can no longer hold onto the ground. Returns the loose volume
## poured (m3).
func _spill(terrain: Terrain, xform: Transform3D, delta: float) -> float:
	if fill <= 1e-9:
		return 0.0
	var up := _profile_up(xform.basis)
	if up == Vector2.ZERO:
		return 0.0
	var heap := _tilted_heap(up)
	if fill <= _held_area(up, _tip(), _rim(), INF) * params.bucket_width + heap:
		return 0.0
	# Ground in front of part of the opening walls it off: only the rest lets soil out.
	var first_open := -1
	var last_open := -1
	for k in OPENING_PROBES:
		var fraction := float(k) / (OPENING_PROBES - 1)
		var probe := _tip().lerp(_rim(), fraction) + _opening_normal * OPENING_PROBE_OFFSET
		var world := xform * Vector3(0.0, probe.y, -probe.x)
		if terrain.height_at(world.x, world.z) < world.y:
			if first_open < 0:
				first_open = k
			last_open = k
	if first_open < 0:
		return 0.0
	var a := _tip().lerp(_rim(), float(first_open) / (OPENING_PROBES - 1))
	var b := _tip().lerp(_rim(), float(last_open) / (OPENING_PROBES - 1))
	var excess := fill - _held_area(up, a, b, INF) * params.bucket_width - heap
	if excess <= 1e-9:
		return 0.0
	var amount := excess * (1.0 - exp(-delta / maxf(soil.spill_time, 1e-3)))
	fill -= amount
	deposited += amount
	# Soil pours over the lowest open rim point, spread toward the opening centre as the
	# opening turns to face down.
	var lowest := a if a.dot(up) <= b.dot(up) else b
	var other := b if lowest == a else a
	var outward := xform.basis * _normals[_opening_face]
	var reach := clampf(-outward.y, 0.0, 1.0) * 0.5
	var nudge := Vector3(outward.x, 0.0, outward.z) * 0.05
	for s in SPILL_POINTS:
		var x := lerpf(-_half_width, _half_width, (s + 0.5) / SPILL_POINTS)
		for along in 2:
			var point := lowest.lerp(other, reach * along)
			var world := xform * Vector3(x, point.y, -point.x) + nudge
			terrain.deposit_parts(world.x, world.z, _load_shares, amount / (SPILL_POINTS * 2), world.y)
	var middle := lowest.lerp(other, reach * 0.5)
	pour_point = xform * Vector3(0.0, middle.y, -middle.x) + nudge
	pour_across = (xform.basis * Vector3.RIGHT).normalized()
	var far := lowest.lerp(other, reach)
	var span := xform.basis * Vector3(0.0, far.y - lowest.y, lowest.x - far.x)
	pour_spread = Vector2(span.x, span.z).length()
	return amount


## World up in the bucket side plane (u, v), or zero when the plane is horizontal.
func _profile_up(bucket_basis: Basis) -> Vector2:
	var local := bucket_basis.inverse() * Vector3.UP
	var up := Vector2(-local.z, local.y)
	return up.normalized() if up.length() > 1e-3 else Vector2.ZERO


func _held_area(up: Vector2, a: Vector2, b: Vector2, level: float) -> float:
	var area := 0.0
	for piece in _held_pieces(up, a, b, level):
		area += polygon_area(piece)
	return area


## Pieces of the profile the load can fill below a level with the opening free between
## a and b. Above each horizontal position the soil surface may rise no steeper than the
## heap angle from the open rim, and not above the opening itself; three vertical strips,
## split at the ends of the opening, each get one straight bound.
func _held_pieces(up: Vector2, a: Vector2, b: Vector2, level: float) -> Array[PackedVector2Array]:
	var side := Vector2(up.y, -up.x)
	if a.dot(side) > b.dot(side):
		var swap := a
		a = b
		b = swap
	var t := tan(deg_to_rad(soil.bucket_heap_angle_deg))
	var sa := a.dot(side)
	var sb := b.dot(side)
	var ha := a.dot(up)
	var hb := b.dot(up)
	var pieces: Array[PackedVector2Array] = []

	# Before the opening: rising away from the nearer end, or the far end if lower.
	var left := a if hb - ha + t * (sb - sa) >= 0.0 else b
	var normal := up + side * t
	pieces.append(_bounded(_profile, [side, sa, normal, left.dot(normal)], level, up))

	# Across the opening: the opening line when flatter than the heap angle, otherwise
	# rising from its lower end.
	if sb - sa > 1e-6:
		var slope := (hb - ha) / (sb - sa)
		var anchor := a
		if slope > t:
			slope = t
		elif slope < -t:
			slope = -t
			anchor = b
		normal = up - side * slope
		pieces.append(_bounded(_profile, [-side, -sa, side, sb, normal, anchor.dot(normal)], level, up))

	# After the opening: rising from whichever end gives the lower surface.
	var right := a if ha - hb + t * (sb - sa) <= 0.0 else b
	normal = up - side * t
	pieces.append(_bounded(_profile, [-side, -sb, normal, right.dot(normal)], level, up))
	return pieces


## Clips a polygon by pairs (normal, offset) from a flat array, then by a level along up.
static func _bounded(polygon: PackedVector2Array, planes: Array, level: float, up: Vector2) -> PackedVector2Array:
	var result := polygon
	for i in range(0, planes.size(), 2):
		result = clip(result, planes[i], planes[i + 1])
		if result.size() < 3:
			return PackedVector2Array()
	if level < INF:
		result = clip(result, up, level)
	return result if result.size() >= 3 else PackedVector2Array()


## Heap volume over the opening when it faces up and tilts less than the heap angle:
## the level heap shrinks like the side-view triangle between the opening and two
## lines at the heap angle.
func _tilted_heap(up: Vector2) -> float:
	if _opening_normal.dot(up) <= 0.0:
		return 0.0
	var sin_tilt := absf((_rim() - _tip()).normalized().dot(up))
	var sin_heap := sin(deg_to_rad(soil.bucket_heap_angle_deg))
	if sin_tilt >= sin_heap:
		return 0.0
	return _level_heap(soil.bucket_heap_angle_deg) * (sin_heap * sin_heap - sin_tilt * sin_tilt) / (sin_heap * sin_heap)


## Hip roof of equal slopes over the opening rectangle.
func _level_heap(angle_deg: float) -> float:
	return tan(deg_to_rad(angle_deg)) * _roof_volume_per_height() * heap_ridge_inset()


## Hip roof volume per unit of ridge height over the opening rectangle.
func _roof_volume_per_height() -> float:
	var chord := _tip().distance_to(_rim())
	var long_side := maxf(chord, params.bucket_width)
	var short_side := minf(chord, params.bucket_width)
	return short_side * long_side * 0.5 - short_side * short_side / 6.0
