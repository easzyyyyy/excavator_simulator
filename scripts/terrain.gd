@tool
class_name Terrain
extends Node3D
## Diggable ground: a square heightfield with one surface height per grid point. The
## top of each column may be loose soil (dug, dumped or pushed) resting on ground in
## place (bank soil).
##
## Materials: the ground in place of each column is one of `materials`, and the loose soil
## on it keeps apart how much of each material it holds, however it was mixed. Each
## material brings its densities, angle of repose, resistance and colours.
##
## The machine reads the ground through height_at(). The bucket edits it through
## remove_above() and add_loose() or deposit(). Relaxation lets loose soil slide to its
## angle of repose, the mean of its materials'; ground in place keeps the shape it was cut
## to. Running sums keep the soil volume of each material, counted as bank volume, so
## digging can be checked for conservation. Loose soil does not slide into the space a
## solid body fills above the ground (set_ceilings(): the bucket), and relaxation runs
## after the machine changed the ground in the same physics step, so no frame draws soil
## that has not slid yet.
##
## Rendering: flat chunk meshes aligned with the grid are lifted on the GPU from float
## textures, so editing heights only re-uploads textures, once per frame. Each chunk has
## its own small textures of heights, loose soil and loose shares, one point of apron all
## round for the normals, and only the chunks whose points changed are sent again. The
## material of the ground in place and the heights as built are whole-grid textures, set
## when the ground is built. A flat ring extends the ground beyond the grid. Collision: one HeightMapShape3D per tile, rebuilt
## only for tiles whose heights changed, at most every COLLISION_REFRESH_INTERVAL. The
## machine itself never stands on the collision shapes; they serve raycasts and future
## physics objects.

enum Layout { FLAT, TEST_GROUND, SITE }

## Materials the shader can tell apart.
const MAX_MATERIALS := 4
const DEFAULT_SOIL := preload("res://data/common_earth.tres")

const SHADER := preload("res://shaders/terrain.gdshader")
const VISUAL_GROUP := "Visual"
const COLLISION_GROUP := "Collision"
const HEIGHT_BOUND := 64.0
## Point visits per physics tick for the angle of repose relaxation.
const RELAX_VISITS_PER_TICK := 400
## Physics processing order: after the machine, whose bucket changes the ground.
const PHYSICS_PRIORITY := 10
## Render layer the ground chunks are on besides the default one: paint marks on the
## ground (decals) project on it alone, never on the machine or the truck.
const MARKING_LAYER := 2
## Minimum time between two collision tile rebuilds while the ground keeps changing.
const COLLISION_REFRESH_INTERVAL := 0.5
## Loose thickness under which a point counts as bare ground in place.
const LOOSE_EPSILON := 1e-5
## Height excess over the repose slope that relaxation leaves alone (m).
const RELAX_TOLERANCE := 1e-4
## Eight neighbours: the four sides first, then the diagonals.
const NEIGHBOUR_X: Array[int] = [1, -1, 0, 0, 1, 1, -1, -1]
const NEIGHBOUR_Z: Array[int] = [0, 0, 1, -1, 1, -1, 1, -1]

@export var layout := Layout.TEST_GROUND:
	set(value):
		layout = value
		if is_node_ready():
			rebuild()
## Ground materials. The first one is laid wherever the layout puts no other.
@export var materials: Array[SoilParams] = [DEFAULT_SOIL]
## Distance between grid points (m).
@export var cell_size := 0.25
## Cells along each side. Keep it a multiple of chunk_cells and tile_cells.
@export var cells := 512
@export var chunk_cells := 64
@export var tile_cells := 64
## Width of the flat ground ring drawn around the grid (m).
@export var outer_margin := 150.0

## Things standing on the ground that catch soil poured over them, such as a truck body.
## Each has catch_soil(world_x, world_z, from_height, volumes, scale) -> bool,
## landing_height(world_x, world_z, from_height) -> float (NAN where it does not catch)
## and push_bucket(bucket, from, to, result).
var structures: Array[Node] = []

## The first material. Setting it makes a ground of that one material.
var soil: SoilParams:
	get:
		return materials[0] if not materials.is_empty() else null
	set(value):
		materials = [value]

## Surface heights in metres, row major: index = iz * points + ix.
var heights := PackedFloat32Array()
## Loose soil thickness at each point, part of the surface height: the sum of loose_parts.
var loose := PackedFloat32Array()
## Loose soil thickness of each material at each point, one array per material.
var loose_parts: Array[PackedFloat32Array] = []
## Material of the ground in place at each point, an index into materials.
var bank_material := PackedByteArray()
## Grid points along each side.
var points := 0
## bank_volume() when the ground was last built, for the volume balance.
var volume_reference := 0.0

