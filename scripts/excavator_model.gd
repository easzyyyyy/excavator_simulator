@tool
class_name ExcavatorModel
extends ExcavatorPrimitives
## Prepared 3D model of the machine (assets/models/excavator, see MODEL_NOTES.md).
##
## The model pivots sit on the MachineParams axes, so its parts are moved under the
## simulator pivots unchanged. Moving parts are posed every frame from MachineParams
## like the primitives, whose track loop and cab lever motion are reused: cylinder
## barrels and rods, bucket linkage, joysticks, travel levers, track shoes and wheels.

const SCENE_PATH := "res://assets/models/excavator/excavator.gltf"
const MODEL_GROUP_NAME := "Model"
## Model nodes that go under a simulator pivot of their own.
const OWN_PIVOTS: Array[String] = ["Turret", "Cab", "EyePoint", "Boom", "Stick", "Bucket"]

var _boom_barrels: Array[Node3D] = []
var _boom_rods: Array[Node3D] = []
var _stick_barrel: Node3D
var _stick_rod: Node3D
var _bucket_barrel: Node3D
var _bucket_rod: Node3D
var _rocker: Node3D
var _power_link: Node3D
## Idler and sprocket of each track (left, right).
var _wheels: Array[Array] = [[], []]


## Removes the geometry a previous build of either visual left under the pivots.
static func clear(pivots: Array[Node3D]) -> void:
	for pivot in pivots:
		for group_name in [GROUP_NAME, MODEL_GROUP_NAME]:
			var old := pivot.get_node_or_null(NodePath(group_name))
			if old:
				pivot.remove_child(old)
				old.free()


func build(p_params: MachineParams, undercarriage: Node3D, p_turret: Node3D, cab: Node3D,
		p_boom: Node3D, p_stick: Node3D, bucket: Node3D) -> void:
	params = p_params
	turret = p_turret
	boom = p_boom
	stick = p_stick
	var model := (load(SCENE_PATH) as PackedScene).instantiate()
	# The parts leave the model scene, so they must not keep its root as owner.
	for node in model.find_children("*", "", true, false):
		node.owner = null
		if node is MeshInstance3D:
			_disable_transparent_shadows(node)

	var undercarriage_parts := _move_parts(model.find_child("Undercarriage", true, false), undercarriage)
	var turret_parts := _move_parts(model.find_child("Turret", true, false), turret)
	var cab_part: Node3D = model.find_child("Cab", true, false)
	cab_part.reparent(_group(cab), false)
	var boom_parts := _move_parts(model.find_child("Boom", true, false), boom)
	var stick_parts := _move_parts(model.find_child("Stick", true, false), stick)
	_move_parts(model.find_child("Bucket", true, false), bucket)
	model.free()

	_boom_barrels = [turret_parts.get_node("BoomCylinderLeftBarrel"), turret_parts.get_node("BoomCylinderRightBarrel")]
	_boom_rods = [boom_parts.get_node("BoomCylinderLeftRod"), boom_parts.get_node("BoomCylinderRightRod")]
	_stick_barrel = boom_parts.get_node("StickCylinderBarrel")
	_stick_rod = stick_parts.get_node("StickCylinderRod")
	_bucket_barrel = stick_parts.get_node("BucketCylinderBarrel")
	_bucket_rod = stick_parts.get_node("BucketCylinderRod")
	_rocker = stick_parts.get_node("RockerLink")
	_power_link = stick_parts.get_node("PowerLink")
	left_joystick = cab_part.get_node("LeftJoystick")
	right_joystick = cab_part.get_node("RightJoystick")
	travel_levers = [cab_part.get_node("LeftTravelLever"), cab_part.get_node("RightTravelLever")]

	_setup_track_loop()
	_track_shoes = [[], []]
	_wheels = [[], []]
	for side in 2:
		var prefix := "Undercarriage_%s" % ("Left" if side == 0 else "Right")
		for i in params.track_shoe_count:
			_track_shoes[side].append(undercarriage_parts.get_node("%sTrackShoe_%02d" % [prefix, i]))
		_wheels[side] = [undercarriage_parts.get_node(prefix + "Idler"), undercarriage_parts.get_node(prefix + "Sprocket")]


func update(_stick_deg: float, bucket_deg: float) -> void:
	var p := params
	# Boom cylinders: barrel on the turret, rod on the boom.
	for i in _boom_barrels.size():
		var lateral := (-1.0 if i == 0 else 1.0) * p.boom_cyl_lateral
		var base := p.boom_foot + ArmGeometry.to_local(p.boom_cyl_base, lateral)
		var rod_end := ArmGeometry.to_local(p.boom_cyl_rod_end, lateral)
		_aim(_boom_barrels[i], base, boom.transform * rod_end)
		_aim(_boom_rods[i], rod_end, boom.transform.affine_inverse() * base)

	# Stick cylinder: barrel on the boom, rod on the stick tail.
	var stick_base := ArmGeometry.to_local(p.stick_cyl_base)
	var stick_rod_end := ArmGeometry.to_local(p.stick_cyl_rod_end)
	_aim(_stick_barrel, stick_base, stick.transform * stick_rod_end)
	_aim(_stick_rod, stick_rod_end, stick.transform.affine_inverse() * stick_base)

	# Bucket cylinder and linkage, all in stick space.
	var linkage := ArmGeometry.bucket_linkage(p, bucket_deg)
	if linkage.is_empty():
		return
	var joint := ArmGeometry.to_local(linkage["joint"])
	var bucket_base := ArmGeometry.to_local(p.bucket_cyl_base)
	_aim(_bucket_barrel, bucket_base, joint)
	_aim(_bucket_rod, joint, bucket_base)
	_aim(_rocker, ArmGeometry.to_local(p.rocker_pivot), joint)
	_aim(_power_link, joint, ArmGeometry.to_local(linkage["bucket_link_pin"]))


## Shoes run around the loop as in the primitives; idlers and sprockets turn with them.
func update_tracks(left_distance: float, right_distance: float) -> void:
	super(left_distance, right_distance)
	for side in _wheels.size():
		var distance := left_distance if side == 0 else right_distance
		for wheel: Node3D in _wheels[side]:
			wheel.rotation.x = -distance / _track_loop_radius


func _group(parent: Node3D) -> Node3D:
	clear([parent])
	var group := Node3D.new()
	group.name = MODEL_GROUP_NAME
	parent.add_child(group)
	return group


## Moves the parts of a model pivot under a new group of the matching simulator pivot.
func _move_parts(source: Node, pivot: Node3D) -> Node3D:
	var group := _group(pivot)
	for child in source.get_children():
		if not OWN_PIVOTS.has(String(child.name)):
			child.reparent(group, false)
	return group


## Puts a cylinder or link node on its pin, its local -Z toward the other pin.
static func _aim(node: Node3D, from: Vector3, to: Vector3) -> void:
	if from.distance_squared_to(to) < 1e-8:
		return
	node.transform = Transform3D(MeshKit.side_basis_z(to - from), from)


## The glass keeps its depth pre-pass from the import, which would shade the cab.
static func _disable_transparent_shadows(node: MeshInstance3D) -> void:
	for i in node.mesh.get_surface_count():
		var material := node.mesh.surface_get_material(i) as BaseMaterial3D
		if material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return
