extends RefCounted
## Phase 6 checks: ground materials (data, digging one and dumping it on another, mixed
## piles, resistance), the work site layout, the truck against its data sheets and the
## soil in its body, the time of day, and on a running tree the free camera, the soil drawn
## falling from the bucket, a bucket poured into the truck, and the bucket butting against
## the truck.
## Driven by run_tests.gd, which owns the check counters.

const DT := 1.0 / 120.0
const SoilTests := preload("res://tests/soil_tests.gd")
const EARTH := 0
const CLAY := 1
const SAND := 2

var _runner: SceneTree


func _init(runner: SceneTree) -> void:
	_runner = runner


func run(params: MachineParams) -> void:
	var materials: Array[SoilParams] = [load("res://data/common_earth.tres"), load("res://data/clay.tres"),
			load("res://data/sand.tres")]
	_test_material_data(materials)
	_test_dig_clay_dump_on_sand(params, materials)
	_test_mixed_pile(materials)
	_test_material_resistance(params, materials)
	_test_site_ground(materials)
	var truck: TruckParams = load("res://data/man_tgs_8x4_tipper.tres")
	_test_truck_data(truck)
	_test_truck_body(truck, materials, params)
	_test_sun_path()


func run_scene(excavator: Excavator) -> void:
	_test_lighting_nodes(excavator.get_parent())
	_test_free_camera(excavator)
	_test_pouring_shows(excavator)
	_test_pour_into_truck(excavator)
	_test_bucket_butts_against_truck(excavator)


func _test_material_data(materials: Array[SoilParams]) -> void:
	print("Ground materials")
	var earth := materials[EARTH]
	var clay := materials[CLAY]
	var sand := materials[SAND]
	_near(1.0 / (1.0 + clay.swell()), 0.82, 0.01, "clay in its natural bed, load factor (handbook 0.82)")
	_near(1.0 / (1.0 + sand.swell()), 0.89, 0.01, "damp sand, load factor (handbook 0.89)")
	_check(clay.repose_angle_deg >= 20.0 and clay.repose_angle_deg <= 35.0,
			"clay angle of repose within the handbook 20 to 35 deg for gravel, sand and clay")
	_check(sand.repose_angle_deg >= 30.0 and sand.repose_angle_deg <= 45.0,
			"damp sand angle of repose within the handbook 30 to 45 deg")
	_check(clay.cutting_resistance > earth.cutting_resistance and earth.cutting_resistance > sand.cutting_resistance,
			"at the surface the teeth cut clay hardest and sand easiest")
	_check(clay.bearing_capacity > earth.bearing_capacity and earth.bearing_capacity > sand.bearing_capacity,
			"and the back of the bucket bears most on clay and least on sand")
	_check(sand.overburden_factor > earth.overburden_factor and earth.overburden_factor > clay.overburden_factor,
			"resistance grows with depth most in sand and least in clay")
	var names := {}
	for material in materials:
		names[material.display_name] = true
	_check(names.size() == materials.size() and materials.all(func(m: SoilParams) -> bool:
			return m.bucket_heap_angle_deg == 45.0), "every material has its own name and the SAE 45 deg heap")


## Clay under the digging area, sand where the load is dumped.
func _test_dig_clay_dump_on_sand(params: MachineParams, materials: Array[SoilParams]) -> void:
	print("Digging clay and dumping it on sand")
	var rig = SoilTests.Rig.new(params, materials[EARTH])
	var terrain: Terrain = rig.terrain
	terrain.materials = materials
	terrain.setup(160, 0.25)
	terrain.paint_material(Rect2(-4.0, -10.0, 8.0, 7.0), CLAY)
	terrain.paint_material(Rect2(3.0, -4.0, 10.0, 8.0), SAND)
	var start := PackedFloat64Array()
	for m in materials.size():
		start.append(terrain.bank_volume_of(m))
	var bucket: BucketSoil = rig.bucket
	rig.move_tip(Vector2(7.4, 0.2), -100.0, 0.0)
	rig.move_tip(Vector2(7.2, -0.5), -105.0, 0.6)
	rig.move_tip(Vector2(5.4, -0.35), -125.0, 2.0)
	rig.move_tip(Vector2(5.0, 0.3), -170.0, 1.2)
	var volumes := bucket.load_volumes()
	_check(bucket.fill > 0.9 and volumes[CLAY] > 0.99 * bucket.fill,
			"a pass through clay fills the bucket with clay (%.2f of %.2f m3)" % [volumes[CLAY], bucket.fill])
	_near(bucket.load_mass(), bucket.fill * materials[CLAY].loose_density, 0.01, "load mass from the clay loose density (kg)")
	rig.move_tip(Vector2(5.0, 1.8), -174.9, 1.0)
	rig.swing_to(90.0, 2.0)
	rig.turn_bucket(params.bucket_max_deg, 4.0)
	rig.hold(3.0)
	var pile := rig.bucket_world().origin
	var point := terrain.nearest_point(pile.x, pile.z)
	_check(terrain.point_material(point.x, point.y) == SAND and terrain.loose_material_at(pile.x, pile.z) == CLAY,
			"the dumped pile is clay lying on sand")
	var worst := 0.0
	var parts := bucket.load_volumes()
	for m in materials.size():
		var in_bucket: float = parts[m] / (1.0 + materials[m].swell())
		worst = maxf(worst, absf(terrain.bank_volume_of(m) + in_bucket - start[m]))
	_check(worst < 1e-3, "each material keeps its volume through the cycle (worst %.5f m3)" % worst)
	var recount := 0.0
	for m in materials.size():
		recount = maxf(recount, absf(terrain.bank_volume_of(m) - terrain.bank_volume_of_recount(m)))
	_check(recount < 1e-3, "running volume of each material matches a full recount")
	terrain.free()


