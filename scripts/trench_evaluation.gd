class_name TrenchEvaluation
extends RefCounted
## Scores a trench dug in the terrain against the CACES R482 B1 trench task
## (TrenchExerciseParams), from the ground surface alone, as an examiner judges the
## finished work. Depths are measured from the ground as capture() found it.
##
## - Straightness: every section of the trench (grid row) is dug at least half deep across
##   the whole width, and nowhere past an edge by more than edge_tolerance. Rows dug past
##   an end by more than that count as extra sections off the line.
## - Bottom: each point inside the outline scores in full within bottom_tolerance of the
##   required depth and half within bottom_tolerance_half, loose soil left on it included.
## - Spoil: nothing rises more than berm_spoil_tolerance above the ground on the berm all
##   round the outline. Soil that slid into a hole dug past the outline is not on the berm.
## - Speed: full up to the reference time, falling to nothing at the time limit.
## Each criterion is rounded to half a point. A trench dug short of completion_share gets
## nothing for spoil and speed. Past the time limit, or after an eliminatory manoeuvre, the
## task scores 0.

enum Failure { NONE, TIME_OVER, RAISED_LOAD }

## Ground measured around the outline, beyond the berm and the tolerances (m).
const MARGIN := 2.0

var params: TrenchExerciseParams
var terrain: Terrain

## Grid bounds of the measured ground and its heights at capture, row major.
var _from := Vector2i.ZERO
var _to := Vector2i.ZERO
var _reference := PackedFloat32Array()


## Keeps the ground heights around the trench before it is dug.
func capture(p_terrain: Terrain, p_params: TrenchExerciseParams) -> void:
	terrain = p_terrain
	params = p_params
	var area := params.outline().grow(MARGIN)
	_from = terrain.nearest_point(area.position.x, area.position.y)
	_to = terrain.nearest_point(area.end.x, area.end.y)
	_reference = PackedFloat32Array()
	for iz in range(_from.y, _to.y + 1):
		for ix in range(_from.x, _to.x + 1):
			_reference.append(terrain.point_height(ix, iz))


## Depth dug below the captured ground at a grid point (m), negative where soil was added.
func dug_depth(ix: int, iz: int) -> float:
	var columns := _to.x - _from.x + 1
	return _reference[(iz - _from.y) * columns + ix - _from.x] - terrain.point_height(ix, iz)


func score(elapsed: float, failure := Failure.NONE) -> Dictionary:
	var area := params.outline()
	var half_depth := params.depth * 0.5
	var berm := area.grow(params.berm_width)
	var lateral := Vector2(area.position.x - params.edge_tolerance, area.end.x + params.edge_tolerance)
	var ends := Vector2(area.position.y - params.edge_tolerance, area.end.y + params.edge_tolerance)
	var rows := 0
	var rows_on_line := 0
	var extra_rows := 0
	var inside := 0
	var dug := 0
	var within := 0
	var within_half := 0
	var depth_sum := 0.0
	var berm_points := 0
	var berm_clear := 0
	for iz in range(_from.y, _to.y + 1):
		var z := terrain.point_position(0, iz).y
		var in_length := z > area.position.y and z < area.end.y
		var past_end := z < ends.x or z > ends.y
		var covered := true
		var off_line := false
		for ix in range(_from.x, _to.x + 1):
			var x := terrain.point_position(ix, 0).x
			var depth := dug_depth(ix, iz)
			var deep := depth >= half_depth
			if in_length and x > area.position.x and x < area.end.x:
				inside += 1
				covered = covered and deep
				dug += 1 if deep else 0
				depth_sum += depth
				var error := absf(depth - params.depth)
				if error <= params.bottom_tolerance:
					within += 1
				elif error <= params.bottom_tolerance_half:
					within_half += 1
				continue
			var in_band := x >= lateral.x and x <= lateral.y
			if deep and ((in_length and not in_band) or (past_end and in_band)):
				off_line = true
			if berm.has_point(Vector2(x, z)):
				berm_points += 1
				if -depth <= params.berm_spoil_tolerance:
					berm_clear += 1
		if in_length:
			rows += 1
			if covered and not off_line:
				rows_on_line += 1
		elif off_line:
			extra_rows += 1

	inside = maxi(inside, 1)
	var complete := dug >= params.completion_share * inside
	var limit := params.time_limit()
	if failure == Failure.NONE and elapsed > limit:
		failure = Failure.TIME_OVER
	var result := {
		"straightness": snappedf(params.straightness_points * rows_on_line / maxi(rows + extra_rows, 1), 0.5),
		"bottom": snappedf(params.bottom_points * (within + 0.5 * within_half) / inside, 0.5),
		"berm": snappedf(params.berm_points * berm_clear / maxi(berm_points, 1), 0.5) if complete else 0.0,
		"speed": snappedf(params.speed_points * clampf((limit - elapsed) / (limit - params.reference_time), 0.0, 1.0),
				0.5) if complete else 0.0,
		"sections": rows + extra_rows,
		"sections_on_line": rows_on_line,
		"within": float(within) / inside,
		"within_half": float(within + within_half) / inside,
		"mean_depth": depth_sum / inside,
		"berm_clear": float(berm_clear) / maxi(berm_points, 1),
		"dug_share": float(dug) / inside,
		"complete": complete,
		"time": elapsed,
		"failure": failure,
	}
	var total: float = result["straightness"] + result["bottom"] + result["berm"] + result["speed"]
	result["total"] = total if failure == Failure.NONE else 0.0
	result["passed"] = failure == Failure.NONE and total >= params.pass_points
	return result
