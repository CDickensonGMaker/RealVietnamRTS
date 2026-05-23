extends PanelContainer
class_name CommandPanel
## Global Order Panel - Macro-level commands for Vietnam RTS.
## Player issues high-level orders; units autonomously execute them.
## No micro-management - just strategic command placement.
##
## Design philosophy: Player is the commander, not a babysitter.
## Orders create zones/tasks that available units fulfill.

const MilitaryTheme = preload("res://battle_system/ui/military_theme.gd")
const CursorModeScript = preload("res://battle_system/ui/cursor_mode.gd")

# =============================================================================
# SIGNALS
# =============================================================================

## Emitted when a command button is pressed
signal command_pressed(command_name: String)

## Emitted when build submenu is opened
signal build_menu_requested()

# =============================================================================
# CONFIGURATION
# =============================================================================

const PANEL_WIDTH: float = 340.0
const PANEL_HEIGHT: float = 180.0
const BUTTON_SIZE: float = 52.0
const GRID_COLS: int = 5
const ROW_SPACING: int = 4

# =============================================================================
# COMMAND DEFINITIONS - CONSTRUCTION ORDERS (Row 1)
# These create zones that engineers/bulldozers auto-fulfill
# =============================================================================

const CONSTRUCTION_ORDERS: Array[Dictionary] = [
	{"name": "clear", "label": "CLEAR", "hotkey": "C", "icon_color": Color(0.6, 0.4, 0.2),
	 "tooltip": "Paint area to clear jungle. Engineers use det-cord."},
	{"name": "flatten", "label": "FLAT", "hotkey": "F", "icon_color": Color(0.5, 0.5, 0.3),
	 "tooltip": "Paint area to flatten terrain. Bulldozers grade."},
	{"name": "build", "label": "BUILD", "hotkey": "B", "icon_color": Color(0.5, 0.6, 0.4),
	 "tooltip": "Place building. Engineers construct."},
	{"name": "repair", "label": "REPAIR", "hotkey": "R", "icon_color": Color(0.6, 0.7, 0.3),
	 "tooltip": "Click structure to repair. Engineers fix."},
	{"name": "dozer_clear", "label": "GRADE", "hotkey": "G", "icon_color": Color(0.7, 0.5, 0.2),
	 "tooltip": "Draw line for bulldozer road clearing."},
]

# =============================================================================
# COMMAND DEFINITIONS - TACTICAL ORDERS (Row 2)
# High-level combat/movement commands
# =============================================================================

const TACTICAL_ORDERS: Array[Dictionary] = [
	{"name": "attack_move", "label": "A-MOVE", "hotkey": "A", "icon_color": Color(0.9, 0.5, 0.2),
	 "tooltip": "Attack-move to location. Engage enemies en route."},
	{"name": "patrol", "label": "PATROL", "hotkey": "P", "icon_color": Color(0.5, 0.7, 0.9),
	 "tooltip": "Set patrol route. Units auto-patrol."},
	{"name": "defend", "label": "DEFEND", "hotkey": "D", "icon_color": Color(0.4, 0.5, 0.7),
	 "tooltip": "Defend position. Units hold and engage."},
	{"name": "garrison", "label": "ENTER", "hotkey": "E", "icon_color": Color(0.4, 0.5, 0.6),
	 "tooltip": "Enter nearest bunker/structure."},
	{"name": "unload", "label": "EXIT", "hotkey": "U", "icon_color": Color(0.6, 0.5, 0.4),
	 "tooltip": "Exit garrison or unload cargo."},
]

# =============================================================================
# COMMAND DEFINITIONS - AIR/SUPPORT ORDERS (Row 3)
# Fire support and air operations
# =============================================================================

const SUPPORT_ORDERS: Array[Dictionary] = [
	{"name": "fire_mission", "label": "ARTY", "hotkey": "1", "icon_color": Color(0.9, 0.3, 0.2),
	 "tooltip": "Call artillery fire mission."},
	{"name": "napalm", "label": "NAPALM", "hotkey": "2", "icon_color": Color(0.9, 0.5, 0.2),
	 "tooltip": "Call napalm strike (clears jungle)."},
	{"name": "bomb", "label": "BOMB", "hotkey": "3", "icon_color": Color(0.8, 0.3, 0.3),
	 "tooltip": "Call bomb run."},
	{"name": "medevac", "label": "MEDVAC", "hotkey": "4", "icon_color": Color(0.3, 0.8, 0.3),
	 "tooltip": "Request medevac helicopter."},
	{"name": "resupply", "label": "SUPPLY", "hotkey": "5", "icon_color": Color(0.5, 0.6, 0.3),
	 "tooltip": "Request supply drop/convoy."},
]

