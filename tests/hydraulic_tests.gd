extends RefCounted
## Phase 4 checks: cylinders and swing against the manufacturer data, pump flow and power
## sharing, engine speed under load, mass properties and tipping load, and on a scene
## instance the soil resisting the bucket, stalling, the machine lifting on its bucket, and
## the teeth digging without lifting it.
## Driven by run_tests.gd, which owns the check counters.

const DT := 1.0 / 120.0

var _runner: SceneTree


func _init(runner: SceneTree) -> void:
	_runner = runner


func run(params: MachineParams) -> void:
	_test_cylinder_behaviour()
	_test_function_times(params)
	_test_digging_forces(params)
	_test_swing(params)
	_test_flow_sharing(params)
	_test_power_and_engine(params)
	_test_mass_properties(params)
	_test_side_tipping_load(params)


func run_scene(excavator: Excavator) -> void:
	var terrain := Terrain.new()
	terrain.layout = Terrain.Layout.FLAT
	terrain.cells = 96
	terrain.chunk_cells = 32
	terrain.tile_cells = 32
	excavator.get_parent().add_child(terrain)
	excavator.terrain = terrain
	excavator.controls.pattern = ControlInput.Pattern.ISO
	_test_pressing_lifts_the_front(excavator, terrain)
	_test_teeth_dig_without_lifting(excavator, terrain)
	_test_stall_drops_revs(excavator, terrain)
	_test_pressing_leaves_no_spikes(excavator, terrain)
	_test_loose_soil_gives_way(excavator, terrain)
	excavator.terrain = null
	excavator.bucket_soil.clear()
	excavator.reset_pose()
	excavator.return_to_start()
	terrain.queue_free()


func _test_cylinder_behaviour() -> void:
	print("Hydraulic cylinder")
	var cylinder := HydraulicCylinder.new()
	cylinder.setup(func(a: float) -> float: return 1.0 + a * 0.01, -10.0, 90.0, 0.1, 0.05, 1,
			0.5, 0.4, 0.3, 0.2, 0.0, 1.0, 35.0e6)
	cylinder.set_angle(0.0)
	_run(cylinder, 1.0, 0.15)
	_check(cylinder.rod_speed > 0.2 and cylinder.rod_speed < 0.3,
			"half the spool ramp gives about half speed (%.2f m/s)" % cylinder.rod_speed)
	_run(cylinder, 1.0, 0.2)
	_check(is_equal_approx(cylinder.rod_speed, 0.5) and is_equal_approx(cylinder.speed_fraction(), 1.0),
			"full rod speed once the spool is open")
	_check(absf(cylinder.speed_deg_s - 50.0) < 0.01, "rod speed turns into joint speed through the lever (%.2f deg/s)"
			% cylinder.speed_deg_s)
	_run(cylinder, 0.0, 0.1)
	_check(cylinder.rod_speed > 0.2, "speed does not drop instantly on release")
	_run(cylinder, 0.0, 0.2)
	_check(is_zero_approx(cylinder.rod_speed), "function stops once the spool is closed")
	_run(cylinder, 1.0, 0.5)
	_run(cylinder, -1.0, DT)
	_check(cylinder.rod_speed > 0.0, "reversal brakes before moving the other way")
	_run(cylinder, 1.0, 10.0)
	_check(is_equal_approx(cylinder.angle_deg, 90.0) and cylinder.at_limit() and is_zero_approx(cylinder.rod_speed),
			"the rod stops exactly at the end of the stroke")
	_check(cylinder.pushing_limit(1.0) and not cylinder.pushing_limit(-1.0) and not cylinder.pushing_limit(0.0),
			"only a command toward the end stop pushes against it (relief valve)")
	_check(absf(cylinder.angle_at_length(cylinder.length_at_angle(37.3)) - 37.3) < 1e-3
			and absf(cylinder.lever(40.0) - rad_to_deg(0.01)) < 1e-3, "length and angle convert both ways, lever in m/rad")
	var retracting := HydraulicCylinder.new()
	retracting.setup(func(a: float) -> float: return 2.0 - a * 0.01, 0.0, 90.0, 0.1, 0.05, 2,
			0.5, 0.5, 0.01, 0.01, 0.05, 0.3, 35.0e6)
	_check(retracting.inflow_area(1.0) == retracting.rod_area and retracting.inflow_area(-1.0) == retracting.cap_area
			and is_equal_approx(retracting.cap_area, PI * 0.005), "a joint that shortens its cylinder feeds the rod side")
	retracting.set_angle(89.0)
	_run(retracting, 1.0, 0.05)
	_check(retracting.rod_speed < 0.25, "end-of-stroke cushion slows the rod (%.2f m/s)" % retracting.rod_speed)
	_check(retracting.pressure_to_move(-1000.0, 1.0) > 0.0 and is_zero_approx(retracting.pressure_to_move(1000.0, 1.0)),
			"a load against the motion needs pressure, a load along it does not")


