extends Control
##
## MainMenu: game start screen. Logo + buttons for Start (which becomes
## "Continue" once any level is completed) / How to Play / Level Select /
## Quit. Start loads the highest unlocked level (per SaveState). Level Select
## opens the level picker.
##

# Hardcoded upper bound on level numbering for the level_%02d.tscn
# filename pattern. Bump this when adding new levels.
const MAX_LEVEL: int = 3

# Settings panel scene used by the Settings button. Same scene
# the pause menu instances — settings_menu handles its own Esc/Close
# and queue_frees itself; main_menu stays as the backdrop.
const SETTINGS_MENU_SCENE := "res://scenes/settings_menu.tscn"

# Instruction pages shown in the How to Play overlay, indexed by
# _current_page. _update_page() swaps the TextureRect's texture and
# toggles Prev/Next disabled state at the ends. Adding a page is a
# one-line change here — the panel auto-resizes its indicator.
const INSTRUCTION_PAGES: Array[Texture2D] = [
	preload("res://assets/images/instructionPage1.png"),
	preload("res://assets/images/instructionPage2.png"),
]


@onready var how_to_play_panel: Panel = $HowToPlayPanel
@onready var instruction_image: TextureRect = $HowToPlayPanel/VBoxContainer/InstructionImage
@onready var prev_button: Button = $HowToPlayPanel/VBoxContainer/NavRow/PrevButton
@onready var page_indicator: Label = $HowToPlayPanel/VBoxContainer/NavRow/PageIndicator
@onready var next_button: Button = $HowToPlayPanel/VBoxContainer/NavRow/NextButton
@onready var close_button: Button = $HowToPlayPanel/VBoxContainer/CloseButton
@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton
@onready var _audio_manager: Node = get_node("/root/AudioManager")

# Which instruction page is currently shown. Resets to 0 every time
# the How to Play panel opens (set in _on_how_to_play_pressed), so
# closing mid-read doesn't lose the player's spot in a surprising way.
var _current_page: int = 0


## Wire up button signals, start the menu music, and toggle the Start
## button's label between "Start" (fresh save) and "Continue"
## (any level previously completed).
func _ready() -> void:
	$CenterContainer/VBoxContainer/StartButton.pressed.connect(_on_start_pressed)
	$CenterContainer/VBoxContainer/HowToPlayButton.pressed.connect(_on_how_to_play_pressed)
	$CenterContainer/VBoxContainer/LevelSelectButton.pressed.connect(_on_level_select_pressed)
	$CenterContainer/VBoxContainer/SettingsButton.pressed.connect(_on_settings_pressed)
	$CenterContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)
	$CenterContainer/VBoxContainer/LevelEditorButton.pressed.connect(_on_level_editor_pressed)
	close_button.pressed.connect(_on_how_to_play_close)
	prev_button.pressed.connect(_on_prev_page)
	next_button.pressed.connect(_on_next_page)

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


## How-To-Play-button handler: toggle the help overlay on/off. When
## opening, reset to page 1 so the player always starts at the
## beginning of the tutorial rather than wherever they left off.
## Same button both opens and closes it for keyboard-friendly UX.
func _on_how_to_play_pressed() -> void:
	how_to_play_panel.visible = not how_to_play_panel.visible
	if how_to_play_panel.visible:
		_current_page = 0
		_update_page()


## Prev-page button: step backward through INSTRUCTION_PAGES. Disabled
## at page 0 by _update_page (the click is also a no-op as a guard).
func _on_prev_page() -> void:
	if _current_page > 0:
		_current_page -= 1
		_update_page()


## Next-page button: step forward through INSTRUCTION_PAGES. Disabled
## at the last page by _update_page (the click is also a no-op as a guard).
func _on_next_page() -> void:
	if _current_page < INSTRUCTION_PAGES.size() - 1:
		_current_page += 1
		_update_page()


## Sync the instruction-image texture, page indicator, and Prev/Next
## disabled state to match `_current_page`. Called on initial display
## (when the panel opens) and after every page change.
func _update_page() -> void:
	instruction_image.texture = INSTRUCTION_PAGES[_current_page]
	page_indicator.text = "Page %d of %d" % [_current_page + 1, INSTRUCTION_PAGES.size()]
	prev_button.disabled = _current_page == 0
	next_button.disabled = _current_page == INSTRUCTION_PAGES.size() - 1


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


## Settings-button handler: instance the settings panel as an overlay
## on top of the main menu. Settings handles its own Esc/Close and
## queue_frees itself; main_menu stays as the backdrop (no scene
## change). No-op if a settings panel is already open (guards
## against double-clicks stacking duplicate panels).
func _on_settings_pressed() -> void:
	if SettingsMenu.is_any_open():
		return
	var settings: CanvasLayer = load(SETTINGS_MENU_SCENE).instantiate()
	add_child(settings)


## Find the highest level the player has unlocked (i.e., the most
## recent level they can play). Level 1 is always unlocked since
## SaveState starts with highest_level_completed = 0. Walks from
## MAX_LEVEL down to 1 and returns the first unlocked one.
func _highest_unlocked_level() -> int:
	for level_num in range(MAX_LEVEL, 0, -1):
		if SaveState.is_level_unlocked(level_num):
			return level_num
	return 1  # safety fallback — never reached since level 1 is always unlocked