# =============================================================================
# STATE
# =============================================================================

var _current_selection: Array[Node3D] = []
var _row_containers: Array[HBoxContainer] = []
var _buttons: Dictionary = {}  # command_name -> Button
var _hotkey_map: Dictionary = {}  # hotkey_char -> command_name

## Cached autoload reference
var _selection_manager: Node = null


func _ready() -> void:
	# Cache autoload reference
	_selection_manager = get_node_or_null("/root/SelectionManager")

	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	# CRITICAL: Stop mouse events from propagating through to SelectionManager
	# This prevents clicking command buttons from clearing the current selection
	mouse_filter = Control.MOUSE_FILTER_STOP

	_setup_theme()
	_build_ui()

	# Connect to selection changes
	if BattleSignals:
		BattleSignals.selection_changed.connect(_on_selection_changed)

	# Build initial buttons (always visible)
	_rebuild_buttons()

	# Always visible - global command panel
	visible = true


func _setup_theme() -> void:
	var panel_style: StyleBoxFlat = MilitaryTheme.create_panel_stylebox()
	add_theme_stylebox_override("panel", panel_style)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", ROW_SPACING)
	margin.add_child(vbox)

	# Create 3 rows for commands
	for i in 3:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", ROW_SPACING)
		vbox.add_child(row)
		_row_containers.append(row)


func _on_selection_changed(_selected: Array = []) -> void:
	# Get current selection from SelectionManager
	if _selection_manager and _selection_manager.has_method("get_selected_units"):
		_current_selection = _selection_manager.get_selected_units()
	else:
		_current_selection = []


func _update_button_states() -> void:
	# For now, all buttons are always enabled
	# In the future, grey out unavailable commands
	pass


func _rebuild_buttons() -> void:
	# Clear existing buttons and hotkey map
	for row in _row_containers:
		for child in row.get_children():
			child.queue_free()
	_buttons.clear()
	_hotkey_map.clear()

	# === ROW 1: Construction Orders (always visible) ===
	for cmd in CONSTRUCTION_ORDERS:
		_create_command_button(_row_containers[0], cmd)

	# === ROW 2: Tactical Orders (always visible) ===
	for cmd in TACTICAL_ORDERS:
		_create_command_button(_row_containers[1], cmd)

	# === ROW 3: Support Orders (always visible) ===
	for cmd in SUPPORT_ORDERS:
		_create_command_button(_row_containers[2], cmd)

	# All rows always visible in macro mode
	for row in _row_containers:
		row.visible = true

	# Adjust panel height
	_update_panel_size()


func _analyze_selection() -> Dictionary:
	var info: Dictionary = {
		"has_engineer": false,
		"has_bulldozer": false,
		"has_bunker": false,
		"has_artillery_deployed": false,
		"has_artillery_packed": false,
		"has_helicopter": false,
		"has_airplane_idle": false,
		"has_airplane_flying": false,
		"has_vehicle": false,
		"has_transport": false,
		"has_combat_units": false,
		"has_basic_infantry": false,
	}

	for unit in _current_selection:
		if not is_instance_valid(unit):
			continue

		# Check unit type by groups and properties
		if unit.is_in_group("bunkers"):
			info.has_bunker = true

		if unit.is_in_group("vehicles"):
			info.has_vehicle = true

		if unit.is_in_group("transports") or unit.is_in_group("helicopters"):
			info.has_transport = true

		if unit.has_method("get"):
			# Check for engineer capability
			var data: Resource = unit.get("data")
			if data:
				if "can_build" in data and data.can_build:
					# Check if it's a bulldozer (vehicle that can build) or engineer
					if "is_vehicle" in data and data.is_vehicle:
						info.has_bulldozer = true
					else:
						info.has_engineer = true

				# Check if basic infantry (no special abilities)
				if "unit_type" in data:
					var unit_type: int = data.unit_type
					# Basic infantry types don't get special abilities
					if unit_type == 0:  # RIFLE_SQUAD type
						info.has_basic_infantry = true
					# Check for BULLDOZER type (unit_type = 3)
					if unit_type == 3:  # BULLDOZER type
						info.has_bulldozer = true

				# Check for combat capability
				if "attack_range" in data and data.attack_range > 0:
					info.has_combat_units = true

			# Check for artillery state
			if unit.is_in_group("artillery"):
				var art_state: Variant = unit.get("state")
				if art_state != null:
					if art_state == GameEnums.ArtilleryState.DEPLOYED:
						info.has_artillery_deployed = true
					elif art_state == GameEnums.ArtilleryState.PACKED:
						info.has_artillery_packed = true

			# Check helicopter
			if unit.is_in_group("helicopters"):
				info.has_helicopter = true
				info.has_transport = true

			# Check airplane
			if unit.is_in_group("airplanes"):
				var plane_state: Variant = unit.get("state")
				if plane_state != null:
					if plane_state == GameEnums.AirplaneState.IDLE_AT_AIRPORT:
						info.has_airplane_idle = true
					elif plane_state == GameEnums.AirplaneState.PATROLLING or plane_state == GameEnums.AirplaneState.ATTACK_RUN:
						info.has_airplane_flying = true

	return info


