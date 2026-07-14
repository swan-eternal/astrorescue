extends Line2D
##
## Draws the planet's orbital ellipse (sun-only 2-body orbit).
## Computed analytically from the planet's current position and velocity.
## The sun's mass is read dynamically each frame — change `sun.mass` in
## the inspector and the ellipse updates without restart.
##

## Number of polygon vertices used to approximate the orbit ellipse.
## Higher = smoother but slower to compute. 64 is plenty for visual use.
@export var segments: int = 64

## Width of the orbit ellipse line (in pixels). Scales with camera zoom
## so the line stays visible at any zoom level (see _process).
@export var line_width: float = 1.0

## Alpha (0–1) applied to the ellipse color, blended from the parent
## planet's color. 0.5 keeps the orbit visible without dominating the
## planet itself.
@export var default_alpha: float = 0.5

# Time markers — small dots at fixed time intervals around the planet's
# orbit ellipse showing "where the planet will be at time T" for planning.
# Markers are drawn in screen space, but only when their projected screen
# position is within the viewport. Off-screen markers are dropped.

## Time interval (in seconds) between consecutive orbit markers.
## Smaller = more markers, denser visual.
@export var time_marker_interval: float = 10.0

## Radius (in pixels) of each orbit marker dot.
@export var time_marker_radius: float = 4.0

## Fill color of the orbit markers. Bright yellow for high contrast
## against the dark space background.
@export var time_marker_color: Color = Color(1.0, 0.95, 0.2, 0.95)

## Edge buffer (in pixels) for off-screen marker culling. 0 = strict
## in/out (markers exactly on the edge are dropped). Increase to hide
## markers that would crowd the screen edge.
@export var time_marker_margin: float = 0.0

# Local alias for the project-wide gravity constant (PhysicsConstants.G).
const G: float = PhysicsConstants.G

# Local alias for the gravity / orbit distance floor (PhysicsConstants.MIN_DIST).
const MIN_DIST: float = PhysicsConstants.MIN_DIST

const TimeMarkerScene: PackedScene = preload("res://scenes/time_marker.tscn")


# Cached reference to the parent planet. Read each frame to get position
# and velocity for the ellipse calculation.
var planet: Node2D = null

# Cached reference to the sun (heaviest body in "attractors"). Mass is
# read each frame from sun.mass so inspector tweaks take effect live.
var sun: Node2D = null

# Internal CanvasLayer so the time markers draw in screen space
# (independent of camera zoom/position). Created in _ready.
var _time_marker_canvas: CanvasLayer

# The actual TimeMarker Control, child of the CanvasLayer. Its
# update_positions() is called every frame with the new marker list.
var _time_marker: Control


## Initialize top_level (for world-space positioning), cache the parent
## planet + sun, set the line color (from the planet's color at
## default_alpha), and create the CanvasLayer + TimeMarker for the
## orbit-marker dots.
func _ready() -> void:
	top_level = true
	width = line_width
	planet = get_parent()
	sun = _find_sun()

	var planet_color: Color = Color(planet.get("color"))
	planet_color.a = default_alpha
	default_color = planet_color

	# Create a CanvasLayer for screen-space marker rendering.
	_time_marker_canvas = CanvasLayer.new()
	_time_marker_canvas.layer = 100
	add_child(_time_marker_canvas)

	# Create the TimeMarker as a child of the CanvasLayer (in screen space).
	_time_marker = TimeMarkerScene.instantiate()
	_time_marker.marker_radius = time_marker_radius
	_time_marker.marker_color = time_marker_color
	_time_marker_canvas.add_child(_time_marker)


## Each frame: recompute the orbit ellipse from current planet state
## (position, velocity, sun mass) and update the time markers.
## Skips silently if either the planet or the sun reference is null
## (e.g., during scene teardown).
func _process(_delta: float) -> void:
	if planet == null:
		return

	# Lazy-init sun: in current levels the sun is added to the scene
	# before each planet (because _load_level iterates bodies[] in JSON
	# order, and JSON puts the sun first), so _ready's _find_sun usually
	# succeeds. This is a defensive mirror of trajectoryline_2d.gd's
	# lazy-init — if a future level reverses the order, the planet
	# orbit still finds the sun on the next frame instead of going dark.
	if sun == null:
		sun = _find_sun()
	if sun == null:
		return

	# Scale line width inversely with camera zoom — same scheme as the player
	# trajectory line, so all orbit ellipses stay readable when zoomed out.
	var cam := get_viewport().get_camera_2d()
	var zoom_factor: float = clampf(cam.zoom.x, 0.1, 1.0) if cam != null else 1.0
	width = line_width / zoom_factor

	var sun_mass: float = float(sun.get("mass"))
	points = _compute_orbit_ellipse_from_elements(sun_mass)
	_time_marker.update_positions(_world_to_screen_markers(_compute_orbit_markers()))


