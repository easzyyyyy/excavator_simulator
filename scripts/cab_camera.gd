class_name CabCamera
extends Node3D
## Operator head in the cab. Free look is independent of the machine: the head
## is attached to the turret, and yaw and pitch are relative to it.
## Mouse look while the cursor is captured, D-pad look on a gamepad.

@export var mouse_sensitivity := 0.12
@export var pad_look_speed_deg := 90.0
@export var yaw_limit_deg := 160.0
@export var pitch_min_deg := -75.0
@export var pitch_max_deg := 60.0

@onready var camera: Camera3D = $Camera3D

## Gamepad used for D-pad look, -1 for none.
var joypad_id := -1
var yaw_deg := 0.0
var pitch_deg := -12.0


func _ready() -> void:
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if not camera.current:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw_deg -= event.relative.x * mouse_sensitivity
		pitch_deg -= event.relative.y * mouse_sensitivity
		_apply()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		recenter()


func _process(delta: float) -> void:
	if not camera.current:
		return
	if joypad_id < 0:
		return
	var look := Vector2(
		float(Input.is_joy_button_pressed(joypad_id, JOY_BUTTON_DPAD_RIGHT))
				- float(Input.is_joy_button_pressed(joypad_id, JOY_BUTTON_DPAD_LEFT)),
		float(Input.is_joy_button_pressed(joypad_id, JOY_BUTTON_DPAD_UP))
				- float(Input.is_joy_button_pressed(joypad_id, JOY_BUTTON_DPAD_DOWN)))
	if look != Vector2.ZERO:
		yaw_deg -= look.x * pad_look_speed_deg * delta
		pitch_deg += look.y * pad_look_speed_deg * delta
		_apply()


func recenter() -> void:
	yaw_deg = 0.0
	pitch_deg = -12.0
	_apply()


func look_at_angles(p_yaw_deg: float, p_pitch_deg: float) -> void:
	yaw_deg = p_yaw_deg
	pitch_deg = p_pitch_deg
	_apply()


func _apply() -> void:
	yaw_deg = clampf(yaw_deg, -yaw_limit_deg, yaw_limit_deg)
	pitch_deg = clampf(pitch_deg, pitch_min_deg, pitch_max_deg)
	rotation = Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0)
