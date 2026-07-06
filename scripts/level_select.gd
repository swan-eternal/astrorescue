extends Control
##
## LevelSelect: simple level picker. Three buttons (Level 1, 2, 3) stacked
## vertically. Each is enabled or disabled based on SaveState.is_level_unlocked().
## Disabled buttons show "Level N (locked)" with a Back to Main Menu at the
## bottom. Clicking an enabled button loads the corresponding level scene.
##

const MAX_LEVEL: int = 3

@onready var buttons: Array = [
	$CenterContainer/VBoxContainer/Level1Button,
	$CenterContainer/VBoxContainer/Level2Button,
	$CenterContainer/VBoxContainer/Level3Button,
]
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton
@onready var _audio_manager: Node = get_node("/root/AudioManager")


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)

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


func _on_level_selected(level_num: int) -> void:
	var path: String = "res://scenes/level_%02d.tscn" % level_num
	get_tree().change_scene_to_file(path)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")