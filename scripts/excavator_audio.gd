class_name ExcavatorAudio
extends Node
## Cab sound layers driven by the machine state.
##
## The engine starts, then idles. Its revs come from the engine model, which rises with
## the levers and sags under pump load, and crossfade an idle and a high revs recording.
## The pump flow follows the total cylinder speed, each cylinder hisses while it moves,
## the relief valve whines while a lever holds a cylinder against its end stop or a load
## it cannot move, and the swing motor follows the turret speed.
##
## Every value here is sound mixing, none is machine behaviour.

const RELIEF_ATTACK_TIME := 0.05
const RELIEF_RELEASE_TIME := 0.15
const FLOW_PITCH_RANGE := Vector2(0.9, 1.1)
const SWING_PITCH_RANGE := Vector2(0.8, 1.05)
## Pitch added at full cylinder speed, on top of the per-cylinder base pitch.
const CYLINDER_PITCH_RISE := 0.12
const SILENT_GAIN := 0.0001

@export var excavator_path: NodePath = ^".."

@export_group("Streams")
@export var engine_start: AudioStream
@export var engine_idle: AudioStream
@export var engine_high: AudioStream
@export var hydraulic_flow: AudioStream
@export var hydraulic_cylinder: AudioStream
@export var hydraulic_relief: AudioStream
@export var swing_motor: AudioStream

@export_group("Engine")
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var engine_volume_db := 0.0
## Engine firing frequency of the high revs recording divided by the idle one.
@export var high_revs_ratio := 1.81
## Overlap between the end of the start recording and the idle loop.
@export var start_crossfade := 0.4

@export_group("Hydraulics")
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var flow_volume_db := -8.0
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var cylinder_volume_db := -6.0
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var relief_volume_db := -4.0
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var swing_volume_db := 0.0
## Base pitch of the boom, stick and bucket cylinders: bigger bores sound lower.
@export var cylinder_pitches := Vector3(0.85, 1.0, 1.12)

## 0 at idle, 1 at full revs.
var revs := 0.0

var _excavator: Excavator
var _start: AudioStreamPlayer
var _idle: AudioStreamPlayer
var _high: AudioStreamPlayer
var _flow: AudioStreamPlayer
var _relief: AudioStreamPlayer
var _swing: AudioStreamPlayer
## Boom, stick and bucket, in that order.
var _cylinders: Array[AudioStreamPlayer] = []
var _since_start := 0.0
var _relief_level := 0.0


func _ready() -> void:
	_excavator = get_node_or_null(excavator_path) as Excavator
	_start = _add_player("EngineStart", engine_start)
	_idle = _add_player("EngineIdle", engine_idle)
	_high = _add_player("EngineHigh", engine_high)
	_flow = _add_player("HydraulicFlow", hydraulic_flow)
	_relief = _add_player("HydraulicRelief", hydraulic_relief)
	_swing = _add_player("SwingMotor", swing_motor)
	for label in ["Boom", "Stick", "Bucket"]:
		_cylinders.append(_add_player(label + "Cylinder", hydraulic_cylinder))
	for player in [_idle, _high, _flow, _relief, _swing]:
		_set_gain(player, 0.0, 0.0)
		player.play()
	# The three cylinders share one loop: start them apart so they never sound as one.
	var cylinder_length := hydraulic_cylinder.get_length() if hydraulic_cylinder != null else 0.0
	for i in _cylinders.size():
		_set_gain(_cylinders[i], 0.0, 0.0)
		_cylinders[i].play(cylinder_length * i / _cylinders.size())
	_start.volume_db = engine_volume_db
	_start.play()


func _process(delta: float) -> void:
	if _excavator == null or _excavator.params == null:
		return
	_since_start += delta
	_update_engine(delta)
	_update_hydraulics(delta)


## Loops that must repeat seamlessly; the start recording plays once.
func looping_streams() -> Array[AudioStream]:
	return [engine_idle, engine_high, hydraulic_flow, hydraulic_cylinder, hydraulic_relief, swing_motor]


func _update_engine(_delta: float) -> void:
	var start_length := engine_start.get_length() if engine_start != null else 0.0
	var running := clampf((_since_start - start_length + start_crossfade) / start_crossfade, 0.0, 1.0)
	revs = _excavator.hydraulics.revs_fraction() * running

	# Both layers follow the same engine speed, expressed in idle units.
	var speed := lerpf(1.0, high_revs_ratio, revs)
	_idle.pitch_scale = speed
	_high.pitch_scale = speed / high_revs_ratio
	_set_gain(_idle, cos(revs * PI / 2.0) * running, engine_volume_db)
	_set_gain(_high, sin(revs * PI / 2.0) * running, engine_volume_db)


func _update_hydraulics(delta: float) -> void:
	var ex := _excavator
	var c := ex.controls
	var joints: Array[HydraulicCylinder] = ex.hydraulics.cylinders
	var commands: Array[float] = [c.boom, c.stick, c.bucket]
	var flow := 0.0
	var relief := absf(c.swing) if ex.swing_joint.stalled else 0.0
	for i in joints.size():
		var speed := minf(joints[i].speed_fraction(), 1.0)
		flow += speed
		_cylinders[i].pitch_scale = cylinder_pitches[i] + CYLINDER_PITCH_RISE * speed
		_set_gain(_cylinders[i], sqrt(speed), cylinder_volume_db)
		if joints[i].relieving(commands[i]):
			relief = maxf(relief, absf(commands[i]))

	flow = minf(flow, 1.0)
	_flow.pitch_scale = lerpf(FLOW_PITCH_RANGE.x, FLOW_PITCH_RANGE.y, flow)
	_set_gain(_flow, sqrt(flow), flow_volume_db)

	var time := RELIEF_ATTACK_TIME if relief > _relief_level else RELIEF_RELEASE_TIME
	_relief_level = move_toward(_relief_level, relief, delta / time)
	_set_gain(_relief, _relief_level, relief_volume_db)

	var swing := minf(ex.swing_joint.speed_fraction(), 1.0)
	_swing.pitch_scale = lerpf(SWING_PITCH_RANGE.x, SWING_PITCH_RANGE.y, swing)
	_set_gain(_swing, sqrt(swing), swing_volume_db)


func _add_player(player_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	add_child(player)
	return player


static func _set_gain(player: AudioStreamPlayer, gain: float, volume_db: float) -> void:
	player.volume_db = volume_db + linear_to_db(maxf(gain, SILENT_GAIN))
