extends RefCounted
## Phase 2 checks: heightfield, track drive and machine resting on the ground.
## Driven by run_tests.gd, which owns the check counters.

const DT := 1.0 / 120.0
const PROBE_PLANE := Vector3(0.12, 0.8, -0.2)

var _runner: SceneTree


func _init(runner: SceneTree) -> void:
	_runner = runner


func run(params: MachineParams) -> void:
	_test_heightfield_sampling()
	var ground := Terrain.new()
	ground.setup(512, 0.25)
	TestGround.build(ground)
	_test_test_ground_shape(ground)
	_test_travel_speeds(params)
	_test_spin_and_pivot(params)
	_test_climb_ramp_and_crests(params, ground)
	_test_gradeability(params, ground)
	_test_side_bank(params, ground)
	ground.free()


## Keyboard travel mode through the real input path, on a scene instance.
func run_scene(excavator: Excavator) -> void:
	print("Travel mode from the keyboard")
	excavator.return_to_start()
	var arm_before := [excavator.boom_joint.angle_deg, excavator.stick_joint.angle_deg, excavator.swing_joint.angle_deg]
	_hold(excavator, [KEY_SPACE, KEY_W], 1.0)
	var arm_after := [excavator.boom_joint.angle_deg, excavator.stick_joint.angle_deg, excavator.swing_joint.angle_deg]
	_check(arm_before == arm_after, "travel mode leaves the arm and swing still")
	_check(excavator.ground.heading < -0.05, "left track forward alone turns the machine right (%.1f deg)"
			% rad_to_deg(excavator.ground.heading))
	_check(excavator.travel.left_distance > 0.2 and is_zero_approx(excavator.travel.right_distance),
			"only the left track ran")
	excavator.return_to_start()
	_hold(excavator, [KEY_SPACE, KEY_W, KEY_I], 2.0)
	_check(excavator.position.z < -1.0 and absf(excavator.position.x) < 0.01,
			"both tracks forward drive straight ahead (%.2f m)" % -excavator.position.z)
	_check(excavator.transform.basis.is_equal_approx(Basis.IDENTITY), "machine stays level on flat ground")
	excavator.return_to_start()


## Small terrain with collision, added to the tree so physics registers it.
func add_collision_probe(root: Node) -> Terrain:
	var probe := Terrain.new()
	probe.layout = Terrain.Layout.FLAT
	probe.cells = 64
	probe.chunk_cells = 32
	probe.tile_cells = 32
	root.add_child(probe)
	probe.apply(Rect2(-10.0, -10.0, 20.0, 20.0), _probe_height)
	probe.commit()
	return probe


func check_collision_probe(probe: Terrain) -> void:
	print("Terrain collision tiles")
	var space := probe.get_world_3d().direct_space_state
	var worst := 0.0
	var hits := 0
	for point in [Vector2(-7.9, -7.9), Vector2(-3.3, 2.1), Vector2(0.0, 0.0), Vector2(0.1, -0.05), Vector2(5.2, 7.7)]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, 50.0, point.y), Vector3(point.x, -50.0, point.y))
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		hits += 1
		worst = maxf(worst, absf(hit["position"].y - probe.height_at(point.x, point.y)))
	_check(hits == 5 and worst < 0.01, "raycasts hit the collision tiles at the heightfield height (%d hits, %.4f m)"
			% [hits, worst])


func _test_heightfield_sampling() -> void:
	print("Heightfield")
	var terrain := Terrain.new()
	terrain.setup(64, 0.25)
	terrain.apply(Rect2(-10.0, -10.0, 20.0, 20.0), _probe_height)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	for i in 200:
		var x := rng.randf_range(-8.0, 8.0)
		var z := rng.randf_range(-8.0, 8.0)
		worst = maxf(worst, absf(terrain.height_at(x, z) - _probe_height(x, z, 0.0)))
	_check(worst < 1e-4, "bilinear sampling reproduces a plane (%.6f m)" % worst)
	_check(is_equal_approx(terrain.height_at(30.0, 0.0), terrain.height_at(8.0, 0.0)),
			"sampling outside the grid clamps to its edge")
	terrain.free()


