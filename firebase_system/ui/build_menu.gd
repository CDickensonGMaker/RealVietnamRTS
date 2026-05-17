extends PanelContainer
class_name BuildMenu
## Build Menu UI - Allows player to construct buildings at firebases

signal building_selected(building_type: int)
signal menu_closed()

const BuildingData = preload("res://firebase_system/building_data.gd")
const Firebase = preload("res://firebase_system/firebase.gd")

## Currently selected firebase
var selected_firebase: Node3D = null

## UI References
var _title_label: Label
var _supply_label: Label
var _building_list: VBoxContainer
var _close_button: Button
var _building_buttons: Dictionary = {}  # BuildingType -> Button


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

	for building_type in _building_buttons:
		var btn: Button = _building_buttons[building_type]
		var data: BuildingData = BuildingData.get_building_data(building_type)

		var can_build: bool = true
		var reason: String = ""

		# Check supply
		if selected_firebase.supply_level < data.supply_cost:
			can_build = false
			reason = "Not enough supply"

		# Check firebase level
		if data.requires_firebase_level > selected_firebase.level:
			can_build = false
			reason = "Firebase level too low"

		# Check for empty zone
		if selected_firebase.get_empty_zone() == null:
			can_build = false
			reason = "No empty zones"

		btn.disabled = not can_build
		if not can_build and reason != "":
			btn.tooltip_text = data.description + "\n[" + reason + "]"
		else:
			btn.tooltip_text = data.description


func _on_building_button_pressed(building_type: int) -> void:
	if not selected_firebase:
		return

	building_selected.emit(building_type)

	# Update UI after build
	_update_supply_display()
	_update_button_states()


func _on_close_pressed() -> void:
	visible = false
	selected_firebase = null
	menu_closed.emit()


func _process(_delta: float) -> void:
	if visible and selected_firebase:
		_update_supply_display()
		_update_button_states()
