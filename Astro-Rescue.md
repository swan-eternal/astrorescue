# Astro-Rescue

> **Status:** Active development. Commenting pass complete 2026-07-06.
> **Engine:** Godot 4.7 (Forward Plus, Jolt Physics, d3d12)
> **Project root:** `rocketman/astrorescue-main/rocketman/`
> **Window:** 1800×980, canvas_items stretch mode

## Concept

2D arcade game. Player starts landed on a home planet, launches with limited fuel, transfers between planets via gravity, rescues stranded astronauts, returns to base. Crash on high-speed planet impacts. Fuel pickups at intermediate bodies. Series of hand-crafted levels with rising difficulty.

## Current State (2026-07-06)

### ✅ What's Complete

- **Core physics:** sun gravity, planet orbits, rocket flight under gravity
- **Rocket controls:** thrust + rotation, time warp (1×/2×/4×/8× via `>` / `<`)
- **Collision:** distance-based landing/crash detection (skill §3.1 pattern — not Area2D signals)
- **Landed state:** glues to planet, thrust unsticks, auto-orients nose-outward so first thrust = launch
- **Astronauts:** auto-spawn on `has_astronaut` planets; proximity-based pickup on landing
- **Fuel pickups:** auto-spawn on `has_fuel` planets, orbit at configurable radius
- **Trajectory predictor:** TRUE mode (Velocity Verlet forward sim) + ORBITAL mode (analytical ellipse within planet's SOI)
- **Time markers:** yellow dots along TRUE-mode trajectories, screen-space (off-screen markers dropped)
- **HUD:** relative velocity (color-coded for landing safety), fuel bar, mode labels, astronaut indicators, time warp level
- **Camera:** follows rocket by default, mouse-wheel zoom, free-cam mode (F key + left-drag)
- **UI:** main menu (Start/Continue toggle), level select (3 levels), win/lose screens
- **Save system:** persists `highest_level_completed` to `user://save.json`
- **Audio:** music (menu + gameplay), thruster loop, one-shot pickup sounds
- **Levels:** 3 hand-crafted (`level_01`, `level_02`, `level_03`)
- **Commenting standard:** every `@export` has `##` inspector tooltip, every function has `##` docstring (per skill §2.2)
- **Indentation:** standardized to tabs across all 20 scripts

### 🔧 Known Limitations

- **No sun collision:** the sun has no `radius` export (only `mass`), and `rocket.gd::_find_nearest_attractor()` filters bodies by `radius` — so the rocket can fly straight through the sun with no crash detection. The filter is right for landing (don't land on the sun) but wrong for collision (should still crash on contact).
- **Hardcoded level restart:** `win_screen.gd` and `lose_screen.gd` Restart buttons hardcode `res://scenes/level_01.tscn`. Should track current level via `SaveState` so Restart works for any level.
- **Planet fallback mass:** `planet.gd` defines `const DEFAULT_SUN_MASS := 4_000_000.0` as a fallback if no attractor is found. Defensive but a second source of truth for sun mass.
- **No audio on win/lose screens:** by design — no victory/defeat tracks yet.
- **Planet auto-spawn coupling:** `planet.gd` instantiates astronaut + fuel pickup directly via `const AstronautScene` / `FuelPickupScene`. Changing which scenes to use requires editing planet.gd.
- **Pickup SFX plays even on near-miss landing:** `rocket.gd`'s landing branch plays `play_astronaut_pickup()` whenever landing near an astronaut, even if just barely outside the actual pickup radius. Matches the original behavior but is probably too generous.
- **Magic-number coupling:** `rocket.gd`'s `_make_triangle` uses `0.8` for the back vertex, and `tail_reach = size * 0.8` reuses it. If you change the triangle shape, both must change in lockstep.

## Architecture

### Autoloads

| Name | Script | Purpose |
|---|---|---|
| `SaveState` | `scripts/save_state.gd` | Persistent progress (`highest_level_completed` → `user://save.json`) |
| `AudioManager` | `scripts/audio_manager.gd` | Music + SFX |

Consumers access via path-based references (`@onready var _x = get_node("/root/X")`), not bare names — see skill §6.1 for why this matters after manual `project.godot` edits.

### Scene Tree (per level)

```
Level_XX
├── LevelController            ← watches rocket → win/lose transitions
├── Sun (mass=4_000_000)       ← group "attractors"
├── Planet_1, Planet_2, ...    ← group "attractors", orbit the sun
│   ├── Astronaut (if has_astronaut) — child node, hexagon
│   ├── FuelPickup (if has_fuel) — orbiting child, hexagon
│   └── PlanetTrajectoryLine2D  ← shows planet's orbit ellipse + markers
├── Rocket                     ← group "player", thrust/rotate/landing/crash
│   ├── TrajectoryLine2D        ← TRUE (Velocity Verlet) + ORBITAL (analytical)
│   └── Camera2D (rocket_camera.gd) — follow + zoom + free-cam
├── OrientationDial            ← rotating heading indicator
├── AstronautIndicators        ← blue rings + edge-arrows for off-screen astronauts
└── HUD                        ← velocity, fuel, mode labels, astronaut dots, time warp
```

### Groups

- `"attractors"` — sun + all planets (every body that exerts gravity)
- `"player"` — the rocket
- `"fuel"` — fuel pickups

### Input Map

| Action | Default Key(s) |
|---|---|
| `thrust` | W, Up Arrow |
| `rotate_left` | A, Left Arrow |
| `rotate_right` | D, Right Arrow |
| `toggle_trajectory_mode` | Tab |
| `toggle_free_camera` | F |
| `time_warp_up` | `>` |
| `time_warp_down` | `<` |
| `restart` | R |

### Key Tuning Constants

- `G = 1.0` (universal gravitational constant for this project — same value in sun.gd, planet.gd, rocket.gd, both trajectory scripts)
- Sun mass default: `4_000_000`
- Planet mass default: `1000`
- Rocket landing thresholds: rel_speed ≤ `8.0` = land, > `30.0` = crash, in between = crash (danger zone)
- Time warp levels: `[1.0, 2.0, 4.0, 8.0]` (drives `Engine.time_scale`)
- Trajectory predictor: 300 steps × 0.05s = ~15s lookahead
- Planet orbit predictor: 64 segments analytical ellipse

## Scripts Index

| File | Lines | Role |
|---|---|---|
| `scripts/sun.gd` | 21 | Gravity source |
| `scripts/planet.gd` | 163 | Orbit dynamics, level-design knobs |
| `scripts/sunpolygon_2d.gd` | 28 | Visual circle helper (placeholder art) |
| `scripts/astronaut.gd` | 55 | Rescue target |
| `scripts/fuel_pickup.gd` | 60 | Orbiting fuel pickup |
| `scripts/rocket.gd` | 380 | Player — biggest file |
| `scripts/save_state.gd` | 67 | Persistent save (autoload) |
| `scripts/audio_manager.gd` | 119 | Music + SFX (autoload) |
| `scripts/main_menu.gd` | 77 | Title screen |
| `scripts/level_select.gd` | 53 | Level picker |
| `scripts/level_controller.gd` | 119 | Per-level logic |
| `scripts/win_screen.gd` | 28 | Win result screen |
| `scripts/lose_screen.gd` | 28 | Lose result screen |
| `scripts/hud.gd` | 136 | HUD overlay |
| `scripts/rocket_camera.gd` | 120 | Follow + free-cam camera |
| `scripts/orientation_dial.gd` | 86 | Heading indicator |
| `scripts/astronaut_indicators.gd` | 104 | Off-screen astronaut markers |
| `scripts/time_marker.gd` | 46 | Yellow marker dots |
| `scripts/planettrajectoryline_2d.gd` | 205 | Planet orbit ellipse |
| `scripts/trajectoryline_2d.gd` | 418 | Rocket trajectory predictor (largest) |

## Planned Features / TODO

### 🔴 High priority

- [ ] **Fix hardcoded level restart** in `win_screen.gd` / `lose_screen.gd` — track current level in `SaveState` so Restart works for any level.
- [ ] **Sun collision** — add a crash check against the sun (separate from the landing check, which correctly skips bodies without a `radius`). Options: give the sun a non-zero `radius` (simplest, but then landing check would treat it as landable), or add a second "obstacle" group / check that includes the sun regardless of radius.
- [ ] **More levels** — currently 3; need additional hand-crafted ones with rising difficulty.
- [ ] **Asteroid belt** — narrow-window obstacle in later levels. **Asteroids as a body type:** hardcoded orbit (not gravity-simulated, to keep them stable), do **not** act as attractors (rocket doesn't feel their pull), pure navigation hazards on collision. No astronauts on asteroids. *May* support fuel pickups. The belt is the first/primary use case but the same body type could appear elsewhere (e.g., a single rogue asteroid near a tricky landing).
- [ ] **Multi-astronaut rescue** — levels where one trip doesn't suffice (planned per MEMORY build order).

### 🟡 Medium priority

- [ ] **Replace hardcoded `level_%02d.tscn` paths** with a JSON-driven level loader (see Design Notes below).
- [ ] **Refactor `planet.gd`'s `DEFAULT_SUN_MASS`** — remove the fallback, error early if no sun found.
- [ ] **Tighten astronaut pickup logic** — current code plays the SFX even when pickup radius isn't reached. Move the SFX inside the inner distance check.
- [ ] **Fuel economy** — consider adding fuel pickups at intermediate bodies (per MEMORY: "fuel pickups at intermediate bodies" is in the game spec but currently fuel only exists on planet `has_fuel` flag, not as free-orbit pickups along transfer paths).
- [ ] **Faster time acceleration** — extend `TIME_WARP_LEVELS` in `rocket.gd` from `[1, 2, 4, 8]` to at least `[1, 2, 4, 8, 16]`, maybe 32× for big levels. Update the HUD readout if the label gets crowded.
- [ ] **Trajectory line rewrite** — current implementation in `trajectoryline_2d.gd` has three issues: (1) only shows the predicted path, not the closed orbital ellipse the rocket would actually trace; (2) uses a fixed `steps` count (300) regardless of how far the trajectory extends; (3) "jitters" near planetary gravity wells because the forward-sim gets sensitive to step size when close to a body. May need adaptive step sizing (smaller `step_dt` when |r| is small), switching to the analytical ellipse for stable orbits, or a hybrid that forward-sims far from planets and uses the analytical form inside SOIs.
- [ ] **Moons** — new body type that orbits a *planet* (not the sun). **Hardcoded orbits** rather than gravity-simulated to keep them stable (a real gravity sim of moon-planet-sun systems goes chaotic fast, especially with the rocket perturbing everything). Moons still **act as attractors** (the rocket feels their pull) and can host their own fuel pickups and astronauts. Architectural changes: a new `Moon` scene (or generalize `Planet` to take a `parent_body`), per-moon hardcoded orbit params, update `LevelController` / `LevelLoader` to scan the right groups, possibly a `_find_nearest_moon` in `rocket.gd` for landing/crash logic.

### 🟢 Low priority / Polish

- [ ] **How to Play content** — currently a placeholder label. Replace with actual image asset(s).
- [ ] **Win/lose music** — currently silent on result screens (no victory/defeat tracks).
- [ ] **Visual feedback on crashed rocket** — currently freezes in place; could show smoke/explosion.
- [ ] **Visual feedback on successful astronaut pickup** — currently just audio + indicator change.
- [ ] **Artwork: replace drawn objects with sprites** — currently the sun, planets, astronaut, fuel pickup, and rocket are all rendered as `Polygon2D` with computed shapes (circles, hexagons, triangles). Swap each for a `Sprite2D` (or `AnimatedSprite2D` for the rocket's idle/thrust) backed by a PNG asset. The `sunpolygon_2d.gd` helper and the geometry-building code in each script can stay as a debug fallback or be removed once assets exist. Per-body sprite paths are likely a JSON field in the level data (defer to the JSON refactor in the design notes below).
- [ ] **Tune fuel consumption / thrust acceleration** — play with `fuel_consumption_rate` and `thrust_acceleration` in `rocket.gd` until the game feels challenging but fair.
- [ ] **Tune crash / landing speed thresholds** — play with `landing_speed_threshold` and `crash_speed_threshold` in `rocket.gd` to find the sweet spot for "fair but challenging" planet transfers.

### 📦 Backlog / Stretch

- [ ] **Graphical level editor** — drag planets around in the scene with the mouse, set mass/orbit/colors live, save to a level file. Stretch goal — might not be worth the dev time. *Idea:* could be a player unlockable as a "reward" for beating the game, exposing level design as a creative outlet for players.
- [ ] **Multiple rocket types** — different rockets with different sprites *and* characteristics (fuel efficiency, thrust, rotation speed, max fuel, etc). Pairs naturally with the level editor (each level could pick a rocket that fits its design — e.g., a fuel-efficient scout for long transfers, a fast-but-thirsty interceptor for tight windows). Needs a rocket-selection UI, per-rocket sprite, and balance work to make each type feel meaningfully different.
- [ ] **Multiple difficulty modes** (casual / realistic physics).
- [ ] **Achievements** (first rescue, all levels cleared, perfect fuel usage, etc.).
- [ ] **Leaderboards** for time-to-complete.
- [ ] **Steam release** — currently Windows-only build via `AstroRescue.exe` / `.pck`.

## Design Notes — JSON-driven levels + closed-form orbits

> Status: design only, not yet implemented. See the TODO entry for "Replace hardcoded `level_%02d.tscn` paths" above. The level editor (📦 backlog) builds on this; the editor writes JSON, so design and player-made levels share the same format.
>
> **Scope expansion (2026-07-06):** originally scoped to JSON-driven level data; now also covers replacing Euler-integrated orbits with **closed-form orbital elements** (perihelion/aphelion/angle/phase). The two refactors are fused because: (a) the JSON schema needs to specify orbital elements anyway, (b) the body scripts get rewritten regardless, (c) doing them together has a cleaner test surface (level 1 must look identical before and after — no behavior change in either dimension).

### Why

The current 3 levels are each their own `.tscn` with planets/sun hard-baked as scene children. This is fine for 3 hand-crafted levels but blocks several TODOs at once:

- 🔴 **Hardcoded level restart** in `win_screen.gd` / `lose_screen.gd` (Restart hardcodes `level_01.tscn`)
- 🟡 **Level registry** for cleaner level-number handling
- 🟡 **More levels** — currently requires a new `.tscn` and editor work per level
- 📦 **Graphical level editor** — would have to be scene-tree aware, much more complex

A JSON-driven architecture solves all four: one shared `level.tscn`, data per level in JSON, levels are just files.

### Target file layout

```
project root/
├── scenes/
│   ├── level.tscn          ← ONE shared scene (HUD, controller, camera, loader)
│   ├── main_menu.tscn
│   ├── level_select.tscn
│   ├── win_screen.tscn
│   ├── lose_screen.tscn
│   ├── sun.tscn            ← unchanged
│   ├── planet.tscn         ← unchanged
│   └── ... (other scene assets)
├── data/
│   └── levels/
│       ├── level_01.json
│       ├── level_02.json
│       └── level_03.json
├── scripts/
│   ├── orbit_calculator.gd  ← NEW: pure math (orbital elements + t → position/velocity)
│   ├── level_loader.gd     ← NEW: parses JSON, instantiates bodies
│   ├── level_controller.gd ← simplified: no more @export level_number
│   ├── planet.gd           ← MODIFIED: closed-form orbit instead of Euler integration
│   └── ... (other scripts)
└── ...
```

Player-created levels would live under `user://levels/` (writable from the game, per SaveState's `user://save.json` pattern).

### Files affected

**New files:**

| Path | Purpose |
|---|---|
| `scripts/orbit_calculator.gd` | Pure math: orbital elements + t → `{position, velocity}`. No node dependencies. |
| `scripts/level_loader.gd` | Parses level JSON, instantiates bodies, sets @exports. |
| `data/levels/level_01.json` | Level 1 data (orbital elements, body specs). |
| `data/levels/level_02.json` | Level 2 data. |
| `data/levels/level_03.json` | Level 3 data. |
| `scenes/level.tscn` | New shared scene: HUD, controller, camera, loader, rocket placeholder. No per-level bodies. |

**Modified files:**

| Path | Change |
|---|---|
| `scripts/planet.gd` | Replace Euler integration with closed-form from `orbit_calculator`. New @exports: `perihelion`, `aphelion`, `angle_of_aphelion` (replacing `orbit_radius` + `initial_speed_multiplier`). |
| `scripts/level_controller.gd` | Drop `@export var level_number`. Read from `SaveState.current_level_number` instead. |
| `scripts/save_state.gd` | Add `var current_level_number: int = 0`. |
| `scripts/level_select.gd` | Set `SaveState.current_level_number = level_num` before `change_scene_to_file("res://scenes/level.tscn")`. |
| `scripts/main_menu.gd` | Continue button: same flow. |
| `scripts/win_screen.gd` | Restart uses `SaveState.current_level_number` (not hardcoded `level_01.tscn`). |
| `scripts/lose_screen.gd` | Same. |
| `scripts/trajectoryline_2d.gd` | Replace forward-sim (`_simulate_heliocentric`) with closed-form sampling using `orbit_calculator`. Variable step count. |
| `scripts/planettrajectoryline_2d.gd` | Verify only — the analytical orbit math is the same; just reads `planet.position`/`velocity` (now closed-form). |
| `scripts/rocket.gd` | Minor: gravity calc still iterates `"attractors"` group; bodies in that group now have exact closed-form velocities. No logic change. |
| `project.godot` | No change. (`run/main_scene` stays as `main_menu.tscn`.) |

**Unchanged files:**

- `scripts/hud.gd`, `scripts/audio_manager.gd`, `scripts/astronaut.gd`, `scripts/fuel_pickup.gd`, `scripts/sunpolygon_2d.gd`, `scripts/rocket_camera.gd`, `scripts/orientation_dial.gd`, `scripts/astronaut_indicators.gd`, `scripts/time_marker.gd` — none of these depend on orbit math or level data.

**Deleted (after migration):**

- `scenes/level_01.tscn`, `scenes/level_02.tscn`, `scenes/level_03.tscn` (replaced by shared `level.tscn` + JSON). Keep in git history until all 3 levels confirmed equivalent.

### JSON schema (v2 — orbital elements + body-type polymorphism)

```json
{
  "name": "First Steps",
  "version": 2,

  "bodies": [
    {
      "type": "sun",
      "mass": 4000000,
      "position": [0, 0]
    },
    {
      "type": "planet",
      "name": "Home",
      "is_home": true,
      "has_astronaut": false,
      "has_fuel": false,
      "mass": 1000,
      "radius": 8,
      "color": [0.4, 0.7, 0.9],
      "perihelion": 200,
      "aphelion": 200,
      "angle_of_aphelion": 0.0,
      "phase": 0.0,
      "fuel_orbit_radius": 0.0,
      "fuel_orbit_speed": 0.0
    },
    {
      "type": "planet",
      "name": "Rescue",
      "is_home": false,
      "has_astronaut": true,
      "has_fuel": false,
      "mass": 800,
      "radius": 6,
      "color": [0.9, 0.5, 0.3],
      "perihelion": 350,
      "aphelion": 350,
      "angle_of_aphelion": 0.0,
      "phase": 2.1
    }
  ],

  "rocket": {
    "auto_snap_to_home": true,
    "starting_fuel": 100.0
  }
}
```

Field mapping (all in radians, `[x, y]` for Vector2, `[r, g, b]` or `[r, g, b, a]` for Color):

- **`type`** — `"sun"` or `"planet"` for v2. Reserved for `"moon"` and `"asteroid"` in later versions.
- **Orbital elements** (sun has none; planet has these):
  - `perihelion` — closest approach to central body
  - `aphelion` — farthest approach (equal to perihelion for circular orbit)
  - `angle_of_aphelion` — orientation of the ellipse's major axis, in radians
  - `phase` — body's initial position along orbit, in radians of mean anomaly
- **Visual** (planet): `color`, `radius`. The visual size is independent of the orbital size.
- **Gameplay flags** (planet): `is_home`, `has_astronaut`, `has_fuel`, plus `fuel_orbit_radius`/`fuel_orbit_speed` if `has_fuel`.
- **Sun**: only `mass` and `position` (origin = [0, 0] by convention; offset for custom layouts later if needed).
- **Omitted fields** use the script's `= default` value — forward-compatible (add fields to JSON without breaking older files).
- **Conversion note**: for the existing 3 levels, all planets have `initial_speed_multiplier = 1.0` (circular orbits), so the migration is simply `perihelion = aphelion = orbit_radius`. Non-circular orbits: `a = orbit_radius / (2 - multiplier²)`, then `perihelion = a*(1-e)`, `aphelion = a*(1+e)`. None of the 3 existing levels need the elliptical math.

### LevelLoader behavior

A new `scripts/level_loader.gd` attached to `level.tscn` does:

1. **Resolve level path** from `SaveState.current_level_number` (e.g., `res://data/levels/level_02.json`)
2. **Load JSON** via `var data = JSON.parse_string(FileAccess.get_file_as_string(path))`
3. **Validate** — check `version` field, required top-level keys (`bodies`); `push_error` and fall back to a default level on malformed input (or crash loudly during the refactor pass; graceful fallback important for player levels later)
4. **Loop over `data["bodies"]`**, `match body["type"]`:
   - `"sun"`: instantiate `Sun.tscn`, set `mass` and `position`, add to `SunContainer`
   - `"planet"`: instantiate `Planet.tscn`, set all @exports from the body dict, add to `PlanetsContainer`
   - `"moon"` / `"asteroid"`: not implemented in v2; loader pushes an error and skips
5. **Configure rocket** from `data["rocket"]` (e.g., `starting_fuel` overrides the scene default; `auto_snap_to_home` controls the existing `_snap_to_home_planet` behavior)
6. **Defer to ready** — `LevelController._initialize()` then runs as it does now (deferred so groups are populated)

The PlanetScene's existing `auto-spawn` pattern (astronaut when `has_astronaut`, fuel when `has_fuel`) still works — those flags are just data in the JSON now. Each body computes its own position/velocity from its orbital elements + game time (using `orbit_calculator.gd`).

### Implementation Plan

The refactor is staged so each phase leaves the game in a working, testable state. **Don't skip phases or combine them** — the staged discipline is what catches bugs early.

#### Stage 1: Foundation (additive, no behavior change)

**Phase 1 — Build `orbit_calculator.gd`**
- *What:* New pure-math helper. Single function: `compute_state(perihelion, aphelion, angle_of_aphelion, phase, t, central_mass) -> {position: Vector2, velocity: Vector2}`. Implements the Keplerian math: a/e from perihelion/aphelion, T from a and central_mass, solve Kepler's equation via Newton-Raphson (3 iterations), true anomaly, distance, rotate by `angle_of_aphelion`, velocity from vis-viva perpendicular to radius.
- *Files added:* `scripts/orbit_calculator.gd`
- *Risk:* **Low** — pure helper, no side effects, no node dependencies. Testable in isolation.
- *Verify:*
  - Circular case: orbit at r=200 around mass 4_000_000. Position over t traces a circle of radius 200. Period ≈ 2π·sqrt(200³ / (1·4_000_000)) ≈ 444s.
  - At t=0 with phase=0: position is (perihelion, 0), velocity is (0, +v_peri) where `v_peri = sqrt(GM·(2/perihelion - 1/a))`.
  - Edge case: perihelion == aphelion (circular) — no division by zero.
  - Edge case: perihelion very small — Newton-Raphson still converges.

**Phase 2 — Add `current_level_number` to SaveState**
- *What:* New `var current_level_number: int = 0` on SaveState. Unused for now — the current Restart behavior stays unchanged.
- *Files modified:* `scripts/save_state.gd`
- *Risk:* **Low** — additive field.
- *Verify:* Game plays identically. `SaveState.current_level_number` is 0 by default.

**Phase 3 — Author `data/levels/level_01.json`**
- *What:* Hand-author `level_01.json` from the current `level_01.tscn`. For level 1's planets (all circular with `initial_speed_multiplier=1.0`), `perihelion == aphelion == orbit_radius`.
- *Files added:* `data/levels/level_01.json`
- *Risk:* **Low** — data file only, nothing reads it yet.
- *Verify:* Diff JSON values against `.tscn` values by hand. Every planet's mass/radius/color/orbit/phase/is_home/has_astronaut/has_fuel/fuel_orbit_* must match.

#### Stage 2: Build planet body around closed-form orbits

**Phase 4 — Update `planet.gd` to use closed-form orbits**
- *What:* Replace `planet.gd::_physics_process` Euler integration with a closed-form position update from `orbit_calculator.gd`. New @exports: `perihelion`, `aphelion`, `angle_of_aphelion`. Drop (or keep temporarily) `orbit_radius` and `initial_speed_multiplier`. Each frame, body reads `game_time` + its own elements, computes position/velocity, sets `position` and `velocity` directly.
- *Files modified:* `scripts/planet.gd`
- *Risk:* **Medium** — touches every planet's behavior. Must play identically to Euler.
- *Verify:*
  - Play level 1: every planet's orbit visually identical to pre-refactor (no drift, no escape, same period).
  - At 8× time warp: planets move 8× faster in lockstep with the rocket.
  - Edge case: perihelion == aphelion (no division-by-zero in orbit_calculator).
- *Depends on:* Phase 1.

**Phase 5 — Add `game_time` global**
- *What:* A single `game_time: float` accumulator. Starts at 0 when a level loads, ticks `delta * Engine.time_scale` each physics frame. Body scripts read it for position computation. Implemented in `level_controller.gd` (or a new autoload if cleaner).
- *Files modified:* `scripts/level_controller.gd` (or new autoload)
- *Risk:* **Low** — read-only time source.
- *Verify:* Print `game_time` before and after a level, check it advances at the expected rate.
- *Depends on:* Phase 4.

#### Stage 3: Replace the per-level scenes

**Phase 6 — Build `level_loader.gd`**
- *What:* New script attached to `level.tscn`. Reads `data/levels/level_<n>.json` (n from `SaveState.current_level_number`), parses `bodies[]`, instantiates the appropriate scene for each type, sets @exports, adds as children.
- *Files added:* `scripts/level_loader.gd`
- *Risk:* **Low** — pure loader, no behavior logic.
- *Verify:* Add a debug print; spot-check that all expected bodies are in the scene tree after load.

**Phase 7 — Create shared `level.tscn`**
- *What:* New scene with infrastructure only: HUD, orientation_dial, astronaut_indicators, level_controller, level_loader, camera, rocket (placeholder; loader configures from JSON). No per-level children.
- *Files added:* `scenes/level.tscn`
- *Risk:* **Medium** — first end-to-end test of the new architecture.
- *Verify:*
  - Update `main_scene` temporarily to `level.tscn` for testing.
  - Load level 1: all planets present, orbits identical to pre-refactor.
  - Restart works (R key reloads, returns to level 1).
- *Depends on:* Phases 4, 5, 6.

**Phase 8 — Wire `current_level_number` plumbing**
- *What:* `level_select.gd` and `main_menu.gd` set `SaveState.current_level_number = level_num` before `change_scene_to_file("res://scenes/level.tscn")`. `win_screen.gd` / `lose_screen.gd` use `SaveState.current_level_number` for Restart.
- *Files modified:* `scripts/level_select.gd`, `scripts/main_menu.gd`, `scripts/win_screen.gd`, `scripts/lose_screen.gd`
- *Risk:* **Low** — pure plumbing.
- *Verify:*
  - Click level 2 in select → game loads level 2.
  - Win level 2 → Restart returns to level 2 (not level 1).
  - Win level 2 → Main Menu → Continue → resumes at level 2.
- *Depends on:* Phase 7.

**Phase 9 — Migrate levels 2 and 3**
- *What:* Author `level_02.json` and `level_03.json` from the existing `.tscn` files. Test each.
- *Files added:* `data/levels/level_02.json`, `data/levels/level_03.json`
- *Risk:* **Low** — same pattern as level 1.
- *Verify:* Play each level through; visually identical to pre-refactor.
- *Depends on:* Phase 8.

#### Stage 4: Simplify the trajectory predictor

**Phase 10 — Update `trajectoryline_2d.gd` to closed-form elliptical trajectory + time markers**
- *What:* Replace the forward-sim (`_simulate_heliocentric`) with the **full closed-form orbital ellipse** — the line shows where the rocket will go *indefinitely* (the complete orbit), not a fading 15-second prediction. The **time markers stay**: discrete dots at `t+5s`, `t+10s`, `t+15s` along the orbit, sampled from the same closed-form math via `orbit_calculator.compute_state(rocket, t + N*interval)`. Variable step count for the line itself (no fixed 300); markers are at fixed intervals.
- *Files modified:* `scripts/trajectoryline_2d.gd`
- *Risk:* **Medium** — touches complex code, but the math is already in the file (`_orbit_ellipse`).
- *Verify:*
  - Trajectory line shows a closed orbital ellipse (or a multi-orbit polyline for hyperbolas — see existing handling).
  - Time markers render at the correct positions on the ellipse.
  - **No more jitter** near planetary gravity wells (math is now exact).
  - ORBITAL mode (inside a planet's SOI) still shows the planetocentric ellipse as today.
- *Depends on:* Phase 4 (planets also closed-form, so trajectory math has exact references).

#### Stage 5: Cleanup

**Phase 11 — Delete old per-level scenes**
- *What:* Remove `scenes/level_01.tscn`, `level_02.tscn`, `level_03.tscn`. Search the codebase for `level_0` references; should be none (other than the new shared `level.tscn` and JSON filenames).
- *Files deleted:* the three old .tscn files
- *Risk:* **Low** — no remaining references after phases 7–9.
- *Verify:* `grep` for `level_0` in the codebase; only matches should be in `level_select.gd` filename formatting and the JSON filenames.

**Phase 12 — Verify `planettrajectoryline_2d.gd` works with closed-form bodies**
- *What:* The planet trajectory line already uses analytical orbit math; verify it reads `planet.position` and `planet.velocity` correctly given the new approach (should be a no-op). Possibly simplify: instead of recomputing the ellipse from r, v, mu, use the body's stored orbital elements directly.
- *Files modified:* `scripts/planettrajectoryline_2d.gd` (verify only)
- *Risk:* **Low.**
- *Verify:* Planet orbit ellipses still draw correctly. Time markers still place at correct times.

#### Validation strategy

The whole refactor must be a **no-op for gameplay**. The 3 existing levels must play identically before and after. Tactics:

- **Orbit trace** (phases 1, 4): log planet positions over one full period, before and after. Compare traces — should overlap (modulo precision of analytical math).
- **Per-level playtest** (phases 7, 9): play through level 1, 2, 3 in the new architecture. Same gameplay, same difficulty, same feel.
- **Time-warp test** (phase 4): at 8× time warp, planets move 8× faster in lockstep with the rocket. No drift, no desync.
- **Restart test** (phase 8): win a non-level-1 level, hit Restart, must reload the correct level.
- **Trajectory test** (phase 10): trajectory line looks the same in typical scenarios AND does not jitter near planets.

#### Time estimate

Rough, assuming focused work and iterating:

| Phase | Estimate | Cumulative |
|---|---|---|
| 1. orbit_calculator | 1–2h | 1–2h |
| 2. SaveState field | 10m | 1.5–2.5h |
| 3. Author level_01.json | 1h | 2.5–3.5h |
| 4. planet.gd closed-form | 2–3h | 4.5–6.5h |
| 5. game_time global | 30m | 5–7h |
| 6. level_loader | 2–3h | 7–10h |
| 7. shared level.tscn | 1–2h | 8–12h |
| 8. wire current_level_number | 30m | 8.5–12.5h |
| 9. migrate levels 2, 3 | 1–2h | 9.5–14.5h |
| 10. trajectoryline closed-form | 2–3h | 11.5–17.5h |
| 11. delete old scenes | 15m | 11.75–18h |
| 12. verify planet trajectory | 30m | 12–18h |

**Total: ~12–18 hours of focused work**, spread over multiple sessions.

#### Open design decisions

These should be settled before (or during) phase 1:

- **Level number plumbing.** Options: (a) `level_loader.gd` reads a `LEVEL_NUMBER` env var, (b) `SaveState` gains a `current_level_number` global, (c) the level select scene passes the number via `change_scene_to_file`'s optional args. **(b)** is the plan — matches SaveState's existing role and fixes the hardcoded Restart bug for free.
- **Player-created level directory.** `user://levels/` mirrors `user://save.json`; how are they listed in the level select? Separate "Community Levels" entry? Mixed in with the main list once unlocked?
- **Schema versioning.** The `"version": 2` field lets us evolve the format. Loader checks version and errors on mismatch. Cheap insurance; include from day one.
- **Per-body sprite paths.** When the artwork pass happens (see 🟢 Polish), each body (sun, planet, astronaut, fuel pickup, rocket) will need a sprite path. Adds a `sprite` field to the planet spec (and similar for sun). Defer until the actual artwork exists — for now, `color` and `radius` are the visual knobs.
- **Body-type generalization (moons + asteroids).** The schema's `bodies[]` with `type` field is forward-looking: it accommodates `moon` and `asteroid` in later schema versions. v2 implements only `sun` and `planet`. The body types themselves are deferred to separate refactor efforts (after this one lands).
- **Rocket start overrides.** Should JSON be able to override the home-planet auto-snap (e.g., start the rocket mid-orbit for cinematic intro levels)? Adds flexibility; can defer until needed.
- **Per-level music.** Currently one gameplay music track. Defer until levels need distinct moods.
- **Time warp with new orbits.** With closed-form orbits, `t` advances 8× faster at 8× warp, so planets move 8× faster. That matches the current desired behavior. Confirm via playtest in phase 4.
- **Planet's @export renames.** Replace `orbit_radius` + `initial_speed_multiplier` outright, or keep them as derived @exports (for backward compat with existing scenes during the transition)? **Replace outright** is cleaner — but means old `.tscn` files break temporarily. Plan: do the planet.gd change AND the JSON authoring in the same phase so the .tscn is never loaded with a broken state.

### Decisions made (2026-07-06)

- **`game_time` origin: level start.** `game_time` resets to 0 each time a level loads. Deterministic per run, enables future replay support. Reflected in phase 5.
- **Malformed JSON handling: crash loudly during refactor.** `push_error` + visible failure for the refactor pass (level files are ours). Graceful fallback ("Level file invalid" message + kick back to main menu) deferred to when player levels exist.
- **Trajectory predictor: draw analytical ellipse + keep time markers.** The closed-form orbit means we can draw the rocket's *full* orbital ellipse, not a fading predicted path. Time markers stay as discrete dots at `t+5s`, `t+10s`, `t+15s` along the orbit — they become "where I'll be at time T" points on the closed ellipse, useful for timing burns. Reflected in phase 10.

### What this refactor enables

- 🔴 **Hardcoded level restart** — fixed by step 7/8 (current_level_number plumbing)
- 🔴 **Trajectory jitter** — gone (closed-form math is exact, no forward-sim step sensitivity)
- 🟡 **Level registry** — JSON filenames ARE the registry
- 🟡 **More levels** — drop a new JSON file, no scene editor work
- 🟡 **Stable orbits for moons and asteroids** — they get the same closed-form treatment (moons/asteroids are separate refactors, but the architecture supports them)
- 🟡 **Faster time acceleration (16×/32×)** — closed-form orbits are exact at any t, no integration step issue
- 🟡 **Show rocket's full orbital ellipse in predictor** — analytical math, not sampling
- 🟡 **No chaos from rocket perturbation** — bodies no longer integrate, so they can't get yanked out of orbit
- 🟡 **Better performance** — Newton-Raphson + trig per body per frame is far cheaper than per-frame N-body integration
- 📦 **Level editor** — editor becomes "a UI that produces JSON" (much smaller than mutating a scene tree)
- 📦 **Multiple rocket types** — JSON can specify which rocket the level uses
- Player level sharing — JSON files are portable, easy to send to other players

### Risk: regression

The whole refactor must be a **no-op for gameplay**. The 3 existing levels must play identically before and after. Approach:

- Convert level 1 first, test exhaustively, **then** convert 2 and 3
- Keep the old `level_01.tscn` etc. around (or in git history) until parity is confirmed
- The schema should be a strict superset of the per-scene @export values; nothing gets dropped or reinterpreted
- Each phase has explicit "Verify" criteria — don't proceed until those pass
- For orbital elements specifically: the math is analytical, so the only regression risk is unit errors (using radians vs degrees, signs of trig functions) or off-by-one in Newton-Raphson iteration count. Verify by comparing traces before/after over several full orbital periods.

## Working Notes

- **Project root:** `rocketman/astrorescue-main/rocketman/`
- **Obsolete path (ignore):** `rocketman/` outer dir has stale `NOTES.md` from the sim phase; the live game is in `astrorescue-main/rocketman/`.
- **Git:** Initialized, single "first commit" baseline. Working tree currently has uncommitted indentation-standardization + commenting-pass changes. Jason prefers to defer commits until multiple edits are batched together.
- **Commenting standard:** `##` above every `@export` (inspector tooltips) + every function; `#` for inline `why` comments. Per skill §2.2.
- **Indentation:** Tabs only, displayed 4-wide. Match existing file style when editing. Notable: `trajectoryline_2d.gd` has `\t\t   ` continuation alignment in one place (lines ~222–226) — that's deliberate readability for a multi-line `if` expression, not mixed indentation.

## References

- `godot-best-practices` skill (live in workspace) — Godot 4.x pitfalls reference
- Godot 4 official docs: https://docs.godotengine.org/en/stable/
- `MEMORY.md` — long-term memory (no longer holds project-specific Astro-Rescue state; use this file instead)