func _test_function_times(params: MachineParams) -> void:
	print("Unloaded full-stroke function times")
	var system := HydraulicSystem.new()
	system.setup(params)
	_near(_stroke_time(system.boom, 1.0), params.ref_boom_raise_time, 0.10, "boom raise")
	_near(_stroke_time(system.boom, -1.0), params.ref_boom_lower_time, 0.10, "boom lower")
	_near(_stroke_time(system.stick, 1.0), params.ref_stick_out_time, 0.10, "stick out")
	_near(_stroke_time(system.stick, -1.0), params.ref_stick_in_time, 0.10, "stick in")
	_near(_stroke_time(system.bucket, 1.0), params.ref_bucket_dump_time, 0.10, "bucket dump")
	_near(_stroke_time(system.bucket, -1.0), params.ref_bucket_curl_time, 0.10, "bucket curl")


func _test_digging_forces(params: MachineParams) -> void:
	print("Digging forces at the relief pressure (ISO 6015)")
	var system := HydraulicSystem.new()
	system.setup(params)
	_near(_largest_torque(system.bucket, -1.0) / params.bucket_tip_radius / 1000.0,
			params.ref_bucket_digging_force_kn, 0.15, "bucket digging force (kN)")
	_near(_largest_torque(system.stick, -1.0) / (params.stick_length + params.bucket_tip_radius) / 1000.0,
			params.ref_stick_digging_force_kn, 0.15, "stick digging force (kN)")


func _test_swing(params: MachineParams) -> void:
	print("Swing inertia, speed and drift")
	var statics := ArmStatics.new()
	statics.setup(params)
	var compact := statics.swing_inertia(_doosan_swing_pose(params, statics), 0.0)
	var swing := SwingDrive.new()
	swing.setup(params)
	var time := 0.0
	while swing.angle_deg < 1080.0 and time < 60.0:
		_swing_step(swing, 1.0, compact)
		time += DT
	_check(time >= 15.5 and time <= 17.5, "three full turns in %.1f s (Doosan test: 15.5 to 17.5 s)" % time)
	var drift := _drift_after_release(swing, compact)
	# The Doosan marks sit on the upper structure and the undercarriage; take the frame edge.
	var at_marks := deg_to_rad(drift) * params.upper_width * 0.5
	_check(at_marks < 1.2 and drift > 5.0,
			"released at full speed the turret coasts %.0f deg, %.2f m at the upper frame edge (Doosan: under 1.2 m)"
			% [drift, at_marks])
	var loaded := statics.swing_inertia(statics.joint_frames(0.0, 0.0, -40.0, -60.0), 1.19 * 1510.0)
	var loaded_drift := _drift_after_release(swing, loaded)
	_check(loaded > 2.0 * compact and loaded_drift > 1.8 * drift,
			"a full bucket at reach coasts further: %.0f deg for %.0f kg m2 against %.0f kg m2" % [loaded_drift, loaded, compact])


func _test_flow_sharing(params: MachineParams) -> void:
	print("Pump flow sharing")
	var system := HydraulicSystem.new()
	system.setup(params)
	for cylinder in system.cylinders:
		cylinder.set_angle((cylinder.min_deg + cylinder.max_deg) * 0.5)
	var single := _planned_speeds(system, 1.0, 0.0, 0.0, 0.0)
	_check(is_equal_approx(system.flow_share, 1.0), "one function alone gets all the flow it asks for")
	var stick_alone := _planned_speeds(system, 0.0, -1.0, 0.0, 0.0)
	var bucket_alone := _planned_speeds(system, 0.0, 0.0, -1.0, 0.0)
	var together := _planned_speeds(system, 1.0, -1.0, -1.0, 0.0)
	var ratios := Vector3(together.x / single.x, together.y / stick_alone.y, together.z / bucket_alone.z)
	_check(ratios.x < 0.6 and is_equal_approx(ratios.x, ratios.y) and is_equal_approx(ratios.y, ratios.z),
			"boom raise, stick in and curl together each run at %.0f %% of their speed alone" % [100.0 * ratios.x])
	var with_swing := _planned_speeds(system, 1.0, 0.0, 0.0, 1.0)
	_check(with_swing.x < 0.8 * single.x and system.swing_target() < 0.8 * params.swing_speed_deg_s(),
			"swinging while raising the boom slows both (boom at %.0f %%)" % [100.0 * with_swing.x / single.x])


