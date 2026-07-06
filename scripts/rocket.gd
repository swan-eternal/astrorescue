extends Node2D
##
## The player rocket — now controllable.
##
## Step 6: orbits under sun's gravity, no input.
## Step 7 (current): rotation + thrust input, _physics_process.
##

# --- Visual ---
@export var size: float = 10.0
@export var color: Color = Color(0.9, 0.95, 1.0)

# --- Initial conditions ---
@export var initial_position: Vector2 = Vector2(300.0, 0.0)
@export var initial_velocity: Vector2 = Vector2(0.0, 115.0)
@export var fuel: float = 100.0
@export var max_fuel: float = 100.0

# --- Controls ---
@export var rotation_speed: float = 3.0        # radians per second
@export var thrust_acceleration: float = 100.0  # units per second²

# --- Collision ---
@export var landing_speed_threshold: float = 8.0   # rel speed ≤ this → land
@export var landing_buffer: float = 1.0             # extra pixels past visual contact
@export var crash_speed_threshold: float = 30.0    # rel speed > this → crash
@export var launch_speed: float = 30.0             # initial velocity when thrusting off a planet


# --- Astronaut ---
# Pickup is proximity-based on landing: pickup_radius = planet.radius × this.
# Default 1.5. Tighter = more precise "near the astronaut" landings needed.
@export var astronaut_pickup_radius_multiplier: float = 1.5


# --- Fuel ---
# Thrust burns fuel at this rate (units per second).
# Dial down to ~0.5 for unconstrained testing, ~5 for normal play.
@export var fuel_consumption_rate: float = 5.0
# Each pickup restores this much fuel, capped at max_fuel.
@export var fuel_pickup_amount: float = 50.0
# Rocket-to-pickup distance below which the pickup is collected.
@export var fuel_pickup_radius: float = 30.0


# --- Physics constants (matches planet.gd) ---
const G := 1.0

# --- Runtime state ---
var velocity: Vector2 = Vector2.ZERO
@onready var _poly: Polygon2D = $Polygon2D
@onready var _audio_manager: Node = get_node("/root/AudioManager")
var landed: bool = false
var crashed: bool = false
var landed_planet: Node2D = null
var landed_offset: Vector2 = Vector2.ZERO
var crashed_planet: Node2D = null
var crashed_offset: Vector2 = Vector2.ZERO

# --- Astronaut state ---
var carrying_astronaut: bool = false
var picked_up_count: int = 0  # incremented on pickup; HUD reads this for the circle indicators

# --- Time warp ---
# Press > to speed up, < to slow down. Clamped at 1x and 8x.
# Engine.time_scale drives the global sim rate — physics, _process, etc.
# all run faster. Crucially, delta scales with it, so burning fuel at
# 8x burns 8x fuel per thrust tick — naturally punishes wasteful burns.
const TIME_WARP_LEVELS: Array[float] = [1.0, 2.0, 4.0, 8.0]
var time_warp_index: int = 0


func _ready() -> void:
	_poly.color = color
	_poly.polygon = _make_triangle(size)

	position = initial_position
	velocity = initial_velocity
	add_to_group("player")
	rotation = 0.0

	# If a planet is flagged as is_home, snap the rocket to its surface (riding
	# the planet in its direction of motion) instead of using the scene's
	# initial_position. This is the standard "start landed on the home planet"
	# pattern. If no is_home planet exists, the scene's initial_position and
	# initial_velocity are used as fallbacks.
	_snap_to_home_planet()


# If a planet in the "attractors" group has `is_home = true`, place the rocket
# landed on its surface in the direction of the planet's motion (so the rocket
# is "riding" the planet). Sets landed/landed_planet/landed_offset so the
# existing landed-glue logic in _physics_process maintains the position every
# frame. If no is_home planet is found, does nothing (scene's initial_position
# and initial_velocity remain in effect).
func _snap_to_home_planet() -> void:
	for body in get_tree().get_nodes_in_group("attractors"):
		if not body.get("is_home"):
			continue
		var planet_radius: float = float(body.get("radius"))
		var planet_pos: Vector2 = body.global_position
		var planet_vel: Vector2 = Vector2(body.get("velocity"))
		# Place at the surface in the direction of the planet's motion
		# (tangent to orbit). Default to +X if the planet is stationary.
		var facing: Vector2 = planet_vel.normalized() if planet_vel.length() > 0.01 else Vector2.RIGHT
		# 8.0 is the rocket's tail_reach offset (matches landing math).
		var surface_pos: Vector2 = planet_pos + facing * (planet_radius + 8.0)
		global_position = surface_pos
		velocity = planet_vel
		rotation = (global_position - planet_pos).angle()
		landed = true
		landed_planet = body
		landed_offset = surface_pos - planet_pos
		return


