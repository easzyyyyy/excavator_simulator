class_name OrbitCamera
extends Camera3D
## External camera orbiting around the machine, for observing the arm.

@export var target_path: NodePath
@export var target_offset := Vector3(0, 2.0, 0)
@export var mouse_sensitivity := 0.25
@export var min_distance := 4.0
@export var max_distance := 60.0

var yaw_deg := -35.0
var pitch_deg := -18.0
var distance := 18.0

@onready var _target: Node3D = get_node_or_null(target_path)


func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw_deg -= event.relative.x * mouse_sensitivity
		pitch_deg = clampf(pitch_deg - event.relative.y * mouse_sensitivity, -85.0, 10.0)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(min_distance, distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance * 1.1)


func _process(_delta: float) -> void:
	set_view(yaw_deg, pitch_deg, distance)


func set_view(p_yaw_deg: float, p_pitch_deg: float, p_distance: float) -> void:
	yaw_deg = p_yaw_deg
	pitch_deg = p_pitch_deg
	distance = p_distance
	var focus := target_offset
	if _target:
		focus += _target.global_position
	var orbit := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0))
	global_position = focus + orbit * Vector3(0, 0, distance)
	look_at(focus, Vector3.UP)
