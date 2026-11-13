extends RefCounted
## CACES trench exercise checks: the task placed on the work site, the scoring of dug
## trenches against the R482 B1 criteria, and on a running tree the exercise flow (start
## place, painted outline, clock, eliminatory manoeuvre, time limit, report).
## Driven by run_tests.gd, which owns the check counters.

const DT := 1.0 / 120.0

var _runner: SceneTree


func _init(runner: SceneTree) -> void:
	_runner = runner


func run(params: MachineParams) -> void:
	var trench: TrenchExerciseParams = load("res://data/caces_b1_trench.tres")
	_test_site_placement(trench, params)
	_test_scoring(trench)


func run_scene(excavator: Excavator) -> void:
	_test_exercise_flow(excavator)
	_test_dug_trench(excavator)


func _test_site_placement(trench: TrenchExerciseParams, params: MachineParams) -> void:
	print("Trench exercise on the site")
	var area := trench.outline()
	var work := area.grow(4.0)
	var start := Vector2(trench.axis_x - params.boom_foot.x, trench.far_end_z + trench.start_distance)
	_check(SiteGround.PLATFORM.encloses(work) and not SiteGround.CLAY_PATCH.intersects(work)
			and SiteGround.PLATFORM.has_point(start + Vector2(0.0, 4.0)),
			"the trench, its spoil and the machine stay on the flat earth of the start platform")
	var midway := true
	for edge in [area.position.x, area.end.x, area.position.y, area.end.y]:
		midway = midway and is_equal_approx(fposmod(edge, 0.25), 0.125)
	_check(midway, "every edge of the trench lies midway between grid points")
	var state := (load("res://scenes/main.tscn") as PackedScene).get_state()
	var found := false
	for node in state.get_node_count():
		if state.get_node_name(node) != "TrenchExercise":
			continue
		for property in state.get_node_property_count(node):
			if state.get_node_property_name(node, property) == "params":
				found = (state.get_node_property_value(node, property) as Resource).resource_path == trench.resource_path
	_check(found, "the game has the trench exercise with its data")
	_near(trench.total_points(), 10.0, 1e-6, "the task is worth its 10 points of the B1 grid")
	_near(trench.pass_points / trench.total_points(), 0.7, 1e-6, "pass mark of the practical test")


func _test_scoring(trench: TrenchExerciseParams) -> void:
	print("Trench scoring")
	var area := trench.outline()
	var reference := trench.reference_time

	var score := _score_carved(trench, area, trench.depth, trench.axis_x - 3.0, reference * 0.9)
	_check(score["total"] == 10.0 and score["passed"] and score["sections_on_line"] == 24 and score["sections"] == 24,
			"a trench dug to the line and the depth, spoil clear, in time, scores 10 / 10")

	score = _score_carved(trench, area.grow_individual(0.25, 0.0, 0.25, 0.0), trench.depth, trench.axis_x - 3.0, reference)
	_check(score["straightness"] == 3.0 and score["bottom"] == 3.0,
			"one grid column wider on each side still follows the line")

	score = _score_carved(trench, Rect2(area.position + Vector2(0.25, 0.0), area.size), trench.depth, trench.axis_x - 3.0,
			reference)
	_check(score["straightness"] == 0.0 and not score["passed"],
			"a trench shifted one column off the line fails straightness (%.1f / 10)" % score["total"])

	score = _score_carved(trench, area.grow_individual(0.0, 1.0, 0.0, 0.0), trench.depth, trench.axis_x - 3.0, reference)
	_check(score["sections"] == 27 and score["straightness"] == 2.5,
			"digging 1 m past the far end adds sections off the line (%d of %d on it)" % [score["sections_on_line"],
			score["sections"]])

	score = _score_carved(trench, area, trench.depth - 0.08, trench.axis_x - 3.0, reference)
	_check(score["within"] == 0.0 and score["within_half"] == 1.0 and score["bottom"] == 1.5,
			"a bottom 8 cm high scores half the bottom points")
	score = _score_carved(trench, area, trench.depth + 0.12, trench.axis_x - 3.0, reference)
	_check(score["bottom"] == 0.0, "a bottom 12 cm too deep scores no bottom point")

	score = _score_carved(trench, area, trench.depth, trench.axis_x - 1.2, reference)
	_check(score["berm"] < trench.berm_points and score["berm_clear"] < 0.8,
			"spoil on the berm loses the windrow points (%d %% clear)" % roundi(100.0 * score["berm_clear"]))

	score = _score_carved(trench, area, trench.depth, trench.axis_x - 3.0, reference * 1.15)
	_check(score["speed"] == 1.0 and score["passed"], "half the speed points halfway to the time limit")
	score = _score_carved(trench, area, trench.depth, trench.axis_x - 3.0, trench.time_limit() + 1.0)
	_check(score["failure"] == TrenchEvaluation.Failure.TIME_OVER and score["total"] == 0.0 and not score["passed"],
			"past 130 % of the reference time the task scores 0")

	score = _score_carved(trench, area, 0.0, trench.axis_x - 3.0, reference * 0.5)
	_check(not score["complete"] and score["total"] == 0.0, "an undug trench scores nothing, not even for spoil or speed")
	score = _score_carved(trench, area, trench.depth, trench.axis_x - 3.0, reference * 0.5,
			TrenchEvaluation.Failure.RAISED_LOAD)
	_check(score["total"] == 0.0 and not score["passed"], "an eliminatory manoeuvre scores 0 whatever the trench")


