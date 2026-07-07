# Astro-Rescue

> **Status (2026-07-06):** Core gameplay loop working end-to-end — land on home planet, take off, transfer between planets via gravity, rescue astronaut, return home, win/lose flow all functional. **13 commits ahead of origin/main**, not yet pushed. Working tree clean except this doc's in-progress updates and one stale untracked `scenes/level_01.tscn` (left over from before Stage 5 cleanup).
>
> **Engine:** Godot 4.x
> **Project root:** `rocketman/astrorescue-main/rocketman/`

## Concept

2D arcade game. Player starts landed on a home planet, launches with limited fuel, transfers between planets via gravity, rescues stranded astronauts, returns to base. Crash on high-speed planet impacts. Fuel pickups at intermediate bodies. Series of hand-crafted levels with rising difficulty.

## What's Complete

### Closed-form orbit + JSON-driven levels — refactor stages (5/5 + post-refactor)

**Stage 1** (`4a0df4d`) — Foundation:
- `scripts/orbit_calculator.gd` — pure-math helper. Static functions: orbital elements + t + central_mass → position/velocity. Kepler equation via Newton-Raphson (3 iterations), vis-viva velocity, world-frame rotation.
- `SaveState.current_level_number` — used by level routing.
- `data/levels/level_01.json` — initial level data.

**Stage 2** (`742e27d`) — Closed-form planet orbits:
- `scripts/planet.gd` rewritten to call `OrbitCalculator.compute_state(perihelion, aphelion, angle_of_aphelion, phase, GameTime.current, sun_mass)` in `_physics_process`. No more Euler integration.
- New @exports: `perihelion`, `aphelion`, `angle_of_aphelion`, `phase` (replaced `orbit_radius` + `initial_speed_multiplier`).
- `scripts/game_time.gd` — static class with `current`, `reset()`, `tick(delta)`. Bodies read `GameTime.current` without a Node reference.
- `level_controller.gd` calls `GameTime.reset()` in `_initialize()` and `GameTime.tick(delta)` in `_physics_process`. Time-warp works uniformly (8× warp → planets move 8× faster).
- `level_01.tscn` updated to use new @exports.

**Stage 3** (`5fde0e7`) — Shared `level.tscn` + JSON-driven loading:
- `scripts/level_loader.gd` — reads `data/levels/level_<n>.json` (n from `SaveState.current_level_number`), instantiates bodies from the `bodies[]` spec, configures the rocket's @exports. Per skill §1.5, @exports assigned AFTER `add_child` so the script is fully initialized.
- `scenes/level.tscn` — new shared scene with infrastructure only (LevelController, SunContainer, PlanetContainer, rocket placeholder with rocketCamera child, HUD, LevelLoader). No per-level bodies.
- Wired `SaveState.current_level_number` through `level_select._on_level_selected`, `main_menu._on_start_pressed`, `win_screen._on_restart_pressed`, `lose_screen._on_restart_pressed`. Fixes the hardcoded `'level_01.tscn'` Restart bug.
- `data/levels/level_02.json`, `data/levels/level_03.json` authored with circular orbits (positions match originals exactly, verified via Python port).

**Stage 4** (`defc6e0`) — Closed-form trajectory line:
- `scripts/trajectoryline_2d.gd` rewritten to use closed-form orbital mechanics instead of Velocity Verlet forward-sim. Forward-sim was drifting by ~80 world units after 5 seconds for an eccentric orbit (e=0.37) — closed-form is exact.
- New @export `ellipse_segments: int = 128` replaces the old `steps` + `step_dt`.
- New `_compute_elements_from_state(r, v, mu)` helper converts (r, v) to orbital elements so `OrbitCalculator.compute_state` can sample at any future time.
- Time markers preserved (t+5s, t+10s, t+15s along the orbit).
- Removed dead code: `_simulate_heliocentric`, `_planet_accel`, `_rocket_accel`, `_PlanetSim` inner class.
- `scenes/rocket.tscn` cleaned up: removed orphan `steps = 1500` and `step_dt = 0.1`, replaced with `ellipse_segments = 128`.

