extends Node2D
##
## A planet under real gravity simulation.
## Step 8 update: gravity reads the sun's mass dynamically, but planets
## only feel the sun (not each other) — keeps orbits stable and avoids
## cross-planet physics cost.
##

# --- Level design ---
@export var is_home: bool = false         # starting/ending planet
@export var has_astronaut: bool = false   # rescue target lives here
@export var has_fuel: bool = false        # this planet has orbiting fuel pickups
@export var fuel_orbit_radius: float = 10.0  # distance beyond the planet's surface where the fuel pickup orbits (added to the planet's base radius)
@export var fuel_orbit_speed: float = 0.5    # radians per second

# --- Visual ---
@export var radius: float = 8.0
@export var color: Color = Color(0.4, 0.7, 0.9)

# --- Initial conditions ---
@export var orbit_radius: float = 200.0
@export var phase: float = 0.0
@export var initial_speed_multiplier: float = 1.0

# --- Physics ---
@export var mass: float = 1000.0
const G := 1.0
const DEFAULT_SUN_MASS := 4_000_000.0  # fallback if sun isn't in group yet
const AstronautScene := preload("res://scenes/astronaut.tscn")
const FuelPickupScene := preload("res://scenes/fuel_pickup.tscn")

# --- Runtime state ---
var velocity: Vector2 = Vector2.ZERO
@onready var _poly: Polygon2D = $Polygon2D


func _ready() -> void:
 _poly.color = color
 _poly.polygon = _make_circle(radius, 48)

 position = Vector2(cos(phase), sin(phase)) * orbit_radius

 # Initial velocity tangent to position, magnitude for circular orbit.
 # Pull sun's mass dynamically so changes to M_sun propagate.
 var sun_mass := _find_sun_mass()
 var tangent := Vector2(-sin(phase), cos(phase))
 var circular_speed := sqrt(G * sun_mass / orbit_radius)
 velocity = tangent * circular_speed * initial_speed_multiplier

 add_to_group("attractors")  # so the rocket can be pulled by this planet

 # Auto-spawn the astronaut if flagged. Designer just toggles `has_astronaut`
 # on the planet instance in the level scene — the scene manages itself.
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


func _physics_process(delta: float) -> void:
 # Planets feel only the sun (assumed at world origin), not each other.
 # The sun's mass is read dynamically each frame from the group.
 var sun_mass := _find_sun_mass()
 var to_sun := -position
 var r := maxf(to_sun.length(), 1.0)
 var accel_mag := G * sun_mass / (r * r)
 velocity += to_sun.normalized() * accel_mag * delta
 position += velocity * delta


# Find the most massive attractor (the sun, given our mass setup).
func _find_sun_mass() -> float:
 var attractors := get_tree().get_nodes_in_group("attractors")
 var max_mass := 0.0
 for body in attractors:
  var mass_value: float = float(body.get("mass"))
  if mass_value > max_mass:
   max_mass = mass_value
 return max_mass if max_mass > 0.0 else DEFAULT_SUN_MASS


func _make_circle(r: float, segs: int) -> PackedVector2Array:
 var pts := PackedVector2Array()
 for i in segs:
  var angle := TAU * float(i) / float(segs)
  pts.append(Vector2(cos(angle), sin(angle)) * r)
 return pts
