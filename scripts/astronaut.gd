extends Node2D
##
## Astronaut: a small sprite positioned on the planet's surface.
## Auto-positions itself 135° ahead of the planet's orbital position
## (the "leading" side of the orbit, ahead of motion). Becomes invisible
## when picked up. Lives as a child of a planet; auto-spawned when
## planet.has_astronaut is true (see planet.gd).
##

# Visual size and color. Not exported — these rarely need tuning, and
# consistent appearance across all astronauts makes them easier to spot.
const SIZE: float = 6.0
const COLOR: Color = Color(0.3, 0.6, 1.0)

# Whether the rocket has collected this astronaut. Read by:
# - rocket.gd's landing branch (decides whether to call pick_up())
# - astronaut_indicators.gd (skips rendering already-collected ones)
var picked_up: bool = false

@onready var _poly: Polygon2D = $Polygon2D


## Build the hexagon sprite and place ourselves on the parent's surface.
## Runs before the parent's _ready (children init first), so we read
## `phase` (set via scene-instantiate) rather than `velocity` (not set yet).
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
	# 3π/4 = 135°. This is the angle ahead of the planet's orbital
	# position where the astronaut stands. Not at the front (0°) because
	# that's where the rocket tends to land; placing the astronaut off-
	# axis forces a more deliberate rendezvous.
	var offset_angle: float = phase + 3.0 * PI / 4.0
	position = Vector2(cos(offset_angle), sin(offset_angle)) * planet_radius


## Mark this astronaut as collected and hide it. Called by rocket.gd
## when the rocket lands on the parent planet within pickup range.
## Does NOT increment the rocket's picked_up_count — that's the
## caller's job (kept explicit so the rocket owns its own counter).
func pick_up() -> void:
	picked_up = true
	visible = false