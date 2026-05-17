extends PanelContainer
class_name SelectionCard
## Bottom-left panel showing selected unit information.
## Shows single-unit detail view or multi-unit aggregate view.

const MilitaryTheme = preload("res://battle_system/ui/military_theme.gd")

# =============================================================================
# CONFIGURATION
# =============================================================================

const UPDATE_INTERVAL: float = 0.1  # 10Hz update rate
const CARD_WIDTH: float = 320.0
const CARD_HEIGHT: float = 180.0

# =============================================================================
# STATE
# =============================================================================

var _update_timer: float = 0.0
var _current_selection: Array[Node3D] = []

# =============================================================================
# UI COMPONENTS
# =============================================================================

## Single unit view
var _single_view: VBoxContainer
var _faction_stripe: ColorRect
var _portrait_slot: ColorRect
var _name_label: Label
var _type_label: Label
var _state_badge: ColorRect
var _state_label: Label
var _hp_bar_bg: ColorRect
var _hp_bar_fill: ColorRect
var _hp_text: Label
var _vet_bar_bg: ColorRect
var _vet_bar_fill: ColorRect
var _vet_label: Label
var _stats_container: HBoxContainer
var _ammo_label: Label
var _crew_label: Label

## Smooth HP bar animation
var _target_hp_ratio: float = 1.0
var _display_hp_ratio: float = 1.0
const HP_SMOOTH_SPEED: float = 5.0  # How fast HP bar catches up

## Multi-unit view
var _multi_view: VBoxContainer
var _count_label: Label
var _aggregate_hp_bg: ColorRect
var _aggregate_hp_fill: ColorRect
var _type_list: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	_setup_theme()
	_build_ui()

	# Connect to selection changes
	if BattleSignals:
		BattleSignals.selection_changed.connect(_on_selection_changed)

	# Initialize hidden
	visible = false


func _process(delta: float) -> void:
	# Smooth HP bar interpolation
	if _display_hp_ratio != _target_hp_ratio:
		_display_hp_ratio = lerpf(_display_hp_ratio, _target_hp_ratio, delta * HP_SMOOTH_SPEED)
		# Snap when close enough to avoid endless tiny updates
		if absf(_display_hp_ratio - _target_hp_ratio) < 0.001:
			_display_hp_ratio = _target_hp_ratio
		_hp_bar_fill.anchor_right = _display_hp_ratio

	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = UPDATE_INTERVAL
		_update_display()


func _setup_theme() -> void:
	var panel_style: StyleBoxFlat = MilitaryTheme.create_panel_stylebox()
	add_theme_stylebox_override("panel", panel_style)


func _build_ui() -> void:
	# Main container
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 4)
	add_child(main)

	# Build single-unit view
	_build_single_view(main)

	# Build multi-unit view
	_build_multi_view(main)

	# Start with both hidden
	_single_view.visible = false
	_multi_view.visible = false


