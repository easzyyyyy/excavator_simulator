extends RefCounted
## Phase 5 checks: the prepared 3D model sits on the MachineParams axes and its moving
## parts follow the machine. Driven by run_tests.gd, which owns the check counters.

## Pivot position error allowed between the model and MachineParams.
const PIVOT_TOLERANCE := 0.005
const AIM_TOLERANCE_DEG := 0.1
const CYLINDERS := [
	["BoomCylinderLeftBarrel", "BoomCylinderLeftRod"],
	["BoomCylinderRightBarrel", "BoomCylinderRightRod"],
	["StickCylinderBarrel", "StickCylinderRod"],
	["BucketCylinderBarrel", "BucketCylinderRod"],
]

var _runner: SceneTree


func _init(runner: SceneTree) -> void:
	_runner = runner


func run(params: MachineParams) -> void:
	_test_pivots_on_axes(params)


func run_scene(excavator: Excavator) -> void:
	print("3D model in the scene")
	var used_model := excavator.use_model
	excavator.use_model = true
	_test_parts_under_pivots(excavator)
	_test_moving_parts(excavator)
	_test_cab_controls(excavator)
	_test_tracks(excavator)
	_test_visual_switch(excavator)
	excavator.use_model = used_model
	excavator.reset_pose()


## In the zero pose, every model pivot is where MachineParams puts the simulator axis. A
## change to the arm, cylinder or linkage geometry needs the model to be re-exported.
func _test_pivots_on_axes(params: MachineParams) -> void:
	print("3D model pivots")
	var p := params
	var model := _instantiate_model()
	var stick_pin := p.boom_foot + Vector3(0.0, 0.0, -p.boom_length)
	var joint := ArmGeometry.to_local(ArmGeometry.bucket_linkage(p, 0.0)["joint"])
	var expected := {
		"Undercarriage": Vector3.ZERO,
		"Turret": Vector3.ZERO,
		"Boom": p.boom_foot,
		"Stick": stick_pin,
		"Bucket": stick_pin + Vector3(0.0, 0.0, -p.stick_length),
		"EyePoint": p.eye_position,
		"BoomCylinderLeftBarrel": p.boom_foot + ArmGeometry.to_local(p.boom_cyl_base, -p.boom_cyl_lateral),
		"BoomCylinderRightBarrel": p.boom_foot + ArmGeometry.to_local(p.boom_cyl_base, p.boom_cyl_lateral),
		"BoomCylinderLeftRod": p.boom_foot + ArmGeometry.to_local(p.boom_cyl_rod_end, -p.boom_cyl_lateral),
		"BoomCylinderRightRod": p.boom_foot + ArmGeometry.to_local(p.boom_cyl_rod_end, p.boom_cyl_lateral),
		"StickCylinderBarrel": p.boom_foot + ArmGeometry.to_local(p.stick_cyl_base),
		"StickCylinderRod": stick_pin + ArmGeometry.to_local(p.stick_cyl_rod_end),
		"BucketCylinderBarrel": stick_pin + ArmGeometry.to_local(p.bucket_cyl_base),
		"BucketCylinderRod": stick_pin + joint,
		"RockerLink": stick_pin + ArmGeometry.to_local(p.rocker_pivot),
		"PowerLink": stick_pin + joint,
	}
	var worst := 0.0
	var worst_name := ""
	var missing: Array[String] = []
	for node_name: String in expected:
		var node := model.find_child(node_name, true, false) as Node3D
		if node == null:
			missing.append(node_name)
			continue
		var error := _model_space(node, model).origin.distance_to(expected[node_name])
		if error > worst:
			worst = error
			worst_name = node_name
	_check(missing.is_empty(), "model has every simulator pivot %s" % ("" if missing.is_empty() else str(missing)))
	_check(worst < PIVOT_TOLERANCE, "model pivots sit on the MachineParams axes (worst %.1f mm, %s)"
			% [worst * 1000.0, worst_name])
	model.free()


