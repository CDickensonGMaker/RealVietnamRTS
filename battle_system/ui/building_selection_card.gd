extends PanelContainer
class_name BuildingSelectionCard
## Bottom-left panel showing selected building information.
## Shows health, garrison status, defensive status, and construction progress.

const MilitaryTheme = preload("res://battle_system/ui/military_theme.gd")

# =============================================================================
# CONFIGURATION
# =============================================================================

const UPDATE_INTERVAL: float = 0.2  # 5Hz update rate
const CARD_WIDTH: float = 320.0
const CARD_HEIGHT: float = 200.0

# =============================================================================
# STATE
# =============================================================================

var _update_timer: float = 0.0
var _current_building: Node3D = null
var _construction_zone: Node = null

# =============================================================================
# UI COMPONENTS
# =============================================================================

var _name_label: Label
var _category_label: Label
var _hp_bar_bg: ColorRect
var _hp_bar_fill: ColorRect
var _hp_text: Label
var _status_label: Label
var _garrison_label: Label
var _defense_label: Label
var _construction_progress_bar: ColorRect
var _construction_text: Label
var _stats_container: VBoxContainer

## Smooth HP bar animation
var _target_hp_ratio: float = 1.0
var _display_hp_ratio: float = 1.0
const HP_SMOOTH_SPEED: float = 5.0


func _ready() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	_setup_theme()
	_build_ui()

	# Connect to building selection signal (emitted when clicking buildings)
	if BattleSignals and BattleSignals.has_signal("building_selected"):
		BattleSignals.building_selected.connect(_on_building_selected)

	# Initialize hidden
	visible = false


func _process(delta: float) -> void:
	# Smooth HP bar interpolation
	if _display_hp_ratio != _target_hp_ratio:
		_display_hp_ratio = lerpf(_display_hp_ratio, _target_hp_ratio, delta * HP_SMOOTH_SPEED)
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
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 6)
	add_child(main)

	# Header row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	main.add_child(header)

	# Building icon placeholder
	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.color = Color(0.3, 0.35, 0.25)
	header.add_child(icon)

	# Name and category
	var info_col := VBoxContainer.new()
	info_col.add_theme_constant_override("separation", 2)
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(info_col)

	_name_label = Label.new()
	_name_label.text = "Building Name"
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_PRIMARY)
	info_col.add_child(_name_label)

	_category_label = Label.new()
	_category_label.text = "Firebase Perimeter"
	_category_label.add_theme_font_size_override("font_size", 10)
	_category_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	info_col.add_child(_category_label)

	_status_label = Label.new()
	_status_label.text = "Operational"
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.add_theme_color_override("font_color", MilitaryTheme.COL_HEALTH_FULL)
	info_col.add_child(_status_label)

	# HP bar row
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	main.add_child(hp_row)

	var hp_label := Label.new()
	hp_label.text = "HP"
	hp_label.add_theme_font_size_override("font_size", 10)
	hp_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	hp_label.custom_minimum_size = Vector2(30, 0)
	hp_row.add_child(hp_label)

	var hp_bar_container := Control.new()
	hp_bar_container.custom_minimum_size = Vector2(180, 14)
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

	# Construction progress (only visible during construction)
	var construction_row := HBoxContainer.new()
	construction_row.name = "ConstructionRow"
	construction_row.add_theme_constant_override("separation", 8)
	main.add_child(construction_row)

	var constr_label := Label.new()
	constr_label.text = "Build"
	constr_label.add_theme_font_size_override("font_size", 10)
	constr_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	constr_label.custom_minimum_size = Vector2(30, 0)
	construction_row.add_child(constr_label)

	var construction_bar_container := Control.new()
	construction_bar_container.custom_minimum_size = Vector2(180, 10)
	construction_bar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	construction_row.add_child(construction_bar_container)

	var constr_bg := ColorRect.new()
	constr_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	constr_bg.color = Color(0.1, 0.1, 0.1, 0.8)
	construction_bar_container.add_child(constr_bg)

	_construction_progress_bar = ColorRect.new()
	_construction_progress_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_construction_progress_bar.anchor_right = 0.0
	_construction_progress_bar.color = Color(0.8, 0.7, 0.3)
	construction_bar_container.add_child(_construction_progress_bar)

	_construction_text = Label.new()
	_construction_text.text = "0%"
	_construction_text.add_theme_font_size_override("font_size", 10)
	_construction_text.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_PRIMARY)
	construction_row.add_child(_construction_text)

	# Stats container
	_stats_container = VBoxContainer.new()
	_stats_container.add_theme_constant_override("separation", 4)
	main.add_child(_stats_container)

	# Garrison info
	_garrison_label = Label.new()
	_garrison_label.text = "Garrison: 0/8"
	_garrison_label.add_theme_font_size_override("font_size", 10)
	_garrison_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	_stats_container.add_child(_garrison_label)

	# Defense info
	_defense_label = Label.new()
	_defense_label.text = "Defense: M60 (500m range)"
	_defense_label.add_theme_font_size_override("font_size", 10)
	_defense_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	_stats_container.add_child(_defense_label)


