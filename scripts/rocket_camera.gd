extends Camera2D
##
## Camera that follows the rocket by default. Mouse wheel zooms in/out.
##
## Press [toggle_free_action] (default: F) to detach from the rocket and pan
## around the solar system with left-click drag. Press F again to re-attach —
## the camera will smoothly catch up to the rocket over a few frames (no snap).
##
## `top_level = true` keeps the camera in world coordinates, so it doesn't
## spin when the rocket rotates.
##

# --- Follow behavior (used when not in free-cam mode) ---
@export var follow_speed: float = 5.0   # higher = snappier catch-up

# --- Zoom (works in both modes) ---
@export var zoom_step: float = 0.15
@export var min_zoom: float = 0.1
@export var max_zoom: float = 3.0

# --- Free-camera toggle ---
@export var toggle_free_action: String = "toggle_free_camera"


var free_camera: bool = false
var _dragging: bool = false
var _drag_last_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	# `top_level = true` makes our transform be in world space, ignoring
	# the rocket's rotation. Without this, the whole world would spin as
	# the rocket rotates — which is disorienting and not what we want.
	top_level = true


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(toggle_free_action):
		free_camera = not free_camera
		# End any in-progress drag if we just switched modes, so we don't
		# suddenly snap-pan on the next motion event.
		_dragging = false

	if not free_camera:
		# Smoothly follow the parent (the rocket). `lerp` interpolates a
		# fraction of the way to the target each frame — at follow_speed=5
		# and 60fps, that's about 8% of the way per frame, which feels tight
		# but not instant. Also gives a graceful re-attach when toggling
		# out of free-cam mode.
		var target_pos: Vector2 = get_parent().global_position
		position = position.lerp(target_pos, follow_speed * delta)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel: zoom (always available, regardless of mode).
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_by(zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_by(-zoom_step)
			MOUSE_BUTTON_LEFT:
				# Start a left-click drag in free-cam mode (ignored otherwise,
				# so single clicks in follow mode don't accidentally pan).
				if free_camera:
					_dragging = true
					_drag_last_pos = event.position
		return

	# Mouse button release: end drag.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = false
		return

	# Mouse motion while dragging in free-cam: pan the camera.
	if event is InputEventMouseMotion and _dragging and free_camera:
		var motion: Vector2 = event.position - _drag_last_pos
		_drag_last_pos = event.position
		# Convert screen-pixel motion to world-space motion by dividing by zoom:
		# at zoom 2 (zoomed in), 1 screen pixel = 0.5 world units, so we move the
		# camera by half as much. Drag-right on screen should reveal world to
		# the right, so the camera moves LEFT (negative).
		position -= motion / zoom


func _zoom_by(delta_zoom: float) -> void:
	var new_zoom := zoom + Vector2(delta_zoom, delta_zoom)
	new_zoom = new_zoom.clamp(
		Vector2(min_zoom, min_zoom),
		Vector2(max_zoom, max_zoom)
	)
	zoom = new_zoom