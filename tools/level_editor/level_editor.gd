extends Control
class_name LevelEditor
##
## Level Editor — graphical tool for authoring Astro-Rescue levels.
##
## Lives in tools/level_editor/ and is excluded from the export preset
## so it doesn't ship with the game.
##
## Architecture: this script builds its UI dynamically in `_ready()`
## from code. The benefit is no fragile .tscn authoring for the shell —
## all layout, controls, and wiring are explicit in GDScript.
##
## **Phase 2 (shell):** minimal UI scaffolding + in-memory bodies[]
## model. Add/Remove buttons work and rebuild the viewport via the
## same `LevelLoader.build_scene_from_spec` the JSON loader uses —
## guarantees a level that previews correctly plays correctly.
##
## **Phase 4 (inspector):** replaced the placeholder Label with a
## real per-body-type inspector. Selecting a body in the list
## rebuilds the inspector with the right fields for that body type
## (sun / planet / asteroid / moon). Every field mutates the spec
## in place and triggers `_refresh_viewport()` for live preview.
## Moons are edited inline in the planet's inspector (since the
## top-level list only shows top-level bodies).
##
## Save / Test Level wired (Phase 6 MVP). Sun is always present and
## non-removable (auto-injected in _ready if missing; _on_remove_selected
## refuses to delete it; the Sun button was dropped from the add grid).
## Matches the physics invariant — orbit math treats origin as the sun,
## and a non-zero visual position would just float the disk while
## planets still orbit (0, 0).
##
## Data flow:
##   UI mutates `spec` (in-memory Dictionary mirroring v3 JSON schema)
##        ↓
##   _refresh_viewport() calls LevelLoader.build_scene_from_spec(spec, root)
##        ↓
##   viewport contents match the current spec
##
## The editor and the game share scene-building code, so orbit math,
## body init order, and physics stay in sync by construction.
##


# --- In-memory data model ---
# Mirrors the v3 JSON schema. Edits via UI panels mutate this in place.
# On every mutation, _refresh_viewport() rebuilds the scene from this dict.
var spec: Dictionary = {
	"name": "New Level",
	"version": 3,
	"bodies": [],
	"rocket": {
		"initial_position": [0.0, 0.0],
		"initial_velocity": [0.0, 50.0],
	},
}


# --- FileDialogs for save + load (built in code, popped up on click) ---
# Both modal: block input until the user picks a path or cancels, then
# return to the editor. Filters to *.json so the suggested extension
# matches the v3 JSON schema. Both open in user://levels/ (lazily
# created on first save by _on_save).
var _save_dialog: FileDialog
var _load_dialog: FileDialog


# --- UI references (created in _ready) ---
var _body_list: ItemList
var _viewport_root: Node2D  # SubViewport's child Node2D
var _inspector: VBoxContainer  # Phase 4: holds the per-body-type editor panel
var _camera: Camera2D  # Phase 5: viewport camera, referenced for pan/zoom input
var _viewport_container: SubViewportContainer  # Phase 5: needed for container-relative screen math (zoom-at-cursor, etc.)


# --- Phase 5 viewport control state + tunables ---
# Middle-click drag (or Space+left-drag) pans; scroll wheel zooms. State
# persists between drags so subsequent drags start from the last camera
# position rather than the press position.
var _is_panning: bool = false
var _pan_start_screen_pos: Vector2 = Vector2.ZERO
var _pan_start_camera_pos: Vector2 = Vector2.ZERO

# Zoom range: small MIN so user can zoom out to see the whole system;
# MAX = 1.0 (1:1 world-to-screen) is more than enough for editing.
# ZOOM_STEP = 1.2 means each wheel notch zooms ~20%.
const MIN_ZOOM: float = 0.001
const MAX_ZOOM: float = 1.0
const ZOOM_STEP: float = 1.2


# --- Inspector field limits (tunable, edit here) ---
# Each Vector3 holds (min, max, step) for one numeric field. The
# field-builder functions reference these constants, so editing
# any of them changes the slider/input range for that field across
# the whole editor. Tune for Astro-Rescue-scale levels: perihelion
# up to ~10000 world units, sun mass up to ~1e8. Widen if you need
# bigger levels; tighten if you want a tighter playable range.
#
# Angle/phase fields have a fixed -180..180 range (see
# _add_slider_with_input_degrees_field) — angles wrap modulo 2π,
# no meaningful tuning there.

# Sun (always present, single per level — high mass range, IS the gravity source)
const SUN_MASS := Vector3(0.0, 1e8, 1000.0)
const SUN_RADIUS := Vector3(1.0, 1000.0, 1.0)

# Planet (main orbit range)
const PLANET_MASS := Vector3(0.0, 1e7, 100.0)
const PLANET_RADIUS := Vector3(1.0, 500.0, 1.0)

# Asteroid (small inner-system bodies)
const ASTEROID_MASS := Vector3(0.0, 1e5, 1.0)
const ASTEROID_RADIUS := Vector3(1.0, 200.0, 1.0)

# Moon (surface-relative to host planet — smaller distances)
const MOON_MASS := Vector3(0.0, 1e5, 1.0)
const MOON_RADIUS := Vector3(1.0, 100.0, 1.0)

# Orbital distance (perihelion / aphelion)
const ORBIT_DISTANCE := Vector3(0.0, 10000.0, 10.0)  # planet + asteroid
const MOON_ORBIT_DISTANCE := Vector3(0.0, 200.0, 1.0)  # moon (surface-relative)