func _test_power_and_engine(params: MachineParams) -> void:
	print("Pump power and engine speed")
	var system := HydraulicSystem.new()
	system.setup(params)
	system.boom.set_angle(0.0)
	var controls := ControlInput.new()
	controls.boom = 1.0
	for i in int(3.0 / DT):
		_hydraulic_step(system, controls, 12.0e6, false)
		system.boom.set_angle(0.0)
	_check(is_equal_approx(system.power_share, 1.0), "a boom raise holding the arm at 120 bar is not held back by the pump power")
	for i in int(2.0 / DT):
		_hydraulic_step(system, controls, 0.0, false)
		system.boom.set_angle(0.0)
	var working := system.engine_rpm
	_check(absf(working - params.engine_working_rpm) < 60.0, "a moved lever brings the engine to working speed (%.0f rpm)" % working)
	_hydraulic_step(system, controls, 30.0e6, false)
	_check(system.power_share < 0.8, "a boom raise at 300 bar slows to the pump power (%.0f %%)" % [100.0 * system.power_share])
	for i in int(1.0 / DT):
		_hydraulic_step(system, controls, 0.0, true)
		system.boom.set_angle(0.0)
	_check(is_zero_approx(system.boom.rod_speed) and system.relief_open(controls),
			"a stalled cylinder stops and its relief valve opens")
	_check(working - system.engine_rpm > 150.0,
			"the engine sags while the pumps push over the relief (%.0f rpm lost)" % (working - system.engine_rpm))


func _test_mass_properties(params: MachineParams) -> void:
	print("Mass properties")
	var statics := ArmStatics.new()
	statics.setup(params)
	var rest := statics.joint_frames(0.0, params.rest_boom_deg, params.rest_stick_deg, params.rest_bucket_deg)
	_check(statics.center_of_mass(rest, 0.0).distance_to(params.center_of_mass) < 0.001,
			"the arm at rest gives the machine centre of mass")
	var out := statics.joint_frames(0.0, 0.0, params.stick_max_deg, 0.0)
	var forward := statics.center_of_mass(rest, 0.0).z - statics.center_of_mass(out, 0.0).z
	var loaded := statics.center_of_mass(rest, 0.0).z - statics.center_of_mass(out, 1800.0).z
	_check(forward > 0.2 and loaded > forward + 0.3,
			"reaching out moves the centre of mass %.2f m forward, %.2f m with a full bucket" % [forward, loaded])
	var system := HydraulicSystem.new()
	system.setup(params)
	system.boom.set_angle(params.rest_boom_deg)
	var holding := system.boom.holding_pressure(statics.gravity_torques(rest, 0.0, Vector3.DOWN * ArmStatics.GRAVITY).x)
	_check(holding > 5.0e6 and holding < 20.0e6, "the boom cylinders hold the arm at rest at %.0f bar" % (holding / 1.0e5))


func _test_side_tipping_load(params: MachineParams) -> void:
	print("Tipping load over the side")
	var statics := ArmStatics.new()
	statics.setup(params)
	var ground := GroundSupport.new()
	ground.setup(params)
	var pin := Vector2(params.ref_side_tipping_radius, 0.0)
	var angles: Vector3 = ArmGeometry.pose_for_tip(params, pin + Vector2(params.bucket_tip_radius, 0.0), 0.0)
	# Swung to the right, the arm over the right track; the lift chart counts no bucket.
	var frames := statics.joint_frames(90.0, angles.x, angles.y, angles.z)
	var bucket_center: Vector3 = statics.part_centers(frames)[2]
	var mass := params.operating_mass - params.bucket_mass
	var center := (statics.center_of_mass(frames, 0.0) * params.operating_mass - bucket_center * params.bucket_mass) / mass
	var edge := ground.tip_pivot(GroundSupport.Edge.RIGHT).x
	var tipping := mass * (edge - center.x) / (frames[3].origin.x - edge)
	_near(tipping, params.ref_side_tipping_load_kg, 0.15, "load at the bucket pin, 7.5 m out, that tips the machine (kg)")