## Ground dug to a depth over an area, with a windrow of loose soil 1.5 m wide centred
## at spoil_x along the trench, scored after a time.
func _score_carved(trench: TrenchExerciseParams, dug: Rect2, depth: float, spoil_x: float, elapsed: float,
		failure := TrenchEvaluation.Failure.NONE) -> Dictionary:
	var terrain := Terrain.new()
	terrain.setup(128, 0.25)
	var evaluation := TrenchEvaluation.new()
	evaluation.capture(terrain, trench)
	var windrow := Rect2(spoil_x - 0.75, trench.far_end_z, 1.5, trench.length)
	for iz in terrain.points:
		for ix in terrain.points:
			var at := terrain.point_position(ix, iz)
			if depth > 0.0 and dug.has_point(at):
				terrain.set_point_height(ix, iz, -depth)
			elif windrow.has_point(at):
				terrain.add_loose(ix, iz, 0.6 * terrain.cell_size * terrain.cell_size)
	var result := evaluation.score(elapsed, failure)
	terrain.free()
	return result


func _test_exercise_flow(excavator: Excavator) -> void:
	print("Trench exercise flow")
	var terrain := Terrain.new()
	terrain.layout = Terrain.Layout.FLAT
	terrain.cells = 128
	terrain.chunk_cells = 32
	terrain.tile_cells = 32
	var parent := excavator.get_parent()
	parent.add_child(terrain)
	excavator.terrain = terrain
	excavator.controls.pattern = ControlInput.Pattern.ISO
	var exercise := TrenchExercise.new()
	exercise.params = load("res://data/caces_b1_trench.tres")
	exercise.excavator = excavator
	parent.add_child(exercise)
	var trench := exercise.params
	var params := excavator.params

	exercise.start()
	var tip := excavator.bucket.to_global(Vector3(0.0, 0.0, -params.bucket_tip_radius))
	_check(exercise.state == TrenchExercise.State.READY and absf(tip.x - trench.axis_x) < 1e-3
			and absf(excavator.global_position.z - trench.far_end_z - trench.start_distance) < 1e-3,
			"the exercise rests the machine behind the trench, arm on its axis")
	var decals: Array[Decal] = []
	for child in exercise.markings().get_children():
		if child is Decal:
			decals.append(child)
	var area := trench.outline()
	var middles := [Vector2(area.get_center().x, area.position.y), Vector2(area.end.x, area.get_center().y),
			Vector2(area.get_center().x, area.end.y), Vector2(area.position.x, area.get_center().y)]
	var painted := decals.size() == 4
	for k in mini(decals.size(), 4):
		var local := decals[k].global_transform.affine_inverse() * Vector3(middles[k].x, 0.0, middles[k].y)
		painted = painted and absf(local.x) < decals[k].size.x * 0.5 and absf(local.y) < decals[k].size.y * 0.5 \
				and absf(local.z) < decals[k].size.z * 0.5 and decals[k].cull_mask == Terrain.MARKING_LAYER
	var chunk := terrain.get_node("Visual").get_child(0) as MeshInstance3D
	var machine_marked := _meshes(excavator).any(func(mesh: MeshInstance3D) -> bool:
			return mesh.layers & Terrain.MARKING_LAYER != 0)
	_check(painted and chunk.layers & Terrain.MARKING_LAYER != 0 and not machine_marked,
			"the outline is painted on the ground, and on nothing else")

	_step(excavator, exercise, [], 0.1)
	_check(exercise.state == TrenchExercise.State.READY and exercise.elapsed == 0.0 and "premier mouvement" in exercise.status_text(),
			"the clock waits for the first command")
	_step(excavator, exercise, [KEY_W], 0.1)
	_check(exercise.state == TrenchExercise.State.RUNNING and is_equal_approx(exercise.elapsed, 12 * DT),
			"the first command starts the clock")
	_check("1 m de profondeur" in exercise.status_text() and "6 m de long" in exercise.status_text(),
			"the trench size stays on screen while the clock runs")

	var profile := params.bucket_profile
	var level := 180.0 + rad_to_deg(atan2(profile[0].y - profile[profile.size() - 1].y,
			profile[profile.size() - 1].x - profile[0].x))
	var low: Vector3 = ArmGeometry.pose_for_tip(params, Vector2(5.0, 0.6), level)
	excavator.set_pose(0.0, low.x, low.y, low.z)
	excavator.bucket_soil.fill = excavator.bucket_soil.max_fill()
	_step(excavator, exercise, [KEY_SPACE, KEY_W, KEY_I], 0.6)
	_check(exercise.state == TrenchExercise.State.RUNNING and excavator.travel.left_speed > trench.high_load_speed,
			"travelling with the loaded bucket carried low goes on")
	var high: Vector3 = ArmGeometry.pose_for_tip(params, Vector2(5.0, 3.0), level)
	excavator.set_pose(0.0, high.x, high.y, high.z)
	_step(excavator, exercise, [KEY_SPACE, KEY_W, KEY_I], 0.6)
	_check(exercise.state == TrenchExercise.State.DONE
			and exercise.result["failure"] == TrenchEvaluation.Failure.RAISED_LOAD and exercise.result["total"] == 0.0
			and "éliminatoire" in exercise.status_text(),
			"travelling with the loaded bucket held up ends the task with 0, eliminatory")
	_step(excavator, exercise, [], 1.0)

	excavator.bucket_soil.clear()
	exercise.start()
	_step(excavator, exercise, [KEY_W], 0.05)
	exercise.elapsed = trench.time_limit() - DT * 0.5
	_step(excavator, exercise, [], DT)
	_check(exercise.state == TrenchExercise.State.DONE and exercise.result["failure"] == TrenchEvaluation.Failure.TIME_OVER
			and "temps limite" in exercise.status_text(), "the task stops at the time limit")

	exercise.start()
	_step(excavator, exercise, [KEY_W], 0.05)
	exercise.finish()
	var text := exercise.status_text()
	_check(exercise.state == TrenchExercise.State.DONE and not exercise.result["complete"] and "inachevée" in text
			and "Note 0 / 10" in text and "Rectitude" in text and "Célérité" in text,
			"declared finished at once, the report shows an unfinished trench and its criteria")
	exercise.stop()
	_check(exercise.state == TrenchExercise.State.OFF and exercise.markings() == null and exercise.status_text() == "",
			"leaving the exercise removes the outline and its text")

	excavator.terrain = null
	excavator.bucket_soil.clear()
	excavator.reset_pose()
	excavator.return_to_start()
	exercise.queue_free()
	terrain.queue_free()