func _test_test_ground_shape(terrain: Terrain) -> void:
	print("Test ground")
	var ramp := (terrain.height_at(-18.0, 0.0) - terrain.height_at(-12.0, 0.0)) / 6.0
	_near(ramp, TestGround.RAMP_SLOPE, 0.01, "ramp slope")
	_near(terrain.height_at(-24.0, 0.0), TestGround.PLATEAU_HEIGHT, 0.001, "plateau height")
	var descent := (terrain.height_at(-29.0, 0.0) - terrain.height_at(-32.0, 0.0)) / 3.0
	_near(descent, TestGround.DESCENT_SLOPE, 0.01, "descent slope")
	var bank := (terrain.height_at(5.0, 24.0) - terrain.height_at(5.0, 20.0)) / 4.0
	_near(bank, TestGround.BANK_SLOPE, 0.01, "side bank slope")
	var flat := true
	for point in [Vector2.ZERO, Vector2(0.1, -15.0), Vector2(8.5, -4.0), Vector2(8.5, 5.0)]:
		flat = flat and is_zero_approx(terrain.height_at(point.x, point.y))
	_check(flat, "start area, stakes and truck stand on flat ground")


func _test_travel_speeds(params: MachineParams) -> void:
	print("Travel speeds on flat ground")
	for high in [false, true]:
		var machine := _machine(params, null, Vector2.ZERO, 0.0)
		machine.travel.high_speed = high
		_drive(machine, null, 1.0, 1.0, 3.0)
		var start := machine.ground.position
		_drive(machine, null, 1.0, 1.0, 5.0)
		var speed_kmh := start.distance_to(machine.ground.position) / 5.0 * 3.6
		var expected := params.travel_speed_high_kmh if high else params.travel_speed_low_kmh
		_near(speed_kmh, expected, 0.01, "%s range speed (km/h)" % ("high" if high else "low"))
		_check(machine.ground.position.z < 0.0 and absf(machine.ground.position.x) < 1e-6
				and is_zero_approx(machine.ground.heading), "drives straight toward the front")
	var reversing := _machine(params, null, Vector2.ZERO, 0.0)
	_drive(reversing, null, -1.0, -1.0, 2.0)
	_check(reversing.ground.position.z > 0.5, "both levers back reverse the machine")


func _test_spin_and_pivot(params: MachineParams) -> void:
	print("Steering")
	var spin := _machine(params, null, Vector2.ZERO, 0.0)
	_drive(spin, null, 1.0, -1.0, 6.0)
	var drift := Vector2(spin.ground.position.x, spin.ground.position.z).length()
	_check(spin.ground.heading < -1.0 and drift < 0.001,
			"counter-rotation turns right on the spot (%.0f deg, drift %.4f m)" % [rad_to_deg(spin.ground.heading), drift])
	print("        full counter-rotation in %.1f s at low speed" % (TAU / absf(spin.travel.yaw_rate())))
	var pivot := _machine(params, null, Vector2.ZERO, 0.0)
	_drive(pivot, null, 1.0, 0.0, 3.0)
	_check(pivot.ground.heading < -0.2 and pivot.ground.position.z < -0.5,
			"left track alone moves forward while turning right")


func _test_climb_ramp_and_crests(params: MachineParams, terrain: Terrain) -> void:
	print("Ramp, plateau and 70 % descent")
	var machine := _machine(params, terrain, Vector2(-4.0, 0.0), 90.0)
	machine.travel.high_speed = true
	var com := params.center_of_mass
	var deepest := 0.0
	var ramp_pitch := NAN
	var plateau_height := NAN
	var steepest_nose_down := 0.0
	var largest_step := 0.0
	var previous_pitch := machine.ground.pitch_deg()
	var steps := 0
	while machine.ground.position.x > -40.0 and steps < 40 * 120:
		machine.travel.step(1.0, 1.0, DT)
		machine.ground.advance(terrain, machine.travel, com, DT)
		steps += 1
		var x := machine.ground.position.x
		var pitch := machine.ground.pitch_deg()
		largest_step = maxf(largest_step, absf(pitch - previous_pitch))
		previous_pitch = pitch
		steepest_nose_down = minf(steepest_nose_down, pitch)
		if steps % 4 == 0:
			deepest = maxf(deepest, machine.ground.max_penetration(terrain))
		if absf(x + 15.0) < 0.05:
			ramp_pitch = pitch
		if absf(x + 24.0) < 0.05:
			plateau_height = machine.ground.position.y
	_check(machine.ground.position.x <= -40.0, "crosses the ramp, plateau and descent (%.1f s)" % (steps * DT))
	_near(ramp_pitch, rad_to_deg(atan(TestGround.RAMP_SLOPE)), 0.02, "pitch on the 35 % ramp (deg)")
	_near(plateau_height, TestGround.PLATEAU_HEIGHT, 0.005, "height on the plateau")
	_near(-steepest_nose_down, rad_to_deg(atan(TestGround.DESCENT_SLOPE)), 0.02, "nose down on the 70 % descent (deg)")
	_check(deepest < 0.02, "tracks never sink into the ground (deepest %.3f m)" % deepest)
	_check(largest_step < 1.0, "tipping over crests is progressive (largest step %.2f deg at 120 Hz)" % largest_step)
	_check(absf(machine.ground.position.y) < 0.005 and absf(machine.ground.pitch_deg()) < 0.1,
			"back level on the flat after the descent")


