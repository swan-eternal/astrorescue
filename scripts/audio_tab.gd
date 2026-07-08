extends Control
##
## AudioTab: settings panel for the three audio buses (Master / Music / SFX).
## One row per channel: name label, slider (0..100 -> MIN_DB..MAX_DB dB),
## live dB value label, mute checkbox. All reads/writes go through the
## `AudioSettings` autoload, which persists to user://settings.cfg.
##
## Built entirely in code (no .tscn child structure) to match the
## pause_menu / main_menu patterns elsewhere in the project.
##

# Slider bounds. 0 = near-silent (-40 dB), 100 = unity gain (0 dB).
# Conversion to dB is linear: db = MIN_DB + (slider / 100) * (MAX_DB - MIN_DB).
const SLIDER_MIN := 0.0
const SLIDER_MAX := 100.0

# Channel keys in AudioSettings.BUSES. Order here = display order.
# Labels are the user-facing names shown in the row.
const CHANNELS := [
	{"key": "master", "label": "Master"},
	{"key": "music",  "label": "Music"},
	{"key": "sfx",    "label": "SFX"},
]

# dB range mapped to the slider. Mirrors AudioSettings.MIN_DB / MAX_DB
# so the slider bounds stay in sync if those constants are ever tweaked.
# Pulled as AudioSettings constants here (allowed at parse time because
# AudioSettings is an autoload registered before scene scripts run).
const _DB_RANGE := Vector2(AudioSettings.MIN_DB, AudioSettings.MAX_DB)


# Per-channel UI handles, indexed by AudioSettings key. Populated in
# _build_ui; read/written by the slider/checkbox callbacks.
var _rows: Dictionary = {}


func _ready() -> void:
	_build_ui()
	_refresh_from_state()


## Build three rows of [name | slider | dB value | mute checkbox].
## Each row is an HBox laid out side-by-side; the slider uses
## SIZE_EXPAND_FILL so it stretches while the label/value/mute keep
## their fixed widths.
func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	# Hint label at the top — explains what the slider numbers mean.
	var hint := Label.new()
	hint.text = "Volume (0..100, lower = quieter)"
	hint.modulate = Color(1, 1, 1, 0.6)
	vbox.add_child(hint)

	for channel in CHANNELS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vbox.add_child(row)

		# Channel name (fixed-width so the slider column lines up).
		var name_label := Label.new()
		name_label.text = channel["label"]
		name_label.custom_minimum_size = Vector2(70, 0)
		row.add_child(name_label)

		# Volume slider: integer-stepped 0..100.
		var slider := HSlider.new()
		slider.min_value = SLIDER_MIN
		slider.max_value = SLIDER_MAX
		slider.step = 1.0
		slider.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		row.add_child(slider)

		# Live dB readout (or "Muted" override). Right-aligned, fixed
		# width so the digits don't make the layout twitch.
		var value_label := Label.new()
		value_label.text = "0 dB"
		value_label.custom_minimum_size = Vector2(64, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)

		# Mute checkbox.
		var mute := CheckBox.new()
		mute.text = "Mute"
		row.add_child(mute)

		# Wire signals AFTER all controls exist so initial set_block_signals
		# in _refresh_from_state() doesn't race with a half-built row.
		slider.value_changed.connect(_on_slider_changed.bind(channel["key"]))
		mute.toggled.connect(_on_mute_toggled.bind(channel["key"]))

		_rows[channel["key"]] = {"slider": slider, "mute": mute, "label": value_label}


## Read AudioSettings state and reflect it in the UI. Called once in
## _ready so the panel shows the persisted values (from
## user://settings.cfg) instead of the slider/checkbox defaults.
func _refresh_from_state() -> void:
	for channel in CHANNELS:
		var key: String = channel["key"]
		var db: float = AudioSettings.get_db(key)
		var muted: bool = AudioSettings.is_muted(key)
		var row: Dictionary = _rows[key]

		# Invert the slider->dB mapping: slider = (db - MIN_DB) / (MAX_DB - MIN_DB) * 100.
		# Clamp to slider bounds in case persisted db somehow sits outside the range.
		var slider_value: float = (db - _DB_RANGE.x) / (_DB_RANGE.y - _DB_RANGE.x) * SLIDER_MAX
		slider_value = clampf(slider_value, SLIDER_MIN, SLIDER_MAX)

		# set_block_signals around the programmatic update so the
		# value_changed / toggled handlers don't fire and re-push
		# the same value back to AudioSettings (and re-save to disk).
		row["slider"].set_block_signals(true)
		row["slider"].value = slider_value
		row["slider"].set_block_signals(false)

		row["mute"].set_block_signals(true)
		row["mute"].button_pressed = muted
		row["mute"].set_block_signals(false)

		_update_value_label(key, db, muted)


## Slider drag: convert 0..100 to dB linearly and push to AudioSettings.
func _on_slider_changed(value: float, key: String) -> void:
	var db: float = _DB_RANGE.x + (value / SLIDER_MAX) * (_DB_RANGE.y - _DB_RANGE.x)
	AudioSettings.set_db(key, db)
	_update_value_label(key, db, AudioSettings.is_muted(key))


## Mute checkbox toggled: push state and refresh the label.
func _on_mute_toggled(pressed: bool, key: String) -> void:
	AudioSettings.set_muted(key, pressed)
	_update_value_label(key, AudioSettings.get_db(key), pressed)


## Format the value column. "Muted" overrides the dB read so the user
## can see at a glance which channels are silent (mute is on top of
## volume; the underlying dB value is preserved).
func _update_value_label(key: String, db: float, muted: bool) -> void:
	var label: Label = _rows[key]["label"]
	if muted:
		label.text = "Muted"
	else:
		label.text = "%d dB" % roundi(db)