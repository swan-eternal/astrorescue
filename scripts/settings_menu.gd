extends CanvasLayer
class_name SettingsMenu
##
## SettingsMenu: tabbed settings panel (Audio / Visual / Gameplay).
## Self-contained: builds its UI in _ready, handles Esc via
## _unhandled_input, and queue_frees itself to close.
##
## process_mode = PROCESS_MODE_ALWAYS so it works while the game
## tree is paused (e.g., opened from the pause menu). layer = 110
## to draw above the pause menu (layer = 100) and HUD.
##
## Static `_is_any_open` flag lets the pause menu's own Esc handler
## distinguish "settings is showing" from "settings is closed" —
## otherwise pressing Esc to close the settings panel would also
## resume the game underneath (because both handlers would see the
## same Esc event in the same frame).
##

# Tab scenes instanced into the TabContainer. Each child's `name`
# is used by TabContainer as the tab label, so the .tscn roots
# are named "Audio" / "Visual" / "Gameplay" accordingly.
const AUDIO_TAB_SCENE := "res://scenes/audio_tab.tscn"
const VISUAL_TAB_SCENE := "res://scenes/visual_tab.tscn"
const GAMEPLAY_TAB_SCENE := "res://scenes/gameplay_tab.tscn"

# Panel sizing. Wide enough for the audio row layout (name + slider +
# dB + mute) without cramping; tall enough for the placeholder text
# in the visual/gameplay tabs without overflow.
const PANEL_SIZE := Vector2(460, 0)
const TABS_MIN_SIZE := Vector2(440, 320)


# Flag flipped by _ready / _exit_tree. Checked by the pause menu's
# _unhandled_input: when true, ignore Esc (don't resume the game,
# don't open anything else — let settings handle it).
static var _is_any_open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
	_is_any_open = true
	_build_ui()


## Reset the flag on tree exit. queue_free is deferred to the end
## of the current idle frame, so _exit_tree fires AFTER the current
## event has finished propagating — meaning a parent (pause menu)
## whose _unhandled_input fires earlier in the same frame still sees
## _is_any_open = true and ignores Esc. By the next frame the flag
## is false, so a fresh Esc press acts on the parent normally.
func _exit_tree() -> void:
	_is_any_open = false


## Build: full-rect backdrop + centered PanelContainer with title,
## TabContainer (Audio/Visual/Gameplay), and a Close button.
func _build_ui() -> void:
	# Backdrop: full-rect Control with mouse_filter = STOP so a click
	# outside the panel doesn't fall through to anything behind
	# (e.g., the pause menu buttons). Same pattern as the pause menu.
	var backdrop := Control.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	# CenterContainer centers its single child and respects its
	# custom_minimum_size for sizing. Replaces the previous
	# set_anchors_and_offsets_preset(PRESET_CENTER) approach, which
	# set anchors to 0.5/0.5/0.5/0.5 but kept offsets at 0/0/0/0
	# because the Control had zero size when the preset was applied
	# (before being added to the tree). End result: panel anchored
	# at center, sized to zero, rendered at origin.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(center)

	# Panel with the title + tabs + close button. Stylebox override
	# (see _make_panel_stylebox) replaces Godot's default semi-
	# transparent Panel bg — when opened from the main menu, that
	# default lets the "PLAY"/"SETTINGS"/"QUIT" buttons bleed through,
	# which reads as visually messy. Opaque dark here keeps the panel
	# as a solid modal surface.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	panel.add_theme_stylebox_override("panel", _make_panel_stylebox())
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	# TabContainer: each child becomes a tab; the child's `name`
	# is the tab label. The .tscn roots set their own names.
	var tabs := TabContainer.new()
	tabs.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	tabs.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	tabs.custom_minimum_size = TABS_MIN_SIZE
	vbox.add_child(tabs)

	var audio_tab: Control = preload(AUDIO_TAB_SCENE).instantiate()
	tabs.add_child(audio_tab)

	var visual_tab: Control = preload(VISUAL_TAB_SCENE).instantiate()
	tabs.add_child(visual_tab)

	var gameplay_tab: Control = preload(GAMEPLAY_TAB_SCENE).instantiate()
	tabs.add_child(gameplay_tab)

	# Close button: same behavior as Esc (queue_free).
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(_close)
	vbox.add_child(close_btn)


## Esc closes the panel. set_input_as_handled stops the event from
## propagating to any other _unhandled_input handler — in particular
## the pause menu's, which would otherwise also see this Esc and
## resume the game underneath the settings panel.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()


## Free this scene. queue_free is deferred; the node stays alive for
## the rest of the current frame so any _unhandled_input handler that
## fires later in the same frame (or any tree_exited listener) still
## sees the settings panel in the tree.
func _close() -> void:
	queue_free()


## Build a fully-opaque dark stylebox for the panel. Godot's default
## PanelContainer bg_color is alpha = 0.75 — opening settings over the
## main menu lets the buttons behind show through, which reads as
## visually messy. Override is per-instance (add_theme_stylebox_override
## on this PanelContainer only) rather than mutating the global theme,
## so any future Panels in the project keep the default look unless
## they explicitly opt in. The dark color here matches the typical
## "modal panel" tone used by most UIs — solid enough to read as a
## distinct surface, not so dark it looks like a hole in the screen.
func _make_panel_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.14, 1.0)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


## Static accessor used by pause_menu.gd to gate its own Esc handler.
static func is_any_open() -> bool:
	return _is_any_open