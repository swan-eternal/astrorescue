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
## Save / Save As / Test Level remain stubs (Phase 6).
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


# --- UI references (created in _ready) ---
var _body_list: ItemList
var _viewport_root: Node2D  # SubViewport's child Node2D
var _inspector: VBoxContainer  # Phase 4: holds the per-body-type editor panel


## Build the UI, then render the initial (empty) viewport.
func _ready() -> void:
	_build_ui()
	_refresh_viewport()


# --- UI construction ---

## Top-level layout: HSplitContainer (sidebar | viewport) over a bottom
## action bar (Save / Save As / Test Level).
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

	# Add buttons in a 2x2 grid so all four body types fit at 280px wide.
	var add_grid := GridContainer.new()
	add_grid.columns = 2
	sidebar.add_child(add_grid)
	add_grid.add_child(_make_button("Sun", _on_add_sun))
	add_grid.add_child(_make_button("Planet", _on_add_planet))
	add_grid.add_child(_make_button("Moon", _on_add_moon))
	add_grid.add_child(_make_button("Asteroid", _on_add_asteroid))

	sidebar.add_child(_make_button("Remove Selected", _on_remove_selected))

	sidebar.add_child(HSeparator.new())

	sidebar.add_child(_make_label("Inspector", true))
	_inspector = VBoxContainer.new()
	_inspector.add_child(_make_label("(select a body to edit properties)"))
	sidebar.add_child(_inspector)


## Right panel: SubViewportContainer + SubViewport with a scene tree
## that matches level.tscn (SunContainer + PlanetContainer as named
## children of a Node2D root) so LevelLoader.build_scene_from_spec
## can find them by name.
func _build_viewport(parent: Container) -> void:
	var sv_container := SubViewportContainer.new()
	sv_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv_container.stretch = true  # render to fit container size
	parent.add_child(sv_container)

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
	# from origin fit in view. Phase 5 will add user-controllable pan
	# and zoom.
	var camera := Camera2D.new()
	camera.position = Vector2.ZERO
	camera.zoom = Vector2(0.05, 0.05)
	_viewport_root.add_child(camera)


## Bottom bar: Save / Save As / Test Level. All stubs for Phase 2/6.
func _build_action_bar(parent: Container) -> void:
	var bar := HBoxContainer.new()
	parent.add_child(bar)

	bar.add_child(_make_button("Save", _on_save))
	bar.add_child(_make_button("Save As...", _on_save_as))
	bar.add_child(_make_button("Test Level", _on_test_level))


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
	_add_spin_box_field("Mass", body, "mass", 0.0, 1e8, 1000.0)
	_add_spin_box_field("Radius", body, "radius", 1.0, 1000.0, 1.0)
	_add_check_box_field("Landable", body, "is_landable")
	_add_vec2_field("Position", body, "position")


func _build_planet_fields(body: Dictionary, _index: int) -> void:
	_add_line_edit_field("Name", body, "name")
	_add_check_box_field("Home", body, "is_home")
	_add_check_box_field("Has Astronaut", body, "has_astronaut")
	_add_check_box_field("Has Fuel", body, "has_fuel")
	_add_spin_box_field("Mass", body, "mass", 0.0, 1e7, 100.0)
	_add_spin_box_field("Radius", body, "radius", 1.0, 500.0, 1.0)
	_add_color_picker_field(body, "color")
	_add_spin_box_field("Perihelion", body, "perihelion", 0.0, 10000.0, 10.0)
	_add_spin_box_field("Aphelion", body, "aphelion", 0.0, 10000.0, 10.0)
	_add_spin_box_field("Angle of Aphelion", body, "angle_of_aphelion", -PI, PI, 0.01)
	_add_spin_box_field("Phase", body, "phase", -PI, PI, 0.01)
	_add_spin_box_field("Fuel Orbit Radius", body, "fuel_orbit_radius", 0.0, 500.0, 1.0)
	_add_spin_box_field("Fuel Orbit Speed", body, "fuel_orbit_speed", -10.0, 10.0, 0.01)
	_add_moons_section(body)


