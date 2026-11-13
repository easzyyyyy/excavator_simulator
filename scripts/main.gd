extends Node3D
## Scene controller: camera switching (cab, orbit around the machine, free camera),
## time of day, mouse capture, control pattern toggle,
## travel speed range, return to the start place, ground reset, HUD toggles, fullscreen,
## sound volume, the CACES trench exercise (start, finish, leave), and an automated
## screenshot mode for visual checks (run with `-- --shots=<absolute dir>`), which ends
## with a scripted dig, carry and dump, the front of the machine lifted on the back of its
## bucket, the truck loaded, and the trench exercise marked out.

const DEMO_STEP := 1.0 / 120.0

enum View { CAB, ORBIT, FREE }

@onready var excavator: Excavator = $Excavator
@onready var cab_camera: CabCamera = $Excavator/Undercarriage/Turret/Head
@onready var orbit_camera: OrbitCamera = $OrbitCamera
@onready var free_camera: FreeCamera = $FreeCamera
@onready var lighting: SiteLighting = $Lighting
@onready var truck: DumpTruck = $DumpTruck
@onready var hud: Hud = $Hud
@onready var trench: TrenchExercise = $TrenchExercise

var sound := SoundSettings.new()
var camera_view := View.CAB


func _enter_tree() -> void:
	# Runs before the machine enters the tree and starts its engine sound.
	sound.load_saved()


func _ready() -> void:
	hud.sound_label = sound.label()
	hud.hour_label = lighting.label()
	_use_cab_view(true)
	var shots_dir := _user_arg("--shots")
	if shots_dir != "":
		hud.show_help = false
		_take_screenshots.call_deferred(shots_dir)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# The free camera captures the mouse only while its button is held.
		if camera_view != View.FREE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F1:
				hud.show_help = not hud.show_help
			KEY_F2:
				excavator.controls.toggle_pattern()
			KEY_F3:
				hud.show_debug = not hud.show_debug
			KEY_F4:
				excavator.controls.cycle_joypad()
			KEY_F5:
				sound.change_volume(-1)
				_sound_changed()
			KEY_F6:
				sound.change_volume(1)
				_sound_changed()
			KEY_F7:
				sound.toggle_mute()
				_sound_changed()
			KEY_F8:
				trench.stop()
				_reset_ground()
			KEY_F9:
				_change_hour(-1)
			KEY_F10:
				_change_hour(1)
			KEY_F11:
				_toggle_fullscreen()
			KEY_C:
				_cycle_view()
			KEY_V:
				cab_camera.recenter()
			KEY_R:
				excavator.reset_pose()
			KEY_T:
				excavator.travel.high_speed = not excavator.travel.high_speed
			KEY_BACKSPACE:
				excavator.return_to_start()
			KEY_B:
				truck.empty()
			KEY_P:
				_start_trench()
			KEY_ENTER, KEY_KP_ENTER:
				if trench.state == TrenchExercise.State.RUNNING:
					trench.finish()
				elif trench.state == TrenchExercise.State.DONE:
					trench.stop()
			KEY_DELETE:
				trench.stop()
	elif event is InputEventJoypadButton and event.pressed and event.device == excavator.controls.joypad_id:
		match event.button_index:
			JOY_BUTTON_BACK:
				_use_cab_view(camera_view != View.CAB)
			JOY_BUTTON_Y:
				excavator.controls.toggle_pattern()
			JOY_BUTTON_START:
				excavator.reset_pose()
			JOY_BUTTON_X:
				excavator.travel.high_speed = not excavator.travel.high_speed


func _process(_delta: float) -> void:
	cab_camera.joypad_id = excavator.controls.joypad_id
	excavator.controls.keyboard_enabled = not free_camera.piloting
	hud.exercise_text = trench.status_text()


func _reset_ground() -> void:
	if excavator.terrain != null:
		excavator.terrain.rebuild()
	excavator.bucket_soil.clear()
	truck.body_load.clear()


## Fresh ground, the machine at the start of the trench, seen from the cab.
func _start_trench() -> void:
	_reset_ground()
	trench.start()
	_use_cab_view(true)
	hud.show_help = false


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _change_hour(steps: int) -> void:
	lighting.change_hour(steps)
	hud.hour_label = lighting.label()


func _sound_changed() -> void:
	sound.save()
	hud.sound_label = sound.label()


func _use_cab_view(enabled: bool) -> void:
	_set_view(View.CAB if enabled else View.ORBIT)


