extends CanvasLayer
##
## Post-processing layer: applies screen-space shader effects to
## the rendered scene below. Polls VisualSettings each frame and
## pushes values to the ShaderMaterial's uniforms (cached: only
## pushes when the value changes).
##
## Per-frame-poll pattern matches scripts/soi_indicator.gd —
## avoids signal wiring and the value-sync bugs that come with it.
## If the uniform list grows large (Phase 3+ adds more effects),
## swap to a signal-based push from VisualSettings to avoid polling
## N values every frame.
##

# Cached reference to the ColorRect that holds the ShaderMaterial.
# Resolved in _ready so $ColorRect is safe to access (the scene
# tree must be fully built before any child lookups).
@onready var _color_rect: ColorRect = $ColorRect

# Cache the last value pushed to the shader uniform. Avoids the
# (cheap-but-unnecessary) set_shader_parameter call when the
# persisted value hasn't changed since last frame. Sentinel value
# -1.0 guarantees the first frame always pushes (real values are
# in [0.0, 1.0]).
var _last_vignette_intensity: float = -1.0


func _process(_delta: float) -> void:
	if not _color_rect.material is ShaderMaterial:
		# Defensive: if the ShaderMaterial is ever removed from the
		# ColorRect (e.g., during editor fiddling), there's no work
		# to do. The shader IS the point of this node.
		return
	var mat: ShaderMaterial = _color_rect.material
	var vignette_intensity: float = VisualSettings.get_vignette_intensity()
	if vignette_intensity != _last_vignette_intensity:
		mat.set_shader_parameter("vignette_intensity", vignette_intensity)
		_last_vignette_intensity = vignette_intensity