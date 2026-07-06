extends Line2D
##
## Predicts the rocket's trajectory. Two modes:
##
## - TRUE (heliocentric): forward-simulates gravity in the sun's frame.
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

## Number of simulation steps to run for the TRUE-mode forward sim.
## Higher = longer predicted path but more compute per frame.
@export var steps: int = 300

## Time step (seconds) per TRUE-mode simulation step. Smaller = more
## accurate but more compute; 0.05 gives ~15s of lookahead at default.
@export var step_dt: float = 0.05

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

## Color of the line in TRUE mode (heliocentric forward simulation).
@export var true_color: Color = Color(1.0, 0.5, 0.5, 0.7)

## Color of the line in ORBITAL mode (planetocentric ellipse).
@export var orbital_color: Color = Color(0.5, 1.0, 0.7, 0.7)

# Time markers — small dots at fixed time intervals along the trajectory
# (TRUE mode only) showing "where will I be at time T" for planning burns.
# Markers are drawn in screen space, but only when their projected screen
# position is within the viewport. Markers that would land off-screen are
# dropped (don't show at the edge, don't show at all) so the trajectory
# line stays clean when the camera is far from the action.

## Time interval (in seconds) between TRUE-mode time markers. Smaller
## = more markers, denser visual.
@export var time_marker_interval: float = 5.0

## Radius (in pixels) of each TRUE-mode time marker dot.
@export var time_marker_radius: float = 2.5

## Fill color of TRUE-mode time markers. Bright yellow with high alpha
## to stand out against the red TRUE-mode line.
@export var time_marker_color: Color = Color(1.0, 0.95, 0.2, 0.95)

## Edge buffer (in pixels) for off-screen marker culling. 0 = strict
## in/out (markers exactly on the edge are dropped).
@export var time_marker_margin: float = 0.0

# Marker conveyor: each marker is at "rocket's projected position N seconds
# in the future" where N is its time_remaining. Every frame, time_remaining
# ticks down (markers flow toward the rocket). When a marker reaches 0, it
# despawns and a new one is spawned at the back (max time). This gives the
# rocket a continuous "moving target" to plan intercepts against.

## Number of markers in the conveyor (e.g., 3 = markers at 5s, 10s, 15s
## in the future with the default time_marker_interval of 5.0).
@export var time_marker_count: int = 3

# Universal gravitational constant for this script (matches planet.gd
# and the rocket — keep them in sync).
const G := 1.0

# Floor used to avoid division by zero in gravity calculations when r
# is very small (e.g., rocket exactly on top of a planet, which is a
# degenerate case anyway).
const MIN_DIST := 1.0

const TimeMarkerScene: PackedScene = preload("res://scenes/time_marker.tscn")


# Internal "ghost planet" for TRUE-mode forward simulation. Holds the
# position/velocity/accel used by the integrator (separate from the
# real planets so the simulation doesn't disturb the actual scene).
class _PlanetSim:
	var pos: Vector2
	var vel: Vector2
	var acc: Vector2
	var mass: float

	func _init(p: Vector2, v: Vector2, m: float) -> void:
		pos = p
		vel = v
		mass = m
		acc = Vector2.ZERO


# Cached reference to the rocket. Read each frame for current position
# and velocity (the simulation's initial conditions).
var rocket: Node2D = null

# Cached reference to the sun (heaviest body in "attractors"). The mass
# is read each frame from sun.mass so inspector tweaks take effect live.
var sun: Node2D = null

# Mirror of sun.mass refreshed each frame in _process. Cached here so
# the integrator in _update doesn't have to call .get("mass") per step.
var sun_mass: float = 0.0

# Child CanvasLayer so the time markers draw in screen space
# (independent of camera zoom/position). Created in _ready.
var _time_marker_canvas: CanvasLayer

# The actual TimeMarker Control, child of the CanvasLayer.
var _time_marker: Control

# Time-remaining (seconds) for each conveyor marker; decreases each
# tick. When it hits 0, the marker is "recycled" back to the back of
# the conveyor (max time). Sized by `time_marker_count` in _ready.
var _marker_times: PackedFloat32Array = PackedFloat32Array()

# The planet whose Hill sphere contains the rocket (in ORBITAL mode).
# Instance var so _process can read it across frames. null when not
# within any planet's SOI.
var central_planet: Node2D = null


## Initialize top_level (world-space positioning), cache the rocket +
## sun, build the time-marker conveyor array, and create the CanvasLayer
## + TimeMarker for the marker dots.
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


## Each frame: scale line width for current zoom, refresh sun_mass from
## the cached reference, handle the mode-toggle input, suppress output
## while the rocket is landed, recompute the trajectory, and advance
## the time-marker conveyor.
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
	# (planettrajectoryline_2d) already shows where the planet is going. The
	# rocket's predicted path is just tangent to the orbit and adds noise
	# without useful information.
	if rocket.landed:
		points = PackedVector2Array()
		_time_marker.update_positions(PackedVector2Array())
		return

	_update()

	# Marker conveyor: each marker is at "rocket's projected position N
	# seconds in the future" where N is its time_remaining. Every frame,
	# decrement time_remaining (markers flow toward the rocket). When a marker
	# reaches time_remaining <= 0, it despawns and a new one is spawned at
	# the back (max time = time_marker_interval * time_marker_count).
	if mode == Mode.ORBITAL and central_planet != null:
		_time_marker.update_positions(PackedVector2Array())
	else:
		for i in range(_marker_times.size()):
			_marker_times[i] -= _delta
			if _marker_times[i] <= 0.0:
				_marker_times[i] = time_marker_interval * float(time_marker_count)

		# Compute marker positions from the current trajectory. `points` (just
		# recomputed in _update above) is time-ordered at step_dt intervals.
		# We pick `points[index]` for each marker where index is the integer
		# time-remaining offset in step_dt units.
		var marker_positions: PackedVector2Array = PackedVector2Array()
		for time_remaining in _marker_times:
			var index: int = int(time_remaining / step_dt)
			if index < 0:
				index = 0
			elif index >= points.size():
				index = points.size() - 1
			marker_positions.append(points[index])
		_time_marker.update_positions(_world_to_screen_markers(marker_positions))