var _world_origin := Vector2.ZERO
## The ground as the layout built it, to reset it without building it again.
var _built := {}
var _base_heights := PackedFloat32Array()
var _height_sum := 0.0
## Per material: loose thickness summed over all points, and ground in place thickness
## (height less loose) summed over the points of that material.
var _loose_sums := PackedFloat64Array()
var _bank_sums := PackedFloat64Array()
## Per material: tangent of the angle of repose, and loose over bank volume.
var _repose_tangents := PackedFloat64Array()
var _swell_factors := PackedFloat64Array()
## Loose soil share of each material per point, four bytes per point, for the shader.
var _mix_bytes := PackedByteArray()
var _active := PackedInt32Array()
var _active_flags := PackedByteArray()
var _neighbour_index := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
var _neighbour_excess := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0])
## Lowest height of a solid body standing over each point, INF where none, and the points
## that have one.
var _ceilings := PackedFloat32Array()
var _ceiling_points := PackedInt32Array()

## Per chunk, row major: images and textures of heights, loose thickness and loose shares,
## three entries per chunk, and whether the chunk's points changed since the last upload.
var _chunk_images: Array[Image] = []
var _chunk_textures: Array[ImageTexture] = []
var _chunk_flags := PackedByteArray()
var _render_dirty := false
var _tiles: Array[CollisionShape3D] = []
var _tile_flags := PackedByteArray()
var _tiles_dirty := false
var _collision_age := 0.0


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY
	rebuild()


func _process(delta: float) -> void:
	if _render_dirty:
		_upload_textures()
	if _tiles_dirty:
		_collision_age += delta
		if _collision_age >= COLLISION_REFRESH_INTERVAL:
			_update_dirty_tiles()


func _physics_process(_delta: float) -> void:
	if not _active.is_empty():
		relax(RELAX_VISITS_PER_TICK)


## Regenerates heights from the layout and rebuilds rendering and collision.
func rebuild() -> void:
	if not _restore_built():
		setup(cells, cell_size)
		match layout:
			Layout.TEST_GROUND:
				TestGround.build(self)
			Layout.SITE:
				SiteGround.build(self)
		# Built piles already stand at their angle of repose.
		_active = PackedInt32Array()
		_active_flags.fill(0)
		_keep_built()
	_base_heights = heights.duplicate()
	volume_reference = bank_volume()
	_build_visuals()
	_build_collision()
	commit()


## Allocates a flat grid. Usable without adding the node to a tree.
func setup(p_cells: int, p_cell_size: float) -> void:
	cells = p_cells
	cell_size = p_cell_size
	points = cells + 1
	var count := points * points
	heights = PackedFloat32Array()
	heights.resize(count)
	heights.fill(0.0)
	loose = heights.duplicate()
	_base_heights = heights.duplicate()
	var material_count := clampi(materials.size(), 1, MAX_MATERIALS)
	loose_parts.clear()
	for m in material_count:
		loose_parts.append(heights.duplicate())
	bank_material = PackedByteArray()
	bank_material.resize(count)
	bank_material.fill(0)
	_mix_bytes = PackedByteArray()
	_mix_bytes.resize(count * 4)
	_mix_bytes.fill(0)
	_height_sum = 0.0
	_loose_sums = PackedFloat64Array()
	_loose_sums.resize(material_count)
	_loose_sums.fill(0.0)
	_bank_sums = _loose_sums.duplicate()
	_repose_tangents = _loose_sums.duplicate()
	_swell_factors = _loose_sums.duplicate()
	for m in material_count:
		var material := material_params(m)
		_repose_tangents[m] = tan(deg_to_rad(material.repose_angle_deg))
		_swell_factors[m] = 1.0 + material.swell()
	_active = PackedInt32Array()
	_active_flags = PackedByteArray()
	_active_flags.resize(count)
	_active_flags.fill(0)
	_ceilings = PackedFloat32Array()
	_ceilings.resize(count)
	_ceilings.fill(INF)
	_ceiling_points = PackedInt32Array()
	_refresh_origin()
	_tile_flags = PackedByteArray()
	_tile_flags.resize(_tile_count() * _tile_count())
	_tile_flags.fill(1)
	_tiles_dirty = true
	_chunk_flags = PackedByteArray()
	_chunk_flags.resize(_chunk_count() * _chunk_count())
	_chunk_flags.fill(1)
	_render_dirty = true


func size() -> float:
	return cells * cell_size


## Recomputes the running sums from every point, after a builder wrote heights, loose
## soil or materials directly.
func refresh_sums() -> void:
	_height_sum = 0.0
	_bank_sums.fill(0.0)
	for i in heights.size():
		_height_sum += heights[i]
		_bank_sums[bank_material[i]] += heights[i] - loose[i]
	for m in loose_parts.size():
		var sum := 0.0
		for thickness in loose_parts[m]:
			sum += thickness
		_loose_sums[m] = sum
	_render_dirty = true
	_chunk_flags.fill(1)
	_tiles_dirty = true
	_tile_flags.fill(1)


