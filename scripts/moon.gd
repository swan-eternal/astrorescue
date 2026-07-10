extends Node2D
##
## A moon — orbits a host planet (not the sun) using the same closed-form
## orbital mechanics as `planet.gd`, with the host planet's mass as the
## central body.
##
## Architecture: moons are CHILDREN of their host planet in the scene tree,
## not siblings. `level_loader.gd::_instantiate_planet_moon` adds each moon
## as a child of its planet after the planet's @exports are set, so the
## moon's `get_parent()` is always the host planet. This eliminates the
## host_planet-name lookup that the old architecture needed (and that had
## a bug fix in commit `68bb4ba`).
##
## Each physics tick:
##
##   state = OrbitCalculator.compute_state(
##       host_radius + perihelion,    # center-relative distance
##       host_radius + aphelion,      # center-relative distance
##       angle_of_aphelion, phase, GameTime.current, host_mass
##   )
##   position = state["position"]                      # local (Godot applies parent transform)
##   velocity = parent.velocity + state["velocity"]    # world-frame (for rocket collision reads)
##
## Perihelion and aphelion in the JSON are **distance from the planet's
## SURFACE** (not center). The script adds `host_radius` internally so the
## OrbitCalculator math is consistent with planet orbits (which use
## center-relative distance). This makes it physically impossible for a
## moon to render inside its planet — earth (radius 40) with a moon
## perihelion of 5 orbits at 45 from center, well clear of the surface.
##
## As an attractor: yes (joins "attractors" group; the rocket's gravity
## loop reads `mass` like any other body). Default mass is small (10) so
## the gravity pull on the rocket is gentle — moons perturb, not dominate.
##
## Landable: default true. Use `is_landable = false` in JSON if you want
## a moon that's a hazard rather than a target.
##
## Astronaut + fuel flags: same as planets. Spawn via
## `spawn_dynamic_children()` called explicitly by `level_loader.gd`
## after @exports are set (see the same pattern in `planet.gd`).
##


# --- Orbital elements (relative to the host planet's SURFACE) ---

## Distance at closest approach to the host planet's SURFACE, in world
## units. The script adds the host planet's radius internally, so the
## actual orbital perihelion (distance from planet center) is
## `host_radius + this value`. Must be >= 0 to keep the moon outside
## the planet.
@export var perihelion: float = 30.0

## Distance at farthest approach from the host planet's SURFACE. Same
## offset semantics as `perihelion`. Equal to `perihelion` for a
## circular orbit.
@export var aphelion: float = 30.0

## Orientation of the orbital ellipse, in radians.
@export var angle_of_aphelion: float = 0.0

## Initial mean anomaly at t=0, in radians.
@export var phase: float = 0.0


# --- Visual ---

## Visual radius (world units). Doesn't affect physics — only the
## rendered Polygon2D shape. Collision radius uses this same value
## (single source of truth).
@export var radius: float = 6.0

## Fill color for the moon's visual.
@export var color: Color = Color(0.7, 0.7, 0.8)


# --- Physics ---

## Gravitational mass. Smaller than typical planets by default; tune per
## level to control how strongly the moon tugs the rocket.
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


# Universal gravitational constant. Matches orbit_calculator.gd and other
# body scripts — keep in sync.
const G: float = 1.0


const AstronautScene := preload("res://scenes/astronaut.tscn")
const FuelPickupScene := preload("res://scenes/fuel_pickup.tscn")


# --- Runtime state ---

# Cached reference to the host planet. Always `get_parent()` — the loader
# adds moons as children of their planets (see `_ready`).
var _host: Node2D = null

# Cached host planet radius (world units). Read from the parent in
# `_ready`. The loader sets the planet's @export BEFORE adding moons as
# children, so the cache captures the JSON value, not the @export default.
var _host_radius: float = 0.0

# World-frame velocity. Updated each physics tick — used by the rocket's
# collision branch for the rel_speed landing/crash check. = parent's
# world velocity (planet) + our orbital velocity (relative to planet).
var velocity: Vector2 = Vector2.ZERO


@onready var _poly: Polygon2D = $Polygon2D


## Cache the host planet and its radius, build a placeholder visual,
## register with "attractors". The rest of the init (visual from current
## @exports, dynamic children, initial position) is deferred to methods
## called by `level_loader.gd` after @export values are set. Same pattern
## as `planet.gd` to avoid init-order bugs from the @export-after-add_child
## rule (skill §1.5).
##
## At this point the parent (planet) has already had its @exports set by
## the loader, so `get_parent().get("radius")` is the JSON value, not the
## default. Cache it for use in `_physics_process`.
func _ready() -> void:
	_host = get_parent()
	_host_radius = float(_host.get("radius"))
	apply_visual()
	add_to_group("attractors")


## Apply the current `radius` and `color` @exports to the visual polygon.
## Idempotent — safe to call from `_ready` (placeholder) and from
## `level_loader` (after JSON values are set).
func apply_visual() -> void:
	_poly.color = color
	_poly.polygon = _make_circle(radius, 32)


## Compute the closed-form orbital position at t=0 (relative to the host
## planet's center) and place ourselves there. Called by
## `level_loader._instantiate_planet_moon` AFTER the moon's @export
## values are set. Host is always `get_parent()` — no name lookup needed
## (the pre-refactor design had a `body_label` lookup bug here, fixed in
## commit `68bb4ba`; with the parent-child architecture that whole class
## of bug is gone).
func resolve_orbit() -> void:
	var state: Dictionary = OrbitCalculator.compute_state(
		_host_radius + perihelion,
		_host_radius + aphelion,
		angle_of_aphelion, phase, 0.0, _get_host_mass()
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


## Each physics tick: compute closed-form position relative to the host
## planet (Kepler equation via `orbit_calculator.gd`) and place ourselves.
## `perihelion` and `aphelion` are surface-relative in the JSON; the
## script offsets by `_host_radius` so OrbitCalculator receives
## center-relative distances.
##
## Position is set as a LOCAL position — Godot applies the parent's
## transform automatically because we're a child node, so the moon's
## world position is correct without manual offset math. Velocity is
## set as a WORLD-frame vector so `rocket.gd`'s collision branch can
## read it directly for the rel_speed landing/crash check.
func _physics_process(_delta: float) -> void:
	var state: Dictionary = OrbitCalculator.compute_state(
		_host_radius + perihelion,
		_host_radius + aphelion,
		angle_of_aphelion, phase, GameTime.current, _get_host_mass()
	)
	position = state["position"]
	velocity = Vector2(_host.get("velocity")) + state["velocity"]


# Read the host planet's mass. Called once per physics tick — direct
# accessor, no defensive null check (the parent is always set by the
# loader; if it isn't, we have a much bigger problem than a crash here).
func _get_host_mass() -> float:
	return float(_host.get("mass"))


# Build a closed circle polygon for the visual.
func _make_circle(r: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs:
		var angle := TAU * float(i) / float(segs)
		pts.append(Vector2(cos(angle), sin(angle)) * r)
	return pts
