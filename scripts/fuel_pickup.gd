extends Node2D
##
## Fuel pickup: a small cyan hexagon orbiting the parent planet at a fixed
## radius. When the rocket flies close, fuel is added and the pickup is freed.
##

# Orbit parameters — defaults below are used if no planet override is provided.
# Per-planet overrides are set by the spawner in planet.gd (via @export).
var orbit_radius: float = 50.0
var orbit_speed: float = 0.5  # radians per second
const COLOR: Color = Color(1.0, 0.55, 0.2)
const SIZE: float = 5.0

var _elapsed: float = 0.0

@onready var _poly: Polygon2D = $Polygon2D


func _ready() -> void:
	# Build hexagon sprite.
	var pts := PackedVector2Array()
	for i in 6:
		var a := TAU * float(i) / 6.0
		pts.append(Vector2(cos(a), sin(a)) * SIZE)
	_poly.polygon = pts
	_poly.color = COLOR

	# Join the "fuel" group so the rocket can find us.
	add_to_group("fuel")


func _process(delta: float) -> void:
	_elapsed += delta
	# orbit_radius is "distance beyond the planet's surface" — we add it to
	# the planet's base radius so the pickup is always outside the planet,
	# even if orbit_radius is small or zero. Without this, a planet with a
	# big radius and a small orbit_radius would clip the pickup inside itself.
	var planet_radius: float = float(get_parent().get("radius"))
	position = Vector2(cos(_elapsed * orbit_speed), sin(_elapsed * orbit_speed)) * (planet_radius + orbit_radius)