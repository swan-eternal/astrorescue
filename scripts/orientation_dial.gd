extends Control
##
## Orientation dial: shows the rocket's heading as a rotating icon inside
## a fixed circular frame. Visible at any zoom level so the player can read
## which way their ship is pointed regardless of how far the camera is
## zoomed out.
##

# --- Visual style ---
@export var dial_radius: float = 44.0
@export var bg_color: Color = Color(0.05, 0.05, 0.1, 0.7)
@export var border_color: Color = Color(0.4, 0.5, 0.6, 0.8)
@export var tick_color: Color = Color(0.5, 0.6, 0.7, 0.8)
@export var north_color: Color = Color(1.0, 0.85, 0.3)        # "up" marker at 12 o'clock
@export var rocket_color: Color = Color(0.9, 0.95, 1.0)


var rocket: Node2D = null


func _ready() -> void:
	rocket = get_tree().get_first_node_in_group("player")
	if rocket == null:
		push_warning("OrientationDial: no rocket found in 'player' group")


func _process(_delta: float) -> void:
	# Redraw every frame so the icon tracks the rocket's rotation smoothly.
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var r := dial_radius

	# Background disk.
	draw_circle(center, r, bg_color)

	# Outer border.
	draw_arc(center, r, 0.0, TAU, 48, border_color, 1.5, false)

	# Four cardinal tick marks at 12 / 3 / 6 / 9 o'clock (fixed in world/screen).
	# 12 o'clock is the yellow "north" reference, the rest are muted gray-blue.
	for i in 4:
		var angle := -PI / 2.0 + float(i) * PI / 2.0
		var inner_pt := center + Vector2(cos(angle), sin(angle)) * (r - 6.0)
		var outer_pt := center + Vector2(cos(angle), sin(angle)) * r
		var col := north_color if i == 0 else tick_color
		var width := 2.5 if i == 0 else 1.5
		draw_line(inner_pt, outer_pt, col, width)

	# Rocket icon: rotates with rocket.rotation. Mirrors the rocket's triangle
	# shape (nose forward, splayed tail).
	if rocket == null:
		return
	var heading := rocket.rotation
	var nose_offset := Vector2(cos(heading), sin(heading)) * (r * 0.80)
	var tail_offset := Vector2(cos(heading + PI), sin(heading + PI)) * (r * 0.55)
	var wing_offset := Vector2(cos(heading + PI / 2.0), sin(heading + PI / 2.0)) * (r * 0.40)

	var nose := center + nose_offset
	var wing_l := center + tail_offset + wing_offset
	var wing_r := center + tail_offset - wing_offset

	draw_colored_polygon([nose, wing_l, wing_r], rocket_color)