func _test_mixed_pile(materials: Array[SoilParams]) -> void:
	print("Mixed pile")
	var terrain := Terrain.new()
	terrain.materials = materials
	terrain.setup(64, 0.25)
	var poured := 0.0
	while poured < 1.2:
		terrain.deposit(0.0, 0.0, 0.004, CLAY)
		terrain.deposit(0.0, 0.0, 0.004, SAND)
		poured += 0.008
		terrain.relax(Terrain.RELAX_VISITS_PER_TICK)
	while terrain.relax(Terrain.RELAX_VISITS_PER_TICK) > 0:
		pass
	var steepest := 0.0
	var shares_kept := true
	for iz in range(1, terrain.cells):
		for ix in range(1, terrain.cells):
			var i := iz * terrain.points + ix
			if terrain.loose[i] <= 0.01:
				continue
			var clay_share := terrain.loose_parts[CLAY][i] / terrain.loose[i]
			shares_kept = shares_kept and absf(clay_share - 0.5) < 0.01
			var height := terrain.point_height(ix, iz)
			for k in 8:
				var drop := height - terrain.point_height(ix + Terrain.NEIGHBOUR_X[k], iz + Terrain.NEIGHBOUR_Z[k])
				var run := terrain.cell_size * (1.0 if k < 4 else sqrt(2.0))
				steepest = maxf(steepest, rad_to_deg(atan(drop / run)))
	var mean := rad_to_deg(atan((tan(deg_to_rad(materials[CLAY].repose_angle_deg))
			+ tan(deg_to_rad(materials[SAND].repose_angle_deg))) * 0.5))
	_check(steepest <= mean + 0.05 and steepest > materials[SAND].repose_angle_deg,
			"half clay, half sand stands at %.1f deg, between sand and clay (%.1f deg)" % [steepest, mean])
	_check(shares_kept, "sliding soil keeps its half and half mix")
	var clay_volume := 0.6 / (1.0 + materials[CLAY].swell())
	var sand_volume := 0.6 / (1.0 + materials[SAND].swell())
	_check(absf(terrain.bank_volume_of(CLAY) - clay_volume) < 1e-3 and absf(terrain.bank_volume_of(SAND) - sand_volume) < 1e-3,
			"relaxation keeps the volume of each material")
	terrain.free()


## The same push of the teeth into each material.
func _test_material_resistance(params: MachineParams, materials: Array[SoilParams]) -> void:
	print("Resistance of each material")
	var bucket := BucketSoil.new()
	bucket.setup(params, materials[EARTH])
	var forces := PackedFloat64Array()
	for m in materials.size():
		var terrain := Terrain.new()
		terrain.materials = materials
		terrain.setup(96, 0.25)
		terrain.paint_material(Rect2(-12.0, -12.0, 24.0, 24.0), m)
		var angles: Vector3 = ArmGeometry.pose_for_tip(params, Vector2(6.5, -0.3), -95.0)
		var deeper: Vector3 = ArmGeometry.pose_for_tip(params, Vector2(6.5, -0.32), -95.0)
		var from := ArmGeometry.bucket_transform(params, 0.0, angles.x, angles.y, angles.z)
		var to := ArmGeometry.bucket_transform(params, 0.0, deeper.x, deeper.y, deeper.z)
		forces.append((bucket.resistance(terrain, from, to)["force"] as Vector3).length())
		terrain.free()
	_check(forces[CLAY] > forces[EARTH] and forces[EARTH] > forces[SAND] and forces[SAND] > 0.0,
			"teeth pushed 30 cm deep: clay %.0f kN, earth %.0f kN, sand %.0f kN" % [forces[CLAY] / 1000.0,
			forces[EARTH] / 1000.0, forces[SAND] / 1000.0])