func _cycle_view() -> void:
	_set_view(((camera_view + 1) % View.size()) as View)


## The free camera starts from the view it replaces.
func _set_view(p_view: View) -> void:
	var previous := get_viewport().get_camera_3d()
	camera_view = p_view
	match camera_view:
		View.CAB:
			cab_camera.camera.make_current()
			hud.camera_label = "cabine"
		View.ORBIT:
			orbit_camera.make_current()
			hud.camera_label = "extérieure"
		View.FREE:
			if previous != null and previous != free_camera:
				free_camera.copy_view(previous)
			free_camera.make_current()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			hud.camera_label = "libre"


func _take_screenshots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var views := [
		{"name": "cab_rest", "cab": true, "pose": [0.0, 15.0, -110.0, -90.0], "look": [-20.0, -18.0]},
		{"name": "cab_digging", "cab": true, "pose": [0.0, -8.0, -70.0, -40.0], "look": [-30.0, -30.0]},
		{"name": "cab_swing_right", "cab": true, "pose": [60.0, 25.0, -80.0, -100.0], "look": [-25.0, -8.0]},
		{"name": "cab_look_left", "cab": true, "pose": [0.0, 15.0, -110.0, -90.0], "look": [70.0, -10.0]},
		# Place: ground x, z and heading in degrees (90 faces -X). Side views stand clear of
		# the ramp and the truck.
		{"name": "ext_side_rest", "cab": false, "pose": [0.0, 15.0, -110.0, -90.0], "place": [0.0, 12.0, 0.0],
				"orbit": [-90.0, -8.0, 20.0]},
		{"name": "ext_side_reach", "cab": false, "pose": [0.0, 0.0, -28.0, 0.0], "place": [0.0, 12.0, 0.0],
				"orbit": [-90.0, -5.0, 22.0]},
		{"name": "ext_side_deep", "cab": false, "pose": [0.0, -50.0, -40.0, -60.0], "place": [0.0, 12.0, 0.0],
				"orbit": [-90.0, -2.0, 22.0]},
		{"name": "ext_linkage_curl", "cab": false, "pose": [0.0, 35.0, -60.0, -140.0], "orbit": [-70.0, -5.0, 11.0]},
		{"name": "ext_linkage_dump", "cab": false, "pose": [0.0, 35.0, -60.0, 35.0], "orbit": [-70.0, -5.0, 11.0]},
		{"name": "ext_three_quarter", "cab": false, "pose": [30.0, 20.0, -95.0, -70.0], "orbit": [-40.0, -22.0, 20.0]},
		{"name": "ext_tracks", "cab": false, "pose": [0.0, 15.0, -110.0, -90.0], "orbit": [-60.0, -12.0, 8.0]},
		# Site places: the ramp onto the bench, the bench crest, the trench and its spoil, the
		# sand stockpile, the truckload piles to level.
		{"name": "ext_ramp_climb", "cab": false, "pose": [0.0, 15.0, -110.0, -90.0], "place": [-69.0, 32.0, 0.0],
				"orbit": [-90.0, -6.0, 24.0]},
		{"name": "ext_bench_crest", "cab": false, "pose": [0.0, 15.0, -110.0, -90.0], "place": [-50.6, -20.0, -90.0],
				"orbit": [180.0, -4.0, 22.0]},
		{"name": "cab_bench_edge", "cab": true, "pose": [0.0, 15.0, -110.0, -90.0], "place": [-51.0, -20.0, -90.0],
				"look": [0.0, -25.0]},
		{"name": "cab_trench", "cab": true, "pose": [0.0, 15.0, -110.0, -90.0], "look": [0.0, -20.0]},
		{"name": "ext_trench_spoil", "cab": false, "pose": [0.0, 15.0, -110.0, -90.0], "orbit": [-150.0, -30.0, 30.0]},
		{"name": "ext_stockpile", "cab": false, "pose": [0.0, 15.0, -110.0, -90.0], "place": [30.0, -18.0, -45.0],
				"orbit": [-20.0, -18.0, 30.0]},
		{"name": "ext_level_area", "cab": false, "pose": [0.0, 15.0, -110.0, -90.0], "place": [-8.0, 44.0, 90.0],
				"orbit": [120.0, -25.0, 30.0]},
		{"name": "free_site_overview", "free": [40.0, 55.0, 70.0, 30.0, -32.0], "pose": [0.0, 15.0, -110.0, -90.0]},
	]
	for view in views:
		# A pose set straight into the ground digs it: start every view from fresh ground.
		_reset_ground()
		var place: Array = view.get("place", [0.0, 0.0, 0.0])
		excavator.place(Vector2(place[0], place[1]), deg_to_rad(place[2]))
		var pose: Array = view["pose"]
		excavator.set_pose(pose[0], pose[1], pose[2], pose[3])
		await _shoot(dir, view)

	# Digging views on the platform, facing east: three passes dumped to the right rear,
	# then a fourth load shown carried and half poured.
	_reset_ground()
	excavator.place(Vector2(0.0, 12.0), deg_to_rad(-90.0))
	for pass_index in 3:
		_demo_dig(pass_index)
		_demo_dump()
	await _shoot(dir, {"name": "ext_trench_and_pile", "cab": false, "orbit": [-150.0, -35.0, 24.0]})
	await _shoot(dir, {"name": "cab_dug_trench", "cab": true, "look": [0.0, -35.0]})
	_demo_dig(3)
	await _shoot(dir, {"name": "ext_bucket_load", "cab": false, "orbit": [-55.0, -12.0, 11.0]})
	await _shoot(dir, {"name": "cab_bucket_load", "cab": true, "look": [-5.0, -12.0]})
	_demo_swing(0.0, 120.0)
	_demo_bucket(-30.0, 1.5)
	await _shoot(dir, {"name": "ext_dump_pour", "cab": false, "orbit": [100.0, -18.0, 16.0]})
	_demo_bucket(excavator.params.bucket_max_deg, 1.5)
	_demo_hold(2.0)
	await _shoot(dir, {"name": "ext_spoil_pile", "cab": false, "orbit": [120.0, -30.0, 14.0]})

	# Boom lowered on the back of the bucket through the hydraulics, as in play.
	_reset_ground()
	excavator.place(Vector2(0.0, 12.0), deg_to_rad(-90.0))
	var lift_pose: Vector3 = ArmGeometry.pose_for_tip(excavator.params, Vector2(6.5, 0.54), -165.0)
	excavator.set_pose(0.0, lift_pose.x, lift_pose.y, lift_pose.z)
	_demo_levers([KEY_I], 1.2)
	_demo_levers([], 1.0)
	await _shoot(dir, {"name": "ext_front_lift", "cab": false, "orbit": [-90.0, -6.0, 18.0]})
	await _shoot(dir, {"name": "cab_front_lift", "cab": true, "look": [0.0, -25.0]})

	# Loading the truck from the start place: five full buckets turned over the body.
	_reset_ground()
	excavator.place(Vector2.ZERO, 0.0)
	var profile := excavator.params.bucket_profile
	var level := 180.0 + rad_to_deg(atan2(profile[0].y - profile[profile.size() - 1].y,
			profile[profile.size() - 1].x - profile[0].x))
	var carry: Vector3 = ArmGeometry.pose_for_tip(excavator.params, Vector2(6.5, 3.4), level)
	for load_index in 5:
		excavator.set_pose(90.0, carry.x, carry.y, carry.z)
		excavator.bucket_soil.fill = excavator.bucket_soil.max_fill()
		_demo_bucket(excavator.params.bucket_max_deg, 2.0)
		while truck.body_load.relax(4000, truck._overflow) > 0:
			pass
	excavator.set_pose(90.0, carry.x, carry.y, carry.z)
	await _shoot(dir, {"name": "ext_truck_loaded", "cab": false, "orbit": [20.0, -30.0, 16.0]})
	await _shoot(dir, {"name": "cab_truck_loaded", "cab": true, "look": [-5.0, -22.0]})

	# The trench exercise marked out, with its briefing.
	_start_trench()
	await _shoot(dir, {"name": "cab_trench_exercise", "cab": true, "look": [0.0, -22.0]})
	await _shoot(dir, {"name": "ext_trench_exercise", "cab": false, "orbit": [-140.0, -35.0, 16.0]})
	trench.stop()
	get_tree().quit()


