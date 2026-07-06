extends Line2D
##
## Predicts the rocket's trajectory. Two modes:
##
## - TRUE (heliocentric): draws the full closed orbital ellipse of the
##   rocket around the sun, computed in closed form from current (r, v).
##   No integration, no jitter — exact at any time scale.
## - ORBITAL (planetocentric): within a planet's SOI, shows the orbit
##   around that planet (analytical ellipse).
##
## Toggle with the configured action (default: Tab).
## `top_level = true` keeps the line in world coordinates.
## The sun's mass is read dynamically each frame — change `sun.mass`
## in the inspector and the trajectory updates without restart.
##

enum Mode { TRUE, ORBITAL }

## Current trajectory mode. Toggle with `toggle_action` (default: Tab).
@export var mode: Mode = Mode.TRUE

## Input action name that toggles between TRUE and ORBITAL modes.
## Default "toggle_trajectory_mode" (the Tab key).
@export var toggle_action: String = "toggle_trajectory_mode"


# TRUE-mode parameters

## Number of segments used when drawing the closed orbital ellipse for
## the trajectory line. Higher = smoother curve but more compute per
## frame. Closed ellipse (not a fading prediction), so 64-128 is plenty.
@export var ellipse_segments: int = 128


# ORBITAL-mode parameters

## SOI = Hill sphere × this fraction. The Hill sphere is the radius at
## which the planet's gravity equals the sun's; we use a fraction of it
## as the SOI cutoff so the inner half is "definitely orbiting the planet"
## and the outer half is transition zone (where the sun starts to dominate).
## 0.5 is the common default.
@export var soi_fraction: float = 0.5

## Number of polygon vertices used to draw the ORBITAL-mode ellipse.
@export var orbit_segments: int = 64


# Visual

## Width of the trajectory line (in pixels). Scales inversely with
## camera zoom so the line stays readable at any zoom level.
@export var line_width: float = 2.0

## Color of the line in TRUE mode (heliocentric closed ellipse).
@export var true_color: Color = Color(1.0, 0.5, 0.5, 0.7)

## Color of the line in ORBITAL mode (planetocentric ellipse).
@export var orbital_color: Color = Color(0.5, 1.0, 0.7, 0.7)


# Time markers — small dots showing where the rocket will be at
# t+interval, t+2*interval, t+3*interval (etc.) along the closed
# orbit. Markers are sampled in world space, projected to screen;
# off-screen markers are dropped (strict visibility).
#
# Implementation: a "conveyor" array tracks each marker's remaining
# time. Each physics tick the counters decrement; when one hits 0,
# it recycles to the next interval. The marker's WORLD position is
# computed via orbit_calculator.compute_state at (GameTime.current +
# time_remaining), so each marker's screen position is exact.

## Time interval (seconds) between consecutive orbit markers.
## Smaller = more markers, denser visual.
@export var time_marker_interval: float = 5.0

## Radius (pixels) of each marker dot.
@export var time_marker_radius: float = 2.5

## Fill color of marker dots. Bright yellow with high alpha to stand
## out against the red TRUE-mode line.
@export var time_marker_color: Color = Color(1.0, 0.95, 0.2, 0.95)

## Edge buffer (pixels) for off-screen marker culling. 0 = strict
## in/out (markers exactly on the edge are dropped).
@export var time_marker_margin: float = 0.0

## Number of markers in the conveyor (e.g., 3 = markers at 5s, 10s, 15s
## in the future with the default time_marker_interval of 5.0).
@export var time_marker_count: int = 3


# Universal gravitational constant for this script (matches planet.gd
# and the rocket — keep them in sync).
const G: float = 1.0

# Floor for distance in gravity calculations to avoid division-by-zero
# in degenerate cases (e.g., the rocket exactly on the sun).
const MIN_DIST: float = 1.0

const TimeMarkerScene: PackedScene = preload("res://scenes/time_marker.tscn")


# Cached reference to the rocket. Read each frame for current position
# and velocity (the closed-form orbit is computed from this).
var rocket: Node2D = null

# Cached reference to the sun (heaviest body in "attractors"). Mass
# is read each frame from sun.mass so inspector tweaks take effect live.
var sun: Node2D = null

# Mirror of sun.mass refreshed each frame. Cached here so the closed-form
# math doesn't have to call .get("mass") per step.
var sun_mass: float = 0.0

# Child CanvasLayer so the time markers draw in screen space
# (independent of camera zoom/position). Created in _ready.
var _time_marker_canvas: CanvasLayer

# The actual TimeMarker Control, child of the CanvasLayer.
var _time_marker: Control

# Time-remaining (seconds) for each conveyor marker. Decrements each
# tick; when it hits 0, the marker is recycled to the next interval.
# Sized by `time_marker_count` in _ready.
var _marker_times: PackedFloat32Array = PackedFloat32Array()

# The planet whose Hill sphere contains the rocket (in ORBITAL mode).
# Instance var so _process can read it across frames. null when not
# within any planet's SOI.
var central_planet: Node2D = null