func _test_site_ground(materials: Array[SoilParams]) -> void:
	print("Work site")
	var state := (load("res://scenes/main.tscn") as PackedScene).get_state()
	var settings := {}
	for node in state.get_node_count():
		if state.get_node_name(node) == "Terrain":
			for property in state.get_node_property_count(node):
				settings[state.get_node_property_name(node, property)] = state.get_node_property_value(node, property)
	_check(settings.get("layout") == Terrain.Layout.SITE and settings.get("cells", 0) * 0.25 >= 200.0
			and (settings.get("materials", []) as Array).size() == 3,
			"the game opens on the work site, %.0f m square, with earth, clay and sand" % (settings.get("cells", 0) * 0.25))

	var terrain := Terrain.new()
	terrain.materials = materials
	terrain.setup(832, 0.25)
	var started := Time.get_ticks_msec()
	SiteGround.build(terrain)
	print("        built in %d ms" % (Time.get_ticks_msec() - started))
	var flat := true
	for x in range(-16, 25, 2):
		for z in range(-4, 27, 2):
			flat = flat and absf(terrain.height_at(x, z)) < 0.005
	_check(flat, "the start platform is flat")

	var trench := terrain.height_at(SiteGround.TRENCH_X, -16.0)
	_check(absf(trench + SiteGround.TRENCH_DEPTH) < 1e-3 and terrain.material_at(SiteGround.TRENCH_X, -16.0) == CLAY
			and absf(terrain.height_at(SiteGround.TRENCH_X, -3.0)) < 1e-3,
			"a trench is started in clay 6 m ahead of the machine, %.1f m deep" % -trench)
	var dug := SiteGround.trench_bank_volume(terrain)
	_near(SiteGround.loose_volume(terrain, CLAY), dug * terrain.swell_factor(CLAY), 0.02,
			"its spoil windrow holds the %.1f m3 dug, swollen (m3)" % dug)

	_near(terrain.height_at(-65.0, -20.0), SiteGround.BENCH_HEIGHT, 0.001, "bench top height (m)")
	var face := (terrain.height_at(-49.5, -20.0) - terrain.height_at(-46.5, -20.0)) / 3.0
	_near(face, 1.0 / SiteGround.BENCH_FACE_RUN, 0.02, "bench face slope, 3:2")
	var ramp := (terrain.height_at(-69.0, 25.0) - terrain.height_at(-69.0, 35.0)) / 10.0
	_near(ramp, SiteGround.RAMP_SLOPE, 0.01, "access ramp slope")

	_near(SiteGround.loose_volume(terrain, EARTH), SiteGround.TRUCKLOAD * SiteGround.LEVEL_PILES.x * SiteGround.LEVEL_PILES.y,
			0.03, "truckload piles of earth to level (m3)")
	print("        sand stockpile %.0f m3" % SiteGround.loose_volume(terrain, SAND))
	var before := terrain.heights.duplicate()
	for iz in terrain.points:
		for ix in terrain.points:
			if terrain.point_loose(ix, iz) > 0.0:
				terrain.add_loose(ix, iz, 0.0)
	var steps := 0
	while terrain.relax(4000) > 0 and steps < 500:
		steps += 1
	var moved := 0.0
	for i in before.size():
		moved = maxf(moved, absf(terrain.heights[i] - before[i]))
	_check(moved < 0.005, "every pile stands at its angle of repose as built (%.3f m moved)" % moved)

	var lowest := INF
	var highest := -INF
	for x in range(20, 95, 3):
		for z in range(40, 95, 3):
			lowest = minf(lowest, terrain.height_at(x, z))
			highest = maxf(highest, terrain.height_at(x, z))
	_check(highest - lowest > 0.3 and highest - lowest < 1.5,
			"the natural ground rolls gently away from the work areas (%.2f m)" % (highest - lowest))
	terrain.free()


func _test_truck_data(truck: TruckParams) -> void:
	print("Truck against its data sheets")
	_near(truck.overall_length(), 1.475 + 1.795 + 3.205 + 1.4 + 0.8, 1e-4, "MAN TGS 8x4 overall length from its axle spacings (m)")
	_near(truck.cab_height, 3.158, 1e-4, "cab roof height, unladen (m)")
	_near(truck.frame_height, 1.046, 1e-4, "frame height at the rear wheels, unladen (m)")
	_check(truck.body_inside_rear() + truck.body_wall_thickness <= truck.overall_length() + 0.05,
			"the body ends with the frame (%.2f m for %.2f m)" % [truck.body_inside_rear() + truck.body_wall_thickness,
			truck.overall_length()])
	_check(truck.body_inner_width + truck.body_wall_thickness * 2.0 <= 2.55, "the body stays within the 2.55 m road width")
	_check(truck.body_side_height >= truck.ref_side_height_range.x - 1e-4 and truck.body_side_height <= truck.ref_side_height_range.y + 1e-4,
			"side walls within the MEILLER P430 range")
	_check(truck.struck_volume() <= truck.ref_body_max_volume and truck.struck_volume() > 0.85 * truck.ref_body_max_volume,
			"body holds %.1f m3 level, MEILLER P430 up to %.0f m3" % [truck.struck_volume(), truck.ref_body_max_volume])
	_check(truck.loading_height() > 2.3 and truck.loading_height() < 3.0,
			"side wall tops %.2f m above the ground" % truck.loading_height())
	_check(truck.payload() > 17000.0 and truck.payload() < 21000.0, "payload %.1f t on a 32 t truck" % (truck.payload() / 1000.0))


