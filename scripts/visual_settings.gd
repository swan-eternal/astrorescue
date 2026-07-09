extends Node
##
## VisualSettings: persistent visual toggles for the game.
## Autoloaded so it's accessible from any scene as `VisualSettings`.
## The visual tab UI calls into this module on every toggle change.
##
## Storage: ConfigFile at `user://visual_settings.cfg` (separate file
## from AudioSettings's `user://settings.cfg` so the two autoloads
## don't need to coordinate read-modify-write cycles — each is
## self-contained). Same OS-managed user dir as the audio file.
##
## Lifecycle:
##   _ready()        load user://visual_settings.cfg if it exists;
##                   otherwise apply defaults.
##   set_*()         mutate one setting's state, save immediately.
##
## Adding a new visual toggle = add a field below + a `get_*` / `set_*`
## accessor pair + a `set_value` / `has_section_key` line in the
## load/save helpers. Settings stay organized in one section per
## concern (audio / visual / etc.) for forward-compat.
##

const SETTINGS_PATH := "user://visual_settings.cfg"
const SECTION := "visual"

# Default for `show_soi` — whether to render the SOI (Sphere of
# Influence) visualization around planets during gameplay. Off by
# default since it's primarily a planning aid; the user toggles it on
# via Settings → Visual when they want it.
const DEFAULT_SHOW_SOI: bool = false


# Internal state. Adding a new visual toggle = add a field here + a
# `get_*` / `set_*` accessor pair below.
var _show_soi: bool = DEFAULT_SHOW_SOI


## Load persisted settings (if any). Missing file = defaults.
## Corrupt file = log a warning and fall back to defaults (don't
## crash — settings should never block gameplay).
func _ready() -> void:
	_load_from_disk()


## Public API: get the current `show_soi` value.
func is_show_soi() -> bool:
	return _show_soi


## Public API: set `show_soi`, persist immediately. The SOI indicator
## polls `is_show_soi()` each frame, so it picks up the change on the
## next draw — no explicit signal wiring needed.
func set_show_soi(value: bool) -> void:
	_show_soi = value
	_save_to_disk()


# --- internals ---


func _load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		# First run (no file yet) is the common case; not an error.
		if err != ERR_FILE_NOT_FOUND:
			push_warning("VisualSettings: could not load %s (err %d); using defaults." % [SETTINGS_PATH, err])
		return
	if cfg.has_section_key(SECTION, "show_soi"):
		_show_soi = bool(cfg.get_value(SECTION, "show_soi", DEFAULT_SHOW_SOI))


func _save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "show_soi", _show_soi)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("VisualSettings: could not save %s (err %d)." % [SETTINGS_PATH, err])