extends Node2D
##
## The player rocket — controllable spacecraft.
##
## - Lives in group "player" so the HUD, indicators, and level_controller
##   can find us via get_first_node_in_group("player").
## - Listens to thrust/rotate/restart input each physics tick.
## - Feels gravity from every body in the "attractors" group.
## - Detects landing vs. crash via distance check against the nearest
##   planet (skill §3.1: per-frame distance, not Area2D signals).
## - On land, glues to the planet and matches its velocity; thrust
##   unsticks (auto-oriented so the first thrust = launch).
## - Carries fuel and astronaut pickups; refuels on fuel-pickup contact.
##

# --- Visual ---

## Triangle size — controls both the rendered Polygon2D and the
## landing-collision tail reach. They must stay in sync (see
## `tail_reach = size * 0.8` in _physics_process).
@export var size: float = 10.0

## Fill color for the rocket's triangle visual.
@export var color: Color = Color(0.9, 0.95, 1.0)

## Minimum visual size, as a multiple of `size`. The rocket's Polygon2D
## is scaled by `min_visual_scale / zoom_factor` each frame so the
## on-screen display size stays roughly constant at `min_visual_scale ×
## size` pixels regardless of how far the camera is zoomed out. Bump
## this up if the rocket is still hard to spot at extreme zoom-out.
## Visual only — physics size, collision radius, and trajectory math
## all use the underlying `size` directly (unchanged).
@export var min_visual_scale: float = 1.75

# --- Initial conditions ---

## Spawn position used ONLY if no planet is flagged `is_home`.
## Otherwise the rocket auto-snaps to the home planet's surface
## in _snap_to_home_planet.
@export var initial_position: Vector2 = Vector2(300.0, 0.0)

## Spawn velocity used ONLY if no planet is flagged `is_home`.
## Tangent to a circular orbit at initial_position, around the sun.
@export var initial_velocity: Vector2 = Vector2(0.0, 115.0)

## Starting fuel amount. Burned by thrust (see fuel_consumption_rate);
## refilled by fuel pickups up to max_fuel.
@export var fuel: float = 100.0

## Maximum fuel cap — pickups can't push fuel above this.
@export var max_fuel: float = 100.0

# --- Controls ---

## Rotation speed when A/D (or arrow keys) are held. In radians per
## second. 3.0 ≈ half-turn per second — increase for snappier ships.
@export var rotation_speed: float = 3.0

## Thrust acceleration at full throttle, along the rocket's nose.
## In units per second². With the variable-thrust system, this is the
## force applied at `throttle = 1.0` — actual thrust scales linearly
## with the current `throttle` value.
@export var thrust_acceleration: float = 200.0

## Current throttle level in [0.0, 1.0]. 0 = idle (no thrust), 1 = full
## thrust. Ramps up/down via Shift/Ctrl input (handled in _process so
## the rate is in real seconds, not scaled by Engine.time_scale).
## Snaps to 0 on landing or crash. The thruster audio volume and the
## HUD throttle bar both read this value.
@export var throttle: float = 0.0

## How fast `throttle` changes per real-second when Shift/Ctrl is held.
## 0.5 = full sweep in 2 seconds (KSP-ish feel). Higher = snappier.
@export var throttle_change_rate: float = 0.5

## Threshold below which throttle is treated as "off" — gates the
## "unstick from landed" check and the audio deadzone. Matches
## AudioManager.THRUSTER_DEADZONE so behavior is consistent across
## the rocket ↔ audio boundary.
const THROTTLE_DEADZONE := 0.001

# --- Collision (skill §3.1: distance-based, not Area2D signals) ---

## Maximum relative speed for a contact to count as "soft" (else crash).
## At rel_speed ≤ this on contact, the rocket sticks; > this, it crashes.
@export var landing_speed_threshold: float = 60.0

## Extra distance past the visual contact point at which the landing
## trigger fires. Small overshoot so the rocket doesn't appear to
## "land floating" right at the visual edge.
@export var landing_buffer: float = 0.5

## Minimum relative speed for a contact to count as a crash. Anything
## in the gap (landing_speed_threshold, crash_speed_threshold) lands
## as a crash because it's too fast to be safe.
@export var crash_speed_threshold: float = 80.0

## Fraction of the tangent-velocity mismatch (rocket vs. planet)
## closed each physics tick while in contact with a landable body.
## 0.5 = settle in ~10 ticks (snappy, current default). Lower = more
## skid/slip, higher = stickier landing. The biggest feel lever for
## the continuous-physics landing model — sweep this first if
## landings feel too slippery or too glued.
@export var tangent_damping: float = 0.5

