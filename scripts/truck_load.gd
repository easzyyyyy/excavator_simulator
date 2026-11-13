@tool
class_name TruckLoad
extends RefCounted
## Loose soil in a truck body: a small grid over the body floor holding the loose thickness
## of each material, in truck space (TruckParams). Soil poured in lands on the grid and
## slides at its angle of repose between the walls. What stands above a wall top more
## steeply than its angle of repose goes over it, handed to an overflow callable to land on
## the ground outside.
##
## Volumes are loose volumes (m3), in the shares of the materials poured.

## Largest cell edge of the grid (m).
const MAX_CELL := 0.2
const RELAX_TOLERANCE := 1e-4
const LOOSE_EPSILON := 1e-5
## Distance outside a wall where soil going over it lands (m).
const OVERFLOW_OUT := 0.25
const NEIGHBOUR_X: Array[int] = [1, -1, 0, 0, 1, 1, -1, -1]
const NEIGHBOUR_Z: Array[int] = [0, 0, 1, -1, 1, -1, 1, -1]

var params: TruckParams
var materials: Array[SoilParams] = []
## Cells across the body (x) and along it (z), and their size (m).
var across := 1
var along := 1
var cell_x := MAX_CELL
var cell_z := MAX_CELL
## Loose thickness per material per cell, row major along z: index = iz * across + ix.
var parts: Array[PackedFloat32Array] = []
var thickness := PackedFloat32Array()
## Loose volume per material (m3) that went over the walls, and that was emptied, since
## the last clear.
var spilled := PackedFloat64Array()
var hauled := PackedFloat64Array()
## Set whenever the soil in the body changes, for redrawing.
var changed := true

var _active := PackedInt32Array()
var _active_flags := PackedByteArray()
var _repose_tangents := PackedFloat64Array()
var _neighbour_index := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
var _neighbour_excess := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0])
var _scratch := PackedFloat64Array()


func setup(p_params: TruckParams, p_materials: Array[SoilParams]) -> void:
	params = p_params
	materials = p_materials
	across = ceili(params.body_inner_width / MAX_CELL)
	along = ceili(params.body_inner_length / MAX_CELL)
	cell_x = params.body_inner_width / across
	cell_z = params.body_inner_length / along
	thickness = PackedFloat32Array()
	thickness.resize(across * along)
	thickness.fill(0.0)
	parts.clear()
	_repose_tangents.clear()
	for material in materials:
		parts.append(thickness.duplicate())
		_repose_tangents.append(tan(deg_to_rad(material.repose_angle_deg)))
	spilled = PackedFloat64Array()
	spilled.resize(materials.size())
	spilled.fill(0.0)
	hauled = spilled.duplicate()
	_scratch = spilled.duplicate()
	_active = PackedInt32Array()
	_active_flags = PackedByteArray()
	_active_flags.resize(across * along)
	_active_flags.fill(0)
	changed = true


## Height of the soil surface in a cell above the ground, in truck space.
func surface_height(ix: int, iz: int) -> float:
	return params.body_floor_height + thickness[iz * across + ix]


## Truck space centre of a cell on the floor.
func cell_centre(ix: int, iz: int) -> Vector3:
	return Vector3(-params.body_inner_width * 0.5 + (ix + 0.5) * cell_x, params.body_floor_height,
			params.body_inside_front() + (iz + 0.5) * cell_z)


## Takes soil poured at a truck space point above the body floor when it falls inside the
## body, onto the soil already there: volumes (m3) per material, times scale. Returns whether
## the body caught it.
func catch_soil(local: Vector3, volumes: PackedFloat64Array, scale: float) -> bool:
	var u := (local.x + params.body_inner_width * 0.5) / cell_x
	var v := (local.z - params.body_inside_front()) / cell_z
	if u < 0.0 or v < 0.0 or u >= across or v >= along or local.y < params.body_floor_height:
		return false
	var ix := int(u)
	var iz := int(v)
	var i := iz * across + ix
	var cell_area := cell_x * cell_z
	for m in mini(volumes.size(), parts.size()):
		if volumes[m] > 0.0:
			_change(i, m, volumes[m] * scale / cell_area)
	_activate(i)
	return true


## Height of the soil surface under a truck space point above the body floor inside the
## body, NAN where the body would not catch soil poured there.
func landing_height(local: Vector3) -> float:
	var u := (local.x + params.body_inner_width * 0.5) / cell_x
	var v := (local.z - params.body_inside_front()) / cell_z
	if u < 0.0 or v < 0.0 or u >= across or v >= along or local.y < params.body_floor_height:
		return NAN
	return surface_height(int(u), int(v))


## Lets soil slide toward lower cells and over the walls until no slope is steeper than
## the angle of repose, visiting at most max_visits cells. Soil going over a wall is given
## to overflow.call(truck_space_point, volumes). Returns the cells still waiting.
func relax(max_visits: int, overflow: Callable) -> int:
	var visits := 0
	while not _active.is_empty() and visits < max_visits:
		var batch := _active
		_active = PackedInt32Array()
		var count := mini(batch.size(), max_visits - visits)
		for k in count:
			_active_flags[batch[k]] = 0
			_relax_cell(batch[k], overflow)
		visits += count
		if count < batch.size():
			var rest := batch.slice(count)
			rest.append_array(_active)
			_active = rest
	return _active.size()