**Stage 5** (`02d98cd`) — Cleanup:
- Deleted `scenes/level_01.tscn`, `level_02.tscn`, `level_03.tscn` (obsolete, replaced by shared `level.tscn` + JSON).
- Fixed regression in `planettrajectoryline_2d.gd::_compute_orbit_markers` — was reading removed `orbit_radius` @export, now reads `perihelion`/`aphelion` and computes semi-major axis as their average.

**Post-refactor feature** (`c90542d`) — Trajectory modes:
- Renamed enum: `Mode { TRUE, ORBITAL }` → `Mode { ELLIPSE, PROJECTED }`.
- `ELLIPSE` mode: closed-form orbit. **Auto-switches to nearest planet orbit** when rocket is inside its SOI (Hill sphere × `soi_fraction`). No more manual toggle — happens automatically based on proximity.
- `PROJECTED` mode: forward-simulated trajectory under sun + every planet's gravity. Planet positions sampled via `OrbitCalculator.compute_state(planet's elements, GameTime.current + step_dt, sun_mass)` at each step (so planet motion is exact; only the rocket is numerically integrated). 300 steps × 0.05s = 15s of predicted path. Symplectic Euler.
- Time markers work in both modes. ELLIPSE: closed-form (exact on the orbital ellipse). PROJECTED: indices into the forward-simulated polyline.
- `scripts/hud.gd` updated to label modes as "ELLIPSE" / "PROJECTED" instead of "TRUE" / "ORBITAL".
- Renamed color @exports: `true_color` → `closed_form_sun_color`, `orbital_color` → `closed_form_planet_color`. New `projected_color` (light blue) for PROJECTED mode.
- New @exports for PROJECTED tuning: `projected_steps: int = 300`, `projected_step_dt: float = 0.05`.

### Loose-ends cleanup — 5 commits, head `88afd46`

A long debug session surfaced and fixed several init-order and `@export`-timing bugs that the refactor had masked. Each fix in its own commit for review:

**`1302eb9` — `fix(loader): apply_visual + spawn_dynamic_children + configure_rocket trim`**

Root cause: `planet._ready` built visuals and spawned children from `@export` values that `level_loader` was assigning AFTER `add_child` (skill §1.5). At `_ready` time those `@export`s were still defaults, so visual size/color used placeholders and astronaut/fuel children were never spawned. Fix: two new methods called explicitly by `level_loader` once `@export`s are set.

- `planet.apply_visual()` — rebuilds the Polygon2D color/shape from current `radius` / `color`. Fixes "all planets render as small default dots."
- `planet.spawn_dynamic_children()` — instantiates `Astronaut` and `FuelPickup` children based on `has_astronaut` / `has_fuel` flags. Fixes "no astronauts visible."
- `_configure_rocket` stripped to position/velocity only — game-wide physics live in `rocket.gd` `@export`s (paired with `4908453` below).

**`7931e51` — `fix(trajectory): bounds guard + lazy-init sun + PROJECTED-only markers`**

Three bugs in `trajectoryline_2d.gd` / scene init order:

- Out-of-bounds crash on Tab when `_simulate_projected` returned empty (`sun_mass <= 0` during early init). Manual if/elif clamp could produce `index = -1` then access `points[-1]`. Replaced with `clampi` + empty-guard.
- `_find_sun()` in `_ready` returned `null` — `trajectoryline._ready` runs before `LevelLoader._ready` (LevelLoader is a sibling that adds the sun). Lazy retry in `_process` caches the result on first success.
- Marker dots in ELLIPSE mode were fixed-time samples on the closed-form ellipse — clutter on top of the ellipse itself. Marker sampling is now PROJECTED-only.

**`c3e4541` — `fix(planet-orbit-line): sample elements directly, kill high-warp breathing`**

The derive-from-state approach computed `omega` (argument of periapsis) from `(r, v)` each frame, where `r` and `v` come from Newton-Raphson Kepler iteration with machine-epsilon precision. At low warp this is invisible; at 8× warp the per-frame `omega` wobble translated to a visible slow "breathing" pulse on the planet's orbit line.

Now reads the `@export` orbital elements (constants set from JSON) and samples `OrbitCalculator.compute_state` at evenly-spaced times around one period. The line is identical frame-to-frame modulo inspector edits to the elements themselves.

(Same derive-from-state pattern exists in `trajectoryline_2d.gd::_orbit_ellipse` for the rocket's ELLIPSE mode but masked by the rocket's own per-frame motion; left alone, can refactor if it ever visibly breathes.)

**`4908453` — `refactor(rocket): single source of truth + min_visual_scale`**

- Triple-source-of-truth: rocket physics (thrust, landing/crash thresholds, fuel) were settable in `rocket.gd` `@export`, `rocket.tscn` scene override, AND `level_NN.json` rocket section. Moved all game-wide physics into `rocket.gd` `@export`s. JSON rocket sections are now placement-only (`initial_position`, `initial_velocity`).
- Dropped dead `launch_speed` `@export` (declared + assigned from JSON, never read) from JSON, script, and scene.
- New `min_visual_scale` `@export` (default 1.5): rocket Polygon2D scales inversely with camera zoom, keeping on-screen size constant at `min_visual_scale × size` pixels. Visual-only — physics, collision, trajectory math unchanged.
- `call_deferred("_snap_to_home_planet")` — same init-order class as the trajectory fixes; rocket was stranded at `initial_position` instead of glued to the home planet.

**`88afd46` — `chore: trailing-newline cleanups + uid regeneration`**

Drive-by trailing-newline normalization across `audio_manager` / `main_menu`. Auto-generated `.uid` files for `game_time`, `level_loader`, `orbit_calculator` now tracked (Godot editor regenerates these for cross-script references; see TODO about whether `.gitignore` would be cleaner).

## Architecture

### Autoloads (`project.godot`)
- `SaveState` (`scripts/save_state.gd`) — persistent game progress (`highest_level_completed`, `current_level_number`); saved to `user://save.json`
- `AudioManager` (`scripts/audio_manager.gd`) — music + SFX (menu + gameplay music, thruster loop, pickup SFX)

