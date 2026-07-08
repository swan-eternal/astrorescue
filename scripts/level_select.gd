extends Control
##
## LevelSelect: simple level picker. Three buttons (Level 1, 2, 3) stacked
## vertically. Each is enabled or disabled based on SaveState.is_level_unlocked().
## Disabled buttons show "Level N (locked)" with a Back to Main Menu at the
## bottom. Clicking an enabled button loads the corresponding level scene.
##

# Hardcoded upper bound on level numbering for the level_%02d.tscn
# filename pattern. Bump this when adding new levels.
const MAX_LEVEL: int = 3

@onready var buttons: Array = [
	$CenterContainer/VBoxContainer/Level1Button,
	$CenterContainer/VBoxContainer/Level2Button,
	$CenterContainer/VBoxContainer/Level3Button,
]
@onready var custom_levels_button: Button = $CenterContainer/VBoxContainer/CustomLevelsButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton
@onready var _audio_manager: Node = get_node("/root/AudioManager")


# FileDialog for the Custom Levels picker. Built in code so we don't
# need to add a node to the .tscn. Defaults to user://levels/ where
# the editor's Save writes.
var _custom_dialog: FileDialog


## Wire up the back button, start the menu music, and enable/disable
## each level button based on SaveState.is_level_unlocked(). Disabled
## buttons display "Level N (locked)" so the player knows what they're
## missing.
func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	custom_levels_button.pressed.connect(_on_custom_levels_pressed)

	# Level picker is a menu-like screen, so it uses the menu music.
	_audio_manager.play_menu_music()

	for i in range(buttons.size()):
		var level_num: int = i + 1
		var button: Button = buttons[i]
		if SaveState.is_level_unlocked(level_num):
			button.disabled = false
			button.text = "Level %d" % level_num
			button.pressed.connect(_on_level_selected.bind(level_num))
		else:
			button.disabled = true
			button.text = "Level %d (locked)" % level_num

	_build_custom_dialog()


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