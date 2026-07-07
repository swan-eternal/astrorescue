extends Node2D
##
## A moon — orbits a host planet (not the sun) using the same closed-form
## orbital mechanics as `planet.gd`, with the host planet's mass as the
## central body. Each physics tick:
##
##   world_position = host_planet.global_position + state["position"]
##   world_velocity = host_planet.velocity + state["velocity"]
##
## — both in the host's reference frame, then offset to world coords.
##
## As an attractor: yes (joins "attractors" group; the rocket's gravity
## loop reads `mass` like any other body). Default mass is small (10)
## so the gravity pull on the rocket is gentle — moons pull the
## rocket around, but the dominant pull is still the host planet (and
## the sun).
##
## Landable: default true. Use `is_landable = false` in JSON if you
## want a moon that's a hazard rather than a target.
##
## Astronaut + fuel flags: same as planets. Spawn via
## `spawn_dynamic_children()` called explicitly by `level_loader.gd`
## after @exports are set (see the same pattern in `planet.gd`).
##

# --- Orbital elements (relative to the host planet) ---

## Name of the host planet to orbit. The level_loader resolves this
## string to a Node2D in the "attractors" group during
## `resolve_orbit()`. Required — moons have no meaningful orbit
## without a host.
@export var host_planet_name: String = ""

## Distance at closest approach to the host planet. Must be > 0.
@export var perihelion: float = 30.0

## Distance at farthest approach from the host planet. Equal to
## `perihelion` for a circular orbit.
@export var aphelion: float = 30.0

## Orientation of the orbital ellipse, in radians.
@export var angle_of_aphelion: float = 0.0

## Initial mean anomaly at t=0, in radians.
@export var phase: float = 0.0


# --- Visual ---

## Visual radius (world units). Doesn't affect physics — only the
## rendered Polygon2D shape. Build collision radius uses this same
## value (single source of truth).
@export var radius: float = 6.0

## Fill color for the moon's visual.
@export var color: Color = Color(0.7, 0.7, 0.8)


# --- Physics ---

## Gravitational mass. Smaller than typical planets by default; tune
## per level to control how strongly the moon tugs the rocket.
@export var mass: float = 10.0


# --- Gameplay flags ---

## Whether the rocket can land here. Default true (moons are landable).
## Set false in JSON to make the moon a hazard instead.
@export var is_landable: bool = true

## If true, an Astronaut is auto-spawned as a child in
## `spawn_dynamic_children()`.
@export var has_astronaut: bool = false

## If true, a FuelPickup is auto-spawned as a child in
## `spawn_dynamic_children()`.
@export var has_fuel: bool = false

## Distance beyond the moon's surface where the fuel pickup orbits.
@export var fuel_orbit_radius: float = 8.0

## Angular speed (radians/second) of the orbiting fuel pickup.
@export var fuel_orbit_speed: float = 0.5


# Universal gravitational constant. Matches orbit_calculator.gd and
# other body scripts — keep in sync.
const G: float = 1.0


const AstronautScene := preload("res://scenes/astronaut.tscn")
const FuelPickupScene := preload("res://scenes/fuel_pickup.tscn")


# --- Runtime state ---

# Cached reference to the host planet. Set in `resolve_orbit()` after
# the loader has set `host_planet_name` from JSON.
var host_planet: Node2D = null

# World-frame velocity. Updated each physics tick — used by the
# rocket's collision branch for the rel_speed landing/crash check.
var velocity: Vector2 = Vector2.ZERO


@onready var _poly: Polygon2D = $Polygon2D


## Build a placeholder visual, register with "attractors". The rest of
## the init (host lookup, initial position, dynamic children) is
## deferred to methods called by `level_loader.gd` after @export
## values are set. Same pattern as `planet.gd` to avoid init-order
## bugs from the @export-after-add_child rule (skill §1.5).
func _ready() -> void:
	apply_visual()
	add_to_group("attractors")


## Apply the current `radius` and `color` @exports to the visual polygon.
## Idempotent — safe to call from `_ready` (placeholder) and from
## `level_loader` (after JSON values are set).
func apply_visual() -> void:
	_poly.color = color
	_poly.polygon = _make_circle(radius, 32)


## Resolve the host planet (by name from "attractors") and place
## ourselves at the orbit-derived initial position. Called by
## `level_loader._instantiate_moon` AFTER `host_planet_name` is set.
func resolve_orbit() -> void:
	for body in get_tree().get_nodes_in_group("attractors"):
		# Match against body's `body_label` @export (set by
		# level_loader from JSON's "name" key), NOT `body.name`
		# which is the Node's scene-tree identifier and is
		# always "planet" from scenes/planet.tscn.
		if body.get("body_label") == host_planet_name:
			host_planet = body
			break

	if host_planet == null:
		push_warning("Moon: host_planet '%s' not found in 'attractors' group" % host_planet_name)
		return

	# Initial position relative to host planet (closed-form orbit at t=0).
	var host_mass: float = _get_host_mass()
	var state: Dictionary = OrbitCalculator.compute_state(
		perihelion, aphelion, angle_of_aphelion, phase, 0.0, host_mass
	)
	position = state["position"]
	velocity = state["velocity"]


## Spawn astronaut + fuel pickup children based on the gameplay flags.
## Same pattern as `planet.gd` — called explicitly by the loader after
## @export values are set.
func spawn_dynamic_children() -> void:
	if has_astronaut:
		var astronaut := AstronautScene.instantiate()
		add_child(astronaut)
	if has_fuel:
		var fuel_pickup := FuelPickupScene.instantiate()
		add_child(fuel_pickup)
		fuel_pickup.orbit_radius = fuel_orbit_radius
		fuel_pickup.orbit_speed = fuel_orbit_speed


## Each physics tick: compute closed-form position relative to the
## host planet (Kepler equation via `orbit_calculator.gd`) and place
## ourselves in world coordinates. Same math as `planet.gd` — just
## with the host planet's mass as central body.
func _physics_process(_delta: float) -> void:
	if host_planet == null:
		return
	var host_mass: float = _get_host_mass()
	var state: Dictionary = OrbitCalculator.compute_state(
		perihelion, aphelion, angle_of_aphelion, phase, GameTime.current, host_mass
	)
	var planet_velocity: Vector2 = Vector2(host_planet.get("velocity"))
	# World position = host's world position + moon's offset in
	# the host's reference frame.
	global_position = host_planet.global_position + state["position"]
	# World velocity = host's world velocity + moon's relative velocity.
	# Needed by the rocket's rel_speed landing/crash check.
	velocity = planet_velocity + state["velocity"]


# Read the host planet's mass. Fallback small constant if the host
# hasn't been resolved yet (shouldn't happen after resolve_orbit()
# runs, but defensive against misordered loader calls).
func _get_host_mass() -> float:
	if host_planet == null:
		return 10.0
	return float(host_planet.get("mass"))


# Build a closed circle polygon for the visual.
func _make_circle(r: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var angle := TAU * float(i) / float(segs)
		pts.append(Vector2(cos(angle), sin(angle)) * r)
	return pts