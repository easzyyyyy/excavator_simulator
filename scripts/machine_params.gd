@tool
class_name MachineParams
extends Resource
## Complete description of one machine: arm and bucket geometry, joint limits,
## hydraulic cylinders, pumps, engine, masses and approximate body dimensions.
##
## Side-plane points are Vector2(u, v): u points forward along the part, v is
## perpendicular and points up when the part is horizontal. A side-plane point
## maps to the part's local 3D space as Vector3(x, v, -u).
##
## Positive joint angles raise or open: boom up, stick out, bucket dump.
## Boom angle is measured from the turret horizontal, stick angle from the boom
## pin line, bucket angle (pin to tooth tip) from the stick pin line.

@export_group("Arm geometry")
## Boom foot pin in turret space (x right, y up, z negative forward).
@export var boom_foot := Vector3(0.30, 2.10, -0.15)
## Boom foot pin to boom nose pin.
@export var boom_length := 5.70
## Stick pivot pin to bucket pin.
@export var stick_length := 2.90
## Bucket pin to tooth tip.
@export var bucket_tip_radius := 1.56
@export var bucket_width := 1.20
## Bucket side profile, convex, in the bucket side plane: from the back rim near the
## pin, over the back and bottom plates, to the tooth tip at (bucket_tip_radius, 0).
## The closing edge from the tip to the first point is the opening (strike-off plane).
@export var bucket_profile := PackedVector2Array([
	Vector2(0.0, 0.14), Vector2(0.40, 0.63), Vector2(1.10, 0.63), Vector2(1.50, 0.16), Vector2(1.56, 0.0)])

@export_group("Joint limits (deg)")
@export var boom_min_deg := -50.0
@export var boom_max_deg := 55.0
@export var stick_min_deg := -158.0
@export var stick_max_deg := -28.0
@export var bucket_min_deg := -140.0
@export var bucket_max_deg := 35.0

@export_group("Rest pose (deg)")
@export var rest_boom_deg := 15.0
@export var rest_stick_deg := -110.0
@export var rest_bucket_deg := -90.0

@export_group("Rod speeds (m/s)")
## Full-lever rod speeds, calibrated so that the full strokes, with the spool ramp and
## the cushion, take the reference function times below. The pump flow sharing only
## slows them when functions run together or under heavy load.
@export var boom_raise_rod_speed := 0.412
@export var boom_lower_rod_speed := 0.529
@export var stick_out_rod_speed := 0.629
@export var stick_in_rod_speed := 0.390
@export var bucket_dump_rod_speed := 0.530
@export var bucket_curl_rod_speed := 0.312
## Time for a spool to open fully from neutral.
@export var joint_accel_time := 0.30
## Time for a spool to close from fully open.
@export var joint_decel_time := 0.20
## Stroke length of the end-of-stroke cushion (m).
@export var cushion_length := 0.06
## Speed fraction left at the very end of the stroke.
@export var cushion_speed_factor := 0.35

@export_group("Hydraulic system")
## Rated implement flow of both pumps (Cat 320: 2 x 214.5 L/min).
@export var pump_flow_lpm := 429.0
## Implement relief pressure (Cat 320, normal mode: 35 MPa).
@export var relief_pressure_mpa := 35.0
## Swing relief pressure (Cat 320: 27.5 MPa).
@export var swing_relief_pressure_mpa := 27.5
## Largest power the pumps draw. Unsourced: 85 % of the net engine power.
@export var pump_power_kw := 109.0

@export_group("Engine")
## Cat 320, ISO 9249 net power.
@export var engine_net_power_kw := 128.5
## Unsourced class values: low idle, and the working speed with a lever moved.
@export var engine_idle_rpm := 1000.0
@export var engine_working_rpm := 1800.0
## Engine speed lost when the pumps draw their full power. Unsourced, tuned by ear.
@export var engine_lug_rpm := 220.0
## Time to rise from idle to working speed and to fall back.
@export var engine_rev_up_time := 0.8
@export var engine_rev_down_time := 1.5
## Time constant of the speed drop and recovery under pump load.
@export var engine_lug_time := 0.25

@export_group("Swing")
@export var swing_speed_rpm := 11.25
## Cat 320: 82 kN m at the swing relief pressure.
@export var swing_torque_knm := 82.0
## Upper structure without the arm about the swing axis (kg m2). Estimated from the Cat
## component weights: 4.2 t counterweight about 2.3 m out, 1.9 t swing frame and about
## 4.3 t of engine, pumps, tanks and cab closer in.
@export var upper_swing_inertia := 31000.0
## Share of the estimated swing inertia (upper structure, arm and load) the turret turns
## with. Set to a third by hand: at full estimate the turret felt too slow to start and to
## stop. Still within the Doosan drift limit either way.
@export var swing_inertia_scale := 1.0 / 3.0

@export_group("Reference function times (s)")
## Unloaded full-stroke times used by the tests to validate the speeds above.
@export var ref_boom_raise_time := 3.3
@export var ref_boom_lower_time := 2.6
@export var ref_stick_out_time := 2.6
@export var ref_stick_in_time := 4.1
@export var ref_bucket_dump_time := 2.3
@export var ref_bucket_curl_time := 3.8

@export_group("Reference envelope (m)")
@export var ref_max_reach_ground := 9.86
@export var ref_max_dig_depth := 6.72
@export var ref_max_cutting_height := 9.37
@export var ref_max_loading_height := 6.49
## SAE J296 heaped capacity: struck volume plus a 1:1 heap (Cat 320 GD bucket).
@export var ref_bucket_heaped_capacity := 1.19

