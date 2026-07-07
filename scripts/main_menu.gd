extends Control
##
## MainMenu: game start screen. Title + buttons for Start (which becomes
## "Continue" once any level is completed) / How to Play / Level Select /
## Quit. Start loads the highest unlocked level (per SaveState). Level Select
## opens the level picker.
##

@onready var how_to_play_panel: Panel = $HowToPlayPanel
@onready var close_button: Button = $HowToPlayPanel/VBoxContainer/CloseButton
@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var _audio_manager: Node = get_node("/root/AudioManager")

# Hardcoded upper bound on level numbering for the level_%02d.tscn
# filename pattern. Bump this when adding new levels.
const MAX_LEVEL: int = 3


## Wire up button signals, start the menu music, and toggle the Start
## button's label between "Start" (fresh save) and "Continue"
## (any level previously completed).
func _ready() -> void:
	$CenterContainer/VBoxContainer/StartButton.pressed.connect(_on_start_pressed)
	$CenterContainer/VBoxContainer/HowToPlayButton.pressed.connect(_on_how_to_play_pressed)
	$CenterContainer/VBoxContainer/LevelSelectButton.pressed.connect(_on_level_select_pressed)
	$CenterContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)
	$CenterContainer/VBoxContainer/LevelEditorButton.pressed.connect(_on_level_editor_pressed)
	close_button.pressed.connect(_on_how_to_play_close)

	# Background music for the menu (and the level picker, which is also a menu).
	_audio_manager.play_menu_music()

	# Start/Continue label: "Start" for a fresh save, "Continue" once any
	# level has been completed (so the player resumes where they left off).
	if SaveState.highest_level_completed == 0:
		start_button.text = "Start"
	else:
		start_button.text = "Continue"


## Start-button handler: jump to the highest unlocked level (so a
## returning player resumes where they left off rather than restarting).
## Sets SaveState.current_level_number so the shared level.tscn (loaded
## next) knows which JSON to read.
func _on_start_pressed() -> void:
	var level_num: int = _highest_unlocked_level()
	SaveState.current_level_number = level_num
	get_tree().change_scene_to_file("res://scenes/level.tscn")


## Level-Select-button handler: open the level picker scene.
func _on_level_select_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/level_select.tscn")


## How-To-Play-button handler: toggle the help overlay on/off.
## Same button both opens and closes it for keyboard-friendly UX.
func _on_how_to_play_pressed() -> void:
	how_to_play_panel.visible = not how_to_play_panel.visible


## Close-button handler (inside the How-To-Play panel). Explicit close
## in addition to the toggle so the panel has a natural dismiss affordance.
func _on_how_to_play_close() -> void:
	how_to_play_panel.visible = false


## Quit-button handler: terminate the game.
func _on_quit_pressed() -> void:
	get_tree().quit()


## Level-Editor-button handler: swap to the level editor scene so
## Jason can author / tweak levels without leaving the running game.
## The editor scene lives under tools/level_editor/. ResourceLoader.exists
## guards against a future build that excludes that folder (the
## level_editor.gd header claims this exclusion; export_presets.cfg
## doesn't currently set it — when it does, the click no-ops cleanly
## here instead of crashing on a missing scene).
func _on_level_editor_pressed() -> void:
	const LEVEL_EDITOR_SCENE := "res://tools/level_editor/level_editor.tscn"
	if not ResourceLoader.exists(LEVEL_EDITOR_SCENE):
		push_warning("Level editor scene not available in this build.")
		return
	get_tree().change_scene_to_file(LEVEL_EDITOR_SCENE)


## Find the highest level the player has unlocked (i.e., the most
## recent level they can play). Level 1 is always unlocked since
## SaveState starts with highest_level_completed = 0. Walks from
## MAX_LEVEL down to 1 and returns the first unlocked one.
func _highest_unlocked_level() -> int:
	for level_num in range(MAX_LEVEL, 0, -1):
		if SaveState.is_level_unlocked(level_num):
			return level_num
	return 1  # safety fallback — never reached since level 1 is always unlocked
