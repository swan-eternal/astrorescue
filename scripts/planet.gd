extends Node2D
##
## A planet under closed-form orbital mechanics.
##
## Each frame, the planet computes its position and velocity from its
## orbital elements (perihelion, aphelion, angle_of_aphelion, phase) plus
## `GameTime.current` via `orbit_calculator.gd`. Closed-form replaces the
## previous Euler integration: no numerical drift, exact at any time
## scale, stable orbits.
##
## Planets don't feel each other (only the sun, looked up via the
## "attractors" group each frame). Level designers configure mass,
## orbit, and gameplay flags via @export vars.
##

# --- Level design ---

## If true, this planet is the player's starting/ending world.
## The rocket auto-snaps to its surface (riding its orbital motion) on
## level start, and landing here with an astronaut counts as a win.
@export var is_home: bool = false

## If true, an Astronaut is auto-spawned as a child node in _ready.
## Pickup happens via proximity when the rocket lands on this planet
## (see rocket.gd's landing branch).
@export var has_astronaut: bool = false

## If true, a FuelPickup is auto-spawned as a child node in _ready,
## orbiting at `fuel_orbit_radius` + this planet's `radius` at
## `fuel_orbit_speed`. The pickup itself becomes the planet's child so
## it inherits the planet's position automatically.
@export var has_fuel: bool = false

## Distance beyond the planet's surface where the fuel pickup orbits.
## Added to the planet's base `radius` so the pickup always stays
## outside the planet, even if this value is small or zero.
@export var fuel_orbit_radius: float = 10.0

## Angular speed (radians/second) of the orbiting fuel pickup.
@export var fuel_orbit_speed: float = 0.5

# --- Visual ---

## Visual radius of the planet's circle (in world units).
## Doesn't affect physics — only the rendered Polygon2D shape.
@export var radius: float = 8.0

## Fill color for the planet's visual.
@export var color: Color = Color(0.4, 0.7, 0.9)

# --- Orbital elements ---

## Distance at closest approach to the central body (the sun for
## planets). Combined with `aphelion`, defines the size and shape of
## the orbit.
@export var perihelion: float = 200.0

## Distance at farthest approach from the central body. Equal to
## `perihelion` for a circular orbit. Larger values = more elliptical.
@export var aphelion: float = 200.0

## Orientation of the ellipse's major axis, in radians, measured
## counterclockwise from world +X. 0 = periapsis along +X axis.
@export var angle_of_aphelion: float = 0.0

## Body's initial position along the orbit at t=0, in radians of mean
## anomaly. 0 = body starts at periapsis, π = body starts at apoapsis.
@export var phase: float = 0.0

# --- Physics ---

## Gravitational mass in arbitrary units. Read by other bodies (notably
## the rocket) when computing gravity on them. Planets do NOT feel each
## other's gravity — only the sun's. Lower this for a planet that
## doesn't tug the rocket much.
@export var mass: float = 1000.0

# Universal gravitational constant for this script (matches rocket.gd
# and the trajectory scripts — keep them in sync).
const G := 1.0

# Fallback sun mass, used only when no attractor is found in the group
# yet (e.g., during the first physics tick before any body has joined).
# The real sun's mass is read dynamically from sun.gd in _physics_process.
const DEFAULT_SUN_MASS := 4_000_000.0

const AstronautScene := preload("res://scenes/astronaut.tscn")
const FuelPickupScene := preload("res://scenes/fuel_pickup.tscn")

# --- Runtime state ---

# Cached linear velocity. Updated each frame from orbit_calculator.
# Read by the trajectory predictor and the HUD.
var velocity: Vector2 = Vector2.ZERO

@onready var _poly: Polygon2D = $Polygon2D


## Set up the visual polygon, register with "attractors", compute the
## initial position from orbital elements at t=0 (so the planet appears
## at the right place from frame 1), and auto-spawn any astronaut or
## fuel pickup children.
func _ready() -> void:
	_poly.color = color
	_poly.polygon = _make_circle(radius, 48)

	add_to_group("attractors")  # so the rocket can be pulled by this planet

	# Compute initial position at t=0 explicitly (not via GameTime.current,
	# which is reset later in level_controller._initialize and could still
	# hold a stale value from a previous level at this point in scene
	# loading). t=0 always means "the start of this orbit."
	var sun_mass := _find_sun_mass()
	var state := OrbitCalculator.compute_state(
		perihelion, aphelion, angle_of_aphelion, phase, 0.0, sun_mass
	)
	position = state["position"]
	velocity = state["velocity"]

	# Auto-spawn the astronaut if flagged. Designer just toggles
	# `has_astronaut` on the planet instance — the scene manages itself.
	if has_astronaut:
		var astronaut := AstronautScene.instantiate()
		add_child(astronaut)

	# Same pattern for fuel pickups — the spawned pickup inherits the
	# orbit radius/speed we just configured on this planet.
	if has_fuel:
		var fuel_pickup := FuelPickupScene.instantiate()
		add_child(fuel_pickup)
		fuel_pickup.orbit_radius = fuel_orbit_radius
		fuel_pickup.orbit_speed = fuel_orbit_speed


## Each physics tick: compute closed-form position from orbital
## elements + `GameTime.current`. No integration, no drift.
func _physics_process(_delta: float) -> void:
	var sun_mass := _find_sun_mass()
	var state := OrbitCalculator.compute_state(
		perihelion, aphelion, angle_of_aphelion, phase,
		GameTime.current, sun_mass
	)
	position = state["position"]
	velocity = state["velocity"]


# Find the most massive body in the "attractors" group (the sun, given
# our mass setup). Returns DEFAULT_SUN_MASS if no attractors yet (e.g.,
# during the first physics tick before the sun has joined the group).
func _find_sun_mass() -> float:
	var attractors := get_tree().get_nodes_in_group("attractors")
	var max_mass := 0.0
	for body in attractors:
		var mass_value: float = float(body.get("mass"))
		if mass_value > max_mass:
			max_mass = mass_value
	return max_mass if max_mass > 0.0 else DEFAULT_SUN_MASS


# Build a closed circle polygon for the planet visual. `segs` controls
# the smoothness — 48 segments is plenty for any planet size visible
# on screen.
func _make_circle(r: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var angle := TAU * float(i) / float(segs)
		pts.append(Vector2(cos(angle), sin(angle)) * r)
	return pts