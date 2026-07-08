extends Node
##
## AudioSettings: persistent volume + mute state for the three audio
## buses (Master, Music, SFX). Autoloaded so it's accessible from any
## scene as `AudioSettings`. The audio tab UI calls into this module
## on every slider release / mute toggle.
##
## Storage: ConfigFile at user://settings.cfg (under
## AppData/Local/<game>/ on Windows, ~/.local/share/<game>/ on Linux,
## etc. — engine-managed). One section [audio] with six keys:
##   master_db, master_muted, music_db, music_muted, sfx_db, sfx_muted
##
## Lifecycle:
##   _ready()        load user://settings.cfg if it exists; otherwise
##                   apply defaults (all 0 dB, all unmuted). Then push
##                   to AudioServer.set_bus_volume_db / .set_bus_mute.
##   set_*()         mutate one channel's state, push to AudioServer,
##                   save user://settings.cfg immediately.
##
## Slider 0..100 <-> dB -40..0 mapping is a property of the UI layer
## (audio_tab.gd). This module stores dB directly so the persisted
## format is in meaningful units, not arbitrary slider positions.
##

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "audio"

# Bus name <-> settings key. Master is the global "Overall" channel.
# Music routes the music player; SFX routes thruster + oneshots.
const BUSES := {
	"master": "Master",
	"music": "Music",
	"sfx": "SFX",
}

# dB range the UI slider maps onto. Anything below MIN_DB is effectively
# silent for game audio; MAX_DB of 0 means "no attenuation" (Unity's
# default). UI caps at MAX_DB so users can't accidentally amplify past
# unity gain via the slider (an explicit "boost" toggle would be a
# separate feature).
const MIN_DB := -40.0
const MAX_DB := 0.0
const DEFAULT_DB := 0.0

# Internal state: dict of channel name -> { db: float, muted: bool }.
var _state: Dictionary = {
	"master": {"db": DEFAULT_DB, "muted": false},
	"music":  {"db": DEFAULT_DB, "muted": false},
	"sfx":    {"db": DEFAULT_DB, "muted": false},
}


## Load persisted settings (if any) and apply to AudioServer.
## Falls back to defaults silently if the file is missing or corrupt
## (first run, OS reinstall, etc.) — never crash on settings IO.
func _ready() -> void:
	_load_from_disk()
	_apply_all()


## Public API: get the current dB value for a channel.
## `channel` is one of "master", "music", "sfx".
func get_db(channel: String) -> float:
	return _state[channel]["db"]


## Public API: get the current mute state for a channel.
func is_muted(channel: String) -> bool:
	return _state[channel]["muted"]


## Public API: set the dB for a channel, push to AudioServer, persist.
func set_db(channel: String, db: float) -> void:
	# Clamp to the slider's range so a stray value from the UI layer
	# can't push the bus into +dB or below -INF.
	db = clampf(db, MIN_DB, MAX_DB)
	_state[channel]["db"] = db
	_apply_channel(channel)
	_save_to_disk()


## Public API: set the mute state for a channel, push to AudioServer,
## persist. Note: muting overrides the dB value (bus_mute = true silences
## the bus regardless of volume_db) but doesn't reset it — unmuting
## restores the prior volume.
func set_muted(channel: String, muted: bool) -> void:
	_state[channel]["muted"] = muted
	_apply_channel(channel)
	_save_to_disk()


# --- internals ---


## Read user://settings.cfg into `_state`. Missing file = defaults.
## Corrupt file = log a warning and fall back to defaults (don't
## crash — settings should never block gameplay).
func _load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		# First run (no file yet) is the common case; not an error.
		if err != ERR_FILE_NOT_FOUND:
			push_warning("AudioSettings: could not load %s (err %d); using defaults." % [SETTINGS_PATH, err])
		return
	for channel in BUSES:
		if cfg.has_section_key(SECTION, channel + "_db"):
			_state[channel]["db"] = clampf(float(cfg.get_value(SECTION, channel + "_db", DEFAULT_DB)), MIN_DB, MAX_DB)
		if cfg.has_section_key(SECTION, channel + "_muted"):
			_state[channel]["muted"] = bool(cfg.get_value(SECTION, channel + "_muted", false))


## Write current `_state` to user://settings.cfg. Called after every
## UI change. ConfigFile.save() can fail if user:// is read-only or
## out of space — log and move on (don't crash gameplay on settings IO).
func _save_to_disk() -> void:
	var cfg := ConfigFile.new()
	for channel in BUSES:
		cfg.set_value(SECTION, channel + "_db", _state[channel]["db"])
		cfg.set_value(SECTION, channel + "_muted", _state[channel]["muted"])
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("AudioSettings: could not save %s (err %d)." % [SETTINGS_PATH, err])


## Push all channel states to AudioServer. Called once at startup.
func _apply_all() -> void:
	for channel in BUSES:
		_apply_channel(channel)


## Push one channel's state to AudioServer. Looks up the bus index by
## name (defensive: if the bus doesn't exist, skip — the .tres file
## might be misconfigured).
func _apply_channel(channel: String) -> void:
	var bus_name: String = BUSES[channel]
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		push_warning("AudioSettings: bus %s not found in AudioServer." % bus_name)
		return
	AudioServer.set_bus_volume_db(bus_idx, _state[channel]["db"])
	AudioServer.set_bus_mute(bus_idx, _state[channel]["muted"])