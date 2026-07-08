extends Control
##
## VisualTab: settings placeholder. No real controls yet — just a
## centered label listing what's coming so the settings menu has
## three tabs of consistent structure (Audio / Visual / Gameplay).
##
## Built in code (no .tscn child structure) to match the audio_tab
## and pause_menu patterns.
##

func _ready() -> void:
	var label := Label.new()
	label.text = "Visual settings\n\nComing soon:\nfullscreen, brightness, ..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)