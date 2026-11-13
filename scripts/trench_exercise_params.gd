@tool
class_name TrenchExerciseParams
extends Resource
## The "Réaliser une tranchée" task of the CACES R482 category B1 practical test
## (recommendation R482B, July 2026). Annex 2 gives what the examiner looks at: the
## straightness asked for, a flat trench bottom, the safety distance of the spoil
## windrow, and speed. Annex 3 gives the task 10 of the test's 100 points, a pass mark of
## 70 % and the eliminatory manoeuvres; annex 4 scores 0 beyond 130 % of the reference
## time. The trench itself, the tolerances, the split of the 10 points and the reference
## time are left to each test centre: those numbers are this simulator's choice.
##
## The trench runs along the grid Z axis, from its far end toward the machine. The default
## outline puts every edge midway between grid points 0.25 m apart, so each point is
## either in the trench or out of it.

## Name shown to the operator, in French.
@export var display_name := "Réaliser une tranchée"

@export_group("Trench (m)")
@export var axis_x := -8.0
@export var far_end_z := 3.875
@export var length := 6.0
## Five grid cells, for a 1.20 m bucket.
@export var width := 1.25
@export var depth := 1.0
## Start place: swing axis this far behind the far end, arm plane on the axis, facing it.
@export var start_distance := 7.5

@export_group("Tolerances (m)")
## Bottom points within this of the required depth score in full.
@export var bottom_tolerance := 0.05
## Bottom points within this score half.
@export var bottom_tolerance_half := 0.10
## A section may be dug past an edge or an end by up to this much and stay on the line.
@export var edge_tolerance := 0.30
## Clear strip between the trench edges and the spoil. Code du travail R4534-32 asks for
## 40 cm along trenches deeper than 1.30 m; the test asks for a safety distance at any depth.
@export var berm_width := 0.40
## Spoil rising less than this above the ground on the berm still leaves it clear.
@export var berm_spoil_tolerance := 0.05
## Share of the trench dug at least half deep for the work to count as done: short of it,
## the spoil and the speed score nothing.
@export var completion_share := 0.9

@export_group("Time (s)")
@export var reference_time := 480.0
@export var time_limit_ratio := 1.3

@export_group("Points")
@export var straightness_points := 3.0
@export var bottom_points := 3.0
@export var berm_points := 2.0
@export var speed_points := 2.0
## 70 % of the task, the pass mark of the practical test.
@export var pass_points := 7.0

@export_group("Travelling with a raised load")
## Eliminatory in annex 3: the tracks moving faster than this (m/s) while the bucket holds
## more than high_load_fill (m3) with its lowest point higher than high_load_height above
## the track plane (m).
@export var high_load_speed := 0.1
@export var high_load_fill := 0.1
@export var high_load_height := 1.0


## Trench outline on the ground (x, z).
func outline() -> Rect2:
	return Rect2(axis_x - width * 0.5, far_end_z, width, length)


func time_limit() -> float:
	return reference_time * time_limit_ratio


func total_points() -> float:
	return straightness_points + bottom_points + berm_points + speed_points
