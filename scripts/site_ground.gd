@tool
class_name SiteGround
extends RefCounted
## Free work site, about 200 m square, around the start position: the machine at the
## origin facing -Z, which is north, east is +X. Nothing on it asks for anything; it only
## offers places to work.
##
## - Start platform around the origin, flat, where the truck waits on the right.
## - Started trench straight ahead in a patch of clay, its spoil in a windrow on its left.
## - Embankment to the west: a bench with 3:2 faces, reached by a 20 % ramp from the south.
## - Fill stockpile to the north-east: loose sand already heaped at its angle of repose.
## - Ground to level to the south-west: loose earth dumped in truckload piles.
## Between them the natural ground rolls gently, and it flattens out toward the grid edge.
##
## Materials are indices into Terrain.materials: earth, clay, sand.

const EARTH := 0
const CLAY := 1
const SAND := 2

const PLATFORM := Rect2(-16.0, -6.0, 40.0, 32.0)

const CLAY_PATCH := Rect2(-14.0, -44.0, 28.0, 40.0)
## Trench axis: the arm plane of the machine at the start, facing north.
const TRENCH_X := 0.3
const TRENCH_Z := Vector2(-6.0, -26.0)
const TRENCH_WIDTH := 1.5
const TRENCH_DEPTH := 1.5
## Distance from the trench axis to the spoil windrow ridge, on the west side.
const SPOIL_OFFSET := 3.6

const BENCH_TOP := Rect2(-80.0, -64.0, 30.0, 84.0)
const BENCH_HEIGHT := 4.0
## Horizontal run per metre of height of the bench faces.
const BENCH_FACE_RUN := 1.5
const RAMP_X := Vector2(-74.0, -64.0)
const RAMP_SLOPE := 0.2

## Stockpile cones (x, z, base radius) and a ridge pile (from, to, half base width).
const STOCKPILE_CONES: Array[Vector3] = [Vector3(38.0, -32.0, 6.5), Vector3(52.0, -24.0, 5.0)]
const STOCKPILE_RIDGE_FROM := Vector2(34.0, -48.0)
const STOCKPILE_RIDGE_TO := Vector2(60.0, -44.0)
const STOCKPILE_RIDGE_HALF_WIDTH := 5.0

const LEVEL_AREA := Rect2(-46.0, 32.0, 34.0, 26.0)
## Loose volume of one truckload pile (m3) and the rows of piles.
const TRUCKLOAD := 9.0
const LEVEL_PILES := Vector2i(4, 3)

## Rolling of the natural ground: height amplitude (m), wavelength (m), and the distance
## over which it calms down toward the work areas and the grid edge.
const ROLL_AMPLITUDE := 0.5
const ROLL_WAVELENGTH := 45.0
const CALM_DISTANCE := 14.0
const EDGE_DISTANCE := 16.0
const NOISE_SEED := 20260911
## Spacing of the natural ground heights the grid is read from (m).
const NATURAL_SPACING := 2.0
## Piles are laid this much flatter than the angle of repose, so that they stand as built.
const PILE_SLOPE_MARGIN_DEG := 0.5


static func build(terrain: Terrain) -> void:
	var natural := _natural_grid(terrain)
	var count := int(sqrt(natural.size()))
	var points := terrain.points
	var origin := terrain.world_origin()
	var step := NATURAL_SPACING / terrain.cell_size
	var bench := _bench_bounds()
	var heights := terrain.heights
	for iz in points:
		var z := origin.y + iz * terrain.cell_size
		var gz := minf(iz / step, count - 1.001)
		var j := int(gz)
		var fz := gz - j
		var row := j * count
		for ix in points:
			var gx := minf(ix / step, count - 1.001)
			var i := int(gx)
			var fx := gx - i
			var near := natural[row + i] + (natural[row + i + 1] - natural[row + i]) * fx
			var far := natural[row + count + i] + (natural[row + count + i + 1] - natural[row + count + i]) * fx
			var height := near + (far - near) * fz
			var x := origin.x + ix * terrain.cell_size
			if x >= bench.position.x and x <= bench.end.x and z >= bench.position.y and z <= bench.end.y:
				height = maxf(height, bench_height(x, z))
			heights[iz * points + ix] = height
	_paint(terrain, CLAY_PATCH, CLAY)
	_cut_trench(terrain)
	terrain.refresh_sums()
	_lay_spoil(terrain)
	_lay_stockpile(terrain)
	_lay_truckloads(terrain)


