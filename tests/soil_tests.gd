extends RefCounted
## Phase 3 checks: soil data, bucket capacities, loose soil relaxation, a full dig,
## carry and dump cycle with volume conservation, and digging from the keyboard.
## Driven by run_tests.gd, which owns the check counters.

const DT := 1.0 / 120.0

var _runner: SceneTree


func _init(runner: SceneTree) -> void:
	_runner = runner


func run(params: MachineParams) -> void:
	var soil: SoilParams = load("res://data/common_earth.tres")
	_test_soil_data(soil)
	_test_bucket_capacities(params, soil)
	_test_relaxation(soil)
	_test_relaxation_after_a_slide(soil)
	_test_dumped_cone(soil)
	_test_stick_does_not_dig(params, soil)
	_test_placed_bucket(params, soil)
	_test_dig_carry_dump(params, soil)
	_test_bucket_back_pushes(params, soil)


## Digging through the real input path on a scene instance.
func run_scene(excavator: Excavator) -> void:
	print("Digging from the keyboard")
	var params := excavator.params
	var turret_bucket := excavator.global_transform.affine_inverse() * excavator.bucket.global_transform
	var planar := ArmGeometry.bucket_transform(params, excavator.swing_joint.angle_deg, excavator.boom_joint.angle_deg,
			excavator.stick_joint.angle_deg, excavator.bucket_joint.angle_deg)
	_check(turret_bucket.is_equal_approx(planar), "bucket pose from planar kinematics matches the scene")
	_check(excavator.bucket.get_node_or_null("SoilLoad") is BucketLoadVisual, "bucket carries a soil load mesh")

	var terrain := Terrain.new()
	terrain.layout = Terrain.Layout.FLAT
	terrain.cells = 96
	terrain.chunk_cells = 32
	terrain.tile_cells = 32
	excavator.get_parent().add_child(terrain)
	excavator.terrain = terrain
	excavator.bucket_soil.clear()
	excavator.controls.pattern = ControlInput.Pattern.ISO
	excavator.place(Vector2.ZERO, 0.0)
	var angles: Vector3 = ArmGeometry.pose_for_tip(params, Vector2(6.5, -0.35), -100.0)
	excavator.set_pose(0.0, angles.x, angles.y, angles.z)
	var reference := terrain.bank_volume()
	# ISO: left stick back pulls the stick in, right stick left curls the bucket.
	_hold(excavator, [KEY_S, KEY_J], 1.5)
	_check(excavator.bucket_soil.fill > 0.3, "stick in and bucket curl fill the bucket (%.2f m3)" % excavator.bucket_soil.fill)
	var lowest := INF
	for iz in terrain.points:
		for ix in terrain.points:
			lowest = minf(lowest, terrain.point_height(ix, iz))
	_check(lowest < -0.2, "the ground in front of the machine is dug (%.2f m deep)" % -lowest)
	var swell := terrain.soil.swell()
	var error := (terrain.bank_volume() - reference + excavator.bucket_soil.bank_fill()) * (1.0 + swell)
	_check(absf(error) < 1e-3, "soil volume is conserved in play (%.5f m3)" % error)
	excavator._process(DT)
	var load_mesh := (excavator.bucket.get_node("SoilLoad") as MeshInstance3D).mesh
	_check(load_mesh != null and load_mesh.get_surface_count() == 1, "the load is drawn in the bucket")
	excavator.terrain = null
	excavator.bucket_soil.clear()
	excavator.reset_pose()
	excavator.return_to_start()
	terrain.queue_free()


func _test_soil_data(soil: SoilParams) -> void:
	print("Soil data")
	_near(1.0 / (1.0 + soil.swell()), 0.80, 0.01, "common earth load factor (handbook 0.80)")
	_check(soil.repose_angle_deg >= 30.0 and soil.repose_angle_deg <= 35.0, "angle of repose within the planned 30 to 35 deg")


