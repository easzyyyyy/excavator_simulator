@tool
class_name TruckParams
extends Resource
## One rigid tipper truck: chassis, cab and body dimensions, and masses.
##
## Truck space: x across to the right, y up from the ground, z back from the front bumper
## along the truck (the cab looks toward -Z).
##
## Defaults: MAN TGS 32.400 8x4 BB normal height tipper chassis (MAN UK bodybuilder sheet,
## May 2022) with a MEILLER P430 rear tipper body (up to 17 m3, side walls 1.2 to 1.5 m).
## The sheets give the chassis and cab; the body inner length fills the space behind the
## cab less the front ram, and the inner width and floor height are the usual values for
## such a body on a 2.5 m wide truck.

@export_group("Chassis (m)")
## Front bumper to first front axle (MAN L5).
@export var front_overhang := 1.475
## First to second front axle (MAN L3).
@export var front_axle_spread := 1.795
## Second front axle to first rear axle (MAN L1, short wheelbase).
@export var wheelbase := 3.205
## Between the two rear axles (MAN L2).
@export var rear_bogie_spread := 1.4
## Last axle to the rear end of the frame (MAN L7).
@export var rear_overhang := 0.8
## Top of the frame over the rear wheels, unladen (MAN H3).
@export var frame_height := 1.046
## Outside width of the frame rails.
@export var frame_width := 0.85
## Width across the rear tyres (MAN B1).
@export var rear_track_width := 2.462
## 295/80 R 22.5 tyres: 571.5 mm rim plus twice 236 mm of sidewall.
@export var tyre_diameter := 1.044
@export var tyre_width := 0.295

@export_group("Cab (m)")
## First front axle to the back of the cab (MAN L9).
@export var axle_to_cab_back := 0.49
## Cab width over the wings (MAN B2) and roof height, unladen (MAN H1).
@export var cab_width := 2.499
@export var cab_height := 3.158
## Height of the cab floor above the ground, estimated from the frame.
@export var cab_floor_height := 1.25

@export_group("Body (m)")
## Back of the cab to the start of the body, where the front ram stands (MAN L10), and the
## space the front ram takes before the headboard.
@export var cab_to_body := 0.06
@export var ram_space := 0.45
@export var body_inner_length := 6.1
@export var body_inner_width := 2.3
@export var body_side_height := 1.2
## Headboard rising above the side walls.
@export var headboard_extra_height := 0.25
@export var body_wall_thickness := 0.05
## Top of the body floor above the ground, over the frame, subframe and cross members.
@export var body_floor_height := 1.35
@export var body_floor_thickness := 0.1

@export_group("Masses (kg)")
## Unladen chassis cab with fuel and driver (MAN sheet, short wheelbase).
@export var chassis_mass := 9432.0
## Body with its ram and subframe. Unsourced estimate for a light 17 m3 steel body.
@export var body_mass := 2800.0
## UK legal gross vehicle weight (MAN sheet); France allows the same 32 t for four axles.
@export var gross_mass := 32000.0

@export_group("Reference data")
## MEILLER P430 nominal volume and side wall height range.
@export var ref_body_max_volume := 17.0
@export var ref_side_height_range := Vector2(1.2, 1.5)


## Axle positions back from the front bumper (m).
func axle_positions() -> PackedFloat32Array:
	var first := front_overhang
	var second := first + front_axle_spread
	var third := second + wheelbase
	return PackedFloat32Array([first, second, third, third + rear_bogie_spread])


func overall_length() -> float:
	return axle_positions()[3] + rear_overhang


func cab_back() -> float:
	return front_overhang + axle_to_cab_back


## Front and rear of the body's inside, back from the front bumper.
func body_inside_front() -> float:
	return cab_back() + cab_to_body + ram_space + body_wall_thickness


func body_inside_rear() -> float:
	return body_inside_front() + body_inner_length


## Height of the side wall tops above the ground.
func loading_height() -> float:
	return body_floor_height + body_side_height


## Volume held level with the side walls (m3).
func struck_volume() -> float:
	return body_inner_length * body_inner_width * body_side_height


func payload() -> float:
	return gross_mass - chassis_mass - body_mass
