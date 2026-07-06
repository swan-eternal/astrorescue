extends Node2D
##
## Astronaut: a small sprite positioned on the planet's surface.
## Auto-positions 135° ahead of the planet's orbital position (the
## "leading" side of the orbit, ahead of motion). Becomes invisible
## when picked up.
##

const SIZE: float = 6.0
const COLOR: Color = Color(0.3, 0.6, 1.0)

var picked_up: bool = false

@onready var _poly: Polygon2D = $Polygon2D


func _ready() -> void:
	# Build hexagon shape.
	var pts := PackedVector2Array()
	for i in 6:
		var a := TAU * float(i) / 6.0
		pts.append(Vector2(cos(a), sin(a)) * SIZE)
	_poly.polygon = pts
	_poly.color = COLOR

	# Auto-position at the planet's surface, ahead of orbital motion.
	# We compute from `phase` directly because planet.velocity isn't
	# initialized yet when our _ready runs (child _ready fires before
	# parent's). phase is set during scene instantiation, so it's safe.
	var planet := get_parent()
	var planet_radius: float = float(planet.get("radius"))
	var phase: float = float(planet.get("phase"))
	var offset_angle: float = phase + 3.0 * PI / 4.0
	position = Vector2(cos(offset_angle), sin(offset_angle)) * planet_radius


func pick_up() -> void:
	picked_up = true
	visible = false