### Scene Tree (per level — from `scenes/level.tscn`)
```
level (Node2D)
├── LevelController (Node) — `scripts/level_controller.gd`
├── SunContainer (Node2D) — sun instance added by loader
├── PlanetContainer (Node2D) — planet instances added by loader
├── rocket (Node2D) — `scenes/rocket.tscn`
│   ├── Polygon2D (visual triangle)
│   ├── Line2D — `scripts/trajectoryline_2d.gd`
│   │   └── CanvasLayer (TimeMarker, via `scenes/time_marker.tscn`)
│   └── rocketCamera (Camera2D) — `scripts/rocket_camera.gd`
├── OrientationDial (Control) — `scripts/orientation_dial.gd`
├── AstronautIndicators (Control) — `scripts/astronaut_indicators.gd`
├── hud (CanvasLayer) — `scenes/hud.tscn` / `scripts/hud.gd`
└── LevelLoader (Node) — `scripts/level_loader.gd`
```

### Groups
- `"attractors"` — sun + planets (every body that exerts gravity)
- `"player"` — the rocket
- `"fuel"` — fuel pickups

### Input Map (in `project.godot`)
- `thrust` (W / ↑)
- `rotate_left` (A / ←)
- `rotate_right` (D / →)
- `toggle_trajectory_mode` (Tab)
- `toggle_free_camera` (F)
- `time_warp_up` (`>`)
- `time_warp_down` (`<`)
- `restart` (R)

### Key Tuning Constants
- `G = 1.0` (universal gravitational constant for this project)
- Sun mass default: `4_000_000`
- Planet mass default: `1000`
- Rocket landing threshold: rel_speed ≤ `80.0` = land, > `150.0` = crash (in between = crash, "danger zone")
- Time warp levels: `[1.0, 2.0, 4.0, 8.0]` (drives `Engine.time_scale`)
- Trajectory predictor (PROJECTED): 300 steps × 0.05s = 15s lookahead
- Planet orbit predictor: 64 segments analytical ellipse, sampled from `@export` orbital elements
- Hill-sphere SOI fraction: `0.5` (for auto-SOI detection in ELLIPSE mode)