func _test_gradeability(params: MachineParams, terrain: Terrain) -> void:
	print("Gradeability")
	var climber := _machine(params, terrain, Vector2(-38.0, 0.0), -90.0)
	climber.travel.high_speed = true
	_drive(climber, terrain, 1.0, 1.0, 12.0)
	_check(climber.ground.position.x > -24.0 and absf(climber.ground.position.y - TestGround.PLATEAU_HEIGHT) < 0.01,
			"climbs the 70 %% slope up to the plateau (%.0f deg, the published gradeability)"
			% rad_to_deg(atan(TestGround.DESCENT_SLOPE)))

	var wall := Terrain.new()
	wall.setup(160, 0.25)
	wall.apply(Rect2(-20.0, -20.0, 40.0, 40.0), func(x: float, _z: float, _h: float) -> float:
			return clampf(-6.0 - x, 0.0, 10.0))
	var machine := _machine(params, wall, Vector2(0.0, 0.0), 90.0)
	machine.travel.high_speed = true
	_drive(machine, wall, 1.0, 1.0, 15.0)
	var stalled_at := machine.ground.position
	var track_before := machine.travel.left_distance
	_drive(machine, wall, 1.0, 1.0, 3.0)
	_check(stalled_at.distance_to(machine.ground.position) < 0.01 and machine.travel.left_distance > track_before + 4.0,
			"on a 45 deg slope the tracks keep turning but the machine stalls")
	_check(stalled_at.y < 4.0, "stalls low on the 45 deg slope (%.1f m up)" % stalled_at.y)
	wall.free()


func _test_side_bank(params: MachineParams, terrain: Terrain) -> void:
	print("Side bank")
	var machine := _machine(params, terrain, Vector2(8.0, 22.0), 90.0)
	var expected := rad_to_deg(atan(TestGround.BANK_SLOPE))
	_near(-machine.ground.roll_deg(), expected, 0.02, "roll along the 25 % bank, right side downhill (deg)")
	_check(absf(machine.ground.pitch_deg()) < 0.1, "no pitch when driving along the bank")
	var deepest := 0.0
	for i in 5 * 120:
		machine.travel.step(1.0, 1.0, DT)
		machine.ground.advance(terrain, machine.travel, params.center_of_mass, DT)
		if i % 4 == 0:
			deepest = maxf(deepest, machine.ground.max_penetration(terrain))
	_near(-machine.ground.roll_deg(), expected, 0.02, "roll after driving 5 s along the bank (deg)")
	_check(deepest < 0.02, "downhill shoe edges stay on the ground surface (deepest %.3f m)" % deepest)
	var body_up := machine.ground.body_basis().y
	var surface_up := Vector3(0.0, 1.0, -TestGround.BANK_SLOPE).normalized()
	_check(body_up.angle_to(surface_up) < deg_to_rad(0.5), "body normal matches the bank normal")


class Machine:
	var travel := TrackDrive.new()
	var ground := GroundSupport.new()
	var center_of_mass := Vector3.ZERO


func _machine(params: MachineParams, terrain: Terrain, position: Vector2, heading_deg: float) -> Machine:
	var machine := Machine.new()
	machine.travel.setup(params)
	machine.ground.setup(params)
	machine.center_of_mass = params.center_of_mass
	machine.ground.place(terrain, position, deg_to_rad(heading_deg), params.center_of_mass)
	return machine


func _drive(machine: Machine, terrain: Terrain, left: float, right: float, duration: float) -> void:
	for i in int(round(duration / DT)):
		machine.travel.step(left, right, DT)
		machine.ground.advance(terrain, machine.travel, machine.center_of_mass, DT)


func _hold(excavator: Excavator, keys: Array, duration: float) -> void:
	for key in keys:
		_send_key(key, true)
	for i in int(round(duration / DT)):
		excavator._physics_process(DT)
	for key in keys:
		_send_key(key, false)
	for i in int(round(1.0 / DT)):
		excavator._physics_process(DT)


static func _send_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


static func _probe_height(x: float, z: float, _current: float) -> float:
	return PROBE_PLANE.y + PROBE_PLANE.x * x + PROBE_PLANE.z * z


func _check(condition: bool, message: String) -> void:
	_runner.call("_check", condition, message)


func _near(value: float, expected: float, tolerance_ratio: float, message: String) -> void:
	_runner.call("_near", value, expected, tolerance_ratio, message)
