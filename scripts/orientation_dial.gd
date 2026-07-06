extends Control
##
## Orientation dial: shows the rocket's heading as a rotating icon inside
## a fixed circular frame. Visible at any zoom level so the player can read
## which way their ship is pointed regardless of how far the camera is
## zoomed out.
##

# --- Visual style ---

## Radius of the dial in pixels (the disk that contains the icon).
@export var dial_radius: float = 44.0

## Fill color of the dial's background disk.
@export var bg_color: Color = Color(0.05, 0.05, 0.1, 0.7)

## Color of the outer border arc.
@export var border_color: Color = Color(0.4, 0.5, 0.6, 0.8)

## Color of the 3, 6, 9 o'clock tick marks (the non-north cardinals).
@export var tick_color: Color = Color(0.5, 0.6, 0.7, 0.8)

## Color of the 12 o'clock tick mark — the "north" reference so the
## player can orient "up" in the world.
@export var north_color: Color = Color(1.0, 0.85, 0.3)

## Fill color for the rocket icon triangle inside the dial.
@export var rocket_color: Color = Color(0.9, 0.95, 1.0)


# Cached reference to the rocket (via "player" group). Read every
# _draw to get the current heading.
var rocket: Node2D = null


## Cache the rocket reference via the "player" group. Warns (no crash)
## if not found so the dial degrades to a static compass frame.
func _ready() -> void:
	rocket = get_tree().get_first_node_in_group("player")
	if rocket == null:
		push_warning("OrientationDial: no rocket found in 'player' group")


## Queue a redraw every frame so the icon tracks the rocket's rotation
## smoothly. Cheap work (a few draw_circle/draw_line calls) — no need
## to optimize.
func _process(_delta: float) -> void:
	queue_redraw()


## Render the dial: background disk, border arc, four cardinal ticks,
## and a rocket-shaped triangle that points along the rocket's heading.
## The cardinals are fixed in screen space (don't rotate with the icon).
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