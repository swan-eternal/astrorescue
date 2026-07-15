extends CanvasLayer
##
## Post-processing layer: applies the vignette + chromatic aberration
## screen-space shader effects to the rendered scene below.
##
## One responsibility per frame:
##   - Vignette: poll VisualSettings.get_vignette_intensity(),
##     push to the ShaderMaterial's `vignette_intensity` uniform.
##     Cached (only pushes on change) — cheap.
##   - Chromatic aberration: poll VisualSettings
##     .get_chromatic_aberration_enabled(), push to the
##     ShaderMaterial's `chromatic_aberration_enabled` uniform.
##     Cached (only pushes on change) — cheap.
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

# Cache the last vignette value pushed to the shader uniform.
# Avoids the (cheap-but-unnecessary) set_shader_parameter call
# when the persisted value hasn't changed since last frame.
# Sentinel value -1.0 guarantees the first frame always pushes
# (real values are in [0.0, 1.0]).
var _last_vignette_intensity: float = -1.0

# Cache the last chromatic_aberration_enabled bool pushed to the
# shader uniform. Sentinel value `false` differs from the default
# (`true`), guaranteeing the first frame always pushes. Subsequent
# frames skip the set_shader_parameter call when the persisted
# value hasn't changed.
var _last_chromatic_aberration_enabled: bool = false


func _process(_delta: float) -> void:
	if not _color_rect.material is ShaderMaterial:
		return
	var mat: ShaderMaterial = _color_rect.material

	# Vignette: shader uniform push (cached).
	var vignette_intensity: float = VisualSettings.get_vignette_intensity()
	if vignette_intensity != _last_vignette_intensity:
		mat.set_shader_parameter("vignette_intensity", vignette_intensity)
		_last_vignette_intensity = vignette_intensity

	# Chromatic aberration: shader uniform push (cached).
	var chromatic_aberration_enabled: bool = VisualSettings.get_chromatic_aberration_enabled()
	if chromatic_aberration_enabled != _last_chromatic_aberration_enabled:
		mat.set_shader_parameter("chromatic_aberration_enabled", chromatic_aberration_enabled)
		_last_chromatic_aberration_enabled = chromatic_aberration_enabled