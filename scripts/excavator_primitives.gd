@tool
class_name ExcavatorPrimitives
extends RefCounted
## Placeholder geometry of the machine, sized from MachineParams. Static parts
## are built once under each pivot; cylinders, bucket linkage, track shoes and cab
## levers are updated every frame from the machine state.
##
## Body dimensions outside the arm are approximate; the arm, cylinder anchors
## and bucket linkage come from MachineParams and match the simulation.

const GROUP_NAME := "Primitives"
const SHOE_HEIGHT := 0.10
const TRAVEL_LEVER_REST_DEG := 12.0
const TRAVEL_LEVER_TILT_DEG := 18.0
const BUCKET_PLATE := 0.04
## Teeth: width across the bucket, thickness at the root and at the point, and how far the
## root sits back inside the end of the cutting edge.
const TOOTH_WIDTH := 0.09
const TOOTH_ROOT_THICKNESS := 0.044
const TOOTH_POINT_THICKNESS := 0.03
const TOOTH_ROOT_DEPTH := 0.01
const TOOTH_COUNT := 5

var params: MachineParams
var turret: Node3D
var boom: Node3D
var stick: Node3D

var boom_cylinders: Array[HydraulicCylinderVisual] = []
var stick_cylinder: HydraulicCylinderVisual
var bucket_cylinder: HydraulicCylinderVisual
var rocker_plates: Array[MeshInstance3D] = []
var power_link: MeshInstance3D
var link_joint_pin: MeshInstance3D
var left_joystick: Node3D
var right_joystick: Node3D
var travel_levers: Array[Node3D] = []

## Track shoes per side (left, right) and the loop they run around.
var _track_shoes: Array[Array] = [[], []]
var _track_x := PackedFloat32Array([0.0, 0.0])
var _track_half_contact := 1.0
var _track_axle_height := 0.4
var _track_loop_radius := 0.35
var _track_loop_length := 1.0


func build(p_params: MachineParams, undercarriage: Node3D, p_turret: Node3D, cab: Node3D,
		p_boom: Node3D, p_stick: Node3D, bucket: Node3D) -> void:
	params = p_params
	turret = p_turret
	boom = p_boom
	stick = p_stick
	_build_undercarriage(_group(undercarriage))
	_build_turret(_group(turret))
	_build_cab(_group(cab))
	_build_boom(_group(boom))
	_build_stick(_group(stick))
	_build_bucket(_group(bucket))


func update(stick_deg: float, bucket_deg: float) -> void:
	# Boom cylinders: base on the turret, rod end on the boom.
	for i in boom_cylinders.size():
		var side := -1.0 if i == 0 else 1.0
		var lateral := side * params.boom_cyl_lateral
		var base := params.boom_foot + ArmGeometry.to_local(params.boom_cyl_base, lateral)
		var rod_end := boom.transform * ArmGeometry.to_local(params.boom_cyl_rod_end, lateral)
		boom_cylinders[i].update(base, rod_end)

	# Stick cylinder: base on the boom, rod end on the stick tail.
	var stick_rod_end := stick.transform * ArmGeometry.to_local(params.stick_cyl_rod_end)
	stick_cylinder.update(ArmGeometry.to_local(params.stick_cyl_base), stick_rod_end)

	# Bucket cylinder and linkage, all in stick space.
	var linkage := ArmGeometry.bucket_linkage(params, bucket_deg)
	if not linkage.is_empty():
		var joint := ArmGeometry.to_local(linkage["joint"])
		bucket_cylinder.update(ArmGeometry.to_local(params.bucket_cyl_base), joint)
		var pivot := ArmGeometry.to_local(params.rocker_pivot)
		var link_pin := ArmGeometry.to_local(linkage["bucket_link_pin"])
		for plate in rocker_plates:
			_place_beam(plate, Vector3(plate.position.x, pivot.y, pivot.z), Vector3(plate.position.x, joint.y, joint.z))
		_place_beam(power_link, link_pin, joint)
		link_joint_pin.position = joint