func _test_parts_under_pivots(excavator: Excavator) -> void:
	var parts := {
		excavator.undercarriage: "Undercarriage_Carbody",
		excavator.turret: "Turret_Body",
		excavator.cab: "Cab/Cab_Frame",
		excavator.boom: "Boom_Body",
		excavator.stick: "Stick_Body",
		excavator.bucket: "Bucket_Body",
	}
	var built := true
	for pivot: Node3D in parts:
		built = built and pivot.has_node(NodePath(ExcavatorModel.MODEL_GROUP_NAME + "/" + parts[pivot]))
		built = built and not pivot.has_node(NodePath(ExcavatorPrimitives.GROUP_NAME))
	_check(built, "model parts are built under the six pivots, without the primitives")
	var glass := excavator.cab.get_node(NodePath(ExcavatorModel.MODEL_GROUP_NAME + "/Cab/Cab_Glass")) as MeshInstance3D
	_check(glass.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "cab glass casts no shadow")


## At an arbitrary pose, each barrel and rod sit on their pins and face each other, and
## the linkage closes on the bucket link pin.
func _test_moving_parts(excavator: Excavator) -> void:
	var p := excavator.params
	excavator.set_pose(25.0, 30.0, -100.0, -60.0)
	var pins := {
		"BoomCylinderLeftBarrel": excavator.turret.to_global(p.boom_foot + ArmGeometry.to_local(p.boom_cyl_base, -p.boom_cyl_lateral)),
		"BoomCylinderRightBarrel": excavator.turret.to_global(p.boom_foot + ArmGeometry.to_local(p.boom_cyl_base, p.boom_cyl_lateral)),
		"BoomCylinderLeftRod": excavator.boom.to_global(ArmGeometry.to_local(p.boom_cyl_rod_end, -p.boom_cyl_lateral)),
		"BoomCylinderRightRod": excavator.boom.to_global(ArmGeometry.to_local(p.boom_cyl_rod_end, p.boom_cyl_lateral)),
		"StickCylinderBarrel": excavator.boom.to_global(ArmGeometry.to_local(p.stick_cyl_base)),
		"StickCylinderRod": excavator.stick.to_global(ArmGeometry.to_local(p.stick_cyl_rod_end)),
		"BucketCylinderBarrel": excavator.stick.to_global(ArmGeometry.to_local(p.bucket_cyl_base)),
		"RockerLink": excavator.stick.to_global(ArmGeometry.to_local(p.rocker_pivot)),
	}
	var worst_pin := 0.0
	for node_name: String in pins:
		worst_pin = maxf(worst_pin, _part(excavator, node_name).global_position.distance_to(pins[node_name]))
	var worst_aim := 0.0
	for pair: Array in CYLINDERS:
		var barrel := _part(excavator, pair[0])
		var rod := _part(excavator, pair[1])
		worst_aim = maxf(worst_aim, maxf(_aim_error_deg(barrel, rod.global_position), _aim_error_deg(rod, barrel.global_position)))
	_check(worst_pin < 0.001 and worst_aim < AIM_TOLERANCE_DEG,
			"cylinder barrels and rods stay on their pins and in line (%.2f mm, %.3f deg)" % [worst_pin * 1000.0, worst_aim])

	var rocker := _part(excavator, "RockerLink")
	var power_link := _part(excavator, "PowerLink")
	var link_pin := excavator.bucket.to_global(ArmGeometry.to_local(
			Vector2.RIGHT.rotated(deg_to_rad(p.bucket_link_angle_deg)) * p.bucket_link_radius))
	var closes := power_link.global_position.is_equal_approx(_part(excavator, "BucketCylinderRod").global_position)
	closes = closes and absf(rocker.global_position.distance_to(power_link.global_position) - p.rocker_length) < 0.001
	closes = closes and absf(power_link.global_position.distance_to(link_pin) - p.power_link_length) < 0.001
	var aim := maxf(_aim_error_deg(rocker, power_link.global_position), _aim_error_deg(power_link, link_pin))
	_check(closes and aim < AIM_TOLERANCE_DEG, "bucket linkage closes on the bucket link pin (%.3f deg)" % aim)