func _build_single_view(parent: Control) -> void:
	_single_view = VBoxContainer.new()
	_single_view.add_theme_constant_override("separation", 4)
	parent.add_child(_single_view)

	# Top row: portrait + info
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	_single_view.add_child(top_row)

	# Faction stripe (6px left edge)
	_faction_stripe = ColorRect.new()
	_faction_stripe.custom_minimum_size = Vector2(6, 64)
	_faction_stripe.color = MilitaryTheme.COL_FACTION_US
	top_row.add_child(_faction_stripe)

	# Portrait placeholder (64x64)
	_portrait_slot = ColorRect.new()
	_portrait_slot.name = "PortraitSlot"
	_portrait_slot.custom_minimum_size = Vector2(64, 64)
	_portrait_slot.color = Color(0.25, 0.25, 0.25)
	top_row.add_child(_portrait_slot)

	# Info column
	var info_col := VBoxContainer.new()
	info_col.add_theme_constant_override("separation", 2)
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(info_col)

	# Name + training level
	_name_label = Label.new()
	_name_label.text = "Unit Name"
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_PRIMARY)
	info_col.add_child(_name_label)

	# Type / role
	_type_label = Label.new()
	_type_label.text = "Infantry"
	_type_label.add_theme_font_size_override("font_size", 10)
	_type_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	info_col.add_child(_type_label)

	# State badge
	var state_row := HBoxContainer.new()
	state_row.add_theme_constant_override("separation", 4)
	info_col.add_child(state_row)

	_state_badge = ColorRect.new()
	_state_badge.custom_minimum_size = Vector2(8, 8)
	_state_badge.color = MilitaryTheme.COL_STATE_IDLE
	state_row.add_child(_state_badge)

	_state_label = Label.new()
	_state_label.text = "IDLE"
	_state_label.add_theme_font_size_override("font_size", 10)
	_state_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	state_row.add_child(_state_label)

	# Veterancy badge (in state row)
	_vet_label = Label.new()
	_vet_label.text = "Conscript"
	_vet_label.add_theme_font_size_override("font_size", 10)
	_vet_label.add_theme_color_override("font_color", MilitaryTheme.COL_VET[0])
	state_row.add_child(_vet_label)

	# HP bar row
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	_single_view.add_child(hp_row)

	var hp_label := Label.new()
	hp_label.text = "HP"
	hp_label.add_theme_font_size_override("font_size", 10)
	hp_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	hp_label.custom_minimum_size = Vector2(24, 0)
	hp_row.add_child(hp_label)

	var hp_bar_container := Control.new()
	hp_bar_container.custom_minimum_size = Vector2(180, 12)
	hp_bar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_row.add_child(hp_bar_container)

	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_bar_bg.color = Color(0.1, 0.1, 0.1, 0.8)
	hp_bar_container.add_child(_hp_bar_bg)

	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_bar_fill.color = MilitaryTheme.COL_HEALTH_FULL
	hp_bar_container.add_child(_hp_bar_fill)

	_hp_text = Label.new()
	_hp_text.text = "100/100"
	_hp_text.add_theme_font_size_override("font_size", 10)
	_hp_text.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_PRIMARY)
	hp_row.add_child(_hp_text)

	# Veterancy XP bar
	var vet_row := HBoxContainer.new()
	vet_row.add_theme_constant_override("separation", 8)
	_single_view.add_child(vet_row)

	var vet_bar_label := Label.new()
	vet_bar_label.text = "XP"
	vet_bar_label.add_theme_font_size_override("font_size", 10)
	vet_bar_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	vet_bar_label.custom_minimum_size = Vector2(24, 0)
	vet_row.add_child(vet_bar_label)

	var vet_bar_container := Control.new()
	vet_bar_container.custom_minimum_size = Vector2(180, 8)
	vet_bar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vet_row.add_child(vet_bar_container)

	_vet_bar_bg = ColorRect.new()
	_vet_bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vet_bar_bg.color = Color(0.1, 0.1, 0.1, 0.8)
	vet_bar_container.add_child(_vet_bar_bg)

	_vet_bar_fill = ColorRect.new()
	_vet_bar_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vet_bar_fill.anchor_right = 0.0  # Start empty
	_vet_bar_fill.color = MilitaryTheme.COL_VET[0]
	vet_bar_container.add_child(_vet_bar_fill)

	# Stats row (ammo, crew, etc)
	_stats_container = HBoxContainer.new()
	_stats_container.add_theme_constant_override("separation", 16)
	_single_view.add_child(_stats_container)

	_ammo_label = Label.new()
	_ammo_label.text = "Ammo: 100"
	_ammo_label.add_theme_font_size_override("font_size", 10)
	_ammo_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	_stats_container.add_child(_ammo_label)

	_crew_label = Label.new()
	_crew_label.text = ""
	_crew_label.add_theme_font_size_override("font_size", 10)
	_crew_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	_stats_container.add_child(_crew_label)


