class_name Hud
extends CanvasLayer
## Minimal operator overlay (French UI): status line with the engine speed, the travel
## speed, the bucket load, the truck load and the time of day, controls help, and a debug panel with joint angles,
## cylinder strokes and pressures, pumps, bucket tip position, tracks, machine attitude
## and lift, and the soil volume balance. An exercise under way shows its text in a panel
## at the top middle.

@export var excavator_path: NodePath
@export var truck_path: NodePath

var show_help := true
var show_debug := false
var camera_label := "Cabine"
var sound_label := ""
var hour_label := ""
## Text of the exercise under way, empty outside exercises.
var exercise_text := ""

var _excavator: Excavator
var _truck: DumpTruck
var _status: Label
var _help: Label
var _debug: Label
var _exercise_panel: PanelContainer
var _exercise: Label


func _ready() -> void:
	_excavator = get_node_or_null(excavator_path)
	_truck = get_node_or_null(truck_path) as DumpTruck
	var settings := LabelSettings.new()
	settings.font_size = 17
	settings.outline_size = 5
	settings.outline_color = Color(0, 0, 0, 0.85)
	_status = _label(settings, Vector2(16, 12))
	_help = _label(settings, Vector2(16, 44))
	_debug = _label(settings, Vector2(16, 44))
	_debug.anchor_left = 1.0
	_debug.anchor_right = 1.0
	_debug.offset_left = -430.0
	_help.text = _help_text()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.55)
	panel_style.set_content_margin_all(12.0)
	_exercise_panel = PanelContainer.new()
	_exercise_panel.add_theme_stylebox_override("panel", panel_style)
	_exercise_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exercise_panel.anchor_left = 0.5
	_exercise_panel.anchor_right = 0.5
	_exercise_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_exercise_panel.offset_top = 44.0
	add_child(_exercise_panel)
	_exercise = Label.new()
	_exercise.label_settings = settings
	_exercise.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exercise_panel.add_child(_exercise)


func _process(_delta: float) -> void:
	if _excavator == null or _excavator.params == null:
		return
	var controls := _excavator.controls
	var pad := controls.joypad_name()
	_status.text = "Disposition %s  |  Vue %s  |  %s  |  %s  |  %s%s  |  %s  |  %s  |  %s  |  F1 aide" % [
		ControlInput.pattern_name(controls.pattern), camera_label, _engine_text(), _travel_text(), _load_text(),
		_truck_text(), ("Manette : " + pad) if pad != "" else "Clavier, aucune manette", sound_label, "Heure " + hour_label]
	_help.visible = show_help
	_debug.visible = show_debug
	_exercise_panel.visible = exercise_text != ""
	_exercise.text = exercise_text
	if show_debug:
		_debug.text = _debug_text()