func _test_cab_controls(excavator: Excavator) -> void:
	var controls := excavator.controls
	controls.travel_mode = false
	controls.left_stick = Vector2(0.0, 1.0)
	controls.left_track = 1.0
	excavator._visual.update_operator(controls)
	var cab_part := excavator.cab.get_node(NodePath(ExcavatorModel.MODEL_GROUP_NAME + "/Cab"))
	var joystick := cab_part.get_node("LeftJoystick") as Node3D
	var lever := cab_part.get_node("LeftTravelLever") as Node3D
	_check(joystick.rotation.x < -0.3 and lever.rotation.x < 0.0, "model joystick and travel lever follow the controls")
	controls.left_stick = Vector2.ZERO
	controls.left_track = 0.0
	excavator._visual.update_operator(controls)


## Shoes computed like the primitives land on the model's own shoe layout, then run
## around the loop with their track while the wheels turn.
func _test_tracks(excavator: Excavator) -> void:
	var visual := excavator._visual
	var group := excavator.undercarriage.get_node(NodePath(ExcavatorModel.MODEL_GROUP_NAME))
	visual.update_tracks(0.0, 0.0)
	var model := _instantiate_model()
	var worst := 0.0
	var oriented := true
	var count := 0
	for reference: Node3D in model.find_children("*TrackShoe_*", "MeshInstance3D", true, false):
		var shoe := group.get_node_or_null(NodePath(reference.name)) as Node3D
		if shoe == null:
			continue
		count += 1
		worst = maxf(worst, shoe.transform.origin.distance_to(reference.transform.origin))
		oriented = oriented and shoe.transform.basis.is_equal_approx(reference.transform.basis)
	model.free()
	_check(count == 2 * excavator.params.track_shoe_count and worst < 0.001 and oriented,
			"track loop of the primitives matches the model shoes (%d shoes, worst %.2f mm)" % [count, worst * 1000.0])

	var left := group.get_node("Undercarriage_LeftTrackShoe_00") as Node3D
	var right := group.get_node("Undercarriage_RightTrackShoe_00") as Node3D
	var left_start := left.position
	var right_start := right.position
	visual.update_tracks(1.0, 0.0)
	_check(left.position.distance_to(left_start + Vector3(0.0, 0.0, 1.0)) < 0.001 and right.position.is_equal_approx(right_start),
			"left shoes run 1 m rearward under the machine, right shoes stay")
	var idler := group.get_node("Undercarriage_LeftIdler") as Node3D
	var sprocket := group.get_node("Undercarriage_LeftSprocket") as Node3D
	_check(sprocket.rotation.x < -1.0 and is_equal_approx(idler.rotation.x, sprocket.rotation.x),
			"left idler and sprocket turn with the shoes")
	visual.update_tracks(excavator.travel.left_distance, excavator.travel.right_distance)


func _test_visual_switch(excavator: Excavator) -> void:
	excavator.use_model = false
	var primitives := excavator.boom.has_node(NodePath(ExcavatorPrimitives.GROUP_NAME)) \
			and not excavator.boom.has_node(NodePath(ExcavatorModel.MODEL_GROUP_NAME))
	excavator.use_model = true
	var model := excavator.boom.has_node(NodePath(ExcavatorModel.MODEL_GROUP_NAME)) \
			and not excavator.boom.has_node(NodePath(ExcavatorPrimitives.GROUP_NAME))
	_check(primitives and model, "use_model switches between the model and the primitives")


static func _instantiate_model() -> Node:
	return (load(ExcavatorModel.SCENE_PATH) as PackedScene).instantiate()


static func _model_space(node: Node, root: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	while node != root:
		xform = (node as Node3D).transform * xform
		node = node.get_parent()
	return xform


static func _part(excavator: Excavator, node_name: String) -> Node3D:
	return excavator.find_child(node_name, true, false) as Node3D


## Angle between a part's local -Z and the direction to a point.
static func _aim_error_deg(node: Node3D, target: Vector3) -> float:
	return rad_to_deg((-node.global_basis.z).angle_to(target - node.global_position))


func _check(condition: bool, message: String) -> void:
	_runner.call("_check", condition, message)
