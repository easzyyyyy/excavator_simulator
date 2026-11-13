class_name SoundSettings
extends RefCounted
## Operator sound volume on the master bus, saved between sessions.
##
## The volume is a loudness fraction set in 10 % steps: halving it sounds half as
## loud, which is -10 dB.

const PATH := "user://settings.cfg"
const SECTION := "sound"
const STEP := 0.1
const DEFAULT_VOLUME := 0.1

var volume := DEFAULT_VOLUME
var muted := false


func load_saved() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		volume = clampf(float(config.get_value(SECTION, "volume", DEFAULT_VOLUME)), 0.0, 1.0)
		muted = bool(config.get_value(SECTION, "muted", false))
	apply()


func save() -> void:
	var config := ConfigFile.new()
	config.load(PATH) # Keeps any other section already saved.
	config.set_value(SECTION, "volume", volume)
	config.set_value(SECTION, "muted", muted)
	config.save(PATH)


func change_volume(steps: int) -> void:
	volume = clampf(snappedf(volume + steps * STEP, STEP), 0.0, 1.0)
	muted = false
	apply()


func toggle_mute() -> void:
	muted = not muted
	apply()


func apply() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, is_silent())
	AudioServer.set_bus_volume_db(bus, loudness_to_db(volume))


func is_silent() -> bool:
	return muted or volume <= 0.0


func label() -> String:
	return "Son coupé" if is_silent() else "Son %d %%" % roundi(volume * 100.0)


static func loudness_to_db(fraction: float) -> float:
	return 10.0 * log(fraction) / log(2.0) if fraction > 0.0 else -80.0
