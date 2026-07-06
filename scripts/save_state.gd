extends Node
##
## SaveState: persistent game progress (autoload singleton).
## Stores the highest level completed. Saved to user://save.json so it
## survives game restarts. Used by main menu (Level Select gate) and by
## level_controller.complete_level() when a level is won.
##

const SAVE_PATH := "user://save.json"

# 0 = no level completed yet. 1 = level 1 done, 2 = level 2 done, etc.
var highest_level_completed: int = 0


func _ready() -> void:
	load_state()


# Called by level_controller when a level is won. Only writes if the new
# level is strictly greater than the current record (no demotion).
func complete_level(level: int) -> void:
	if level > highest_level_completed:
		highest_level_completed = level
		save_state()


# Used by level_select to decide which level buttons are enabled.
# Levels up through (highest_level_completed + 1) are unlocked — i.e., the
# player can always play the "next" level beyond their best.
func is_level_unlocked(level: int) -> bool:
	return level <= highest_level_completed + 1


# --- Persistence ---

func save_state() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveState: failed to open save file for writing at %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({"highest_level_completed": highest_level_completed}))
	file.close()


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