func _on_building_selected(building: Node3D) -> void:
	"""Called when a building is selected"""
	if not is_instance_valid(building):
		_current_building = null
		_construction_zone = null
		visible = false
		return

	_current_building = building

	# Try to find the ConstructionZone parent
	var parent: Node = building.get_parent()
	while parent:
		if parent is ConstructionZone:
			_construction_zone = parent
			break
		parent = parent.get_parent()

	# If the building IS a ConstructionZone
	if building is ConstructionZone:
		_construction_zone = building

	visible = true
	_target_hp_ratio = 1.0
	_display_hp_ratio = 1.0
	_update_display()


func show_building(building: Node3D) -> void:
	"""Manually show building info (for direct API use)"""
	_on_building_selected(building)


func show_construction_zone(zone: ConstructionZone) -> void:
	"""Show info for a construction zone directly"""
	_construction_zone = zone
	_current_building = zone.completed_building if zone.completed_building else zone
	visible = true
	_update_display()


func hide_card() -> void:
	"""Hide the building card"""
	_current_building = null
	_construction_zone = null
	visible = false


func _update_display() -> void:
	if not _construction_zone and not _current_building:
		return

	var zone: ConstructionZone = _construction_zone as ConstructionZone
	if zone:
		_update_from_construction_zone(zone)
	elif _current_building:
		_update_from_building(_current_building)


