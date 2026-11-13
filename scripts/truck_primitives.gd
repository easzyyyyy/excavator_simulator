@tool
class_name TruckPrimitives
extends RefCounted
## Placeholder geometry of a rigid tipper truck, sized from TruckParams: frame rails, cab
## with its glazing, wheels, fuel tank, front ram and the steel body. Shapes that matter to
## the excavator (cab, body walls and floor, wheels, frame) also come out as boxes in truck
## space, for the bucket to butt against. Small details stay inside those boxes.

const GROUP_NAME := "Primitives"
const RAIL_HEIGHT := 0.27
const BUMPER_HEIGHT := 0.35
const TANK_SIZE := Vector3(0.6, 0.6, 1.2)

var params: TruckParams


func build(p_params: TruckParams, root: Node3D) -> void:
	params = p_params
	var old := root.get_node_or_null(GROUP_NAME)
	if old:
		root.remove_child(old)
		old.free()
	var group := Node3D.new()
	group.name = GROUP_NAME
	root.add_child(group)
	for shape in solid_boxes():
		var key: String = shape["look"]
		if key == "":
			continue
		var box: AABB = shape["box"]
		MeshKit.box(group, shape["name"], box.size, box.get_center(), key)
	_build_wheels(group)
	_build_glazing(group)
	_build_ram(group)


## Truck parts as boxes in truck space: name, box, and material key ("" for wheels, drawn
## as cylinders).
func solid_boxes() -> Array[Dictionary]:
	var p := params
	var shapes: Array[Dictionary] = []
	var length := p.overall_length()
	var rail_x := p.frame_width * 0.5 - 0.045
	for side in [-1.0, 1.0]:
		shapes.append(_shape("FrameRail", Vector3(side * rail_x, p.frame_height - RAIL_HEIGHT * 0.5, (0.3 + length) * 0.5),
				Vector3(0.09, RAIL_HEIGHT, length - 0.3), "black"))
	shapes.append(_shape("Bumper", Vector3(0.0, 0.45 + BUMPER_HEIGHT * 0.5, 0.15), Vector3(p.cab_width - 0.1, BUMPER_HEIGHT, 0.3),
			"black"))
	var cab_front := 0.02
	var cab_bottom := p.cab_floor_height - 0.45
	shapes.append(_shape("Cab", Vector3(0.0, (cab_bottom + p.cab_height) * 0.5, (cab_front + p.cab_back()) * 0.5),
			Vector3(p.cab_width, p.cab_height - cab_bottom, p.cab_back() - cab_front), "truck_cab"))
	var tank_z := p.axle_positions()[1] + 0.9 + TANK_SIZE.z * 0.5
	shapes.append(_shape("FuelTank", Vector3(p.frame_width * 0.5 + TANK_SIZE.x * 0.5 + 0.02, 0.75, tank_z), TANK_SIZE, "steel"))

	# Body: floor, side walls, headboard and tailgate around the inside.
	var inside_front := p.body_inside_front()
	var inside_rear := p.body_inside_rear()
	var wall := p.body_wall_thickness
	var outer_width := p.body_inner_width + wall * 2.0
	var floor_bottom := p.body_floor_height - p.body_floor_thickness
	var top := p.loading_height()
	var middle_z := (inside_front + inside_rear) * 0.5
	for side in [-1.0, 1.0]:
		shapes.append(_shape("Subframe", Vector3(side * rail_x, (p.frame_height + floor_bottom) * 0.5, middle_z),
				Vector3(0.09, floor_bottom - p.frame_height, p.body_inner_length), "black"))
	shapes.append(_shape("BodyFloor", Vector3(0.0, (floor_bottom + p.body_floor_height) * 0.5, middle_z),
			Vector3(outer_width, p.body_floor_thickness, p.body_inner_length + wall * 2.0), "truck_body"))
	for side in [-1.0, 1.0]:
		shapes.append(_shape("SideWall", Vector3(side * (p.body_inner_width + wall) * 0.5, (p.body_floor_height + top) * 0.5,
				middle_z), Vector3(wall, p.body_side_height, p.body_inner_length + wall * 2.0), "truck_body"))
	var headboard_top := top + p.headboard_extra_height
	shapes.append(_shape("Headboard", Vector3(0.0, (p.body_floor_height + headboard_top) * 0.5, inside_front - wall * 0.5),
			Vector3(outer_width, headboard_top - p.body_floor_height, wall), "truck_body"))
	shapes.append(_shape("Tailgate", Vector3(0.0, (p.body_floor_height + top) * 0.5, inside_rear + wall * 0.5),
			Vector3(outer_width, p.body_side_height, wall), "truck_body"))

	for axle in p.axle_positions():
		for side in [-1.0, 1.0]:
			var outer := p.rear_track_width * 0.5
			shapes.append(_shape("Wheels", Vector3(side * (outer - p.tyre_width), p.tyre_diameter * 0.5, axle),
					Vector3(p.tyre_width * 2.0, p.tyre_diameter, p.tyre_diameter), ""))
	return shapes


func _shape(node_name: String, centre: Vector3, size: Vector3, look: String) -> Dictionary:
	return {"name": node_name, "box": AABB(centre - size * 0.5, size), "look": look}


## Single tyres on the front axles, twin tyres on the rear ones.
func _build_wheels(group: Node3D) -> void:
	var p := params
	var axles := p.axle_positions()
	var radius := p.tyre_diameter * 0.5
	var outer := p.rear_track_width * 0.5
	for a in axles.size():
		for side in [-1.0, 1.0]:
			var offsets := [outer - p.tyre_width * 0.5] if a < 2 else [outer - p.tyre_width * 0.5, outer - p.tyre_width * 1.5 - 0.02]
			for offset in offsets:
				MeshKit.pin(group, "Tyre", Vector3(side * offset, radius, axles[a]), radius, p.tyre_width - 0.01, "rubber")
			MeshKit.pin(group, "Hub", Vector3(side * (outer - p.tyre_width * 0.5 + 0.02), radius, axles[a]), 0.28,
					p.tyre_width + 0.02, "steel")


func _build_glazing(group: Node3D) -> void:
	var p := params
	var windscreen_bottom := p.cab_floor_height + 0.35
	var windscreen_top := p.cab_height - 0.25
	MeshKit.box(group, "Windscreen", Vector3(p.cab_width - 0.3, windscreen_top - windscreen_bottom, 0.02),
			Vector3(0.0, (windscreen_bottom + windscreen_top) * 0.5, 0.0), "dark_glass")
	for side in [-1.0, 1.0]:
		MeshKit.box(group, "SideWindow", Vector3(0.02, windscreen_top - windscreen_bottom, 0.9),
				Vector3(side * (p.cab_width * 0.5 + 0.012), (windscreen_bottom + windscreen_top) * 0.5, 0.75), "dark_glass")


func _build_ram(group: Node3D) -> void:
	var p := params
	var ram_z := p.cab_back() + p.cab_to_body + p.ram_space * 0.5
	var bottom := p.frame_height
	var top := p.body_floor_height + p.body_side_height * 0.6
	var ram := MeshKit.cylinder(group, "FrontRam", 0.09, top - bottom, "steel")
	ram.position = Vector3(0.0, (bottom + top) * 0.5, ram_z)
