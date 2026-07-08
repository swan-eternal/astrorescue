extends Node
##
## SaveState: persistent game progress (autoload singleton).
## Stores the highest level completed. Saved to user://save.json so it
## survives game restarts. Used by main menu (Level Select gate) and by
## level_controller.complete_level() when a level is won.
##

const SAVE_PATH := "user://save.json"

# 0 = no level completed yet. 1 = level 1 done, 2 = level 2 done, etc.
# Mutated by complete_level() and load_state(); read by is_level_unlocked().
var highest_level_completed: int = 0

# Which level is currently loaded. Set by level_select / main_menu before
# changing scene to the shared level.tscn. Read by win_screen / lose_screen
# for the Restart button (so Restart returns to the level the player just
# completed, not always level 1). Resets to 0 between game sessions.
var current_level_number: int = 0


# Editor test-spec: when non-empty, the next level scene to load uses
# this spec instead of reading JSON from disk. Set by either the level
# editor's Test Level button or the level select menu's Custom Levels
# button. Consumed (set back to {}) by LevelLoader._load_level on use
# — one-shot transfer mechanism so subsequent level loads fall back
# to the normal JSON path.
var pending_spec: Dictionary = {}


## Load the saved state from disk on startup, so the menu's
## Start/Continue label and Level Select gates reflect prior progress.
func _ready() -> void:
	load_state()


## Record that the player has won `level`. Called by level_controller
## when a level's win condition fires. Only writes if `level` is strictly
## greater than the current record (no demotion — re-completing an old
## level doesn't lower the unlocked set).
func complete_level(level: int) -> void:
	if level > highest_level_completed:
		highest_level_completed = level
		save_state()


## Used by level_select to decide which level buttons are enabled.
## Levels up through (highest_level_completed + 1) are unlocked — i.e.,
## the player can always play the "next" level beyond their best, but
## must complete levels in order to progress past that.
func is_level_unlocked(level: int) -> bool:
	return level <= highest_level_completed + 1


# --- Persistence ---

## Write the current highest_level_completed to SAVE_PATH as JSON.
## Silently no-ops on file-write failure (with a push_error for the
## editor console) — saving shouldn't crash gameplay.
func save_state() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveState: failed to open save file for writing at %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({"highest_level_completed": highest_level_completed}))
	file.close()


## Read the saved state from SAVE_PATH. No-ops on missing file (first
## run; defaults apply) or malformed JSON. On parse failure, keeps the
## current (default) value rather than crashing.
func load_state() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return  # First run — no save file yet, defaults (highest_level_completed = 0) apply
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveState: failed to open save file for reading at %s" % SAVE_PATH)
		return
	var data = JSON.parse_string(file.get_as_text())
	if data is Dictionary and data.has("highest_level_completed"):
		highest_level_completed = int(data["highest_level_completed"])
	file.close()
