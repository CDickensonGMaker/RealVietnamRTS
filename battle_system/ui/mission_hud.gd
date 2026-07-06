extends Control
class_name MissionHUD
## MissionHUD - Displays objectives and mission status
## Positioned at top-right of screen, shows primary/secondary objectives

const MissionObjective = preload("res://campaign/mission_objective.gd")
const MilitaryTheme = preload("res://battle_system/ui/military_theme.gd")

## UI Components
var _container: VBoxContainer
var _mission_label: Label
var _time_label: Label
var _objectives_container: VBoxContainer
var _objective_items: Dictionary = {}  # objective_id -> HBoxContainer

## Current mission reference
var _current_mission = null

## Styling
const COMPLETE_COLOR := Color(0.3, 0.8, 0.3)  # Green
const FAILED_COLOR := Color(0.8, 0.3, 0.3)  # Red
const ACTIVE_COLOR := Color(0.9, 0.9, 0.9)  # White
const SECONDARY_COLOR := Color(0.7, 0.7, 0.7)  # Gray


func _ready() -> void:
	_create_ui()
	visible = false  # Hidden until mission starts


func _process(_delta: float) -> void:
	if visible and _current_mission:
		_update_time()


func _create_ui() -> void:
	# Main container - top left (per ui-vision.md concept; top-right belongs
	# to minimap + firebase panel)
	_container = VBoxContainer.new()
	_container.name = "MissionContainer"
	add_child(_container)

	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = 10
	offset_right = 320
	offset_top = 10
	offset_bottom = 300

	# Background panel
	var panel := PanelContainer.new()
	panel.name = "Background"
	_container.add_child(panel)
	panel.add_theme_stylebox_override("panel", MilitaryTheme.create_panel_stylebox())

	# Inner container
	var inner := VBoxContainer.new()
	inner.name = "Inner"
	panel.add_child(inner)

	# Mission name label
	_mission_label = Label.new()
	_mission_label.name = "MissionName"
	_mission_label.text = "MISSION"
	_mission_label.add_theme_font_size_override("font_size", 18)
	_mission_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_HIGHLIGHT)
	inner.add_child(_mission_label)

	# Time label
	_time_label = Label.new()
	_time_label.name = "TimeRemaining"
	_time_label.text = ""
	_time_label.add_theme_font_size_override("font_size", 14)
	_time_label.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_PRIMARY)
	inner.add_child(_time_label)

	# Separator
	var sep := HSeparator.new()
	inner.add_child(sep)

	# Objectives header
	var obj_header := Label.new()
	obj_header.text = "OBJECTIVES"
	obj_header.add_theme_font_size_override("font_size", 14)
	obj_header.add_theme_color_override("font_color", MilitaryTheme.COL_TEXT_SECONDARY)
	inner.add_child(obj_header)

	# Objectives container
	_objectives_container = VBoxContainer.new()
	_objectives_container.name = "Objectives"
	inner.add_child(_objectives_container)


## Show mission objectives
func show_mission(mission) -> void:
	_current_mission = mission
	visible = true

	# Update mission name
	_mission_label.text = mission.mission_name.to_upper()

	# Clear old objectives
	for child in _objectives_container.get_children():
		child.queue_free()
	_objective_items.clear()

	# Add primary objectives
	for obj in mission.primary_objectives:
		if obj and obj.is_revealed:
			_add_objective_item(obj, true)

	# Add secondary objectives
	for obj in mission.secondary_objectives:
		if obj and obj.is_revealed:
			_add_objective_item(obj, false)


func _add_objective_item(obj: MissionObjective, is_primary: bool) -> void:
	var item := HBoxContainer.new()
	item.name = "Obj_" + obj.objective_id

	# Checkbox/status indicator
	var status := Label.new()
	status.name = "Status"
	status.text = "[ ]"
	status.add_theme_font_size_override("font_size", 14)
	status.custom_minimum_size.x = 30
	item.add_child(status)

	# Objective name and progress
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = obj.objective_name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", ACTIVE_COLOR if is_primary else SECONDARY_COLOR)
	info.add_child(name_label)

	var progress_label := Label.new()
	progress_label.name = "Progress"
	progress_label.text = obj.get_status_text()
	progress_label.add_theme_font_size_override("font_size", 12)
	progress_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	info.add_child(progress_label)

	item.add_child(info)

	_objectives_container.add_child(item)
	_objective_items[obj.objective_id] = item

	# Set initial state
	_update_objective_visual(obj)


## Update objective display
func update_objective(obj: MissionObjective) -> void:
	_update_objective_visual(obj)


func _update_objective_visual(obj: MissionObjective) -> void:
	if not _objective_items.has(obj.objective_id):
		return

	var item: HBoxContainer = _objective_items[obj.objective_id]
	var status: Label = item.get_node("Status")
	var name_label: Label = item.get_node("VBoxContainer/Name") if item.has_node("VBoxContainer/Name") else null
	var progress_label: Label = item.get_node("VBoxContainer/Progress") if item.has_node("VBoxContainer/Progress") else null

	# Find labels by iterating (more reliable)
	for child in item.get_children():
		if child is Label and child.name == "Status":
			status = child
		elif child is VBoxContainer:
			for subchild in child.get_children():
				if subchild is Label:
					if subchild.name == "Name":
						name_label = subchild
					elif subchild.name == "Progress":
						progress_label = subchild

	if obj.is_completed:
		if status:
			status.text = "[X]"
			status.add_theme_color_override("font_color", COMPLETE_COLOR)
		if name_label:
			name_label.add_theme_color_override("font_color", COMPLETE_COLOR)
		if progress_label:
			progress_label.text = "COMPLETE"
			progress_label.add_theme_color_override("font_color", COMPLETE_COLOR)
	elif obj.is_failed:
		if status:
			status.text = "[!]"
			status.add_theme_color_override("font_color", FAILED_COLOR)
		if name_label:
			name_label.add_theme_color_override("font_color", FAILED_COLOR)
		if progress_label:
			progress_label.text = "FAILED"
			progress_label.add_theme_color_override("font_color", FAILED_COLOR)
	else:
		if status:
			status.text = "[ ]"
		if progress_label:
			progress_label.text = obj.get_status_text()


func _update_time() -> void:
	if not _current_mission:
		_time_label.text = ""
		return

	var remaining: float = _current_mission.get_time_remaining()
	if remaining < 0:
		_time_label.text = ""
		return

	var minutes: int = int(remaining / 60.0)
	var seconds: int = int(remaining) % 60

	_time_label.text = "Time: %02d:%02d" % [minutes, seconds]

	# Color based on urgency
	if remaining < 300:  # Less than 5 minutes
		_time_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	elif remaining < 600:  # Less than 10 minutes
		_time_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	else:
		_time_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))


## Hide the HUD
func hide_mission() -> void:
	visible = false
	_current_mission = null