func _keep_built() -> void:
	var parts: Array[PackedFloat32Array] = []
	for part in loose_parts:
		parts.append(part.duplicate())
	_built = {"layout": layout, "cells": cells, "cell_size": cell_size, "materials": materials.duplicate(),
			"heights": heights.duplicate(), "loose": loose.duplicate(), "parts": parts,
			"bank_material": bank_material.duplicate(), "mix": _mix_bytes.duplicate(),
			"height_sum": _height_sum, "loose_sums": _loose_sums.duplicate(), "bank_sums": _bank_sums.duplicate()}


func _restore_built() -> bool:
	if _built.is_empty() or _built["layout"] != layout or _built["cells"] != cells 			or _built["cell_size"] != cell_size or _built["materials"] != materials or layout == Layout.FLAT:
		return false
	setup(cells, cell_size)
	heights = (_built["heights"] as PackedFloat32Array).duplicate()
	loose = (_built["loose"] as PackedFloat32Array).duplicate()
	for m in loose_parts.size():
		loose_parts[m] = (_built["parts"][m] as PackedFloat32Array).duplicate()
	bank_material = (_built["bank_material"] as PackedByteArray).duplicate()
	_mix_bytes = (_built["mix"] as PackedByteArray).duplicate()
	_chunk_flags.fill(1)
	_height_sum = _built["height_sum"]
	_loose_sums = (_built["loose_sums"] as PackedFloat64Array).duplicate()
	_bank_sums = (_built["bank_sums"] as PackedFloat64Array).duplicate()
	return true


## World position of grid point (0, 0) on the ground plane.
func world_origin() -> Vector2:
	return _world_origin


func point_height(ix: int, iz: int) -> float:
	return heights[iz * points + ix]


func point_loose(ix: int, iz: int) -> float:
	return loose[iz * points + ix]


func material_count() -> int:
	return loose_parts.size()


## Material of the ground in place at a grid point.
func point_material(ix: int, iz: int) -> int:
	return bank_material[iz * points + ix]


func material_params(material: int) -> SoilParams:
	if material >= 0 and material < materials.size() and materials[material] != null:
		return materials[material]
	return DEFAULT_SOIL


## Material of the ground in place nearest to a world position.
func material_at(world_x: float, world_z: float) -> int:
	var point := nearest_point(world_x, world_z)
	return bank_material[point.y * points + point.x]


## Material holding the largest share of the loose soil nearest to a world position, or
## the ground in place there when it carries no loose soil.
func loose_material_at(world_x: float, world_z: float) -> int:
	var point := nearest_point(world_x, world_z)
	var i := point.y * points + point.x
	var best := bank_material[i]
	var largest := 0.0
	for m in loose_parts.size():
		if loose_parts[m][i] > largest:
			largest = loose_parts[m][i]
			best = m
	return best


## World x and z of a grid point.
func point_position(ix: int, iz: int) -> Vector2:
	return _world_origin + Vector2(ix, iz) * cell_size


## Nearest grid point to a world position, clamped to the grid.
func nearest_point(world_x: float, world_z: float) -> Vector2i:
	return Vector2i(clampi(roundi((world_x - _world_origin.x) / cell_size), 0, cells),
			clampi(roundi((world_z - _world_origin.y) / cell_size), 0, cells))


## Sets the surface height of ground in place. Meant for building the ground.
func set_point_height(ix: int, iz: int, height: float) -> void:
	var i := iz * points + ix
	var before := heights[i]
	heights[i] = height
	_height_sum += heights[i] - before
	_bank_sums[bank_material[i]] += heights[i] - before
	_mark_dirty(ix, iz)


## Sets the material of the ground in place at a point. Meant for building the ground:
## the drawn materials only follow on the next rebuild.
func set_point_material(ix: int, iz: int, material: int) -> void:
	var i := iz * points + ix
	var thickness := heights[i] - loose[i]
	_bank_sums[bank_material[i]] -= thickness
	bank_material[i] = clampi(material, 0, loose_parts.size() - 1)
	_bank_sums[bank_material[i]] += thickness


## Lays a material under every point of a world rectangle (x, z) where inside.call(x, z)
## is true, or everywhere in it without a callable.
func paint_material(area: Rect2, material: int, inside := Callable()) -> void:
	var from_x := clampi(floori((area.position.x - _world_origin.x) / cell_size), 0, cells)
	var to_x := clampi(ceili((area.end.x - _world_origin.x) / cell_size), 0, cells)
	var from_z := clampi(floori((area.position.y - _world_origin.y) / cell_size), 0, cells)
	var to_z := clampi(ceili((area.end.y - _world_origin.y) / cell_size), 0, cells)
	for iz in range(from_z, to_z + 1):
		var z := _world_origin.y + iz * cell_size
		for ix in range(from_x, to_x + 1):
			var x := _world_origin.x + ix * cell_size
			if not inside.is_valid() or inside.call(x, z):
				set_point_material(ix, iz, material)