## Bench profile: flat top, 3:2 faces all round, and the ramp climbing north onto its
## south end, with 3:2 sides.
static func bench_height(x: float, z: float) -> float:
	var outside := _distance_to_rect(BENCH_TOP, x, z)
	var height := BENCH_HEIGHT - outside / BENCH_FACE_RUN
	if z > BENCH_TOP.end.y:
		var side := maxf(maxf(RAMP_X.x - x, x - RAMP_X.y), 0.0)
		height = maxf(height, BENCH_HEIGHT - (z - BENCH_TOP.end.y) * RAMP_SLOPE - side / BENCH_FACE_RUN)
	return maxf(height, 0.0)


static func trench_contains(x: float, z: float) -> bool:
	return absf(x - TRENCH_X) <= TRENCH_WIDTH * 0.5 and z <= TRENCH_Z.x and z >= TRENCH_Z.y


## Bank volume dug out of the trench (m3), as the grid holds it.
static func trench_bank_volume(terrain: Terrain) -> float:
	var count := 0
	var from := terrain.nearest_point(TRENCH_X - TRENCH_WIDTH, TRENCH_Z.y - 1.0)
	var to := terrain.nearest_point(TRENCH_X + TRENCH_WIDTH, TRENCH_Z.x + 1.0)
	for iz in range(from.y, to.y + 1):
		for ix in range(from.x, to.x + 1):
			var at := terrain.point_position(ix, iz)
			if trench_contains(at.x, at.y):
				count += 1
	return count * TRENCH_DEPTH * terrain.cell_size * terrain.cell_size


## Loose volume of one material lying on the ground (m3).
static func loose_volume(terrain: Terrain, material: int) -> float:
	var total := 0.0
	for thickness in terrain.loose_parts[material]:
		total += thickness
	return total * terrain.cell_size * terrain.cell_size


static func _bench_bounds() -> Rect2:
	var run := BENCH_HEIGHT * BENCH_FACE_RUN
	var bounds := BENCH_TOP.grow(run)
	return bounds.expand(Vector2(RAMP_X.y + run, BENCH_TOP.end.y + BENCH_HEIGHT / RAMP_SLOPE))


static func _stockpile_bounds() -> Rect2:
	var bounds := Rect2(STOCKPILE_RIDGE_FROM, Vector2.ZERO).expand(STOCKPILE_RIDGE_TO).grow(STOCKPILE_RIDGE_HALF_WIDTH)
	for cone in STOCKPILE_CONES:
		bounds = bounds.merge(Rect2(cone.x - cone.z, cone.y - cone.z, cone.z * 2.0, cone.z * 2.0))
	return bounds