# --- Astronaut pickup ---

## Pickup is proximity-based on landing. The pickup zone is this
## many times the planet's radius around the landing point.
## Tighter (1.0) = more precise "near the astronaut" landings needed.
@export var astronaut_pickup_radius_multiplier: float = 1.5

# --- Fuel ---

## Fuel burned per second of thrust. At time warp 8×, this becomes
## effectively 8× per real second (delta scales with Engine.time_scale).
## Dial down to ~0.5 for unconstrained testing, ~5 for normal play.
@export var fuel_consumption_rate: float = 7.5

## Fuel restored per pickup, capped at max_fuel.
@export var fuel_pickup_amount: float = 50.0

## Rocket-to-pickup distance below which a fuel pickup is collected.
## In world units.
@export var fuel_pickup_radius: float = 30.0

# --- Physics constants (matches planet.gd and the trajectory predictor) ---
const G := 1.0

# --- Runtime state ---

# Cached linear velocity. Mutated by gravity, thrust, and the landed-
# glue logic. Read by the trajectory predictor and the HUD.
var velocity: Vector2 = Vector2.ZERO

# Visual triangle; we set its polygon and color in _ready.
@onready var _poly: Polygon2D = $Polygon2D

# Cached reference to the AudioManager autoload (resolved by path —
# see skill §6.1: autoloads can parse-fail if the project hasn't
# been reopened in the editor after manual project.godot edits).
@onready var _audio_manager: Node = get_node("/root/AudioManager")

# Informational: true while the rocket is currently in contact with a
# landable body (i.e. sitting on a planet). Edge-triggered: set on
# the first tick of contact with rel_speed < landing_speed_threshold,
# cleared when contact ends. Read by level_controller.gd for the
# win check; rocket.gd's own physics is continuous and doesn't gate
# on this flag.
var landed: bool = false

# True once the rocket has crashed (frozen on the crashed_planet).
var crashed: bool = false

# Planet we're currently in contact with (informational). null when
# in flight. level_controller.gd reads this for the home-planet
# win check on landing.
var landed_planet: Node2D = null

# Planet we crashed into. null when in flight or landed.
var crashed_planet: Node2D = null

# Position offset from crashed_planet (where on the planet we hit).
var crashed_offset: Vector2 = Vector2.ZERO

# --- Astronaut state ---

# True while carrying an astronaut back to the home planet. Cleared
# when we land on the home planet (delivery).
var carrying_astronaut: bool = false

# Total astronauts picked up across the level. Read by the HUD
# (renders ● picked vs ○ unpicked) and by level_controller (win check).
var picked_up_count: int = 0

# --- Time warp ---

# Discrete time-warp levels. Press > / < to step through them; index
# 0 = 1× (real-time), max = 32×. Engine.time_scale drives the global
# sim rate — physics, _process, etc. all run faster, and delta scales
# with it, so fuel burn at 32× is 32× per thrust tick. 32× added 2026-07-09
# because 16× wasn't fast enough for far-out orbits (waiting on
# periapsis at 9000 px takes too long at 16×).
const TIME_WARP_LEVELS: Array[float] = [1.0, 2.0, 4.0, 8.0, 16.0, 32.0]

# Current index into TIME_WARP_LEVELS.
var time_warp_index: int = 0


## Set the visual polygon, place the rocket (snap to home planet if one
## exists, else use initial_position), and add to the "player" group.
func _ready() -> void:
	_poly.color = color
	_poly.polygon = _make_triangle(size)

	position = initial_position
	velocity = initial_velocity
	add_to_group("player")
	rotation = 0.0

	# If a planet is flagged as is_home, snap the rocket to its surface
	# (riding the planet in its direction of motion) instead of using
	# the scene's initial_position. If no is_home planet exists, the
	# scene's initial_position and initial_velocity are used as fallbacks.
	#
	# Deferred because LevelLoader is a sibling of the rocket and adds
	# planets to the "attractors" group in its own _ready. _ready runs
	# bottom-up, so LevelLoader hasn't run yet by this point — calling
	# _snap_to_home_planet() directly would find an empty group and
	# silently no-op, stranding the rocket at initial_position.
	# call_deferred runs after all _ready completes, so earth is in
	# the group by the time this fires.
	call_deferred("_snap_to_home_planet")