## A shorter trench, dug from the start place in two layers of passes that never overfill
## the bucket, each load dumped to the left, then a pass along the bottom.
func _test_dug_trench(excavator: Excavator) -> void:
	print("Trench dug pass by pass")
	var terrain := Terrain.new()
	terrain.layout = Terrain.Layout.FLAT
	terrain.cells = 128
	terrain.chunk_cells = 32
	terrain.tile_cells = 32
	var parent := excavator.get_parent()
	parent.add_child(terrain)
	excavator.terrain = terrain
	var exercise := TrenchExercise.new()
	exercise.params = (load("res://data/caces_b1_trench.tres") as TrenchExerciseParams).duplicate()
	exercise.params.length = 3.75
	exercise.excavator = excavator
	parent.add_child(exercise)
	exercise.start()
	var started := Time.get_ticks_msec()
	for layer in [[0.0, 0.5], [0.5, 1.0]]:
		for segment in [[7.45, 5.95], [6.05, 4.55], [4.65, 3.75]]:
			_dig_pass(excavator, segment[0], segment[1], layer[0], layer[1])
			_dump(excavator)
	_dig_pass(excavator, 7.45, 3.75, 0.5, 1.0, -115.0)
	_dump(excavator)
	exercise.state = TrenchExercise.State.RUNNING
	exercise.elapsed = 150.0
	exercise.finish()
	var result := exercise.result
	print("        dug in %d ms: %s" % [Time.get_ticks_msec() - started, exercise.report().get_slice("\n", 1)])
	_check(result["passed"] and result["total"] >= 8.0 and result["straightness"] == 3.0 and result["berm"] == 2.0,
			"dug to the line without overfilling the bucket, the trench passes with its spoil clear (%.1f / 10)" % result["total"])
	_check(absf(result["mean_depth"] - exercise.params.depth) < 0.1 and result["within_half"] > 0.6,
			"its bottom lies at the required depth (%.2f m, %d %% within 10 cm)" % [result["mean_depth"],
			roundi(100.0 * result["within_half"])])
	exercise.stop()
	excavator.terrain = null
	excavator.bucket_soil.clear()
	excavator.reset_pose()
	excavator.return_to_start()
	exercise.queue_free()
	terrain.queue_free()