func _build_asteroid_fields(body: Dictionary, _index: int) -> void:
	_add_spin_box_field("Mass", body, "mass", 0.0, 1e5, 1.0)
	_add_spin_box_field("Radius", body, "radius", 1.0, 200.0, 1.0)
	_add_color_picker_field(body, "color")
	_add_check_box_field("Landable", body, "is_landable")
	_add_check_box_field("Has Fuel", body, "has_fuel")
	_add_spin_box_field("Fuel Orbit Radius", body, "fuel_orbit_radius", 0.0, 500.0, 1.0)
	_add_spin_box_field("Fuel Orbit Speed", body, "fuel_orbit_speed", -10.0, 10.0, 0.01)
	_add_spin_box_field("Perihelion", body, "perihelion", 0.0, 10000.0, 10.0)
	_add_spin_box_field("Aphelion", body, "aphelion", 0.0, 10000.0, 10.0)
	_add_spin_box_field("Angle of Aphelion", body, "angle_of_aphelion", -PI, PI, 0.01)
	_add_spin_box_field("Phase", body, "phase", -PI, PI, 0.01)


# --- Inspector field helpers (generic) ---
# All helpers take a `body` Dictionary and a `key` String. Mutations
# happen in place on the dict — the dict is the same reference held
# by spec.bodies[index], so the change persists. _refresh_viewport()
# rebuilds the live preview from the (now-updated) spec.

## Numeric field: HBox [Label "Mass"] [SpinBox]. SpinBox emits
## value_changed on every arrow click and on every typed-value commit,
## so a drag fires many rebuilds. Fast enough for small scenes.
func _add_spin_box_field(label_text: String, body: Dictionary, key: String, min_v: float, max_v: float, step: float) -> void:
	var hbox := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	hbox.add_child(label)
	var sb := SpinBox.new()
	sb.min_value = min_v
	sb.max_value = max_v
	sb.step = step
	sb.value = float(body.get(key, 0.0))
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.value_changed.connect(func(v):
		body[key] = v
		_refresh_viewport()
	)
	hbox.add_child(sb)
	_inspector.add_child(hbox)


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
	_add_spin_box_field("Radius", moon, "radius", 1.0, 100.0, 1.0)
	_add_color_picker_field(moon, "color")
	_add_check_box_field("Landable", moon, "is_landable")
	_add_check_box_field("Has Astronaut", moon, "has_astronaut")
	_add_check_box_field("Has Fuel", moon, "has_fuel")
	_add_spin_box_field("Mass", moon, "mass", 0.0, 1e5, 1.0)
	_add_spin_box_field("Perihelion", moon, "perihelion", 0.0, 200.0, 1.0)
	_add_spin_box_field("Aphelion", moon, "aphelion", 0.0, 200.0, 1.0)
	_add_spin_box_field("Angle of Aphelion", moon, "angle_of_aphelion", -PI, PI, 0.01)
	_add_spin_box_field("Phase", moon, "phase", -PI, PI, 0.01)
	_add_spin_box_field("Fuel Orbit Radius", moon, "fuel_orbit_radius", 0.0, 200.0, 1.0)
	_add_spin_box_field("Fuel Orbit Speed", moon, "fuel_orbit_speed", -10.0, 10.0, 0.01)


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

func _on_add_sun() -> void:
	# One sun per level. Warn if one exists rather than creating a
	# second (the existing sun's properties can be edited once the
	# Phase 4 inspector is in).
	for body in spec.bodies:
		if body.get("type") == "sun":
			_inspector_placeholder_warn("Sun already exists. Edit the existing sun's properties.")
			return
	spec.bodies.append(_make_default_sun_spec())
	_refresh_body_list()
	_refresh_viewport()
	_select_last_body()


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


func _on_remove_selected() -> void:
	var selected := _body_list.get_selected_items()
	if selected.is_empty():
		return
	var i: int = selected[0]
	if i >= spec.bodies.size():
		return
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


# --- Save / Test Level stubs (Phase 6) ---

func _on_save() -> void:
	push_warning("LevelEditor: Save (Phase 6 — not implemented yet)")


func _on_save_as() -> void:
	push_warning("LevelEditor: Save As... (Phase 6 — not implemented yet)")


func _on_test_level() -> void:
	push_warning("LevelEditor: Test Level (Phase 6 — not implemented yet)")