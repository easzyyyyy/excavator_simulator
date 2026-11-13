@tool
class_name DumpTruck
extends Node3D
## A tipper truck standing still on the site, drawn from TruckParams, with the soil in its
## body. It stands on the ground under its middle, facing -Z of its own transform.
##
## It joins the terrain's structures: soil poured over the body lands in it rather than on
## the ground, and slides at its angle of repose; what stands above a wall more steeply goes
## over it onto the ground. empty() takes the whole load away at once.
##
## The bucket butts against the cab, the body, the frame and the wheels as against rigid
## boxes: push_bucket() adds their push to the soil resistance, so the cylinders and the
## swing stall against the truck, and pressing the bucket down on it lifts the machine as
## pressing on hard ground does. The soil in the body does not resist the bucket.

## Cell visits per physics tick for the load relaxation.
const RELAX_VISITS := 240
## Shortest time between two redraws of the load while it keeps changing (s).
const REDRAW_INTERVAL := 0.05
## Pressure with which the truck pushes back on the bucket (Pa): steel on steel, far beyond
## what the cylinders can push, so that the contact stalls them instead of giving way.
const CONTACT_PRESSURE := 50.0e6
## Spacing of the points along the truck edges that the bucket can meet between its own
## sample points (m), and the width each point stands for (m).
const EDGE_SPACING := 0.1
const EDGE_WIDTH := 0.05

@export var params: TruckParams:
	set(value):
		params = value
		if is_node_ready():
			_rebuild()
@export var terrain_path: NodePath

var body_load := TruckLoad.new()
var terrain: Terrain

var _visual := TruckPrimitives.new()
## Rigid parts in truck space, the box around all of them, and points along their edges.
var _solids: Array[AABB] = []
var _solids_bounds := AABB()
var _edge_points := PackedVector3Array()
var _load_mesh := MeshInstance3D.new()
var _load_look := StandardMaterial3D.new()
var _redraw_age := 0.0


func _ready() -> void:
	# The load slides after the machine poured into it in the same physics step.
	process_physics_priority = Terrain.PHYSICS_PRIORITY
	_load_mesh.name = "BodyLoad"
	_load_look.vertex_color_use_as_albedo = true
	_load_look.vertex_color_is_srgb = true
	_load_look.roughness = 1.0
	_load_mesh.material_override = _load_look
	add_child(_load_mesh)
	if not Engine.is_editor_hint() and not terrain_path.is_empty():
		terrain = get_node_or_null(terrain_path) as Terrain
	_rebuild()


func _exit_tree() -> void:
	if terrain != null:
		terrain.structures.erase(self)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or terrain == null:
		return
	body_load.relax(RELAX_VISITS, _overflow)


func _process(delta: float) -> void:
	_redraw_age += delta
	if body_load.changed and _redraw_age >= REDRAW_INTERVAL:
		_redraw_load()


## Takes soil poured over the body at a world position, falling from a height: volumes
## (m3) per material, times scale. Returns whether the body caught it.
func catch_soil(world_x: float, world_z: float, from_height: float, volumes: PackedFloat64Array, scale: float) -> bool:
	var height := minf(from_height, global_position.y + 100.0)
	return body_load.catch_soil(to_local(Vector3(world_x, height, world_z)), volumes, scale)


## World height where soil falling from a height at a world position lands in the body,
## NAN where the body does not catch it.
func landing_height(world_x: float, world_z: float, from_height: float) -> float:
	var local := to_local(Vector3(world_x, minf(from_height, global_position.y + 100.0), world_z))
	var surface := body_load.landing_height(local)
	if is_nan(surface):
		return NAN
	return to_global(Vector3(local.x, surface, local.z)).y


## Takes the load away at once.
func empty() -> void:
	body_load.empty()


## Adds the truck's push on the bucket moving from one world pose to another to a
## BucketSoil.resistance() result: a bucket point entering a truck part over the motion, or
## going deeper into it, is pushed back out through the face it came in by; a truck edge
## point going deeper into the bucket pushes the bucket back through the bucket's nearest
## face. Following each point over the motion keeps a thin wall from slipping between two
## steps.
func push_bucket(bucket: BucketSoil, from: Transform3D, to: Transform3D, result: Dictionary) -> void:
	if _solids.is_empty():
		return
	var inverse := global_transform.affine_inverse()
	var to_truck := inverse * to
	var from_truck := inverse * from
	var box := bucket.bounds_at(to_truck)
	if not box.intersects(_solids_bounds):
		return
	var near: Array[AABB] = []
	for solid in _solids:
		if solid.intersects(box):
			near.append(solid)
	if near.is_empty():
		return
	var basis := global_basis
	for s in bucket.sample_count():
		var point := to_truck * bucket.sample_point(s)
		var before := from_truck * bucket.sample_point(s)
		for solid in near:
			if not solid.has_point(point) and solid.intersects_segment(before, point) == null:
				continue
			var normal := _entry_normal(solid, before)
			var going_in := (point - before).dot(-normal)
			if going_in > 0.0:
				_add_push(result, basis * normal * (CONTACT_PRESSURE * bucket.sample_area(s)), global_transform * point,
						going_in)
			break
	var to_bucket := to_truck.affine_inverse()
	var from_bucket := from_truck.affine_inverse()
	for point in _edge_points:
		if not box.has_point(point):
			continue
		var depth := bucket.prism_depth(to_bucket * point)
		if depth.x <= 0.0:
			continue
		var going_in := depth.x - bucket.prism_depth(from_bucket * point).x
		if going_in <= 0.0:
			continue
		var normal := to.basis * bucket.face_normal(int(depth.y))
		_add_push(result, -normal * (CONTACT_PRESSURE * EDGE_SPACING * EDGE_WIDTH), global_transform * point, going_in)