## Ground height at a world position, bilinear between grid points and clamped
## to the grid edge outside it.
func height_at(world_x: float, world_z: float) -> float:
	var gx := clampf((world_x - _world_origin.x) / cell_size, 0.0, cells)
	var gz := clampf((world_z - _world_origin.y) / cell_size, 0.0, cells)
	var ix := mini(int(gx), cells - 1)
	var iz := mini(int(gz), cells - 1)
	var fx := gx - ix
	var fz := gz - iz
	var i := iz * points + ix
	var near_row := lerpf(heights[i], heights[i + 1], fx)
	var far_row := lerpf(heights[i + points], heights[i + points + 1], fx)
	return lerpf(near_row, far_row, fz)


## Loose soil thickness at a world position, bilinear like height_at().
func loose_at(world_x: float, world_z: float) -> float:
	var gx := clampf((world_x - _world_origin.x) / cell_size, 0.0, cells)
	var gz := clampf((world_z - _world_origin.y) / cell_size, 0.0, cells)
	var ix := mini(int(gx), cells - 1)
	var iz := mini(int(gz), cells - 1)
	var fx := gx - ix
	var fz := gz - iz
	var i := iz * points + ix
	var near_row := lerpf(loose[i], loose[i + 1], fx)
	var far_row := lerpf(loose[i + points], loose[i + points + 1], fx)
	return lerpf(near_row, far_row, fz)


## Replaces heights inside a world rectangle (x, z) with shape.call(x, z, height).
func apply(area: Rect2, shape: Callable) -> void:
	var from_x := clampi(floori((area.position.x - _world_origin.x) / cell_size), 0, cells)
	var to_x := clampi(ceili((area.end.x - _world_origin.x) / cell_size), 0, cells)
	var from_z := clampi(floori((area.position.y - _world_origin.y) / cell_size), 0, cells)
	var to_z := clampi(ceili((area.end.y - _world_origin.y) / cell_size), 0, cells)
	for iz in range(from_z, to_z + 1):
		var z := _world_origin.y + iz * cell_size
		for ix in range(from_x, to_x + 1):
			var x := _world_origin.x + ix * cell_size
			set_point_height(ix, iz, shape.call(x, z, point_height(ix, iz)))


## Lowers the surface at a point down to floor_height, loose soil first, its materials in
## their shares. Adds the loose volume (m3) each material makes once dug to taken, one
## entry per material, and returns the total.
func remove_above(ix: int, iz: int, floor_height: float, taken: PackedFloat64Array) -> float:
	var i := iz * points + ix
	var height_before := heights[i]
	if height_before <= floor_height:
		return 0.0
	var area := cell_size * cell_size
	var loose_before := loose[i]
	var total := 0.0
	if loose_before > 0.0:
		var kept := maxf(1.0 - (height_before - floor_height) / loose_before, 0.0)
		for m in loose_parts.size():
			var part := loose_parts[m][i]
			if part <= 0.0:
				continue
			loose_parts[m][i] = part * kept
			var removed_part := part - loose_parts[m][i]
			_loose_sums[m] -= removed_part
			taken[m] += removed_part * area
			total += removed_part * area
	var bank_before := height_before - loose_before
	heights[i] = floor_height
	_height_sum += heights[i] - height_before
	_refresh_loose(i)
	var bank_removed := bank_before - (heights[i] - loose[i])
	var material := bank_material[i]
	_bank_sums[material] -= bank_removed
	taken[material] += bank_removed * area * _swell_factors[material]
	total += bank_removed * area * _swell_factors[material]
	_mark_dirty(ix, iz)
	_activate_around(ix, iz)
	return total


## Adds a volume (m3) of loose soil of one material on top of a point.
func add_loose(ix: int, iz: int, volume: float, material := 0) -> void:
	var i := iz * points + ix
	_change_loose(i, clampi(material, 0, loose_parts.size() - 1), volume / (cell_size * cell_size))
	_mark_dirty(ix, iz)
	_activate(i)


## Adds loose soil on top of a point: volumes (m3) per material, times scale.
func add_loose_parts(ix: int, iz: int, volumes: PackedFloat64Array, scale := 1.0) -> void:
	var i := iz * points + ix
	var per_area := scale / (cell_size * cell_size)
	for m in mini(volumes.size(), loose_parts.size()):
		if volumes[m] > 0.0:
			_change_loose(i, m, volumes[m] * per_area)
	_mark_dirty(ix, iz)
	_activate(i)