## Each frame: scale the visual polygon based on camera zoom + handle
## throttle input. Throttle input lives in _process (not _physics_process)
## so the ramp rate is in real seconds — `delta` here doesn't scale with
## Engine.time_scale, so 32× time warp doesn't make the throttle 32×
## faster to respond. Visual scale and input are unrelated, but both
## are render-rate work so they share the function.
func _process(delta: float) -> void:
	# Visual scale: same convention as trajectoryline_2d.gd: zoom_factor
	# in [0.1, 1.0], where lower = more zoomed-out (objects smaller on
	# screen) and 1.0 = the upper edge of the clamp (zoomed in past 1.0,
	# the rocket is already plenty big, so we don't keep scaling up).
	var cam := get_viewport().get_camera_2d()
	var zoom_factor: float = clampf(cam.zoom.x, 0.1, 1.0) if cam != null else 1.0
	# Divide min_visual_scale by zoom_factor so on-screen size stays
	# constant across zooms. With min_visual_scale = 1.5 and size = 10,
	# the rocket is roughly 30 px wide at any zoom in [0.1, 1.0].
	_poly.scale = Vector2.ONE * (min_visual_scale / zoom_factor)

	# Throttle input. Skipped when crashed — once the rocket is dead,
	# the throttle bar is hidden (hud.gd) and the value is frozen at 0
	# (set by the crash branch in _physics_process). Letting the user
	# shift up while crashed would be confusing.
	if crashed:
		return
	if Input.is_action_pressed("thrust_up"):
		throttle = minf(throttle + throttle_change_rate * delta, 1.0)
	if Input.is_action_pressed("thrust_down"):
		throttle = maxf(throttle - throttle_change_rate * delta, 0.0)
	if Input.is_action_just_pressed("thrust_kill"):
		throttle = 0.0


## If a planet in the "attractors" group has `is_home = true`, place
## the rocket on its surface in the direction of the planet's motion
## (so the rocket is "riding" the planet at the home position).
## Pre-sets `landed = true` so the first physics tick's edge-detection
## sees the rocket as already on the planet and skips the spurious
## landing event (otherwise the snap would auto-pickup any astronaut
## on the home planet). Physics after this point is continuous — no
## glue flag, no unstick threshold. If no is_home planet is found,
## does nothing (scene's initial_position and initial_velocity remain
## in effect).
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
		# 8.0 is the rocket's tail-reach offset (matches the tail-reach
		# math in _physics_process). Keeps the rocket visually "sitting"
		# on the surface rather than centered on it.
		var surface_pos: Vector2 = planet_pos + facing * (planet_radius + 8.0)
		global_position = surface_pos
		velocity = planet_vel
		rotation = (global_position - planet_pos).angle()
		# Pre-set landed + landed_planet so the first physics tick's
		# edge-detection sees landed=true and doesn't fire a spurious
		# landing event. With continuous physics, being in contact is
		# the source of truth; landed just remembers it across frames.
		landed = true
		landed_planet = body
		return


