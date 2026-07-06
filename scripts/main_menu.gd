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
func _on_start_pressed() -> void:
	var level_num: int = _highest_unlocked_level()
	var path: String = "res://scenes/level_%02d.tscn" % level_num
	get_tree().change_scene_to_file(path)


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


## Find the highest level the player has unlocked (i.e., the most
## recent level they can play). Level 1 is always unlocked since
## SaveState starts with highest_level_completed = 0. Walks from
## MAX_LEVEL down to 1 and returns the first unlocked one.
func _highest_unlocked_level() -> int:
	for level_num in range(MAX_LEVEL, 0, -1):
		if SaveState.is_level_unlocked(level_num):
			return level_num
	return 1  # safety fallback — never reached since level 1 is always unlocked