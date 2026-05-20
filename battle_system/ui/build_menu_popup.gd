extends PanelContainer
class_name BuildMenuPopup
## Build Menu Popup - Grid-based building selection panel
##
## Displays available buildings in a 3-column grid with thumbnails.
## Click a building to enter placement mode.
## Reference: BP RTS Dark Shadows style build menu.

const BuildingData = preload("res://firebase_system/building_data.gd")

signal building_selected(building_key: String, placement_mode: PlacementMode)
signal menu_closed()

## Placement modes for different building types
enum PlacementMode {
	SINGLE,                  # One click, one building
	PAINTABLE,               # Continuous drag placement (seamless)
	PAINTABLE_SPACED,        # Continuous drag with spacing (e.g., tank traps)
	PAINTABLE_LINE_JITTERED  # Drag line with jittered spacing (foxholes)
}

## Building entry for the menu
class BuildingEntry:
	var key: String
	var display_name: String
	var supply_cost: int
	var placement_mode: PlacementMode
	var scene_path: String
	var spacing: float = 0.0  # For PAINTABLE_SPACED
	var category: String = "defenses"
	var building_type: int = -1  # BuildingData.BuildingType

## Visual settings
const PANEL_SIZE := Vector2(420, 520)
const THUMBNAIL_SIZE := Vector2(120, 100)
const GRID_COLUMNS := 3
const GRID_SPACING := 8

## Colors
const BG_COLOR := Color(0.1, 0.12, 0.1, 0.92)
const BORDER_COLOR := Color(0.29, 0.36, 0.24)  # Military green
const HEADER_COLOR := Color(0.18, 0.22, 0.16)
const HOVER_COLOR := Color(0.25, 0.35, 0.2, 0.6)
const DISABLED_ALPHA := 0.4

## Available buildings - defined here for quick iteration
var BUILDINGS: Array[BuildingEntry] = []

## UI elements
var _header: HBoxContainer
var _title_label: Label
var _close_button: Button
var _scroll_container: ScrollContainer
var _grid_container: GridContainer
var _thumbnail_buttons: Dictionary = {}  # key -> Button

## Current supply (for graying out unaffordable)
var current_supply: int = 1000


func _ready() -> void:
	_setup_buildings()
	_create_ui()
	visible = false

	# Allow clicking outside to close
	gui_input.connect(_on_panel_gui_input)


func _setup_buildings() -> void:
	## Define available buildings for the menu
	## This is where you add/remove buildings from the build menu

	# Sandbag Wall - paintable, seamless
	_add_building("sandbag_wall", "Sandbag Wall", 5, PlacementMode.PAINTABLE,
		"", BuildingData.BuildingType.SANDBAG_LIGHT)

	# Wire Obstacle - paintable with spacing
	_add_building("wire_obstacle", "Wire Obstacle", 10, PlacementMode.PAINTABLE_SPACED,
		"", BuildingData.BuildingType.WIRE_OBSTACLE, 2.0)

	# Tank Traps - jittered line placement
	_add_building("tank_trap", "Tank Trap", 8, PlacementMode.PAINTABLE_LINE_JITTERED,
		"", -1, 2.5)  # 2.5m spacing with jitter

	# Bunker - single placement
	_add_building("bunker", "Bunker", 40, PlacementMode.SINGLE,
		"", BuildingData.BuildingType.BUNKER)

	# MG Nest - single placement
	_add_building("mg_nest", "MG Nest", 30, PlacementMode.SINGLE,
		"", BuildingData.BuildingType.MACHINE_GUN_NEST)

	# Mortar Pit - single placement
	_add_building("mortar_pit", "Mortar Pit", 35, PlacementMode.SINGLE,
		"", BuildingData.BuildingType.MORTAR_PIT)

	# Watchtower - single placement
	_add_building("watchtower", "Watchtower", 25, PlacementMode.SINGLE,
		"", BuildingData.BuildingType.WATCHTOWER)

	# Foxhole - jittered line placement (CoH-style defensive line)
	_add_building("foxhole", "Foxhole", 15, PlacementMode.PAINTABLE_LINE_JITTERED,
		"", -1, 4.0)  # 4m base spacing

	# Helipad - single placement
	_add_building("helipad", "Helipad", 50, PlacementMode.SINGLE,
		"", BuildingData.BuildingType.HELIPAD)

	# Ammo Bunker - single placement
	_add_building("ammo_bunker", "Ammo Bunker", 45, PlacementMode.SINGLE,
		"", BuildingData.BuildingType.AMMO_BUNKER)

	# Medical Station - single placement
	_add_building("medical_station", "Medical Station", 35, PlacementMode.SINGLE,
		"", BuildingData.BuildingType.MEDICAL_STATION)

	# TOC (Command) - single placement
	_add_building("toc", "TOC", 80, PlacementMode.SINGLE,
		"", BuildingData.BuildingType.TOC)

	# Gate Entrance - single placement
	_add_building("gate_entrance", "Gate Entrance", 25, PlacementMode.SINGLE,
		"res://assets/buildings/composed/gate_entrance.tscn", -1)

	# Trench - paintable, seamless
	_add_building("trench", "Trench", 12, PlacementMode.PAINTABLE,
		"", -1)

	# Artillery Pit - single placement
	_add_building("artillery_pit", "Artillery Pit", 100, PlacementMode.SINGLE,
		"", BuildingData.BuildingType.ARTILLERY_PIT)