func _build_multi_view(parent: Control) -> void:
	_multi_view = VBoxContainer.new()
	_multi_view.add_theme_constant_override("separation", 4)
	parent.add_child(_multi_view)

	# Count header
	_count_label = Label.new()
	_count_label.text = "12 UNITS SELECTED"
	_count_label.add_theme_font_size_override("font_size", 14)
	_count_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_PRIMARY)
	_multi_view.add_child(_count_label)

	# Aggregate HP bar
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	_multi_view.add_child(hp_row)

	var hp_label := Label.new()
	hp_label.text = "Total HP"
	hp_label.add_theme_font_size_override("font_size", 10)
	hp_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	hp_row.add_child(hp_label)

	var hp_container := Control.new()
	hp_container.custom_minimum_size = Vector2(200, 12)
	hp_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_row.add_child(hp_container)

	_aggregate_hp_bg = ColorRect.new()
	_aggregate_hp_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_aggregate_hp_bg.color = Color(0.1, 0.1, 0.1, 0.8)
	hp_container.add_child(_aggregate_hp_bg)

	_aggregate_hp_fill = ColorRect.new()
	_aggregate_hp_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_aggregate_hp_fill.color = MilitaryTheme.COL_HEALTH_FULL
	hp_container.add_child(_aggregate_hp_fill)

	# Type breakdown list
	_type_list = VBoxContainer.new()
	_type_list.add_theme_constant_override("separation", 2)
	_multi_view.add_child(_type_list)


func _on_selection_changed(_selected: Array = []) -> void:
	# Get current selection from SelectionManager
	var sel_mgr: Node = get_node_or_null("/root/SelectionManager")
	if sel_mgr and sel_mgr.has_method("get_selected_units"):
		_current_selection = sel_mgr.get_selected_units()
	else:
		_current_selection = []

	# Reset HP bar animation state for new selection
	_target_hp_ratio = 1.0
	_display_hp_ratio = 1.0

	# Toggle visibility based on selection
	visible = _current_selection.size() > 0

	# Switch view mode
	if _current_selection.size() == 1:
		_single_view.visible = true
		_multi_view.visible = false
	elif _current_selection.size() > 1:
		_single_view.visible = false
		_multi_view.visible = true
		_rebuild_type_list()
	else:
		_single_view.visible = false
		_multi_view.visible = false

	# Force immediate update
	_update_display()


func _update_display() -> void:
	if _current_selection.size() == 1:
		_update_single_view()
	elif _current_selection.size() > 1:
		_update_multi_view()