## Per-tick update: time-warp input, audio gating, contact physics
## (normal force + tangent damping when in contact), landing/crash
## edge events, normal flight integration, and fuel-pickup collection.
## Order matters — see comments inline.
##
## Landing model (continuous-physics + edge-triggered-events):
## Being in contact with a landable body is detected per-tick. The
## physics response (position snap + radial velocity cancellation +
## tangent damping) keeps the rocket on the surface while landed. The
## `landed` flag is informational only — set/cleared on the in-flight
## ↔ in-contact edge transitions, read by `level_controller.gd` for
## the win check. Astronaut pickup and home delivery fire as edge
## events on the FIRST tick of contact with a landable body. There
## is no "break free" mechanic — the rocket lifts off whenever
## applied thrust exceeds gravity.
func _physics_process(delta: float) -> void:

	# Time warp input. Handled at the top so it works regardless of
	# crashed/landed state.
	if Input.is_action_just_pressed("time_warp_up"):
		time_warp_index = min(time_warp_index + 1, TIME_WARP_LEVELS.size() - 1)
		Engine.time_scale = TIME_WARP_LEVELS[time_warp_index]
	elif Input.is_action_just_pressed("time_warp_down"):
		time_warp_index = max(time_warp_index - 1, 0)
		Engine.time_scale = TIME_WARP_LEVELS[time_warp_index]

	# Thruster audio: tracks the current `throttle` value. Called at the
	# top so audio reflects current throttle every frame, including
	# crashed frames (where throttle is 0). The deadzone + play/stop
	# logic lives in `AudioManager.set_thruster_volume` — rocket.gd
	# just feeds it the throttle value.
	_audio_manager.set_thruster_volume(throttle)

	# Crashed: freeze on the surface where we hit. Once crashed, no
	# further input or physics — the level_controller's lose check
	# handles the scene transition.
	if crashed:
		if crashed_planet != null:
			global_position = crashed_planet.global_position + crashed_offset
		return

	# Defensive: if landed_planet is invalid (freed, or stale), clear
	# the landed state so level_controller doesn't read a null planet
	# on the win check.
	if landed and (landed_planet == null or not is_instance_valid(landed_planet)):
		landed = false
		landed_planet = null

	# Contact detection: nearest attractor + distance check. Drives
	# both the continuous-physics contact response (below) and the
	# edge-triggered landing events.
	var nearest := _find_nearest_attractor()
	var in_contact := false
	var contact_eff_r := 0.0
	if nearest != null:
		var planet_radius: float = float(nearest.get("radius")) * abs(nearest.global_scale.x)
		# size * 0.8 matches the back-vertex offset in _make_triangle —
		# the triangle is (s, 0), (-s*0.8, ±s*0.6), so the back vertex
		# is 0.8·s behind the center. Keep these in sync.
		var tail_reach: float = size * 0.8
		contact_eff_r = planet_radius + tail_reach + landing_buffer
		var dist: float = global_position.distance_to(nearest.global_position)
		in_contact = (dist <= contact_eff_r)

	if in_contact and nearest != null:
		# In contact with nearest. Apply contact response + edge events.
		var radial: Vector2 = (global_position - nearest.global_position).normalized()
		var planet_velocity: Vector2 = Vector2(nearest.get("velocity"))
		var rel_velocity: Vector2 = velocity - planet_velocity
		var is_landable: bool = nearest.get("is_landable")

		if not is_landable:
			# Non-landable body (sun, asteroids). Instant crash on contact.
			crashed = true
			crashed_planet = nearest
			crashed_offset = global_position - nearest.global_position
			velocity = Vector2.ZERO
			throttle = 0.0
			_audio_manager.play_rocket_crash()
			# No normal force, no settle — rocket is dead.
		else:
			# Landable body. Apply continuous contact physics:
			#   - Position snap to surface (avoid penetration)
			#   - Cancel inward radial velocity (implicit ground normal)
			#   - Damp tangent velocity toward planet's surface velocity
			#     so the rocket settles into the planet's frame of ref
			#     over a few ticks instead of sliding indefinitely.
			global_position = nearest.global_position + radial * contact_eff_r
			var radial_speed: float = rel_velocity.dot(radial)
			if radial_speed < 0.0:
				velocity -= radial * radial_speed
			var tangent: Vector2 = Vector2(-radial.y, radial.x)
			var tangent_diff: float = velocity.dot(tangent) - planet_velocity.dot(tangent)
			# Close `tangent_damping` of the gap each tick. 0.5 = snappy
			# settle (~10 ticks to within 0.1% of planet velocity).
			# Tune lower for more skid / higher for stickier landings.
			velocity -= tangent * tangent_diff * tangent_damping

			# Edge-triggered landing/crash: rel_speed threshold decides
			# soft-land vs. over-speed crash on the FIRST tick of
			# contact. After that, contact is sustained; the rocket
			# sits on the surface via the normal force above until
			# applied thrust exceeds gravity and lifts it off.
			var rel_speed: float = rel_velocity.length()
			if rel_speed < landing_speed_threshold:
				if not landed:
					# Edge: just landed. Informational flags set here;
					# level_controller reads these for the win check.
					landed = true
					landed_planet = nearest
					# Auto-orient nose-outward so thrust (when applied)
					# points away from the planet — otherwise the
					# default tangent orientation would just skid
					# along the surface.
					rotation = radial.angle()
					_handle_landing_event(nearest)
			else:
				# Over-speed crash on a landable body.
				crashed = true
				crashed_planet = nearest
				crashed_offset = global_position - nearest.global_position
				velocity = Vector2.ZERO
				throttle = 0.0
				_audio_manager.play_rocket_crash()
	elif landed:
		# Was in contact last tick, no longer in contact. Take off.
		landed = false
		landed_planet = null

	# --- Thrust + rotation (always runs, even when landed) ---
	var rot_dir := 0.0
	if Input.is_action_pressed("rotate_left"):
		rot_dir -= 1.0
	if Input.is_action_pressed("rotate_right"):
		rot_dir += 1.0
	rotation += rot_dir * rotation_speed * delta

	if throttle > THROTTLE_DEADZONE and fuel > 0.0:
		# Thrust scales linearly with throttle, so partial throttle
		# burns partial fuel — matches KSP's model and gives the
		# player fine control over fuel economy on long burns.
		fuel -= fuel_consumption_rate * throttle * delta
		var forward: Vector2 = Vector2.RIGHT.rotated(rotation)
		velocity += forward * thrust_acceleration * throttle * delta

	# Gravity from every attractor (sun + all planets + asteroids +
	# moons). Cancelled each tick by the radial-velocity-cancel step
	# above when in contact; otherwise accumulates normally so the
	# rocket orbits / falls.
	var total_accel: Vector2 = Vector2.ZERO
	for body in get_tree().get_nodes_in_group("attractors"):
		if body == self:
			continue
		var mass_value: float = float(body.get("mass"))
		var to_attractor: Vector2 = body.global_position - global_position
		# Floor at 1.0 to avoid division-by-zero singularities when the
		# rocket is exactly on top of an attractor (rare but possible
		# during a teleport or scene reload).
		var r: float = maxf(to_attractor.length(), 1.0)
		var accel_mag: float = G * mass_value / (r * r)
		total_accel += to_attractor.normalized() * accel_mag
	velocity += total_accel * delta
	position += velocity * delta

	# Fuel pickup collection: scan the "fuel" group, collect anything
	# in range. queue_free is deferred to end-of-frame, so each pickup
	# is collected at most once per physics tick.
	for pickup in get_tree().get_nodes_in_group("fuel"):
		if pickup == null or not is_instance_valid(pickup):
			continue
		if global_position.distance_to(pickup.global_position) <= fuel_pickup_radius:
			fuel = minf(fuel + fuel_pickup_amount, max_fuel)
			pickup.queue_free()
			_audio_manager.play_fuel_pickup()


