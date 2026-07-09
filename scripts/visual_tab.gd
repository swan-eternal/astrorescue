extends Control
##
## VisualTab: settings panel for visual toggles. Currently has one
## control: Show Planet SOI (Sphere of Influence around planets during
## gameplay). Reads/writes go through the `VisualSettings` autoload,
## which persists to user://visual_settings.cfg.
##
## Built entirely in code (no .tscn child structure) to match the
## audio_tab / pause_menu / main_menu patterns.
##

# Per-toggle UI handles, populated in _build_ui; read/written by the
# toggle callback.
var _show_soi: CheckBox


func _ready() -> void:
	_build_ui()
	_refresh_from_state()


## Build one CheckBox for the SOI toggle. The CheckBox's `toggled`
## signal is wired to push the new value into VisualSettings.
func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	# Section header — explains what follows. Modulated down so the
	# controls below read as the primary content.
	var hint := Label.new()
	hint.text = "Visual toggles"
	hint.modulate = Color(1, 1, 1, 0.6)
	vbox.add_child(hint)

	_show_soi = CheckBox.new()
	_show_soi.text = "Show Planet SOI"
	_show_soi.toggled.connect(_on_show_soi_toggled)
	vbox.add_child(_show_soi)


## Read VisualSettings state and reflect it in the UI. Called once in
## _ready so the panel shows the persisted value (from
## user://visual_settings.cfg) instead of the CheckBox default.
func _refresh_from_state() -> void:
	# set_block_signals around the programmatic update so the toggled
	# handler doesn't fire and re-push the same value back to
	# VisualSettings (and re-save to disk).
	_show_soi.set_block_signals(true)
	_show_soi.button_pressed = VisualSettings.is_show_soi()
	_show_soi.set_block_signals(false)


## Show SOI checkbox toggled: push state to VisualSettings. The actual
## SOI indicator reads `VisualSettings.is_show_soi()` each frame so the
## visualization updates on the next draw — no explicit signal wiring
## needed here.
func _on_show_soi_toggled(pressed: bool) -> void:
	VisualSettings.set_show_soi(pressed)