static func _distance_to_rect(area: Rect2, x: float, z: float) -> float:
	var dx := maxf(maxf(area.position.x - x, x - area.end.x), 0.0)
	var dz := maxf(maxf(area.position.y - z, z - area.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)


## Natural ground heights every NATURAL_SPACING over the grid, row major: the rolling
## noise, calmed down near the work areas and the grid edge. Read back bilinearly.
static func _natural_grid(terrain: Terrain) -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.seed = NOISE_SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / ROLL_WAVELENGTH
	noise.fractal_octaves = 3
	var calm_areas: Array[Rect2] = [PLATFORM, CLAY_PATCH, LEVEL_AREA, _stockpile_bounds(), _bench_bounds()]
	var half := terrain.size() * 0.5
	var count := ceili(terrain.size() / NATURAL_SPACING) + 1
	var grid := PackedFloat32Array()
	grid.resize(count * count)
	for j in count:
		var z := terrain.world_origin().y + j * NATURAL_SPACING
		for i in count:
			var x := terrain.world_origin().x + i * NATURAL_SPACING
			var calm := CALM_DISTANCE
			for area in calm_areas:
				calm = minf(calm, _distance_to_rect(area, x, z))
			var edge := minf(half - absf(x), half - absf(z))
			grid[j * count + i] = noise.get_noise_2d(x, z) * ROLL_AMPLITUDE * smoothstep(0.0, CALM_DISTANCE, calm) \
					* smoothstep(0.0, EDGE_DISTANCE, edge)
	return grid


static func _cut_trench(terrain: Terrain) -> void:
	var from := terrain.nearest_point(TRENCH_X - TRENCH_WIDTH, TRENCH_Z.y - 1.0)
	var to := terrain.nearest_point(TRENCH_X + TRENCH_WIDTH, TRENCH_Z.x + 1.0)
	for iz in range(from.y, to.y + 1):
		for ix in range(from.x, to.x + 1):
			var at := terrain.point_position(ix, iz)
			if trench_contains(at.x, at.y):
				terrain.heights[iz * terrain.points + ix] = -TRENCH_DEPTH


static func _paint(terrain: Terrain, area: Rect2, material: int) -> void:
	var from := terrain.nearest_point(area.position.x, area.position.y)
	var to := terrain.nearest_point(area.end.x, area.end.y)
	for iz in range(from.y, to.y + 1):
		for ix in range(from.x, to.x + 1):
			terrain.bank_material[iz * terrain.points + ix] = material


## Trench spoil as a straight windrow of loose clay beside it, with round ends, holding the
## loose volume the trench bank volume makes.
static func _lay_spoil(terrain: Terrain) -> void:
	var clay := terrain.material_params(CLAY)
	var slope := tan(deg_to_rad(clay.repose_angle_deg - PILE_SLOPE_MARGIN_DEG))
	var length := TRENCH_Z.x - TRENCH_Z.y
	var volume := trench_bank_volume(terrain) * terrain.swell_factor(CLAY)
	# Ridge height h: a triangular prism h^2 / slope over the length, and a half cone at
	# each end, together pi h^3 / (3 slope^2). Newton steps on the volume.
	var ridge := sqrt(volume * slope / length)
	for i in 8:
		var held := ridge * ridge * length / slope + PI * pow(ridge, 3.0) / (3.0 * slope * slope)
		var rate := 2.0 * ridge * length / slope + PI * ridge * ridge / (slope * slope)
		ridge -= (held - volume) / rate
	var ridge_x := TRENCH_X - SPOIL_OFFSET
	_lay_shape(terrain, CLAY, Rect2(ridge_x - ridge / slope, TRENCH_Z.y - ridge / slope,
			ridge / slope * 2.0, length + ridge / slope * 2.0), func(x: float, z: float) -> float:
		var along := maxf(maxf(TRENCH_Z.y - z, z - TRENCH_Z.x), 0.0)
		return ridge - Vector2(absf(x - ridge_x), along).length() * slope)


static func _lay_stockpile(terrain: Terrain) -> void:
	var sand := terrain.material_params(SAND)
	var slope := tan(deg_to_rad(sand.repose_angle_deg - PILE_SLOPE_MARGIN_DEG))
	for cone in STOCKPILE_CONES:
		_lay_shape(terrain, SAND, Rect2(cone.x - cone.z, cone.y - cone.z, cone.z * 2.0, cone.z * 2.0),
				func(x: float, z: float) -> float: return (cone.z - Vector2(x - cone.x, z - cone.y).length()) * slope)
	var ridge_height := STOCKPILE_RIDGE_HALF_WIDTH * slope
	var bounds := Rect2(STOCKPILE_RIDGE_FROM, Vector2.ZERO).expand(STOCKPILE_RIDGE_TO).grow(STOCKPILE_RIDGE_HALF_WIDTH)
	_lay_shape(terrain, SAND, bounds, func(x: float, z: float) -> float:
		var point := Vector2(x, z)
		var closest := Geometry2D.get_closest_point_to_segment(point, STOCKPILE_RIDGE_FROM, STOCKPILE_RIDGE_TO)
		return ridge_height - point.distance_to(closest) * slope)


static func _lay_truckloads(terrain: Terrain) -> void:
	var earth := terrain.material_params(EARTH)
	var slope := tan(deg_to_rad(earth.repose_angle_deg - PILE_SLOPE_MARGIN_DEG))
	var radius := pow(3.0 * TRUCKLOAD / (PI * slope), 1.0 / 3.0)
	var spacing := Vector2(LEVEL_AREA.size.x / LEVEL_PILES.x, LEVEL_AREA.size.y / LEVEL_PILES.y)
	for row in LEVEL_PILES.y:
		for column in LEVEL_PILES.x:
			# Dumped where the truck stopped, not on a grid.
			var jitter := Vector2(sin(column * 12.9 + row * 78.2), cos(column * 39.3 + row * 11.7)) * 1.5
			var centre := LEVEL_AREA.position + spacing * (Vector2(column, row) + Vector2(0.5, 0.5)) + jitter
			_lay_shape(terrain, EARTH, Rect2(centre - Vector2.ONE * radius, Vector2.ONE * radius * 2.0),
					func(x: float, z: float) -> float: return (radius - Vector2(x, z).distance_to(centre)) * slope)


## Lays loose soil of one material over an area, as thick as shape.call(x, z) wherever
## that is positive.
static func _lay_shape(terrain: Terrain, material: int, area: Rect2, shape: Callable) -> void:
	var from := terrain.nearest_point(area.position.x, area.position.y)
	var to := terrain.nearest_point(area.end.x, area.end.y)
	var cell_area := terrain.cell_size * terrain.cell_size
	for iz in range(from.y, to.y + 1):
		for ix in range(from.x, to.x + 1):
			var at := terrain.point_position(ix, iz)
			var thickness: float = shape.call(at.x, at.y)
			if thickness > 0.0:
				terrain.add_loose(ix, iz, thickness * cell_area, material)
