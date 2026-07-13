extends Node2D
##
## HomePlanetIndicator: pulsing blue ring around the home planet
## (`is_home == true`), shown only when every astronaut in the level
## has been picked up. Tells the player "land here to finish the level."
##
## Pattern follows scripts/soi_indicator.gd — Node2D drawn in world
## space, ring radius scaled by the home planet's collision/visual
## radius, border width scaled inversely with camera zoom so the line
## stays visually constant regardless of zoom level.
##
## Tree placement: added to scenes/level.tscn right after SoiIndicator
## and BEFORE SunContainer / BodyContainer so the home planet draws ON
## TOP of the ring (the ring ends up as a halo around the planet, not
## a flat disk over it). See scenes/level.tscn for node order.
##

## Toggle visibility per-instance. Useful for disabling in a level
## editor preview where the indicator would be distracting during
## normal editing.
@export var enabled: bool = true

## Color of the pulsing ring. Blue, matching the astronaut marker
## color in scripts/astronaut_indicators.gd for visual consistency
## across the game's "look for this" indicators.
@export var ring_color: Color = Color(0.3, 0.6, 1.0)

## Ring radius as a multiple of the home planet's collision/visual
## radius. 1.5 = ring is 50% larger than the planet, leaving a clear
## gap between the planet's edge and the ring's inner edge.
@export var ring_radius_multiplier: float = 1.5

## Border width in pixels (before camera-zoom scaling). The drawn
## width is `ring_width / camera_zoom`, matching the scheme used in
## scripts/soi_indicator.gd — keeps the line visually constant at
## any zoom level.
@export var ring_width: float = 3.0

## Pulse oscillation as a fraction of the base ring radius.
## 0.15 = ring radius varies between 0.85× and 1.15× its base size.
@export var pulse_amount: float = 0.15

## Pulse speed in Hz (cycles per second). 1.5 = the ring completes
## one full size cycle 1.5 times per second — slow enough to read
## as a pulse, fast enough to feel alive.
@export var pulse_speed: float = 1.5

## Number of segments used to approximate the ring. 48 is plenty
## for smooth visual use; higher numbers cost more draw vertices
## without visible quality gain at this radius range.
@export var circle_segments: int = 48


# Cached references. Best-effort lookups — graceful warnings rather
# than crashes if anything is missing. `_level_controller` resolves
# immediately in `_ready` (LevelController is a sibling node always
# present in the scene tree). `_rocket` and `_home_planet` lazy-init
# in `_process` because their respective groups ("player" and
# "attractors") aren't populated until later in the init order.
var _home_planet: Node2D = null
var _rocket: Node2D = null
var _level_controller: Node = null

# Pulse clock. Increments every frame and feeds the sin() that drives
# the ring's size oscillation.
var _time: float = 0.0


## Cache the level_controller reference. LevelController is a sibling
## node in scenes/level.tscn — findable via path even before its own
## `_ready()` fires. The rocket and home planet use lazy init in
## `_process` because their groups ("player" / "attractors") aren't
## populated until rocket.gd and LevelLoader's `_ready` calls fire,
## which may happen after this one depending on sibling-order semantics.
func _ready() -> void:
	_level_controller = get_parent().get_node_or_null("LevelController")
	if _level_controller == null:
		push_warning("HomePlanetIndicator: no LevelController sibling found")


## Each frame: advance pulse clock, lazy-init rocket + home planet,
## queue redraw. Lazy-init mirrors scripts/soi_indicator.gd's sun
## lookup — on the first frame after level load, the groups may not
## be populated yet. Cheap (one group query each) and runs only until
## each reference is found.
func _process(delta: float) -> void:
	if not enabled:
		return
	_time += delta
	if _rocket == null:
		_rocket = get_tree().get_first_node_in_group("player")
	if _home_planet == null:
		_home_planet = _find_home_planet()
	queue_redraw()


## Find the body with `is_home == true` in the `attractors` group.
## Returns null if not found yet — caller retries next frame. Cheap:
## one group query + a short scan, only runs once per indicator
## lifetime thanks to the lazy-init guard in _process.
func _find_home_planet() -> Node2D:
	for body in get_tree().get_nodes_in_group("attractors"):
		if body.get("is_home"):
			return body
	return null


## Draw the pulsing ring if all astronauts are picked up. Otherwise
## nothing renders. World-space coordinates — Node2D's identity
## transform means local == world, so `draw_arc`'s radius is in
## world units and naturally scales with camera zoom.
##
## Visibility gates (in evaluation order):
##   1. `enabled` — per-instance kill switch.
##   2. Home planet / rocket / level_controller resolved — can't draw
##      without all three.
##   3. `total_astronauts > 0` — a level with zero astronauts has no
##      "go home" signal to show.
##   4. `picked_up_count >= total_astronauts` — the actual reason this
##      indicator exists.
func _draw() -> void:
	if not enabled:
		return
	if _home_planet == null or _rocket == null or _level_controller == null:
		return

	var total: int = int(_level_controller.get("total_astronauts"))
	if total <= 0:
		return
	if int(_rocket.get("picked_up_count")) < total:
		return

	# Pulse: ring radius oscillates around base_radius via sin().
	# _time is in seconds, pulse_speed is Hz, so _time * pulse_speed * TAU
	# is the angle in radians that completes a full cycle 1.5 times/sec
	# at the default pulse_speed.
	var base_radius: float = float(_home_planet.get("radius")) * ring_radius_multiplier
	var pulse: float = 1.0 + pulse_amount * sin(_time * pulse_speed * TAU)
	var ring_radius: float = base_radius * pulse

	# Border width scales inversely with camera zoom so the line
	# stays visually constant regardless of zoom level. Clamp avoids
	# division blowup at extreme zoom-out (zoom < 0.1). Same scheme
	# as scripts/soi_indicator.gd.
	var cam := get_viewport().get_camera_2d()
	var zoom_factor: float = clampf(cam.zoom.x, 0.1, 1.0) if cam != null else 1.0
	var scaled_width: float = ring_width / zoom_factor

	draw_arc(_home_planet.global_position, ring_radius, 0.0, TAU,
		circle_segments, ring_color, scaled_width, true)