## Joysticks follow the sticks; in travel mode they rest and the travel levers move.
func update_operator(controls: ControlInput) -> void:
	_tilt_joystick(left_joystick, Vector2.ZERO if controls.travel_mode else controls.left_stick)
	_tilt_joystick(right_joystick, Vector2.ZERO if controls.travel_mode else controls.right_stick)
	for i in travel_levers.size():
		var command := controls.left_track if i == 0 else controls.right_track
		travel_levers[i].rotation.x = deg_to_rad(TRAVEL_LEVER_REST_DEG - command * TRAVEL_LEVER_TILT_DEG)


## Shoes run around each track loop by the distance that track has turned.
func update_tracks(left_distance: float, right_distance: float) -> void:
	for side in _track_shoes.size():
		var shoes := _track_shoes[side]
		if shoes.is_empty():
			continue
		var distance := left_distance if side == 0 else right_distance
		var spacing := _track_loop_length / shoes.size()
		for i in shoes.size():
			var shoe: MeshInstance3D = shoes[i]
			shoe.transform = _track_shoe_transform(fposmod(distance + i * spacing, _track_loop_length), _track_x[side])


func _group(parent: Node3D) -> Node3D:
	var old := parent.get_node_or_null(GROUP_NAME)
	if old:
		parent.remove_child(old)
		old.free()
	var group := Node3D.new()
	group.name = GROUP_NAME
	parent.add_child(group)
	return group


func _build_undercarriage(root: Node3D) -> void:
	var p := params
	_setup_track_loop()
	var end_radius := _track_axle_height
	var shoe_mesh := BoxMesh.new()
	shoe_mesh.size = Vector3(p.shoe_width, SHOE_HEIGHT, _track_loop_length / p.track_shoe_count * 0.8)
	var wheel_radius := end_radius - SHOE_HEIGHT - 0.01
	var roller_radius := 0.09
	_track_shoes = [[], []]
	for side in 2:
		var x := _track_x[side]
		MeshKit.box(root, "TrackFrame", Vector3(p.shoe_width * 0.5, wheel_radius * 1.2, p.track_contact_length),
				Vector3(x, end_radius, 0.0), "black")
		MeshKit.pin(root, "Idler", Vector3(x, end_radius, -_track_half_contact), wheel_radius, p.shoe_width * 0.45)
		MeshKit.pin(root, "Sprocket", Vector3(x, end_radius, _track_half_contact), wheel_radius, p.shoe_width * 0.35)
		for i in p.track_roller_count:
			var u := lerpf(-_track_half_contact + 0.45, _track_half_contact - 0.45,
					float(i) / maxf(p.track_roller_count - 1, 1))
			MeshKit.pin(root, "TrackRoller", Vector3(x, SHOE_HEIGHT + roller_radius, -u), roller_radius, p.shoe_width * 0.4)
		for i in p.carrier_roller_count:
			var u := lerpf(-_track_half_contact * 0.45, _track_half_contact * 0.45,
					float(i) / maxf(p.carrier_roller_count - 1, 1))
			MeshKit.pin(root, "CarrierRoller", Vector3(x, 2.0 * end_radius - SHOE_HEIGHT - 0.07, -u), 0.07,
					p.shoe_width * 0.3)
		for i in p.track_shoe_count:
			var shoe := MeshInstance3D.new()
			shoe.name = "Shoe"
			shoe.mesh = shoe_mesh
			shoe.material_override = MeshKit.material("track")
			root.add_child(shoe)
			_track_shoes[side].append(shoe)
	MeshKit.box(root, "Carbody", Vector3(p.track_gauge - p.shoe_width, 0.45, 2.3),
			Vector3(0, p.ground_clearance + 0.225, 0), "black")
	var ring := MeshKit.cylinder(root, "SwingRing", 1.05, 0.12, "black")
	ring.position = Vector3(0, 1.0, 0)
	update_tracks(0.0, 0.0)