## Height where soil falling from a height at a world position lands: in a structure that
## catches it there, otherwise on the ground.
func landing_height(world_x: float, world_z: float, from_height := INF) -> float:
	for structure in structures:
		var height: float = structure.landing_height(world_x, world_z, from_height)
		if not is_nan(height):
			return height
	return height_at(world_x, world_z)


## Drops a volume (m3) of loose soil of one material at a world position, shared between
## the four surrounding points.
func deposit(world_x: float, world_z: float, volume: float, material := 0) -> void:
	var volumes := PackedFloat64Array()
	volumes.resize(loose_parts.size())
	volumes[clampi(material, 0, loose_parts.size() - 1)] = volume
	deposit_parts(world_x, world_z, volumes)


## Drops loose soil at a world position, volumes (m3) per material times scale, falling
## from a height: a structure under it catches it, otherwise it lands shared between the
## four surrounding points.
func deposit_parts(world_x: float, world_z: float, volumes: PackedFloat64Array, scale := 1.0,
		from_height := INF) -> void:
	for structure in structures:
		if structure.catch_soil(world_x, world_z, from_height, volumes, scale):
			return
	var gx := clampf((world_x - _world_origin.x) / cell_size, 0.0, cells)
	var gz := clampf((world_z - _world_origin.y) / cell_size, 0.0, cells)
	var ix := mini(int(gx), cells - 1)
	var iz := mini(int(gz), cells - 1)
	var fx := gx - ix
	var fz := gz - iz
	var weights := [(1.0 - fx) * (1.0 - fz), fx * (1.0 - fz), (1.0 - fx) * fz, fx * fz]
	for k in 4:
		if weights[k] > 1e-9:
			add_loose_parts(ix + k % 2, iz + k / 2, volumes, scale * weights[k])


## Soil volume above the zero plane counted as ground in place (m3): loose soil counts
## for the bank volume it came from. Unchanged while soil only moves between the ground
## and a bucket, once the bucket load is counted the same way.
func bank_volume() -> float:
	var total := 0.0
	for m in loose_parts.size():
		total += bank_volume_of(m)
	return total


## bank_volume() for one material.
func bank_volume_of(material: int) -> float:
	return (_bank_sums[material] + _loose_sums[material] / _swell_factors[material]) * cell_size * cell_size


## bank_volume() recomputed from every point, to check the running sums.
func bank_volume_recount() -> float:
	var total := 0.0
	for m in loose_parts.size():
		total += bank_volume_of_recount(m)
	return total


func bank_volume_of_recount(material: int) -> float:
	var bank_sum := 0.0
	var loose_sum := 0.0
	var parts := loose_parts[material]
	for i in heights.size():
		if bank_material[i] == material:
			bank_sum += heights[i] - loose[i]
		loose_sum += parts[i]
	return (bank_sum + loose_sum / _swell_factors[material]) * cell_size * cell_size


## Loose volume per bank volume of a material, once dug.
func swell_factor(material: int) -> float:
	return _swell_factors[material]


## Points waiting for relaxation.
func pending_relaxation() -> int:
	return _active.size()


## Marks the space a solid body fills over some points, grid indices, down to its lowest
## height over each, in place of the previous marks: loose soil does not slide into it.
## Soil held back by a mark that went away or rose slides again.
func set_ceilings(indices: PackedInt32Array, lowest: PackedFloat32Array) -> void:
	var previous := _ceiling_points
	var before := PackedFloat32Array()
	before.resize(previous.size())
	for k in previous.size():
		before[k] = _ceilings[previous[k]]
		_ceilings[previous[k]] = INF
	for k in indices.size():
		_ceilings[indices[k]] = lowest[k]
	_ceiling_points = indices
	for k in previous.size():
		var i := previous[k]
		if _ceilings[i] > before[k] and heights[i] >= before[k] - RELAX_TOLERANCE:
			_activate_around(i % points, i / points)


## Lowest height of a solid body over a point, INF where none.
func ceiling(ix: int, iz: int) -> float:
	return _ceilings[iz * points + ix]


## Lets loose soil slide toward lower neighbours until no slope from a point carrying
## loose soil is steeper than the angle of repose. Only points whose surroundings
## changed are visited, at most max_visits per call. Returns the points still waiting.
func relax(max_visits: int) -> int:
	if _active.is_empty():
		return 0
	var visits := 0
	while not _active.is_empty() and visits < max_visits:
		var batch := _active
		_active = PackedInt32Array()
		var count := mini(batch.size(), max_visits - visits)
		for k in count:
			var i := batch[k]
			_active_flags[i] = 0
			_relax_point(i)
		visits += count
		if count < batch.size():
			# Unvisited points keep their flag and go back to the front of the queue.
			var rest := batch.slice(count)
			rest.append_array(_active)
			_active = rest
	return _active.size()