func _shoot(dir: String, view: Dictionary) -> void:
	if view.has("free"):
		# Free camera: position x, y, z, then yaw and pitch.
		var free: Array = view["free"]
		_set_view(View.FREE)
		free_camera.global_position = Vector3(free[0], free[1], free[2])
		free_camera.yaw_deg = free[3]
		free_camera.pitch_deg = 0.0
		free_camera.turn(0.0, free[4])
	elif view["cab"]:
		_use_cab_view(true)
		cab_camera.look_at_angles(view["look"][0], view["look"][1])
	else:
		_use_cab_view(false)
		var orbit: Array = view["orbit"]
		orbit_camera.set_view(orbit[0], orbit[1], orbit[2])
	for i in 8:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	image.save_png(dir.path_join(view["name"] + ".png"))
	print("screenshot ", view["name"], " (bucket %.2f m3)" % excavator.bucket_soil.fill)


## One pass along the trench in front of the machine, each deeper, ending with the
## bucket level above the ground.
func _demo_dig(pass_index: int) -> void:
	var depth := 0.5 * (pass_index + 1)
	_demo_tip(Vector2(7.6, 0.3 - depth + 0.5), -100.0, 0.0)
	_demo_tip(Vector2(7.2, -depth), -105.0, 0.8)
	_demo_tip(Vector2(5.2, -depth + 0.15), -125.0, 2.2)
	_demo_tip(Vector2(4.8, -depth + 0.8), -170.0, 1.2)
	_demo_tip(Vector2(5.0, 1.8), -174.9, 1.2)