func _add_building(key: String, name: String, cost: int, mode: PlacementMode,
		scene: String, building_type: int, spacing: float = 0.0) -> void:
	var entry := BuildingEntry.new()
	entry.key = key
	entry.display_name = name
	entry.supply_cost = cost
	entry.placement_mode = mode
	entry.scene_path = scene
	entry.building_type = building_type
	entry.spacing = spacing
	BUILDINGS.append(entry)


func _create_ui() -> void:
	# Panel styling
	custom_minimum_size = PANEL_SIZE

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)

	# Main layout
	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 4)
	add_child(main_vbox)

	# Header
	_create_header(main_vbox)

	# Separator
	var sep := HSeparator.new()
	main_vbox.add_child(sep)

	# Scroll container for grid
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(_scroll_container)

	# Grid container
	_grid_container = GridContainer.new()
	_grid_container.columns = GRID_COLUMNS
	_grid_container.add_theme_constant_override("h_separation", GRID_SPACING)
	_grid_container.add_theme_constant_override("v_separation", GRID_SPACING)
	_scroll_container.add_child(_grid_container)

	# Populate grid with buildings
	_populate_grid()


func _create_header(parent: VBoxContainer) -> void:
	_header = HBoxContainer.new()

	var header_style := StyleBoxFlat.new()
	header_style.bg_color = HEADER_COLOR
	header_style.content_margin_left = 8
	header_style.content_margin_right = 8
	header_style.content_margin_top = 6
	header_style.content_margin_bottom = 6

	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", header_style)
	parent.add_child(header_panel)
	header_panel.add_child(_header)

	_title_label = Label.new()
	_title_label.text = "BUILD MENU"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", 16)
	_header.add_child(_title_label)

	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.custom_minimum_size = Vector2(28, 28)
	_close_button.pressed.connect(_on_close_pressed)
	_header.add_child(_close_button)


func _populate_grid() -> void:
	# Clear existing
	for child in _grid_container.get_children():
		child.queue_free()
	_thumbnail_buttons.clear()

	# Add building thumbnails
	for entry in BUILDINGS:
		var thumb := _create_thumbnail(entry)
		_grid_container.add_child(thumb)
		_thumbnail_buttons[entry.key] = thumb


