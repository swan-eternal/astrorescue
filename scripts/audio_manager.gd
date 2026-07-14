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
## the loop stays seamless when set_thruster_volume() ramps volume
## up and down across the throttle range.
func _ready() -> void:
	# Music player: one stream at a time, swapped when the scene changes.
	# Routed to the "Music" bus so the music volume slider only affects
	# music and not SFX.
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)

	# Thruster player: long-lived so the loop is seamless across the
	# variable-throttle ramp. The thruster.ogg stream is loaded with
	# loop=true (set in its .import file) so the sound sustains as long
	# as set_thruster_volume() keeps volume above the deadzone. Routed
	# to the "SFX" bus so the audio settings menu's SFX slider applies
	# on top of the per-player volume.
	_thruster_player = AudioStreamPlayer.new()
	_thruster_player.bus = "SFX"
	var thruster_stream: AudioStream = load(SFX_THRUSTER)
	_thruster_player.stream = thruster_stream
	# Start silent — at the deadzone. Without this, the player's default
	# volume_db = 0 would play the thruster at full volume on level load
	# until rocket.gd's first set_thruster_volume(0.0) call fires. The
	# set_thruster_volume() helper handles starting playback once throttle
	# ramps above the deadzone.
	_thruster_player.volume_db = -80.0
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


# --- Thruster (variable-volume looping SFX) ---

## Set the thruster's playback volume to `volume` in [0.0, 1.0].
## Maps the rocket's current throttle to a perceptual loudness curve.
##
## Below the deadzone (≤ 0.001) the player is explicitly stopped to
## avoid sub-audible hiss at -60dB and free the audio thread when
## idle. The player object itself persists in the tree, so resuming
## just calls play() again — no reallocation cost.
##
## Above the deadzone the player is ensured to be playing and its
## volume_db is set via `linear_to_db(volume)` — perceptual scaling,
## so doubling `volume` roughly doubles perceived loudness. (Doubling
## amplitude in linear units is a +6dB change, which is the threshold
## of perceived "twice as loud" for most listeners.)
##
## Called every physics tick from rocket.gd with the current throttle
## value, so the audio tracks the throttle bar visually.
##
## The thruster stream is on the SFX bus, so the audio settings menu's
## SFX volume slider still applies on top of this per-player volume.
## `linear_to_db(1.0) = 0dB`, matching the thruster's pre-throttle
## default — so at full throttle the perceived loudness is unchanged
## from before this feature landed.
const THRUSTER_DEADZONE := 0.001

func set_thruster_volume(volume: float) -> void:
	var v: float = clampf(volume, 0.0, 1.0)
	if v <= THRUSTER_DEADZONE:
		# Below threshold — explicit stop. Player object stays in tree
		# so we don't pay the create-cost again when throttle ramps back up.
		_thruster_player.stop()
		return
	if not _thruster_player.playing:
		_thruster_player.play()
	_thruster_player.volume_db = linear_to_db(v)


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