# Orbital speed (negative = retrograde). Covers Astro-Rescue's existing
# JSON values + headroom for experimentation.
const ORBIT_SPEED := Vector3(-10.0, 10.0, 0.01)

# Fuel orbit radius (around host planet for fuel pickup)
const FUEL_ORBIT_RADIUS := Vector3(0.0, 500.0, 1.0)  # planet + asteroid
const MOON_FUEL_ORBIT_RADIUS := Vector3(0.0, 200.0, 1.0)  # moon


## Build the UI, ensure the sun invariant, then render the viewport.
## The sun is always present (auto-injected if missing) and is locked
## against removal — matches the physics invariant (orbit math treats
## origin as the sun) and removes the "two suns" failure mode.
func _ready() -> void:
	if not _has_sun():
		spec.bodies.insert(0, _make_default_sun_spec())
	_build_ui()
	_refresh_viewport()


# --- UI construction ---

## Top-level layout: HSplitContainer (sidebar | viewport) over a bottom
## action bar (Save / Test Level).
func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_vbox)

	var splitter := HSplitContainer.new()
	splitter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(splitter)

	_build_sidebar(splitter)
	_build_viewport(splitter)
	_build_action_bar(root_vbox)


## Left panel: body list + Add/Remove buttons + inspector panel.
## The inspector (Phase 4) is a VBoxContainer rebuilt every time
## selection changes — it's filled with SpinBoxes / CheckBoxes /
## ColorPickerButtons appropriate to the selected body type.
## Wrapped in a ScrollContainer so a tall inspector (planet + moons
## = ~30 fields) scrolls instead of squeezing the body list to zero
## height and making it unclickable.
func _build_sidebar(parent: Container) -> void:
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(280, 0)
	parent.add_child(sidebar)

	sidebar.add_child(_make_label("Bodies", true))

	_body_list = ItemList.new()
	_body_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_list.item_selected.connect(_on_body_selected)
	sidebar.add_child(_body_list)

	sidebar.add_child(HSeparator.new())

	# Add buttons in a 1x3 grid (Planet / Moon / Asteroid). No "Add
	# Sun" — sun is always present (auto-injected in _ready if the
	# spec didn't have one) and non-removable (refused by
	# _on_remove_selected). Matches the physics invariant.
	var add_grid := GridContainer.new()
	add_grid.columns = 3
	sidebar.add_child(add_grid)
	add_grid.add_child(_make_button("Planet", _on_add_planet))
	add_grid.add_child(_make_button("Moon", _on_add_moon))
	add_grid.add_child(_make_button("Asteroid", _on_add_asteroid))

	sidebar.add_child(_make_button("Remove Selected", _on_remove_selected))

	sidebar.add_child(HSeparator.new())

	sidebar.add_child(_make_label("Inspector", true))
	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(inspector_scroll)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.add_child(_make_label("(select a body to edit properties)"))
	inspector_scroll.add_child(_inspector)


## Right panel: SubViewportContainer + SubViewport with a scene tree
## that matches level.tscn (SunContainer + PlanetContainer as named
## children of a Node2D root) so LevelLoader.build_scene_from_spec
## can find them by name.
func _build_viewport(parent: Container) -> void:
	var sv_container := SubViewportContainer.new()
	sv_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv_container.stretch = true  # render to fit container size
	# MOUSE_FILTER_IGNORE lets mouse events on the viewport pass through
	# to _unhandled_input cleanly. Default MOUSE_FILTER_STOP would consume
	# events at the container and could prevent pan/zoom from firing.
	sv_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sv_container)
	_viewport_container = sv_container  # Phase 5: needed for container-relative screen math

	var sub_viewport := SubViewport.new()
	sub_viewport.size = Vector2(800, 600)
	sv_container.add_child(sub_viewport)

	_viewport_root = Node2D.new()
	sub_viewport.add_child(_viewport_root)

	var sun_container := Node2D.new()
	sun_container.name = "SunContainer"
	_viewport_root.add_child(sun_container)

	var planet_container := Node2D.new()
	planet_container.name = "PlanetContainer"
	_viewport_root.add_child(planet_container)

	# Fixed camera at origin, zoomed out so bodies up to ~5000 units
	# from origin fit in view. Phase 5: user-controllable pan (middle-
	# click drag or Space+left-drag) and zoom (scroll wheel). Pan/zoom
	# input handlers live in _unhandled_input below.
	var camera := Camera2D.new()
	camera.position = Vector2.ZERO
	camera.zoom = Vector2(0.05, 0.05)
	_viewport_root.add_child(camera)
	_camera = camera  # save reference for input handlers


## Bottom bar: Load (path picker) / Save (path picker) / Test Level.
func _build_action_bar(parent: Container) -> void:
	var bar := HBoxContainer.new()
	parent.add_child(bar)

	bar.add_child(_make_button("Load", _on_load))
	bar.add_child(_make_button("Save", _on_save))
	bar.add_child(_make_button("Test Level", _on_test_level))
	_build_save_dialog()
	_build_load_dialog()


## Build the FileDialog used by Load. Open mode (vs Save's save mode),
## otherwise structurally identical to _build_save_dialog.
func _build_load_dialog() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_USERDATA
	dialog.current_dir = "user://levels"
	dialog.filters = PackedStringArray(["*.json ; JSON level spec"])
	dialog.file_selected.connect(_on_load_dialog_file_selected)
	add_child(dialog)
	_load_dialog = dialog