func _create_thumbnail(entry: BuildingEntry) -> Control:
	var container := VBoxContainer.new()
	container.custom_minimum_size = THUMBNAIL_SIZE

	# Thumbnail button
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(THUMBNAIL_SIZE.x, THUMBNAIL_SIZE.y - 35)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_building_selected.bind(entry.key))
	btn.mouse_entered.connect(_on_thumb_hover.bind(btn, true))
	btn.mouse_exited.connect(_on_thumb_hover.bind(btn, false))

	# Style the button
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.15, 0.18, 0.14)
	btn_style.border_color = Color(0.3, 0.35, 0.28)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", btn_style)

	var btn_hover := btn_style.duplicate()
	btn_hover.bg_color = HOVER_COLOR
	btn_hover.border_color = Color(0.4, 0.5, 0.35)
	btn.add_theme_stylebox_override("hover", btn_hover)

	# Add icon/preview (placeholder for now)
	var icon_label := Label.new()
	icon_label.text = _get_building_icon(entry.key)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 28)
	btn.add_child(icon_label)

	container.add_child(btn)

	# Name label
	var name_label := Label.new()
	name_label.text = entry.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	container.add_child(name_label)

	# Cost label
	var cost_label := Label.new()
	cost_label.text = "%d" % entry.supply_cost
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 12)
	cost_label.add_theme_color_override("font_color", Color(0.94, 0.75, 0.25))  # Yellow
	container.add_child(cost_label)

	# Store entry reference
	container.set_meta("entry", entry)
	container.set_meta("cost_label", cost_label)

	return container


func _get_building_icon(key: String) -> String:
	## Return simple text icon based on building type
	match key:
		"sandbag_wall": return "[=]"
		"wire_obstacle": return "///"
		"tank_trap": return "XXX"
		"bunker": return "[B]"
		"mg_nest": return "[M]"
		"mortar_pit": return "[O]"
		"watchtower": return "[T]"
		"foxhole": return "(F)"
		"helipad": return "[H]"
		"ammo_bunker": return "[A]"
		"medical_station": return "[+]"
		"toc": return "[C]"
		"gate_entrance": return "[G]"
		"trench": return "---"
		"artillery_pit": return "[!]"
		_: return "[?]"


func _update_button_states() -> void:
	for key in _thumbnail_buttons:
		var container: Control = _thumbnail_buttons[key]
		var entry: BuildingEntry = container.get_meta("entry")
		var cost_label: Label = container.get_meta("cost_label")

		var can_afford: bool = current_supply >= entry.supply_cost

		# Update visual state
		container.modulate.a = 1.0 if can_afford else DISABLED_ALPHA

		# Update cost label color
		if can_afford:
			cost_label.add_theme_color_override("font_color", Color(0.94, 0.75, 0.25))
		else:
			cost_label.add_theme_color_override("font_color", Color(0.6, 0.4, 0.4))


func _on_building_selected(key: String) -> void:
	# Find entry
	var entry: BuildingEntry = null
	for e in BUILDINGS:
		if e.key == key:
			entry = e
			break

	if not entry:
		return

	# Check affordability
	if current_supply < entry.supply_cost:
		print("[BuildMenu] Cannot afford %s (need %d, have %d)" % [
			entry.display_name, entry.supply_cost, current_supply])
		return

	# Close menu and emit selection
	visible = false
	building_selected.emit(key, entry.placement_mode)
	print("[BuildMenu] Selected: %s (%s mode)" % [
		entry.display_name, PlacementMode.keys()[entry.placement_mode]])


func _on_thumb_hover(btn: Button, hovering: bool) -> void:
	# Could add tooltip or additional hover effects here
	pass


func _on_close_pressed() -> void:
	close_menu()


func _on_panel_gui_input(event: InputEvent) -> void:
	# Close on click outside content area handled by parent
	pass


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		var key := (event as InputEventKey).keycode
		if key == KEY_ESCAPE or key == KEY_B:
			close_menu()
			get_viewport().set_input_as_handled()


## Open the build menu
func open_menu(supply: int = 1000) -> void:
	current_supply = supply
	_update_button_states()
	visible = true

	# Center on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	position = (viewport_size - size) * 0.5
	position.x = viewport_size.x - size.x - 20  # Right side


## Close the build menu
func close_menu() -> void:
	visible = false
	menu_closed.emit()


## Get building entry by key
func get_building(key: String) -> BuildingEntry:
	for entry in BUILDINGS:
		if entry.key == key:
			return entry
	return null


## Get spacing for a building (for PAINTABLE_SPACED)
func get_building_spacing(key: String) -> float:
	var entry := get_building(key)
	if entry:
		return entry.spacing
	return 0.0


## Update supply display
func set_supply(supply: int) -> void:
	current_supply = supply
	if visible:
		_update_button_states()