@export_group("Reference forces")
## ISO 6015 digging forces at the normal relief pressure (Cat 320, 1.56 m tip radius).
@export var ref_bucket_digging_force_kn := 150.0
@export var ref_stick_digging_force_kn := 106.0
## Load at the bucket pin, over the side, that tips the machine: the Cat 320 lift chart
## rates 3550 kg at 7.5 m radius with the pin at ground level, which is 75 % of tipping.
@export var ref_side_tipping_load_kg := 4730.0
@export var ref_side_tipping_radius := 7.5

@export_group("Boom cylinders")
## Base pin relative to the boom foot, in the turret side plane.
@export var boom_cyl_base := Vector2(0.145, -0.784)
## Rod end pin in the boom side plane.
@export var boom_cyl_rod_end := Vector2(2.496, -0.351)
## Lateral offset of each of the two boom cylinders from the boom centre.
@export var boom_cyl_lateral := 0.42
@export var boom_cyl_count := 2
@export var boom_cyl_closed_length := 1.803
@export var boom_cyl_stroke := 1.26
@export var boom_cyl_bore := 0.12
## Unsourced: usual rod over bore ratio for this class.
@export var boom_cyl_rod := 0.085

@export_group("Stick cylinder")
## Base pin in the boom side plane.
@export var stick_cyl_base := Vector2(3.050, 1.328)
## Rod end pin on the stick tail, in the stick side plane.
@export var stick_cyl_rod_end := Vector2(-0.793, 0.244)
@export var stick_cyl_closed_length := 2.193
@export var stick_cyl_stroke := 1.504
@export var stick_cyl_bore := 0.14
@export var stick_cyl_rod := 0.10

@export_group("Bucket cylinder and linkage")
## Base pin in the stick side plane.
@export var bucket_cyl_base := Vector2(0.278, 0.369)
@export var bucket_cyl_closed_length := 1.634
@export var bucket_cyl_stroke := 1.104
@export var bucket_cyl_bore := 0.12
@export var bucket_cyl_rod := 0.085
## Guide link (rocker) pivot on the stick, in the stick side plane.
@export var rocker_pivot := Vector2(2.424, -0.049)
@export var rocker_length := 0.655
## Power link from the rocker joint to the bucket.
@export var power_link_length := 0.620
## Power link pin on the bucket: distance from the bucket pin.
@export var bucket_link_radius := 0.503
## Power link pin on the bucket: angle from the tooth tip direction.
@export var bucket_link_angle_deg := 102.0

@export_group("Undercarriage (m)")
## Overall track length.
@export var track_length := 4.45
## Idler centre to sprocket centre ("length to center of rollers").
@export var track_contact_length := 3.65
@export var track_gauge := 2.38
@export var shoe_width := 0.60
@export var track_shoe_count := 49
@export var track_roller_count := 8
@export var carrier_roller_count := 2
@export var ground_clearance := 0.47

@export_group("Travel")
## Two-speed travel. Cat publishes only the high speed; low is the class value.
@export var travel_speed_low_kmh := 3.5
@export var travel_speed_high_kmh := 5.7
## Time for a track to reach high speed from rest, and to stop from high speed.
@export var travel_accel_time := 0.8
@export var travel_decel_time := 0.4
## Effective steering gauge over the real gauge: tracks slip sideways when turning.
@export var skid_steer_factor := 1.5
## Steepest slope the machine climbs at full traction.
@export var gradeability_deg := 35.0
## Slope beyond the gradeability over which traction fades to zero.
@export var slip_range_deg := 5.0

@export_group("Mass and ground contact")
## Cat 320 operating weight with 600 mm shoes.
@export var operating_mass := 21700.0
## Centre of mass of the whole machine in turret space with the arm in the rest pose
## (x right, y up, z negative forward).
@export var center_of_mass := Vector3(0.0, 1.35, -0.13)
## Arm parts, Cat component weights. The boom includes its lines, pins, the stick cylinder
## and the two boom cylinders (1900 + 340 kg); the stick includes the bucket cylinder and
## linkage. Centres of mass are estimates in each part's side plane.
@export var boom_mass := 2240.0
@export var boom_mass_center := Vector2(2.65, 0.35)
@export var stick_mass := 1110.0
@export var stick_mass_center := Vector2(1.1, 0.15)
@export var bucket_mass := 940.0
@export var bucket_mass_center := Vector2(0.75, 0.3)
## Machine without the arm about horizontal axes through its centre of mass (kg m2), for
## the lift about a track edge: across (pitch) and along (roll) the tracks. Estimated from
## the Cat component weights: a 10 t upper structure with its counterweight at the tail
## and an 8.5 t undercarriage, their centres about 1.4 m apart in height.
@export var body_pitch_inertia := 47000.0
@export var body_roll_inertia := 24000.0
## Body acceleration toward its rest pose when the ground drops away under it.
@export var settle_acceleration := 3.0

@export_group("Upper structure, approximate (m)")
@export var upper_width := 2.95
@export var upper_front_z := -1.30
@export var tail_swing_radius := 2.83
@export var counterweight_clearance := 1.05
@export var cab_width := 1.00
@export var cab_length := 1.85
@export var cab_top_height := 2.95

@export_group("Operator")
## Operator eye point in turret space.
@export var eye_position := Vector3(-0.95, 2.42, -0.45)


func swing_speed_deg_s() -> float:
	return swing_speed_rpm * 6.0