### JSON Schema v2 — `data/levels/level_NN.json`
```json
{
  "name": "Level 01",
  "version": 2,
  "bodies": [
    {
      "type": "sun",
      "mass": 4000000,
      "position": [-1, -3]
    },
    {
      "type": "planet",
      "name": "earth",
      "is_home": true,
      "has_astronaut": false,
      "has_fuel": true,
      "mass": 10000,
      "radius": 40.0,
      "color": [0.3823967, 0.77151555, 0.31417027, 1.0],
      "perihelion": 1847.7,
      "aphelion": 2000.0,
      "angle_of_aphelion": 3.141592653589793,
      "phase": 3.141592653589793,
      "fuel_orbit_radius": 50.0,
      "fuel_orbit_speed": 0.5
    }
  ],
  "rocket": {
    "initial_position": [3500.0, 0.0],
    "initial_velocity": [0.0, 50.0]
  }
}
```

Note: `sun.position` is **cosmetic** — orbital math treats scene origin as the sun regardless of the JSON value. The `-1, -3` only affects where the sun is drawn. See "Known Issues" for the cleanup TODO.

Body types planned in the schema (currently only `sun` and `planet` implemented): `moon`, `asteroid`.

## Scripts Index

| File | Role |
|---|---|
| `scripts/orbit_calculator.gd` | Pure-math orbital elements → position/velocity (Kepler, vis-viva) |
| `scripts/game_time.gd` | Global game-time clock (static class) |
| `scripts/level_controller.gd` | Per-level logic, win/lose detection |
| `scripts/level_loader.gd` | JSON → scene. Instantiates sun/planets, calls `planet.apply_visual()` + `planet.spawn_dynamic_children()`, configures rocket position/velocity. |
| `scripts/trajectoryline_2d.gd` | Rocket trajectory: ELLIPSE (closed-form, auto-SOI) or PROJECTED (forward-sim). Bounds guard + lazy sun init. |
| `scripts/planettrajectoryline_2d.gd` | Planet orbit ellipse + time markers. Samples `@export` elements directly (no derive-from-state wobble). |
| `scripts/planet.gd` | Closed-form orbit body. `apply_visual()` + `spawn_dynamic_children()` called explicitly by `level_loader` after `@export` setup. |
| `scripts/rocket.gd` | Player — thrust, rotation, gravity, landing/crash, `_snap_to_home_planet` (deferred via `call_deferred`). Game-wide physics in `@export`s. New `min_visual_scale`. |
| `scripts/sun.gd` | Gravity source (adds to "attractors" group) |
| `scripts/sunpolygon_2d.gd` | Sun visual (procedural polygon) |
| `scripts/asteroid.gd` | (planned, not yet implemented) |
| `scripts/moon.gd` | (planned, not yet implemented) |
| `scripts/astronaut.gd` | Rescue target (auto-spawned by `planet.spawn_dynamic_children()` if `has_astronaut = true`) |
| `scripts/fuel_pickup.gd` | Orbiting fuel pickup (auto-spawned by `planet.spawn_dynamic_children()` if `has_fuel = true`) |
| `scripts/astronaut_indicators.gd` | On-screen + edge-arrow markers for uncollected astronauts |
| `scripts/orientation_dial.gd` | Heading indicator (rotating icon in fixed circle) |
| `scripts/rocket_camera.gd` | Follow + free-cam camera (zoom, F to toggle) |
| `scripts/audio_manager.gd` | Music + SFX (autoload) |
| `scripts/save_state.gd` | Persistent save (autoload) |
| `scripts/time_marker.gd` | Yellow marker dot (used by trajectoryline, planettrajectoryline) |
| `scripts/hud.gd` | Velocity, fuel, mode labels (ELLIPSE/PROJECTED), astronaut dots, time warp |
| `scripts/main_menu.gd` | Title screen (Start/Continue, How to Play, Level Select, Quit) |
| `scripts/level_select.gd` | Level picker |
| `scripts/win_screen.gd` | Win result |
| `scripts/lose_screen.gd` | Lose result |

## Git History

