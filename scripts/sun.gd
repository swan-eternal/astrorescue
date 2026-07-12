extends Node2D
##
## The sun — the gravity source of the solar system.
##
## Mostly just data: its `mass` is read every frame by every other body
## (planets, rocket, trajectory predictor) when computing gravity. The
## visual is on the Polygon2D child (sunpolygon_2d.gd); this script
## also owns the collision radius (single source of truth for both the
## visible disk and the rocket's contact check) and the
## `is_landable = false` flag so contact with the sun is an instant
## crash.
##

## Gravitational mass in arbitrary units.
## Higher values = stronger pull on planets and rocket. Changes in the
## inspector take effect immediately — every consumer reads this via
## `sun.get("mass")` each frame, no restart needed.
@export var mass: float = 3_000_000.0

## Collision radius in world units. Single source of truth for both
## the rocket's contact check (read by `rocket.gd::_physics_process`)
## and the visible disk drawn by sunpolygon_2d.gd. Higher = larger
## disk and a wider region where the rocket will crash. Changing the
## level JSON's `radius` for the sun overrides this default.
@export var radius: float = 200.0

## Whether the rocket can land here. Always false for the sun —
## touching the sun is an instant crash regardless of approach speed.
## Planets keep the default true (see `planet.gd`).
@export var is_landable: bool = false

# Cached linear velocity. The sun has no orbit (sits at the
# heliocentric origin), so this stays at Vector2.ZERO. Exposed anyway
# because every other attractor body (planet.gd, moon.gd, asteroid.gd)
# has `var velocity`, and HUD/rocket/trajectory/moon code reads
# body.get("velocity") unconditionally. Vector2(null) would crash with
# Nonexistent Vector2 constructor otherwise.
var velocity: Vector2 = Vector2.ZERO


## Register ourselves in the "attractors" group so other bodies (planets,
## rocket, trajectory predictor) can find us when computing gravity.
func _ready() -> void:
	add_to_group("attractors")


## Rebuild the visual polygon to match the current @export radius.
## Mirrors planet.gd / moon.gd / asteroid.gd — called by
## LevelLoader._instantiate_sun after setting @exports from the spec,
## and implicitly via the editor's _refresh_viewport() on every
## inspector edit. The polygon child built a placeholder from the
## default radius=200 during add_child, before this method could
## override it.
func apply_visual() -> void:
	var poly := get_node_or_null("Polygon2D")
	if poly != null and poly.has_method("rebuild_circle"):
		poly.rebuild_circle()
