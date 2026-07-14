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
var _vignette_slider: HSlider
var _vignette_value_label: Label


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

	# Vignette intensity row: label + HSlider + numeric readout in
	# an HBoxContainer so the readout sits to the right of the slider.
	# The HBoxContainer is added to the vbox so the rows stack vertically
	# with the SOI checkbox above and the slider below.
	var vignette_row := HBoxContainer.new()
	vignette_row.add_theme_constant_override("separation", 12)
	vbox.add_child(vignette_row)

	var vignette_label := Label.new()
	vignette_label.text = "Vignette intensity"
	vignette_label.custom_minimum_size = Vector2(160, 0)
	vignette_row.add_child(vignette_label)

	_vignette_slider = HSlider.new()
	_vignette_slider.min_value = 0.0
	_vignette_slider.max_value = 1.0
	# 0.01 step = 100 discrete positions across the range. Fine enough
	# for visual tuning, coarse enough that the saved config file
	# stays clean (no float-drift values).
	_vignette_slider.step = 0.01
	_vignette_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vignette_slider.value_changed.connect(_on_vignette_changed)
	vignette_row.add_child(_vignette_slider)

	_vignette_value_label = Label.new()
	_vignette_value_label.custom_minimum_size = Vector2(40, 0)
	_vignette_value_label.text = "0.30"
	vignette_row.add_child(_vignette_value_label)


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

	# Same pattern for the vignette slider — programmatic value set
	# without firing value_changed.
	var vignette_value: float = VisualSettings.get_vignette_intensity()
	_vignette_slider.set_block_signals(true)
	_vignette_slider.value = vignette_value
	_vignette_slider.set_block_signals(false)
	_update_vignette_label(vignette_value)


## Show SOI checkbox toggled: push state to VisualSettings. The actual
## SOI indicator reads `VisualSettings.is_show_soi()` each frame so the
## visualization updates on the next draw — no explicit signal wiring
## needed here.
func _on_show_soi_toggled(pressed: bool) -> void:
	VisualSettings.set_show_soi(pressed)


## Vignette slider changed: push state to VisualSettings. Fires
## continuously while the user drags, so the disk write happens on
## every frame the slider moves — same pattern as the SOI checkbox
## (no debounce). For V1 that's fine; if it ever shows up in
## profiling, throttle via a Timer.
func _on_vignette_changed(value: float) -> void:
	# Snap to slider step to keep the saved config file clean (no
	# floating-point drift from sub-step values).
	var snapped: float = snappedf(value, _vignette_slider.step)
	VisualSettings.set_vignette_intensity(snapped)
	_update_vignette_label(snapped)


## Format and write the slider's current value into the readout
## label. Centralized so the initial _refresh_from_state and the
## slider's value_changed handler go through the same display path.
func _update_vignette_label(value: float) -> void:
	_vignette_value_label.text = "%.2f" % value