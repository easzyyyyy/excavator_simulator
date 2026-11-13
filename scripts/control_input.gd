@tool
class_name ControlInput
extends RefCounted
## Reads the operator joysticks (gamepad sticks, keyboard fallback) and maps them
## to the four arm functions according to the selected control pattern.
##
## Travel mode, held on a shoulder button or the space bar, hands the sticks to the
## tracks: the forward axis of each stick drives the track on its side, and the arm
## functions receive no command.
##
## Stick vectors use x = right positive and y = forward positive.

enum Pattern { ISO, SAE }

var pattern := Pattern.ISO
var deadzone := 0.10
## Exponent applied after the deadzone: above 1 gives finer control near neutral.
var response_exponent := 1.5

## Shaped stick positions after deadzone and response curve.
var left_stick := Vector2.ZERO
var right_stick := Vector2.ZERO

## Function commands in [-1, 1].
var swing := 0.0 ## +1 swings right.
var boom := 0.0 ## +1 raises.
var stick := 0.0 ## +1 moves out.
var bucket := 0.0 ## +1 dumps.

var travel_mode := false
var left_track := 0.0 ## +1 drives the left track forward.
var right_track := 0.0 ## +1 drives the right track forward.

var joypad_id := -1
## False while the keyboard flies the free camera: the machine then only reads the gamepad.
var keyboard_enabled := true
## Device picked by the operator with cycle_joypad(); -2 means automatic.
var _chosen_joypad := -2


## Maps stick positions to function commands. Only boom and stick change hands
## between patterns; swing stays on the left lateral axis, bucket on the right.
static func map_pattern(p_pattern: Pattern, left: Vector2, right: Vector2) -> Dictionary:
	var commands := {
		"swing": left.x,
		"bucket": right.x,
	}
	if p_pattern == Pattern.ISO:
		commands["stick"] = left.y
		commands["boom"] = -right.y
	else:
		commands["boom"] = -left.y
		commands["stick"] = right.y
	return commands


## Maps stick positions to track commands in travel mode.
static func map_travel(left: Vector2, right: Vector2) -> Dictionary:
	return {"left_track": left.y, "right_track": right.y}


static func pattern_name(p_pattern: Pattern) -> String:
	return "ISO" if p_pattern == Pattern.ISO else "SAE"


func toggle_pattern() -> void:
	pattern = Pattern.SAE if pattern == Pattern.ISO else Pattern.ISO


func poll() -> void:
	_refresh_joypad()
	var left := Vector2.ZERO
	var right := Vector2.ZERO
	if keyboard_enabled:
		left = _keyboard_stick(KEY_A, KEY_D, KEY_W, KEY_S)
		right = _keyboard_stick(KEY_J, KEY_L, KEY_I, KEY_K)
		right += _keyboard_stick(KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN)
	if joypad_id >= 0:
		left += Vector2(
			Input.get_joy_axis(joypad_id, JOY_AXIS_LEFT_X),
			-Input.get_joy_axis(joypad_id, JOY_AXIS_LEFT_Y))
		right += Vector2(
			Input.get_joy_axis(joypad_id, JOY_AXIS_RIGHT_X),
			-Input.get_joy_axis(joypad_id, JOY_AXIS_RIGHT_Y))
	left_stick = Vector2(_shape(left.x), _shape(left.y))
	right_stick = Vector2(_shape(right.x), _shape(right.y))

	travel_mode = keyboard_enabled and Input.is_physical_key_pressed(KEY_SPACE)
	if joypad_id >= 0:
		var shoulder := Input.is_joy_button_pressed(joypad_id, JOY_BUTTON_LEFT_SHOULDER)
		shoulder = shoulder or Input.is_joy_button_pressed(joypad_id, JOY_BUTTON_RIGHT_SHOULDER)
		travel_mode = travel_mode or shoulder

	var commands := map_travel(left_stick, right_stick) if travel_mode else map_pattern(pattern, left_stick, right_stick)
	swing = commands.get("swing", 0.0)
	boom = commands.get("boom", 0.0)
	stick = commands.get("stick", 0.0)
	bucket = commands.get("bucket", 0.0)
	left_track = commands.get("left_track", 0.0)
	right_track = commands.get("right_track", 0.0)


func joypad_name() -> String:
	return Input.get_joy_name(joypad_id) if joypad_id >= 0 else ""


## Cycles through connected devices, then keyboard only.
func cycle_joypad() -> void:
	var options: Array[int] = [-1]
	options.append_array(Input.get_connected_joypads())
	var index := options.find(joypad_id)
	_chosen_joypad = options[(index + 1) % options.size()]
	_refresh_joypad()


## Automatic choice uses the first device with a known gamepad mapping, so
## keyboards or mice exposing a HID joystick interface are ignored.
func _refresh_joypad() -> void:
	var pads := Input.get_connected_joypads()
	if _chosen_joypad == -1 or pads.has(_chosen_joypad):
		joypad_id = _chosen_joypad
		return
	joypad_id = -1
	for pad in pads:
		if Input.is_joy_known(pad):
			joypad_id = pad
			return


func _shape(value: float) -> float:
	value = clampf(value, -1.0, 1.0)
	var magnitude := absf(value)
	if magnitude <= deadzone:
		return 0.0
	var scaled := (magnitude - deadzone) / (1.0 - deadzone)
	return signf(value) * pow(scaled, response_exponent)


static func _keyboard_stick(left_key: Key, right_key: Key, forward_key: Key, back_key: Key) -> Vector2:
	var result := Vector2.ZERO
	if Input.is_physical_key_pressed(right_key):
		result.x += 1.0
	if Input.is_physical_key_pressed(left_key):
		result.x -= 1.0
	if Input.is_physical_key_pressed(forward_key):
		result.y += 1.0
	if Input.is_physical_key_pressed(back_key):
		result.y -= 1.0
	return result