## Pushes height changes to rendering and to the collision tiles that changed.
func commit() -> void:
	_upload_textures()
	_update_dirty_tiles()


func _relax_point(i: int) -> void:
	var available := loose[i]
	if available <= LOOSE_EPSILON:
		return
	var slope := _repose_tangents[0]
	if loose_parts.size() > 1:
		slope = 0.0
		for m in loose_parts.size():
			slope += loose_parts[m][i] / available * _repose_tangents[m]
	var straight := slope * cell_size
	var diagonal := straight * sqrt(2.0)
	var ix := i % points
	var iz := i / points
	var height := heights[i]
	var count := 0
	var total := 0.0
	var steepest := 0.0
	for k in 8:
		var jx := ix + NEIGHBOUR_X[k]
		var jz := iz + NEIGHBOUR_Z[k]
		if jx < 0 or jz < 0 or jx >= points or jz >= points:
			continue
		var j := jz * points + jx
		# A neighbour takes at most half its excess: up to the body standing over it.
		var excess := minf(height - heights[j] - (straight if k < 4 else diagonal), 2.0 * (_ceilings[j] - heights[j]))
		if excess > 0.0:
			_neighbour_index[count] = j
			_neighbour_excess[count] = excess
			count += 1
			total += excess
			steepest = maxf(steepest, excess)
	if steepest < RELAX_TOLERANCE:
		return
	# Half the steepest excess levels the pair; the others take their share of it. Each
	# material moves in its share of the loose soil.
	var share := minf(available, steepest * 0.5) / available
	for material in loose_parts.size():
		var part := loose_parts[material][i]
		if part <= 0.0:
			continue
		var moved := -_change_loose(i, material, -part * share)
		for k in count:
			_change_loose(_neighbour_index[k], material, moved * _neighbour_excess[k] / total)
	_mark_dirty(ix, iz)
	_activate(i)
	for k in count:
		var j := _neighbour_index[k]
		_mark_dirty(j % points, j / points)
		_activate(j)
	# The point went down: loose soil standing higher around it may slide onto it now.
	height = heights[i]
	for k in 8:
		var jx := ix + NEIGHBOUR_X[k]
		var jz := iz + NEIGHBOUR_Z[k]
		if jx >= 0 and jz >= 0 and jx < points and jz < points:
			var j := jz * points + jx
			if loose[j] > LOOSE_EPSILON and heights[j] > height:
				_activate(j)


## Adds loose thickness of one material at a point (negative removes it, never below
## none) and raises the surface with it. Keeps the running sums on the values actually
## stored, and returns the thickness actually added.
func _change_loose(i: int, material: int, thickness: float) -> float:
	var parts := loose_parts[material]
	var part_before := parts[i]
	parts[i] = maxf(part_before + thickness, 0.0)
	var added := parts[i] - part_before
	_loose_sums[material] += added
	var height_before := heights[i]
	var bank_before := height_before - loose[i]
	heights[i] = height_before + added
	_height_sum += heights[i] - height_before
	_refresh_loose(i)
	# Rounding in the stored values must not change the ground in place unseen.
	_bank_sums[bank_material[i]] += (heights[i] - loose[i]) - bank_before
	return added


## Recomputes the loose total and the shader shares of a point from its parts.
func _refresh_loose(i: int) -> void:
	var total := 0.0
	for m in loose_parts.size():
		total += loose_parts[m][i]
	loose[i] = total
	var byte := i * 4
	for m in loose_parts.size():
		_mix_bytes[byte + m] = roundi(255.0 * loose_parts[m][i] / total) if total > 0.0 else 0


func _activate(i: int) -> void:
	if _active_flags[i] == 0:
		_active_flags[i] = 1
		_active.append(i)


func _activate_around(ix: int, iz: int) -> void:
	for jz in range(maxi(iz - 1, 0), mini(iz + 1, cells) + 1):
		for jx in range(maxi(ix - 1, 0), mini(ix + 1, cells) + 1):
			_activate(jz * points + jx)


func _refresh_origin() -> void:
	var offset := global_position if is_inside_tree() else position
	_world_origin = Vector2(offset.x, offset.z) - Vector2.ONE * size() * 0.5


func _tile_count() -> int:
	return ceili(float(cells) / tile_cells)


func _chunk_count() -> int:
	return ceili(float(cells) / chunk_cells)