## Find the sun = heaviest body in the "attractors" group.
## Returns null if no attractors yet (early frame).
func _find_sun() -> Node2D:
	var attractors := get_tree().get_nodes_in_group("attractors")
	var heaviest: Node2D = null
	var heaviest_mass := 0.0
	for body in attractors:
		var m: float = float(body.get("mass"))
		if m > heaviest_mass:
			heaviest_mass = m
			heaviest = body
	return heaviest


## Compute the orbit ellipse by sampling OrbitCalculator.compute_state at
## evenly-spaced times around one orbital period. Uses the planet's own
## perihelion/aphelion/angle_of_aphelion/phase @exports as constants
## rather than deriving orbital elements from the current (r, v) state.
##
## Why derive-from-state is wrong here: it computes orbital elements like
## the argument of periapsis (omega = atan2(eccentricity_vec.y, .x)) on
## every frame, and the eccentricity vector itself is computed from r and v
## which come from Newton-Raphson Kepler solver iterations with machine-
## epsilon precision. Frame-to-frame the derived omega wobbles by ~1e-7
## radians. At low time-warp (1×, 2×) this is invisible. At high time-warp
## (8×) the planet moves fast across the orbit while the line "rocks" with
## each per-frame wobble — the visual is a slow breathing pulse.
##
## Sampling OrbitCalculator.compute_state directly with constant elements
## eliminates the wobble: the line is identical frame-to-frame modulo any
## inspector edits to the elements themselves.
func _compute_orbit_ellipse_from_elements(sun_mass: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if sun_mass <= 0.0:
		return pts
	var perihelion: float = float(planet.get("perihelion"))
	var aphelion: float = float(planet.get("aphelion"))
	var omega: float = float(planet.get("angle_of_aphelion"))
	var phase: float = float(planet.get("phase"))
	if perihelion <= 0.0 or aphelion <= 0.0:
		return pts
	var period: float = OrbitCalculator.compute_period(perihelion, aphelion, sun_mass)
	if period <= 0.0:
		return pts
	# Sample evenly across one period. Use segments+1 points so the last
	# sample (at t = period) duplicates the first (at t = 0), closing the
	# loop cleanly — same shape Line2D sees as before.
	for i in segments + 1:
		var t: float = period * float(i) / float(segments)
		var state: Dictionary = OrbitCalculator.compute_state(
			perihelion, aphelion, omega, phase, t, sun_mass
		)
		pts.append(state["position"])
	return pts


## Compute world positions of dots placed at fixed time intervals
## around the planet's orbit. Uses a linear time↔angle mapping (good
## enough for nearly-circular orbits, the case for current levels).
## Returns an empty array if any required input is missing/zero.
func _compute_orbit_markers() -> PackedVector2Array:
	var markers: PackedVector2Array = PackedVector2Array()
	if time_marker_interval <= 0.0 or points.is_empty() or sun == null or planet == null:
		return markers
	var sun_mass_val: float = float(sun.get("mass"))
	if sun_mass_val <= 0.0:
		return markers
	# Read orbital elements instead of the legacy orbit_radius @export
	# (which was removed in Stage 2 when planet.gd switched to closed-form
	# orbital elements). Semi-major axis = average of perihelion/aphelion.
	# For circular orbits perihelion == aphelion == a; for elliptical this
	# gives the correct average.
	var perihelion: float = float(planet.get("perihelion"))
	var aphelion: float = float(planet.get("aphelion"))
	if perihelion <= 0.0 or aphelion <= 0.0:
		return markers
	var a: float = (perihelion + aphelion) / 2.0
	var period: float = TAU * sqrt(a * a * a / (G * sun_mass_val))
	if period <= 0.0:
		return markers
	var step_index: int = max(1, int(round(time_marker_interval * float(segments) / period)))
	var i: int = step_index
	while i < segments:
		markers.append(points[i])
		i += step_index
	return markers


## Convert a list of world-space marker positions to screen-space,
## INCLUDING only those that fall within the viewport (with optional
## edge buffer). Off-screen markers are dropped, not clamped — strict
## visibility.
func _world_to_screen_markers(world_positions: PackedVector2Array) -> PackedVector2Array:
	var canvas_xform: Transform2D = get_viewport().get_canvas_transform()
	var viewport_size: Vector2 = get_viewport_rect().size
	var screen_positions: PackedVector2Array = PackedVector2Array()
	for world_pos in world_positions:
		var screen_pos: Vector2 = canvas_xform * world_pos
		if screen_pos.x >= time_marker_margin and \
					screen_pos.x <= viewport_size.x - time_marker_margin and \
					screen_pos.y >= time_marker_margin and \
					screen_pos.y <= viewport_size.y - time_marker_margin:
			screen_positions.append(screen_pos)
	return screen_positions
