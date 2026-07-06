extends Node2D
##
## The sun — the gravity source of the solar system.
##
## Mostly just data: its `mass` is read every frame by every other body
## (planets, rocket, trajectory predictor) when computing gravity. The
## visual is on the Polygon2D child (sunpolygon_2d.gd); this script only
## handles the gravity-source role.
##

## Gravitational mass in arbitrary units.
## Higher values = stronger pull on planets and rocket. Changes in the
## inspector take effect immediately — every consumer reads this via
## `sun.get("mass")` each frame, no restart needed.
@export var mass: float = 4_000_000.0


## Register ourselves in the "attractors" group so other bodies (planets,
## rocket, trajectory predictor) can find us when computing gravity.
func _ready() -> void:
	add_to_group("attractors")
