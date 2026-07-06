extends CanvasLayer
##
## Rocket HUD: relative velocity (color-coded for landing safety), fuel bar, trajectory mode.
##

@onready var velocity_label: Label = $MarginContainer/HBoxContainer/VBoxContainer/VelocityLabel
@onready var fuel_bar: ProgressBar = $MarginContainer/HBoxContainer/VBoxContainer/FuelBar
@onready var trajectory_label: Label = $MarginContainer/HBoxContainer/VBoxContainer/TrajectoryLabel
@onready var camera_label: Label = $MarginContainer/HBoxContainer/VBoxContainer/CameraLabel
@onready var astronaut_label: Label = $MarginContainer/HBoxContainer/VBoxContainer/AstronautLabel
@onready var time_warp_label: Label = $MarginContainer/HBoxContainer/VBoxContainer/TimeWarpLabel


var rocket: Node2D = null
var trajectory_line: Line2D = null
var camera: Camera2D = null
var total_astronauts: int = 0


# Colors for the relative-velocity indicator (label font color via `modulate`).
const COLOR_SAFE: Color = Color(0.4, 1.0, 0.4)      # green — rel_speed ≤ landing threshold
const COLOR_CAUTION: Color = Color(1.0, 0.75, 0.0)  # orange — between landing and crash
const COLOR_CRASH: Color = Color(1.0, 0.3, 0.3)     # red — rel_speed ≥ crash threshold
const COLOR_INACTIVE: Color = Color(1.0, 1.0, 1.0)  # white — no planet in range


## Resolve cached references: the rocket (via "player" group), the
## trajectory Line2D and Camera2D (both children of the rocket), and
## the total astronaut count for this level. Runs once at scene load;
## safe to fail gracefully (warnings instead of crashes) so the HUD
## degrades to empty labels if the rocket isn't found yet.
func _ready() -> void:
	# Find the rocket via the "player" group (added in rocket.gd's _ready).
	rocket = get_tree().get_first_node_in_group("player")
	if rocket == null:
		push_warning("HUD: no rocket found in 'player' group")
		return

	# Find the trajectory line and camera — they're both children of the rocket.
	for child in rocket.get_children():
		if child is Line2D:
			trajectory_line = child
		elif child is Camera2D:
			camera = child

	# Count astronauts in level (one per planet with has_astronaut = true).
	# Discovered at startup so the HUD doesn't need to be updated when
	# levels change. Implicit bool coercion handles null/false/true uniformly
	# (sun doesn't have this property → null → skipped).
	for body in get_tree().get_nodes_in_group("attractors"):
		if body.get("has_astronaut"):
			total_astronauts += 1


## Update every HUD label each frame. Cheap work (a few label.text
## assignments + modulate swaps) so the cost is dominated by the
## _find_nearest_planet() distance scan.
func _process(_delta: float) -> void:
	if rocket == null:
		return

	# Relative velocity vs. the nearest planet — the meaningful number for landing.
	var nearest := _find_nearest_planet()
	if nearest != null:
		var rel_speed: float = (Vector2(rocket.get("velocity")) - Vector2(nearest.get("velocity"))).length()
		velocity_label.text = "Rel. Velocity: %.1f  [%s]" % [rel_speed, nearest.name]
		var landing_threshold: float = float(rocket.get("landing_speed_threshold"))
		var crash_threshold: float = float(rocket.get("crash_speed_threshold"))
		if rel_speed <= landing_threshold:
			velocity_label.modulate = COLOR_SAFE
		elif rel_speed >= crash_threshold:
			velocity_label.modulate = COLOR_CRASH
		else:
			velocity_label.modulate = COLOR_CAUTION
	else:
		velocity_label.text = "Rel. Velocity: —"
		velocity_label.modulate = COLOR_INACTIVE

	# Fuel bar (depletes on thrust, refills on pickup).
	var fuel: float = float(rocket.get("fuel"))
	var max_fuel: float = float(rocket.get("max_fuel"))
	if max_fuel > 0.0:
		fuel_bar.max_value = max_fuel
		# Color-code: white above 50%, yellow above 25%, red below.
		var fuel_ratio := fuel / max_fuel
		if fuel_ratio > 0.5:
			fuel_bar.modulate = Color(1.0, 1.0, 1.0)
		elif fuel_ratio > 0.25:
			fuel_bar.modulate = Color(1.0, 0.8, 0.0)
		else:
			fuel_bar.modulate = Color(1.0, 0.3, 0.3)
	fuel_bar.value = fuel

	# Trajectory mode (set by the Line2D's `mode` enum).
	var mode_val: int = int(trajectory_line.get("mode")) if trajectory_line != null else -1
	var mode_str: String = "ORBITAL" if mode_val == 1 else ("TRUE" if mode_val == 0 else "—")
	trajectory_label.text = "Trajectory [Tab]: %s" % mode_str

	# Camera mode (FIXED = follow rocket, FREE = manual pan).
	if camera != null:
		var cam_state: String = "FREE" if bool(camera.get("free_camera")) else "FIXED"
		camera_label.text = "Camera [F]: %s" % cam_state
	else:
		camera_label.text = "Camera [F]: —"

	# Time warp level (reads Engine.time_scale directly; rocket updates it).
	time_warp_label.text = "Time warp [< >]: %dx" % int(Engine.time_scale)

	# Astronaut indicators: ● picked, ○ unpicked. Total is discovered at startup.
	if total_astronauts > 0:
		var rescued: int = int(rocket.get("picked_up_count"))
		astronaut_label.text = "Astronauts: %s%s" % [
			"● ".repeat(rescued),
			"○ ".repeat(total_astronauts - rescued)
		]
	else:
		astronaut_label.text = "Astronauts: —"


## Find the closest attractor that has a `radius` (a landable planet).
## Used by the HUD to pick the reference body for relative-velocity display.
## Mirrors rocket.gd's `_find_nearest_attractor` — kept separate so the HUD
## doesn't need to reach into the rocket's internals.
func _find_nearest_planet() -> Node2D:
	var nearest: Node2D = null
	var nearest_d2: float = INF
	for body in get_tree().get_nodes_in_group("attractors"):
		if body == rocket:
			continue
		if body.get("radius") == null:
			continue
		var d2: float = rocket.global_position.distance_squared_to(body.global_position)
		if d2 < nearest_d2:
			nearest_d2 = d2
			nearest = body
	return nearest