func _test_pressing_lifts_the_front(excavator: Excavator, terrain: Terrain) -> void:
	print("Pressing the bucket on the ground")
	_reset(excavator, terrain)
	_pose_bucket_above_ground(excavator, 6.5, -165.0, 0.05)
	var slowed := false
	_press(excavator, [KEY_I], true)
	for i in int(1.0 / DT):
		excavator._physics_process(DT)
		terrain.relax(Terrain.RELAX_VISITS_PER_TICK)
		slowed = slowed or (excavator.boom_joint.speed_share < 0.5
				and is_equal_approx(excavator.boom_joint.pressure, excavator.boom_joint.relief_pressure))
	_press(excavator, [KEY_I], false)
	var ground := excavator.ground
	var lift := ground.tip_deg()
	_check(lift > 2.0 and ground.tip_edge == GroundSupport.Edge.REAR and not excavator.boom_joint.stalled,
			"lowering the boom on the back of the bucket lifts the front of the machine (%.1f deg)" % lift)
	_check(slowed, "the boom pushes on its relief valve while the machine picks up speed, slowed down to it")
	var lowest := _lowest_ground(terrain)
	_check(lowest > -0.12, "the bucket stays on firm ground instead of sinking in (%.2f m)" % lowest)
	# Released, the machine coasts on a little, settles back on its bucket, then nothing moves.
	_hold(excavator, [], 1.0)
	lift = ground.tip_deg()
	lowest = _lowest_ground(terrain)
	_hold(excavator, [], 1.0)
	_check(lift > 2.0 and absf(ground.tip_deg() - lift) < 0.5,
			"released, the machine settles and stays up on its bucket (%.1f deg)" % ground.tip_deg())
	_hold(excavator, [KEY_K], 2.0)
	_check(is_zero_approx(ground.tip_angle) and _lowest_ground(terrain) > lowest - 0.02,
			"raising the boom sets the machine back down without digging (%.1f deg, %.3f m then %.3f m)"
			% [ground.tip_deg(), lowest, _lowest_ground(terrain)])


func _test_teeth_dig_without_lifting(excavator: Excavator, terrain: Terrain) -> void:
	print("Digging with the teeth")
	# The same short push of the boom at full speed, teeth first then on the back of the bucket.
	_reset(excavator, terrain)
	_pose_bucket_above_ground(excavator, 6.5, -90.0, 0.0)
	var teeth_lift := _highest_lift(excavator, [[[KEY_I], 0.25]])
	var teeth := -_lowest_ground(terrain)
	_reset(excavator, terrain)
	_pose_bucket_above_ground(excavator, 6.5, -165.0, 0.0)
	_highest_lift(excavator, [[[KEY_I], 0.25]])
	var back := -_lowest_ground(terrain)
	_check(teeth > 0.15 and teeth > 5.0 * back and teeth_lift < 0.1,
			"pushed down, the teeth go %.2f m into ground in place without lifting the machine, the back of the bucket %.2f m"
			% [teeth, back])
	# Teeth set in, then stick in and bucket curled together, as a pass is dug.
	_reset(excavator, terrain)
	_pose_bucket_above_ground(excavator, 7.0, -75.0, 0.05)
	var pass_lift := _highest_lift(excavator, [[[KEY_I], 0.25], [[KEY_S, KEY_J], 2.5]])
	_check(pass_lift < 0.5 and excavator.bucket_soil.fill > 0.5,
			"a digging pass fills %.2f m3 without lifting the machine (%.1f deg at most)"
			% [excavator.bucket_soil.fill, pass_lift])
	_settle(excavator)


func _test_stall_drops_revs(excavator: Excavator, terrain: Terrain) -> void:
	print("Stalling in the ground")
	_reset(excavator, terrain)
	# Bucket curled teeth down, a metre under ground in place, its back to the far side.
	var angles: Vector3 = ArmGeometry.pose_for_tip(excavator.params, Vector2(6.5, -1.3), -90.0)
	excavator.set_pose(0.0, angles.x, angles.y, angles.z)
	var start := excavator.stick_joint.angle_deg
	_press(excavator, [KEY_W], true)
	var relief := false
	for i in int(2.5 / DT):
		excavator._physics_process(DT)
		relief = excavator.hydraulics.relief_open(excavator.controls)
	var rpm := excavator.hydraulics.engine_rpm
	_press(excavator, [KEY_W], false)
	_check(excavator.stick_joint.stalled and relief and absf(excavator.stick_joint.angle_deg - start) < 3.0,
			"pushing the back of a buried bucket into the ground stalls the stick (moved %.1f deg)"
			% absf(excavator.stick_joint.angle_deg - start))
	_check(excavator.params.engine_working_rpm - rpm > 150.0, "the engine sags while stalled (%.0f rpm)" % rpm)
	_settle(excavator)


