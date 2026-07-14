extends Node2D
##
## MenuBackground: non-interactive mini-level running behind the main
## menu UI. Loads `data/levels/background.json` (level schema v3, same
## format as gameplay levels) and builds the scene via
## `LevelLoader.build_scene_from_spec` — the same code path the
## gameplay uses, so visual style stays consistent and there's only
## one place to fix orbit-math bugs.
##
## Animation: a Camera2D orbits the sun at a small radius while its
## zoom oscillates on a slow cycle. Both use sin/cos so the loop is
## seamless (no jump-back to start). Tuned to feel like a slow
## establishing shot, not a kinetic intro.
##
## IMPORTANT — scope of the Camera2D's transform:
## In Godot 4 a Camera2D that becomes current applies its transform to
## every CanvasItem it can reach. Earlier attempts at this menu UI
## tried (a) leaving Camera2D at scene-root, which scaled every
## Control into the bottom-right of the screen; then (b) wrapping
## MenuBackground in a CanvasLayer, which the diagnostic proved had
## no scoping effect — the same Camera2D showed up as the root
## viewport's current camera, and its transform leaked into the
## Background ColorRect anyway.
##
## Working approach: MenuBackground (and its Camera2D, sun, planets,
## their Line2D children) lives inside a dedicated SubViewport
## (`OrbitalViewport` under `OrbitalViewportContainer` in
## scenes/main_menu.tscn). SubViewport has its own World2D + camera,
## so the Camera2D's transform is truly isolated to the orbital
## scene's canvas only — the main Viewport keeps an identity
## canvas_transform, so the Background ColorRect and the menu
## CenterContainer stay full-rect and the menu UI sits on top
## unchanged.
##
## Note on Line2D alignment: `planettrajectoryline_2d.gd` reads
## `get_viewport().get_canvas_transform()` to place orbit markers.
## Inside the SubViewport, that resolves to the SubViewport's
## canvas_transform (driven by THIS Camera2D), so markers, planet
## bodies, and ellipse lines all share the same transform — they
## align. The previous CanvasLayer-based attempt got the geometry
## wrong because the cameras leaked through to the root viewport.
##
## GameTime side effect: `_process` calls `GameTime.tick(delta)` so the
## background bodies actually orbit. When a level loads,
## `level_controller.gd::_initialize` calls `GameTime.reset()`, so
## menu-idle time doesn't bleed into gameplay. Same code path the
## gameplay uses for the clock.
##

## Path to the JSON spec. Lives alongside the gameplay levels
## (`data/levels/level_NN.json`) but uses `background.json` so it's
## clearly distinct from playable levels.
const BACKGROUND_JSON_PATH := "res://data/levels/background.json"

# --- Camera animation tuning ---
#
# Pan: camera orbits the sun at PAN_RADIUS units. With the sun at
# world origin and bodies orbiting between ~500 and ~5000, a small
# PAN_RADIUS keeps the whole system roughly centered on screen.
# PAN_SPEED is in rad/sec; 0.04 → one full revolution per ~157 sec.
const PAN_RADIUS := 200.0
const PAN_SPEED := 0.04

# Zoom: oscillates between (ZOOM_BASE - ZOOM_AMPLITUDE) and
# (ZOOM_BASE + ZOOM_AMPLITUDE). 0.30 ↔ 0.55 keeps all bodies' orbit
# lines visible at low zoom (Pluto at orbit 5000 → ~1500 px from
# center) and makes inner planets prominent at high zoom (Mercurius
# at orbit 500 → ~275 px from center).
# ZOOM_PERIOD is rad/sec; 0.05 → full cycle per ~126 sec.
const ZOOM_BASE := 0.425
const ZOOM_AMPLITUDE := 0.125
const ZOOM_PERIOD := 0.05


# Cached camera reference (resolved by @onready from the scene tree).
@onready var camera: Camera2D = $Camera2D

# Animation clock. Drives both pan angle and zoom phase. Survives
# tree-pause cycles (when the settings menu opens and closes), so
# the background picks up exactly where it left off.
var _time: float = 0.0


## Load background.json, validate, build the scene. Resets GameTime so
## the background starts at t=0 every time the menu loads (predictable
## restart behavior — main_menu.tscn reloads on every visit from the
## win/lose screen, so _ready fires fresh).
##
## No rocket in the "player" group means the rocket-config block
## inside `build_scene_from_spec` is a no-op — bodies + orbit lines
## only. Orbit lines come for free since `planet.tscn` has a Line2D
## (`planettrajectoryline_2d.gd`) as a child.
func _ready() -> void:
	GameTime.reset()

	var file := FileAccess.open(BACKGROUND_JSON_PATH, FileAccess.READ)
	if file == null:
		push_error("MenuBackground: failed to open %s" % BACKGROUND_JSON_PATH)
		return
	var json_text := file.get_as_text()
	file.close()

	var data: Variant = JSON.parse_string(json_text)
	if not data is Dictionary:
		push_error("MenuBackground: failed to parse JSON in %s" % BACKGROUND_JSON_PATH)
		return

	# Same schema check level_loader does. Background uses v3 like the
	# other levels; if someone authors a v4 later, this guard prevents
	# silent breakage.
	var version: int = data.get("version", 0)
	if version != 3:
		push_error("MenuBackground: unsupported schema version %d (expected 3)" % version)
		return

	# Build the scene. `self` is the MenuBackground node — it has
	# SunContainer + BodyContainer as direct children, matching what
	# build_scene_from_spec expects. No rocket, no LevelController,
	# no HUD, no PauseMenu — pure orbital showcase.
	LevelLoader.build_scene_from_spec(data, self)


## Advance animation + GameTime each frame. Both pan and zoom use
## pure sin/cos so the cycle is seamless (no jump-back).
##
## Tree-pause interaction: when the settings menu opens it calls
## `get_tree().paused = true`, which stops this `_process` from
## firing. GameTime freezes too (no `_process` to tick it). When the
## settings menu closes, both resume from where they left off.
func _process(delta: float) -> void:
	_time += delta
	GameTime.tick(delta)

	if camera == null:
		return  # Camera2D missing from scene tree; nothing to animate

	# Slow pan: camera position traces a small circle around the sun.
	# PAN_RADIUS is small relative to scene scale (bodies orbit at
	# 500-5000), so the system stays roughly centered.
	var angle: float = _time * PAN_SPEED
	camera.position = Vector2(cos(angle), sin(angle)) * PAN_RADIUS

	# Subtle zoom oscillation around ZOOM_BASE. The sin wave is offset
	# by zero, so the cycle starts at ZOOM_BASE and smoothly oscillates.
	var zoom: float = ZOOM_BASE + ZOOM_AMPLITUDE * sin(_time * ZOOM_PERIOD)
	camera.zoom = Vector2.ONE * zoom
