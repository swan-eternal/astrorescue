extends RefCounted
class_name GameTime
##
## Global game-time clock. Resets to 0 at each level start; advances by
## `delta * Engine.time_scale` each physics tick.
##
## Used by bodies (planet.gd and future moon.gd, asteroid.gd) to compute
## their position via `orbit_calculator.gd`. Lives as a static utility
## class so any script can read `GameTime.current` without a Node
## reference.
##
## Why a static class rather than an autoload or a member of some
## existing script: bodies live per-level and shouldn't know about the
## level controller; an autoload adds a project.godot entry and another
## file to track; a static class is the simplest possible global state.

## Current game time in seconds (real time × Engine.time_scale).
## Reset to 0 by `level_controller.gd::_initialize()` each time a level
## loads.
static var current: float = 0.0


## Reset the clock to 0. Called by `level_controller.gd::_initialize()`
## at the start of each level.
static func reset() -> void:
	current = 0.0


## Advance the clock by one physics frame. The actual delta is
## multiplied by `Engine.time_scale` so time-warp affects the simulation
## uniformly — at 8× time warp, planets move 8× faster (since their
## position is computed from the closed-form math at `GameTime.current`,
## and that value is advancing 8× per real second).
static func tick(delta: float) -> void:
	current += delta * Engine.time_scale