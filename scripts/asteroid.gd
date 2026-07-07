extends Node2D
##
## An asteroid — small body orbiting the sun. Same closed-form orbit
## math as `planet.gd` (sun is the central mass). Two behavioral
## differences from a planet:
##
## - `mass = 0.0` by default. Joining "attractors" group means
##   collision detection finds us (rocket.gd::_find_nearest_attractor
##   iterates the group), but the gravity loop in `rocket.gd` reads
##   `mass = 0` and computes zero force. So the asteroid is an
##   obstacle, not an attractor.
## - `is_landable = false` by default — touching always crashes
##   regardless of approach speed (same logic the sun uses).
##
## Optional `has_fuel = true` adds a fuel pickup orbiting at
## `fuel_orbit_radius + radius`. Designed as deliberate risk/reward:
## you have to fly close enough to grab the fuel without hitting the
## rock. Off by default — opt-in per-asteroid in JSON.
##

# --- Orbital elements (relative to the sun) ---

## Distance at closest approach to the sun.
@export var perihelion: float = 1500.0

## Distance at farthest approach from the sun.
@export var aphelion: float = 2000.0

## Orientation of the orbital ellipse, in radians.
@export var angle_of_aphelion: float = 0.0

## Initial mean anomaly at t=0, in radians.
@export var phase: float = 0.0


# --- Visual ---

## Visual radius (world units). Same value used for collision
## (single source of truth, like the sun).
@export var radius: float = 8.0

## Fill color for the asteroid's visual.
@export var color: Color = Color(0.5, 0.4, 0.3)


# --- Physics ---

## Gravitational mass. Default 0.0 so the asteroid exerts no pull on
## the rocket. Override in JSON only for designer-chosen "heavy"
## asteroids (rare — usually you'd rather bump the player's
## `thrust_acceleration` than give an asteroid gravity).
@export var mass: float = 0.0


# --- Gameplay flags ---

## Touching the asteroid always crashes. Default false. Override to
## true only for designer-chosen "safe" asteroids that are just
## scenery.
@export var is_landable: bool = false

## If true, a FuelPickup is auto-spawned as a child. Risk/reward:
## grab fuel without hitting the rock. Off by default.
@export var has_fuel: bool = false

## Distance beyond the asteroid's surface where the fuel pickup orbits.
@export var fuel_orbit_radius: float = 12.0

## Angular speed (radians/second) of the orbiting fuel pickup.
@export var fuel_orbit_speed: float = 0.3


# Universal gravitational constant. Matches orbit_calculator.gd and
# other body scripts.
const G: float = 1.0


const FuelPickupScene := preload("res://scenes/fuel_pickup.tscn")


# --- Runtime state ---

# Cached linear velocity. Set each frame from the orbit math.
var velocity: Vector2 = Vector2.ZERO


@onready var _poly: Polygon2D = $Polygon2D


## Build a placeholder visual, register with "attractors", compute
## initial position from orbital elements. Astronaut/fuel spawning is
## deferred to `spawn_dynamic_children()` called by the loader after
## @export values are set — same init-order pattern as `planet.gd`.
func _ready() -> void:
	apply_visual()
	add_to_group("attractors")

	# Compute initial position at t=0 explicitly. The sun is already
	# in "attractors" by the time asteroids are instantiated (sun
	# comes first in JSON bodies[] order), so this finds it.
	var sun_mass: float = _find_sun_mass()
	var state: Dictionary = OrbitCalculator.compute_state(
		perihelion, aphelion, angle_of_aphelion, phase, 0.0, sun_mass
	)
	position = state["position"]
	velocity = state["velocity"]


## Apply the current `radius` and `color` @exports to the visual polygon.
## Idempotent — safe from `_ready` (placeholder) and from the loader
## (after JSON values are set).
func apply_visual() -> void:
	_poly.color = color
	_poly.polygon = _make_circle(radius, 32)


## Spawn fuel pickup if `has_fuel` is true. Called explicitly by
## `level_loader` after @export values are set. Asteroids don't carry
## astronauts, so no astronaut branch.
func spawn_dynamic_children() -> void:
	if has_fuel:
		var fuel_pickup := FuelPickupScene.instantiate()
		add_child(fuel_pickup)
		fuel_pickup.orbit_radius = fuel_orbit_radius
		fuel_pickup.orbit_speed = fuel_orbit_speed


## Each physics tick: compute closed-form sun-orbit position.
## Same math as `planet.gd` — central mass is the sun, position is in
## heliocentric (= world) frame.
func _physics_process(_delta: float) -> void:
	var sun_mass: float = _find_sun_mass()
	var state: Dictionary = OrbitCalculator.compute_state(
		perihelion, aphelion, angle_of_aphelion, phase, GameTime.current, sun_mass
	)
	position = state["position"]
	velocity = state["velocity"]


# Find the most massive body in "attractors" (the sun, given our mass
# setup). Returns 0 if no attractors yet (e.g., during the very first
# physics tick before the sun has joined the group — should not happen
# in practice since asteroids are instantiated after the sun).
func _find_sun_mass() -> float:
	var attractors := get_tree().get_nodes_in_group("attractors")
	var max_mass: float = 0.0
	for body in attractors:
		var mass_value: float = float(body.get("mass"))
		if mass_value > max_mass:
			max_mass = mass_value
	return max_mass


# Build a closed circle polygon for the visual.
func _make_circle(r: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var angle := TAU * float(i) / float(segs)
		pts.append(Vector2(cos(angle), sin(angle)) * r)
	return pts