func _label(settings: LabelSettings, position: Vector2) -> Label:
	var label := Label.new()
	label.label_settings = settings
	label.position = position
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _help_text() -> String:
	var k := func(key: Key) -> String: return _key_name(key)
	var lines := PackedStringArray([
		"Manette : les deux sticks sont les deux manipulateurs.",
		"Chenilles : maintenir %s, LB ou RB, puis avant ou arrière de chaque stick pour la chenille de son côté"
				% k.call(KEY_SPACE),
		"Clavier, manipulateur gauche : %s %s %s %s" % [k.call(KEY_W), k.call(KEY_A), k.call(KEY_S), k.call(KEY_D)],
		"Clavier, manipulateur droit : %s %s %s %s ou flèches" % [k.call(KEY_I), k.call(KEY_J), k.call(KEY_K), k.call(KEY_L)],
		"",
		"Disposition ISO : gauche = orientation et balancier, droite = godet et flèche",
		"Disposition SAE : gauche = orientation et flèche, droite = godet et balancier",
		"",
		"F2 ou Y : changer de disposition",
		"%s : vue cabine, autour de la pelle ou libre, Select : vue cabine ou extérieure" % k.call(KEY_C),
		"Vue libre, clic droit maintenu : la souris oriente, %s %s %s %s déplacent, %s / %s montent / descendent"
				% [k.call(FreeCamera.FORWARD_KEY), k.call(FreeCamera.LEFT_KEY), k.call(FreeCamera.BACK_KEY),
				k.call(FreeCamera.RIGHT_KEY), k.call(FreeCamera.UP_KEY), k.call(FreeCamera.DOWN_KEY)],
		"Vue libre : Maj pour aller plus vite, molette pour régler la vitesse",
		"Clic : capturer la souris pour regarder, Échap : libérer",
		"Clic molette ou %s : recentrer le regard, croix : regarder à la manette" % k.call(KEY_V),
		"%s ou Start : remettre la machine en position de repos" % k.call(KEY_R),
		"%s ou X : translation lente ou rapide, %s : revenir au point de départ" % [k.call(KEY_T), k.call(KEY_BACKSPACE)],
		"F8 : remettre le terrain à neuf et vider le godet et le camion",
		"%s : le camion part vider sa benne et revient vide" % k.call(KEY_B),
		"%s : épreuve CACES, réaliser une tranchée (remet le terrain à neuf)" % k.call(KEY_P),
		"Entrée : terminer l'épreuve, Suppr : l'abandonner",
		"F9 / F10 : reculer / avancer l'heure de la journée",
		"F4 : changer de périphérique d'entrée",
		"F5 / F6 : baisser / monter le son, F7 : couper le son",
		"F11 : plein écran ou fenêtre",
		"F3 : panneau technique, F1 : masquer cette aide",
	])
	return "\n".join(lines)


func _debug_text() -> String:
	var ex := _excavator
	var p := ex.params
	var tip := ex.tip_point()
	var h := ex.hydraulics
	var lines := PackedStringArray([
		"Panneau technique",
		"Orientation %7.1f deg  %6.1f deg/s  couple %3.0f %%%s" % [wrapf(ex.swing_joint.angle_deg, -180.0, 180.0),
				ex.swing_joint.speed_deg_s, 100.0 * ex.swing_joint.torque_fraction, " calée" if ex.swing_joint.stalled else ""],
		"Flèche      %7.1f deg  %6.1f deg/s" % [ex.boom_joint.angle_deg, ex.boom_joint.speed_deg_s],
		"Balancier   %7.1f deg  %6.1f deg/s" % [ex.stick_joint.angle_deg, ex.stick_joint.speed_deg_s],
		"Godet       %7.1f deg  %6.1f deg/s" % [ex.bucket_joint.angle_deg, ex.bucket_joint.speed_deg_s],
		"",
		_cylinder_line("Vérin flèche   ", ex.boom_joint, p.boom_cyl_closed_length, p.boom_cyl_stroke),
		_cylinder_line("Vérin balancier", ex.stick_joint, p.stick_cyl_closed_length, p.stick_cyl_stroke),
		_cylinder_line("Vérin godet    ", ex.bucket_joint, p.bucket_cyl_closed_length, p.bucket_cyl_stroke),
		"Pompes %3.0f bar, %3.0f kW, débit %3.0f %%, puissance %3.0f %%" % [h.pump_pressure / 1.0e5, h.power / 1000.0,
				100.0 * h.flow_share, 100.0 * h.power_share],
		"",
		"Dents : portée %5.2f m, hauteur %5.2f m" % [tip.x, tip.y],
		"",
		"Chenilles : gauche %+.2f m/s, droite %+.2f m/s" % [ex.travel.left_speed, ex.travel.right_speed],
		"Tangage %+5.1f deg, dévers %+5.1f deg%s" % [ex.ground.pitch_deg(), ex.ground.roll_deg(), _lift_text()],
		"Position x %.1f m, z %.1f m, altitude %.2f m" % [ex.ground.position.x, ex.ground.position.z, ex.ground.position.y],
		"Commandes : O %+.2f  F %+.2f  B %+.2f  G %+.2f" % [
			ex.controls.swing, ex.controls.boom, ex.controls.stick, ex.controls.bucket],
		"",
	])
	lines.append_array(_soil_lines())
	lines.append_array([
		"%d img/s" % Engine.get_frames_per_second(),
	])
	return "\n".join(lines)