## Build the FileDialog used by Save. Popped up on click; the dialog's
## `file_selected` signal fires when the user picks a path, which calls
## _on_save_dialog_file_selected. user:// is the right root for editor
## saves — it's per-user data, writeable in exported builds.
func _build_save_dialog() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_USERDATA
	dialog.current_dir = "user://levels"
	dialog.filters = PackedStringArray(["*.json ; JSON level spec"])
	dialog.file_selected.connect(_on_save_dialog_file_selected)
	add_child(dialog)
	_save_dialog = dialog


# --- UI helpers ---

func _make_label(text: String, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	if bold:
		label.add_theme_font_size_override("font_size", 16)
	return label


func _make_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	return btn


# --- Body list refresh + selection ---

## Rebuild the body list from `spec.bodies`. Preserves the selection
## (so editing a planet's name doesn't deselect it) and re-fires the
## selection handler so the inspector also refreshes.
func _refresh_body_list() -> void:
	var previous := _body_list.get_selected_items()
	var prev_index: int = previous[0] if previous.size() > 0 else -1
	_body_list.clear()
	for i in range(spec.bodies.size()):
		var body: Dictionary = spec.bodies[i]
		_body_list.add_item(_body_label_for(body, i), null)
	if prev_index >= 0 and prev_index < spec.bodies.size():
		_body_list.select(prev_index)
		# item_selected may not fire on programmatic select; call
		# manually so the inspector reflects the new label data.
		_on_body_selected(prev_index)


## Human-readable label for a body in the list. Used to show type,
## name (if any), and moon count (for planets).
func _body_label_for(body: Dictionary, index: int) -> String:
	var type: String = body.get("type", "?")
	var name: String = body.get("name", "")
	match type:
		"sun":
			# No "locked" indicator — sun is always present by design,
			# and the user will figure that out from the body list
			# always containing exactly one Sun (Jason's preference
			# after e7ae08c's locked-label was deemed too utilitarian).
			return "Sun (mass %.0f)" % float(body.get("mass", 0))
		"planet":
			var moons_count: int = body.get("moons", []).size()
			var moons_suffix: String = ""
			if moons_count > 0:
				moons_suffix = " + %d moon%s" % [moons_count, "s" if moons_count != 1 else ""]
			var label_name: String = name if name else "#%d" % (index + 1)
			return "Planet: %s%s" % [label_name, moons_suffix]
		"moon":
			# Moons don't appear at the top level in v3 — they're inside
			# their host planet's moons[]. This branch is defensive in
			# case a stray moon entry slips in.
			return "  ↳ Moon (parent: %s)" % body.get("host_planet", "?")
		"asteroid":
			return "Asteroid #%d" % (index + 1)
		_:
			return "%s #%d" % [type, index + 1]


## Selection changed in the body list. Rebuild the inspector to show
## the right fields for the new selection (or the empty state).
func _on_body_selected(index: int) -> void:
	if index < 0 or index >= spec.bodies.size():
		_rebuild_inspector_empty()
		return
	var body: Dictionary = spec.bodies[index]
	_rebuild_inspector_for(body, index)


# --- Inspector rebuild (Phase 4) ---

## Inspector contents are fully torn down and rebuilt whenever the
## selection changes. Simpler than dynamic show/hide of individual
## controls, and fast enough for a one-at-a-time editor panel.
## Old children are queue_free'd (safe for in-tree nodes); new ones
## take their place immediately.

func _rebuild_inspector_empty() -> void:
	_clear_inspector()
	_inspector.add_child(_make_label("(select a body to edit properties)"))


func _rebuild_inspector_for(body: Dictionary, index: int) -> void:
	_clear_inspector()
	var type: String = body.get("type", "?")
	_inspector.add_child(_make_label(type.capitalize(), true))
	match type:
		"sun":
			_build_sun_fields(body, index)
		"planet":
			_build_planet_fields(body, index)
		"asteroid":
			_build_asteroid_fields(body, index)
		_:
			_inspector.add_child(_make_label("(unknown body type: %s)" % type))


func _clear_inspector() -> void:
	for c in _inspector.get_children():
		c.queue_free()


# --- Inspector field builders (one per body type) ---
# Each helper adds rows directly into _inspector. Every field helper
# closes over `body` (a Dictionary — reference type, so mutations to
# body[key] = v write through to spec.bodies[index]). After every
# mutation, _refresh_viewport() rebuilds the live preview so the user
# sees their changes immediately.

func _build_sun_fields(body: Dictionary, _index: int) -> void:
	_add_slider_with_input_field("Mass", body, "mass", SUN_MASS.x, SUN_MASS.y, SUN_MASS.z)
	_add_slider_with_input_field("Radius", body, "radius", SUN_RADIUS.x, SUN_RADIUS.y, SUN_RADIUS.z)
	_add_check_box_field("Landable", body, "is_landable")
	# No position field — the sun is locked to (0, 0). Orbit math
	# treats origin as the sun, so a non-zero visual position would
	# just float the disk while planets still orbit (0, 0). Loader
	# forces Vector2.ZERO regardless of spec.


func _build_planet_fields(body: Dictionary, _index: int) -> void:
	_add_line_edit_field("Name", body, "name")
	_add_check_box_field("Home", body, "is_home")
	_add_check_box_field("Has Astronaut", body, "has_astronaut")
	_add_check_box_field("Has Fuel", body, "has_fuel")
	_add_slider_with_input_field("Mass", body, "mass", PLANET_MASS.x, PLANET_MASS.y, PLANET_MASS.z)
	_add_slider_with_input_field("Radius", body, "radius", PLANET_RADIUS.x, PLANET_RADIUS.y, PLANET_RADIUS.z)
	_add_color_picker_field(body, "color")
	_add_slider_with_input_field("Perihelion", body, "perihelion", ORBIT_DISTANCE.x, ORBIT_DISTANCE.y, ORBIT_DISTANCE.z)
	_add_slider_with_input_field("Aphelion", body, "aphelion", ORBIT_DISTANCE.x, ORBIT_DISTANCE.y, ORBIT_DISTANCE.z)
	_add_slider_with_input_degrees_field("Angle of Aphelion", body, "angle_of_aphelion")
	_add_slider_with_input_degrees_field("Phase", body, "phase")
	_add_slider_with_input_field("Fuel Orbit Radius", body, "fuel_orbit_radius", FUEL_ORBIT_RADIUS.x, FUEL_ORBIT_RADIUS.y, FUEL_ORBIT_RADIUS.z)
	_add_slider_with_input_field("Fuel Orbit Speed", body, "fuel_orbit_speed", ORBIT_SPEED.x, ORBIT_SPEED.y, ORBIT_SPEED.z)
	_add_moons_section(body)


func _build_asteroid_fields(body: Dictionary, _index: int) -> void:
	_add_slider_with_input_field("Mass", body, "mass", ASTEROID_MASS.x, ASTEROID_MASS.y, ASTEROID_MASS.z)
	_add_slider_with_input_field("Radius", body, "radius", ASTEROID_RADIUS.x, ASTEROID_RADIUS.y, ASTEROID_RADIUS.z)
	_add_color_picker_field(body, "color")
	_add_check_box_field("Landable", body, "is_landable")
	_add_check_box_field("Has Fuel", body, "has_fuel")
	_add_slider_with_input_field("Fuel Orbit Radius", body, "fuel_orbit_radius", FUEL_ORBIT_RADIUS.x, FUEL_ORBIT_RADIUS.y, FUEL_ORBIT_RADIUS.z)
	_add_slider_with_input_field("Fuel Orbit Speed", body, "fuel_orbit_speed", ORBIT_SPEED.x, ORBIT_SPEED.y, ORBIT_SPEED.z)
	_add_slider_with_input_field("Perihelion", body, "perihelion", ORBIT_DISTANCE.x, ORBIT_DISTANCE.y, ORBIT_DISTANCE.z)
	_add_slider_with_input_field("Aphelion", body, "aphelion", ORBIT_DISTANCE.x, ORBIT_DISTANCE.y, ORBIT_DISTANCE.z)
	_add_slider_with_input_degrees_field("Angle of Aphelion", body, "angle_of_aphelion")
	_add_slider_with_input_degrees_field("Phase", body, "phase")


# --- Inspector field helpers (generic) ---
# All helpers take a `body` Dictionary and a `key` String. Mutations
# happen in place on the dict — the dict is the same reference held
# by spec.bodies[index], so the change persists. _refresh_viewport()
# rebuilds the live preview from the (now-updated) spec.

## Numeric field with slider + input combo: VBox [Label] [HBox [HSlider] [SpinBox]].
## HSlider for exploration ("drag right to make bigger"); SpinBox for precise
## entry. Both edit the same value bidirectionally — set_block_signals during
## sync prevents the other control's value_changed from re-firing our handler.
## Layout: label on top, slider + SpinBox in their own HBox below — slider
## takes the full sidebar width (~260px), SpinBox fixed at 80px on the right.
## Stacked layout costs ~2× vertical space per field but ScrollContainer
## (set up in _build_sidebar) handles the overflow. Use for any "feel"
## numeric (radius, mass, orbital distance, fuel_*). For boolean/color/string/
## vec2, use the other helpers — sliders don't apply.
func _add_slider_with_input_field(label_text: String, body: Dictionary, key: String, min_v: float, max_v: float, step: float) -> void:
	var vbox := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	vbox.add_child(label)
	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)
	var initial_value: float = float(body.get(key, 0.0))
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = initial_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 24)
	hbox.add_child(slider)
	var sb := SpinBox.new()
	sb.min_value = min_v
	sb.max_value = max_v
	sb.step = step
	sb.value = initial_value
	sb.custom_minimum_size = Vector2(80, 0)
	sb.value_changed.connect(func(v: float):
		body[key] = v
		slider.set_block_signals(true)
		slider.value = v
		slider.set_block_signals(false)
		_refresh_viewport()
	)
	hbox.add_child(sb)
	slider.value_changed.connect(func(v: float):
		body[key] = v
		sb.set_block_signals(true)
		sb.value = v
		sb.set_block_signals(false)
		_refresh_viewport()
	)
	_inspector.add_child(vbox)