## Determine the current mode (TRUE vs ORBITAL) and recompute the
## trajectory points. In ORBITAL mode, sets `central_planet` if the
## rocket is inside a planet's SOI; otherwise falls back to TRUE mode
## even if mode == ORBITAL.
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
		points = _simulate_heliocentric(attractors)
		# Markers are updated in _process (with snapshot support).


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
		# Strict in/out: only include if within the viewport (with optional margin).
		if screen_pos.x >= time_marker_margin and \
		   screen_pos.x <= viewport_size.x - time_marker_margin and \
		   screen_pos.y >= time_marker_margin and \
		   screen_pos.y <= viewport_size.y - time_marker_margin:
			screen_positions.append(screen_pos)
	return screen_positions


## ORBITAL mode: analytical orbit ellipse around a planet (in the
## planet's frame). Returns points relative to world origin (the
## `offset` param shifts them by the planet's world position).
func _compute_planetocentric_ellipse(planet: Node2D) -> PackedVector2Array:
	var planet_pos: Vector2 = planet.global_position
	var planet_vel: Vector2 = Vector2(planet.get("velocity"))

	# Rocket state in planet's reference frame.
	var r: Vector2 = rocket.global_position - planet_pos
	var v: Vector2 = Vector2(rocket.get("velocity")) - planet_vel

	var mu: float = G * float(planet.get("mass"))
	return _orbit_ellipse(r, v, mu, orbit_segments, planet_pos)


## TRUE mode: forward simulation in the sun's frame, planets simulated
## too (as ghost _PlanetSim copies that don't affect the actual scene).
## Uses Velocity Verlet integration for stability over many steps.
func _simulate_heliocentric(attractors: Array) -> PackedVector2Array:
	var planets: Array = []
	for body in attractors:
		var m: float = float(body.get("mass"))
		if m < sun_mass * 0.5:
			planets.append(_PlanetSim.new(
	body.global_position,
	Vector2(body.get("velocity")),
	m
		))

	var r_pos: Vector2 = rocket.global_position
	var r_vel: Vector2 = Vector2(rocket.get("velocity"))
	var r_acc: Vector2 = _rocket_accel(r_pos, planets)
	for p in planets:
		p.acc = _planet_accel(p.pos)

	var pts := PackedVector2Array()
	pts.append(r_pos)

	for i in steps:
		for p in planets:
			var new_pos: Vector2 = p.pos + p.vel * step_dt + 0.5 * p.acc * step_dt * step_dt
			var new_acc: Vector2 = _planet_accel(new_pos)
			var new_vel: Vector2 = p.vel + 0.5 * (p.acc + new_acc) * step_dt
			p.pos = new_pos
			p.vel = new_vel
			p.acc = new_acc

		var new_r_pos: Vector2 = r_pos + r_vel * step_dt + 0.5 * r_acc * step_dt * step_dt
		var new_r_acc: Vector2 = _rocket_accel(new_r_pos, planets)
		var new_r_vel: Vector2 = r_vel + 0.5 * (r_acc + new_r_acc) * step_dt
		r_pos = new_r_pos
		r_vel = new_r_vel
		r_acc = new_r_acc

		pts.append(r_pos)

	return pts


## Compute an analytical orbit ellipse from current position, velocity,
## and `mu` (= G × central_mass). Used by both the planet orbit lines
## and the rocket's ORBITAL mode. Returns a closed loop (first point
## appended at the end). Falls back to a single point for unbound orbits.
func _orbit_ellipse(r: Vector2, v: Vector2, mu: float, segs: int, offset: Vector2) -> PackedVector2Array:
	var dist: float = maxf(r.length(), MIN_DIST)
	var v_sq: float = v.length_squared()

	var epsilon: float = v_sq / 2.0 - mu / dist
	if epsilon >= 0.0:
		return PackedVector2Array([offset + r])

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
	pts.append(pts[0])  # close the loop — same missing-segment issue as the planet orbit ellipses
	return pts


## Acceleration on a planet at `pos` due to the sun (only — planets
## don't feel each other in this simulation). Used inside _simulate_heliocentric.
func _planet_accel(pos: Vector2) -> Vector2:
	var to_sun := -pos
	var r := maxf(to_sun.length(), MIN_DIST)
	return to_sun.normalized() * (G * sun_mass / (r * r))


## Acceleration on the rocket at `pos` due to the sun + every simulated
## planet (ghost _PlanetSim copies). Used inside _simulate_heliocentric.
func _rocket_accel(pos: Vector2, planets: Array) -> Vector2:
	var total := Vector2.ZERO

	var to_sun := -pos
	var r_sun := maxf(to_sun.length(), MIN_DIST)
	total += to_sun.normalized() * (G * sun_mass / (r_sun * r_sun))

	for p in planets:
		var to_p: Vector2 = p.pos - pos
		var r_p := maxf(to_p.length(), MIN_DIST)
		total += to_p.normalized() * (G * p.mass / (r_p * r_p))

	return total