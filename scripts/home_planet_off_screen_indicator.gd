extends Control
##
## HomePlanetOffScreenIndicator: blue edge-clamped arrow pointing
## toward the home planet when it is off-screen. Pairs with the
## world-space ring in scripts/home_planet_indicator.gd — the ring
## draws in world space (anchored to the planet), this Control draws
## a screen-space edge arrow (clamped at the screen edge).
##
## Same trigger gate as HomePlanetIndicator: only after every
## astronaut in the level has been picked up (the "go home" signal).
## Same blue color as the world-space ring and the astronaut edge
## arrows for cross-indicator consistency.
##
## Pattern mirrors scripts/astronaut_indicators.gd — Controls draw
## markers in screen space using get_viewport().get_canvas_transform()
## to project world positions to screen coordinates. The Control is
## typically a sibling of AstronautIndicators in scenes/hud.tscn so it
## shares the HUD's CanvasLayer and inherits the project's screen-
## space drawing convention.
##

## Distance from the screen edge (in pixels) at which the arrow is
## clamped before drawing. Matches astronaut_indicators.gd's default
## (30.0) for consistent edge positioning across indicators.
@export var edge_padding: float = 30.0

## Color of the edge arrow. Matches the home-planet ring color in
## scripts/home_planet_indicator.gd and the astronaut indicator
## color in scripts/astronaut_indicators.gd so every "this is where
## you should go" indicator in the game shares the same blue.
@export var arrow_color: Color = Color(0.3, 0.6, 1.0)

## Size (in pixels) of the edge-clamped arrow. Slightly larger than
## the astronaut arrow (14 vs 12 px) because the home planet is the
## level's terminal goal — visual weight should match that priority.
@export var arrow_size: float = 14.0

# Cached references — best-effort lookups with graceful degradation.
#
# `_rocket` and `_home_planet` use lazy init in `_process` because
# their groups (`player` and `attractors`) aren't populated until
# rocket.gd and LevelLoader's `_ready` calls fire, which happens
# AFTER this Control's `_ready` (sibling-order semantics). Same bug
# class as scripts/home_planet_indicator.gd's lazy-init pattern.
#
# `_total_astronauts` is derived from the same attractors scan HUD
# uses in scripts/hud.gd:_count_astronauts — no LevelController
# dependency, so this control doesn't need a parent-walk to find
# sibling nodes from another scene.
var _rocket: Node2D = null
var _home_planet: Node2D = null
# -1 sentinel = "not yet counted". A level's total astronaut count
# is fixed at load time (no bodies added/removed at runtime), so we
# only need to scan once.
var _total_astronauts: int = -1


## Each frame: lazy-init any unresolved refs, queue a redraw.
##
## On the first frame the attractors group may still be empty
## (LevelLoader hasn't run yet). All three lookups tolerate this —
## they no-op cleanly and retry on the next frame. The astronaut
## total is cached once the group has at least one body (signals
## LevelLoader has populated), since a level's astronaut count
## can't change at runtime without reloading the level.
func _process(_delta: float) -> void:
	if _rocket == null:
		_rocket = get_tree().get_first_node_in_group("player")
	if _home_planet == null:
		_home_planet = _find_home_planet()
	if _total_astronauts < 0:
		# Try counting, but only commit once the attractors group is
		# non-empty — LevelLoader adds bodies during its own _ready,
		# which can fire AFTER this Control's `_process` starts. The
		# "non-empty group" signal means the loader's add_child pass
		# has at least started; we trust the count from that frame on.
		var group_size := get_tree().get_nodes_in_group("attractors").size()
		if group_size > 0:
			_total_astronauts = _count_astronauts()
	queue_redraw()


## Find the attractor with `is_home == true`. Returns null until the
## attractors group is populated by LevelLoader; caller retries next
## frame. Same scan pattern as scripts/home_planet_indicator.gd.
func _find_home_planet() -> Node2D:
	for body in get_tree().get_nodes_in_group("attractors"):
		if body.get("is_home"):
			return body
	return null


## Count bodies in the attractors group with `has_astronaut = true`.
## Implicit bool coercion handles null (sun has no such property)
## and true uniformly. Mirrors scripts/hud.gd:_count_astronauts.
func _count_astronauts() -> int:
	var n: int = 0
	for body in get_tree().get_nodes_in_group("attractors"):
		if body.get("has_astronaut"):
			n += 1
	return n


## Draw the edge-clamped arrow ONLY IF all four conditions hold:
##   1. Required refs resolved (rocket + home planet).
##   2. Level has at least one astronaut (otherwise there is no
##      "go home" signal to communicate — mirrors HomePlanetIndicator's
##      gate; a zero-astronaut level finishes immediately on launch).
##   3. Every astronaut has been collected (`rocket.picked_up_count`
##      equals the cached level total).
##   4. The home planet is currently OFF-SCREEN. On-screen is the
##      world-space ring's job — drawing both at once would create
##      a duplicate indicator at the same screen edge.
## Otherwise nothing renders.
func _draw() -> void:
	if _rocket == null or _home_planet == null:
		return

	if _total_astronauts <= 0:
		return
	if int(_rocket.get("picked_up_count")) < _total_astronauts:
		return

	# Project the home planet's world position to screen space. Same
	# transform math as scripts/astronaut_indicators.gd:_draw —
	# `canvas_xform` accounts for the active camera's position and zoom.
	var canvas_xform: Transform2D = get_viewport().get_canvas_transform()
	var viewport_size: Vector2 = get_viewport_rect().size
	var screen_pos: Vector2 = canvas_xform * _home_planet.global_position

	# On-screen check uses inclusive bounds (>=0 and <=viewport_size).
	# A home planet exactly at the screen edge is "on-screen" by this
	# definition; only strictly outside triggers the edge arrow.
	var on_screen: bool = (
		screen_pos.x >= 0.0 and screen_pos.x <= viewport_size.x and
		screen_pos.y >= 0.0 and screen_pos.y <= viewport_size.y
	)
	if on_screen:
		return

	# Clamp the off-screen position to just inside the screen edge.
	var clamped_x: float = clamp(screen_pos.x, edge_padding, viewport_size.x - edge_padding)
	var clamped_y: float = clamp(screen_pos.y, edge_padding, viewport_size.y - edge_padding)
	var arrow_pos: Vector2 = Vector2(clamped_x, clamped_y)

	# Direction from clamp position outward toward the off-screen home
	# planet. Triangle tip points along this direction.
	var direction: Vector2 = screen_pos - arrow_pos
	if direction.length_squared() < 0.0001:
		return  # Home planet is essentially at the camera position; nothing useful to draw
	direction = direction.normalized()

	# Triangle: tip pointing outward, base centered on the edge-clamped position.
	var tip: Vector2 = arrow_pos + direction * arrow_size
	var back: Vector2 = arrow_pos - direction * (arrow_size * 0.3)
	var perp: Vector2 = direction.rotated(PI / 2.0)
	var base_left: Vector2 = back + perp * arrow_size * 0.5
	var base_right: Vector2 = back - perp * arrow_size * 0.5

	var triangle: PackedVector2Array = PackedVector2Array([tip, base_left, base_right])
	draw_colored_polygon(triangle, arrow_color)
