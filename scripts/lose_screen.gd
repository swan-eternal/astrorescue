extends Control
##
## LoseScreen: shown when the player crashes. Two buttons:
## Restart (reloads the current level) and Main Menu (back to title).
##

@onready var _audio_manager: Node = get_node("/root/AudioManager")


## Wire up the buttons and stop the music (no defeat track yet —
## the user hasn't recorded one).
func _ready() -> void:
	$CenterContainer/VBoxContainer/RestartButton.pressed.connect(_on_restart_pressed)
	$CenterContainer/VBoxContainer/MainMenuButton.pressed.connect(_on_main_menu_pressed)
	# No music on the lose screen (the user didn't provide a defeat track).
	_audio_manager.stop_music()


## Restart-button handler: reload the current level.
## MVP: hardcoded to level_01 since we only have one level. Phase 2 will
## track the current level via SaveState (e.g., save_state.current_level_number)
## so this works for any level.
func _on_restart_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/level_01.tscn")


## Main-Menu-button handler: return to the title screen.
func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")