func _update_single_view() -> void:
	if _current_selection.is_empty():
		return

	var unit: Node3D = _current_selection[0]
	if not is_instance_valid(unit):
		return

	# Get unit data
	var data: Resource = null
	if unit.has_method("get") and unit.get("data") != null:
		data = unit.data

	# Update name
	var display_name: String = unit.name
	if data and "display_name" in data:
		display_name = data.display_name
	_name_label.text = display_name

	# Update type
	var type_text: String = "Unit"
	if data and "unit_type" in data:
		type_text = str(data.unit_type)
	_type_label.text = type_text

	# Update faction color
	var faction: int = 0
	if data and "faction" in data:
		faction = data.faction
	_faction_stripe.color = MilitaryTheme.faction_color(faction)

	# Update state
	if unit.has_method("get") and unit.get("state") != null:
		var state_val: int = unit.state
		var state_name: String = _get_state_name(state_val)
		_state_label.text = state_name
		_state_badge.color = MilitaryTheme.state_color(state_name)

	# Update HP
	var current_hp: float = 100.0
	var max_hp: float = 100.0
	if unit.has_method("get"):
		var c: Variant = unit.get("current_health")
		var m: Variant = unit.get("max_health")
		if c != null:
			current_hp = float(c)
		if m != null:
			max_hp = float(m)

	var hp_ratio: float = current_hp / max_hp if max_hp > 0 else 0.0
	_target_hp_ratio = hp_ratio  # Smooth transition handled in _process
	_hp_bar_fill.color = MilitaryTheme.health_color(hp_ratio)
	_hp_text.text = "%d/%d" % [int(current_hp), int(max_hp)]

	# Update veterancy
	var vet_level: int = 0
	var vet_progress: float = 0.0
	var vet_name: String = "Conscript"

	var vet_tracker: Node = get_node_or_null("/root/VeterancyTracker")
	if vet_tracker and vet_tracker.has_method("get_state"):
		var state: Resource = vet_tracker.get_state(unit)
		if state:
			vet_level = state.level if "level" in state else 0
			vet_progress = state.get_level_progress() if state.has_method("get_level_progress") else 0.0
			vet_name = state.get_level_name() if state.has_method("get_level_name") else "Conscript"

	_vet_label.text = vet_name
	_vet_label.add_theme_color_override("font_color", MilitaryTheme.veterancy_color(vet_level))
	_vet_bar_fill.anchor_right = vet_progress
	_vet_bar_fill.color = MilitaryTheme.veterancy_color(vet_level)

	# Update ammo
	if unit.has_method("get") and unit.get("current_ammo") != null:
		var ammo: int = unit.current_ammo
		var max_ammo: int = unit.max_ammo if unit.get("max_ammo") != null else 100
		_ammo_label.text = "Ammo: %d/%d" % [ammo, max_ammo]
		_ammo_label.add_theme_color_override("font_color",
			MilitaryTheme.ammo_color(float(ammo) / float(max_ammo) if max_ammo > 0 else 1.0))
		_ammo_label.visible = true
	else:
		_ammo_label.visible = false

	# Update crew (for vehicles/artillery)
	if unit.has_method("get") and unit.get("crew_remaining") != null:
		var crew: int = unit.crew_remaining
		var max_crew: int = unit.crew_size if unit.get("crew_size") != null else crew
		_crew_label.text = "Crew: %d/%d" % [crew, max_crew]
		_crew_label.visible = true
	else:
		_crew_label.visible = false


func _update_multi_view() -> void:
	_count_label.text = "%d UNITS SELECTED" % _current_selection.size()

	# Calculate aggregate HP
	var total_current: float = 0.0
	var total_max: float = 0.0

	for unit in _current_selection:
		if not is_instance_valid(unit):
			continue
		if unit.has_method("get"):
			var c: Variant = unit.get("current_health")
			var m: Variant = unit.get("max_health")
			if c != null:
				total_current += float(c)
			if m != null:
				total_max += float(m)

	var ratio: float = total_current / total_max if total_max > 0 else 0.0
	_aggregate_hp_fill.anchor_right = ratio
	_aggregate_hp_fill.color = MilitaryTheme.health_color(ratio)


func _rebuild_type_list() -> void:
	# Clear existing
	for child in _type_list.get_children():
		child.queue_free()

	# Count by type
	var type_counts: Dictionary = {}
	for unit in _current_selection:
		if not is_instance_valid(unit):
			continue
		var type_name: String = "Unknown"
		if unit.has_method("get") and unit.get("data") != null:
			var data: Resource = unit.data
			if "display_name" in data:
				type_name = data.display_name
		else:
			type_name = unit.name

		if type_name in type_counts:
			type_counts[type_name] += 1
		else:
			type_counts[type_name] = 1

	# Create labels
	for type_name in type_counts:
		var count: int = type_counts[type_name]
		var label := Label.new()
		label.text = "x%d %s" % [count, type_name]
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
		_type_list.add_child(label)


func _get_state_name(state_value: int) -> String:
	# Match common state enums
	match state_value:
		0: return "IDLE"
		1: return "MOVING"
		2: return "COMBAT"
		3: return "SUPPRESSED"
		4: return "DEAD"
		5: return "CLEARING"
		_: return "UNKNOWN"
