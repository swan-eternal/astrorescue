extends Node2D
##
## The sun. Mostly just data — its mass is read by every other body
## when computing gravity. The visual stays on the Polygon2D child
## (sun_polygon.gd); this script only handles the gravity-source role.
##

@export var mass: float = 4_000_000.0

func _ready() -> void:
 add_to_group("attractors")
