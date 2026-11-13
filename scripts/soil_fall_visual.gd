class_name SoilFallVisual
extends Node3D
## Soil pouring out of the bucket: a falling curtain of clumps from the rim down to where
## the soil lands, stones and crumbs tumbling in it, and the dust raised where it lands.
## Everything follows the poured flow: the curtain thickens and closes up, and the pieces
## and dust puffs thrown per second grow, in proportion to the loose volume poured per
## second, so a trickle shows a few scattered clumps and a full dump a thick stream.
##
## The soil lands where BucketSoil pours it: on the ground or in a structure under the
## rim (Terrain.landing_height()). The curtain ends there and the pieces vanish there.
##
## Everything lives in world space: the curtain is laid out by its shader around the pour
## point, the emitters follow the pour point, and pieces already falling keep going when
## the bucket moves.

## Stones and crumbs thrown per m3 poured.
const STONES_PER_M3 := 40.0
const CRUMBS_PER_M3 := 300.0
## Dust puffs raised per m3 poured.
const DUST_PER_M3 := 60.0
## Pour rate the particle budgets are sized for (m3/s); faster pours stay at that density.
const MAX_RATE := 3.0
## Longest fall a piece is kept for (s): 30 m of free fall.
const PIECE_LIFETIME := 2.5
const DUST_LIFETIME := 2.5
## Rate under which nothing is thrown (m3/s).
const MIN_RATE := 0.002
## Speed at which soil leaves the rim (m/s).
const EXIT_SPEED := 2.0
## Rate from which the curtain is closed (m3/s); under it, it thins out in proportion.
const FULL_STREAM_RATE := 0.8
const MIN_COVERAGE := 0.1
## Curtain thickness at the rim (m).
const MIN_THICKNESS := 0.05
const MAX_THICKNESS := 0.5
const LANDING_POINTS := 5
const STREAM_SIDES := 16
const STREAM_RINGS := 32
const STREAM_SHADER := preload("res://shaders/soil_stream.gdshader")
const PIECES_SHADER := preload("res://shaders/soil_pieces.gdshader")
## Grey the stones are drawn toward from the soil colour.
const STONE_GREY := Color(0.46, 0.44, 0.41)

var stream := MeshInstance3D.new()
var stones := GPUParticles3D.new()
var crumbs := GPUParticles3D.new()
var dust := GPUParticles3D.new()
## Landing heights at LANDING_POINTS across the stream, last drawn.
var landing_heights := PackedFloat32Array()
var _stream_look := ShaderMaterial.new()
var _shown_look: SoilParams
var _flow_time := 0.0


func _init() -> void:
	name = "SoilFall"
	top_level = true
	landing_heights.resize(LANDING_POINTS)
	_setup_stream()
	_setup_pieces(stones, STONES_PER_M3, 11)
	_setup_pieces(crumbs, CRUMBS_PER_M3, 23)
	_setup_dust()
	add_child(stream)
	add_child(stones)
	add_child(crumbs)
	add_child(dust)


