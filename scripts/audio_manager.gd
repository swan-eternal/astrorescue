extends Node
##
## AudioManager: global audio controller (autoload singleton).
##
## Manages background music (menu and gameplay) and SFX (looping thruster
## plus one-shot astronaut/fuel pickups). Created as an autoload so it's
## accessible from any scene as `AudioManager.play_*()`. Path-based access
## via `get_node("/root/AudioManager")` is used by consumers — see skill
## §6.1 for why we don't rely on the bare identifier.
##

const MUSIC_MENU := "res://assets/sound/menubackground.ogg"
const MUSIC_GAMEPLAY := "res://assets/sound/gamebackground.ogg"
const SFX_THRUSTER := "res://assets/sound/thruster.ogg"
const SFX_ASTRONAUT_PICKUP := "res://assets/sound/success_ding.ogg"
const SFX_FUEL_PICKUP := "res://assets/sound/fuelbloop.ogg"
const SFX_ROCKET_CRASH := "res://assets/sound/rocket_crash.ogg"

var _music_player: AudioStreamPlayer
var _thruster_player: AudioStreamPlayer


## Create the persistent AudioStreamPlayers: one for music (swapped
## per scene) and one for the looping thruster SFX. The thruster
## player is created here and lives for the whole game — that's how
## the loop stays seamless when start_thruster() is called.
func _ready() -> void:
	# Music player: one stream at a time, swapped when the scene changes.
	# Routed to the "Music" bus so the music volume slider only affects
	# music and not SFX.
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)

	# Thruster player: long-lived so the loop is seamless. The thruster.ogg
	# stream is loaded with loop=true (set in its .import file) so the sound
	# sustains as long as start_thruster() has been called. Routed to
	# the "SFX" bus.
	_thruster_player = AudioStreamPlayer.new()
	_thruster_player.bus = "SFX"
	var thruster_stream: AudioStream = load(SFX_THRUSTER)
	_thruster_player.stream = thruster_stream
	add_child(_thruster_player)


## Reserved hook for re-triggering looping streams that finished.
## Currently a no-op because the looping streams honor their loop flag
## and never emit "finished". Kept as a place to add recovery logic if
## we ever swap to a stream format that doesn't loop reliably.
func _process(_delta: float) -> void:
	pass


# --- Music ---

## Load `path` and start playing it on the music channel, looping.
## No-ops if the same track is already playing (avoids restarting on
## a duplicate call, e.g., two scene-ready handlers racing).
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


## Convenience: play the menu background track.
func play_menu_music() -> void:
	play_music(MUSIC_MENU)


## Convenience: play the gameplay background track.
func play_gameplay_music() -> void:
	play_music(MUSIC_GAMEPLAY)


## Stop the music channel entirely. Used by win/lose screens (no music
## during the result overlay).
func stop_music() -> void:
	_music_player.stop()


# --- Thruster (looping SFX) ---

## Start the thruster loop if it isn't already playing. Idempotent —
## safe to call every frame from rocket.gd without restarting the sound.
func start_thruster() -> void:
	if not _thruster_player.playing:
		_thruster_player.play()


## Stop the thruster loop. Idempotent — safe to call when already stopped.
func stop_thruster() -> void:
	_thruster_player.stop()


# --- One-shot SFX (astronaut/fuel pickup) ---

## Play a one-shot SFX from `path`. Creates a fresh AudioStreamPlayer,
## connects its `finished` signal to queue_free so we don't leak nodes
## after each pickup sound. Routed to the "SFX" bus.
##
## Note on loop behavior: `.import` files for Ogg streams can declare
## `loop=true` at the resource level (the thruster, fuel pickup, and
## both music tracks all do — see `assets/sound/*.import`). The
## `finished` signal only fires when the *stream* ends, which won't
## happen on a looping stream — so without this override, an
## imported `loop=true` stream played via `play_oneshot()` would
## loop forever and never reach `queue_free`, leaking the player.
## `assets/sound/fuelbloop.ogg` is the in-the-wild example: its
## `.import` has `loop=true` (matching its filename — it's the loop
## version of the asset), but it's used as a one-shot pickup cue.
## Forcing `loop = false` after load makes `play_oneshot` honor its
## name regardless of how the .import was authored. Same defensive
## pattern `play_music()` uses in reverse (`stream.loop = true`).
func play_oneshot(path: String) -> void:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.bus = "SFX"
	add_child(player)
	player.stream = load(path)
	# Force one-shot semantics regardless of the .import's loop setting
	# — see the docstring above for the fuelbloop.ogg bug this prevents.
	player.stream.loop = false
	player.play()
	# Auto-cleanup: free the player when the sound finishes. This avoids
	# leaking AudioStreamPlayer nodes for each one-shot SFX.
	player.finished.connect(player.queue_free)


## Convenience: play the astronaut-pickup success sound.
func play_astronaut_pickup() -> void:
	play_oneshot(SFX_ASTRONAUT_PICKUP)


## Convenience: play the fuel-pickup loop sound.
func play_fuel_pickup() -> void:
	play_oneshot(SFX_FUEL_PICKUP)


## Convenience: play the rocket-crash sound. One-shot — plays once
## per call, no loop. Routed to the "SFX" bus via `play_oneshot`.
## Called from `scripts/rocket.gd` at the moment of crash in both
## the non-landable (sun, asteroid) and over-speed branches.
func play_rocket_crash() -> void:
	play_oneshot(SFX_ROCKET_CRASH)