func _physics_process(delta: float) -> void:
	# Time warp input. Handled at the top so it works regardless of crashed/landed.
	if Input.is_action_just_pressed("time_warp_up"):
		time_warp_index = min(time_warp_index + 1, TIME_WARP_LEVELS.size() - 1)
		Engine.time_scale = TIME_WARP_LEVELS[time_warp_index]
	elif Input.is_action_just_pressed("time_warp_down"):
		time_warp_index = max(time_warp_index - 1, 0)
		Engine.time_scale = TIME_WARP_LEVELS[time_warp_index]

	# Crashed: freeze on the surface where we hit.
	if crashed:
		if crashed_planet != null:
			global_position = crashed_planet.global_position + crashed_offset
		return

	# Thruster audio: plays while the user is holding thrust AND has fuel.
	# Stops on release, when fuel hits 0, or when crashed. Checked here (before
	# the crashed/landed early-returns) so the sound stops even if the rocket
	# is dead, and starts correctly when un-sticking from a planet.
	if not crashed and Input.is_action_pressed("thrust") and fuel > 0.0:
		_audio_manager.start_thruster()
	else:
		_audio_manager.stop_thruster()

	# Landed: glue to the planet; thrust unsticks us.
	if landed and landed_planet != null:
		if Input.is_action_pressed("thrust"):
			landed = false
			landed_planet = null
			# velocity stays matched to the planet (set on land); the
			# physics below now runs and pushes us outward
		else:
			global_position = landed_planet.global_position + landed_offset
			velocity = Vector2(landed_planet.get("velocity"))
			return

	# Landing/crash detection: nearest attractor by distance.
	if not landed and not crashed:
		var nearest := _find_nearest_attractor()
		if nearest != null:
			# Visual radius of the planet's surface (radius × scale), then add
			# the rocket's tail reach so the trigger fires when the tail is
			# at the surface. `landing_buffer` is a small overshoot past that.
			var planet_radius: float = float(nearest.get("radius")) * abs(nearest.global_scale.x)
			var tail_reach: float = size * 0.8   # matches the back vertex in _make_triangle
			var effective_radius: float = planet_radius + tail_reach + landing_buffer
			var dist: float = global_position.distance_to(nearest.global_position)
			if dist <= effective_radius:
				var planet_velocity := Vector2(nearest.get("velocity"))
				var rel_speed: float = (velocity - planet_velocity).length()
				if rel_speed < landing_speed_threshold:
					landed = true
					landed_planet = nearest
					landed_offset = global_position - nearest.global_position
					velocity = planet_velocity
					# Auto-orient nose-outward so first thrust = launch.
					rotation = (global_position - nearest.global_position).angle()

					# Astronaut delivery (carrying on home planet) takes precedence over pickup.
					if carrying_astronaut and landed_planet.get("is_home"):
						carrying_astronaut = false
					else:
						# Try to pick up an astronaut on this planet.
						var astronaut := landed_planet.get_node_or_null("Astronaut")
						if astronaut != null and not astronaut.get("picked_up"):
							# Reuse the outer `planet_radius` (nearest.radius × scale),
							# which is the astronaut's actual world distance from the planet center.
							var pickup_radius: float = planet_radius * astronaut_pickup_radius_multiplier
							var dist_to_astronaut: float = global_position.distance_to(astronaut.global_position)
							if dist_to_astronaut <= pickup_radius:
								astronaut.call("pick_up")
								carrying_astronaut = true
								picked_up_count += 1
							_audio_manager.play_astronaut_pickup()
				else:
					crashed = true
					crashed_planet = nearest
					crashed_offset = global_position - nearest.global_position
					velocity = Vector2.ZERO

	# --- Normal flight ---
	var rot_dir := 0.0
	if Input.is_action_pressed("rotate_left"):
		rot_dir -= 1.0
	if Input.is_action_pressed("rotate_right"):
		rot_dir += 1.0
	rotation += rot_dir * rotation_speed * delta

	if Input.is_action_pressed("thrust"):
		if fuel > 0.0:
			fuel -= fuel_consumption_rate * delta
			var forward := Vector2.RIGHT.rotated(rotation)
			velocity += forward * thrust_acceleration * delta

	var total_accel := Vector2.ZERO
	for body in get_tree().get_nodes_in_group("attractors"):
		if body == self:
			continue
		var mass_value: float = float(body.get("mass"))
		var to_attractor: Vector2 = body.global_position - global_position
		var r := maxf(to_attractor.length(), 1.0)
		var accel_mag := G * mass_value / (r * r)
		total_accel += to_attractor.normalized() * accel_mag
	velocity += total_accel * delta
	position += velocity * delta

	# Fuel pickup collection: scan the "fuel" group, collect anything in range.
	# queue_free is deferred to end-of-frame, so each pickup is collected at
	# most once per physics tick.
	for pickup in get_tree().get_nodes_in_group("fuel"):
		if pickup == null or not is_instance_valid(pickup):
			continue
		if global_position.distance_to(pickup.global_position) <= fuel_pickup_radius:
			fuel = minf(fuel + fuel_pickup_amount, max_fuel)
			pickup.queue_free()
			_audio_manager.play_fuel_pickup()


# Triangle with nose at +X (forward when rotation = 0).
func _unhandled_input(event: InputEvent) -> void:
	# R key restarts the level by reloading the current scene. Rocket state,
	# planet positions, and the level_controller all reset to fresh values.
	# Works during gameplay (the typical case). The level_controller's
	# `is_instance_valid(self)` guard handles the rare case of pressing R
	# during the win/lose 0.5s transition delay.
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


func _make_triangle(s: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(s, 0.0),
		Vector2(-s * 0.8, -s * 0.6),
		Vector2(-s * 0.8,  s * 0.6),
	])


# Find the closest body in "attractors" that's a valid landing target.
# Skips the rocket itself and any attractor without a `radius` (e.g. the sun —
# it's still a gravity source, but not a landing target).
func _find_nearest_attractor() -> Node2D:
	var nearest: Node2D = null
	var nearest_d2: float = INF
	for body in get_tree().get_nodes_in_group("attractors"):
		if body == self:
			continue
		if body.get("radius") == null:
			continue
		var d2: float = global_position.distance_squared_to(body.global_position)
		if d2 < nearest_d2:
			nearest_d2 = d2
			nearest = body
	return nearest