## Idler (front) and sprocket (rear) centres are track_contact_length apart and the
## track wraps around them, so its outer radius fills the overall length.
func _setup_track_loop() -> void:
	var p := params
	var end_radius := (p.track_length - p.track_contact_length) * 0.5
	_track_half_contact = p.track_contact_length * 0.5
	_track_axle_height = end_radius
	_track_loop_radius = end_radius - SHOE_HEIGHT * 0.5
	_track_loop_length = 2.0 * p.track_contact_length + TAU * _track_loop_radius
	for side in 2:
		_track_x[side] = (-1.0 if side == 0 else 1.0) * p.track_gauge * 0.5


## Shoe pose at a distance along the loop. The loop starts under the idler and runs
## rearward along the ground, the way the shoes move relative to the machine when
## it drives forward, then up around the sprocket and forward along the top.
func _track_shoe_transform(s: float, x: float) -> Transform3D:
	var contact := _track_half_contact * 2.0
	var r := _track_loop_radius
	var arc := PI * r
	var point: Vector2
	var tangent: Vector2
	if s < contact:
		point = Vector2(_track_half_contact - s, _track_axle_height - r)
		tangent = Vector2.LEFT
	elif s < contact + arc:
		var angle := -PI * 0.5 - (s - contact) / r
		point = Vector2(-_track_half_contact, _track_axle_height) + Vector2(cos(angle), sin(angle)) * r
		tangent = Vector2(sin(angle), -cos(angle))
	elif s < 2.0 * contact + arc:
		point = Vector2(-_track_half_contact + s - contact - arc, _track_axle_height + r)
		tangent = Vector2.RIGHT
	else:
		var angle := PI * 0.5 - (s - 2.0 * contact - arc) / r
		point = Vector2(_track_half_contact, _track_axle_height) + Vector2(cos(angle), sin(angle)) * r
		tangent = Vector2(sin(angle), -cos(angle))
	return Transform3D(MeshKit.side_basis_z(ArmGeometry.to_local(tangent)), ArmGeometry.to_local(point, x))


func _build_turret(root: Node3D) -> void:
	var p := params
	var deck_y := p.counterweight_clearance
	var front := p.upper_front_z
	var rear := p.tail_swing_radius
	# The deck stops where the counterweight starts: faces sharing a plane flicker.
	var counterweight_front := rear - 0.8
	MeshKit.box(root, "Deck", Vector3(p.upper_width, 0.2, counterweight_front - front),
			Vector3(0, deck_y + 0.1, (front + counterweight_front) * 0.5), "black")
	MeshKit.box(root, "Counterweight", Vector3(p.upper_width, 1.15, rear - counterweight_front),
			Vector3(0, deck_y + 0.575, (counterweight_front + rear) * 0.5), "yellow")
	MeshKit.box(root, "EngineHood", Vector3(p.upper_width, 0.85, 1.55),
			Vector3(0, deck_y + 0.2 + 0.425, rear - 0.8 - 0.775), "yellow")
	var tank_left := p.boom_foot.x + 0.45
	var tank_right := p.upper_width * 0.5
	MeshKit.box(root, "Tank", Vector3(tank_right - tank_left, 0.9, 1.8),
			Vector3((tank_left + tank_right) * 0.5, deck_y + 0.2 + 0.45, front + 0.9), "yellow")
	var exhaust := MeshKit.cylinder(root, "Exhaust", 0.06, 0.45, "black")
	exhaust.position = Vector3(0.9, deck_y + 1.3, rear - 1.3)

	# Boom foot bracket and boom cylinder base lugs.
	var bracket_bottom := deck_y + 0.2
	var bracket_top := p.boom_foot.y + 0.12
	MeshKit.box(root, "BoomFootBracket", Vector3(0.8, bracket_top - bracket_bottom, 0.9),
			Vector3(p.boom_foot.x, (bracket_top + bracket_bottom) * 0.5, p.boom_foot.z), "yellow")
	for side in [-1.0, 1.0]:
		var base: Vector3 = p.boom_foot + ArmGeometry.to_local(p.boom_cyl_base, side * p.boom_cyl_lateral)
		MeshKit.box(root, "BoomCylinderLug", Vector3(0.1, base.y - bracket_bottom + 0.12, 0.28),
				Vector3(base.x + side * 0.12, (base.y + bracket_bottom) * 0.5 + 0.06, base.z), "yellow")
		MeshKit.pin(root, "BoomCylinderBasePin", base, 0.06, 0.34)
		var cylinder := HydraulicCylinderVisual.new(root, "BoomCylinder", p.boom_cyl_closed_length,
				p.boom_cyl_stroke, p.boom_cyl_bore)
		boom_cylinders.append(cylinder)


