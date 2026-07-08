extends Node
class_name LevelLoader
##
## LevelLoader: reads level_NN.json and builds the scene from it.
##
## Attached to scenes/level.tscn (the shared infrastructure scene). On
## _ready, reads `data/levels/level_<SaveState.current_level_number>.json`,
## instantiates bodies (sun, planets, asteroids) from the spec, and
## configures the rocket's @exports. Moons are nested under planets in
## JSON's `moons[]` arrays and instantiated as children of their host
## planets — see `_instantiate_planet_moon`.
##
## All level-specific data lives in JSON — this loader is the only
## script that interprets it. The shared level.tscn contains no
## per-level data.
##
## **Editor reuse:** `build_scene_from_spec()` and `configure_rocket()`
## are public + static so the upcoming graphical level editor can call
## them with an in-memory spec to drive the live preview, without
## going through JSON. This guarantees the editor and the game share
## the same scene-building code paths — no orbit-math drift, no
## init-order surprises.
##

const SUN_SCENE := preload("res://scenes/sun.tscn")
const PLANET_SCENE := preload("res://scenes/planet.tscn")
const MOON_SCENE := preload("res://scenes/moon.tscn")
const ASTEROID_SCENE := preload("res://scenes/asteroid.tscn")
const LEVELS_DIR := "res://data/levels/"


## Resolve the level path, load JSON, instantiate bodies, configure
## the rocket. Called from _ready so it runs after the rest of the
## scene is set up but before any _physics_process fires on planets.
func _ready() -> void:
	_load_level()


