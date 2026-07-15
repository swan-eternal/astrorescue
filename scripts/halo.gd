extends Sprite2D
##
## Halo: a soft additive-blended radial gradient rendered as a
## Sprite2D child of a celestial body. World-space → scales
## naturally with camera zoom (the exact thing the screen-space
## bloom attempt failed at — see commit message history for #2807).
##
## Adding a halo to a body:
##   1. Drop a Sprite2D as a child of the body, BEFORE the body's
##      polygon node (so it renders behind the body).
##   2. Attach this script (scripts/halo.gd) to the Sprite2D.
##   3. Tune halo_radius_factor and halo_alpha in the inspector.
##
## Reads the parent's `radius` each frame and rescales — matches
## the pattern where parent's radius can change (level JSON
## overrides the @export default, in-editor tweaks, level editor
## "Live Edit" mode). Cached: only re-applies when something
## actually changed. Cheap (one float compare per frame).
##
## Body-iteration code (soi_indicator, rocket gravity, etc.)
## queries the "attractors" group. Halo is never added to that
## group, so it's invisible to all physics/UI consumers — it's
## a pure visual sibling.
##

# Multiplier on the body's radius for the halo's visible extent.
# Sun: ~3.0 (bold dominant glow). Planets: ~1.2 (subtle
# "planetshine"). Default 2.0 = moderate; tune per-body.
@export var halo_radius_factor: float = 2.0

# Modulate alpha for the halo gradient. Low = subtle additive
# glow; high = blown out toward white. Sun: ~0.22. Planets: ~0.05.
@export var halo_alpha: float = 0.15

# Side length of the procedurally-generated radial-gradient
# texture. 256 looks smooth at any realistic zoom without
# burning VRAM. Bump up only if you see banding in zoom-in.
@export var texture_size: int = 256

# Cached values so we only re-apply when something actually
# changed. Sentinels (-1) guarantee the first reapply fires.
var _last_radius: float = -1.0
var _last_factor: float = -1.0
var _last_alpha: float = -1.0


func _ready() -> void:
	_build_texture()
	_setup_blend_material()
	_reapply()


# Additive blend is set via CanvasItemMaterial (Sprite2D itself has no
# blend_mode property in Godot 4). Set once in _ready; doesn't need
# re-polling because we don't expose it as an @export.
func _setup_blend_material() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func _process(_delta: float) -> void:
	# Poll the parent's radius (level overrides + editor live-edit
	# can change it) and our own @exports (inspector tweaks during
	# playtest). Cheap: only re-applies when something actually
	# changed.
	var parent: Node = get_parent()
	var radius_value: float = float(parent.get("radius"))
	if radius_value != _last_radius or halo_radius_factor != _last_factor or halo_alpha != _last_alpha:
		_reapply()


# Build a circular gradient texture: opaque white at center, fully
# transparent at edge. The "halo" is the soft falloff between
# the two stops — cheap to render, GPU-friendly.
func _build_texture() -> void:
	var tex := GradientTexture2D.new()
	tex.width = texture_size
	tex.height = texture_size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	# fill_to can be any point on the bounding-circle edge; we
	# pick the horizontal middle-right because radial gradient
	# modes only care about the axis.
	tex.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = grad
	texture = tex


# Sprite2D inherits the parent's Transform2D position so it sits
# at the body's center automatically (polygons are centered at
# the body's local origin). Scale is in pixels: with a
# texture_size-wide texture, scale = (radius * factor * 2) /
# texture_size makes the visible extent equal parent.radius *
# halo_radius_factor. Additive blend brightens underlying
# pixels without overwriting them — halo + dark space = glow,
# halo + bright sun core = brightens further (looks washed out,
# which is the desired effect at the body center).
func _reapply() -> void:
	var parent: Node = get_parent()
	var radius_value: float = float(parent.get("radius"))
	_last_radius = radius_value
	_last_factor = halo_radius_factor
	_last_alpha = halo_alpha
	modulate = Color(1, 1, 1, halo_alpha)
	var target_diameter: float = radius_value * halo_radius_factor * 2.0
	var scale_factor: float = target_diameter / float(texture_size)
	scale = Vector2(scale_factor, scale_factor)
	position = Vector2.ZERO