## One pass along the trench: teeth in above the start, down to the floor, dragged back at
## that depth while curling, curled out and raised.
func _dig_pass(excavator: Excavator, from_u: float, to_u: float, top: float, floor_depth: float,
		drag_angle := -140.0) -> void:
	_move_tip(excavator, Vector2(from_u + 0.1, 0.4 - top), -95.0, 0.0)
	_move_tip(excavator, Vector2(from_u, -floor_depth), -100.0, 0.8)
	_move_tip(excavator, Vector2(to_u, -floor_depth), drag_angle, 2.2)
	_move_tip(excavator, Vector2(to_u - 0.3, -floor_depth + 0.8), -170.0, 1.0)
	_move_tip(excavator, Vector2(to_u, 2.5), -174.9, 1.2)


## Swings to the left, empties the bucket and swings back.
func _dump(excavator: Excavator) -> void:
	var angles := Vector3(excavator.boom_joint.angle_deg, excavator.stick_joint.angle_deg, excavator.bucket_joint.angle_deg)
	_pose_steps(excavator, 1.5, func(t: float) -> Array: return [-90.0 * t, angles])
	var dumped := Vector3(angles.x, angles.y, excavator.params.bucket_max_deg)
	_pose_steps(excavator, 2.0, func(t: float) -> Array: return [-90.0, angles.lerp(dumped, minf(t * 1.5, 1.0))])
	_pose_steps(excavator, 1.5, func(t: float) -> Array: return [-90.0 * (1.0 - t), dumped.lerp(angles, t)])


## Moves the tooth tip in a straight line while turning the bucket to an absolute
## pin-to-tip angle; zero duration jumps there.
func _move_tip(excavator: Excavator, tip: Vector2, bucket_absolute_deg: float, duration: float) -> void:
	var params := excavator.params
	if duration <= 0.0:
		var target: Vector3 = ArmGeometry.pose_for_tip(params, tip, bucket_absolute_deg)
		excavator.set_pose(0.0, target.x, target.y, target.z)
		return
	var from_tip := excavator.tip_point()
	var from_angle := excavator.boom_joint.angle_deg + excavator.stick_joint.angle_deg + excavator.bucket_joint.angle_deg
	var turn := wrapf(bucket_absolute_deg - from_angle, -180.0, 180.0)
	_pose_steps(excavator, duration, func(t: float) -> Array:
		return [0.0, ArmGeometry.pose_for_tip(params, from_tip.lerp(tip, t), from_angle + turn * t)])


## Poses the arm every physics step for a while, as a scripted operator: pose.call(t) gives
## the swing angle and the boom, stick and bucket angles, or null angles to skip the step.
func _pose_steps(excavator: Excavator, duration: float, pose: Callable) -> void:
	var steps := int(round(duration / DT))
	for i in steps:
		var at: Array = pose.call(float(i + 1) / steps)
		if at[1] != null:
			var angles: Vector3 = at[1]
			excavator.pose_and_dig(at[0], angles.x, angles.y, angles.z, DT)
			excavator.terrain.relax(Terrain.RELAX_VISITS_PER_TICK)


## Holds keys down for a while, stepping the machine and the exercise as the physics loop
## does, then releases them.
func _step(excavator: Excavator, exercise: TrenchExercise, keys: Array, duration: float) -> void:
	for key in keys:
		_send_key(key, true)
	for i in maxi(int(round(duration / DT)), 1):
		excavator._physics_process(DT)
		exercise._physics_process(DT)
	for key in keys:
		_send_key(key, false)


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			found.append(child)
		found.append_array(_meshes(child))
	return found


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