## Edge-triggered landing event. Called from _physics_process on the
## first tick of contact with a landable body. Handles astronaut
## delivery + pickup; nothing else (crash/audio/state changes happen
## in the caller).
##
## Brief-graze pickups: a one-tick graze at low speed on a planet
## with an unpicked astronaut WILL fire pickup. Existing safeguards
## (astronaut.picked_up check, carrying_astronaut check for delivery)
## make spurious events no-ops in practice — picked_up astronauts
## stay picked up, and delivery requires carrying. If spurious fires
## become annoying in playtest, add a debounce here (require N
## consecutive in-contact ticks before firing).
func _handle_landing_event(planet: Node2D) -> void:
	# Astronaut delivery (carrying on home planet) takes precedence
	# over pickup. No delivery sound effect.
	if carrying_astronaut and planet.get("is_home"):
		carrying_astronaut = false
		return

	# Try to pick up an astronaut on this planet.
	var astronaut: Node = planet.get_node_or_null("Astronaut")
	if astronaut != null and not astronaut.get("picked_up"):
		# Reuse the outer `planet_radius` (nearest.radius × scale),
		# which is the astronaut's actual world distance from the
		# planet center.
		var planet_radius: float = float(planet.get("radius")) * abs(planet.global_scale.x)
		var pickup_radius: float = planet_radius * astronaut_pickup_radius_multiplier
		var dist_to_astronaut: float = global_position.distance_to(astronaut.global_position)
		if dist_to_astronaut <= pickup_radius:
			astronaut.call("pick_up")
			carrying_astronaut = true
			picked_up_count += 1
			# SFX fires only on actual pickup (not whenever the rocket
			# merely lands near an astronaut).
			_audio_manager.play_astronaut_pickup()


## Handle the restart key (R) — reloads the current scene. Rocket state,
## planet positions, and the level_controller all reset to fresh values.
## The level_controller's `is_instance_valid(self)` guard handles the
## rare case of pressing R during the win/lose 0.5s transition delay.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


## Build the rocket's triangle polygon. Nose at +X (so the rocket
## "points forward" when rotation = 0 and thrust pushes +X).
## The (s, 0), (-s*0.8, ±s*0.6) layout gives a 0.8·s tail-reach —
## keep this in sync with `tail_reach = size * 0.8` in _physics_process.
func _make_triangle(s: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(s, 0.0),
		Vector2(-s * 0.8, -s * 0.6),
		Vector2(-s * 0.8,  s * 0.6),
	])


## Find the closest body in "attractors". Skips the rocket itself.
## Every attractor has a `radius` now (sun got one), so no per-type
## filtering here — land-vs-crash decision lives in the collision
## branch based on the body's `is_landable` flag.
func _find_nearest_attractor() -> Node2D:
	var nearest: Node2D = null
	var nearest_d2: float = INF
	for body in get_tree().get_nodes_in_group("attractors"):
		if body == self:
			continue
		# Every attractor has a `radius` now (sun got one in the
		# sun-collision fix). The collision branch in `_physics_process`
		# decides land vs. crash based on `is_landable`, not here.
		var d2: float = global_position.distance_squared_to(body.global_position)
		if d2 < nearest_d2:
			nearest_d2 = d2
			nearest = body
	return nearest
