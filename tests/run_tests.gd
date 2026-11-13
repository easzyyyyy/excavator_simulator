extends SceneTree
## Headless test runner:
## godot --headless --path . --script res://tests/run_tests.gd

const DT := 1.0 / 120.0
const TravelTests := preload("res://tests/travel_tests.gd")
const SoilTests := preload("res://tests/soil_tests.gd")
const ModelTests := preload("res://tests/model_tests.gd")
const HydraulicTests := preload("res://tests/hydraulic_tests.gd")
const SiteTests := preload("res://tests/site_tests.gd")
const ExerciseTests := preload("res://tests/exercise_tests.gd")

var _failures := 0
var _checks := 0
var _travel_tests := TravelTests.new(self)
var _soil_tests := SoilTests.new(self)
var _model_tests := ModelTests.new(self)
var _hydraulic_tests := HydraulicTests.new(self)
var _site_tests := SiteTests.new(self)
var _exercise_tests := ExerciseTests.new(self)
var _collision_probe: Terrain
var _physics_frames_at_probe := 0
var _frames := 0
var _final_checks_started := false


func _initialize() -> void:
	var params: MachineParams = load("res://data/cat320.tres")
	_test_pattern_mapping()
	_test_pattern_toggle_swaps_only_boom_and_stick()
	_test_working_envelope(params)
	_test_cylinder_strokes(params)
	_test_bucket_linkage(params)
	_hydraulic_tests.run(params)
	_travel_tests.run(params)
	_soil_tests.run(params)
	_model_tests.run(params)
	_site_tests.run(params)
	_exercise_tests.run(params)


func _process(_delta: float) -> bool:
	# Scene tests need a running tree, so they run on the first frame.
	_frames += 1
	if _frames == 1:
		var completed := _test_scene_structure()
		_check(completed, "scene tests ran to completion")
		_collision_probe = _travel_tests.add_collision_probe(root)
		_physics_frames_at_probe = Engine.get_physics_frames()
		return false
	# Collision shapes answer queries once the physics server has stepped.
	if Engine.get_physics_frames() < _physics_frames_at_probe + 2 and _frames < 10000:
		return false
	if _final_checks_started:
		# A script error interrupted the final checks on the previous frame.
		quit(1)
		return true
	_final_checks_started = true
	_travel_tests.check_collision_probe(_collision_probe)
	print("")
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
	return true


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok    ", message)
	else:
		_failures += 1
		print("  FAIL  ", message)


func _near(value: float, expected: float, tolerance_ratio: float, message: String) -> void:
	var error := absf(value - expected) / absf(expected)
	_check(error <= tolerance_ratio, "%s: %.3f vs %.3f (%+.1f %%)" % [message, value, expected,
			100.0 * (value - expected) / expected])


func _test_pattern_mapping() -> void:
	print("Control patterns")
	var iso := ControlInput.Pattern.ISO
	var sae := ControlInput.Pattern.SAE
	var forward := Vector2(0, 1)
	var right := Vector2(1, 0)
	# ISO: left forward = stick out, right forward = boom lower, right lateral right = bucket dump.
	_check(ControlInput.map_pattern(iso, forward, Vector2.ZERO)["stick"] == 1.0, "ISO left forward moves stick out")
	_check(ControlInput.map_pattern(iso, Vector2.ZERO, forward)["boom"] == -1.0, "ISO right forward lowers boom")
	_check(ControlInput.map_pattern(iso, Vector2.ZERO, -forward)["boom"] == 1.0, "ISO right back raises boom")
	_check(ControlInput.map_pattern(iso, right, Vector2.ZERO)["swing"] == 1.0, "ISO left right swings right")
	_check(ControlInput.map_pattern(iso, Vector2.ZERO, right)["bucket"] == 1.0, "ISO right right dumps bucket")
	_check(ControlInput.map_pattern(iso, Vector2.ZERO, -right)["bucket"] == -1.0, "ISO right left curls bucket")
	# SAE: left forward = boom lower, right forward = stick out.
	_check(ControlInput.map_pattern(sae, forward, Vector2.ZERO)["boom"] == -1.0, "SAE left forward lowers boom")
	_check(ControlInput.map_pattern(sae, Vector2.ZERO, forward)["stick"] == 1.0, "SAE right forward moves stick out")
	# Diagonal gives two functions at once.
	var diagonal := ControlInput.map_pattern(iso, Vector2(0.7, 0.7), Vector2.ZERO)
	_check(diagonal["swing"] > 0.0 and diagonal["stick"] > 0.0, "diagonal on one stick drives two functions")


