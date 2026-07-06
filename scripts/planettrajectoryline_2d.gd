extends Line2D
##
## Draws the planet's orbital ellipse (sun-only 2-body orbit).
## Computed analytically from the planet's current position and velocity.
## The sun's mass is read dynamically each frame — change `sun.mass` in
## the inspector and the ellipse updates without restart.
##

@export var segments: int = 64
@export var line_width: float = 1.0
@export var default_alpha: float = 0.5

# Time markers — small dots at fixed time intervals around the planet's
# orbit ellipse showing "where the planet will be at time T" for planning.
# Markers are drawn in screen space, but only when their projected screen
# position is within the viewport. Off-screen markers are dropped.
@export var time_marker_interval: float = 30.0
@export var time_marker_radius: float = 4.0
@export var time_marker_color: Color = Color(1.0, 0.95, 0.2, 0.95)  # bright yellow
@export var time_marker_margin: float = 0.0  # edge buffer in pixels (0 = strict in/out)

const G := 1.0
const MIN_DIST := 1.0
const TimeMarkerScene: PackedScene = preload("res://scenes/time_marker.tscn")


var planet: Node2D = null
var sun: Node2D = null  # cached node reference; mass read each frame
var _time_marker_canvas: CanvasLayer  # child CanvasLayer so markers draw in screen space
var _time_marker: Control              # the actual marker Control, child of the CanvasLayer


func _ready() -> void:
 top_level = true
 width = line_width
 planet = get_parent()
 sun = _find_sun()

 var planet_color: Color = Color(planet.get("color"))
 planet_color.a = default_alpha
 default_color = planet_color

 # Create a CanvasLayer for screen-space marker rendering.
 _time_marker_canvas = CanvasLayer.new()
 _time_marker_canvas.layer = 100
 add_child(_time_marker_canvas)

 # Create the TimeMarker as a child of the CanvasLayer (in screen space).
 _time_marker = TimeMarkerScene.instantiate()
 _time_marker.marker_radius = time_marker_radius
 _time_marker.marker_color = time_marker_color
 _time_marker_canvas.add_child(_time_marker)


func _process(_delta: float) -> void:
 if planet == null or sun == null:
  return

 # Scale line width inversely with camera zoom — same scheme as the player
 # trajectory line, so all orbit ellipses stay readable when zoomed out.
 var cam := get_viewport().get_camera_2d()
 var zoom_factor: float = clampf(cam.zoom.x, 0.1, 1.0) if cam != null else 1.0
 width = line_width / zoom_factor

 var sun_mass: float = float(sun.get("mass"))
 points = _compute_orbit_ellipse(
  planet.global_position,
  Vector2(planet.get("velocity")),
  sun_mass
 )
 _time_marker.update_positions(_world_to_screen_markers(_compute_orbit_markers()))


# Find the sun = heaviest body in the "attractors" group.
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


func _compute_orbit_ellipse(r: Vector2, v: Vector2, mu: float) -> PackedVector2Array:
 var dist: float = maxf(r.length(), MIN_DIST)
 var v_sq: float = v.length_squared()

 var epsilon: float = v_sq / 2.0 - mu / dist
 if epsilon >= 0.0:
  return PackedVector2Array([r])  # unbound (hyperbolic) — just show current point

 var h: float = r.x * v.y - r.y * v.x
 var a: float = -mu / (2.0 * epsilon)

 var e_vec: Vector2 = ((v_sq - mu / dist) * r - r.dot(v) * v) / mu
 var e: float = e_vec.length()
 var omega: float = atan2(e_vec.y, e_vec.x)

 var pts := PackedVector2Array()
 var one_minus_e_sq: float = 1.0 - e * e
 for i in segments:
  var theta: float = TAU * float(i) / float(segments)
  var r_orbit: float = a * one_minus_e_sq / (1.0 + e * cos(theta - omega))
  pts.append(Vector2(r_orbit * cos(theta), r_orbit * sin(theta)))
 pts.append(pts[0])  # close the loop — last sample is at theta = (n-1)/n * TAU, missing the segment back to 0
 return pts


# Compute world positions of dots placed at fixed time intervals around the
# planet's orbit. Each orbit segment is T/segments in time, so we pick every
# (time_marker_interval / (T/segments)) indices. Uses a linear time↔angle
# mapping (good enough for nearly-circular orbits, the case for current levels).
func _compute_orbit_markers() -> PackedVector2Array:
 var markers: PackedVector2Array = PackedVector2Array()
 if time_marker_interval <= 0.0 or points.is_empty() or sun == null or planet == null:
  return markers
 var sun_mass_val: float = float(sun.get("mass"))
 if sun_mass_val <= 0.0:
  return markers
 var orbit_radius_val: float = float(planet.get("orbit_radius"))
 if orbit_radius_val <= 0.0:
  return markers
 var period: float = TAU * sqrt(orbit_radius_val * orbit_radius_val * orbit_radius_val / (G * sun_mass_val))
 if period <= 0.0:
  return markers
 var step_index: int = max(1, int(round(time_marker_interval * float(segments) / period)))
 var i: int = step_index
 while i < segments:
  markers.append(points[i])
  i += step_index
 return markers


# Convert a list of world-space marker positions to screen-space, INCLUDING
# only those that fall within the viewport (with optional edge buffer).
# Off-screen markers are dropped, not clamped — strict visibility.
func _world_to_screen_markers(world_positions: PackedVector2Array) -> PackedVector2Array:
 var canvas_xform: Transform2D = get_viewport().get_canvas_transform()
 var viewport_size: Vector2 = get_viewport_rect().size
 var screen_positions: PackedVector2Array = PackedVector2Array()
 for world_pos in world_positions:
  var screen_pos: Vector2 = canvas_xform * world_pos
  if screen_pos.x >= time_marker_margin and \
     screen_pos.x <= viewport_size.x - time_marker_margin and \
     screen_pos.y >= time_marker_margin and \
     screen_pos.y <= viewport_size.y - time_marker_margin:
   screen_positions.append(screen_pos)
 return screen_positions
