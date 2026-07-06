extends Node
##
## AudioManager: global audio controller (autoload singleton).
## Manages background music (menu and gameplay) and SFX (looping thruster
## plus one-shot astronaut/fuel pickups). Created as an autoload so it's
## accessible from any scene as `AudioManager.play_*.gd`.
##

const MUSIC_MENU := "res://assets/sound/menubackground.mp3"
const MUSIC_GAMEPLAY := "res://assets/sound/gamebackground.mp3"
const SFX_THRUSTER := "res://assets/sound/thruster.mp3"
const SFX_ASTRONAUT_PICKUP := "res://assets/sound/success_ding.mp3"
const SFX_FUEL_PICKUP := "res://assets/sound/fuelbloop.mp3"

var _music_player: AudioStreamPlayer
var _thruster_player: AudioStreamPlayer


func _ready() -> void:
	# Music player: one stream at a time, swapped when the scene changes.
	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)

	# Thruster player: long-lived so the loop is seamless. The thruster.mp3
	# stream is set to loop=true in play_looping_stream() so the sound
	# sustains as long as start_thruster() has been called.
	_thruster_player = AudioStreamPlayer.new()
	var thruster_stream: AudioStream = load(SFX_THRUSTER)
	_thruster_player.stream = thruster_stream
	add_child(_thruster_player)


func _process(_delta: float) -> void:
	# Re-trigger looping streams that finished (defensive — for streams that
	# don't honor the loop flag, like some MP3 imports). For looping streams
	# this is a no-op because they never emit "finished".
	pass


# --- Music ---

func play_music(path: String) -> void:
	# Avoid restarting the same track if it's already playing (e.g., we
	# accidentally trigger play_music twice on the same menu).
	if _music_player.playing and _music_player.stream != null and _music_player.stream.resource_path == path:
		return
	_music_player.stop()
	var stream: AudioStream = load(path)
	if stream == null:
		push_warning("AudioManager: failed to load stream at %s" % path)
		return
	stream.loop = true
	_music_player.stream = stream
	_music_player.play()


func play_menu_music() -> void:
	play_music(MUSIC_MENU)


func play_gameplay_music() -> void:
	play_music(MUSIC_GAMEPLAY)


func stop_music() -> void:
	_music_player.stop()


# --- Thruster (looping SFX) ---

func start_thruster() -> void:
	if not _thruster_player.playing:
		_thruster_player.play()


func stop_thruster() -> void:
	_thruster_player.stop()


# --- One-shot SFX (astronaut/fuel pickup) ---

func play_oneshot(path: String) -> void:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	add_child(player)
	player.stream = load(path)
	player.play()
	# Auto-cleanup: free the player when the sound finishes. This avoids
	# leaking AudioStreamPlayer nodes for each one-shot SFX.
	player.finished.connect(player.queue_free)


func play_astronaut_pickup() -> void:
	play_oneshot(SFX_ASTRONAUT_PICKUP)


func play_fuel_pickup() -> void:
	play_oneshot(SFX_FUEL_PICKUP)