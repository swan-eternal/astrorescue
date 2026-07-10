# Astro-Rescue V2

> **Project:** 2D arcade game (Godot 4.x). Player launches from home planet with limited fuel, navigates between bodies via gravity, rescues stranded astronauts, returns to base. Series of hand-crafted levels with rising difficulty.
>
> **Engine:** Godot 4.x
> **Project root:** `rocketman/astrorescue-main/rocketman/`

## Description

### What it is

A 2D arcade game where the player pilots a small rocket between planets, transfers via gravity assists, rescues stranded astronauts, and returns to base before running out of fuel. Crash on high-speed impacts with the sun or unlandable bodies. Fuel pickups orbit intermediate bodies for refueling.

### What it feels like to play

- **Slow-burn planning.** The trajectory predictor is your friend, not your enemy. Each jump is: predict → plan → commit. Closed-form orbital math means the predictor is exact — no jitter, no drift, players can trust the line.
- **Each level is a puzzle.** How do I get to that astronaut with the fuel I have? Where's the gravity assist window? When do I burn to slow down for landing?
- **Win/lose is about timing and fuel economy, not reflexes.** Real-time input is the thruster + rotation, but the *strategic* layer is reading the orbital geometry.
- **Two trajectory modes (Tab toggles):** ELLIPSE = closed-form ideal 2-body orbit, auto-switches to planet orbit when inside its sphere of influence; PROJECTED = forward-sim under sun + all planet gravity (shows perturbations, slingshots). Different mental model for different decisions.

### Aesthetic

Procedural Polygon2D circles for all bodies, no sprites yet. Minimal HUD (velocity, fuel, mode label, time warp, astronaut dots, orientation dial). Custom Astro-Rescue title image planned but not yet authored. Background animation in main menu planned but not yet implemented.

---

## Implementation

### Architecture

