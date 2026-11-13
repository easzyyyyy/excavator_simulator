class_name FreeCamera
extends Camera3D
## Camera the operator places anywhere on the site. While the right mouse button is held,
## the mouse turns it and the movement keys fly it: forward, back and sideways along the
## ground, up and down on two more keys, faster with Shift, the wheel sets the speed.
## Released, it stays where it is and the keyboard goes back to the machine.
##
## Keys are physical, so they follow the keyboard layout like the machine keys. The camera
## never goes below the ground nor far outside the site.

const FORWARD_KEY := KEY_W
const BACK_KEY := KEY_S
const LEFT_KEY := KEY_A
const RIGHT_KEY := KEY_D
const UP_KEY := KEY_E
const DOWN_KEY := KEY_Q

@export var terrain_path: NodePath
@export var mouse_sensitivity := 0.15
## Flying speed (m/s), changed with the wheel between the two limits.
@export var speed := 6.0
@export var min_speed := 1.0
@export var max_speed := 40.0
@export var fast_factor := 4.0
## Lowest height above the ground (m).
@export var ground_clearance := 0.4
## How far beyond the diggable grid the camera may go (m).
@export var outside_margin := 50.0

var yaw_deg := 0.0
var pitch_deg := -15.0
## True while the right mouse button is held on this camera.
var piloting := false

var _terrain: Terrain
var _mouse_mode_before := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	_terrain = get_node_or_null(terrain_path) as Terrain
	_apply_rotation()


func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		set_piloting(event.pressed)
	elif not piloting:
		return
	elif event is InputEventMouseMotion:
		turn(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed = minf(speed * 1.25, max_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed = maxf(speed / 1.25, min_speed)


func _process(delta: float) -> void:
	if not current:
		set_piloting(false)
		return
	if not piloting:
		return
	var move := Vector3.ZERO
	move.x = _axis(RIGHT_KEY, LEFT_KEY)
	move.z = _axis(BACK_KEY, FORWARD_KEY)
	move.y = _axis(UP_KEY, DOWN_KEY)
	if move == Vector3.ZERO:
		return
	var rate := speed * (fast_factor if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	var along_ground := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Vector3(move.x, 0.0, move.z)
	fly(Vector3(along_ground.x, move.y, along_ground.z).normalized() * rate * delta)


func set_piloting(value: bool) -> void:
	if value == piloting:
		return
	piloting = value
	if piloting:
		_mouse_mode_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = _mouse_mode_before


func turn(yaw_change_deg: float, pitch_change_deg: float) -> void:
	yaw_deg = wrapf(yaw_deg + yaw_change_deg, -180.0, 180.0)
	pitch_deg = clampf(pitch_deg + pitch_change_deg, -89.0, 89.0)
	_apply_rotation()


## Moves by a world offset, kept above the ground and near the site.
func fly(offset: Vector3) -> void:
	var target := global_position + offset
	if _terrain != null:
		var half := _terrain.size() * 0.5 + outside_margin
		var centre := _terrain.global_position
		target.x = clampf(target.x, centre.x - half, centre.x + half)
		target.z = clampf(target.z, centre.z - half, centre.z + half)
		target.y = maxf(target.y, _terrain.height_at(target.x, target.z) + ground_clearance)
	global_position = target


## Takes the position and view direction of another camera.
func copy_view(other: Camera3D) -> void:
	var forward := -other.global_transform.basis.z
	yaw_deg = rad_to_deg(atan2(-forward.x, -forward.z))
	pitch_deg = clampf(rad_to_deg(asin(clampf(forward.y, -1.0, 1.0))), -89.0, 89.0)
	global_position = other.global_position
	_apply_rotation()
	fly(Vector3.ZERO)


func _apply_rotation() -> void:
	global_basis = Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0))


static func _axis(positive: Key, negative: Key) -> float:
	return float(Input.is_physical_key_pressed(positive)) - float(Input.is_physical_key_pressed(negative))