## Angle field with slider + input combo: same as _add_slider_with_input_field
## but displays / accepts DEGREES in the UI while the spec stores RADIANS
## (matches what OrbitCalculator and planet / moon / asteroid scripts consume).
## Range clamped to [-180, 180] since angles wrap modulo 2π.
func _add_slider_with_input_degrees_field(label_text: String, body: Dictionary, key: String) -> void:
	var vbox := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	vbox.add_child(label)
	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)
	var initial_deg: float = float(body.get(key, 0.0)) * 180.0 / PI
	var slider := HSlider.new()
	slider.min_value = -180.0
	slider.max_value = 180.0
	slider.step = 1.0
	slider.value = initial_deg
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 24)
	hbox.add_child(slider)
	var sb := SpinBox.new()
	sb.min_value = -180.0
	sb.max_value = 180.0
	sb.step = 1.0
	sb.suffix = "°"
	sb.value = initial_deg
	sb.custom_minimum_size = Vector2(80, 0)
	sb.value_changed.connect(func(v: float):
		body[key] = v * PI / 180.0
		slider.set_block_signals(true)
		slider.value = v
		slider.set_block_signals(false)
		_refresh_viewport()
	)
	hbox.add_child(sb)
	slider.value_changed.connect(func(v: float):
		body[key] = v * PI / 180.0
		sb.set_block_signals(true)
		sb.value = v
		sb.set_block_signals(false)
		_refresh_viewport()
	)
	_inspector.add_child(vbox)