func _add_push(result: Dictionary, force: Vector3, world_point: Vector3, going_in: float) -> void:
	result["contact"] = true
	result["force"] += force
	result["moment"] += world_point.cross(force)
	if going_in > result["penetration"]:
		result["penetration"] = going_in
		result["deepest"] = world_point


## Outward normal of the face a point came in by: the face it stood furthest outside of, or
## the nearest face when it was already inside.
static func _entry_normal(solid: AABB, before: Vector3) -> Vector3:
	var inside := [before.x - solid.position.x, solid.end.x - before.x, before.y - solid.position.y,
			solid.end.y - before.y, before.z - solid.position.z, solid.end.z - before.z]
	var normals := [Vector3.LEFT, Vector3.RIGHT, Vector3.DOWN, Vector3.UP, Vector3.FORWARD, Vector3.BACK]
	var best := 0
	for k in 6:
		if inside[k] < inside[best]:
			best = k
	return normals[best]


## Rigid boxes from the primitives, and points every EDGE_SPACING along each box's twelve
## edges.
func _build_solids() -> void:
	_solids.clear()
	_edge_points = PackedVector3Array()
	for shape in _visual.solid_boxes():
		var solid: AABB = shape["box"]
		_solids.append(solid)
		_solids_bounds = solid if _solids.size() == 1 else _solids_bounds.merge(solid)
		for axis in 3:
			var others := [(axis + 1) % 3, (axis + 2) % 3]
			var length := solid.size[axis]
			var count := maxi(ceili(length / EDGE_SPACING), 1)
			for corner in 4:
				var start := solid.position
				start[others[0]] += solid.size[others[0]] * float(corner % 2)
				start[others[1]] += solid.size[others[1]] * float(corner / 2)
				for k in count + 1:
					var point := start
					point[axis] += length * k / count
					_edge_points.append(point)


func _rebuild() -> void:
	if params == null:
		return
	_visual.build(params, self)
	_build_solids()
	var materials: Array[SoilParams] = [Terrain.DEFAULT_SOIL]
	if terrain != null:
		materials = terrain.materials
	body_load.setup(params, materials)
	if terrain != null and not Engine.is_editor_hint():
		position.y = terrain.height_at(global_position.x, global_position.z)
		if not terrain.structures.has(self):
			terrain.structures.append(self)


## Soil going over a wall lands on the ground outside it.
func _overflow(local: Vector3, volumes: PackedFloat64Array) -> void:
	if terrain == null:
		return
	var world := to_global(local)
	terrain.deposit_parts(world.x, world.z, volumes)


## The load surface as a grid of quads over the floor, lifted to the soil in each cell,
## coloured by the material with the largest share, with skirts down to the floor at the
## walls for a heap standing above them.
func _redraw_load() -> void:
	_redraw_age = 0.0
	body_load.changed = false
	var grid := body_load
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var floor_y := params.body_floor_height
	for iz in grid.along:
		for ix in grid.across:
			var height := grid.thickness[iz * grid.across + ix]
			if height <= TruckLoad.LOOSE_EPSILON:
				continue
			var centre := grid.cell_centre(ix, iz)
			var color := _cell_color(iz * grid.across + ix)
			var corners := [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
			var top: Array[Vector3] = []
			for corner in corners:
				var jx := clampi(ix + (1 if corner.x > 0.0 else 0), 0, grid.across)
				var jz := clampi(iz + (1 if corner.y > 0.0 else 0), 0, grid.along)
				top.append(Vector3(centre.x + corner.x * grid.cell_x, floor_y + _corner_height(jx, jz), centre.z + corner.y * grid.cell_z))
			var start := vertices.size()
			MeshKit.add_face(vertices, normals, top, Vector3(centre.x, floor_y - 1.0, centre.z))
			# Skirts on the edges of the grid.
			var edges := []
			if ix == 0:
				edges.append([top[0], top[3]])
			if ix == grid.across - 1:
				edges.append([top[1], top[2]])
			if iz == 0:
				edges.append([top[0], top[1]])
			if iz == grid.along - 1:
				edges.append([top[3], top[2]])
			for edge in edges:
				var a: Vector3 = edge[0]
				var b: Vector3 = edge[1]
				MeshKit.add_face(vertices, normals, [a, b, Vector3(b.x, floor_y, b.z), Vector3(a.x, floor_y, a.z)],
						Vector3(centre.x, floor_y + height * 0.5, centre.z))
			for k in vertices.size() - start:
				colors.append(color)
	if vertices.is_empty():
		_load_mesh.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_load_mesh.mesh = mesh


## Soil thickness at a grid corner: the mean of the cells around it that hold soil.
func _corner_height(jx: int, jz: int) -> float:
	var grid := body_load
	var sum := 0.0
	var count := 0
	for dz in [-1, 0]:
		for dx in [-1, 0]:
			var ix: int = jx + dx
			var iz: int = jz + dz
			if ix < 0 or iz < 0 or ix >= grid.across or iz >= grid.along:
				continue
			sum += grid.thickness[iz * grid.across + ix]
			count += 1
	return sum / maxi(count, 1)


func _cell_color(i: int) -> Color:
	var grid := body_load
	var best := 0
	for m in grid.parts.size():
		if grid.parts[m][i] > grid.parts[best][i]:
			best = m
	return grid.materials[best].loose_color
