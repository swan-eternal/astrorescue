extends CanvasLayer
##
## Post-processing layer: applies the vignette screen-space shader
## effect to the rendered scene below.
##
## One responsibility per frame:
##   - Vignette: poll VisualSettings.get_vignette_intensity(),
##     push to the ShaderMaterial's `vignette_intensity` uniform.
##     Cached (only pushes on change) — cheap.
##
## Per-frame-poll pattern matches scripts/soi_indicator.gd —
## avoids signal wiring and the value-sync bugs that come with it.
##

# Cached reference to the ColorRect that holds the ShaderMaterial.
# Resolved in _ready so $ColorRect is safe to access (the scene
# tree must be fully built before any child lookups).
@onready var _color_rect: ColorRect = $ColorRect

# Cache the last vignette value pushed to the shader uniform.
# Avoids the (cheap-but-unnecessary) set_shader_parameter call
# when the persisted value hasn't changed since last frame.
# Sentinel value -1.0 guarantees the first frame always pushes
# (real values are in [0.0, 1.0]).
var _last_vignette_intensity: float = -1.0


func _process(_delta: float) -> void:
	# Vignette: shader uniform push (cached).
	if not _color_rect.material is ShaderMaterial:
		return
	var mat: ShaderMaterial = _color_rect.material
	var vignette_intensity: float = VisualSettings.get_vignette_intensity()
	if vignette_intensity != _last_vignette_intensity:
		mat.set_shader_parameter("vignette_intensity", vignette_intensity)
		_last_vignette_intensity = vignette_intensity