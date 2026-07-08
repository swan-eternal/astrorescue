extends CanvasLayer
##
## PauseMenu: appears when player presses Esc during gameplay.
## Pauses the game tree and shows a small panel with Continue
## (resume) and Main Menu (return to main menu) options.
##
## Self-contained: builds its UI in _ready, handles its own Esc
## input via _unhandled_input, and uses PROCESS_MODE_ALWAYS so it
## stays interactive while the rest of the game is paused. Layer
## set high so it draws over the HUD.
##

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

# Cached so we can show/hide the panel without rebuilding it.
var _panel: PanelContainer


func _ready() -> void:
	# Stay interactive while the rest of the game tree is paused —
	# otherwise the Continue button would be unclickable.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Draw above the HUD (which sits at default layer 1).
	layer = 100
	_build_ui()
	_panel.visible = false


## Build the pause panel: "Paused" label + Continue / Main Menu
## buttons, centered on the screen.
func _build_ui() -> void:
	# Full-rect Control so the panel can be centered via anchor.
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Eat mouse input over the backdrop so a stray click while paused
	# doesn't fall through to anything behind us. (Setting to STOP on
	# a full-rect Control above the gameplay is the standard way to
	# dim/lock the screen during a modal.)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(280, 0)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	var continue_btn := Button.new()
	continue_btn.text = "Continue"
	continue_btn.pressed.connect(_on_continue_pressed)
	vbox.add_child(continue_btn)

	var main_menu_btn := Button.new()
	main_menu_btn.text = "Main Menu"
	main_menu_btn.pressed.connect(_on_main_menu_pressed)
	vbox.add_child(main_menu_btn)


## Esc handling: pause from gameplay, or resume if already paused.
## Uses _unhandled_input so it doesn't swallow events meant for the
## rocket's input handler unless they're Esc (we set_input_as_handled
## only after we've decided to act).
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		return
	if get_tree().paused:
		_on_continue_pressed()
	else:
		_open_pause()
	get_viewport().set_input_as_handled()


## Show the panel and pause the game tree.
func _open_pause() -> void:
	_panel.visible = true
	get_tree().paused = true


## Hide the panel and resume the game tree. Called by both the
## Continue button and the Esc-while-paused path.
func _on_continue_pressed() -> void:
	_panel.visible = false
	get_tree().paused = false


## Unpause then change scene. Unpause first so the new scene isn't
## frozen when it loads.
func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)