## Full buckets of earth poured along the body, the way an operator spreads them.
func _test_truck_body(truck: TruckParams, materials: Array[SoilParams], params: MachineParams) -> void:
	print("Soil in the truck body")
	var body := TruckLoad.new()
	body.setup(truck, materials)
	var spilled := [0.0]
	var overflow := func(_point: Vector3, volumes: PackedFloat64Array) -> void:
		for volume in volumes:
			spilled[0] += volume
	var bucket := BucketSoil.new()
	bucket.setup(params, materials[EARTH])
	var bucket_volume := bucket.max_fill()
	var level_buckets := floori(truck.struck_volume() / bucket_volume)
	var poured := 0.0
	var count := 0
	var first_overflow := -1
	var volumes := PackedFloat64Array([0.0, 0.0, 0.0])
	while count < 30 and first_overflow < 0:
		volumes[EARTH] = bucket_volume
		# Spread along the body front to back, then again.
		var spot := fmod(count * 0.37, 1.0)
		var z := lerpf(truck.body_inside_front() + 0.6, truck.body_inside_rear() - 0.6, spot)
		for piece in 12:
			body.catch_soil(Vector3(lerpf(-0.5, 0.5, (piece % 4) / 3.0), 4.0, z + (piece / 4 - 1) * 0.3), volumes, 1.0 / 12.0)
		poured += bucket_volume
		count += 1
		while body.relax(4000, overflow) > 0:
			pass
		if spilled[0] > 0.01 and first_overflow < 0:
			first_overflow = count
		if count == level_buckets:
			_check(spilled[0] < 1e-6 and absf(body.loose_volume() - poured) < 1e-3,
					"%d buckets of %.2f m3 fill the body to %.1f m3 without a spill" % [count, bucket_volume, body.loose_volume()])
	print("        first spill over a wall with bucket %d" % first_overflow)
	_check(first_overflow > level_buckets and first_overflow <= level_buckets + 6,
			"soil goes over the walls once the body is heaped, with bucket %d" % first_overflow)
	_check(absf(body.loose_volume() + spilled[0] - poured) < 1e-3, "the body keeps what it does not spill")
	var steepest := 0.0
	for iz in body.along:
		for ix in body.across - 1:
			var drop := absf(body.thickness[iz * body.across + ix] - body.thickness[iz * body.across + ix + 1])
			steepest = maxf(steepest, rad_to_deg(atan(drop / body.cell_x)))
	_check(steepest <= materials[EARTH].repose_angle_deg + 0.1, "no slope in the load steeper than the angle of repose")
	var payload_buckets := ceili(truck.payload() / (bucket_volume * materials[EARTH].loose_density))
	print("        payload reached after %d buckets of earth" % payload_buckets)
	var before := body.loose_volume()
	body.empty()
	_check(body.loose_volume() == 0.0 and absf(body.hauled[EARTH] - before) < 1e-6, "emptying takes the whole load away")