func _update_panel_size() -> void:
	var visible_rows: int = 0
	for row in _row_containers:
		if row.visible and row.get_child_count() > 0:
			visible_rows += 1

	var new_height: float = 8.0 + (visible_rows * (BUTTON_SIZE + ROW_SPACING))
	custom_minimum_size.y = new_height


func _create_command_button(parent: Control, cmd: Dictionary) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)

	# Vertical layout
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Pass clicks to button
	button.add_child(vbox)

	# Icon placeholder (28x28 ColorRect)
	var icon_container := CenterContainer.new()
	icon_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Pass clicks to button
	vbox.add_child(icon_container)

	var icon_slot := ColorRect.new()
	icon_slot.name = "IconSlot"
	icon_slot.custom_minimum_size = Vector2(28, 28)
	icon_slot.color = cmd.get("icon_color", Color(0.5, 0.5, 0.5))
	icon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Pass clicks to button
	icon_container.add_child(icon_slot)

	# Label
	var label := Label.new()
	label.text = cmd.get("label", "CMD")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_PRIMARY)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Pass clicks to button
	vbox.add_child(label)

	# Hotkey hint (top-right)
	var hotkey := Label.new()
	hotkey.text = cmd.get("hotkey", "")
	hotkey.add_theme_font_size_override("font_size", 8)
	hotkey.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	hotkey.position = Vector2(BUTTON_SIZE - 12, 2)
	hotkey.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Pass clicks to button
	button.add_child(hotkey)

	# Apply button theme
	button.add_theme_stylebox_override("normal", MilitaryTheme.create_button_stylebox("normal"))
	button.add_theme_stylebox_override("hover", MilitaryTheme.create_button_stylebox("hover"))
	button.add_theme_stylebox_override("pressed", MilitaryTheme.create_button_stylebox("pressed"))

	# Connect press signal
	var cmd_name: String = cmd.get("name", "")
	button.pressed.connect(_on_button_pressed.bind(cmd_name))

	parent.add_child(button)
	_buttons[cmd_name] = button

	# Register hotkey in mapping
	var hotkey_char: String = cmd.get("hotkey", "")
	if not hotkey_char.is_empty():
		_hotkey_map[hotkey_char.to_upper()] = cmd_name


func _on_button_pressed(command_name: String) -> void:
	print("[CommandPanel] >>> BUTTON CLICKED: %s <<<" % command_name)
	command_pressed.emit(command_name)
	print("[CommandPanel] Signal emitted for: %s" % command_name)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Handle hotkey shortcuts using mapping (efficient lookup)
	if event is InputEventKey and event.pressed and not event.echo:
		var key_char: String = OS.get_keycode_string(event.keycode).to_upper()

		# Direct lookup in hotkey map
		if key_char in _hotkey_map:
			_on_button_pressed(_hotkey_map[key_char])
			get_viewport().set_input_as_handled()
			return


# =============================================================================
# PUBLIC API
# =============================================================================

## Enable or disable a specific command button
func set_command_enabled(command_name: String, enabled: bool) -> void:
	if command_name in _buttons:
		_buttons[command_name].disabled = not enabled


## Highlight a command button (for mode indication)
func set_command_highlighted(command_name: String, highlighted: bool) -> void:
	if command_name in _buttons:
		var button: Button = _buttons[command_name]
		if highlighted:
			button.add_theme_stylebox_override("normal", MilitaryTheme.create_button_stylebox("pressed"))
		else:
			button.add_theme_stylebox_override("normal", MilitaryTheme.create_button_stylebox("normal"))


## Force refresh the command panel (call after unit state changes)
func refresh() -> void:
	_rebuild_buttons()
