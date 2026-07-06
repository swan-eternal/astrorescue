extends Node
##
## LevelController: per-level logic. Watches rocket state and triggers
## scene transitions for win/lose conditions.
##
## Attached as a child node of each level scene (level_NN.tscn). Configure
## `level_number` per level so SaveState.complete_level() knows which
## level was just won.
##

## The 1-based level number for THIS level (1, 2, 3, ...). Set in the
## inspector per level scene; passed to SaveState.complete_level() on win
## so the persistent record reflects which level was just beaten.
@export var level_number: int = 1

# Cached reference to the rocket node (found via "player" group).
# Read each physics tick to check win/lose conditions.
var rocket: Node2D = null

# Cached reference to the SaveState autoload, resolved by scene-tree
# path. Path-based access sidesteps the "Identifier not declared" parse
# error that occurs after a manual project.godot edit before the editor
# has been reopened — see skill §6.1 for the full pattern.
var save_state: Node = null

# Cached reference to the AudioManager autoload (same path-based pattern
# as save_state — see §6.1).
var _audio_manager: Node = null

# Total astronauts in this level, counted once in _initialize() by
# scanning the "attractors" group for has_astronaut = true.
var total_astronauts: int = 0

# Latches: true once we've triggered a win/lose transition so we
# don't double-fire (the create_timer callback runs once after 0.5s;
# during that window _physics_process would otherwise fire it again).
var _win_triggered: bool = false
var _lose_triggered: bool = false


## Defer all group-dependent initialization to _initialize() via
## call_deferred. Reason: this script's _ready() runs in tree order,
## and LevelController is typically the first child of a level scene —
## its _ready() runs BEFORE the rocket has joined "player" and BEFORE
## planets have joined "attractors". Querying those groups here would
## return empty, leading to silent bugs (total_astronauts stays 0,
## win check never fires). call_deferred runs after all _ready calls
## in the tree have completed.
func _ready() -> void:
	call_deferred("_initialize")


## Cache references to the rocket + autoloads, count this level's
## astronauts, and start the gameplay music. Runs once, deferred until
## after every node's _ready() has fired.
func _initialize() -> void:
	rocket = get_tree().get_first_node_in_group("player")
	if rocket == null:
		push_warning("LevelController: rocket not found in 'player' group")
		return

	save_state = get_node("/root/SaveState")
	if save_state == null:
		push_warning("LevelController: SaveState autoload not found at /root/SaveState")

	_audio_manager = get_node("/root/AudioManager")
	if _audio_manager == null:
		push_warning("LevelController: AudioManager autoload not found at /root/AudioManager")

	# Discover total astronauts in this level by counting `has_astronaut = true`.
	for body in get_tree().get_nodes_in_group("attractors"):
		if body.get("has_astronaut"):
			total_astronauts += 1

	# Background music for the level. _initialize runs after all _ready calls
	# (via call_deferred), so the scene is fully loaded by the time music starts.
	_audio_manager.play_gameplay_music()


## Each physics tick: check win/lose conditions on the rocket and
## trigger the corresponding scene transition (with a short delay so
## the landing visuals register before the screen swap).
func _physics_process(_delta: float) -> void:
	if rocket == null or _win_triggered or _lose_triggered:
		return

	# Win check: every astronaut picked up AND currently on the home planet.
	# The home-planet check is what makes "win" require actual delivery to base,
	# not just collecting them anywhere.
	if total_astronauts > 0 and rocket.picked_up_count >= total_astronauts:
		if rocket.landed and rocket.landed_planet != null and rocket.landed_planet.get("is_home"):
			_win_triggered = true
			if save_state != null:
				save_state.complete_level(level_number)
			# Brief delay so the landing visuals register before transition.
			get_tree().create_timer(0.5).timeout.connect(_go_to_win_screen)
			return

	# Lose check: rocket crashed.
	if rocket.crashed:
		_lose_triggered = true
		get_tree().create_timer(0.5).timeout.connect(_go_to_lose_screen)


## Switch to the win screen. Connected to a 0.5s timer so the win
## state is briefly visible before the scene change.
func _go_to_win_screen() -> void:
	if not is_instance_valid(self):
		return  # scene was reloaded (e.g., R pressed) during the delay; abort
	get_tree().change_scene_to_file("res://scenes/win_screen.tscn")


## Switch to the lose screen. Same deferred-trigger pattern as
## _go_to_win_screen; the is_instance_valid guard handles the case of
## pressing R during the transition delay.
func _go_to_lose_screen() -> void:
	if not is_instance_valid(self):
		return  # scene was reloaded (e.g., R pressed) during the delay; abort
	get_tree().change_scene_to_file("res://scenes/lose_screen.tscn")