- **Engine:** Godot 4.7 (Forward Plus), Jolt Physics for 3D (unused by this 2D project).
- **Autoloads** (`project.godot`):
  - `SaveState` (`scripts/save_state.gd`) — persistent game progress (`highest_level_completed`, `current_level_number`); saved to `user://save.json`.
  - `AudioManager` (`scripts/audio_manager.gd`) — music + SFX. Routed: `_music_player.bus = "Music"`, `_thruster_player.bus = "SFX"`, oneshots `bus = "SFX"`.
  - `AudioSettings` (`scripts/audio_settings.gd`) — persistent per-bus volume + mute state (channels `master`/`music`/`sfx`, each with `db` ∈ [-40, 0] + `muted` bool); saved to `user://settings.cfg`. Read by `scripts/audio_tab.gd`; pushes to `AudioServer.set_bus_volume_db` / `set_bus_mute` and persists immediately on each setter.
  - `VisualSettings` (`scripts/visual_settings.gd`) — persistent visual toggles. Currently exposes `show_soi: bool` (default `false`) for the planet SOI visualization; saved to `user://visual_settings.cfg` (separate file from audio settings — the two autoloads don't coordinate read-modify-write, each is self-contained). Read by `scripts/visual_tab.gd`; the `SoiIndicator` polls `is_show_soi()` each frame, so toggles apply on the next draw with no signal wiring.
- **Buses** (`default_bus_layout.tres`): Master (root) + Music + SFX. Music and SFX send to Master.
- **Scene tree per level** (`scenes/level.tscn`):
  ```
  level (Node2D)
  ├── LevelController (Node) — `scripts/level_controller.gd`
  ├── SoiIndicator (Node2D) — `scripts/soi_indicator.gd`. Drawn behind bodies; gated by `VisualSettings.is_show_soi()` each frame (default off — toggled via Settings → Visual → "Show Planet SOI").
  ├── SunContainer (Node2D) — sun instance added by loader
  ├── BodyContainer (Node2D) — planet + asteroid instances added by loader (moons are children of their host planets, not siblings here)
  ├── rocket (Node2D) — `scenes/rocket.tscn`
  │   ├── Polygon2D (visual triangle)
  │   ├── Line2D — `scripts/trajectoryline_2d.gd`
  │   │   └── CanvasLayer (TimeMarker, via `scenes/time_marker.tscn`)
  │   └── rocketCamera (Camera2D) — `scripts/rocket_camera.gd`
  ├── OrientationDial (Control) — `scripts/orientation_dial.gd`
  ├── AstronautIndicators (Control) — `scripts/astronaut_indicators.gd`
  ├── hud (CanvasLayer) — `scenes/hud.tscn` / `scripts/hud.gd`
  ├── LevelLoader (Node) — `scripts/level_loader.gd`
  └── PauseMenu (CanvasLayer) — `scripts/pause_menu.gd`
  ```
- **Groups:** `"attractors"` (sun + planets + moons + asteroids — every body that exerts or participates in collision), `"player"` (the rocket), `"fuel"` (fuel pickups).
- **Level editor** (`tools/level_editor/`): SubViewport-based editor with per-body-type inspector, pan/zoom (WASD pan + scroll-zoom centered on cursor), Save/Load (FileDialog at `user://levels/`, JSON indent 2, version-validated on load), Test Level button (plays the in-progress spec via `SaveState.pending_spec`).

### Key technical decisions

- **Closed-form orbital mechanics over forward-sim.** Every body uses Kepler (Newton-Raphson, 3 iterations) + vis-viva for position/velocity at any time. No drift, exact at any time scale. `scripts/orbit_calculator.gd` is a pure-math static helper; bodies read `GameTime.current` (static class) without a Node reference.
- **JSON-driven levels.** `scripts/level_loader.gd` reads `data/levels/level_NN.json` (n from `SaveState.current_level_number`) and instantiates bodies from a `bodies[]` spec. Shared `scenes/level.tscn` contains only infrastructure (no per-level bodies). Schema version field for forward compat (currently v3).
- **Body type contract.** Every attractor must expose `mass`, `radius`, `velocity`, `perihelion`, `aphelion`, `angle_of_aphelion`, `phase`, `is_landable`. New body types match the contract even for properties they don't physically need (sun has `var velocity: Vector2 = Vector2.ZERO` despite never moving, so HUD/rocket/trajectory/moon code's `body.get("velocity")` lookups don't return null).
- **Init-order pattern.** Three flavors, all seen in this project:
  1. `add_child` first, then call method that reads now-set `@export`s — used for `apply_visual()` + `spawn_dynamic_children()` on planets/moons/asteroids.
  2. Lazy retry in `_process` until resource appears — used for `_find_sun()` in trajectoryline_2d.
  3. `call_deferred` for self-contained setup — used for `_snap_to_home_planet()` in rocket.
- **Subordinate bodies as scene-tree children.** Moons are children of their host planets. `get_parent()` is the relationship. Obsoletes string-name lookups for moon→planet (and the `body_label`-vs-`body.name` pitfall). Moon orbit distance is measured from the planet's SURFACE; `scripts/moon.gd` offsets by `parent.radius` internally so `OrbitCalculator.compute_state` receives center-relative distances.
- **Pause menu and Settings menu use CanvasLayer with PROCESS_MODE_ALWAYS.** Layer 100 (pause) / 110 (settings) draws above HUD. Both are interactive while the rest of the game tree is paused.
- **Settings menu modal coordination via static flag.** `SettingsMenu._is_any_open` + `is_any_open()` lets the pause menu's `_unhandled_input` ignore Esc while settings is up — otherwise Esc-closes-settings would also resume the game underneath.
- **JSON moon-perihelion / aphelion is surface-relative.** Authoring example: earth (radius 40) with moon perihelion 20 → moon orbits at 60 from earth center, 20 above the surface. Bug class this prevents: moon permanently *inside* the earth because the math permitted it.
- **SOI math centralized in `OrbitCalculator.compute_soi_radius`.** Single source of truth for Hill-sphere × fraction. Used by both `scripts/trajectoryline_2d.gd` (SOI-mode auto-switch detection) and `scripts/soi_indicator.gd` (editor + in-game visualization). The `DEFAULT_SOI_FRACTION = 0.5` constant on `OrbitCalculator` is the shared default; both files expose their own `@export var soi_fraction` for per-instance override but fall back to this constant.
- **Escape trajectory: full analytical hyperbola, no world-space clip.** `scripts/trajectoryline_2d.gd:_hyperbola_leg` sweeps the polar form `r(ν) = a(e²-1)/(1 + e·cos(ν))` from the rocket's current true anomaly toward the forward-going asymptote, terminating naturally where `denom ≤ 0.001` near the asymptote (r → ∞). Radial-escape fallback (h = 0): the eccentricity formula collapses to e = 1 whenever r and v are parallel, so `_hyperbola_leg` detects this and draws a straight radial line outward instead.
- **Menu centering via `CenterContainer`, not `PRESET_CENTER`.** `Control.set_anchors_and_offsets_preset(Control.PRESET_CENTER)` sets anchors to 0.5/0.5/0.5/0.5 but keeps offsets at 0/0/0/0 — and on a zero-size Control (before being added to the tree), the panel renders at origin. `CenterContainer` wrapping centers the single child and respects `custom_minimum_size` for sizing. Used in both pause menu (`scripts/pause_menu.gd`) and settings menu (`scripts/settings_menu.gd`).
- **Per-instance `StyleBoxFlat` override for opaque settings panel.** Godot's default `PanelContainer` stylebox is alpha=0.75 — when settings is opened over the main menu, the buttons behind bleed through. Override is per-instance via `add_theme_stylebox_override("panel", ...)` rather than mutating the global theme, so other `PanelContainer`s in the project keep the default look unless they opt in.

### Controls (input map in `project.godot`)

| Action | Key | Notes |
|---|---|---|
| `thrust` | W / ↑ | Forward thrust |
| `rotate_left` | A / ← | Counter-clockwise rotation |
| `rotate_right` | D / → | Clockwise rotation |
| `toggle_trajectory_mode` | Tab | ELLIPSE ↔ PROJECTED |
| `toggle_free_camera` | F | Detached camera (zoom + pan) |
| `time_warp_up` | `>` | Step through `[1, 2, 4, 8, 16, 32]` |
| `time_warp_down` | `<` | Reverse step |
| `restart` | R | Reload current level |
| `pause` (handled in code) | Esc | Pause toggle (gameplay) / Editor return path (editor) / Settings close (settings menu) |

### Key tuning constants

- `G = 1.0` (universal gravitational constant for this project)
- Sun mass default: `4_000_000`
- Sun radius: `200.0` (collision + visual disk, single source of truth)
- Sun `is_landable`: `false` (instant crash on contact)
- Planet mass default: `1000` (planets vary widely per level — earth is `10000`)
- Planet radius default: `8.0` (level_01 earth is `40.0`)
- Planet default `is_landable`: `true`
- Moon mass default: `10.0`
- Moon radius default: `6.0`
- Moon default `is_landable`: `true`
- Asteroid mass default: `0.0` (obstacle only, no gravity)
- Asteroid radius default: `8.0`
- Asteroid default `is_landable`: `false` (instant crash on contact)
- Rocket landing threshold: rel_speed ≤ `80.0` = land, > `150.0` = crash (in between = crash, "danger zone")
- Time warp levels: `[1.0, 2.0, 4.0, 8.0, 16.0, 32.0]` (drives `Engine.time_scale`)
- Trajectory predictor (PROJECTED): 300 steps × 0.05s = 15s lookahead
- Planet orbit predictor: 64 segments analytical ellipse, sampled from `@export` orbital elements
- Hill-sphere SOI fraction: `0.5` (`OrbitCalculator.DEFAULT_SOI_FRACTION`, shared by trajectory-line detection and the editor/in-game SOI visualization; both files can override per-instance)
- Audio slider range: 0..100 → -40..0 dB linear

### Scripts index

| File | Role |
|---|---|
| `scripts/orbit_calculator.gd` | Pure-math orbital elements → position/velocity (Kepler, vis-viva) |
| `scripts/game_time.gd` | Global game-time clock (static class) |
| `scripts/level_controller.gd` | Per-level logic, win/lose detection |
| `scripts/level_loader.gd` | JSON → scene. Dispatches sun/planet/asteroid top-level bodies; `_instantiate_planet` spawns each planet's `moons[]` as child nodes via `_instantiate_planet_moon`. Calls `apply_visual()` + `spawn_dynamic_children()` (+ `resolve_orbit()` for moons) on each body, configures rocket position/velocity. Schema version checked: `v3`. |
| `scripts/trajectoryline_2d.gd` | Rocket trajectory: ELLIPSE (closed-form, auto-SOI, hyperbola-leg fallback at escape velocity) or PROJECTED (forward-sim). Bounds guard + lazy sun init. |
| `scripts/planettrajectoryline_2d.gd` | Planet orbit ellipse + time markers. Samples `@export` elements directly (no derive-from-state wobble). |
| `scripts/planet.gd` | Closed-form orbit body around the sun. `apply_visual()` + `spawn_dynamic_children()` called explicitly by `level_loader` after `@export` setup. |
| `scripts/rocket.gd` | Player — thrust, rotation, gravity, landing/crash (decides via `is_landable` flag on nearest attractor), `_snap_to_home_planet` (deferred via `call_deferred`). Game-wide physics in `@export`s. `min_visual_scale` keeps on-screen size constant. |
| `scripts/sun.gd` | Sun: `mass` + `radius` (collision + visual disk, single source of truth) + `is_landable = false` (instant crash on contact). Exposes `velocity: Vector2 = Vector2.ZERO` for parity with other attractors. |
| `scripts/sunpolygon_2d.gd` | Sun visual (procedural polygon) |
| `scripts/asteroid.gd` | Closed-form orbit body around the sun, `mass = 0` by default (obstacle, no gravity). Default `is_landable = false`. |
| `scripts/moon.gd` | Closed-form orbit body around its parent planet (scene-tree child). `perihelion`/`aphelion` are surface-relative (offset by `parent.radius` internally). |
| `scripts/astronaut.gd` | Rescue target (auto-spawned by planet/moon `spawn_dynamic_children()` if `has_astronaut = true`) |
| `scripts/fuel_pickup.gd` | Orbiting fuel pickup (auto-spawned by planet/moon/asteroid `spawn_dynamic_children()` if `has_fuel = true`) |
| `scripts/astronaut_indicators.gd` | On-screen + edge-arrow markers for uncollected astronauts |
| `scripts/orientation_dial.gd` | Heading indicator (rotating icon in fixed circle) |
| `scripts/rocket_camera.gd` | Follow + free-cam camera (zoom, F to toggle) |
| `scripts/audio_manager.gd` | Music + SFX (autoload). Routed to Music/SFX buses. |
| `scripts/audio_settings.gd` | Persistent volume + mute state for the three audio buses (autoload). ConfigFile at `user://settings.cfg`. |
| `scripts/audio_tab.gd` | Settings panel: 3 rows (Master/Music/SFX) with name + 0..100 slider + live dB readout + mute checkbox. |
| `scripts/settings_menu.gd` | Tabbed settings panel (Audio/Visual/Gameplay). CanvasLayer with `PROCESS_MODE_ALWAYS`, layer 110. Esc/Close queue_free self. Static `_is_any_open` flag for pause-menu Esc coordination. |
| `scripts/visual_tab.gd` | Settings panel: "Show Planet SOI" CheckBox bound to `VisualSettings.set_show_soi()`. Refreshes from persisted state in `_ready` (audio_tab.gd pattern). |
| `scripts/soi_indicator.gd` | Planet SOI visualization. `Node2D` that reads the `attractors` group each frame, computes each planet's SOI radius via `OrbitCalculator.compute_soi_radius`, and draws a filled circle + bordered arc via `draw_circle` / `draw_arc`. `bypass_visual_settings` @export lets the level editor force-show regardless of the user's in-game toggle. Border width scales inversely with camera zoom. |
| `scripts/visual_settings.gd` | Persistent visual toggles (autoload). `is_show_soi()` / `set_show_soi()` API; saved to `user://visual_settings.cfg`. Mirrors the `AudioSettings` pattern but on its own file (no read-modify-write coordination between the two autoloads). |
| `scripts/gameplay_tab.gd` | Settings panel placeholder. |
| `scripts/pause_menu.gd` | Esc pause overlay with Continue / Settings / Main Menu. CanvasLayer with `PROCESS_MODE_ALWAYS`, layer 100. |
| `scripts/save_state.gd` | Persistent save (autoload) |
| `scripts/time_marker.gd` | Yellow marker dot (used by trajectoryline, planettrajectoryline) |
| `scripts/hud.gd` | Velocity, fuel, mode labels (ELLIPSE/PROJECTED), astronaut dots, time warp |
| `scripts/main_menu.gd` | Title screen (Start/Continue, How to Play, Level Select, Settings, Quit, Level Editor) |
| `scripts/level_select.gd` | Level picker (includes Custom Levels FileDialog) |
| `scripts/win_screen.gd` | Win result |
| `scripts/lose_screen.gd` | Lose result |

### JSON schema v3 — `data/levels/level_NN.json`

```json
{
  "name": "Level 01",
  "version": 3,
  "bodies": [
    {
      "type": "sun",
      "mass": 4000000,
      "radius": 200.0,
      "is_landable": false,
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
      "fuel_orbit_speed": 0.5,
      "moons": [
        {
          "radius": 6.0,
          "color": [0.7, 0.7, 0.8],
          "perihelion": 20.0,
          "aphelion": 30.0,
          "angle_of_aphelion": 0.0,
          "phase": 0.0,
          "is_landable": true,
          "mass": 10.0
        }
      ]
    }
  ],
  "rocket": {
    "initial_position": [3500.0, 0.0],
    "initial_velocity": [0.0, 50.0]
  }
}
```

Body types: `sun`, `planet`, `moon`, `asteroid`. Moons are scene-tree children of their host planet (nested as `moons[]` in JSON). Moon orbit distance is surface-relative. Asteroids orbit the sun with `mass = 0` (obstacle only). `sun.position` is cosmetic — orbital math treats scene origin as the sun regardless.

---

## To-Do

> Items below are remaining work. Completed items live in git history (use `git log` / `git blame` for archaeology). Creative decisions are flagged `(creative-Jason)` — needs Jason's input on direction before implementation.

### Immediate (uncommitted, this session)

> All uncommitted items shipped in two commits on 2026-07-09 (commits `3374e30` and `0c145f5`, on top of `c6c0980`). Nothing pending in the working tree.

- ~~**Trajectory escape-line fix** (`scripts/trajectoryline_2d.gd`) — analytical forward-direction hyperbola leg in ELLIPSE mode replaces the collapsed-to-point fallback at escape velocity.~~ **Done** — shipped in `3374e30`. Implementation includes: (a) removed world-space `max_leg_radius` clip so the curve extends to its natural asymptote; (b) radial-escape fallback for h=0 launches (straight radial line outward); (c) SOI math centralized in `OrbitCalculator.compute_soi_radius` shared with the new SOI visualization.
- ~~**Menu centering + settings opacity** (`scripts/pause_menu.gd`, `scripts/settings_menu.gd`)~~ **Done** — shipped in `3374e30`. Both menus use `CenterContainer` wrapping instead of `PRESET_CENTER`; settings panel has per-instance `StyleBoxFlat` override (alpha=1.0) so menu text doesn't bleed through.
- ~~**SOI visualization + VisualSettings toggle** (`scripts/soi_indicator.gd`, `scripts/visual_settings.gd`, etc.)~~ **Done** — shipped in `0c145f5`. Shaded circle per planet in both editor (always visible via `bypass_visual_settings = true`) and in-game (toggleable via Settings → Visual → "Show Planet SOI", default off, persisted to `user://visual_settings.cfg`).
- **In-game verification** — settings panel hasn't been opened in-game yet. Worth a playtest: sliders affect music/SFX live, mute works, Esc returns to pause menu (game still paused), settings from main menu doesn't break anything.

### Game-side polish

- **Multi-astronaut rescue** *(creative-Jason)* — design 2–3 levels where one trip isn't enough (e.g., 3 astronauts scattered, only enough fuel for 2 before refuel).
- **Asteroid belt** *(creative-Jason)* — at least one level using asteroids as a deliberate "thread the needle" course. Asteroids are implemented; no level uses them that way yet.
- **Crash/landing speed tuning** *(creative-Jason)* — playtest the 80/150 defaults; current values untested with real player behavior.
- **Fuel economy tuning** *(creative-Jason)* — no in-transit refueling; asteroids support `has_fuel` for risk/reward near rocks, no level uses it yet.
- **Trajectory crash at extreme planet masses** — pragmatic fix: tighter `PLANET_MASS.y` slider limit. Real fix: investigate numerical issue in `scripts/orbit_calculator.gd:compute_state` when planet mass >> sun mass. Not urgent.

### Polish backlog (longer-term)

- **More levels** *(creative-Jason)* — currently 3; need rising-difficulty progression.
- **How-To-Play content** *(creative-Jason)* — currently placeholder text in `scenes/main_menu.tscn`.
- **Visual feedback on crash / successful pickup** *(creative-Jason)* — currently the only feedback is a visual flash + lose-screen transition.
- **Replace procedural `Polygon2D` circles with sprites** *(creative-Jason)* — visual identity upgrade.
- **Win / lose music** *(creative-Jason)* — currently music stops on win/lose screens (`scripts/audio_manager.gd:stop_music()`), no replacement.
- **Tune fuel consumption / thrust defaults** *(creative-Jason)* — gameplay feel.
- **Fill in Gameplay settings tab** *(creative-Jason)* — Visual tab is partially filled (SOI toggle shipped); Gameplay still a placeholder.
- **Fill in Visual settings tab further** *(creative-Jason)* — currently has one toggle (Show Planet SOI). Add more as they come: trail/particle density, motion blur, color-blind palette, etc.
- **Crash sound effect** *(creative-Jason)* — `scripts/audio_manager.gd` crash SFX on the SFX bus, wired into `rocket.gd`'s crash branch. Audio asset TBD (`res://assets/sound/crash.mp3`).
- **Custom Astro-Rescue title image** *(creative-Jason)* — replace `TitleLabel` in `scenes/main_menu.tscn` with a `TextureRect` pointing at `res://assets/textures/title.png`. Sized to match the current 48-pt label region.
- **Background animation in main menu** *(creative-Jason)* — non-interactive level running behind the buttons (bodies orbiting under closed-form math, no rocket/input). Implementation: `SubViewport` overlay or a `background_only: bool` flag on `scripts/level_loader.gd` that skips the rocket. Camera slowly pans/zooms on a fixed cycle so the background doesn't feel static.

---

## Open Threads

> Items needing verification or decisions. Not action items yet — read, decide, then promote to To-Do.

- **Extreme-mass trajectory crash root cause.** The trajectory line crashes when a planet's mass is set very high in the editor. The slider tightening is the pragmatic fix; the underlying numerical issue in `scripts/orbit_calculator.gd:compute_state` (Newton-Raphson iteration / Kepler solver behavior at extreme mass ratios) is uninvestigated.
- **Music may pause with the game when paused.** `scripts/audio_manager.gd` doesn't set `PROCESS_MODE_ALWAYS`, so its `_music_player` is subject to scene pause. When the player pauses via Esc, the menu music MIGHT stop too. If it's annoying in playtest: add `process_mode = Node.PROCESS_MODE_ALWAYS` to AudioManager's `_ready`.
- **`.uid` policy.** Currently committed; revisit if churn becomes a problem (e.g., mass-rename across many files). No churn observed in 40+ recent commits.
- **Editor doesn't track unsaved state.** Esc from the level editor changes scene to main menu without a "save first?" prompt. If you ever lose work, add a confirmation dialog (mirrors save-state tracking like a text editor).

---

## Release

> Free release on itch.io. Scope is "the current playable game" — no Steam, no paid tiers, no commercial distribution. Recorded here so the build/upload/asset pipeline is documented once instead of redone each session.

### Distribution channel

**itch.io** (free). Project page is created via the itch.io web UI; uploads are easiest via the [itch.io butler CLI](https://itch.io/docs/butler/) for scripted / repeatable pushes. The butler keeps a record of uploaded builds per project (`~/.config/itch/configure.json` or platform equivalent) so re-uploading a channel is a single command.

### Build targets

| Target | Status | Notes |
|---|---|---|
| **Windows Desktop** | ✅ Configured | `export_presets.cfg` → `AstroRescue_WindowsDesktop_v0.5` → `./AstroRescueV01.exe`. x86_64, ~103 MB. Currently the only preset. |
| **Web (HTML5)** | ⚠️ Needed | Godot 4 supports HTML5 export out of the box; need a new preset. Output is a directory containing `index.html` + `.wasm` + `.pck` — zip the directory before uploading to itch.io. Caveats: HTML5 build has no filesystem access, runs in a sandboxed browser tab; audio is fine; performance is fine for this game's draw load. |
| **Linux** | ❓ TBD | Single .x86_64 executable, runs on most distros. Lower priority — itch.io's audience for arcade games skews Windows + browser. |
| **macOS** | ❓ TBD | Requires a Mac to build (Godot can't cross-compile to macOS from Linux/Windows easily). Defer unless itch.io analytics show Mac traffic. |

### Required assets

- [x] **Audio** — `assets/sound/` (5 tracks: `gamebackground`, `fuelbloop`, `menubackground`, `success_ding`, `thruster`).
- [x] **Body visuals** — `assets/images/rocket/rockettemp.png`, `assets/images/sun/suntemp.png`. Procedural `Polygon2D` for planets (no sprite needed).
- [ ] **Title image / cover art** — main menu currently shows `TitleLabel` as plain text. Replace with a `TextureRect` + custom image at `res://assets/textures/title.png` (existing TODO). Sizing: ~960×540 (itch.io's default card aspect ratio) or 16:9.
- [ ] **Screenshots** (3–5) — gameplay shots showing: (1) orbital trajectory with multiple bodies, (2) close-up of rocket on a planet surface with HUD, (3) the settings menu, (4) the level editor in action, (5) optional: a paused-game frame with menu. Capture from the actual game (Godot editor's Viewport → Take Screenshot, or `get_viewport().get_texture().get_image().save_png()` from a debug script).
- [ ] **Trailer / gameplay GIF** *(optional but recommended)* — capture ~15 seconds of gameplay (orbit planning + thrust + landing), convert to GIF via ffmpeg. Aim for ~2–5 MB so itch.io's preview doesn't lag.

### itch.io page metadata

- **Title:** Astro-Rescue
- **Short description:** (~80 chars) "Pilot a small rocket between planets using gravity assists. Closed-form orbital trajectory predictor — no guesswork, just physics."
- **Full description:** (paragraph or two) gameplay loop, controls, what's special about the trajectory predictor, credits.
- **Tags:** Arcade, Space, Physics, Single-player, Godot. Pick 3–5 from itch.io's taxonomy.
- **Pricing:** Free ("No payments"). Optionally "Pay what you want" with min $0 — currently `Free` is the right call for v0.5.
- **Classification:** Game → Web → HTML5; also Game → Download → Windows.
- **Embed options:** 960×540 default, allow fullscreen. Enable "Automatically start on page load" so the game boots immediately when the page is visited.
- **System requirements:** "Any modern browser" (HTML5); "Windows 10+" (`.exe`). No GPU requirements.
- **Controls:** table mirroring the in-game input map — thrust W/↑, rotate A/D, trajectory mode Tab, time-warp `<`/`>`, pause Esc, restart R.

### Release checklist

- [ ] Title image authored + integrated in main menu
- [ ] Web (HTML5) export preset added to `export_presets.cfg`
- [ ] Web export tested in Chrome + Firefox + Safari (HTML5 builds have cross-browser quirks)
- [ ] Screenshots captured (3–5)
- [ ] Trailer / GIF captured (optional)
- [ ] itch.io page created, all metadata fields filled
- [ ] First build uploaded (manual via web, or via butler — see cheatsheet below)
- [ ] Build tested from itch.io page in a fresh browser (incognito) — verify trajectory line, audio, settings all work
- [ ] `Astro-Rescue.md` status header bumped to "released on itch.io"

### Build + upload cheatsheet

```bash
# Windows (already configured; via CLI)
godot --export-release "AstroRescue_WindowsDesktop_v0.5" ./AstroRescueV01.exe

# Web (when preset added)
godot --export-release "Web" ./build/web/index.html

# Zip the HTML5 build directory (itch.io requires a single zip)
zip -r AstroRescue_v0.5.0_web.zip ./build/web/

# itch.io butler (install once: https://itch.io/docs/butler/)
butler login
butler push ./build/web.zip   user/astro-rescue:web --userversion 0.5.0
butler push ./AstroRescueV01.exe user/astro-rescue:win --userversion 0.5.0
```

### Post-release

- **Feedback collection:** itch.io comments are the only feedback channel for v0.5 (no Discord / no in-game feedback form yet). Consider linking the comments page in the main menu footer once it's live.
- **Bug reports:** accepted via itch.io comments only for v0.5.
- **Version cadence:** patch releases for fixes (v0.5.1, v0.5.2…), minor releases for new content/levels (v0.6…). itch.io's "version history" keeps old builds available — players who started on v0.5 can finish it even after v0.6 ships.
- **Save data compatibility:** `SaveState` writes to `user://save.json`. Browser builds use IndexedDB-backed `user://`, which is per-origin — players on itch.io won't share saves with the desktop build. Document this in the page description so players don't lose progress switching between browser and .exe.
- **Updates post-release:** re-export + `butler push` with a new `--userversion` flag. itch.io tracks all uploaded versions under "View all" → users on the page see the latest by default but can roll back to any version.

---

## Lessons Learned

> Patterns and anti-patterns captured during the project. These inform future implementation decisions and are worth re-reading before adding new code.

### Init-order

When a script attaches to a scene where a sibling or cousin populates a group / sets `@export`s later, defer or lazy-init. Three flavors:

1. `add_child` first, then call method that reads now-set `@export`s. Used for `apply_visual()` + `spawn_dynamic_children()` on planets/moons/asteroids. (`scripts/level_loader.gd` writes `@export`s after `add_child` per Godot's init timing.)
2. Lazy retry in `_process` until the resource appears. Used for `_find_sun()` in `scripts/trajectoryline_2d.gd` — `trajectoryline._ready` runs before `LevelLoader._ready` (sibling that adds the sun).
3. `call_deferred` for self-contained setup. Used for `_snap_to_home_planet()` in `scripts/rocket.gd` — rocket was stranded at `initial_position` instead of glued to the home planet.

### Property-contract parity across body types

When adding a new body type that joins `"attractors"`, it must declare every property other code reads unconditionally on attractors — even properties the new body doesn't physically need. The canonical example: `scripts/sun.gd` exposes `var velocity: Vector2 = Vector2.ZERO` despite never moving, because HUD/rocket/trajectory/moon code reads `body.get("velocity")` on every attractor. Without it, `Vector2(null)` crashed the first time the rocket got near the sun.

### Body identification: `body_label` not `body.name`

Scene-tree name (`body.name`) is the scene's internal identifier (always `"planet"` from `scenes/planet.tscn`). JSON's `"name"` key flows into a `body_label` @export via the loader. When looking up by JSON name, always match `body.get("body_label")`, never `body.name`. The moon refactor obsoletes this for moons (they use `get_parent()`); the rule still applies anywhere you do need to find a named body.

### Subordinate bodies as scene-tree children

When a body is conceptually subordinate to another (moon → planet, satellite → ship, projectile → launcher), make it a scene-tree child. The relationship becomes `get_parent()`, robust by construction. Obsoletes string-name lookups (and the `body_label`-vs-`body.name` pitfall above) and mirrors the JSON hierarchy.

### Closed-form > forward-sim for trajectory prediction

Forward-simulated trajectories drift (we saw ~80 world units after 5 seconds for an eccentric orbit with e=0.37). Closed-form Kepler sampling is exact, computationally cheaper, and trustworthy as a *prediction* — the player can plan against it. Use forward-sim only when you need to show what *actually* happens with perturbations (PROJECTED mode).

### Modal coordination via static flag

When layering modals (pause menu over gameplay, settings over pause menu), use a static `_is_any_open` flag on the topmost modal + an `is_any_open()` static accessor. The lower modal's `_unhandled_input` checks the flag and bails. Prevents the case where Esc-closes-settings also resumes the game underneath (both handlers fire on the same Esc event in the same frame). Pattern from `scripts/settings_menu.gd` + `scripts/pause_menu.gd`.

### Slider + SpinBox combo for "feel" params

In the level editor inspector: HSlider for exploration + SpinBox for precise entry, both editing the same value bidirectionally. Bidirectional sync uses `set_block_signals(true)` around the programmatic update of the OTHER control so the `value_changed` cascade doesn't infinite-loop. Same pattern for the audio tab sliders (`scripts/audio_tab.gd`).

### Working-style conventions

Per `MEMORY.md`:
- **GDScript:** tabs only, displayed 4-wide. Match existing file style when editing.
- **Comments:** `##` above every `@export` (inspector tooltips) + every function; `#` for inline `why` comments.
- **Commits:** only when explicitly told. Fewer larger commits preferred.
- **Comment generously when writing GDScript for Jason.** He's a beginner; explanatory comments are part of the working style.

---

## Out of Scope

Intentionally deferred. Kept here for posterity, not on the roadmap. Revisit if/when "release" enters scope.

- Multiple rocket types
- Difficulty modes
- Achievements
- Leaderboards
- Steam release (commercial — the itch.io release is free only)
- Paid tiers on itch.io (current v0.5 is "No payments")
- Multiplayer
- Mobile / touch input

---

## See also

- `Astro-Rescue.md` — original doc, preserved as-is for archaeology. Contains the full "What's Complete" refactor history (Stages 1–5), bug-fix commit narratives, and the original git history block. The Status header is kept current as a one-line summary of the shipped state.
- `tools/level_editor/` — level editor source (SubViewport + per-body-type inspector).
- `data/levels/level_0N.json` — current levels (3).
- `default_bus_layout.tres` — Master/Music/SFX bus definitions.
- `project.godot` — autoloads, input map, audio bus layout reference.