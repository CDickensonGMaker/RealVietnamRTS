extends PanelContainer
class_name BuildMenu
## Build Menu UI - Allows player to construct buildings at firebases
## Integrates with JobSystem for construction job creation

signal building_selected(building_type: int)
signal build_job_created(job: Resource)  # Emits the UnifiedJob created
signal menu_closed()

const BuildingData = preload("res://firebase_system/building_data.gd")
const Firebase = preload("res://firebase_system/firebase.gd")

## Currently selected firebase
var selected_firebase: Node3D = null

## Placement target position (set before opening menu or via click)
var placement_position: Vector3 = Vector3.INF

## UI References
var _title_label: Label
var _supply_label: Label
var _building_list: VBoxContainer
var _close_button: Button
var _building_buttons: Dictionary = {}  # BuildingType -> Button
var _status_label: Label  # Shows validation errors


func _ready() -> void:
	_create_ui()
	visible = false


func _create_ui() -> void:
	custom_minimum_size = Vector2(280, 400)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# Header
	var header := HBoxContainer.new()
	main_vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Build Menu"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.custom_minimum_size = Vector2(30, 30)
	_close_button.pressed.connect(_on_close_pressed)
	header.add_child(_close_button)

	# Supply display
	_supply_label = Label.new()
	_supply_label.text = "Supply: 0/0"
	main_vbox.add_child(_supply_label)

	# Status label (shows errors/success)
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(_status_label)

	# Separator
	var sep := HSeparator.new()
	main_vbox.add_child(sep)

	# Categories
	_create_category(main_vbox, "Perimeter", [
		BuildingData.BuildingType.SANDBAG_LIGHT,
		BuildingData.BuildingType.SANDBAG_HEAVY,
		BuildingData.BuildingType.BUNKER,
		BuildingData.BuildingType.MACHINE_GUN_NEST,
		BuildingData.BuildingType.MORTAR_PIT,
		BuildingData.BuildingType.WIRE_OBSTACLE,
		BuildingData.BuildingType.WATCHTOWER,
	])

	_create_category(main_vbox, "Support", [
		BuildingData.BuildingType.HELIPAD,
		BuildingData.BuildingType.AMMO_BUNKER,
		BuildingData.BuildingType.MEDICAL_STATION,
		BuildingData.BuildingType.TOC,
		BuildingData.BuildingType.COMMO_BUNKER,
	])

	_create_category(main_vbox, "Heavy", [
		BuildingData.BuildingType.ARTILLERY_PIT,
		BuildingData.BuildingType.TANK_REVETMENT,
	])


func _create_category(parent: VBoxContainer, title: String, building_types: Array) -> void:
	var category_label := Label.new()
	category_label.text = "— " + title + " —"
	category_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	category_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5))
	parent.add_child(category_label)

	for building_type in building_types:
		var data: BuildingData = BuildingData.get_building_data(building_type)

		var btn := Button.new()
		btn.text = "%s (%d)" % [data.display_name, data.supply_cost]
		btn.tooltip_text = data.description
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_building_button_pressed.bind(building_type))
		parent.add_child(btn)

		_building_buttons[building_type] = btn


func show_for_firebase(firebase: Node3D) -> void:
	if not firebase is Firebase:
		return

	selected_firebase = firebase
	_title_label.text = firebase.firebase_name + " - Build"
	_update_supply_display()
	_update_button_states()
	visible = true


func _update_supply_display() -> void:
	if selected_firebase and selected_firebase is Firebase:
		_supply_label.text = "Supply: %d / %d" % [
			int(selected_firebase.supply_level),
			int(selected_firebase.max_supply)
		]


