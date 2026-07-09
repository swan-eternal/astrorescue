extends Node2D
##
## Visualizes each planet's Sphere of Influence (SOI) as a semi-
## transparent shaded circle. Useful for level planning — shows the
## designer where trajectory mode would auto-switch from sun-centered
## to planet-centered, and lets them see how mass adjustments affect
## SOI extent in real-time when editing a level.
##
## SOI = Hill sphere × `soi_fraction`, same math the SOI detection
## in `trajectoryline_2d.gd` uses. Both call
## `OrbitCalculator.compute_soi_radius` so the visualization always
## matches the gameplay-relevant region.
##
## Editor-only for now. Added to the level editor's `_viewport_root`
## before `SunContainer` so it renders behind bodies. Persists across
## `_refresh_viewport()` because `LevelLoader.build_scene_from_spec`
## only clears `SunContainer` and `BodyContainer` children, not other
## children of root.
##

## Toggle visibility. Useful for hiding the visualization if it's
## distracting during non-planning edits.
@export var enabled: bool = true

## Fill color for each SOI region. Light blue, low alpha so the
## background and bodies stay visible through it.
@export var fill_color: Color = Color(0.4, 0.7, 1.0, 0.08)

## Border color for each SOI circle. Slightly more opaque than fill
## so the circle's edge is clearly visible.
@export var border_color: Color = Color(0.4, 0.7, 1.0, 0.4)

## Border width in pixels. Scales inversely with camera zoom to
## stay readable at any zoom level (same scheme as trajectory lines).
@export var border_width: float = 1.5

## Number of segments used to approximate each circle. Higher = smoother
## but more vertices to draw. 64 is plenty for typical visual use.
@export var circle_segments: int = 64

## Hill-sphere fraction for SOI computation. Must match the value used
## by `trajectoryline_2d.gd`'s SOI detection for the visualization to
## represent the actual gameplay-relevant region. Default references
## `OrbitCalculator.DEFAULT_SOI_FRACTION` so both files share one
## source of truth — override per-instance in the editor scene if
## needed.
@export var soi_fraction: float = OrbitCalculator.DEFAULT_SOI_FRACTION

## If true, ignores `VisualSettings.is_show_soi()` and always draws
## (subject to `enabled`). Used by the level editor, where the SOI is
## a planning aid that should always be visible regardless of the
## user's in-game setting. Default false (game instances respect the
## user's toggle).
@export var bypass_visual_settings: bool = false


# Cached reference to the sun (heaviest body in "attractors"). Mass is
# read each frame from sun.mass so inspector tweaks take effect live —
# matches the trajectory-line pattern.
var sun: Node2D = null

# Mirror of sun.mass refreshed each frame. Cached here so the draw
# loop doesn't have to call .get("mass") per planet per frame.
var sun_mass: float = 0.0


## Each frame: refresh sun mass, queue a redraw. Drawing happens in
## `_draw()` so it picks up the current sun + planet state.
func _process(_delta: float) -> void:
	# Lazy-init sun: in the editor's first frame, planets may not have
	# been instantiated yet. Retry until found; cheap (one group lookup).
	if sun == null:
		sun = _find_sun()
	if sun != null:
		sun_mass = float(sun.get("mass"))
	queue_redraw()


## Find the sun = heaviest body in the "attractors" group. Returns null
## when no attractors yet (e.g., very early frame, or the spec is empty).
func _find_sun() -> Node2D:
	var attractors := get_tree().get_nodes_in_group("attractors")
	var heaviest: Node2D = null
	var heaviest_mass := 0.0
	for body in attractors:
		var m: float = float(body.get("mass"))
		if m > heaviest_mass:
			heaviest_mass = m
			heaviest = body
	return heaviest


## Draw a filled circle + border for each planet's SOI. Skips the sun
## itself (it has no SOI) and bodies heavier than half the sun (which
## would be a second sun, not a planet — same threshold
## `trajectoryline_2d.gd` uses to classify). Border width scales
## inversely with camera zoom so the lines stay readable when zoomed
## out — same scheme as the trajectory-line width scaling.
##
## Visibility gates (in evaluation order):
##   1. `enabled` — per-instance kill switch (e.g., disable in a specific
##      viewport without touching the global setting).
##   2. `VisualSettings.is_show_soi()` — user toggle in Settings → Visual.
##      Skipped when `bypass_visual_settings` is true (editor instance).
##   3. `sun` and `sun_mass > 0.0` — can't draw without a primary to
##      orbit around.
func _draw() -> void:
	if not enabled:
		return
	if not bypass_visual_settings and not VisualSettings.is_show_soi():
		return
	if sun == null or sun_mass <= 0.0:
		return

	# Scale border width inversely with camera zoom — keeps the lines
	# readable when zoomed out, never thicker than `border_width` when
	# zoomed in. Clamp avoids division blowup at extreme zoom-out.
	var cam := get_viewport().get_camera_2d()
	var zoom_factor: float = clampf(cam.zoom.x, 0.1, 1.0) if cam != null else 1.0
	var scaled_border_width: float = border_width / zoom_factor

	for body in get_tree().get_nodes_in_group("attractors"):
		if body == sun:
			continue
		var m: float = float(body.get("mass"))
		# Mass=0 asteroids still get a degenerate SOI; skip them. Heavy
		# bodies (≥ half the sun) aren't "planets" in the SOI sense —
		# the Hill-sphere formula assumes m << M_sun.
		if m <= 0.0 or m >= sun_mass * 0.5:
			continue

		var orbital_distance: float = body.global_position.distance_to(sun.global_position)
		var soi_radius: float = OrbitCalculator.compute_soi_radius(
			m, sun_mass, orbital_distance, soi_fraction)
		if soi_radius <= 0.0:
			continue

		var center: Vector2 = body.global_position
		draw_circle(center, soi_radius, fill_color)
		draw_arc(center, soi_radius, 0.0, TAU, circle_segments,
			border_color, scaled_border_width, true)