class_name TrenchExercise
extends Node
## The trench task of the CACES R482 B1 practical test on the work site
## (TrenchExerciseParams, scored by TrenchEvaluation). start() rests the machine at its
## start place, arm plane on the trench axis, and paints the trench outline on the ground
## with a stake beyond the far end to aim at. The clock starts with the first command. The
## task stops as the test would, past the time limit or when the machine travels with a
## raised load, or when the operator declares the trench finished; the ground then settles
## and is scored. status_text() is the French text the HUD shows.

enum State { OFF, READY, RUNNING, DONE }

## Paint lines: width, and height of the box they are projected through, so that a line
## goes once its ground is dug away or covered with spoil (m).
const PAINT_WIDTH := 0.08
const PAINT_DEPTH := 0.3
const PAINT_COLOR := Color(0.95, 0.95, 0.9)
const STAKE_SIZE := Vector3(0.05, 1.0, 0.05)
const STAKE_COLOR := Color(0.95, 0.35, 0.05)
## Distance of the stake beyond the far end, on the axis (m).
const STAKE_BEYOND := 1.0
## Relaxation before scoring: visits per call, and calls at most.
const SETTLE_VISITS := 4000
const SETTLE_CALLS := 2000
const KEYS_RUNNING := "Entrée : terminer   Suppr : abandonner"
const KEYS_DONE := "P : recommencer   Entrée : quitter l'épreuve"

static var _paint: ImageTexture

@export var params: TrenchExerciseParams
@export var excavator_path: NodePath

var state := State.OFF
## Time since the first command (s).
var elapsed := 0.0
## Score of the finished task, see TrenchEvaluation.score().
var result := {}
var evaluation := TrenchEvaluation.new()
var excavator: Excavator

var _markings: Node3D


func _ready() -> void:
	process_physics_priority = Terrain.PHYSICS_PRIORITY + 1
	if excavator == null and not excavator_path.is_empty():
		excavator = get_node_or_null(excavator_path) as Excavator


func _physics_process(delta: float) -> void:
	if state == State.READY and _commanded():
		state = State.RUNNING
	if state != State.RUNNING:
		return
	elapsed += delta
	if raised_load_travel():
		_score(TrenchEvaluation.Failure.RAISED_LOAD)
	elif elapsed > params.time_limit():
		_score(TrenchEvaluation.Failure.TIME_OVER)


## Machine start place on the ground (x, z), facing the trench along -Z.
func start_place() -> Vector2:
	return Vector2(params.axis_x - excavator.params.boom_foot.x, params.far_end_z + params.start_distance)


func start() -> void:
	excavator.bucket_soil.clear()
	excavator.reset_pose()
	excavator.place(start_place(), 0.0)
	evaluation.capture(excavator.terrain, params)
	_paint_outline()
	elapsed = 0.0
	result = {}
	state = State.READY


## The operator declares the trench finished.
func finish() -> void:
	if state == State.RUNNING:
		_score(TrenchEvaluation.Failure.NONE)


## Leaves the exercise, keeping the ground as it is.
func stop() -> void:
	if _markings != null:
		remove_child(_markings)
		_markings.queue_free()
		_markings = null
	state = State.OFF
	elapsed = 0.0
	result = {}


## True while the tracks move with a loaded bucket held high: eliminatory in the test.
func raised_load_travel() -> bool:
	var travel := excavator.travel
	if maxf(absf(travel.left_speed), absf(travel.right_speed)) <= params.high_load_speed:
		return false
	var soil := excavator.bucket_soil
	if soil.fill <= params.high_load_fill:
		return false
	var xform := excavator.bucket.global_transform
	var lowest := INF
	for s in soil.sample_count():
		lowest = minf(lowest, (xform * soil.sample_point(s)).y)
	return lowest - excavator.global_position.y > params.high_load_height


func markings() -> Node3D:
	return _markings


func status_text() -> String:
	match state:
		State.READY:
			return "\n".join(PackedStringArray([
				_title(),
				_trench_line(),
				"Déblais en cordon, à %d cm au moins des bords" % roundi(params.berm_width * 100.0),
				"Temps de référence %s, arrêt à %s" % [duration_text(params.reference_time),
					duration_text(params.time_limit())],
				"Le chronomètre part au premier mouvement",
				KEYS_RUNNING,
			]))
		State.RUNNING:
			# The size stays on screen for the whole task.
			return "%s, déblais à %d cm des bords\n%s sur %s   %s" % [_trench_line(), roundi(params.berm_width * 100.0),
					duration_text(elapsed), duration_text(params.reference_time), KEYS_RUNNING]
		State.DONE:
			return report()
	return ""


