extends Control
##
## LevelSelect: simple level picker. One button per level file in
## data/levels/, stacked vertically. Each is enabled or disabled based
## on SaveState.is_level_unlocked(). Disabled buttons show
## "Level N (locked)" with a Back to Main Menu at the bottom. Clicking
## an enabled button loads the corresponding level scene.
##
## Level buttons are built at runtime from the file system (see
## _build_level_buttons / _max_level_number), so adding a new
## level_NN.json automatically adds a button — no scene or constant
## edits needed.
##

# Where the editor's level JSON files live. The scanner looks for
# `level_<N>.json` files in this directory to size the button list.
const LEVELS_DIR := "res://data/levels/"
const LEVEL_FILENAME_PREFIX := "level_"
const LEVEL_FILENAME_EXT := ".json"

@onready var custom_levels_button: Button = $CenterContainer/VBoxContainer/CustomLevelsButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton
@onready var _audio_manager: Node = get_node("/root/AudioManager")


# FileDialog for the Custom Levels picker. Built in code so we don't
# need to add a node to the .tscn. Defaults to user://levels/ where
# the editor's Save writes.
var _custom_dialog: FileDialog


## Wire up the back + custom-levels buttons, start the menu music,
## build the per-level buttons dynamically, then set up the custom-levels
## file picker.
func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	custom_levels_button.pressed.connect(_on_custom_levels_pressed)

	# Level picker is a menu-like screen, so it uses the menu music.
	_audio_manager.play_menu_music()

	_build_level_buttons()
	_build_custom_dialog()


## Build one Button per `level_<N>.json` file found in LEVELS_DIR, in
## numeric order, inserted into the VBoxContainer immediately before
## CustomLevels. Each button is enabled or disabled based on
## SaveState.is_level_unlocked(); disabled ones get "(locked)" in the
## label. A spacer is inserted between the last level button and
## CustomLevels to preserve the vertical rhythm the old Spacer2 had.
##
## Adding a new level file (`level_06.json`) shows up here automatically
## on the next menu open — no scene or constant edits needed.
func _build_level_buttons() -> void:
	var vbox: VBoxContainer = $CenterContainer/VBoxContainer
	var custom_levels_idx: int = vbox.get_children().find(custom_levels_button)

	# Walk 1..N in order, inserting each new button at the current
	# insert index (which advances past each inserted button). This
	# produces the right order with one pass.
	var insert_idx: int = custom_levels_idx
	for level_num in range(1, _max_level_number() + 1):
		var btn := Button.new()
		btn.text = "Level %d" % level_num
		btn.custom_minimum_size = Vector2(220, 0)
		if SaveState.is_level_unlocked(level_num):
			btn.pressed.connect(_on_level_selected.bind(level_num))
		else:
			btn.disabled = true
			btn.text = "Level %d (locked)" % level_num
		vbox.add_child(btn)
		vbox.move_child(btn, insert_idx)
		insert_idx += 1

	# Spacer between the last level button and CustomLevels. Same size
	# as the deleted Spacer2 node so the vertical rhythm matches.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)
	vbox.move_child(spacer, insert_idx)


## Scan LEVELS_DIR for `level_<N>.json` files and return the highest N.
## Returns 0 if the directory is missing or contains no level files
## (menu shows no level buttons, only Custom Levels). Replaces the old
## hardcoded MAX_LEVEL — adding a level file now shows up automatically.
static func _max_level_number() -> int:
	var dir := DirAccess.open(LEVELS_DIR)
	if dir == null:
		return 0
	var max_n: int = 0
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if filename.begins_with(LEVEL_FILENAME_PREFIX) and filename.ends_with(LEVEL_FILENAME_EXT):
			# Slice out the numeric portion between the prefix and
			# extension. is_valid_int() rejects things like
			# `level_01a.json` or `level_.json`.
			var digits: String = filename.substr(
				LEVEL_FILENAME_PREFIX.length(),
				filename.length() - LEVEL_FILENAME_PREFIX.length() - LEVEL_FILENAME_EXT.length()
			)
			if digits.is_valid_int():
				var n: int = digits.to_int()
				if n > max_n:
					max_n = n
		filename = dir.get_next()
	dir.list_dir_end()
	return max_n


## Build the FileDialog used by the Custom Levels picker. Same shape as
## the editor's Save/Load dialogs: ACCESS_USERDATA, *.json filter,
## opens in user://levels/.
func _build_custom_dialog() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_USERDATA
	dialog.current_dir = "user://levels"
	dialog.filters = PackedStringArray(["*.json ; JSON level spec"])
	dialog.file_selected.connect(_on_custom_dialog_file_selected)
	add_child(dialog)
	_custom_dialog = dialog


## Level-button handler: jump to the selected level. The level number
## is bound via .bind() in _ready so this single handler serves all
## three buttons. Sets SaveState.current_level_number so the shared
## level.tscn (loaded next) knows which JSON to read.
func _on_level_selected(level_num: int) -> void:
	SaveState.current_level_number = level_num
	get_tree().change_scene_to_file("res://scenes/level.tscn")


## Back-button handler: return to the main menu.
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## Custom Levels click: open the file picker (defaults to user://levels/).
## Files in that directory are written by the level editor's Save button.
## We do NOT enforce the editor's sun invariant here — the editor is the
## authoring tool, and this menu just plays what's on disk. A sun-less
## file will simply produce an empty game scene.
func _on_custom_levels_pressed() -> void:
	if not DirAccess.dir_exists_absolute("user://levels"):
		DirAccess.make_dir_recursive_absolute("user://levels")
	_custom_dialog.popup_centered_ratio(0.6)


## FileDialog callback: read+parse the chosen file, push the spec
## into SaveState.pending_spec, and change scene to level.tscn. The
## loader checks pending_spec before reading JSON, so the in-memory
## spec is the source of truth — same mechanism the editor's Test
## Level button uses.
##
## Rejects files with the wrong schema version (only v3 supported).
## Malformed JSON, unreadable files, and bad versions all push_error
## and leave the menu intact (no scene change).
func _on_custom_dialog_file_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("LevelSelect: failed to open %s (err %d)" % [path, FileAccess.get_open_error()])
		return
	var json_text := file.get_as_text()
	file.close()
	var data: Variant = JSON.parse_string(json_text)
	if not data is Dictionary:
		push_error("LevelSelect: failed to parse JSON in %s" % path)
		return
	var version: int = (data as Dictionary).get("version", 0)
	if version != 3:
		push_error("LevelSelect: unsupported schema version %d in %s (expected 3)" % [version, path])
		return
	SaveState.pending_spec = data
	get_tree().change_scene_to_file("res://scenes/level.tscn")