func _test_bucket_capacities(params: MachineParams, soil: SoilParams) -> void:
	print("Bucket capacities")
	var bucket := BucketSoil.new()
	bucket.setup(params, soil)
	var profile := params.bucket_profile
	var convex := true
	for i in profile.size():
		var a := profile[i]
		var b := profile[(i + 1) % profile.size()]
		var c := profile[(i + 2) % profile.size()]
		convex = convex and (b - a).cross(c - b) < 0.0
	_check(convex, "bucket profile is convex")
	_check(profile[profile.size() - 1].is_equal_approx(Vector2(params.bucket_tip_radius, 0.0)),
			"bucket profile ends at the tooth tip")
	_near(bucket.heaped_capacity(45.0), params.ref_bucket_heaped_capacity, 0.02, "SAE heaped capacity (m3)")
	print("        struck capacity %.2f m3" % bucket.struck_capacity())

	# Absolute pin-to-tip angle; at level_deg the opening is horizontal and faces up.
	var level_deg := _level_bucket_deg(params)
	var level := bucket.retained_capacity(Basis(Vector3.RIGHT, deg_to_rad(level_deg)))
	_near(level, bucket.max_fill(), 0.001, "level bucket holds its heaped capacity (m3)")
	var teeth_down := bucket.retained_capacity(Basis(Vector3.RIGHT, deg_to_rad(270.0)))
	_check(teeth_down > 0.0 and teeth_down < 0.5 * bucket.struck_capacity(),
			"teeth pointing down hold only the bottom of the load (%.2f m3)" % teeth_down)
	var upside_down := bucket.retained_capacity(Basis(Vector3.RIGHT, deg_to_rad(level_deg + 180.0)))
	_check(upside_down < 0.02 * bucket.struck_capacity(), "opening facing down holds nothing (%.3f m3)" % upside_down)
	var monotonic := true
	var previous := level
	var tilt := 0.0
	var threshold := NAN
	var half_out := NAN
	while tilt <= 180.0:
		var held := bucket.retained_capacity(Basis(Vector3.RIGHT, deg_to_rad(level_deg + tilt)))
		monotonic = monotonic and held <= previous + 1e-6
		if is_nan(threshold) and held < level - 1e-3:
			threshold = tilt
		if is_nan(half_out) and held < level * 0.5:
			half_out = tilt
		previous = held
		tilt += 1.0
	_check(monotonic, "dumping pours out more the further the bucket turns")
	print("        load starts to pour %.0f deg past level, half of it is out at %.0f deg" % [threshold, half_out])


func _test_relaxation(soil: SoilParams) -> void:
	print("Loose soil relaxation")
	var terrain := Terrain.new()
	terrain.soil = soil
	terrain.setup(64, 0.25)
	# A cliff of ground in place: 2 m high over one cell.
	terrain.apply(Rect2(-8.0, -8.0, 16.0, 16.0), func(x: float, _z: float, _h: float) -> float:
			return 2.0 if x < -3.0 else 0.0)
	var cliff := terrain.heights.duplicate()
	terrain.relax(100000)
	_check(terrain.heights == cliff, "ground in place keeps a vertical cut")
	var before := terrain.bank_volume()
	terrain.deposit(0.1, 0.05, 0.8)
	terrain.deposit(-3.4, 1.0, 0.3)
	var steps := 0
	while terrain.relax(Terrain.RELAX_VISITS_PER_TICK) > 0 and steps < 20000:
		steps += 1
	_check(terrain.pending_relaxation() == 0, "relaxation settles (%d ticks)" % steps)
	var steepest := _steepest_loose_slope(terrain)
	_check(steepest <= soil.repose_angle_deg + 0.05, "no loose slope steeper than the angle of repose (%.2f deg)" % steepest)
	var bank_kept := true
	for i in terrain.heights.size():
		bank_kept = bank_kept and terrain.heights[i] - terrain.loose[i] >= cliff[i] - 1e-5
	_check(bank_kept, "loose soil slides over the ground in place without eroding it")
	var added := 1.1 / (1.0 + soil.swell())
	_check(absf(terrain.bank_volume() - before - added) < 1e-4, "relaxation conserves the soil volume")
	_check(absf(terrain.bank_volume() - terrain.bank_volume_recount()) < 1e-4, "running volume matches a full recount")
	terrain.free()