## Lays the curtain from the pour point down to where the soil lands, places the emitters,
## and sets the curtain thickness and the emission from the pour rate.
func update(bucket_load: BucketSoil, terrain: Terrain) -> void:
	var rate := bucket_load.pour_rate if bucket_load != null else 0.0
	var pouring := rate > MIN_RATE
	if not pouring:
		stones.emitting = false
		crumbs.emitting = false
		dust.emitting = false
		stream.visible = false
		_flow_time = 0.0
		return
	var material := bucket_load.material_params(bucket_load.load_material())
	_show_material(material)
	stones.amount_ratio = emission_ratio(rate, STONES_PER_M3, PIECE_LIFETIME, stones.amount)
	crumbs.amount_ratio = emission_ratio(rate, CRUMBS_PER_M3, PIECE_LIFETIME, crumbs.amount)
	dust.amount_ratio = emission_ratio(rate, DUST_PER_M3, DUST_LIFETIME, dust.amount)
	_flow_time += get_process_delta_time() if is_inside_tree() else 0.0

	var point := bucket_load.pour_point
	var width := bucket_load.params.bucket_width
	var across := bucket_load.pour_across
	var up := (Vector3.UP - across * across.dot(Vector3.UP)).normalized()
	var flat_across := Vector3(across.x, 0.0, across.z).normalized()
	var outward := Vector3.UP.cross(flat_across)
	var lowest := INF
	for k in LANDING_POINTS:
		var at := point + flat_across * width * (float(k) / (LANDING_POINTS - 1) - 0.5)
		var height := terrain.landing_height(at.x, at.z, point.y) if terrain != null else 0.0
		landing_heights[k] = minf(height, point.y)
		lowest = minf(lowest, landing_heights[k])
	var thickness := stream_thickness(rate, width, bucket_load.pour_spread)

	stream.visible = true
	stream.custom_aabb = AABB(Vector3(point.x - width - thickness, lowest - 0.1, point.z - width - thickness),
			Vector3(2.0 * (width + thickness), point.y - lowest + 0.2, 2.0 * (width + thickness)))
	_stream_look.set_shader_parameter("rim_point", point)
	_stream_look.set_shader_parameter("across_axis", flat_across)
	_stream_look.set_shader_parameter("outward_axis", outward)
	_stream_look.set_shader_parameter("width", width)
	_stream_look.set_shader_parameter("thickness", thickness)
	_stream_look.set_shader_parameter("land_heights", landing_heights)
	_stream_look.set_shader_parameter("flow_time", _flow_time)
	var fall := point.y - lowest
	_stream_look.set_shader_parameter("flow_speed", (EXIT_SPEED + sqrt(EXIT_SPEED * EXIT_SPEED + 2.0 * 9.8 * fall)) * 0.5)
	_stream_look.set_shader_parameter("coverage", stream_coverage(rate))

	var rim := Transform3D(Basis(across, up, across.cross(up)), point)
	for emitter in [stones, crumbs]:
		emitter.global_transform = rim
		var process := emitter.process_material as ShaderMaterial
		process.set_shader_parameter("emission_extents", Vector3(width * 0.45, 0.03, thickness * 0.5))
		process.set_shader_parameter("rim_point", point)
		process.set_shader_parameter("across_axis", flat_across)
		process.set_shader_parameter("width", width)
		process.set_shader_parameter("land_heights", landing_heights)
	dust.global_position = Vector3(point.x, landing_heights[LANDING_POINTS / 2], point.z)
	# Emitting only once the emitters stand at the rim: a new pour does not throw pieces
	# from where the last one ended.
	stones.emitting = true
	crumbs.emitting = true
	dust.emitting = true


## Share of an emitter's particle budget used at a pour rate: particles per second over
## the budget's own rate.
static func emission_ratio(rate: float, per_m3: float, lifetime: float, amount: int) -> float:
	return clampf(rate * per_m3 * lifetime / amount, 0.0, 1.0)


## Curtain thickness at the rim (m): the flow through the rim width at the exit speed, no
## thinner than the part of the opening the soil leaves over.
static func stream_thickness(rate: float, width: float, spread: float) -> float:
	return clampf(maxf(rate / (maxf(width, 0.01) * EXIT_SPEED), spread), MIN_THICKNESS, MAX_THICKNESS)


## Share of the curtain filled with clumps at a pour rate.
static func stream_coverage(rate: float) -> float:
	return clampf(rate / FULL_STREAM_RATE, MIN_COVERAGE, 1.0)


## Colours the falling soil, its stones and its dust after the material poured, and
## sizes the stones after its grain.
func _show_material(material: SoilParams) -> void:
	if material == _shown_look:
		return
	_shown_look = material
	var dark := material.loose_color.darkened(0.15)
	var light := material.loose_color.lightened(0.15)
	_stream_look.set_shader_parameter("dark_color", dark)
	_stream_look.set_shader_parameter("light_color", light)
	_stream_look.set_shader_parameter("clump_size", clampf(material.grain_scale, 0.06, 0.25))
	var stone := stones.process_material as ShaderMaterial
	stone.set_shader_parameter("dark_color", _vertex_color(dark.lerp(STONE_GREY, 0.3).darkened(0.15)))
	stone.set_shader_parameter("light_color", _vertex_color(light.lerp(STONE_GREY, 0.3)))
	var stone_size := clampf(material.grain_scale * 1.3, 0.04, 0.35)
	stone.set_shader_parameter("size_min", stone_size * 0.35)
	stone.set_shader_parameter("size_max", stone_size)
	var crumb := crumbs.process_material as ShaderMaterial
	crumb.set_shader_parameter("dark_color", _vertex_color(dark))
	crumb.set_shader_parameter("light_color", _vertex_color(light))
	crumb.set_shader_parameter("size_min", 0.015)
	crumb.set_shader_parameter("size_max", 0.045)
	var fade := ((dust.process_material as ParticleProcessMaterial).color_ramp as GradientTexture1D).gradient
	var haze := material.ground_color.lightened(0.35)
	fade.set_color(0, Color(haze, 0.4))
	fade.set_color(1, Color(haze, 0.0))