func _test_pressing_leaves_no_spikes(excavator: Excavator, terrain: Terrain) -> void:
	print("No soil spikes when pressing into the ground")
	var worst := 0.0
	for pose in [[4.0, 0.9, -90.0], [6.5, 0.3, -90.0], [6.5, 0.5, -200.0]]:
		_reset(excavator, terrain)
		var angles: Vector3 = ArmGeometry.pose_for_tip(excavator.params, Vector2(pose[0], pose[1]), pose[2])
		excavator.set_pose(0.0, angles.x, angles.y, angles.z)
		var reference := terrain.bank_volume()
		_hold(excavator, [KEY_I], 3.0)
		for iz in terrain.points:
			for ix in terrain.points:
				worst = maxf(worst, terrain.point_height(ix, iz))
		var error := (terrain.bank_volume() - reference) * (1.0 + terrain.soil.swell()) + excavator.bucket_soil.fill
		_check(absf(error) < 1e-3, "soil volume is conserved while pressing (%.5f m3)" % error)
	_check(worst < 1.0, "the boom pushed down in three bucket attitudes piles no spike (highest %.2f m)" % worst)


func _test_loose_soil_gives_way(excavator: Excavator, terrain: Terrain) -> void:
	print("Loose soil")
	_reset(excavator, terrain)
	var bank := _teeth_penetration(excavator, terrain)
	_reset(excavator, terrain)
	# A loose layer in front of the machine only, so the tracks stay on ground in place.
	for iz in terrain.points:
		for ix in terrain.points:
			var at := terrain.point_position(ix, iz)
			if absf(at.x) < 2.5 and at.y < -4.0 and at.y > -9.0:
				terrain.add_loose(ix, iz, 0.6 * terrain.cell_size * terrain.cell_size)
	var loose := _teeth_penetration(excavator, terrain)
	_check(loose > bank + 0.1, "teeth pushed down go %.2f m into loose soil against %.2f m into ground in place"
			% [loose, bank])


## Teeth set on the surface, boom pushed down: how deep the teeth get below the start surface.
func _teeth_penetration(excavator: Excavator, terrain: Terrain) -> float:
	var surface := terrain.height_at(excavator.params.boom_foot.x, -6.5)
	var angles: Vector3 = ArmGeometry.pose_for_tip(excavator.params, Vector2(6.5, surface), -95.0)
	excavator.set_pose(0.0, angles.x, angles.y, angles.z)
	_hold(excavator, [KEY_I], 0.4)
	var tip := excavator.bucket.global_transform * Vector3(0.0, 0.0, -excavator.params.bucket_tip_radius)
	return surface - tip.y


func _reset(excavator: Excavator, terrain: Terrain) -> void:
	terrain.rebuild()
	excavator.bucket_soil.clear()
	excavator.place(Vector2.ZERO, 0.0)
	excavator.reset_pose()


## Poses the arm with the bucket at an absolute angle, its lowest point a gap above flat ground.
func _pose_bucket_above_ground(excavator: Excavator, reach: float, bucket_absolute_deg: float, gap: float) -> void:
	var p := excavator.params
	var lowest := INF
	for point in p.bucket_profile:
		lowest = minf(lowest, (point.rotated(deg_to_rad(bucket_absolute_deg))).y)
	var tip_height := gap - lowest + p.bucket_tip_radius * sin(deg_to_rad(bucket_absolute_deg))
	var angles: Vector3 = ArmGeometry.pose_for_tip(p, Vector2(reach, tip_height), bucket_absolute_deg)
	_check(angles.z >= p.bucket_min_deg and angles.y <= p.stick_max_deg and angles.y >= p.stick_min_deg,
			"test pose within the joint limits")
	excavator.set_pose(0.0, angles.x, angles.y, angles.z)