## A flat layer of loose soil ending 30 cm high beside a thinner strip at a trench edge:
## once the strip slides into the trench, the layer behind it slides after it.
func _test_relaxation_after_a_slide(soil: SoilParams) -> void:
	var terrain := Terrain.new()
	terrain.soil = soil
	terrain.setup(32, 0.25)
	var cell_area := terrain.cell_size * terrain.cell_size
	# The layer is laid first, so it is checked, found stable, before the strip slides.
	for pass_index in 3:
		for iz in terrain.points:
			for ix in terrain.points:
				var x := terrain.point_position(ix, iz).x
				if pass_index == 0 and x > 0.4:
					terrain.set_point_height(ix, iz, -1.0)
				elif pass_index == 1 and x < 0.1:
					terrain.add_loose(ix, iz, 0.3 * cell_area)
				elif pass_index == 2 and x > 0.1 and x < 0.4:
					terrain.add_loose(ix, iz, 0.2 * cell_area)
	while terrain.relax(Terrain.RELAX_VISITS_PER_TICK) > 0:
		pass
	var steepest := _steepest_loose_slope(terrain)
	_check(steepest <= soil.repose_angle_deg + 0.05,
			"loose soil left standing by a slide below it follows it down (%.2f deg)" % steepest)
	terrain.free()


func _test_dumped_cone(soil: SoilParams) -> void:
	print("Dumping slowly")
	var terrain := Terrain.new()
	terrain.soil = soil
	terrain.setup(64, 0.25)
	var poured := 0.0
	while poured < 1.5:
		terrain.deposit(0.0, 0.0, 0.005)
		poured += 0.005
		terrain.relax(Terrain.RELAX_VISITS_PER_TICK)
	while terrain.relax(Terrain.RELAX_VISITS_PER_TICK) > 0:
		pass
	var centre := terrain.nearest_point(0.0, 0.0)
	var apex := terrain.point_height(centre.x, centre.y)
	var slopes := PackedFloat32Array()
	for direction in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		slopes.append(_flank_slope(terrain, centre, direction, apex))
	var lowest := 90.0
	var highest := 0.0
	for slope in slopes:
		lowest = minf(lowest, slope)
		highest = maxf(highest, slope)
	_check(lowest >= 30.0 and highest <= 35.0, "1.5 m3 poured on one spot forms a cone at %.1f to %.1f deg" % [lowest, highest])
	print("        cone %.2f m high" % apex)
	terrain.free()


func _test_stick_does_not_dig(params: MachineParams, soil: SoilParams) -> void:
	print("Only the bucket digs")
	var rig := Rig.new(params, soil)
	# A 3.2 m block the stick passes through while the bucket, teeth down, stays beside it.
	rig.terrain.apply(Rect2(-3.0, -7.0, 6.0, 0.7), func(_x: float, _z: float, _h: float) -> float: return 3.2)
	var block := rig.terrain.heights.duplicate()
	rig.move_tip(Vector2(8.0, 0.5), -90.0, 0.0)
	var points := ArmGeometry.arm_points(params, rig.angles.x, rig.angles.y, rig.angles.z)
	var nose: Vector2 = points["nose"]
	var pin: Vector2 = points["bucket_pin"]
	var stick_height := lerpf(nose.y, pin.y, (6.65 - nose.x) / (pin.x - nose.x))
	rig.move_tip(Vector2(8.3, 0.5), -90.0, 1.0)
	_check(stick_height < 3.2 and rig.terrain.heights == block and rig.bucket.removed == 0.0,
			"the stick crosses a soil block %.1f m below its top and leaves it untouched" % (3.2 - stick_height))
	rig.terrain.free()


func _test_placed_bucket(params: MachineParams, soil: SoilParams) -> void:
	print("Bucket placed in the ground")
	var rig := Rig.new(params, soil)
	var flat := rig.terrain.heights.duplicate()
	# As after returning the machine to its start while the bucket was deep in a trench.
	rig.move_tip(Vector2(6.0, -2.0), -100.0, 0.0)
	rig.hold(1.0)
	_check(rig.terrain.heights == flat and rig.bucket.pushed == 0.0 and rig.bucket.removed == 0.0,
			"a bucket that jumped into the ground leaves it untouched while at rest")
	rig.move_tip(Vector2(6.0, 1.0), -100.0, 2.0)
	var highest := -INF
	for height in rig.terrain.heights:
		highest = maxf(highest, height)
	_check(highest < 1.0 and rig.balance_error(0.0) < 1e-3,
			"lifting it out digs its way up without piling soil into a spike (%.2f m high)" % highest)
	rig.terrain.free()