func _demo_dump() -> void:
	_demo_swing(0.0, 120.0)
	_demo_bucket(excavator.params.bucket_max_deg, 3.0)
	_demo_hold(1.0)
	_demo_bucket(-114.0, 1.0)
	_demo_swing(120.0, 0.0)


## Moves the tooth tip in a straight line while turning the bucket to an absolute
## pin-to-tip angle; zero duration jumps there.
func _demo_tip(tip: Vector2, bucket_absolute_deg: float, duration: float) -> void:
	var from_tip := excavator.tip_point()
	var from_angle := excavator.boom_joint.angle_deg + excavator.stick_joint.angle_deg + excavator.bucket_joint.angle_deg
	var turn := wrapf(bucket_absolute_deg - from_angle, -180.0, 180.0)
	if duration <= 0.0:
		var target: Vector3 = ArmGeometry.pose_for_tip(excavator.params, tip, bucket_absolute_deg)
		excavator.set_pose(excavator.swing_joint.angle_deg, target.x, target.y, target.z)
		return
	var steps := int(round(duration / DEMO_STEP))
	for i in steps:
		var t := float(i + 1) / steps
		var angles: Variant = ArmGeometry.pose_for_tip(excavator.params, from_tip.lerp(tip, t), from_angle + turn * t)
		if angles != null:
			_demo_pose(excavator.swing_joint.angle_deg, angles)


func _demo_swing(from_deg: float, to_deg: float) -> void:
	var angles := Vector3(excavator.boom_joint.angle_deg, excavator.stick_joint.angle_deg, excavator.bucket_joint.angle_deg)
	var steps := int(round(absf(to_deg - from_deg) / 60.0 / DEMO_STEP))
	for i in steps:
		_demo_pose(lerpf(from_deg, to_deg, float(i + 1) / steps), angles)


func _demo_bucket(bucket_deg: float, duration: float) -> void:
	var start := excavator.bucket_joint.angle_deg
	var steps := int(round(duration / DEMO_STEP))
	for i in steps:
		var angles := Vector3(excavator.boom_joint.angle_deg, excavator.stick_joint.angle_deg,
				lerpf(start, bucket_deg, float(i + 1) / steps))
		_demo_pose(excavator.swing_joint.angle_deg, angles)


func _demo_hold(duration: float) -> void:
	var angles := Vector3(excavator.boom_joint.angle_deg, excavator.stick_joint.angle_deg, excavator.bucket_joint.angle_deg)
	for i in int(round(duration / DEMO_STEP)):
		_demo_pose(excavator.swing_joint.angle_deg, angles)


## Holds keys down for a while, stepping the machine as the physics loop does.
func _demo_levers(keys: Array, duration: float) -> void:
	for pressed in [true, false]:
		for key in keys:
			var event := InputEventKey.new()
			event.physical_keycode = key
			event.keycode = key
			event.pressed = pressed
			Input.parse_input_event(event)
		Input.flush_buffered_events()
		if not pressed:
			return
		for i in int(round(duration / DEMO_STEP)):
			excavator._physics_process(DEMO_STEP)
			excavator.terrain.relax(Terrain.RELAX_VISITS_PER_TICK)


func _demo_pose(swing_deg: float, angles: Vector3) -> void:
	excavator.pose_and_dig(swing_deg, angles.x, angles.y, angles.z, DEMO_STEP)
	excavator.terrain.relax(Terrain.RELAX_VISITS_PER_TICK)


static func _user_arg(key: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(key + "="):
			return arg.substr(key.length() + 1)
	return ""