## Boolean field: standalone CheckBox with a label.
func _add_check_box_field(label_text: String, body: Dictionary, key: String) -> void:
	var cb := CheckBox.new()
	cb.text = label_text
	cb.button_pressed = bool(body.get(key, false))
	cb.toggled.connect(func(pressed: bool):
		body[key] = pressed
		_refresh_viewport()
	)
	_inspector.add_child(cb)


## Color field: HBox [Label] [ColorPickerButton]. Color is stored as
## an Array [r, g, b, a] in the spec (matches v3 JSON shape). On any
## color change, we write the full array back so length is consistent.
func _add_color_picker_field(body: Dictionary, key: String) -> void:
	var hbox := HBoxContainer.new()
	var label := Label.new()
	label.text = key.capitalize().replace("_", " ")
	label.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(label)
	var cp := ColorPickerButton.new()
	var arr: Array = body.get(key, [1.0, 1.0, 1.0, 1.0])
	var a: float = arr[3] if arr.size() > 3 else 1.0
	cp.color = Color(arr[0], arr[1], arr[2], a)
	cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cp.color_changed.connect(func(c: Color):
		body[key] = [c.r, c.g, c.b, c.a]
		_refresh_viewport()
	)
	hbox.add_child(cp)
	_inspector.add_child(hbox)


## String field: HBox [Label] [LineEdit]. Fires on text_submitted
## (Enter key) — debouncing for free. Also refreshes the body list
## so the new name shows in the label without a manual click.
func _add_line_edit_field(label_text: String, body: Dictionary, key: String) -> void:
	var hbox := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(label)
	var le := LineEdit.new()
	le.text = String(body.get(key, ""))
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_submitted.connect(func(t: String):
		body[key] = t
		_refresh_body_list()  # name appears in the list label
		_refresh_viewport()
	)
	hbox.add_child(le)
	_inspector.add_child(hbox)


## Vector2 field: HBox [Label] [SpinBox x] [SpinBox y]. Both spin
## boxes read the current array from `body` on every change so they
## stay in sync if the spec is mutated externally.
func _add_vec2_field(label_text: String, body: Dictionary, key: String) -> void:
	var hbox := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(label)
	var pos: Array = body.get(key, [0.0, 0.0])
	var sb_x := SpinBox.new()
	sb_x.min_value = -10000.0
	sb_x.max_value = 10000.0
	sb_x.step = 1.0
	sb_x.value = pos[0] if pos.size() > 0 else 0.0
	sb_x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb_x.prefix = "x"
	sb_x.value_changed.connect(func(v: float):
		var current: Array = body.get(key, [0.0, 0.0])
		current[0] = v
		body[key] = current
		_refresh_viewport()
	)
	hbox.add_child(sb_x)
	var sb_y := SpinBox.new()
	sb_y.min_value = -10000.0
	sb_y.max_value = 10000.0
	sb_y.step = 1.0
	sb_y.value = pos[1] if pos.size() > 1 else 0.0
	sb_y.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb_y.prefix = "y"
	sb_y.value_changed.connect(func(v: float):
		var current: Array = body.get(key, [0.0, 0.0])
		current[1] = v
		body[key] = current
		_refresh_viewport()
	)
	hbox.add_child(sb_y)
	_inspector.add_child(hbox)


# --- Moons sub-section (inside planet inspector) ---
# Moons are stored in planet["moons"] as a nested array of plain
# dicts (no "type" key — the loader identifies them by being nested).
# Editing happens inline; add/remove buttons live here so the user
# doesn't have to bounce back to the top toolbar.

func _add_moons_section(planet_body: Dictionary) -> void:
	_inspector.add_child(HSeparator.new())
	_inspector.add_child(_make_label("Moons", true))
	var moons: Array = planet_body.get("moons", [])
	if moons.is_empty():
		_inspector.add_child(_make_label("(no moons — click Add Moon below)"))
	else:
		for i in range(moons.size()):
			_add_moon_editor(planet_body, i)
	_add_add_moon_button(planet_body)