## A full bucket turned over the body from the machine at the start position.
func _test_pour_into_truck(excavator: Excavator) -> void:
	print("Pouring into the truck")
	var terrain := Terrain.new()
	terrain.layout = Terrain.Layout.FLAT
	terrain.cells = 96
	terrain.chunk_cells = 32
	terrain.tile_cells = 32
	var parent := excavator.get_parent()
	parent.add_child(terrain)
	var truck := DumpTruck.new()
	truck.params = load("res://data/man_tgs_8x4_tipper.tres")
	truck.terrain_path = truck.get_path_to(terrain) if truck.is_inside_tree() else NodePath()
	truck.position = Vector3(7.5, 0.0, -6.5)
	parent.add_child(truck)
	truck.terrain = terrain
	truck._rebuild()
	excavator.terrain = terrain
	excavator.bucket_soil.clear()
	excavator.place(Vector2.ZERO, 0.0)
	var params := excavator.params
	var profile := params.bucket_profile
	var rim := profile[0]
	var tip := profile[profile.size() - 1]
	var level := 180.0 + rad_to_deg(atan2(rim.y - tip.y, tip.x - rim.x))
	var pose: Vector3 = ArmGeometry.pose_for_tip(params, Vector2(6.5, 3.4), level)
	excavator.set_pose(90.0, pose.x, pose.y, pose.z)
	excavator.bucket_soil.fill = excavator.bucket_soil.max_fill()
	var poured := excavator.bucket_soil.fill
	var start := terrain.bank_volume() + excavator.bucket_soil.bank_fill()
	var steps := int(round(3.0 / DT))
	for i in steps + int(round(2.0 / DT)):
		var angle := lerpf(pose.z, params.bucket_max_deg, minf(float(i + 1) / steps, 1.0))
		excavator.pose_and_dig(90.0, pose.x, pose.y, angle, DT)
		truck._physics_process(DT)
	while truck.body_load.relax(4000, truck._overflow) > 0:
		pass
	var in_body := truck.body_load.loose_volume()
	var deepest := 0
	for cell in truck.body_load.thickness.size():
		if truck.body_load.thickness[cell] > truck.body_load.thickness[deepest]:
			deepest = cell
	var cell_centre := truck.body_load.cell_centre(deepest % truck.body_load.across, deepest / truck.body_load.across)
	var heap := truck.to_global(cell_centre)
	var heap_top := truck.global_position.y + truck.params.body_floor_height + truck.body_load.thickness[deepest]
	_check(absf(terrain.landing_height(heap.x, heap.z, 5.0) - heap_top) < 1e-4,
			"soil falling over the body lands on the load in it (%.2f m)" % terrain.landing_height(heap.x, heap.z, 5.0))
	# Turning the bucket over without moving the arm sweeps the pour 2.5 m across the body.
	_check(in_body > 0.9 * poured and excavator.bucket_soil.fill < 0.02,
			"a full bucket turned over the body without moving the arm leaves %.2f of %.2f m3 in it" % [in_body, poured])
	var under := 0.0
	for iz in terrain.points:
		for ix in terrain.points:
			var at := terrain.point_position(ix, iz)
			var local := truck.to_local(Vector3(at.x, 0.0, at.y))
			var margin := terrain.cell_size + 0.05
			if absf(local.x) < truck.params.body_inner_width * 0.5 - margin and local.z > truck.params.body_inside_front() + margin 					and local.z < truck.params.body_inside_rear() - margin:
				under += terrain.point_loose(ix, iz)
	_check(under * terrain.cell_size * terrain.cell_size < 1e-4, "and none of it falls through onto the ground under the body")
	var balance := terrain.bank_volume() + excavator.bucket_soil.bank_fill() + truck.body_load.bank_volume() - start
	_check(absf(balance) < 1e-3, "the soil volume counts the truck load (%.5f m3)" % balance)
	excavator.terrain = null
	excavator.bucket_soil.clear()
	excavator.reset_pose()
	excavator.return_to_start()
	truck.queue_free()
	terrain.queue_free()


