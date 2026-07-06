extends Control
##
## TimeMarker: renders small dots at given world-space positions via _draw().
## Used as a child of trajectory Line2D nodes to show "where will I be at
## time T" markers along predicted paths and orbit ellipses.
##
## Consumers (e.g., trajectoryline_2d.gd) call update_positions() each frame
## with the list of world-space positions where markers should appear.
##

# Cached positions to render. Mutated via update_positions(); read by _draw.
var positions: PackedVector2Array = PackedVector2Array()

## Radius (in pixels) of each marker dot.
@export var marker_radius: float = 4.0

## Fill color for each marker dot. Bright yellow with high alpha to
## stand out against the red trajectory line.
@export var marker_color: Color = Color(1.0, 0.95, 0.2, 0.95)


## Configure this node to be a non-interactive overlay: ignore mouse
## events and draw above the parent Line2D (which has default z_index=0).
## The explicit z_index makes the render order unambiguous even if the
## scene tree's child order changes.
func _ready() -> void:
	# Don't intercept mouse events — we're an invisible overlay that just draws dots.
	mouse_filter = MOUSE_FILTER_IGNORE
	# Draw on top of the parent Line2D (which has default z_index=0). Children
	# already render after parents, but setting z_index=1 explicitly makes the
	# order unambiguous and prevents the line from obscuring markers at far zoom.
	z_index = 1


## Update the marker positions to render on the next _draw. Called by
## consumers (e.g., trajectoryline_2d.gd) each frame with the list of
## world-space positions where markers should appear.
func update_positions(new_positions: PackedVector2Array) -> void:
	positions = new_positions
	queue_redraw()


## Draw one filled circle per cached position. Runs whenever queue_redraw
## is called (typically once per frame after update_positions).
func _draw() -> void:
	for pos in positions:
		draw_circle(pos, marker_radius, marker_color)