## A colour for the pieces shader: its particle colours reach the draw material as they
## are, read there as sRGB vertex colours.
static func _vertex_color(color: Color) -> Vector3:
	return Vector3(color.r, color.g, color.b)


func _setup_stream() -> void:
	stream.name = "Stream"
	stream.visible = false
	stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_stream_look.shader = STREAM_SHADER
	stream.material_override = _stream_look
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring in STREAM_RINGS + 1:
		for around in STREAM_SIDES + 1:
			vertices.append(Vector3.ZERO)
			uvs.append(Vector2(float(around) / STREAM_SIDES, float(ring) / STREAM_RINGS))
	for ring in STREAM_RINGS:
		for around in STREAM_SIDES:
			var a := ring * (STREAM_SIDES + 1) + around
			var b := a + STREAM_SIDES + 1
			indices.append_array([a, a + 1, b, a + 1, b + 1, b])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	stream.mesh = mesh


## Falling pieces of one kind: an irregular stone mesh, per_m3 of them thrown per m3 poured.
func _setup_pieces(emitter: GPUParticles3D, per_m3: float, shape_seed: int) -> void:
	emitter.amount = ceili(MAX_RATE * per_m3 * PIECE_LIFETIME)
	emitter.lifetime = PIECE_LIFETIME
	emitter.emitting = false
	emitter.local_coords = false
	# Stepped every frame, so that pieces leave the rim where it is as it moves.
	emitter.fixed_fps = 0
	emitter.interpolate = false
	emitter.visibility_aabb = AABB(Vector3(-8.0, -32.0, -8.0), Vector3(16.0, 34.0, 16.0))
	var process := ShaderMaterial.new()
	process.shader = PIECES_SHADER
	process.set_shader_parameter("exit_speed", EXIT_SPEED)
	emitter.process_material = process
	var mesh := stone_mesh(shape_seed)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	mesh.surface_set_material(0, material)
	emitter.draw_pass_1 = mesh


## An irregular stone about one metre across: an icosahedron with each corner pushed in or
## out at random, drawn with flat faces.
static func stone_mesh(shape_seed: int) -> ArrayMesh:
	var random := RandomNumberGenerator.new()
	random.seed = shape_seed
	var golden := (1.0 + sqrt(5.0)) * 0.5
	var corners: Array[Vector3] = [
		Vector3(-1, golden, 0), Vector3(1, golden, 0), Vector3(-1, -golden, 0), Vector3(1, -golden, 0),
		Vector3(0, -1, golden), Vector3(0, 1, golden), Vector3(0, -1, -golden), Vector3(0, 1, -golden),
		Vector3(golden, 0, -1), Vector3(golden, 0, 1), Vector3(-golden, 0, -1), Vector3(-golden, 0, 1)]
	for k in corners.size():
		corners[k] = corners[k].normalized() * 0.5 * random.randf_range(0.7, 1.15)
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4],
		[11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for face in faces:
		MeshKit.add_face(vertices, normals, [corners[face[0]], corners[face[1]], corners[face[2]]], Vector3.ZERO)
	return MeshKit.array_mesh(vertices, normals)


func _setup_dust() -> void:
	dust.amount = ceili(MAX_RATE * DUST_PER_M3 * DUST_LIFETIME)
	dust.lifetime = DUST_LIFETIME
	dust.emitting = false
	dust.local_coords = false
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.visibility_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 10.0, 16.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.5
	process.direction = Vector3.UP
	process.spread = 70.0
	process.initial_velocity_min = 0.3
	process.initial_velocity_max = 1.2
	process.gravity = Vector3(0.0, 0.15, 0.0)
	process.damping_min = 0.4
	process.damping_max = 0.8
	process.scale_min = 0.7
	process.scale_max = 1.3
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.5))
	growth.add_point(Vector2(1.0, 2.2))
	var growth_texture := CurveTexture.new()
	growth_texture.curve = growth
	process.scale_curve = growth_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(0.6, 0.52, 0.43, 0.4))
	fade.set_color(1, Color(0.6, 0.52, 0.43, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	dust.process_material = process
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	var soft := Gradient.new()
	soft.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	soft.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	puff.gradient = soft
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * 1.5
	var material := StandardMaterial3D.new()
	material.vertex_color_is_srgb = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = puff
	material.proximity_fade_enabled = true
	material.proximity_fade_distance = 0.6
	mesh.material = material
	dust.draw_pass_1 = mesh