func _test_dig_carry_dump(params: MachineParams, soil: SoilParams) -> void:
	print("Dig, carry and dump")
	var rig := Rig.new(params, soil)
	var terrain := rig.terrain
	var bucket := rig.bucket
	var start_volume := terrain.bank_volume()
	var worst_balance := 0.0

	# Teeth in, drag toward the machine while curling, scoop up: the bottom plate stays
	# behind the cutting edge.
	rig.move_tip(Vector2(7.4, 0.2), -100.0, 0.0)
	rig.start_dig_area()
	rig.move_tip(Vector2(7.2, -0.5), -105.0, 0.6)
	rig.move_tip(Vector2(5.4, -0.35), -140.0, 2.0)
	rig.move_tip(Vector2(5.0, 0.3), -170.0, 1.2)
	var dug_area := rig.dig_area
	worst_balance = maxf(worst_balance, rig.balance_error(start_volume))
	_check(bucket.fill >= 0.95 * bucket.max_fill() and bucket.fill <= bucket.max_fill() + 1e-6,
			"a 1.8 m pass 0.5 m deep fills the bucket to its heaped capacity (%.2f of %.2f m3)"
			% [bucket.fill, bucket.max_fill()])
	_check(bucket.deposited + bucket.pushed > 0.05,
			"what no longer fits spills or is pushed ahead (%.2f m3 spilled)" % bucket.deposited)

	var outside := 0
	var raised_far := 0
	var grown := dug_area.grow(terrain.cell_size * 1.5)
	for iz in terrain.points:
		for ix in terrain.points:
			var at := terrain.point_position(ix, iz)
			var height := terrain.point_height(ix, iz)
			if height < -0.01 and not grown.has_point(at):
				outside += 1
			if height > 0.01 and not grown.grow(3.0).has_point(at):
				raised_far += 1
	_check(outside == 0 and raised_far == 0, "ground changes only where the bucket passed (%d dug, %d raised outside)"
			% [outside, raised_far])
	var trench := terrain.height_at(rig.pin_x(), -6.5)
	_check(trench < -0.35, "trench left behind is %.2f m deep" % -trench)

	rig.move_tip(Vector2(5.0, 1.8), _level_bucket_deg(params), 1.0)
	rig.hold(1.0)
	var carried := bucket.fill
	var deposited := bucket.deposited
	rig.swing_to(90.0, 2.0)
	_check(bucket.deposited - deposited < 1e-4 and absf(bucket.fill - carried) < 1e-4,
			"a level bucket carries its load without losing any (%.2f m3)" % bucket.fill)
	worst_balance = maxf(worst_balance, rig.balance_error(start_volume))

	var pin := rig.bucket_world().origin
	var pile_before := _highest_near(terrain, Vector2(pin.x, pin.z), 3.0)
	rig.turn_bucket(params.bucket_max_deg, 4.0)
	rig.hold(2.0)
	worst_balance = maxf(worst_balance, rig.balance_error(start_volume))
	_check(bucket.fill < 0.02 * bucket.max_fill(), "dumping empties the bucket (%.3f m3 left)" % bucket.fill)
	var pile := _highest_near(terrain, Vector2(pin.x, pin.z), 3.0)
	_check(pile_before < 0.01 and pile > 0.3, "the dumped load forms a pile under the bucket (%.2f m high)" % pile)
	_check(worst_balance < 1e-3, "removed = in bucket + deposited, conserved through the cycle (worst %.5f m3)"
			% worst_balance)
	_check(not rig.limited, "the scripted cycle stays within the joint limits")
	_check(absf(terrain.bank_volume() - terrain.bank_volume_recount()) < 1e-3, "running volume matches a full recount")
	_check(absf(bucket.removed - bucket.deposited - bucket.fill) < 1e-6, "taken in = poured out + still in the bucket")
	print("        taken in %.2f m3, poured out %.2f m3, pushed %.2f m3" % [bucket.removed, bucket.deposited, bucket.pushed])
	terrain.free()