func _mark_dirty(ix: int, iz: int) -> void:
	_render_dirty = true
	# Every chunk whose texels, apron included, hold this point.
	var chunks := _chunk_count()
	var cx_from := maxi(ceili(float(ix - chunk_cells - 1) / chunk_cells), 0)
	var cx_to := mini(floori(float(ix + 1) / chunk_cells), chunks - 1)
	var cz_from := maxi(ceili(float(iz - chunk_cells - 1) / chunk_cells), 0)
	var cz_to := mini(floori(float(iz + 1) / chunk_cells), chunks - 1)
	for cz in range(cz_from, cz_to + 1):
		for cx in range(cx_from, cx_to + 1):
			_chunk_flags[cz * chunks + cx] = 1
	_tiles_dirty = true
	var count := _tile_count()
	var tx := mini(ix / tile_cells, count - 1)
	var tz := mini(iz / tile_cells, count - 1)
	_tile_flags[tz * count + tx] = 1
	# Points on a tile border are shared with the previous tile.
	var shared_x := ix % tile_cells == 0 and ix > 0
	var shared_z := iz % tile_cells == 0 and iz > 0
	if shared_x:
		_tile_flags[tz * count + (ix / tile_cells - 1)] = 1
	if shared_z:
		_tile_flags[(iz / tile_cells - 1) * count + tx] = 1
	if shared_x and shared_z:
		_tile_flags[(iz / tile_cells - 1) * count + (ix / tile_cells - 1)] = 1


func _group(group_name: String) -> Node3D:
	var old := get_node_or_null(group_name)
	if old:
		remove_child(old)
		old.free()
	var group := Node3D.new()
	group.name = group_name
	add_child(group)
	return group


func _upload_textures() -> void:
	_render_dirty = false
	if _chunk_textures.is_empty():
		return
	var chunks := _chunk_count()
	for k in _chunk_flags.size():
		if _chunk_flags[k] != 0:
			_upload_chunk(k % chunks, k / chunks)
	_chunk_flags.fill(0)


## Copies a chunk's heights, loose thickness and loose shares into its textures: its
## points and one point of apron all round, the grid edge repeated outside the grid.
func _upload_chunk(cx: int, cz: int) -> void:
	var size := chunk_cells + 3
	var height_rows := PackedFloat32Array()
	var loose_rows := PackedFloat32Array()
	var mix_rows := PackedByteArray()
	var first := cx * chunk_cells - 1
	var from := maxi(first, 0)
	var to := mini(first + size - 1, cells)
	for row in size:
		var start := clampi(cz * chunk_cells - 1 + row, 0, cells) * points
		if first < 0:
			height_rows.append(heights[start])
			loose_rows.append(loose[start])
			mix_rows.append_array(_mix_bytes.slice(start * 4, start * 4 + 4))
		height_rows.append_array(heights.slice(start + from, start + to + 1))
		loose_rows.append_array(loose.slice(start + from, start + to + 1))
		mix_rows.append_array(_mix_bytes.slice((start + from) * 4, (start + to + 1) * 4))
		if first + size - 1 > cells:
			var last := start + cells
			height_rows.append(heights[last])
			loose_rows.append(loose[last])
			mix_rows.append_array(_mix_bytes.slice(last * 4, last * 4 + 4))
	var k := (cz * _chunk_count() + cx) * 3
	_chunk_images[k].set_data(size, size, false, Image.FORMAT_RF, height_rows.to_byte_array())
	_chunk_textures[k].update(_chunk_images[k])
	_chunk_images[k + 1].set_data(size, size, false, Image.FORMAT_RF, loose_rows.to_byte_array())
	_chunk_textures[k + 1].update(_chunk_images[k + 1])
	_chunk_images[k + 2].set_data(size, size, false, Image.FORMAT_RGBA8, mix_rows)
	_chunk_textures[k + 2].update(_chunk_images[k + 2])


