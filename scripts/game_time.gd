extends RefCounted
class_name GameTime
##
## Global game-time clock. Resets to 0 at each level start; advances by
## `delta` each physics tick.
##
## Used by bodies (planet.gd, moon.gd, asteroid.gd) to compute their
## position via `orbit_calculator.gd`. Lives as a static utility class
## so any script can read `GameTime.current` without a Node reference.
##
## Why a static class rather than an autoload or a member of some
## existing script: bodies live per-level and shouldn't know about the
## level controller; an autoload adds a project.godot entry and another
## file to track; a static class is the simplest possible global state.

## Current game time in seconds (sim time, which already factors in
## `Engine.time_scale` via Godot's `_physics_process` delta — see the
## note on `tick()` below for why the multiplier isn't here).
## Reset to 0 by `level_controller.gd::_initialize()` each time a level
## loads.
static var current: float = 0.0


## Reset the clock to 0. Called by `level_controller.gd::_initialize()`
## at the start of each level.
static func reset() -> void:
	current = 0.0


## Advance the clock by one physics frame.
##
## IMPORTANT: `_physics_process(delta)` in Godot 4 already receives a
## delta that is scaled by `Engine.time_scale` (it represents sim-time
## since the last tick — see the Node class docs and the Godot 4.5+
## forum confirmation). So accumulating `delta` directly here gives
## the correct sim-time advance at any warp:
##  - at 1×, GameTime advances 1 sim-second per real second
##  - at 8×, GameTime advances 8 sim-seconds per real second
##  - at 0.5×, GameTime advances 0.5 sim-seconds per real second
## Planets/asteroids read `GameTime.current` and pass it into
## `OrbitCalculator.compute_state(..., t, M)`, so their closed-form
## positions scale correctly with warp.
##
## Earlier this function multiplied by `Engine.time_scale` again, which
## double-counted: planets effectively advanced at `time_scale²`
## sim-seconds per real second, while the rocket's own integration
## (which uses `delta` directly in rocket.gd) advanced at `time_scale`.
## At 8× warp the planet visibly orbited 8× faster than the rocket —
## what would previously have read as a planet "too fast".
static func tick(delta: float) -> void:
	current += delta