func _test_bucket_butts_against_truck(excavator: Excavator) -> void:
	print("Bucket against the truck")
	var terrain := Terrain.new()
	terrain.layout = Terrain.Layout.FLAT
	terrain.cells = 96
	terrain.chunk_cells = 32
	terrain.tile_cells = 32
	var parent := excavator.get_parent()
	parent.add_child(terrain)
	var truck := DumpTruck.new()
	truck.params = load("res://data/man_tgs_8x4_tipper.tres")
	truck.position = Vector3(7.5, 0.0, -6.5)
	parent.add_child(truck)
	truck.terrain = terrain
	truck._rebuild()
	excavator.terrain = terrain
	excavator.bucket_soil.clear()
	excavator.controls.pattern = ControlInput.Pattern.ISO
	excavator.place(Vector2.ZERO, 0.0)
	var params := excavator.params

	# Swinging right with the bucket between the body floor and the wall tops.
	var reach: Vector3 = ArmGeometry.pose_for_tip(params, Vector2(7.2, 1.9), -100.0)
	excavator.set_pose(0.0, reach.x, reach.y, reach.z)
	var worst := _hold_keys_against(excavator, truck, [KEY_D], 3.0)
	var swing := excavator.swing_joint.angle_deg
	_check(swing > 40.0 and swing < 62.0 and worst < 0.03,
			"swinging into the body side, the turret stops at %.0f deg with the bucket %.3f m into the wall" % [swing, worst])

	# Boom lowered with the bottom of a curled bucket across the near side wall: the bucket
	# comes to rest on the wall top and the boom lifts the machine, as on hard ground; held
	# down, the machine tips on until the bucket slides off the wall.
	var above: Vector3 = ArmGeometry.pose_for_tip(params, Vector2(6.0, 3.4), -150.0)
	excavator.set_pose(90.0, above.x, above.y, above.z)
	excavator.place(Vector2.ZERO, 0.0)
	var lowest_before := _bucket_lowest(excavator)
	worst = _hold_keys_against(excavator, truck, [KEY_I], 0.7, false)
	var lowest := _bucket_lowest(excavator)
	var wall_top := truck.params.loading_height()
	_check(lowest_before > wall_top + 0.2 and lowest > wall_top - 0.3 and worst < 0.03,
			"the boom lowered on the wall top rests the bucket on it (lowest %.2f m, wall %.2f m, %.3f m in)"
			% [lowest, wall_top, worst])
	_check(excavator.boom_joint.pressure >= excavator.boom_joint.relief_pressure * 0.99 and excavator.ground.tip_angle > 0.0,
			"the boom pushes at its relief pressure and lifts the machine (%.1f deg)" % excavator.ground.tip_deg())
	worst = maxf(worst, _hold_keys_against(excavator, truck, [KEY_I], 2.0))
	_check(worst < 0.03, "held down, the bucket never goes into the truck (%.3f m)" % worst)

	# Cost of the contact with the bucket against the truck.
	var from := excavator.bucket.global_transform
	var to := from.translated(Vector3(0.0, -0.01, 0.0))
	var started := Time.get_ticks_usec()
	for i in 100:
		excavator.bucket_soil.resistance(terrain, from, to)
	var cost := (Time.get_ticks_usec() - started) / 100000.0
	_check(cost < 1.0, "resistance with the bucket on the truck takes %.2f ms" % cost)

	excavator.terrain = null
	excavator.bucket_soil.clear()
	excavator.ground.clear_tip()
	excavator.reset_pose()
	excavator.return_to_start()
	truck.queue_free()
	terrain.queue_free()


## Deepest a bucket sample point is inside a truck part (m).
func _deepest_in_truck(excavator: Excavator, truck: DumpTruck) -> float:
	var bucket := excavator.bucket_soil
	var to_truck := truck.global_transform.affine_inverse() * excavator.bucket.global_transform
	var deepest := 0.0
	for s in bucket.sample_count():
		var point := to_truck * bucket.sample_point(s)
		for solid in truck._solids:
			if solid.has_point(point):
				var depth := minf(minf(point.x - solid.position.x, solid.end.x - point.x),
						minf(minf(point.y - solid.position.y, solid.end.y - point.y), minf(point.z - solid.position.z, solid.end.z - point.z)))
				deepest = maxf(deepest, depth)
	return deepest


func _bucket_lowest(excavator: Excavator) -> float:
	var xform := excavator.bucket.global_transform
	var lowest := INF
	for s in excavator.bucket_soil.sample_count():
		lowest = minf(lowest, (xform * excavator.bucket_soil.sample_point(s)).y)
	return lowest


## Holds keys down, then releases them and lets the machine settle unless told not to.
## Returns how deep the bucket went into the truck at worst (m).
func _hold_keys_against(excavator: Excavator, truck: DumpTruck, keys: Array, duration: float, release := true) -> float:
	var worst := 0.0
	for key in keys:
		_send_key(key, true)
	for i in int(round(duration / DT)):
		excavator._physics_process(DT)
		worst = maxf(worst, _deepest_in_truck(excavator, truck))
	for key in keys:
		_send_key(key, false)
	if release:
		for i in int(round(0.5 / DT)):
			excavator._physics_process(DT)
			worst = maxf(worst, _deepest_in_truck(excavator, truck))
	return worst


func _test_sun_path() -> void:
	print("Time of day")
	var lighting := SiteLighting.new()
	var solar_noon := 12.0 + lighting.clock_offset
	_near(lighting.sun_elevation_deg(solar_noon), 90.0 - lighting.latitude_deg + lighting.declination_deg(), 0.002,
			"sun height at solar noon (deg)")
	var noon := lighting.sun_direction(solar_noon)
	_check(noon.z > 0.0 and absf(noon.x) < 1e-6, "the sun is due south (+Z) at solar noon")
	_check(lighting.sun_direction(solar_noon - 3.0).x > 0.0 and lighting.sun_direction(solar_noon + 3.0).x < 0.0,
			"the sun is in the east in the morning and in the west in the afternoon")
	_check(absf(lighting.sun_elevation_deg(lighting.sunrise())) < 0.01 and absf(lighting.sun_elevation_deg(lighting.sunset())) < 0.01,
			"the sun is on the horizon at sunrise and sunset")
	_check(lighting.sunrise() > 7.0 and lighting.sunrise() < 8.0 and lighting.sunset() > 19.5 and lighting.sunset() < 20.5,
			"sunrise %s and sunset %s, clock time in mid-September" % [_clock(lighting.sunrise()), _clock(lighting.sunset())])
	lighting.hour = 12.0
	for i in 100:
		lighting.change_hour(-1)
	_near(lighting.hour, lighting.sunrise() - lighting.twilight, 0.001, "earliest hour is half an hour before sunrise")
	for i in 100:
		lighting.change_hour(1)
	_near(lighting.hour, lighting.sunset() + lighting.twilight, 0.001, "latest hour is half an hour after sunset")
	lighting.free()


