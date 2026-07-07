extends Line2D
##
## Predicts the rocket's trajectory. Two modes (toggle with Tab):
##
## - ELLIPSE: closed-form orbital prediction. Auto-switches to the nearest
##   planet's orbit when the rocket is inside its SOI (Hill sphere ×
##   soi_fraction); otherwise shows the heliocentric sun orbit. No
##   integration, no jitter — exact at any time scale.
## - PROJECTED: forward-simulated trajectory under sun + every planet's
##   gravity (planet positions sampled via closed-form math at each step).
##   Shows what actually happens with perturbations, slingshots, etc.
##
## `top_level = true` keeps the line in world coordinates.
## The sun's mass is read dynamically each frame.
##

enum Mode { ELLIPSE, PROJECTED }

## Current trajectory mode. Toggle with `toggle_action` (default: Tab).
@export var mode: Mode = Mode.ELLIPSE

## Input action name that toggles between ELLIPSE and PROJECTED modes.
## Default "toggle_trajectory_mode" (the Tab key).
@export var toggle_action: String = "toggle_trajectory_mode"


# ELLIPSE-mode parameters

## Number of segments used when drawing the closed orbital ellipse for
## the trajectory line. Higher = smoother curve but more compute per
## frame. Closed ellipse (not a fading prediction), so 64-128 is plenty.
@export var ellipse_segments: int = 128

## SOI = Hill sphere × this fraction. The Hill sphere is the radius at
## which the planet's gravity equals the sun's; we use a fraction of it
## as the SOI cutoff so the inner half is "definitely orbiting the planet"
## and the outer half is transition zone (where the sun starts to dominate).
## 0.5 is the common default. Used by ELLIPSE mode to auto-switch to
## the planet orbit when the rocket is in range.
@export var soi_fraction: float = 0.5


# PROJECTED-mode parameters

## Number of simulation steps for PROJECTED-mode forward sim.
## Higher = longer predicted path but more compute per frame.
@export var projected_steps: int = 300

## Time step (seconds) per PROJECTED-mode simulation step. The total
## predicted time is projected_steps * projected_step_dt (default: 15s).
@export var projected_step_dt: float = 0.05


# Visual

## Width of the trajectory line (in pixels). Scales inversely with
## camera zoom so the line stays readable at any zoom level.
@export var line_width: float = 2.0

## ELLIPSE mode color when showing the heliocentric sun orbit.
@export var closed_form_sun_color: Color = Color(1.0, 0.5, 0.5, 0.7)

## ELLIPSE mode color when showing a planet orbit (auto-switched when
## the rocket is inside the planet's SOI).
@export var closed_form_planet_color: Color = Color(0.5, 1.0, 0.7, 0.7)

## PROJECTED mode color (forward-simulated trajectory with all gravity).
@export var projected_color: Color = Color(0.4, 0.7, 1.0, 0.7)


# Time markers — small dots showing where the rocket will be at
# t+interval, t+2*interval, t+3*interval (etc.) along the projected
# trajectory. PROJECTED mode only: ELLIPSE mode relies on the closed-form
# ellipse itself to convey the orbital path, so extra dot markers would
# clutter the visualization without adding information.
#
# Implementation: a "conveyor" array tracks each marker's remaining
# time. Each physics tick the counters decrement; when one hits 0,
# it recycles to the next interval. Off-screen markers are dropped.

## Time interval (seconds) between consecutive orbit markers.
## Smaller = more markers, denser visual.
@export var time_marker_interval: float = 5.0

## Radius (pixels) of each marker dot.
@export var time_marker_radius: float = 2.5

## Fill color of marker dots. Bright yellow with high alpha to stand
## out against both the red ELLIPSE-sun line and the blue PROJECTED line.
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
# and velocity (the trajectory is computed from this).
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

# The planet whose Hill sphere contains the rocket. Used by ELLIPSE
# mode to auto-switch between sun and planet orbits. null when not
# within any planet's SOI.
var central_planet: Node2D = null


## Set up top_level, cache rocket/sun, build the time-marker conveyor,
## and create the CanvasLayer + TimeMarker for marker rendering.
func _ready() -> void:
	top_level = true
	width = line_width
	default_color = closed_form_sun_color
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

	# Lazy-init sun: trajectoryline._ready runs BEFORE LevelLoader._ready
	# in scene-tree order, so _find_sun() returns null on the first frame.
	# Retry each frame until found; cheap (one group lookup, one pass).
	if sun == null:
		sun = _find_sun()

	# Refresh sun mass from cached reference — change sun.mass in the
	# inspector and the trajectory picks it up next frame.
	if sun != null:
		sun_mass = float(sun.get("mass"))

	if Input.is_action_just_pressed(toggle_action):
		mode = Mode.PROJECTED if mode == Mode.ELLIPSE else Mode.ELLIPSE

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
	for i in range(_marker_times.size()):
		_marker_times[i] -= _delta
		if _marker_times[i] <= 0.0:
			_marker_times[i] = time_marker_interval * float(time_marker_count)

	# PROJECTED mode only: sample indices into the forward-simulated
	# polyline (shows perturbations from planet gravity). ELLIPSE mode
	# leaves marker_positions empty — the ellipse itself is the path.
	var marker_positions: PackedVector2Array = PackedVector2Array()
	if mode == Mode.PROJECTED and not points.is_empty():
		for time_remaining in _marker_times:
			var index: int = clampi(int(time_remaining / projected_step_dt), 0, points.size() - 1)
			marker_positions.append(points[index])

	_time_marker.update_positions(_world_to_screen_markers(marker_positions))