```
88afd46 chore: trailing-newline cleanups + uid regeneration
4908453 refactor(rocket): single source of truth + min_visual_scale
c3e4541 fix(planet-orbit-line): sample elements directly, kill high-warp breathing
7931e51 fix(trajectory): bounds guard + lazy-init sun + PROJECTED-only markers
1302eb9 fix(loader): apply_visual + spawn_dynamic_children + configure_rocket trim
c90542d feat(trajectory): ELLIPSE/PROJECTED modes with auto-SOI and forward-sim
02d98cd refactor(stage 5/5): cleanup - delete old scenes, fix planet trajectory markers
defc6e0 refactor(stage 4/5): closed-form trajectory line + cleanup
5fde0e7 refactor(stage 3/5): shared level.tscn + JSON-driven loading
742e27d refactor(stage 2/5): closed-form planet orbits + game-time clock
4a0df4d refactor(stage 1/5): foundation for closed-form orbits + JSON levels
1e9fb54 docs: add Astro-Rescue.md with project state, architecture, and TODO
c2462aa chore: standardize GDScript to tabs, add ## tooltips and function docstrings
2625cea first commit
```

**Working tree:** 13 commits ahead of origin/main. Not pushed yet (testing first).

## Known Issues & TODOs

### 🔴 High
- **Sun collision** — rocket can currently fly through the sun. `rocket.gd::_find_nearest_attractor` filters by `radius` and the sun has no `radius` @export. Need a separate "obstacle" check (or add a non-zero `radius` to the sun).
- **More levels** — only 3 currently; need additional hand-crafted levels with rising difficulty.
- **Asteroid belt** — narrow-window obstacle in later levels.
- **Multi-astronaut rescue** — levels where one trip doesn't suffice.

### 🟡 Medium
- **Refactor `planet.gd`'s `DEFAULT_SUN_MASS`** — fallback constant is dead code since the sun mass is read from `sun.gd` directly via `_find_sun_mass()`.
- **Tighten astronaut pickup SFX** — the pickup sound fires whenever the rocket lands near an astronaut, even outside the actual pickup radius. Move SFX call inside the distance check.
- **Fuel economy** — fuel only on planet-flagged `has_fuel`; no in-transit refueling stations.
- **Faster time acceleration** — extend `TIME_WARP_LEVELS` from `[1, 2, 4, 8]` to include 16× (and maybe 32×).
- **Moons** — new body type orbiting planets, hardcoded orbits. New `scripts/moon.gd` and JSON schema entry for `type: "moon"`.

### 🟢 Low / Polish
- How to Play content (placeholder)
- Win/lose music
- Visual feedback on crash / successful pickup
- Replace procedural `Polygon2D` circles with sprites
- Tune fuel consumption / thrust
- Tune crash / land speed thresholds (the `80.0` / `150.0` defaults came straight from level_01's old JSON — Jason hasn't playtested them yet)
- **Sun `position` is cosmetic** — JSON's `sun.position` doesn't enter orbital math (which treats origin as sun). Worth either honoring it or removing the field for clarity.

### 📦 Backlog
- Moons body type (separate refactor)
- Asteroids body type (separate refactor)
- Graphical level editor
- Multiple rocket types
- Multiple difficulty modes
- Achievements
- Leaderboards
- Steam release
- **`.uid` tracking policy** — currently tracked (added in `88afd46`); could move to `.gitignore` if Godot keeps regenerating and churn becomes annoying

## Working Notes

- **Project root:** `rocketman/astrorescue-main/rocketman/`
- **Git:** 13 commits ahead of origin/main, working tree clean except doc + one stale untracked `scenes/level_01.tscn` (delete next session). Not pushed (testing first).
- **Init-order lesson (now repeated across multiple scripts):** Whenever a script attaches to a scene where a sibling or cousin populates a group / sets `@export`s later, defer or lazy-init. Three flavors seen this session:
  - `add_child` first, then call a method that reads now-set `@export`s — `1302eb9` (`apply_visual` + `spawn_dynamic_children`).
  - Lazy retry in `_process` until the resource appears — `7931e51` (`sun = _find_sun()`) and `c3e4541` (the "same pattern" trajectory-side note).
  - `call_deferred` for self-contained setup that has to wait for siblings — `4908453` (`_snap_to_home_planet`).
- **Commenting standard:** `##` above every `@export` (inspector tooltips) + every function; `#` for inline `why` comments. Per godot-best-practices skill §2.2.
- **Indentation:** Tabs only, displayed 4-wide. Match existing file style when editing.
- **Process:** When making non-trivial changes, do them as a complete phase (commit per stage). Don't batch multiple phases. Jason prefers "check in occasionally."
