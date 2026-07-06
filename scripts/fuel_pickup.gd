extends Node2D
##
## Fuel pickup: a small orange hexagon orbiting the parent planet at
## a fixed radius. When the rocket flies close (within rocket.fuel_pickup_radius),
## fuel is added and the pickup is freed.
##
## Auto-spawned as a child of a planet when planet.has_fuel is true;
## the spawner (planet.gd) overrides orbit_radius and orbit_speed
## with the planet's values.
##

# Orbit parameters — defaults below are used if no planet override
# is provided. Per-planet overrides are set by the spawner in planet.gd.
## Distance beyond the planet's surface where this pickup orbits.
## Added to the planet's base `radius` so the pickup is always outside
## the planet, even if this value is small or zero.
var orbit_radius: float = 50.0

## Angular speed (radians/second) of the orbit. Larger = pickup whips
## around faster.
var orbit_speed: float = 0.5

# Visual constants — not exported, consistent look across pickups.
const COLOR: Color = Color(1.0, 0.55, 0.2)  # orange — distinct from astronaut blue
const SIZE: float = 5.0

# Accumulated time used to drive the orbit position. Starts at 0 so
# all pickups spawned together start at the same angular position
# unless their initial _elapsed is seeded (currently isn't).
var _elapsed: float = 0.0

@onready var _poly: Polygon2D = $Polygon2D


## Build the hexagon sprite and join the "fuel" group so the rocket
## can find and collect us each physics tick (rocket.gd scans the group).
func _ready() -> void:
	# Build hexagon shape.
	var pts := PackedVector2Array()
	for i in 6:
		var a := TAU * float(i) / 6.0
		pts.append(Vector2(cos(a), sin(a)) * SIZE)
	_poly.polygon = pts
	_poly.color = COLOR

	# Join the "fuel" group so the rocket can find us.
	add_to_group("fuel")


## Step the orbit position each frame. The pickup is a child of the
## planet, so its `position` is relative to the planet — orbit around
## the parent automatically.
func _process(delta: float) -> void:
	_elapsed += delta
	# orbit_radius is "distance beyond the planet's surface" — we add it
	# to the planet's base radius so the pickup is always outside the
	# planet, even if orbit_radius is small or zero. Without this, a
	# planet with a big radius and a small orbit_radius would clip the
	# pickup inside itself.
	var planet_radius: float = float(get_parent().get("radius"))
	position = Vector2(cos(_elapsed * orbit_speed), sin(_elapsed * orbit_speed)) * (planet_radius + orbit_radius)