## Set up top_level, cache rocket/sun, build the time-marker conveyor,
## and create the CanvasLayer + TimeMarker for marker rendering.
func _ready() -> void:
	top_level = true
	width = line_width
	default_color = true_color
	rocket = get_parent()
	sun = _find_sun()

	# Initialize the marker conveyor: each marker represents "the rocket's
	# projected position N seconds in the future." Every frame, each marker's
	# time_remaining ticks down (the marker flows toward the rocket in world
	# space). When a marker reaches 0, it despawns and a new one is spawned
	# at the back (max time). This gives the rocket a continuous "moving
	# target" to plan intercepts against.
	_marker_times.clear()
	for i in time_marker_count:
		_marker_times.append(time_marker_interval * float(i + 1))

	# Create a CanvasLayer so the TimeMarker draws in screen space rather than
	# the Line2D's world space. Without this, the marker goes off-screen whenever
	# the camera moves away from the marker positions.
	_time_marker_canvas = CanvasLayer.new()
	_time_marker_canvas.layer = 100  # render above the HUD (which is at default layer=1)
	add_child(_time_marker_canvas)

	# Create the TimeMarker as a child of the CanvasLayer (in screen space).
	_time_marker = TimeMarkerScene.instantiate()
	_time_marker.marker_radius = time_marker_radius
	_time_marker.marker_color = time_marker_color
	_time_marker_canvas.add_child(_time_marker)


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


## Each frame: scale line width, refresh sun mass, handle toggle, suppress
## while landed, recompute the trajectory, and advance the marker conveyor.
func _process(_delta: float) -> void:
	if rocket == null:
		return

	# Scale line width inversely with camera zoom — keeps the trajectory
	# readable when zoomed out, never thinner than `line_width` when zoomed in.
	var cam := get_viewport().get_camera_2d()
	var zoom_factor: float = clampf(cam.zoom.x, 0.1, 1.0) if cam != null else 1.0
	width = line_width / zoom_factor

	# Refresh sun mass from cached reference — change sun.mass in the
	# inspector and the trajectory picks it up next frame.
	if sun != null:
		sun_mass = float(sun.get("mass"))

	if Input.is_action_just_pressed(toggle_action):
		mode = Mode.ORBITAL if mode == Mode.TRUE else Mode.TRUE

	# No trajectory line or markers while landed — the planet's own orbit
	# line (planettrajectoryline_2d) already shows where the planet is going.
	# The rocket's predicted path adds noise without useful information.
	if rocket.landed:
		points = PackedVector2Array()
		_time_marker.update_positions(PackedVector2Array())
		return

	_update()

	# Marker conveyor: each marker's time_remaining ticks down; when it
	# hits 0, recycle to the next interval so the conveyor always shows
	# markers at "interval, 2*interval, 3*interval" into the future.
	if mode == Mode.ORBITAL and central_planet != null:
		_time_marker.update_positions(PackedVector2Array())
	else:
		for i in range(_marker_times.size()):
			_marker_times[i] -= _delta
			if _marker_times[i] <= 0.0:
				_marker_times[i] = time_marker_interval * float(time_marker_count)

		# Sample each marker at its future time using the closed-form orbit
		# math. Each marker represents the rocket's position at
		# (GameTime.current + time_remaining), so we ask orbit_calculator
		# for that absolute time. Closed-form = no jitter near planets.
		var elements := _compute_elements_from_state(rocket.global_position, rocket.velocity, sun_mass)
		var marker_positions: PackedVector2Array = PackedVector2Array()
		if not elements.is_empty():
			for time_remaining in _marker_times:
				var t_marker: float = GameTime.current + time_remaining
				var state := OrbitCalculator.compute_state(
					elements["perihelion"], elements["aphelion"],
					elements["angle_of_aphelion"], elements["phase"],
					t_marker, sun_mass
				)
				marker_positions.append(state["position"])
		_time_marker.update_positions(_world_to_screen_markers(marker_positions))


## Determine the current mode (TRUE vs ORBITAL) and recompute the trajectory.
## In ORBITAL mode, sets `central_planet` if the rocket is inside a planet's
## SOI; otherwise falls back to TRUE mode even if mode == ORBITAL.
func _update() -> void:
	var attractors := get_tree().get_nodes_in_group("attractors")

	# Find the closest planet whose Hill sphere contains the rocket (if any).
	if sun != null and sun_mass > 0.0:
		var closest_dist: float = INF
		for body in attractors:
			var m: float = float(body.get("mass"))
			if m < sun_mass * 0.5:  # planet (much lighter than sun)
				# Hill sphere: radius at which the planet's gravity equals the sun's.
				var orbital_distance: float = body.global_position.distance_to(sun.global_position)
				var hill: float = orbital_distance * pow(m / (3.0 * sun_mass), 1.0 / 3.0)
				var soi: float = hill * soi_fraction
				var d: float = (rocket.global_position - body.global_position).length()
				if d < soi and d < closest_dist:
					closest_dist = d
					central_planet = body

	if mode == Mode.ORBITAL and central_planet != null:
		default_color = orbital_color
		points = _compute_planetocentric_ellipse(central_planet)
		# ORBITAL mode markers not yet implemented — _process will clear them.
	else:
		default_color = true_color
		# TRUE mode: full closed-form ellipse from current (r, v) state.
		# Closed-form = exact, no jitter near gravity wells, no drift.
		points = _orbit_ellipse(
			rocket.global_position, rocket.velocity,
			sun_mass, ellipse_segments, Vector2.ZERO
		)


