extends Control
##
## AstronautIndicators: orange markers over each uncollected astronaut in
## the level. On-screen: a small ring at the astronaut's screen position.
## Off-screen: a triangle clamped to the screen edge, pointing outward
## toward the astronaut.
##

@export var on_screen_radius: float = 8.0
@export var edge_padding: float = 30.0
@export var marker_color: Color = Color(0.3, 0.6, 1.0)  # same blue as the astronaut sprite
@export var arrow_size: float = 12.0

var rocket: Node2D = null


func _ready() -> void:
	rocket = get_tree().get_first_node_in_group("player")
	if rocket == null:
		push_warning("AstronautIndicators: no rocket found in 'player' group")


func _process(_delta: float) -> void:
	# Redraw each frame so markers track the world in real time.
	queue_redraw()


func _draw() -> void:
	if rocket == null:
		return

	# Canvas transform converts world coords → screen coords, accounting
	# for camera position and zoom.
	var canvas_xform: Transform2D = get_viewport().get_canvas_transform()
	var viewport_size: Vector2 = get_viewport_rect().size

	# Iterate every attractor that has an Astronaut child. We skip any
	# whose astronaut has been picked up.
	for body in get_tree().get_nodes_in_group("attractors"):
		var astronaut: Node = body.get_node_or_null("Astronaut")
		if astronaut == null:
			continue
		if astronaut.get("picked_up"):
			continue

		var screen_pos: Vector2 = canvas_xform * astronaut.global_position

		var on_screen: bool = (
			screen_pos.x >= 0.0 and screen_pos.x <= viewport_size.x and
			screen_pos.y >= 0.0 and screen_pos.y <= viewport_size.y
		)

		if on_screen:
			_draw_on_screen_marker(screen_pos)
		else:
			_draw_edge_arrow(screen_pos, viewport_size)


func _draw_on_screen_marker(at_pos: Vector2) -> void:
	draw_arc(at_pos, on_screen_radius, 0.0, TAU, 24, marker_color, 2.0, false)


func _draw_edge_arrow(target_pos: Vector2, viewport_size: Vector2) -> void:
	# Clamp the off-screen target to just inside the screen edge with padding.
	var clamped_x: float = clamp(target_pos.x, edge_padding, viewport_size.x - edge_padding)
	var clamped_y: float = clamp(target_pos.y, edge_padding, viewport_size.y - edge_padding)
	var arrow_pos: Vector2 = Vector2(clamped_x, clamped_y)

	# Direction from clamp position outward toward the off-screen astronaut.
	var direction: Vector2 = target_pos - arrow_pos
	if direction.length_squared() < 0.0001:
		return  # Astronaut is essentially at the camera position; nothing useful to draw
	direction = direction.normalized()

	# Triangle: tip pointing outward, base centered on the edge-clamped position.
	var tip: Vector2 = arrow_pos + direction * arrow_size
	var back: Vector2 = arrow_pos - direction * (arrow_size * 0.3)
	var perp: Vector2 = direction.rotated(PI / 2.0)
	var base_left: Vector2 = back + perp * arrow_size * 0.5
	var base_right: Vector2 = back - perp * arrow_size * 0.5

	var triangle: PackedVector2Array = PackedVector2Array([tip, base_left, base_right])
	draw_colored_polygon(triangle, marker_color)