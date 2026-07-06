extends Node2D
##
## A planet under real gravity simulation.
##
## Planets only feel the sun (not each other) — keeps orbits stable and
## avoids cross-planet physics cost. The visual is a Polygon2D child drawn
## by this script's _ready; level designers configure mass, orbit, and
## gameplay flags via @export vars in the inspector.
##
## If `has_astronaut` is true, an astronaut is auto-spawned as a child
## node in _ready. Same for `has_fuel` (auto-spawns a fuel pickup in
## orbit using the planet's fuel_orbit_radius/speed values).
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

# --- Initial conditions ---

## Distance from the sun at which this planet starts. Set per-planet
## in the level scene to lay out the system.
@export var orbit_radius: float = 200.0

## Starting angle around the sun (radians). Different phases per planet
## spread them around the orbit so they don't all start at the same spot.
@export var phase: float = 0.0

## Multiplier on the circular-orbit speed. 1.0 = perfect circular orbit;
## >1.0 = elliptical (faster, larger apoapsis); <1.0 = slower, larger
## periapsis. Designers tweak to shape orbits without recomputing math.
@export var initial_speed_multiplier: float = 1.0

# --- Physics ---

## Gravitational mass in arbitrary units. Read by other bodies (notably
## the rocket) when computing gravity on them. Planets do NOT feel each
## other's gravity — only the sun's. Lower this for a planet that
## doesn't tug the rocket much.
@export var mass: float = 1000.0

# Universal gravitational constant for this project. Same value as in
# sun.gd, planet.gd, rocket.gd, and the trajectory predictor — keep them
# in sync if you ever change it.
const G := 1.0

# Fallback sun mass, used only when no attractor is found in the group
# yet (e.g., during the first physics tick before any body has joined).
# The real sun's mass is read dynamically from sun.gd in _physics_process.
const DEFAULT_SUN_MASS := 4_000_000.0

const AstronautScene := preload("res://scenes/astronaut.tscn")
const FuelPickupScene := preload("res://scenes/fuel_pickup.tscn")

# --- Runtime state ---

# Cached linear velocity. Mutated each frame in _physics_process; the
# rocket reads this when computing its own gravity from this planet.
var velocity: Vector2 = Vector2.ZERO

@onready var _poly: Polygon2D = $Polygon2D


## Initialize the planet's position, orbit, visual, and auto-spawned
## children (astronaut + fuel pickup, depending on the boolean flags).
## Adds this planet to the "attractors" group so the rocket and
## trajectory predictor can find us when computing gravity.
func _ready() -> void:
	_poly.color = color
	_poly.polygon = _make_circle(radius, 48)

	position = Vector2(cos(phase), sin(phase)) * orbit_radius

	# Initial velocity tangent to position, magnitude for circular orbit.
	# Pull sun's mass dynamically so changes to sun.mass propagate.
	var sun_mass := _find_sun_mass()
	var tangent := Vector2(-sin(phase), cos(phase))
	var circular_speed := sqrt(G * sun_mass / orbit_radius)
	velocity = tangent * circular_speed * initial_speed_multiplier

	add_to_group("attractors")  # so the rocket can be pulled by this planet

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


## Apply the sun's gravity and integrate position via a simple Euler
## step. Reads sun.mass dynamically each frame so inspector tweaks
## take effect without restart.
func _physics_process(delta: float) -> void:
	# Planets feel only the sun (assumed at world origin), not each other.
	# This keeps orbits stable and avoids cross-planet physics cost.
	var sun_mass := _find_sun_mass()
	var to_sun := -position
	var r := maxf(to_sun.length(), 1.0)
	var accel_mag := G * sun_mass / (r * r)
	velocity += to_sun.normalized() * accel_mag * delta
	position += velocity * delta


## Find the most massive body in the "attractors" group (the sun, given
## our mass setup) and return its mass. Falls back to DEFAULT_SUN_MASS
## if no attractors have joined the group yet.
func _find_sun_mass() -> float:
	var attractors := get_tree().get_nodes_in_group("attractors")
	var max_mass := 0.0
	for body in attractors:
		var mass_value: float = float(body.get("mass"))
		if mass_value > max_mass:
			max_mass = mass_value
	return max_mass if max_mass > 0.0 else DEFAULT_SUN_MASS


## Build a closed circle polygon for the planet visual. `segs` controls
## the smoothness — 48 segments is plenty for any planet size visible
## on screen.
func _make_circle(r: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var angle := TAU * float(i) / float(segs)
		pts.append(Vector2(cos(angle), sin(angle)) * r)
	return pts