## ORBITAL mode: analytical orbit ellipse around a planet (planetocentric
## frame). Same math as TRUE mode but in the planet's reference frame
## (rocket pos/vel relative to planet, gravitational parameter = planet's).
func _compute_planetocentric_ellipse(planet: Node2D) -> PackedVector2Array:
	var planet_pos: Vector2 = planet.global_position
	var planet_vel: Vector2 = Vector2(planet.get("velocity"))

	# Rocket state in planet's reference frame.
	var r: Vector2 = rocket.global_position - planet_pos
	var v: Vector2 = rocket.velocity - planet_vel

	var mu: float = G * float(planet.get("mass"))
	return _orbit_ellipse(r, v, mu, orbit_segments, planet_pos)


## Convert current (r, v) state to orbital elements (perihelion, aphelion,
## angle_of_aphelion, phase) so OrbitCalculator.compute_state can sample
## the orbit at arbitrary future times. Returns empty Dictionary {} if the
## orbit is unbound (epsilon >= 0, i.e., escape velocity or beyond).
func _compute_elements_from_state(r: Vector2, v: Vector2, mu: float) -> Dictionary:
	var dist: float = maxf(r.length(), MIN_DIST)
	var v_sq: float = v.length_squared()

	# Specific orbital energy: negative = bound, positive = unbound.
	var epsilon: float = v_sq / 2.0 - mu / dist
	if epsilon >= 0.0:
		return {}

	# Semi-major axis from vis-viva rearranged.
	var a: float = -mu / (2.0 * epsilon)

	# Eccentricity vector (points toward periapsis from focus).
	var e_vec: Vector2 = ((v_sq - mu / dist) * r - r.dot(v) * v) / mu
	var e: float = e_vec.length()
	var omega: float = atan2(e_vec.y, e_vec.x)

	# True anomaly at current position: angle from +X axis to current
	# position, minus the angle to periapsis direction.
	var nu: float = atan2(r.y, r.x) - omega
	# Wrap to [0, 2π).
	nu = fmod(nu, TAU)
	if nu < 0.0:
		nu += TAU

	# Convert true anomaly → eccentric anomaly → mean anomaly (the
	# "phase" that OrbitCalculator expects at t=0).
	# tan(E/2) = sqrt((1-e)/(1+e)) · tan(ν/2)
	# E = 2 * atan2(sqrt(1-e)·sin(ν/2), sqrt(1+e)·cos(ν/2))
	var E: float = 2.0 * atan2(sqrt(1.0 - e) * sin(nu / 2.0), sqrt(1.0 + e) * cos(nu / 2.0))
	var M: float = E - e * sin(E)  # mean anomaly at epoch

	return {
		"perihelion": a * (1.0 - e),
		"aphelion": a * (1.0 + e),
		"angle_of_aphelion": omega,
		"phase": M
	}


## Compute an analytical orbit ellipse from current position, velocity,
## and `mu` (= G × central_mass). Returns a closed loop (first point
## appended at the end). Falls back to a single point for unbound orbits.
func _orbit_ellipse(r: Vector2, v: Vector2, mu: float, segs: int, offset: Vector2) -> PackedVector2Array:
	var dist: float = maxf(r.length(), MIN_DIST)
	var v_sq: float = v.length_squared()

	var epsilon: float = v_sq / 2.0 - mu / dist
	if epsilon >= 0.0:
		return PackedVector2Array([offset + r])  # unbound (hyperbolic) — just show current point

	var h: float = r.x * v.y - r.y * v.x
	var a: float = -mu / (2.0 * epsilon)

	var e_vec: Vector2 = ((v_sq - mu / dist) * r - r.dot(v) * v) / mu
	var e: float = e_vec.length()
	var omega: float = atan2(e_vec.y, e_vec.x)

	var pts := PackedVector2Array()
	var one_minus_e_sq: float = 1.0 - e * e
	for i in segs:
		var theta: float = TAU * float(i) / float(segs)
		var r_orbit: float = a * one_minus_e_sq / (1.0 + e * cos(theta - omega))
		pts.append(offset + Vector2(r_orbit * cos(theta), r_orbit * sin(theta)))
	pts.append(pts[0])  # close the loop — last sample is at theta = (n-1)/n * TAU, missing the segment back to 0
	return pts


## Convert a list of world-space marker positions to screen-space,
## including only those that fall within the viewport (with optional
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