func _test_lighting_nodes(parent: Node) -> void:
	print("Lighting nodes")
	var sun := DirectionalLight3D.new()
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.sky = Sky.new()
	world.environment.sky.sky_material = ProceduralSkyMaterial.new()
	parent.add_child(sun)
	parent.add_child(world)
	var lighting := SiteLighting.new()
	lighting.sun_path = sun.get_path()
	lighting.environment_path = world.get_path()
	lighting.hour = 12.0 + lighting.clock_offset
	parent.add_child(lighting)
	var noon_sky := (world.environment.sky.sky_material as ProceduralSkyMaterial).sky_energy_multiplier
	_check(sun.global_basis.z.y > 0.0 and is_equal_approx(sun.light_energy, lighting.sun_energy),
			"at noon the sun shines down at full strength")
	lighting.hour = lighting.sunrise() - lighting.twilight
	lighting.apply()
	var dawn_sky := (world.environment.sky.sky_material as ProceduralSkyMaterial).sky_energy_multiplier
	_check(sun.light_energy < 0.1 * lighting.sun_energy and dawn_sky < 0.5 * noon_sky and sun.light_color.b < 0.5,
			"at dawn the sun is weak and orange and the sky is dim (sun %.2f, sky %.2f)" % [sun.light_energy, dawn_sky])
	lighting.queue_free()
	world.queue_free()
	sun.queue_free()


func _test_free_camera(excavator: Excavator) -> void:
	print("Free camera")
	var terrain := Terrain.new()
	terrain.layout = Terrain.Layout.FLAT
	terrain.cells = 64
	terrain.chunk_cells = 32
	terrain.tile_cells = 32
	var parent := excavator.get_parent()
	parent.add_child(terrain)
	var camera := FreeCamera.new()
	parent.add_child(camera)
	camera.fly(Vector3.ZERO)
	camera._terrain = terrain
	camera.global_position = Vector3(0.0, 3.0, 0.0)
	camera.make_current()
	var from := camera.global_position
	_send_key(FreeCamera.FORWARD_KEY, true)
	camera._process(0.5)
	_check(camera.global_position == from, "without the right button the keys leave the camera alone")
	var controls := ControlInput.new()
	controls.keyboard_enabled = false
	controls.poll()
	_check(controls.stick == 0.0, "the machine ignores the keyboard while the free camera has it")
	controls.keyboard_enabled = true
	controls.poll()
	_check(controls.stick != 0.0, "and reads it again afterwards")

	_press_right_button(camera, true)
	camera.turn(-90.0, 0.0)
	camera._process(0.5)
	var moved := camera.global_position - from
	_check(camera.piloting and is_equal_approx(moved.x, camera.speed * 0.5) and absf(moved.z) < 1e-4,
			"right button held, forward flies where the camera looks (%.2f m)" % moved.x)
	_send_key(FreeCamera.FORWARD_KEY, false)
	_send_key(FreeCamera.DOWN_KEY, true)
	camera._process(10.0)
	_near(camera.global_position.y, camera.ground_clearance, 0.001, "the camera stops above the ground")
	_send_key(FreeCamera.DOWN_KEY, false)
	_press_right_button(camera, false)
	var stopped := camera.global_position
	_send_key(FreeCamera.FORWARD_KEY, true)
	camera._process(0.5)
	_send_key(FreeCamera.FORWARD_KEY, false)
	_check(not camera.piloting and camera.global_position == stopped, "released, the camera stays where it is")

	var reference := Camera3D.new()
	parent.add_child(reference)
	reference.look_at_from_position(Vector3(4.0, 5.0, 6.0), Vector3(0.0, 1.0, 0.0))
	camera.copy_view(reference)
	_check(camera.global_transform.is_equal_approx(reference.global_transform),
			"switching to the free camera keeps the previous view")
	reference.queue_free()
	camera.queue_free()
	terrain.queue_free()