func _update_from_construction_zone(zone: ConstructionZone) -> void:
	"""Update display from a ConstructionZone"""
	var data: RefCounted = zone.building_data
	if not data:
		return

	# Name and category
	_name_label.text = data.display_name if data else "Unknown Building"
	_category_label.text = _get_category_name(data.category) if data else ""

	# Status
	var status_text: String = "Empty"
	var status_color: Color = MilitaryTheme.COL_TEXT_SECONDARY

	match zone.state:
		ConstructionZone.ZoneState.EMPTY:
			status_text = "Empty"
			status_color = MilitaryTheme.COL_TEXT_SECONDARY
		ConstructionZone.ZoneState.CLEARING:
			status_text = "Clearing..."
			status_color = Color(0.8, 0.7, 0.3)
		ConstructionZone.ZoneState.BUILDING:
			status_text = "Under Construction"
			status_color = Color(0.8, 0.7, 0.3)
		ConstructionZone.ZoneState.COMPLETE:
			if zone.is_destroyed():
				status_text = "Destroyed"
				status_color = MilitaryTheme.COL_HEALTH_LOW
			elif zone.get_health_percent() < 0.5:
				status_text = "Damaged"
				status_color = MilitaryTheme.COL_HEALTH_MID
			else:
				status_text = "Operational"
				status_color = MilitaryTheme.COL_HEALTH_FULL

	_status_label.text = status_text
	_status_label.add_theme_color_override("font_color", status_color)

	# Health bar
	var hp_ratio: float = zone.get_health_percent()
	_target_hp_ratio = hp_ratio
	_hp_bar_fill.color = MilitaryTheme.health_color(hp_ratio)
	_hp_text.text = "%d/%d" % [int(zone.current_health), int(zone.max_health)]

	# Construction progress
	var constr_row: Node = get_node_or_null("VBoxContainer/ConstructionRow")
	if zone.state == ConstructionZone.ZoneState.BUILDING:
		if constr_row:
			constr_row.visible = true
		var progress: float = zone.get_progress_percent() / 100.0
		_construction_progress_bar.anchor_right = progress
		_construction_text.text = "%d%%" % int(zone.get_progress_percent())
	else:
		if constr_row:
			constr_row.visible = false

	# Garrison info
	var garrison: Node = zone.completed_building.get_node_or_null("GarrisonableStructure") if zone.completed_building else null
	if garrison:
		var current: int = garrison.garrisoned_units.size() if garrison.has_method("get") else 0
		var max_garrison: int = garrison.max_infantry if garrison.has_method("get") else 0
		_garrison_label.text = "Garrison: %d/%d" % [current, max_garrison]
		_garrison_label.visible = true
	elif data and data.garrison_capacity > 0:
		_garrison_label.text = "Garrison: 0/%d" % data.garrison_capacity
		_garrison_label.visible = true
	else:
		_garrison_label.visible = false

	# Defense info
	var defense: Node = zone.completed_building.get_node_or_null("DefensiveStructure") if zone.completed_building else null
	if defense:
		var weapon: String = defense.weapon_type if defense.has_method("get") else "unknown"
		var range_m: float = defense.attack_range if defense.has_method("get") else 0.0
		var target_name: String = "None"
		if defense.current_target and is_instance_valid(defense.current_target):
			target_name = defense.current_target.name

		if defense.is_active:
			_defense_label.text = "Defense: %s (%.0fm) - Target: %s" % [weapon.to_upper(), range_m, target_name]
		else:
			_defense_label.text = "Defense: DISABLED"
		_defense_label.visible = true
	elif data and data.auto_attacks:
		_defense_label.text = "Defense: %s (%.0fm)" % [data.defense_weapon.to_upper(), data.attack_range]
		_defense_label.visible = true
	else:
		_defense_label.visible = false


func _update_from_building(building: Node3D) -> void:
	"""Update display from a generic building node"""
	_name_label.text = building.name.replace("_", " ")
	_category_label.text = ""

	# Try to get health
	if building.has_method("get"):
		var current: Variant = building.get("current_health")
		var max_hp: Variant = building.get("max_health")
		if current != null and max_hp != null:
			var hp_ratio: float = float(current) / float(max_hp) if float(max_hp) > 0 else 0.0
			_target_hp_ratio = hp_ratio
			_hp_bar_fill.color = MilitaryTheme.health_color(hp_ratio)
			_hp_text.text = "%d/%d" % [int(current), int(max_hp)]

	# Hide construction progress for completed buildings
	var constr_row: Node = get_node_or_null("VBoxContainer/ConstructionRow")
	if constr_row:
		constr_row.visible = false

	# Check for garrison component
	var garrison: Node = building.get_node_or_null("GarrisonableStructure")
	if garrison:
		var current: int = garrison.garrisoned_units.size()
		var max_garrison: int = garrison.max_infantry
		_garrison_label.text = "Garrison: %d/%d" % [current, max_garrison]
		_garrison_label.visible = true
	else:
		_garrison_label.visible = false

	# Check for defense component
	var defense: Node = building.get_node_or_null("DefensiveStructure")
	if defense:
		var weapon: String = defense.weapon_type
		var range_m: float = defense.attack_range
		_defense_label.text = "Defense: %s (%.0fm)" % [weapon.to_upper(), range_m]
		_defense_label.visible = true
	else:
		_defense_label.visible = false


func _get_category_name(category: int) -> String:
	"""Get display name for building category"""
	# These match BuildingData.BuildingCategory enum
	match category:
		0: return "Firebase Perimeter"
		1: return "Firebase Support"
		2: return "Firebase Living"
		3: return "Firebase Heavy"
		4: return "Vietnamese Village"
		5: return "Airfield"
		6: return "French Colonial"
		7: return "Infrastructure"
		8: return "VC/NVA Special"
		9: return "Ruins"
		10: return "Cham Ruins"
		11: return "Commercial"
		_: return "Structure"