func _update_button_states() -> void:
	if not selected_firebase or not selected_firebase is Firebase:
		return

	var job_system = get_node_or_null("/root/JobSystem")

	for building_type in _building_buttons:
		var btn: Button = _building_buttons[building_type]
		var data: BuildingData = BuildingData.get_building_data(building_type)

		var can_build: bool = true
		var reason: String = ""

		# Check supply
		if selected_firebase.supply_level < data.supply_cost:
			can_build = false
			reason = "Not enough supply (%d needed)" % data.supply_cost

		# Check firebase level
		if data.requires_firebase_level > selected_firebase.level:
			can_build = false
			reason = "Firebase level too low"

		# Check placement validation via JobSystem (if position is set)
		if can_build and job_system and placement_position != Vector3.INF:
			var validation: Dictionary = job_system.validate_placement(
				placement_position, data.footprint_size, building_type
			)
			if not validation.valid:
				can_build = false
				reason = validation.message

		btn.disabled = not can_build
		if not can_build and reason != "":
			btn.tooltip_text = data.description + "\n[" + reason + "]"
		else:
			btn.tooltip_text = data.description


func _on_building_button_pressed(building_type: int) -> void:
	if not selected_firebase:
		return

	# Emit legacy signal for compatibility
	building_selected.emit(building_type)

	# Try to create job through JobSystem
	var job = create_build_job_at_position(building_type, placement_position)
	if job:
		build_job_created.emit(job)
		_show_status("Building job created", Color.GREEN)
	else:
		_show_status("Cannot build here", Color.RED)

	# Update UI after build attempt
	_update_supply_display()
	_update_button_states()


func create_build_job_at_position(building_type: int, position: Vector3) -> Resource:
	"""Create a build job at the specified position using JobSystem.
	Returns the job or null if creation failed."""
	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		push_warning("[BuildMenu] JobSystem not found")
		return null

	# Get building data for footprint
	var data: BuildingData = BuildingData.get_building_data(building_type)
	if not data:
		return null

	# Use firebase position if no specific position set
	var build_pos: Vector3 = position
	if build_pos == Vector3.INF and selected_firebase:
		# Find empty position near firebase (simple radial search)
		build_pos = _find_empty_position(selected_firebase.global_position, data.footprint_size)

	if build_pos == Vector3.INF:
		_show_status("No valid placement position", Color.RED)
		return null

	# Create job through JobSystem (handles validation and supply)
	var job = job_system.create_build_job(build_pos, building_type, 0.0, data.footprint_size)
	return job


func _find_empty_position(center: Vector3, footprint: Vector2) -> Vector3:
	"""Find an empty position near the center for building placement"""
	var job_system = get_node_or_null("/root/JobSystem")
	if not job_system:
		return center  # Fall back to center

	# Try positions in expanding rings
	var ring_offsets := [
		Vector3(5, 0, 0), Vector3(-5, 0, 0), Vector3(0, 0, 5), Vector3(0, 0, -5),
		Vector3(10, 0, 0), Vector3(-10, 0, 0), Vector3(0, 0, 10), Vector3(0, 0, -10),
		Vector3(7, 0, 7), Vector3(-7, 0, 7), Vector3(7, 0, -7), Vector3(-7, 0, -7),
	]

	for offset in ring_offsets:
		var test_pos := center + offset
		var validation: Dictionary = job_system.validate_placement(test_pos, footprint)
		if validation.valid:
			return test_pos

	# No valid position found
	return Vector3.INF


func set_placement_position(pos: Vector3) -> void:
	"""Set the position where buildings will be placed"""
	placement_position = pos
	_update_button_states()


func _show_status(message: String, color: Color) -> void:
	"""Show a temporary status message"""
	if _status_label:
		_status_label.text = message
		_status_label.add_theme_color_override("font_color", color)
		# Clear after 2 seconds
		get_tree().create_timer(2.0).timeout.connect(func(): _status_label.text = "")


func _on_close_pressed() -> void:
	visible = false
	selected_firebase = null
	menu_closed.emit()


func _process(_delta: float) -> void:
	if visible and selected_firebase:
		_update_supply_display()
		_update_button_states()