func _add_moon_editor(planet_body: Dictionary, moon_index: int) -> void:
	var moon: Dictionary = planet_body["moons"][moon_index]
	var header := HBoxContainer.new()
	var label := Label.new()
	label.text = "  ↳ Moon %d" % (moon_index + 1)
	label.custom_minimum_size = Vector2(120, 0)
	header.add_child(label)
	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(func() -> void:
		planet_body["moons"].remove_at(moon_index)
		_refresh_body_list()
		_refresh_viewport()
		_rebuild_inspector_for(planet_body, -1)  # refresh this inspector panel
	)
	header.add_child(remove_btn)
	_inspector.add_child(header)
	# Moon fields — match scripts/level_loader.gd `_instantiate_planet_moon`.
	_add_slider_with_input_field("Radius", moon, "radius", MOON_RADIUS.x, MOON_RADIUS.y, MOON_RADIUS.z)
	_add_color_picker_field(moon, "color")
	_add_check_box_field("Landable", moon, "is_landable")
	_add_check_box_field("Has Astronaut", moon, "has_astronaut")
	_add_check_box_field("Has Fuel", moon, "has_fuel")
	_add_slider_with_input_field("Mass", moon, "mass", MOON_MASS.x, MOON_MASS.y, MOON_MASS.z)
	_add_slider_with_input_field("Perihelion", moon, "perihelion", MOON_ORBIT_DISTANCE.x, MOON_ORBIT_DISTANCE.y, MOON_ORBIT_DISTANCE.z)
	_add_slider_with_input_field("Aphelion", moon, "aphelion", MOON_ORBIT_DISTANCE.x, MOON_ORBIT_DISTANCE.y, MOON_ORBIT_DISTANCE.z)
	_add_slider_with_input_degrees_field("Angle of Aphelion", moon, "angle_of_aphelion")
	_add_slider_with_input_degrees_field("Phase", moon, "phase")
	_add_slider_with_input_field("Fuel Orbit Radius", moon, "fuel_orbit_radius", MOON_FUEL_ORBIT_RADIUS.x, MOON_FUEL_ORBIT_RADIUS.y, MOON_FUEL_ORBIT_RADIUS.z)
	_add_slider_with_input_field("Fuel Orbit Speed", moon, "fuel_orbit_speed", ORBIT_SPEED.x, ORBIT_SPEED.y, ORBIT_SPEED.z)


func _add_add_moon_button(planet_body: Dictionary) -> void:
	var btn := Button.new()
	btn.text = "Add Moon"
	btn.pressed.connect(func() -> void:
		if not planet_body.has("moons"):
			planet_body["moons"] = []
		planet_body["moons"].append(_make_default_moon_spec())
		_refresh_body_list()  # updates "Planet: X + N moon(s)" label
		_refresh_viewport()
		_rebuild_inspector_for(planet_body, -1)  # refresh inspector to show new moon
	)
	_inspector.add_child(btn)


# --- Add / Remove handlers ---
# Sun has no add handler — it's auto-injected in _ready if missing
# and locked against removal. See _on_remove_selected for the refusal.


func _on_add_planet() -> void:
	spec.bodies.append(_make_default_planet_spec())
	_refresh_body_list()
	_refresh_viewport()
	_select_last_body()


func _on_add_moon() -> void:
	# Top-level toolbar Add Moon (in addition to the inline button in
	# the planet inspector). Both paths use the same default spec.
	var planet_spec: Variant = _get_selected_planet_spec()
	if planet_spec == null:
		_inspector_placeholder_warn("Select a planet in the list first, then click Add Moon.")
		return
	var planet_dict: Dictionary = planet_spec
	if not planet_dict.has("moons"):
		planet_dict["moons"] = []
	planet_dict["moons"].append(_make_default_moon_spec())
	_refresh_body_list()
	_refresh_viewport()
	# Refresh the inspector to show the new moon (it was built for
	# the planet, but moon editors are added by _add_moons_section).
	_rebuild_inspector_for(planet_dict, -1)


func _on_add_asteroid() -> void:
	spec.bodies.append(_make_default_asteroid_spec())
	_refresh_body_list()
	_refresh_viewport()
	_select_last_body()


## Remove the selected body. Refuses to remove the sun — orbit math
## treats origin as the sun, and the editor enforces the "exactly one
## sun per level" invariant (auto-injected in _ready if missing). The
## body_label_for text mentions "locked" so the user has a hint.
func _on_remove_selected() -> void:
	var selected := _body_list.get_selected_items()
	if selected.is_empty():
		return
	var i: int = selected[0]
	if i >= spec.bodies.size():
		return
	if spec.bodies[i].get("type") == "sun":
		return  # locked — see docstring
	spec.bodies.remove_at(i)
	_refresh_body_list()
	_refresh_viewport()


## Helper: surface a warning message in the inspector without
## needing to know the current selection. Replaces the inspector
## contents temporarily — selection handlers rebuild it on next click.
func _inspector_placeholder_warn(msg: String) -> void:
	_clear_inspector()
	_inspector.add_child(_make_label(msg))


## Helper: select the most recently added body so its inspector
## panel appears immediately. Used by the Add * handlers.
func _select_last_body() -> void:
	var i: int = spec.bodies.size() - 1
	if i < 0:
		return
	_body_list.select(i)
	_on_body_selected(i)


## Helper: return the currently selected body's spec if it's a planet,
## else null. Used by Add Moon to know where to nest the new moon.
## Returns Variant (nullable) — no planet selected / not a planet / OOB
## all yield null. Caller in _on_add_moon() handles each case.
func _get_selected_planet_spec() -> Variant:
	var selected := _body_list.get_selected_items()
	if selected.is_empty():
		return null
	var i: int = selected[0]
	if i >= spec.bodies.size():
		return null
	var body: Dictionary = spec.bodies[i]
	if body.get("type") != "planet":
		return null
	return body


# --- Viewport refresh ---