func report() -> String:
	var lines := PackedStringArray([_title()])
	var total := "Note %s / %s : " % [_number(result["total"]), _number(params.total_points())]
	match result["failure"]:
		TrenchEvaluation.Failure.TIME_OVER:
			lines.append(total + "échouée, temps limite de %s dépassé" % duration_text(params.time_limit()))
		TrenchEvaluation.Failure.RAISED_LOAD:
			lines.append(total + "échouée, circulation avec le godet chargé en hauteur (critère éliminatoire)")
		_:
			lines.append(total + ("réussie" if result["passed"] else "échouée") + ", %s / %s requis" % [
					_number(params.pass_points), _number(params.total_points())])
	if not result["complete"]:
		lines.append("Tranchée inachevée : %d %% creusés, cordon et célérité non notés" % roundi(100.0 * result["dug_share"]))
	lines.append("Rectitude %s / %s : %d sections sur %d dans le tracé" % [_number(result["straightness"]),
			_number(params.straightness_points), result["sections_on_line"], result["sections"]])
	lines.append("Fond de fouille %s / %s : %d %% à %d cm près, %d %% à %d cm près, profondeur moyenne %s m" % [
			_number(result["bottom"]), _number(params.bottom_points), roundi(100.0 * result["within"]),
			roundi(params.bottom_tolerance * 100.0), roundi(100.0 * result["within_half"]),
			roundi(params.bottom_tolerance_half * 100.0), ("%.2f" % result["mean_depth"]).replace(".", ",")])
	lines.append("Cordon %s / %s : berme de %d cm dégagée à %d %%" % [_number(result["berm"]), _number(params.berm_points),
			roundi(params.berm_width * 100.0), roundi(100.0 * result["berm_clear"])])
	lines.append("Célérité %s / %s : %s pour %s de référence" % [_number(result["speed"]), _number(params.speed_points),
			duration_text(result["time"]), duration_text(params.reference_time)])
	lines.append(KEYS_DONE)
	return "\n".join(lines)


static func duration_text(seconds: float) -> String:
	var whole := floori(seconds)
	var minutes := whole / 60
	var rest := whole % 60
	if minutes == 0:
		return "%d s" % rest
	if rest == 0:
		return "%d min" % minutes
	return "%d min %02d s" % [minutes, rest]


func _title() -> String:
	return "Épreuve CACES R482 B1 : " + params.display_name.to_lower()


func _trench_line() -> String:
	return "Tranchée de %s m de long, %s m de large et %s m de profondeur, dans le tracé peint" % [
			_number(params.length), _number(params.width), _number(params.depth)]


func _commanded() -> bool:
	var c := excavator.controls
	return c.swing != 0.0 or c.boom != 0.0 or c.stick != 0.0 or c.bucket != 0.0 \
			or c.left_track != 0.0 or c.right_track != 0.0


func _score(failure: TrenchEvaluation.Failure) -> void:
	for i in SETTLE_CALLS:
		if excavator.terrain.relax(SETTLE_VISITS) == 0:
			break
	result = evaluation.score(elapsed, failure)
	state = State.DONE


func _paint_outline() -> void:
	if _markings != null:
		remove_child(_markings)
		_markings.queue_free()
	_markings = Node3D.new()
	_markings.name = "Markings"
	add_child(_markings)
	var area := params.outline()
	var corners: Array[Vector2] = [area.position, Vector2(area.end.x, area.position.y), area.end,
			Vector2(area.position.x, area.end.y)]
	for k in 4:
		_markings.add_child(_paint_line(corners[k], corners[(k + 1) % 4]))
	var mesh := BoxMesh.new()
	mesh.size = STAKE_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = STAKE_COLOR
	mesh.material = material
	var stake := MeshInstance3D.new()
	stake.name = "Stake"
	stake.mesh = mesh
	var foot := Vector2(params.axis_x, params.far_end_z - STAKE_BEYOND)
	stake.position = Vector3(foot.x, excavator.terrain.height_at(foot.x, foot.y) + STAKE_SIZE.y * 0.5, foot.y)
	_markings.add_child(stake)


## Paint line on the ground between two points (x, z), projected on the ground only.
func _paint_line(from: Vector2, to: Vector2) -> Decal:
	var along := to - from
	var middle := (from + to) * 0.5
	var decal := Decal.new()
	decal.size = Vector3(PAINT_WIDTH, PAINT_DEPTH, along.length() + PAINT_WIDTH)
	decal.position = Vector3(middle.x, excavator.terrain.height_at(middle.x, middle.y), middle.y)
	decal.rotation.y = atan2(along.x, along.y)
	decal.texture_albedo = _paint_texture()
	decal.modulate = PAINT_COLOR
	decal.upper_fade = 0.0
	decal.lower_fade = 0.0
	decal.cull_mask = Terrain.MARKING_LAYER
	return decal


static func _paint_texture() -> ImageTexture:
	if _paint == null:
		var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_paint = ImageTexture.create_from_image(image)
	return _paint


## Number in French: decimal comma, no trailing zeros.
static func _number(value: float) -> String:
	var text := "%.2f" % value
	text = text.rstrip("0").rstrip(".")
	return text.replace(".", ",")