func _build_visuals() -> void:
	var group := _group(VISUAL_GROUP)
	var base_image := Image.create_from_data(points, points, false, Image.FORMAT_RF, _base_heights.to_byte_array())
	var material_image := Image.create_from_data(points, points, false, Image.FORMAT_R8, bank_material)
	var base_material := ShaderMaterial.new()
	base_material.shader = SHADER
	base_material.set_shader_parameter("material_map", ImageTexture.create_from_image(material_image))
	base_material.set_shader_parameter("base_map", ImageTexture.create_from_image(base_image))
	var ground_colors := PackedColorArray()
	var dug_colors := PackedColorArray()
	var loose_colors := PackedColorArray()
	var grain := PackedFloat32Array()
	for m in MAX_MATERIALS:
		var params := material_params(mini(m, loose_parts.size() - 1))
		ground_colors.append(params.ground_color)
		dug_colors.append(params.dug_color)
		loose_colors.append(params.loose_color)
		grain.append(params.grain_scale)
	base_material.set_shader_parameter("ground_colors", ground_colors)
	base_material.set_shader_parameter("dug_colors", dug_colors)
	base_material.set_shader_parameter("loose_colors", loose_colors)
	base_material.set_shader_parameter("grain_scales", grain)
	base_material.set_shader_parameter("grid_origin", _world_origin)
	base_material.set_shader_parameter("cell_size", cell_size)
	base_material.set_shader_parameter("grid_points", points)

	var chunk_size := chunk_cells * cell_size
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * chunk_size
	mesh.subdivide_width = chunk_cells - 1
	mesh.subdivide_depth = chunk_cells - 1
	var local_origin := -Vector2.ONE * size() * 0.5
	var chunks := _chunk_count()
	var texels := chunk_cells + 3
	_chunk_images.clear()
	_chunk_textures.clear()
	for cz in chunks:
		for cx in chunks:
			var chunk_material := base_material.duplicate() as ShaderMaterial
			chunk_material.set_shader_parameter("chunk_origin", Vector2i(cx * chunk_cells - 1, cz * chunk_cells - 1))
			for format in [Image.FORMAT_RF, Image.FORMAT_RF, Image.FORMAT_RGBA8]:
				var image := Image.create_empty(texels, texels, false, format)
				_chunk_images.append(image)
				_chunk_textures.append(ImageTexture.create_from_image(image))
			var k := _chunk_textures.size() - 3
			chunk_material.set_shader_parameter("heightmap", _chunk_textures[k])
			chunk_material.set_shader_parameter("loose_map", _chunk_textures[k + 1])
			chunk_material.set_shader_parameter("mix_map", _chunk_textures[k + 2])
			var chunk := MeshInstance3D.new()
			chunk.name = "Chunk%d_%d" % [cx, cz]
			chunk.mesh = mesh
			chunk.material_override = chunk_material
			chunk.layers = 1 | MARKING_LAYER
			chunk.position = Vector3(local_origin.x + (cx + 0.5) * chunk_size, 0.0,
					local_origin.y + (cz + 0.5) * chunk_size)
			chunk.custom_aabb = AABB(Vector3(-chunk_size * 0.5, -HEIGHT_BOUND, -chunk_size * 0.5),
					Vector3(chunk_size, HEIGHT_BOUND * 2.0, chunk_size))
			group.add_child(chunk)

	# Flat ring around the grid: north and south strips span the full width.
	var half := size() * 0.5
	var outer := half + outer_margin
	var strips: Array[Rect2] = [
		Rect2(-outer, -outer, outer * 2.0, outer_margin),
		Rect2(-outer, half, outer * 2.0, outer_margin),
		Rect2(-outer, -half, outer_margin, size()),
		Rect2(half, -half, outer_margin, size()),
	]
	var ring_material := base_material.duplicate() as ShaderMaterial
	ring_material.set_shader_parameter("outside_grid", true)
	for strip in strips:
		var plane := PlaneMesh.new()
		plane.size = strip.size
		var ring := MeshInstance3D.new()
		ring.name = "OuterGround"
		ring.mesh = plane
		ring.material_override = ring_material
		ring.position = Vector3(strip.get_center().x, 0.0, strip.get_center().y)
		group.add_child(ring)


func _build_collision() -> void:
	var group := _group(COLLISION_GROUP)
	var body := StaticBody3D.new()
	body.name = "Body"
	group.add_child(body)
	_tiles.clear()
	var count := _tile_count()
	var tile_size := tile_cells * cell_size
	var local_origin := -Vector2.ONE * size() * 0.5
	for tz in count:
		for tx in count:
			var shape := HeightMapShape3D.new()
			shape.map_width = tile_cells + 1
			shape.map_depth = tile_cells + 1
			var node := CollisionShape3D.new()
			node.name = "Tile%d_%d" % [tx, tz]
			node.shape = shape
			# Uniform scale: the shape spaces its points 1 apart, heights are divided to match.
			node.transform = Transform3D(Basis.from_scale(Vector3.ONE * cell_size), Vector3(
					local_origin.x + (tx + 0.5) * tile_size, 0.0, local_origin.y + (tz + 0.5) * tile_size))
			body.add_child(node)
			_tiles.append(node)
	_tile_flags.fill(1)
	_tiles_dirty = true


func _update_dirty_tiles() -> void:
	_collision_age = 0.0
	if _tiles.is_empty() or not _tiles_dirty:
		return
	for tile in _tile_flags.size():
		if _tile_flags[tile] != 0:
			_update_tile(tile)
	_tile_flags.fill(0)
	_tiles_dirty = false


func _update_tile(tile: int) -> void:
	var count := _tile_count()
	var tx := tile % count
	var tz := tile / count
	var width := tile_cells + 1
	var data := PackedFloat32Array()
	data.resize(width * width)
	var inverse_scale := 1.0 / cell_size
	for j in width:
		var iz := mini(tz * tile_cells + j, cells)
		for i in width:
			var ix := mini(tx * tile_cells + i, cells)
			data[j * width + i] = heights[iz * points + ix] * inverse_scale
	var shape := _tiles[tile].shape as HeightMapShape3D
	shape.map_data = data