func _test_pouring_shows(excavator: Excavator) -> void:
	print("Soil falling from the bucket")
	var terrain := Terrain.new()
	terrain.layout = Terrain.Layout.FLAT
	terrain.cells = 96
	terrain.chunk_cells = 32
	terrain.tile_cells = 32
	excavator.get_parent().add_child(terrain)
	excavator.terrain = terrain
	excavator.bucket_soil.clear()
	excavator.place(Vector2.ZERO, 0.0)
	var params := excavator.params
	var profile := params.bucket_profile
	var rim := profile[0]
	var tip := profile[profile.size() - 1]
	var level := 180.0 + rad_to_deg(atan2(rim.y - tip.y, tip.x - rim.x))
	var pose: Vector3 = ArmGeometry.pose_for_tip(params, Vector2(6.0, 2.5), level)
	excavator.set_pose(0.0, pose.x, pose.y, pose.z)
	excavator.bucket_soil.fill = excavator.bucket_soil.max_fill()
	var fall := excavator.get_node("SoilFall") as SoilFallVisual
	for i in 24:
		excavator.pose_and_dig(0.0, pose.x, pose.y, pose.z, DT)
		excavator._process(DT)
	_check(excavator.bucket_soil.pour_rate < 1e-4 and not fall.stream.visible and not fall.stones.emitting
			and not fall.dust.emitting, "a level bucket carrying its load throws nothing")

	var peak := 0.0
	var shown := true
	var worst_ratio := 0.0
	var worst_landing := 0.0
	var thin := INF
	var thick := 0.0
	var steps := int(round(2.0 / DT))
	for i in steps + int(round(3.0 / DT)):
		var angle := lerpf(pose.z, params.bucket_max_deg, minf(float(i + 1) / steps, 1.0))
		excavator.pose_and_dig(0.0, pose.x, pose.y, angle, DT)
		excavator._process(DT)
		var soil := excavator.bucket_soil
		if soil.pour_rate <= SoilFallVisual.MIN_RATE:
			continue
		peak = maxf(peak, soil.pour_rate)
		for emitter in [[fall.stones, SoilFallVisual.STONES_PER_M3], [fall.crumbs, SoilFallVisual.CRUMBS_PER_M3]]:
			var expected := SoilFallVisual.emission_ratio(soil.pour_rate, emitter[1], SoilFallVisual.PIECE_LIFETIME,
					emitter[0].amount)
			worst_ratio = maxf(worst_ratio, absf(emitter[0].amount_ratio - expected))
		var landing := Vector3(soil.pour_point.x, terrain.height_at(soil.pour_point.x, soil.pour_point.z), soil.pour_point.z)
		worst_landing = maxf(worst_landing, fall.dust.global_position.distance_to(landing))
		var flat_across := Vector3(soil.pour_across.x, 0.0, soil.pour_across.z).normalized()
		for k in SoilFallVisual.LANDING_POINTS:
			var across := soil.pour_point + flat_across * soil.params.bucket_width * (k / 4.0 - 0.5)
			worst_landing = maxf(worst_landing, absf(fall.landing_heights[k] - terrain.height_at(across.x, across.z)))
		var thickness := SoilFallVisual.stream_thickness(soil.pour_rate, soil.params.bucket_width, soil.pour_spread)
		var closed := SoilFallVisual.stream_coverage(soil.pour_rate)
		thin = minf(thin, thickness * closed)
		thick = maxf(thick, thickness * closed)
		shown = shown and fall.stream.visible and fall.stones.emitting and fall.crumbs.emitting and fall.dust.emitting
	_check(shown, "pouring draws the falling soil with stones and crumbs in it, and raises dust")
	_check(peak > 0.3 and peak < SoilFallVisual.MAX_RATE,
			"the stream follows the pour rate up to %.2f m3/s within the particle budget" % peak)
	_check(worst_ratio < 1e-6, "stones and crumbs thrown per second are proportional to the volume poured per second")
	_check(thick > 3.0 * thin, "the falling soil thickens with the flow (%.3f to %.3f m of soil across)" % [thin, thick])
	_check(worst_landing < 1e-3, "the falling soil ends and the dust rises on the ground under the rim")
	_check(excavator.bucket_soil.fill < 0.02 and excavator.bucket_soil.pour_rate < SoilFallVisual.MIN_RATE
			and not fall.stream.visible and not fall.stones.emitting and not fall.dust.emitting,
			"once the bucket is empty the stream stops")
	excavator.terrain = null
	excavator.bucket_soil.clear()
	excavator.reset_pose()
	excavator.return_to_start()
	terrain.queue_free()


func _press_right_button(camera: FreeCamera, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	camera._unhandled_input(event)


static func _clock(hour: float) -> String:
	var minutes := roundi(hour * 60.0)
	return "%d h %02d" % [minutes / 60, minutes % 60]


static func _send_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, message: String) -> void:
	_runner.call("_check", condition, message)


func _near(value: float, expected: float, tolerance_ratio: float, message: String) -> void:
	_runner.call("_near", value, expected, tolerance_ratio, message)
