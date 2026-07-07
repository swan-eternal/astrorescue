extends Polygon2D
##
## A small helper: draws a filled circle as this node's polygon.
## Radius is read from the parent (which is `sun.gd` for the sun),
## so the visual disk and the collision radius share a single source
## of truth. Segment count is local — circles only need ~48 vertices
## to look smooth at any realistic zoom.
##

## Number of polygon vertices used to approximate the circle.
## 48 is smooth at any realistic zoom; lower it for quick visual debug.
@export var segments: int = 48


## Build the polygon and assign it to this node. Reads `radius` from
## the parent so the visual disk size matches the parent's collision
## radius (kept in sync by construction — same source of truth).
func _ready() -> void:
	var parent := get_parent()
	var r: float = float(parent.get("radius"))
	var pts := PackedVector2Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(angle), sin(angle)) * r)
	polygon = pts
