extends Node
##
## LevelLoader: reads level_NN.json and builds the scene from it.
##
## Attached to scenes/level.tscn (the shared infrastructure scene). On
## _ready, reads `data/levels/level_<SaveState.current_level_number>.json`,
## instantiates bodies (sun, planets) from the spec, and configures
## the rocket's @exports.
##
## All level-specific data lives in JSON — this loader is the only
## script that interprets it. The shared level.tscn contains no
## per-level data.
##

const SUN_SCENE := preload("res://scenes/sun.tscn")
const PLANET_SCENE := preload("res://scenes/planet.tscn")
const LEVELS_DIR := "res://data/levels/"


## Resolve the level path, load JSON, instantiate bodies, configure
## the rocket. Called from _ready so it runs after the rest of the
## scene is set up but before any _physics_process fires on planets.
func _ready() -> void:
	_load_level()


## Resolve the level number from SaveState (set by main_menu /
## level_select in Phase 8), load the corresponding JSON, and build
## the scene's per-level content from it.
func _load_level() -> void:
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

	# Validate schema version. v2 uses orbital elements + body-type
	# polymorphism; earlier schemas (v1) used orbit_radius and a
	# separate sun/planets[] layout — not supported here.
	var version: int = data.get("version", 0)
	if version != 2:
		push_error("LevelLoader: unsupported schema version %d (expected 2)" % version)
		return

	# Instantiate each body in the JSON spec.
	for body_spec in data.get("bodies", []):
		var body_type: String = body_spec.get("type", "")
		match body_type:
			"sun":
				_instantiate_sun(body_spec)
			"planet":
				_instantiate_planet(body_spec)
			_:
				push_warning("LevelLoader: unknown body type '%s' (skipped)" % body_type)

	# Configure the rocket's @exports from the JSON's "rocket" section.
	_configure_rocket(data.get("rocket", {}))


## Instantiate the sun (at most one per level) and add to SunContainer.
## Sun is a gravity source; it has no orbit so we just set mass and
## position. @exports are set AFTER add_child per skill §1.5.
func _instantiate_sun(spec: Dictionary) -> void:
	var sun := SUN_SCENE.instantiate()
	get_node("../SunContainer").add_child(sun)
	sun.mass = spec.get("mass", 4_000_000.0)
	sun.radius = spec.get("radius", 200.0)
	if spec.has("position"):
		var pos: Array = spec["position"]
		if pos.size() >= 2:
			sun.position = Vector2(pos[0], pos[1])


## Instantiate a planet and configure its @exports from the JSON spec.
## @exports are set AFTER add_child per skill §1.5 — the planet script
## is fully initialized at that point. Note: the new @physics_process
## will run on the next frame, by which time all @exports are set.
func _instantiate_planet(spec: Dictionary) -> void:
	var planet := PLANET_SCENE.instantiate()
	get_node("../PlanetContainer").add_child(planet)

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


## Configure the rocket's @exports from the JSON's "rocket" section.
## The rocket is a placeholder in level.tscn; this method tunes its
## per-level values (thrust, speed thresholds, fuel, etc.).
##
## Note: the rocket's _ready fires before this method runs (because
## add_child triggers _ready). For level_01 this is fine because
## _snap_to_home_planet positions the rocket correctly regardless of
## the initial_position value. For levels without a home planet, the
## initial_position override would be lost — see Phase 7 plan notes.
func _configure_rocket(spec: Dictionary) -> void:
	var rocket: Node2D = get_tree().get_first_node_in_group("player")
	if rocket == null:
		push_warning("LevelLoader: rocket not found in 'player' group (still loading?)")
		return

	# Initial position and velocity — only per-level values the JSON
	# carries. Game-wide rocket characteristics (thrust, landing/crash
	# thresholds, fuel capacity, etc.) are configured in rocket.gd's
	# @export defaults so they're all in one place.
	#
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