func pending_relaxation() -> int:
	return _active.size()


## Loose volume of each material in the body (m3).
func volumes() -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for part in parts:
		var sum := 0.0
		for value in part:
			sum += value
		result.append(sum * cell_x * cell_z)
	return result


func loose_volume() -> float:
	var total := 0.0
	for volume in volumes():
		total += volume
	return total


## The load counted as ground in place (m3).
func bank_volume() -> float:
	var result := volumes()
	var total := 0.0
	for m in result.size():
		total += result[m] / (1.0 + materials[m].swell())
	return total


func mass() -> float:
	var result := volumes()
	var total := 0.0
	for m in result.size():
		total += result[m] * materials[m].loose_density
	return total


## Material with the largest volume in the body.
func load_material() -> int:
	var result := volumes()
	var best := 0
	for m in result.size():
		if result[m] > result[best]:
			best = m
	return best


## Empties the body at once: the load leaves the site.
func empty() -> void:
	var result := volumes()
	for m in result.size():
		hauled[m] += result[m]
		parts[m].fill(0.0)
	thickness.fill(0.0)
	_active = PackedInt32Array()
	_active_flags.fill(0)
	changed = true


## Empties the body and forgets what was spilled and hauled.
func clear() -> void:
	empty()
	spilled.fill(0.0)
	hauled.fill(0.0)


func _relax_cell(i: int, overflow: Callable) -> void:
	var available := thickness[i]
	if available <= LOOSE_EPSILON:
		return
	var slope := 0.0
	for m in parts.size():
		slope += parts[m][i] / available * _repose_tangents[m]
	var ix := i % across
	var iz := i / across
	var height := params.body_floor_height + available
	var count := 0
	var total := 0.0
	var steepest := 0.0
	var wall_total := 0.0
	# Walls first: the virtual neighbour of an edge cell is the wall top, half a cell and a
	# wall thickness away.
	var walls: Array[Vector3] = []
	if ix == 0:
		walls.append(Vector3(-1.0, 0.0, cell_x * 0.5))
	if ix == across - 1:
		walls.append(Vector3(1.0, 0.0, cell_x * 0.5))
	if iz == 0:
		walls.append(Vector3(0.0, -1.0, cell_z * 0.5))
	if iz == along - 1:
		walls.append(Vector3(0.0, 1.0, cell_z * 0.5))
	var wall_excess := PackedFloat64Array()
	for wall in walls:
		var top := params.loading_height()
		if wall.y < 0.0:
			top += params.headboard_extra_height
		var excess := height - top - slope * (wall.z + params.body_wall_thickness)
		wall_excess.append(excess)
		if excess > 0.0:
			wall_total += excess
			steepest = maxf(steepest, excess)
	for k in 8:
		var jx := ix + NEIGHBOUR_X[k]
		var jz := iz + NEIGHBOUR_Z[k]
		if jx < 0 or jz < 0 or jx >= across or jz >= along:
			continue
		var j := jz * across + jx
		var run := Vector2(NEIGHBOUR_X[k] * cell_x, NEIGHBOUR_Z[k] * cell_z).length()
		var excess := available - thickness[j] - slope * run
		if excess > 0.0:
			_neighbour_index[count] = j
			_neighbour_excess[count] = excess
			count += 1
			total += excess
			steepest = maxf(steepest, excess)
	if steepest < RELAX_TOLERANCE:
		return
	var share := minf(available, steepest * 0.5) / available
	var cell_area := cell_x * cell_z
	var all := total + wall_total
	for m in parts.size():
		var part := parts[m][i]
		if part <= 0.0:
			continue
		var moved := -_change(i, m, -part * share)
		for k in count:
			_change(_neighbour_index[k], m, moved * _neighbour_excess[k] / all)
		for w in walls.size():
			if wall_excess[w] <= 0.0:
				continue
			var out := moved * wall_excess[w] / all * cell_area
			spilled[m] += out
			_scratch.fill(0.0)
			_scratch[m] = out
			var point := cell_centre(ix, iz)
			var wall := walls[w]
			point.x += wall.x * (cell_x * 0.5 + params.body_wall_thickness + OVERFLOW_OUT)
			point.z += wall.y * (cell_z * 0.5 + params.body_wall_thickness + OVERFLOW_OUT)
			point.y = params.loading_height()
			overflow.call(point, _scratch)
	_activate(i)
	for k in count:
		_activate(_neighbour_index[k])


## Adds loose thickness of one material to a cell (negative removes it, never below none).
## Returns the thickness actually added.
func _change(i: int, material: int, amount: float) -> float:
	var before := parts[material][i]
	parts[material][i] = maxf(before + amount, 0.0)
	var added := parts[material][i] - before
	var sum := 0.0
	for part in parts:
		sum += part[i]
	thickness[i] = sum
	changed = true
	return added


func _activate(i: int) -> void:
	if _active_flags[i] == 0:
		_active_flags[i] = 1
		_active.append(i)
