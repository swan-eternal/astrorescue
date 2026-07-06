extends Control
##
## WinScreen: shown when the player completes a level. Two buttons:
## Restart (reloads the current level) and Main Menu (back to title).
##

@onready var _audio_manager: Node = get_node("/root/AudioManager")


## Wire up the buttons and stop the music (no victory track yet —
## the user hasn't recorded one).
func _ready() -> void:
	$CenterContainer/VBoxContainer/RestartButton.pressed.connect(_on_restart_pressed)
	$CenterContainer/VBoxContainer/MainMenuButton.pressed.connect(_on_main_menu_pressed)
	# No music on the win screen (the user didn't provide a victory track).
	_audio_manager.stop_music()


## Restart-button handler: reload the current level.
## Uses SaveState.current_level_number (set by level_select / main_menu
## when the level was loaded) so Restart works for any level.
func _on_restart_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/level.tscn")


## Main-Menu-button handler: return to the title screen.
func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")