func _build_cab(root: Node3D) -> void:
	var p := params
	var cx := -p.upper_width * 0.5 + p.cab_width * 0.5
	var front := p.upper_front_z
	var rear := front + p.cab_length
	var cz := (front + rear) * 0.5
	var floor_y := p.counterweight_clearance + 0.25
	var top := p.cab_top_height
	var post_h := top - floor_y
	var half_w := p.cab_width * 0.5 - 0.035
	var half_l := p.cab_length * 0.5 - 0.035

	MeshKit.box(root, "Floor", Vector3(p.cab_width, 0.06, p.cab_length), Vector3(cx, floor_y, cz), "black")
	MeshKit.box(root, "Roof", Vector3(p.cab_width + 0.04, 0.07, p.cab_length + 0.04),
			Vector3(cx, top - 0.035, cz), "black")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			MeshKit.box(root, "Post", Vector3(0.07, post_h, 0.07),
					Vector3(cx + sx * half_w, floor_y + post_h * 0.5, cz + sz * half_l), "black")
	MeshKit.box(root, "DoorPost", Vector3(0.06, post_h, 0.06),
			Vector3(cx - half_w, floor_y + post_h * 0.5, cz + 0.2), "black")
	MeshKit.box(root, "RearWall", Vector3(p.cab_width, post_h, 0.05), Vector3(cx, floor_y + post_h * 0.5, rear - 0.03), "black")
	MeshKit.box(root, "FrontSill", Vector3(p.cab_width - 0.07, 0.07, 0.06),
			Vector3(cx, floor_y + 0.33, front + 0.03), "black")
	MeshKit.box(root, "RightLowerPanel", Vector3(0.05, 0.45, p.cab_length - 0.07),
			Vector3(cx + half_w, floor_y + 0.25, cz), "black")

	MeshKit.box(root, "GlassFront", Vector3(p.cab_width - 0.07, post_h - 0.1, 0.01),
			Vector3(cx, floor_y + post_h * 0.5, front + 0.015), "glass")
	MeshKit.box(root, "GlassLeft", Vector3(0.01, post_h - 0.1, p.cab_length - 0.07),
			Vector3(cx - half_w - 0.02, floor_y + post_h * 0.5, cz), "glass")
	MeshKit.box(root, "GlassRight", Vector3(0.01, post_h - 0.55, p.cab_length - 0.07),
			Vector3(cx + half_w + 0.02, floor_y + 0.5 + (post_h - 0.55) * 0.5, cz), "glass")
	MeshKit.box(root, "GlassRoof", Vector3(p.cab_width - 0.2, 0.01, 0.6),
			Vector3(cx, top - 0.08, front + 0.45), "glass")

	# Seat and consoles around the eye point.
	var eye := p.eye_position
	var seat_y := eye.y - 0.72
	var seat_z := eye.z + 0.25
	MeshKit.box(root, "SeatCushion", Vector3(0.5, 0.12, 0.5), Vector3(eye.x, seat_y, seat_z), "seat")
	var back := MeshKit.box(root, "SeatBack", Vector3(0.5, 0.75, 0.1), Vector3(eye.x, seat_y + 0.42, seat_z + 0.27), "seat")
	back.rotation.x = deg_to_rad(-12.0)
	var console_y := seat_y + 0.08
	var console_z := seat_z - 0.12
	for side in [-1.0, 1.0]:
		MeshKit.box(root, "Console", Vector3(0.16, 0.22, 0.55),
				Vector3(eye.x + side * 0.36, console_y, console_z), "black")
	left_joystick = _joystick(root, "LeftJoystick", Vector3(eye.x - 0.36, console_y + 0.11, console_z - 0.18))
	right_joystick = _joystick(root, "RightJoystick", Vector3(eye.x + 0.36, console_y + 0.11, console_z - 0.18))
	travel_levers.clear()
	for side in [-1.0, 1.0]:
		var lever := Node3D.new()
		lever.name = "TravelLever"
		lever.position = Vector3(eye.x + side * 0.1, floor_y + 0.22, front + 0.45)
		lever.rotation.x = deg_to_rad(TRAVEL_LEVER_REST_DEG)
		root.add_child(lever)
		MeshKit.box(lever, "Rod", Vector3(0.03, 0.45, 0.03), Vector3(0, 0.225, 0), "black")
		travel_levers.append(lever)
		MeshKit.box(root, "TravelPedal", Vector3(0.1, 0.03, 0.22),
				Vector3(eye.x + side * 0.1, floor_y + 0.08, front + 0.3), "black")
	var screen := MeshKit.box(root, "Monitor", Vector3(0.22, 0.15, 0.03),
			Vector3(cx + half_w - 0.12, floor_y + 0.7, front + 0.25), "screen")
	screen.rotation.y = deg_to_rad(-25.0)


