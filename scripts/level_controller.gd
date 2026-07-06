extends Node
##
## LevelController: per-level logic. Watches rocket state and triggers
## scene transitions for win/lose conditions.
##
## Attached as a child node of each level scene (level_NN.tscn). Configure
## `level_number` per level so SaveState.complete_level() knows which
## level was just won.
##

@export var level_number: int = 1

var rocket: Node2D = null
var save_state: Node = null  # cached reference to the SaveState autoload (resolved by path)
var _audio_manager: Node = null  # cached reference to the AudioManager autoload (resolved by path; see comment on save_state)
var total_astronauts: int = 0
var _win_triggered: bool = false
var _lose_triggered: bool = false


func _ready() -> void:
	# IMPORTANT: defer all initialization to _initialize() rather than doing it
	# here. _ready() runs in tree order — LevelController is the first child of
	# level_01, so its _ready() runs BEFORE the rocket has added itself to the
	# "player" group and BEFORE planets have added themselves to "attractors".
	# Querying those groups in _ready would return empty, leading to silent bugs
	# (e.g., total_astronauts stays 0, win check never fires).
	# call_deferred runs after all _ready calls in the tree have completed,
	# so the groups are fully populated.
	call_deferred("_initialize")


func _initialize() -> void:
	rocket = get_tree().get_first_node_in_group("player")
	if rocket == null:
		push_warning("LevelController: rocket not found in 'player' group")
		return

	# Resolve the SaveState autoload by its known scene tree path rather than
	# its name. The autoload's name IS registered as a global identifier in
	# Godot, but in some setups (e.g., manually editing project.godot without
	# reopening the project in the editor) the parser hasn't picked it up yet,
	# causing "Identifier not found" errors. Path-based access sidesteps that.
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


func _go_to_win_screen() -> void:
	if not is_instance_valid(self):
		return  # scene was reloaded (e.g., R pressed) during the delay; abort
	get_tree().change_scene_to_file("res://scenes/win_screen.tscn")


func _go_to_lose_screen() -> void:
	if not is_instance_valid(self):
		return  # scene was reloaded (e.g., R pressed) during the delay; abort
	get_tree().change_scene_to_file("res://scenes/lose_screen.tscn")
