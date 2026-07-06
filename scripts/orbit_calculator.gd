extends RefCounted
class_name OrbitCalculator
##
## Pure-math helper: closed-form orbital mechanics for 2D elliptical orbits.
##
## Given orbital elements (perihelion, aphelion, angle_of_aphelion, phase) and
## the current time, returns the exact position and velocity of a body orbiting
## a central mass. No per-frame integration, no drift, no jitter.
##
## All inputs/outputs follow Godot conventions: radians for angles, Vector2 for
## 2D positions/velocities, project-standard units (G = 1.0).
##
## Used by planet.gd (and future moon.gd, asteroid.gd) to compute body
## positions each frame from prescribed orbital elements.

# Universal gravitational constant for this project. Matches planet.gd,
# rocket.gd, and the trajectory predictor scripts — keep them in sync.
const G: float = 1.0

# Floor for distance in velocity calculation to avoid division-by-zero
# when the body is exactly at the central mass (degenerate but possible
# during a scene reload or teleport).
const MIN_DIST: float = 1.0


## Compute position and velocity of a body at time `t` on a closed
## elliptical orbit around `central_mass`.
##
## All orbital elements are in the body's local orbital plane; the result
## is rotated by `angle_of_aphelion` to give world-space position/velocity.
##
## Parameters:
##   perihelion:         Distance at closest approach to the central body.
##                       Must be > 0.
##   aphelion:           Distance at farthest approach. Equal to perihelion
##                       for a circular orbit. Must be > 0 and >= perihelion
##                       (swapped if reversed).
##   angle_of_aphelion:  Orientation of the ellipse's major axis, in radians,
##                       measured counterclockwise from world +X. Default 0.0.
##   phase:              Body's initial position along the orbit at t=0,
##                       in radians of mean anomaly. Default 0.0.
##   t:                  Time since the start of the simulation (typically
##                       the level's `game_time`).
##   central_mass:       Mass of the body being orbited. Must be > 0.
##
## Returns:
##   A Dictionary with keys:
##     - "position" (Vector2): world-space position
##     - "velocity" (Vector2): world-space velocity
##
## Returns Vector2.ZERO for both and pushes a warning if the inputs are
## invalid or the orbit is unbound (e >= 1.0).
static func compute_state(
	perihelion: float,
	aphelion: float,
	angle_of_aphelion: float,
	phase: float,
	t: float,
	central_mass: float
) -> Dictionary:
	# ---- Input validation ----
	if central_mass <= 0.0:
		push_warning("OrbitCalculator: central_mass must be positive (got %f)" % central_mass)
		return {"position": Vector2.ZERO, "velocity": Vector2.ZERO}
	if perihelion <= 0.0 or aphelion <= 0.0:
		push_warning("OrbitCalculator: perihelion and aphelion must be positive (got %f, %f)" % [perihelion, aphelion])
		return {"position": Vector2.ZERO, "velocity": Vector2.ZERO}

	# Swap if reversed — be lenient about input order.
	var q: float = perihelion
	var Q: float = aphelion
	if q > Q:
		var temp: float = q
		q = Q
		Q = temp

	# ---- Convert perihelion/aphelion to standard orbital elements ----
	# Semi-major axis: average of perihelion and aphelion distances.
	var a: float = (q + Q) / 2.0
	# Eccentricity: 0 = circular, approaching 1 = very elongated ellipse.
	var e: float = (Q - q) / (Q + q)

	# Unbound orbit (e >= 1.0). Not supported — the game only uses closed
	# elliptical orbits. Push a warning and return zero state.
	if e >= 1.0:
		push_warning("OrbitCalculator: orbit is unbound (e=%f >= 1.0). Returning zero state." % e)
		return {"position": Vector2.ZERO, "velocity": Vector2.ZERO}

	# ---- Orbital period ----
	# Kepler's third law: T = 2π · sqrt(a³ / (G · M))
	var T: float = TAU * sqrt(a * a * a / (G * central_mass))

	# ---- Mean anomaly at time t ----
	# M increases linearly with time. fmod keeps it bounded to [0, 2π)
	# so the trig functions don't lose precision for very large t.
	var M: float = phase + TAU * fmod(t, T) / T

	# ---- Solve Kepler's equation: M = E - e·sin(E) for E ----
	# Newton-Raphson iteration. For low e (typical for our orbits), 3
	# iterations converge to ~1e-10 precision. For high e (>0.9), more
	# iterations would be needed; we don't support those orbits.
	var E: float = M
	for i in 3:
		# f(E) = E - e*sin(E) - M, f'(E) = 1 - e*cos(E)
		E = E - (E - e * sin(E) - M) / (1.0 - e * cos(E))

	# ---- True anomaly (ν) ----
	# Derived from eccentric anomaly: tan(ν/2) = sqrt((1+e)/(1-e)) · tan(E/2)
	# atan2 form is numerically stable across all quadrants.
	var nu: float = 2.0 * atan2(
		sqrt(1.0 + e) * sin(E / 2.0),
		sqrt(1.0 - e) * cos(E / 2.0)
	)

	# ---- Distance from focus (the central body) ----
	# r = a · (1 - e · cos(E))
	var r: float = a * (1.0 - e * cos(E))

	# ---- Position in orbital frame ----
	# Orbital frame: x-axis along the periapsis direction.
	var pos_orbit: Vector2 = Vector2(r * cos(nu), r * sin(nu))

	# Rotate to world frame.
	var position: Vector2 = pos_orbit.rotated(angle_of_aphelion)

	# ---- Velocity ----
	# Vis-viva equation: v² = GM · (2/r - 1/a)
	# For circular orbit (e=0, r=a): v = sqrt(GM/r), as expected.
	var v_mag: float = sqrt(G * central_mass * (2.0 / maxf(r, MIN_DIST) - 1.0 / a))

	# Velocity direction: perpendicular to radius, in the direction of motion.
	# For prograde motion (which all our orbits are), this is the position
	# vector rotated by +90° (counterclockwise).
	var vel_orbit: Vector2 = Vector2(-v_mag * sin(nu), v_mag * cos(nu))

	# Rotate to world frame.
	var velocity: Vector2 = vel_orbit.rotated(angle_of_aphelion)

	return {"position": position, "velocity": velocity}


## Convenience: compute only the position (skip velocity math).
## Use when you only need to place a body (e.g., initial scene setup) and
## don't care about its velocity.
static func compute_position(
	perihelion: float,
	aphelion: float,
	angle_of_aphelion: float,
	phase: float,
	t: float,
	central_mass: float
) -> Vector2:
	return compute_state(perihelion, aphelion, angle_of_aphelion, phase, t, central_mass)["position"]


## Compute the orbital period for the given orbital elements and central mass.
## Returns 0.0 if inputs are invalid.
static func compute_period(
	perihelion: float,
	aphelion: float,
	central_mass: float
) -> float:
	if central_mass <= 0.0 or perihelion <= 0.0 or aphelion <= 0.0:
		return 0.0
	var q: float = perihelion
	var Q: float = aphelion
	if q > Q:
		var temp: float = q
		q = Q
		Q = temp
	var a: float = (q + Q) / 2.0
	return TAU * sqrt(a * a * a / (G * central_mass))