func _refresh_viewport() -> void:
	# Clear + rebuild via the same path the JSON loader uses. The
	# editor and the game share scene-building code → no math drift.
	LevelLoader.build_scene_from_spec(spec, _viewport_root)


# --- Phase 5: viewport camera control ---
# Scroll wheel zooms (centered on the cursor — world point under the
# mouse stays under the mouse across zoom levels). Plain left-click
# drag pans. We deliberately don't use middle-click as the primary:
# trackpads don't have it, and the discoverability cost outweighs
# avoiding ambiguity with future "click body to select in viewport"
# features (which we'd handle with a dedicated click vs. drag threshold
# when they exist).
#
# **Uses _input, not _unhandled_input.** _unhandled_input fires AFTER
# GUI processing, which meant left-click events on the SubViewport were
# getting forwarded to the SubViewport's world (and marked handled)
# before reaching our handler. Wheel events weren't forwarded, which
# is why zoom worked but pan didn't — looked identical in code but
# had different event delivery. _input fires earlier and bypasses
# that. The viewport-rect check below keeps us from hijacking clicks
# meant for sidebar buttons / body list / inspector.

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	# Only handle events over the viewport area — clicks/drags in the
	# sidebar (body list, buttons, inspector) shouldn't pan/zoom.
	var screen_pos: Vector2 = (event as InputEventMouse).position
	var viewport_rect := Rect2(_viewport_container.global_position, _viewport_container.size)
	if not viewport_rect.has_point(screen_pos):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at_screen_pos(mb.position, ZOOM_STEP)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at_screen_pos(mb.position, 1.0 / ZOOM_STEP)
					get_viewport().set_input_as_handled()
			MOUSE_BUTTON_LEFT:
				# Plain left-click drag = pan. No modifier needed.
				_set_panning(mb.pressed, mb.position)
	elif event is InputEventMouseMotion and _is_panning:
		var mm := event as InputEventMouseMotion
		# Camera moves OPPOSITE to cursor so the world appears to follow
		# the drag (the standard Blender/Photoshop convention).
		var delta: Vector2 = mm.position - _pan_start_screen_pos
		_camera.position = _pan_start_camera_pos - delta / _camera.zoom


## Start or end a pan gesture. Captures the start screen pos + camera
## pos on press so the gesture is anchored (no jump when you start
## dragging from a non-origin camera position).
func _set_panning(pressed: bool, screen_pos: Vector2) -> void:
	_is_panning = pressed
	if _is_panning:
		_pan_start_screen_pos = screen_pos
		_pan_start_camera_pos = _camera.position
	get_viewport().set_input_as_handled()


## Zoom the camera by `factor` (1.2 ≈ +20% per wheel notch) while
## keeping the world point under `screen_pos` fixed under the cursor.
## Without this, zooming moves the view away from where the user is
## looking. Clamped to [MIN_ZOOM, MAX_ZOOM] so the camera can't zoom
## out to a black void or zoom in past useful detail.
##
## **Critical:** the offset is computed relative to the
## SubViewportContainer's center, NOT the window center. The container
## is offset within the editor sidebar layout; assuming window-center
## causes every zoom to drift the view toward the window's true
## center, not the cursor.
func _zoom_at_screen_pos(screen_pos: Vector2, factor: float) -> void:
	var old_zoom: Vector2 = _camera.zoom
	var new_zoom: Vector2 = (old_zoom * factor).clamp(
		Vector2(MIN_ZOOM, MIN_ZOOM), Vector2(MAX_ZOOM, MAX_ZOOM))
	if new_zoom == old_zoom:
		return  # hit clamp, nothing to do
	# Container-relative offset: where the mouse is inside the viewport
	# area, measured from the container's center (the camera's screen
	# origin in world coords).
	var offset: Vector2 = (screen_pos - _viewport_container.global_position
		- _viewport_container.size / 2.0)
	_camera.position += offset / old_zoom - offset / new_zoom
	_camera.zoom = new_zoom


# --- Default spec templates (Phase 4: include all loader-known fields) ---
# These produce reasonable starter values so the bodies are visible
# without overlapping each other. The inspector lets users tune them.
# All fields below are read by scripts/level_loader.gd for the
# corresponding body type — adding a loader-known field here keeps
# newly-added bodies fully configurable from the editor.

func _make_default_sun_spec() -> Dictionary:
	return {
		"type": "sun",
		"mass": 4_000_000.0,
		"radius": 200.0,
		"is_landable": false,
		"position": [0.0, 0.0],  # visual only — orbital math uses origin
	}


func _make_default_planet_spec() -> Dictionary:
	# Spread new planets across the orbit range so they don't all stack
	# at perihelion 1000. Each new planet goes ~800 units further out.
	var existing_count: int = 0
	for body in spec.bodies:
		if body.get("type") == "planet":
			existing_count += 1
	var base_radius: float = 1500.0 + float(existing_count) * 800.0
	return {
		"type": "planet",
		"name": "planet%d" % (existing_count + 1),
		"is_home": false,
		"has_astronaut": false,
		"has_fuel": false,
		"mass": 1000.0,
		"radius": 30.0,
		"color": [0.5, 0.5, 0.5, 1.0],
		"perihelion": base_radius,
		"aphelion": base_radius,
		"angle_of_aphelion": 0.0,
		"phase": 0.0,
		"fuel_orbit_radius": 50.0,
		"fuel_orbit_speed": 0.5,
		"moons": [],
	}