func _test_pattern_toggle_swaps_only_boom_and_stick() -> void:
	print("Pattern toggle")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ok := true
	for i in 200:
		var left := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var right := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var iso := ControlInput.map_pattern(ControlInput.Pattern.ISO, left, right)
		var sae := ControlInput.map_pattern(ControlInput.Pattern.SAE, left, right)
		ok = ok and iso["swing"] == sae["swing"] and iso["bucket"] == sae["bucket"]
		# The function driven by an axis in ISO is driven by the other hand's same axis in SAE.
		var sae_swapped := ControlInput.map_pattern(ControlInput.Pattern.SAE, Vector2(left.x, right.y), Vector2(right.x, left.y))
		ok = ok and is_equal_approx(iso["boom"], sae_swapped["boom"]) and is_equal_approx(iso["stick"], sae_swapped["stick"])
	_check(ok, "toggle keeps swing and bucket, swaps boom and stick between hands")


func _test_working_envelope(params: MachineParams) -> void:
	print("Working envelope against manufacturer data")
	var envelope := ArmGeometry.working_envelope(params, 0.5)
	_near(envelope["max_reach_ground"], params.ref_max_reach_ground, 0.02, "max reach at ground level")
	_near(envelope["max_dig_depth"], params.ref_max_dig_depth, 0.02, "max digging depth")
	_near(envelope["max_cutting_height"], params.ref_max_cutting_height, 0.02, "max cutting height")
	_near(envelope["max_loading_height"], params.ref_max_loading_height, 0.02, "max loading height")


func _test_cylinder_strokes(params: MachineParams) -> void:
	print("Cylinder strokes over the joint ranges")
	_check_stroke("boom", func(a: float) -> float: return ArmGeometry.boom_cylinder_length(params, a),
			params.boom_min_deg, params.boom_max_deg, params.boom_cyl_closed_length, params.boom_cyl_stroke, true)
	_check_stroke("stick", func(a: float) -> float: return ArmGeometry.stick_cylinder_length(params, a),
			params.stick_min_deg, params.stick_max_deg, params.stick_cyl_closed_length, params.stick_cyl_stroke, false)
	_check_stroke("bucket", func(a: float) -> float: return ArmGeometry.bucket_linkage(params, a).get("cylinder_length", NAN),
			params.bucket_min_deg, params.bucket_max_deg, params.bucket_cyl_closed_length, params.bucket_cyl_stroke, false)


func _test_bucket_linkage(params: MachineParams) -> void:
	print("Bucket linkage")
	var ok := true
	var angle := params.bucket_min_deg
	while angle <= params.bucket_max_deg:
		ok = ok and not ArmGeometry.bucket_linkage(params, angle).is_empty()
		angle += 0.5
	_check(ok, "four-bar linkage assembles over the full bucket range")