func _joystick(root: Node3D, node_name: String, position: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	pivot.position = position
	root.add_child(pivot)
	var shaft := MeshKit.cylinder(pivot, "Shaft", 0.012, 0.12, "steel")
	shaft.position = Vector3(0, 0.06, 0)
	var grip := MeshKit.cylinder(pivot, "Grip", 0.025, 0.11, "knob")
	grip.position = Vector3(0, 0.16, 0)
	return pivot


func _tilt_joystick(pivot: Node3D, input: Vector2) -> void:
	if pivot == null:
		return
	var max_tilt := deg_to_rad(22.0)
	pivot.rotation = Vector3(-input.y * max_tilt, 0.0, -input.x * max_tilt)


func _build_boom(root: Node3D) -> void:
	var p := params
	var foot := Vector2(-0.35, -0.05)
	var knee := Vector2(p.boom_length * 0.53, 0.45)
	var nose := Vector2(p.boom_length + 0.25, 0.0)
	MeshKit.beam(root, "BoomLower", ArmGeometry.to_local(foot), ArmGeometry.to_local(knee), 0.62, 0.8, "yellow")
	MeshKit.beam(root, "BoomUpper", ArmGeometry.to_local(knee), ArmGeometry.to_local(nose), 0.55, 0.62, "yellow", 0.2)
	MeshKit.pin(root, "FootPin", Vector3.ZERO, 0.1, 0.84)
	MeshKit.pin(root, "NosePin", ArmGeometry.to_local(Vector2(p.boom_length, 0)), 0.09, 0.72)

	var rod_end := p.boom_cyl_rod_end
	for side in [-1.0, 1.0]:
		var x: float = side * (p.boom_cyl_lateral - 0.1)
		MeshKit.beam(root, "BoomCylinderEar", ArmGeometry.to_local(rod_end, x),
				ArmGeometry.to_local(rod_end + Vector2(-0.15, 0.55), x), 0.05, 0.22, "yellow", 0.08)
	MeshKit.pin(root, "BoomCylinderRodPin", ArmGeometry.to_local(rod_end), 0.06, p.boom_cyl_lateral * 2.0 + 0.1)

	var stick_base := p.stick_cyl_base
	MeshKit.beam(root, "StickCylinderBracket", ArmGeometry.to_local(stick_base + Vector2(-0.15, -0.75)),
			ArmGeometry.to_local(stick_base), 0.3, 0.3, "yellow", 0.06)
	MeshKit.pin(root, "StickCylinderBasePin", ArmGeometry.to_local(stick_base), 0.065, 0.36)
	stick_cylinder = HydraulicCylinderVisual.new(root, "StickCylinder", p.stick_cyl_closed_length,
			p.stick_cyl_stroke, p.stick_cyl_bore)


func _build_stick(root: Node3D) -> void:
	var p := params
	var tail := Vector2(-0.95, 0.2)
	var end := Vector2(p.stick_length + 0.1, -0.02)
	MeshKit.beam(root, "StickBody", ArmGeometry.to_local(tail), ArmGeometry.to_local(end), 0.42, 0.5, "yellow")
	MeshKit.pin(root, "PivotPin", Vector3.ZERO, 0.09, 0.64)
	MeshKit.pin(root, "StickCylinderRodPin", ArmGeometry.to_local(p.stick_cyl_rod_end), 0.065, 0.5)
	MeshKit.pin(root, "BucketCylinderBasePin", ArmGeometry.to_local(p.bucket_cyl_base), 0.06, 0.32)
	MeshKit.beam(root, "BucketCylinderBracket", ArmGeometry.to_local(p.bucket_cyl_base + Vector2(-0.1, -0.25)),
			ArmGeometry.to_local(p.bucket_cyl_base), 0.26, 0.22, "yellow", 0.05)
	MeshKit.pin(root, "BucketPin", ArmGeometry.to_local(Vector2(p.stick_length, 0)), 0.08, 0.52)
	MeshKit.pin(root, "RockerPivotPin", ArmGeometry.to_local(p.rocker_pivot), 0.06, 0.62)

	for side in [-1.0, 1.0]:
		var plate := MeshKit.box(root, "RockerPlate", Vector3(0.04, 0.12, p.rocker_length + 0.12),
				Vector3(side * 0.27, 0, 0), "black")
		rocker_plates.append(plate)
	power_link = MeshKit.box(root, "PowerLink", Vector3(0.36, 0.13, p.power_link_length + 0.12), Vector3.ZERO, "black")
	link_joint_pin = MeshKit.pin(root, "LinkJointPin", Vector3.ZERO, 0.06, 0.62)
	bucket_cylinder = HydraulicCylinderVisual.new(root, "BucketCylinder", p.bucket_cyl_closed_length,
			p.bucket_cyl_stroke, p.bucket_cyl_bore)


func _build_bucket(root: Node3D) -> void:
	var p := params
	var w := p.bucket_width
	# The soil profile ends with the teeth: its last corner before the tooth tip is the
	# cutting edge. Shell plates run outside the profile from the rim to the cutting edge,
	# side plates just inside the cutting width close along the opening, and the teeth
	# stick out from the cutting edge to the tip.
	var tip := p.bucket_profile[p.bucket_profile.size() - 1]
	var profile := p.bucket_profile.slice(0, p.bucket_profile.size() - 1)
	var lip := profile[profile.size() - 1]
	var centroid := Vector2.ZERO
	for point in profile:
		centroid += point / profile.size()
	for i in profile.size() - 1:
		var a := profile[i]
		var b := profile[i + 1]
		var outward := Vector2(b.y - a.y, a.x - b.x).normalized()
		if outward.dot(a - centroid) < 0.0:
			outward = -outward
		var offset := outward * BUCKET_PLATE * 0.5
		var along := (b - a).normalized() * BUCKET_PLATE * 0.5
		# The bottom plate ends just inside the cutting edge rather than in its end face.
		var end := b + along if i < profile.size() - 2 else b - along * 0.5
		MeshKit.beam(root, "Shell", ArmGeometry.to_local(a - along + offset), ArmGeometry.to_local(end + offset),
				w, BUCKET_PLATE, "black")
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for side in [-1.0, 1.0]:
		var outer: float = side * w * 0.5
		MeshKit.add_side_prism(vertices, normals, profile, outer - side * BUCKET_PLATE, outer)
	var plates := MeshInstance3D.new()
	plates.name = "SidePlates"
	plates.mesh = MeshKit.array_mesh(vertices, normals)
	plates.material_override = MeshKit.material("black")
	root.add_child(plates)
	# Steel cutting edge over the front of the bottom plate, a little wider and thicker so
	# that no face lies in a shell face.
	var floor_dir := (lip - profile[profile.size() - 2]).normalized()
	var floor_out := Vector2(floor_dir.y, -floor_dir.x)
	if floor_out.dot(lip - centroid) < 0.0:
		floor_out = -floor_out
	var edge_middle := floor_out * BUCKET_PLATE * 0.5
	MeshKit.beam(root, "CuttingEdge", ArmGeometry.to_local(lip - floor_dir * 0.2 + edge_middle),
			ArmGeometry.to_local(lip + edge_middle), w + 0.02, BUCKET_PLATE + 0.02, "steel")
	# Each tooth leaves the end of the cutting edge from its middle and tapers to the tip. Its
	# root stays inside the cutting edge: a tooth corner poking through a face makes small
	# slivers that shimmer as the bucket moves.
	var root_center := lip - floor_dir * TOOTH_ROOT_DEPTH + edge_middle
	var axis := (tip - root_center).normalized()
	var across := Vector2(-axis.y, axis.x)
	var tooth := PackedVector2Array([
		root_center + across * TOOTH_ROOT_THICKNESS * 0.5, tip + across * TOOTH_POINT_THICKNESS * 0.5,
		tip - across * TOOTH_POINT_THICKNESS * 0.5, root_center - across * TOOTH_ROOT_THICKNESS * 0.5])
	var tooth_vertices := PackedVector3Array()
	var tooth_normals := PackedVector3Array()
	for i in TOOTH_COUNT:
		var x := lerpf(-w * 0.5 + TOOTH_WIDTH, w * 0.5 - TOOTH_WIDTH, float(i) / float(TOOTH_COUNT - 1))
		MeshKit.add_side_prism(tooth_vertices, tooth_normals, tooth, x - TOOTH_WIDTH * 0.5, x + TOOTH_WIDTH * 0.5)
	var teeth := MeshInstance3D.new()
	teeth.name = "Teeth"
	teeth.mesh = MeshKit.array_mesh(tooth_vertices, tooth_normals)
	teeth.material_override = MeshKit.material("steel")
	root.add_child(teeth)
	var link_pin := Vector2.RIGHT.rotated(deg_to_rad(p.bucket_link_angle_deg)) * p.bucket_link_radius
	for side in [-1.0, 1.0]:
		MeshKit.beam(root, "Ear", ArmGeometry.to_local(Vector2(0.1, 0.25), side * 0.24),
				ArmGeometry.to_local(link_pin, side * 0.24), 0.05, 0.22, "black", 0.08)
		MeshKit.beam(root, "Ear", ArmGeometry.to_local(Vector2(0.25, 0.4), side * 0.24),
				ArmGeometry.to_local(Vector2.ZERO, side * 0.24), 0.05, 0.22, "black", 0.08)
	MeshKit.pin(root, "LinkPin", ArmGeometry.to_local(link_pin), 0.06, 0.55)


func _place_beam(node: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	if a.distance_squared_to(b) < 1e-8:
		return
	node.transform = Transform3D(MeshKit.side_basis_z(b - a), (a + b) * 0.5)