func _make_default_moon_spec() -> Dictionary:
	# Perihelion/aphelion are surface-relative to the host planet
	# (the moon script adds host_radius internally — see moon.gd).
	return {
		"radius": 6.0,
		"color": [0.7, 0.7, 0.8, 1.0],
		"perihelion": 20.0,
		"aphelion": 30.0,
		"angle_of_aphelion": 0.0,
		"phase": 0.0,
		"is_landable": true,
		"mass": 10.0,
		"has_astronaut": false,
		"has_fuel": false,
		"fuel_orbit_radius": 8.0,
		"fuel_orbit_speed": 0.5,
	}


func _make_default_asteroid_spec() -> Dictionary:
	var existing_count: int = 0
	for body in spec.bodies:
		if body.get("type") == "asteroid":
			existing_count += 1
	var base_radius: float = 2000.0 + float(existing_count) * 300.0
	return {
		"type": "asteroid",
		"mass": 0.0,
		"radius": 8.0,
		"color": [0.5, 0.4, 0.3, 1.0],
		"perihelion": base_radius,
		"aphelion": base_radius,
		"angle_of_aphelion": 0.0,
		"phase": 0.0,
		"is_landable": false,
		"has_fuel": false,
		"fuel_orbit_radius": 12.0,
		"fuel_orbit_speed": 0.3,
	}


# --- Save / Load / Test Level (Phase 6) ---
# Save opens a FileDialog (built in _build_save_dialog) so the user
# picks the path/name. No "Save As" — with no per-edit tracked path
# the distinction didn't add value (Jason's feedback after 38ee7ee).
# Load opens a FileDialog in OPEN_FILE mode, parses the JSON, replaces
# the in-memory spec, and refreshes the body list / viewport / inspector.
# Test Level pushes the in-memory spec into SaveState.test_spec and
# changes scene to level.tscn — the loader checks that field before
# JSON and uses the editor's spec as the source of truth.

## Save click: open the path-picker dialog (defaults to user://levels/).
func _on_save() -> void:
	# Lazily create the directory so the dialog has somewhere to land.
	if not DirAccess.dir_exists_absolute("user://levels"):
		DirAccess.make_dir_recursive_absolute("user://levels")
	_save_dialog.popup_centered_ratio(0.6)


## FileDialog callback: write the spec to the chosen path. 2-space
## indent matches the existing data/levels/level_NN.json files. Creates
## the parent directory if missing (FileDialog may show nested paths
## the user navigated to).
func _on_save_dialog_file_selected(path: String) -> void:
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mk_err := DirAccess.make_dir_recursive_absolute(dir_path)
		if mk_err != OK:
			push_error("LevelEditor: failed to create %s (err %d)" % [dir_path, mk_err])
			return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("LevelEditor: failed to open %s for writing (err %d)" % [path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(spec, "  "))
	file.close()
	print("LevelEditor: saved to %s" % path)


## Load click: open the file-picker dialog.
func _on_load() -> void:
	if not DirAccess.dir_exists_absolute("user://levels"):
		DirAccess.make_dir_recursive_absolute("user://levels")
	_load_dialog.popup_centered_ratio(0.6)


## FileDialog callback: read+parse the chosen file, replace the
## in-memory spec, and refresh. Rejects files with the wrong schema
## version (only v3 supported). Auto-injects a sun if the file didn't
## have one (forgiving — matches the editor's invariant).
##
## Replacing spec mid-session means any SpinBox in the inspector that
## held a closure-captured reference to an OLD body dict now points
## at a stale dict. _refresh_body_list handles this by re-selecting
## (which triggers _rebuild_inspector with the NEW spec's body), and
## the explicit empty-inspector check below handles the case where
## the new spec has fewer bodies than the old one (selection lost).
func _on_load_dialog_file_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("LevelEditor: failed to open %s (err %d)" % [path, FileAccess.get_open_error()])
		return
	var json_text := file.get_as_text()
	file.close()
	var data: Variant = JSON.parse_string(json_text)
	if not data is Dictionary:
		push_error("LevelEditor: failed to parse JSON in %s" % path)
		return
	var version: int = (data as Dictionary).get("version", 0)
	if version != 3:
		push_error("LevelEditor: unsupported schema version %d in %s (expected 3)" % [version, path])
		return
	spec = data
	if not _has_sun():
		spec.bodies.insert(0, _make_default_sun_spec())
	_refresh_body_list()
	# If the old selection is now out of bounds for the new spec, the
	# inspector keeps showing stale content. Clear it explicitly.
	if _body_list.get_selected_items().is_empty():
		_rebuild_inspector_empty()
	_refresh_viewport()
	print("LevelEditor: loaded %s" % path)


## Helper: does the current spec contain at least one sun? Used by
## _ready and _on_load_dialog_file_selected to enforce the invariant
## that every level has exactly one sun.
func _has_sun() -> bool:
	for body in spec.bodies:
		if body.get("type") == "sun":
			return true
	return false


## "Play what I just made" — push the editor's spec into SaveState
## and change to the actual game scene. The loader checks
## SaveState.test_spec before reading JSON, so the editor's in-memory
## spec is the source of truth. Loader consumes the field (sets back
## to {}) so subsequent scene loads (e.g., winning the test and then
## Next Level) fall back to JSON.
func _on_test_level() -> void:
	SaveState.test_spec = spec
	get_tree().change_scene_to_file("res://scenes/level.tscn")
