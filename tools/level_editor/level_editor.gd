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
## Inspector is a placeholder; Save / Save As / Test Level are stubs.
## Future phases add the real inspector, orbit lines, save/load, etc.
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
var _inspector_placeholder: Label  # Phase 4 replaces this


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


## Left panel: body list + Add/Remove buttons + inspector placeholder.
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
	_inspector_placeholder = Label.new()
	_inspector_placeholder.text = "(select a body to edit properties)"
	_inspector_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(_inspector_placeholder)


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


## Bottom bar: Save / Save As / Test Level. All stubs for Phase 2.
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

func _refresh_body_list() -> void:
	_body_list.clear()
	for i in range(spec.bodies.size()):
		var body: Dictionary = spec.bodies[i]
		_body_list.add_item(_body_label_for(body, i), null)


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


func _on_body_selected(index: int) -> void:
	# Phase 4 will replace the inspector placeholder with a real
	# property panel for the selected body. For Phase 2 we just
	# surface the selection in the placeholder text.
	if index < 0 or index >= spec.bodies.size():
		_inspector_placeholder.text = "(select a body to edit properties)"
		return
	var body: Dictionary = spec.bodies[index]
	var type: String = body.get("type", "?")
	var name: String = body.get("name", "")
	var display_name: String = name if name else type
	_inspector_placeholder.text = "Selected: %s (%s)\n\nProperty editor coming in Phase 4." % [display_name, type]


# --- Add / Remove handlers ---

func _on_add_sun() -> void:
	# One sun per level. Warn if one exists rather than creating a
	# second (the existing sun's properties can be edited once the
	# Phase 4 inspector is in).
	for body in spec.bodies:
		if body.get("type") == "sun":
			_inspector_placeholder.text = "Sun already exists. Edit the existing sun's properties (Phase 4)."
			return
	spec.bodies.append(_make_default_sun_spec())
	_refresh_body_list()
	_refresh_viewport()


func _on_add_planet() -> void:
	spec.bodies.append(_make_default_planet_spec())
	_refresh_body_list()
	_refresh_viewport()


func _on_add_moon() -> void:
	# Moons are nested under their host planet in the v3 schema. Find
	# the currently selected planet and append to its moons[].
	var planet_spec := _get_selected_planet_spec()
	if planet_spec == null:
		_inspector_placeholder.text = "Select a planet in the list first, then click Add Moon."
		return
	if not planet_spec.has("moons"):
		planet_spec["moons"] = []
	planet_spec["moons"].append(_make_default_moon_spec())
	_refresh_body_list()
	_refresh_viewport()


func _on_add_asteroid() -> void:
	spec.bodies.append(_make_default_asteroid_spec())
	_refresh_body_list()
	_refresh_viewport()


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


## Helper: return the currently selected body's spec if it's a planet,
## else null. Used by Add Moon to know where to nest the new moon.
func _get_selected_planet_spec() -> Dictionary:
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


# --- Default spec templates (Phase 2 placeholders) ---
# These produce reasonable starter values so the bodies are visible
# without overlapping each other. The inspector in Phase 4 will let
# users tune them.

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
	return {
		"radius": 6.0,
		"color": [0.7, 0.7, 0.8],
		"perihelion": 20.0,
		"aphelion": 30.0,
		"angle_of_aphelion": 0.0,
		"phase": 0.0,
		"is_landable": true,
		"mass": 10.0,
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
		"color": [0.5, 0.4, 0.3],
		"perihelion": base_radius,
		"aphelion": base_radius,
		"angle_of_aphelion": 0.0,
		"phase": 0.0,
		"is_landable": false,
	}


# --- Save / Test Level stubs (Phase 6) ---

func _on_save() -> void:
	push_warning("LevelEditor: Save (Phase 6 — not implemented yet)")


func _on_save_as() -> void:
	push_warning("LevelEditor: Save As... (Phase 6 — not implemented yet)")


func _on_test_level() -> void:
	push_warning("LevelEditor: Test Level (Phase 6 — not implemented yet)")