func _test_scene_structure() -> bool:
	print("Scene structure")
	var scene: PackedScene = load("res://scenes/excavator.tscn")
	var excavator: Excavator = scene.instantiate()
	root.add_child(excavator)
	for path in ["Undercarriage/Turret", "Undercarriage/Turret/Boom", "Undercarriage/Turret/Boom/Stick",
			"Undercarriage/Turret/Boom/Stick/Bucket", "Undercarriage/Turret/Head/Camera3D", "Undercarriage/Turret/Cab"]:
		_check(excavator.has_node(path), "node %s exists" % path)
	_check(excavator.boom.get_node_or_null("Primitives") != null, "primitive geometry is built")
	var audio :=excavator.get_node_or_null("Audio") as ExcavatorAudio
	_check(audio != null, "audio node exists")
	if audio != null:
		var looping := audio.looping_streams().all(func(stream: AudioStream) -> bool:
				return stream is AudioStreamWAV and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)
		_check(looping, "engine, hydraulic and swing sounds are imported as forward loops")
	var tip := excavator.tip_point()
	var bucket_tip_world := excavator.bucket.to_global(Vector3(0, 0, -excavator.params.bucket_tip_radius))
	_check(bucket_tip_world.distance_to(Vector3(0, tip.y, -tip.x) + Vector3(excavator.params.boom_foot.x, 0, 0)) < 0.001,
			"scene pose matches planar kinematics")
	_test_keyboard_drives_arm(excavator)
	_travel_tests.run_scene(excavator)
	_soil_tests.run_scene(excavator)
	_hydraulic_tests.run_scene(excavator)
	_model_tests.run_scene(excavator)
	_site_tests.run_scene(excavator)
	_exercise_tests.run_scene(excavator)
	excavator.queue_free()
	return true


func _test_keyboard_drives_arm(excavator: Excavator) -> void:
	print("Keyboard input end to end")
	excavator.controls.pattern = ControlInput.Pattern.ISO
	var before := _angles(excavator)
	_hold_key(excavator, KEY_W, 0.5)
	var after := _angles(excavator)
	_check(after.stick > before.stick + 5.0 and is_equal_approx(after.boom, before.boom),
			"ISO: left stick forward moves the stick out and nothing else")
	before = after
	_hold_key(excavator, KEY_I, 0.5)
	after = _angles(excavator)
	_check(after.boom < before.boom - 5.0 and is_equal_approx(after.stick, before.stick),
			"ISO: right stick forward lowers the boom and nothing else")
	excavator.controls.toggle_pattern()
	before = after
	_hold_key(excavator, KEY_W, 0.5)
	after = _angles(excavator)
	_check(after.boom < before.boom - 5.0 and is_equal_approx(after.stick, before.stick),
			"SAE: left stick forward lowers the boom and nothing else")
	before = after
	_hold_key(excavator, KEY_D, 0.5)
	after = _angles(excavator)
	_check(after.swing > before.swing + 5.0 and excavator.turret.rotation.y < 0.0,
			"left stick right swings the turret to the right")


func _hold_key(excavator: Excavator, key: Key, duration: float) -> void:
	_send_key(key, true)
	for i in int(duration / DT):
		excavator._physics_process(DT)
	_send_key(key, false)
	for i in int(1.0 / DT):
		excavator._physics_process(DT)


func _send_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _angles(excavator: Excavator) -> Dictionary:
	return {
		"swing": excavator.swing_joint.angle_deg,
		"boom": excavator.boom_joint.angle_deg,
		"stick": excavator.stick_joint.angle_deg,
	}


func _check_stroke(label: String, length_at: Callable, min_deg: float, max_deg: float,
		closed: float, stroke: float, extends_with_angle: bool) -> void:
	var monotonic := true
	var previous := NAN
	var shortest := INF
	var longest := -INF
	var angle := min_deg
	while angle <= max_deg + 1e-6:
		var length: float = length_at.call(angle)
		shortest = minf(shortest, length)
		longest = maxf(longest, length)
		if not is_nan(previous):
			monotonic = monotonic and ((length > previous) == extends_with_angle)
		previous = length
		angle += 0.5
	_check(monotonic, "%s cylinder length is monotonic over the joint range" % label)
	_check(shortest >= closed - 0.01 and longest <= closed + stroke + 0.01,
			"%s cylinder stays within its stroke: %.3f to %.3f m for %.3f to %.3f m" % [label, shortest, longest, closed, closed + stroke])
