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

## Whether the rocket can land here. Default true (planets are
## landable). Bodies like the sun and (future) asteroids set this to
## false so any contact always counts as a crash, regardless of
## approach speed. Read by `rocket.gd::_physics_process`.
@export var is_landable: bool = true

## Distance beyond the planet's surface where the fuel pickup orbits.
## Added to the planet's base `radius` so the pickup always stays
## outside the planet, even if this value is small or zero.
@export var fuel_orbit_radius: float = 30.0

## Angular speed (radians/second) of the orbiting fuel pickup.
@export var fuel_orbit_speed: float = 0.5

# --- Visual ---

## Visual radius of the planet's circle (in world units).
## Doesn't affect physics — only the rendered Polygon2D shape.
@export var radius: float = 100.0

## Fill color for the planet's visual.
@export var color: Color = Color(0.4, 0.7, 0.9)

## Display name for this body. Used by other bodies (e.g. moons
## looking up their host planet) to reference this one by name.
## Set by level_loader from the JSON's `"name"` key. Renamed
## `body_label` to avoid shadowing the built-in `Node.name`
## (the scene-tree identifier from scenes/planet.tscn).
@export var body_label: String = "planet"

# --- Orbital elements ---

## Distance at closest approach to the central body (the sun for
## planets). Combined with `aphelion`, defines the size and shape of
## the orbit.
@export var perihelion: float = 1000.0

## Distance at farthest approach from the central body. Equal to
## `perihelion` for a circular orbit. Larger values = more elliptical.
@export var aphelion: float = 1000.0

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
@export var mass: float = 10000.0

# Universal gravitational constant for this script (matches rocket.gd
# and the trajectory scripts — keep them in sync).
const G := 1.0

const AstronautScene := preload("res://scenes/astronaut.tscn")
const FuelPickupScene := preload("res://scenes/fuel_pickup.tscn")

# --- Runtime state ---

# Cached linear velocity. Updated each frame from orbit_calculator.
# Read by the trajectory predictor and the HUD.
var velocity: Vector2 = Vector2.ZERO

@onready var _poly: Polygon2D = $Polygon2D


## Build a placeholder visual, register with "attractors", compute the
## initial position from orbital elements at t=0 (so the planet appears
## at the right place from frame 1). Astronaut and fuel pickup spawning
## is deferred to `spawn_dynamic_children()`; visual refresh (radius +
## color from JSON) is deferred to `apply_visual()` — see those methods
## for why neither can run fully in _ready.
func _ready() -> void:
	# Build a placeholder visual from whatever radius + color are set
	# right now. level_loader-driven instances override this via
	# apply_visual() once it sets those @exports from JSON.
	apply_visual()

	add_to_group("attractors")  # so the rocket can be pulled by this planet

	# Compute initial position at t=0 explicitly (not via GameTime.current,
	# which is reset later in level_controller._initialize and could still
	# hold a stale value from a previous level at this point in scene
	# loading). t=0 always means "the start of this orbit."
	#
	# Note: uses the @export orbital elements, which level_loader sets
	# AFTER _ready. So this initial position is wrong for level_loader-
	# driven planets — but _physics_process recomputes the position from
	# the now-correct @exports on the next tick, so the visual catch-up
	# happens within ~1 frame.
	var sun_mass := _find_sun_mass()
	var state := OrbitCalculator.compute_state(
		perihelion, aphelion, angle_of_aphelion, phase, 0.0, sun_mass
	)
	position = state["position"]
	velocity = state["velocity"]


## Apply the current `radius` and `color` @exports to the visual polygon.
## Idempotent — safe to call from both _ready (placeholder for editor-
## placed planets) and from level_loader (after it sets radius/color
## from JSON, to override the _ready placeholder).
func apply_visual() -> void:
	_poly.color = color
	_poly.polygon = _make_circle(radius, 48)


## Spawn astronaut and fuel pickup children based on the `has_astronaut`
## and `has_fuel` flags. Called by level_loader AFTER it sets those @export
## values from JSON — they default to `false` at _ready time, so the
## spawn must happen in a separate pass.
##
## Level designers without level_loader (e.g., placing planets directly
## in a scene file via the editor) can also call this manually after
## setting the flags, or just toggle the @exports in the inspector and
## use `call_deferred("spawn_dynamic_children")` themselves.
func spawn_dynamic_children() -> void:
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
# our mass setup). Returns 0 if no attractors yet. Caller's
# orbit_calculator call will yield a zero-state in that case, which is
# the correct behavior. The window where this returns 0 is at most
# one physics tick (sun is always instantiated before any planet),
# so the visual catch-up via _physics_process handles it cleanly.
func _find_sun_mass() -> float:
	var attractors := get_tree().get_nodes_in_group("attractors")
	var max_mass := 0.0
	for body in attractors:
		var mass_value: float = float(body.get("mass"))
		if mass_value > max_mass:
			max_mass = mass_value
	return max_mass


# Build a closed circle polygon for the planet visual. `segs` controls
# the smoothness — 48 segments is plenty for any planet size visible
# on screen.
func _make_circle(r: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var angle := TAU * float(i) / float(segs)
		pts.append(Vector2(cos(angle), sin(angle)) * r)
	return pts