## Resolve the level number from SaveState (set by main_menu /
## level_select in Phase 8), load the corresponding JSON, and build
## the scene's per-level content from it. If SaveState.pending_spec is
## non-empty (set by the level editor's Test Level button OR the level
## select menu's Custom Levels button), use that spec instead — the
## in-memory state is the source of truth during testing / custom play.
func _load_level() -> void:
	# Test / custom level path: editor or level-select pushed a spec
	# via SaveState.pending_spec. Takes priority over JSON loading.
	# Consumed on use so subsequent level loads (e.g., after winning
	# and choosing Next Level) fall back to the normal JSON path.
	if not SaveState.pending_spec.is_empty():
		var spec_to_use: Dictionary = SaveState.pending_spec
		SaveState.pending_spec = {}
		build_scene_from_spec(spec_to_use, get_parent())
		return

	var level_num: int = SaveState.current_level_number
	if level_num < 1:
		push_error("LevelLoader: SaveState.current_level_number is %d (must be >= 1)" % level_num)
		return

	var path: String = "%slevel_%02d.json" % [LEVELS_DIR, level_num]
	if not FileAccess.file_exists(path):
		push_error("LevelLoader: level file not found: %s" % path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("LevelLoader: failed to open %s" % path)
		return
	var json_text := file.get_as_text()
	file.close()

	var data = JSON.parse_string(json_text)
	if not data is Dictionary:
		push_error("LevelLoader: failed to parse JSON in %s" % path)
		return

	# Validate schema version. v3 uses orbital elements + body-type
	# polymorphism with moons nested under planets. v2 was similar but
	# had moons as top-level bodies. v1 used orbit_radius and a separate
	# sun/planets[] layout — not supported here.
	var version: int = data.get("version", 0)
	if version != 3:
		push_error("LevelLoader: unsupported schema version %d (expected 3)" % version)
		return

	# Build the scene from the loaded JSON. Pass `get_parent()` (the
	# level node) as root — it has SunContainer + PlanetContainer as
	# direct children, matching what build_scene_from_spec expects.
	build_scene_from_spec(data, get_parent())


## Build the per-level scene content from a JSON-style spec dict.
## **Public + static** so the upcoming level editor can call it with
## an in-memory spec without instantiating a LevelLoader node.
##
## `root` should have `SunContainer` and `PlanetContainer` as direct
## children (matches `scenes/level.tscn`). Existing bodies in those
## containers are cleared first — calling this twice replaces the
## level cleanly (used for live preview in the editor).
##
## The rocket (in the `"player"` group) is configured from
## `spec.get("rocket", {})` if found. The editor can call
## `configure_rocket()` directly when it has a specific rocket instance.
static func build_scene_from_spec(spec: Dictionary, root: Node) -> void:
	var sun_container: Node = root.get_node_or_null("SunContainer")
	var planet_container: Node = root.get_node_or_null("PlanetContainer")

	if sun_container == null or planet_container == null:
		push_error("LevelLoader.build_scene_from_spec: root must have SunContainer + PlanetContainer children")
		return

	# Clear existing bodies (idempotent re-build — editor calls this
	# on every property change for live preview).
	for child in sun_container.get_children():
		child.queue_free()
	for child in planet_container.get_children():
		child.queue_free()

	# Instantiate each body in the spec. Order matters: the sun must
	# exist before planets and asteroids can compute their orbits (their
	# physics_process reads sun.mass from the "attractors" group).
	for body_spec in spec.get("bodies", []):
		var body_type: String = body_spec.get("type", "")
		match body_type:
			"sun":
				_instantiate_sun(body_spec, sun_container)
			"planet":
				_instantiate_planet(body_spec, planet_container)
			"asteroid":
				_instantiate_asteroid(body_spec, planet_container)
			_:
				push_warning("LevelLoader: unknown body type '%s' (skipped)" % body_type)

	# Configure the existing rocket if one is in the tree (level.tscn
	# places one in "player" group). The editor can call configure_rocket
	# directly with an explicit instance.
	var tree := root.get_tree()
	if tree:
		var rocket: Node2D = tree.get_first_node_in_group("player")
		if rocket:
			configure_rocket(spec.get("rocket", {}), rocket)


## Configure the rocket's @exports from a JSON-style rocket dict.
## **Public + static** so the editor can call it on any rocket instance.
##
## Only sets initial_position and initial_velocity — the per-level values
## the JSON carries. Game-wide rocket characteristics (thrust, landing/
## crash thresholds, fuel capacity, etc.) are configured in rocket.gd's
## @export defaults so they're all in one place.
static func configure_rocket(spec: Dictionary, rocket: Node2D) -> void:
	if rocket == null:
		push_warning("LevelLoader.configure_rocket: rocket is null")
		return

	# For level_01 the home planet override runs in rocket._ready
	# (call_deferred("_snap_to_home_planet")) and glues the rocket to
	# the planet regardless of initial_position. These values are
	# honored for any future level without an `is_home` planet, where
	# the rocket truly spawns at a fixed point in space.
	if spec.has("initial_position"):
		var pos: Array = spec["initial_position"]
		if pos.size() >= 2:
			rocket.initial_position = Vector2(pos[0], pos[1])
	if spec.has("initial_velocity"):
		var vel: Array = spec["initial_velocity"]
		if vel.size() >= 2:
			rocket.initial_velocity = Vector2(vel[0], vel[1])


## Instantiate the sun (at most one per level) and add to the given
## container. Sun is a gravity source; it has no orbit so we just set
## mass, radius, and position. @exports are set AFTER add_child per
## skill §1.5.
##
## **Position is forced to (0, 0) regardless of spec.** Orbit math
## treats the heliocentric origin as the sun — a non-zero visual
## position would just float the disk while planets still orbit (0,0).
## The spec's "position" field is preserved for JSON schema
## compatibility but ignored here.
static func _instantiate_sun(spec: Dictionary, container: Node) -> void:
	var sun := SUN_SCENE.instantiate()
	container.add_child(sun)
	sun.mass = spec.get("mass", 4_000_000.0)
	sun.radius = spec.get("radius", 200.0)
	# Rebuild the visual polygon with the now-set radius (the polygon
	# child built its placeholder from radius=200 during add_child,
	# before this method could override it).
	sun.apply_visual()
	# Lock to origin — see the docstring above for why.
	sun.position = Vector2.ZERO


## Instantiate a planet and configure its @exports from the JSON spec.
## @exports are set AFTER add_child per skill §1.5 — the planet script
## is fully initialized at that point. Note: the new @physics_process
## will run on the next frame, by which time all @exports are set.
static func _instantiate_planet(spec: Dictionary, container: Node) -> void:
	var planet := PLANET_SCENE.instantiate()
	container.add_child(planet)

	# Display name (read from JSON's "name" key, defaults to "planet"
	# if missing). Used in win/lose UI and HUD to identify the planet
	# to the player; not used for scene-tree relationships.
	planet.body_label = spec.get("name", "planet")

	# Level-design flags.
	planet.is_home = spec.get("is_home", false)
	planet.has_astronaut = spec.get("has_astronaut", false)
	planet.has_fuel = spec.get("has_fuel", false)
	planet.fuel_orbit_radius = spec.get("fuel_orbit_radius", 10.0)
	planet.fuel_orbit_speed = spec.get("fuel_orbit_speed", 0.5)

	# Visual.
	planet.radius = spec.get("radius", 8.0)
	if spec.has("color"):
		var col: Array = spec["color"]
		if col.size() >= 3:
			var alpha: float = col[3] if col.size() >= 4 else 1.0
			planet.color = Color(col[0], col[1], col[2], alpha)

	# Rebuild the visual polygon with the now-set radius + color.
	# planet._ready built a placeholder from default @export values
	# (radius=8, default color) during add_child, before this method
	# could override them.
	planet.apply_visual()

	# Spawn astronaut + fuel pickup children based on the now-set flags.
	# Must be called AFTER the @exports above are set — planet._ready
	# defaults has_astronaut and has_fuel to false, so spawning there
	# would silently skip every planet even when JSON says otherwise.
	planet.spawn_dynamic_children()

	# Orbital elements (closed-form orbit, see orbit_calculator.gd).
	planet.perihelion = spec.get("perihelion", 200.0)
	planet.aphelion = spec.get("aphelion", 200.0)
	planet.angle_of_aphelion = spec.get("angle_of_aphelion", 0.0)
	planet.phase = spec.get("phase", 0.0)

	# Physics.
	planet.mass = spec.get("mass", 1000.0)

	# Spawn moons as children of this planet. Each moon's parent in
	# the scene tree IS its host planet — see scripts/moon.gd and
	# `_instantiate_planet_moon`. Moons are surface-relative to the
	# planet, not center-relative.
	for moon_spec in spec.get("moons", []):
		_instantiate_planet_moon(planet, moon_spec)


## Instantiate a moon as a CHILD of the given planet and configure its
## @exports from the JSON spec. Same init-order pattern as
## `_instantiate_planet`: add_child, set @exports, then call
## apply_visual + spawn_dynamic_children + resolve_orbit. The moon's
## parent in the scene tree IS its host planet — no name lookup needed.
##
## The moon's perihelion and aphelion are **surface-relative** to the
## host planet (see scripts/moon.gd header). The moon script adds the
## host's radius internally to compute center-relative orbital distance,
## which makes it physically impossible for a moon to render inside its
## planet.
##
## Pre-refactor design: moons were siblings of planets, added to
## PlanetContainer alongside them, and used a `host_planet_name` string
## lookup to find their host. The body_label lookup bug (commit
## `68bb4ba`) is gone with the new architecture.
static func _instantiate_planet_moon(planet: Node2D, spec: Dictionary) -> void:
	var moon := MOON_SCENE.instantiate()
	planet.add_child(moon)

	# Gameplay flags.
	moon.is_landable = spec.get("is_landable", true)
	moon.has_astronaut = spec.get("has_astronaut", false)
	moon.has_fuel = spec.get("has_fuel", false)
	moon.fuel_orbit_radius = spec.get("fuel_orbit_radius", 8.0)
	moon.fuel_orbit_speed = spec.get("fuel_orbit_speed", 0.5)

	# Orbital elements (relative to host planet's SURFACE). The moon
	# script offsets by host_radius internally.
	moon.perihelion = spec.get("perihelion", 30.0)
	moon.aphelion = spec.get("aphelion", 30.0)
	moon.angle_of_aphelion = spec.get("angle_of_aphelion", 0.0)
	moon.phase = spec.get("phase", 0.0)
	moon.mass = spec.get("mass", 10.0)

	# Visual.
	moon.radius = spec.get("radius", 6.0)
	if spec.has("color"):
		var col: Array = spec["color"]
		if col.size() >= 3:
			var alpha: float = col[3] if col.size() >= 4 else 1.0
			moon.color = Color(col[0], col[1], col[2], alpha)

	# Same init-order pattern as planets: visual + children need @exports
	# set first; resolve_orbit needs _host_radius cached in _ready
	# (which fires on add_child above — planet's @exports were already
	# set by _instantiate_planet before this loop runs).
	moon.apply_visual()
	moon.spawn_dynamic_children()
	moon.resolve_orbit()


## Instantiate an asteroid and configure its @exports from the JSON
## spec. Asteroid-specific behaviors: `is_landable = false` by default
## (touching crashes regardless of speed), `mass = 0.0` (joins the
## "attractors" group for collision but exerts no gravity), and
## optional `has_fuel` for risk/reward fuel pickup near the rock.
static func _instantiate_asteroid(spec: Dictionary, container: Node) -> void:
	var asteroid := ASTEROID_SCENE.instantiate()
	container.add_child(asteroid)

	# Gameplay flags.
	asteroid.is_landable = spec.get("is_landable", false)
	asteroid.has_fuel = spec.get("has_fuel", false)
	asteroid.fuel_orbit_radius = spec.get("fuel_orbit_radius", 12.0)
	asteroid.fuel_orbit_speed = spec.get("fuel_orbit_speed", 0.3)

	# Orbital elements (sun-centered).
	asteroid.perihelion = spec.get("perihelion", 1500.0)
	asteroid.aphelion = spec.get("aphelion", 2000.0)
	asteroid.angle_of_aphelion = spec.get("angle_of_aphelion", 0.0)
	asteroid.phase = spec.get("phase", 0.0)
	asteroid.mass = spec.get("mass", 0.0)

	# Visual.
	asteroid.radius = spec.get("radius", 8.0)
	if spec.has("color"):
		var col: Array = spec["color"]
		if col.size() >= 3:
			var alpha: float = col[3] if col.size() >= 4 else 1.0
			asteroid.color = Color(col[0], col[1], col[2], alpha)

	asteroid.apply_visual()
	asteroid.spawn_dynamic_children()