func _test_bucket_back_pushes(params: MachineParams, soil: SoilParams) -> void:
	print("Back of the bucket")
	var rig := Rig.new(params, soil)
	var start_volume := rig.terrain.bank_volume()
	# Curled bucket, bottom 0.13 m into the ground, pushed away from the machine.
	rig.move_tip(Vector2(4.2, 0.5), 180.0, 0.0)
	rig.move_tip(Vector2(6.2, 0.5), 180.0, 2.0)
	_check(rig.bucket.fill < 0.01 and rig.bucket.removed < 0.01,
			"pushing with the back leaves the bucket empty (%.3f m3)" % rig.bucket.fill)
	_check(rig.bucket.pushed > 0.1, "the soil met is pushed along instead")
	var pin := rig.bucket_world().origin
	var berm := 0.0
	for k in 12:
		berm = maxf(berm, rig.terrain.height_at(pin.x, pin.z - 0.25 * k))
	_check(berm > 0.1, "a berm builds up ahead of the bucket (%.2f m)" % berm)
	_check(rig.balance_error(start_volume) < 1e-3, "pushing conserves the soil volume")
	_check(not rig.limited, "the push stays within the joint limits")
	rig.terrain.free()


## Absolute pin-to-tip angle at which the bucket opening is horizontal and faces up.
func _level_bucket_deg(params: MachineParams) -> float:
	var profile := params.bucket_profile
	var rim := profile[0]
	var tip := profile[profile.size() - 1]
	return 180.0 + rad_to_deg(atan2(rim.y - tip.y, tip.x - rim.x))


func _highest_near(terrain: Terrain, centre: Vector2, radius: float) -> float:
	var highest := -INF
	var from := terrain.nearest_point(centre.x - radius, centre.y - radius)
	var to := terrain.nearest_point(centre.x + radius, centre.y + radius)
	for iz in range(from.y, to.y + 1):
		for ix in range(from.x, to.x + 1):
			highest = maxf(highest, terrain.point_height(ix, iz))
	return highest


func _steepest_loose_slope(terrain: Terrain) -> float:
	var steepest := 0.0
	for iz in range(1, terrain.cells):
		for ix in range(1, terrain.cells):
			if terrain.point_loose(ix, iz) <= Terrain.LOOSE_EPSILON:
				continue
			var height := terrain.point_height(ix, iz)
			for k in 8:
				var drop := height - terrain.point_height(ix + Terrain.NEIGHBOUR_X[k], iz + Terrain.NEIGHBOUR_Z[k])
				var run := terrain.cell_size * (1.0 if k < 4 else sqrt(2.0))
				steepest = maxf(steepest, rad_to_deg(atan(drop / run)))
	return steepest


## Mean flank slope along a grid direction, between 20 and 80 % of the apex height.
func _flank_slope(terrain: Terrain, centre: Vector2i, direction: Vector2i, apex: float) -> float:
	var run := terrain.cell_size * Vector2(direction).length()
	var upper := Vector2.ZERO
	var lower := Vector2.ZERO
	var k := 0
	while k < 40:
		var point := centre + direction * k
		var height := terrain.point_height(point.x, point.y)
		if height <= apex * 0.8 and upper == Vector2.ZERO:
			upper = Vector2(k * run, height)
		if height <= apex * 0.2:
			lower = Vector2(k * run, height)
			break
		k += 1
	return rad_to_deg(atan((upper.y - lower.y) / maxf(lower.x - upper.x, 1e-6)))


func _hold(excavator: Excavator, keys: Array, duration: float) -> void:
	for key in keys:
		_send_key(key, true)
	for i in int(round(duration / DT)):
		excavator._physics_process(DT)
		excavator.terrain.relax(Terrain.RELAX_VISITS_PER_TICK)
	for key in keys:
		_send_key(key, false)
	for i in int(round(0.5 / DT)):
		excavator._physics_process(DT)


static func _send_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, message: String) -> void:
	_runner.call("_check", condition, message)


func _near(value: float, expected: float, tolerance_ratio: float, message: String) -> void:
	_runner.call("_near", value, expected, tolerance_ratio, message)