## Holds each group of keys for its duration in turn. Returns the highest lift reached (deg).
func _highest_lift(excavator: Excavator, phases: Array) -> float:
	var highest := 0.0
	for phase in phases:
		_press(excavator, phase[0], true)
		for i in int(round(phase[1] / DT)):
			excavator._physics_process(DT)
			excavator.terrain.relax(Terrain.RELAX_VISITS_PER_TICK)
			highest = maxf(highest, excavator.ground.tip_deg())
		_press(excavator, phase[0], false)
	return highest


func _lowest_ground(terrain: Terrain) -> float:
	var lowest := INF
	for iz in terrain.points:
		for ix in terrain.points:
			lowest = minf(lowest, terrain.point_height(ix, iz))
	return lowest


func _settle(excavator: Excavator) -> void:
	for i in int(1.0 / DT):
		excavator._physics_process(DT)


func _hold(excavator: Excavator, keys: Array, duration: float) -> void:
	_press(excavator, keys, true)
	for i in int(round(duration / DT)):
		excavator._physics_process(DT)
		if excavator.terrain != null:
			excavator.terrain.relax(Terrain.RELAX_VISITS_PER_TICK)
	_press(excavator, keys, false)


func _press(_excavator: Excavator, keys: Array, pressed: bool) -> void:
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _run(cylinder: HydraulicCylinder, command: float, duration: float) -> void:
	for i in int(round(duration / DT)):
		cylinder.update_spool(command, DT)
		cylinder.advance(cylinder.free_speed(), DT)


func _stroke_time(cylinder: HydraulicCylinder, command: float) -> float:
	cylinder.stop()
	cylinder.set_angle(cylinder.min_deg if command > 0.0 else cylinder.max_deg)
	var goal := cylinder.max_deg if command > 0.0 else cylinder.min_deg
	var time := 0.0
	while absf(cylinder.angle_deg - goal) > 1e-3 and time < 30.0:
		cylinder.update_spool(command, DT)
		cylinder.advance(cylinder.free_speed(), DT)
		time += DT
	return time


func _largest_torque(cylinder: HydraulicCylinder, direction: float) -> float:
	var largest := 0.0
	var angle := cylinder.min_deg
	while angle <= cylinder.max_deg:
		cylinder.set_angle(angle)
		largest = maxf(largest, cylinder.max_torque(direction))
		angle += 0.5
	return largest


## Doosan swing test posture: stick in, bucket curled, bucket 1.5 m above the ground.
func _doosan_swing_pose(params: MachineParams, statics: ArmStatics) -> Array[Transform3D]:
	var best: Array[Transform3D] = []
	var best_gap := INF
	var boom := params.boom_min_deg
	while boom <= params.boom_max_deg:
		var frames := statics.joint_frames(0.0, boom, params.stick_min_deg, params.bucket_min_deg)
		var lowest := INF
		for point in params.bucket_profile:
			lowest = minf(lowest, (frames[3] * ArmGeometry.to_local(point)).y)
		if absf(lowest - 1.5) < best_gap:
			best_gap = absf(lowest - 1.5)
			best = frames
		boom += 0.5
	return best


func _swing_step(swing: SwingDrive, command: float, inertia: float) -> void:
	swing.update_spool(command, DT)
	swing.advance(swing.free_speed(), inertia, 0.0, DT)


func _drift_after_release(swing: SwingDrive, inertia: float) -> float:
	swing.stop()
	swing.angle_deg = 0.0
	for i in int(6.0 / DT):
		_swing_step(swing, 1.0, inertia)
	var start := swing.angle_deg
	while swing.speed_deg_s > 0.0:
		_swing_step(swing, 0.0, inertia)
	return swing.angle_deg - start


func _planned_speeds(system: HydraulicSystem, boom: float, stick: float, bucket: float, swing: float) -> Vector3:
	var controls := ControlInput.new()
	controls.boom = boom
	controls.stick = stick
	controls.bucket = bucket
	controls.swing = swing
	system.stop()
	system.update_spools(controls, 1.0)
	system.plan()
	return Vector3(system.planned_speed(0), system.planned_speed(1), system.planned_speed(2)).abs()


func _hydraulic_step(system: HydraulicSystem, controls: ControlInput, boom_pressure: float, stalled: bool) -> void:
	system.update_spools(controls, DT)
	system.plan()
	system.boom.pressure = boom_pressure
	system.boom.stalled = stalled
	system.finish(50000.0, 0.0, DT)


func _check(condition: bool, message: String) -> void:
	_runner.call("_check", condition, message)


func _near(value: float, expected: float, tolerance_ratio: float, message: String) -> void:
	_runner.call("_near", value, expected, tolerance_ratio, message)