## Detect central_planet (rocket inside a planet's SOI) and recompute
## the trajectory for the current mode. In ELLIPSE mode, auto-switch
## between sun orbit and planet orbit based on SOI membership.
func _update() -> void:
	var attractors := get_tree().get_nodes_in_group("attractors")

	# Detect central_planet: rocket inside this planet's SOI (Hill sphere × soi_fraction).
	# Used by ELLIPSE mode to auto-switch between sun and planet orbits.
	central_planet = null
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

	match mode:
		Mode.ELLIPSE:
			# Auto-switch: if rocket is in a planet's SOI, show that planet's
			# orbit; otherwise show the heliocentric sun orbit. The user doesn't
			# need to toggle ORBITAL manually — happens automatically based on
			# proximity.
			if central_planet != null:
				default_color = closed_form_planet_color
				points = _compute_planetocentric_ellipse(central_planet)
			else:
				default_color = closed_form_sun_color
				points = _orbit_ellipse(
					rocket.global_position, rocket.velocity,
					sun_mass, ellipse_segments, Vector2.ZERO
				)
		Mode.PROJECTED:
			default_color = projected_color
			points = _simulate_projected(attractors)


## ORBITAL-mode helper (within ELLIPSE): analytical orbit ellipse around
## a planet (planetocentric frame). Same math as the sun-orbit ellipse
## but in the planet's reference frame.
func _compute_planetocentric_ellipse(planet: Node2D) -> PackedVector2Array:
	var planet_pos: Vector2 = planet.global_position
	var planet_vel: Vector2 = Vector2(planet.get("velocity"))

	# Rocket state in planet's reference frame.
	var r: Vector2 = rocket.global_position - planet_pos
	var v: Vector2 = rocket.velocity - planet_vel

	var mu: float = G * float(planet.get("mass"))
	return _orbit_ellipse(r, v, mu, ellipse_segments, planet_pos)


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


## Forward-simulate the rocket under sun + every planet's gravity.
## Planet positions are sampled at each future time via the closed-form
## orbit math (so planet motion is exact), and the rocket is integrated
## with symplectic Euler (sufficient for visualization; the planet-motion
## precision means the dominant error source is the rocket itself, which
## we'd need a much smaller step_dt to reduce further).
##
## Returns a polyline at projected_step_dt intervals from t=0 to
## t=projected_steps * projected_step_dt.
##
## This shows the trajectory the rocket would ACTUALLY take, including
## perturbations, slingshots, etc. — distinct from ELLIPSE mode which
## shows the idealized 2-body orbit.
func _simulate_projected(attractors: Array) -> PackedVector2Array:
	if sun == null or sun_mass <= 0.0:
		return PackedVector2Array()

	# Cache each planet's orbital elements once (avoid re-reading each step).
	var planet_specs: Array = []
	for body in attractors:
		if body == sun or body == rocket:
			continue
		var m: float = float(body.get("mass"))
		if m <= 0.0:
			continue
		planet_specs.append({
			"mass": m,
			"perihelion": float(body.get("perihelion")),
			"aphelion": float(body.get("aphelion")),
			"angle_of_aphelion": float(body.get("angle_of_aphelion")),
			"phase": float(body.get("phase"))
		})

	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(rocket.global_position)

	var r: Vector2 = rocket.global_position
	var v: Vector2 = rocket.velocity

	var dt: float = projected_step_dt
	for i in projected_steps:
		# Acceleration from the sun.
		var to_sun: Vector2 = -r
		var r_sun: float = maxf(to_sun.length(), MIN_DIST)
		var a: Vector2 = to_sun.normalized() * (G * sun_mass / (r_sun * r_sun))

		# Acceleration from each planet (planet position sampled at this future time).
		for spec in planet_specs:
			var t_future: float = GameTime.current + float(i + 1) * dt
			var state: Dictionary = OrbitCalculator.compute_state(
				spec["perihelion"], spec["aphelion"],
				spec["angle_of_aphelion"], spec["phase"],
				t_future, sun_mass
			)
			var planet_pos: Vector2 = state["position"]
			var to_planet: Vector2 = planet_pos - r
			var r_p: float = maxf(to_planet.length(), MIN_DIST)
			a += to_planet.normalized() * (G * spec["mass"] / (r_p * r_p))

		# Symplectic Euler integration. Velocity Verlet would be slightly
		# more accurate but not worth the added complexity for visualization.
		v += a * dt
		r += v * dt
		pts.append(r)

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
