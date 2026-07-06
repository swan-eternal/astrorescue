extends Polygon2D
##
## A small helper: draws a filled circle as this node's polygon.
## Tweak `radius` and `segments` in the Inspector — they'll take effect
## the next time the scene is loaded (press F6 again to refresh).
##
## We use this for the sun, planets, asteroids — anything that's
## "just a colored disk for now." Once we have real art, this gets
## replaced by Sprite2D + a PNG.
##

## Circle radius in world units. Bigger = larger disk drawn.
@export var radius: float = 60.0

## Number of polygon vertices used to approximate the circle.
## 48 is smooth at any realistic zoom; lower it for quick visual debug.
@export var segments: int = 48


## Build the polygon and assign it to this node. Only runs once at
## scene load — changes to radius/segments take effect on the next
## scene reload (F6 in the editor).
func _ready() -> void:
	var pts := PackedVector2Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	polygon = pts