## Bucket volumes in loose m3. The balance adds the terrain change and the bucket load, both
## counted as ground in place: it stays at zero while soil is only moved.
func _soil_lines() -> PackedStringArray:
	var ex := _excavator
	var soil := ex.bucket_soil
	var lines := PackedStringArray([
		"Godet %.2f / %.2f m³, pris %.2f, versé %.2f, poussé %.1f" % [
			soil.fill, soil.max_fill(), soil.removed, soil.deposited, soil.pushed],
	])
	var terrain := ex.terrain
	if terrain != null:
		var change := terrain.bank_volume() - terrain.volume_reference
		var balance := change + soil.bank_fill()
		if _truck != null:
			var body := _truck.body_load
			balance += body.bank_volume() + _hauled_bank_volume(body)
			lines.append("Camion %.2f m³, %.1f t, passés par-dessus %.2f m³, évacués %.2f m³" % [body.loose_volume(),
					body.mass() / 1000.0, _sum(body.spilled), _sum(body.hauled)])
		lines.append("Terrain %+.2f m³ en place, bilan %+.4f m³ en place" % [change, balance])
	return lines


func _truck_text() -> String:
	if _truck == null:
		return ""
	var body := _truck.body_load
	return "  |  Camion %s / %s t" % [("%.1f" % (body.mass() / 1000.0)).replace(".", ","),
			("%.1f" % (_truck.params.payload() / 1000.0)).replace(".", ",")]


## Volume the truck took away, counted as ground in place (m3).
static func _hauled_bank_volume(body: TruckLoad) -> float:
	var total := 0.0
	for m in body.hauled.size():
		total += body.hauled[m] / (1.0 + body.materials[m].swell())
	return total


static func _sum(values: PackedFloat64Array) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total


func _cylinder_line(label: String, cylinder: HydraulicCylinder, closed: float, stroke: float) -> String:
	return "%s %4.0f %% course %4.0f bar%s" % [label, _stroke_percent(cylinder.length, closed, stroke),
			cylinder.pressure / 1.0e5, "  calé" if cylinder.stalled else ""]


func _lift_text() -> String:
	var ground := _excavator.ground
	if ground.tip_angle <= 0.0:
		return ""
	var sides := ["avant", "arrière", "côté droit", "côté gauche"]
	return ", %s soulevé de %.1f deg" % [sides[ground.tip_edge], ground.tip_deg()]


func _engine_text() -> String:
	return "Régime %d tr/min" % int(round(_excavator.hydraulics.engine_rpm / 10.0) * 10.0)


func _load_text() -> String:
	var soil := _excavator.bucket_soil
	var text := "Godet %s m³" % ("%.2f" % soil.fill).replace(".", ",")
	if soil.fill >= 0.01:
		text += " de " + soil.material_params(soil.load_material()).display_name
	return text


func _travel_text() -> String:
	var travel := _excavator.travel
	var speed := ("%.1f" % (_excavator.measured_speed * 3.6)).replace(".", ",")
	var text := "Translation %s km/h, %s" % [speed, "rapide" if travel.high_speed else "lente"]
	if _excavator.controls.travel_mode:
		text += ", chenilles aux manipulateurs"
	return text


static func _stroke_percent(length: float, closed: float, stroke: float) -> float:
	return 100.0 * (length - closed) / stroke


static func _key_name(physical: Key) -> String:
	var label := DisplayServer.keyboard_get_label_from_physical(physical)
	if label == KEY_NONE:
		label = physical
	return OS.get_keycode_string(label)