## Machine at the origin facing -Z on flat ground, arm driven by tooth tip targets.
class Rig:
	var params: MachineParams
	var terrain := Terrain.new()
	var bucket := BucketSoil.new()
	var swing := 0.0
	var angles := Vector3.ZERO
	## Horizontal bounds (x, z) of the bucket while it is in the ground.
	var dig_area := Rect2()
	## True once a target needed a joint beyond its limit.
	var limited := false
	var _tracking := false

	func _init(p_params: MachineParams, soil: SoilParams) -> void:
		params = p_params
		terrain.soil = soil
		terrain.setup(160, 0.25)
		bucket.setup(params, soil)

	## Moves the tip in a straight line to a side-plane point while turning the bucket to
	## an absolute pin-to-tip angle. Zero duration jumps there.
	func move_tip(tip: Vector2, bucket_absolute_deg: float, duration: float) -> void:
		var from_tip := current_tip()
		var from_angle := rad_to_deg(Vector2.RIGHT.rotated(deg_to_rad(angles.x + angles.y + angles.z)).angle())
		if duration <= 0.0:
			_set_angles(ArmGeometry.pose_for_tip(params, tip, bucket_absolute_deg))
			bucket.reset_motion()
			return
		var turn := wrapf(bucket_absolute_deg - from_angle, -180.0, 180.0)
		var steps := int(round(duration / DT))
		for i in steps:
			var t := float(i + 1) / steps
			_set_angles(ArmGeometry.pose_for_tip(params, from_tip.lerp(tip, t), from_angle + turn * t))
			_tick()

	func swing_to(swing_deg: float, duration: float) -> void:
		var from := swing
		var steps := int(round(duration / DT))
		for i in steps:
			swing = lerpf(from, swing_deg, float(i + 1) / steps)
			_tick()

	func turn_bucket(bucket_deg: float, duration: float) -> void:
		var from := angles.z
		var steps := int(round(duration / DT))
		for i in steps:
			angles.z = lerpf(from, bucket_deg, float(i + 1) / steps)
			_tick()

	func hold(duration: float) -> void:
		for i in int(round(duration / DT)):
			_tick()

	func start_dig_area() -> void:
		_tracking = false

	func current_tip() -> Vector2:
		return ArmGeometry.arm_points(params, angles.x, angles.y, angles.z)["tip"]

	func bucket_world() -> Transform3D:
		return ArmGeometry.bucket_transform(params, swing, angles.x, angles.y, angles.z)

	func tip_world() -> Vector3:
		return bucket_world() * Vector3(0.0, 0.0, -params.bucket_tip_radius)

	## Lateral position of the arm plane when the turret faces forward.
	func pin_x() -> float:
		return params.boom_foot.x

	## Soil volume change as loose volume, plus the bucket load: zero when conserved.
	func balance_error(start_volume: float) -> float:
		return absf((terrain.bank_volume() - start_volume + bucket.bank_fill()) * (1.0 + terrain.soil.swell()))

	func _set_angles(pose: Variant) -> void:
		if pose == null:
			limited = true
			return
		var wanted: Vector3 = pose
		angles = Vector3(clampf(wanted.x, params.boom_min_deg, params.boom_max_deg),
				clampf(wanted.y, params.stick_min_deg, params.stick_max_deg),
				clampf(wanted.z, params.bucket_min_deg, params.bucket_max_deg))
		limited = limited or not angles.is_equal_approx(wanted)

	func _tick() -> void:
		var xform := bucket_world()
		bucket.step(terrain, xform, DT)
		terrain.relax(Terrain.RELAX_VISITS_PER_TICK)
		var low := INF
		var corners := Rect2()
		var first := true
		for point in params.bucket_profile:
			for x in [-params.bucket_width * 0.5, params.bucket_width * 0.5]:
				var corner: Vector3 = xform * Vector3(x, point.y, -point.x)
				low = minf(low, corner.y)
				var at := Vector2(corner.x, corner.z)
				corners = Rect2(at, Vector2.ZERO) if first else corners.expand(at)
				first = false
		if low < 0.02:
			dig_area = dig_area.merge(corners) if _tracking else corners
			_tracking = true
