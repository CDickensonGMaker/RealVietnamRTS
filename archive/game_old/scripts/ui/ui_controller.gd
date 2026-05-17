extends Control
## UIController - Main UI manager
## Connects all UI panels to game systems

# Panel references
@onready var supply_label: Label = $"../SupplyPanel/VBox/SupplyLabel"
@onready var air_supply_label: Label = $"../SupplyPanel/VBox/NextAirLabel"
@onready var ground_supply_label: Label = $"../SupplyPanel/VBox/NextGroundLabel"
@onready var time_label: Label = $"../SupplyPanel/VBox/TimeLabel"
@onready var squad_panel: PanelContainer = $"../SquadPanel"
@onready var build_menu: PanelContainer = $"../BuildMenu"
@onready var alert_system: Control = $"../AlertSystem"
@onready var minimap_container: SubViewportContainer = $"../Minimap"

# Build menu
var build_buttons: Dictionary = {}
var build_system: Node
var _setup_complete: bool = false

# Selection
var selection_manager: Node


func _ready() -> void:
	# Wait for scene to be ready
	await get_tree().process_frame
	setup()


func setup() -> void:
	if _setup_complete:
		return
	_setup_complete = true

	_connect_signals()
	_setup_build_menu()
	_setup_squad_panel()

	# Find systems
	selection_manager = get_node_or_null("/root/Main/SelectionManager")
	build_system = get_node_or_null("/root/Main/BuildSystem")

	if selection_manager:
		selection_manager.selection_changed.connect(_on_selection_changed)


func _process(_delta: float) -> void:
	_update_supply_display()
	_update_time_display()


func _connect_signals() -> void:
	GameManager.supplies_changed.connect(_on_supplies_changed)
	GameManager.game_ended.connect(_on_game_ended)

	SupplyDirector.low_supply_warning.connect(_on_low_supply_warning)
	SupplyDirector.helicopter_dispatched.connect(_on_helicopter_dispatched)
	SupplyDirector.convoy_dispatched.connect(_on_convoy_dispatched)


func _update_supply_display() -> void:
	if supply_label:
		supply_label.text = "Supplies: %d / %d" % [GameManager.supplies, GameManager.max_supply_storage]

	if air_supply_label:
		var air_time: float = SupplyDirector.get_time_until_air_supply()
		var air_min: int = int(air_time) / 60
		var air_sec: int = int(air_time) % 60
		air_supply_label.text = "Air Resupply: %d:%02d" % [air_min, air_sec]

	if ground_supply_label:
		var ground_time: float = SupplyDirector.get_time_until_ground_supply()
		var ground_min: int = int(ground_time) / 60
		var ground_sec: int = int(ground_time) % 60
		ground_supply_label.text = "Convoy: %d:%02d" % [ground_min, ground_sec]


func _update_time_display() -> void:
	if time_label:
		time_label.text = "Time: " + GameManager.get_formatted_time()


func _setup_build_menu() -> void:
	if not build_menu:
		return

	# Clear existing children except the container structure
	var vbox: Node = build_menu.get_node_or_null("VBox")
	if not vbox:
		vbox = VBoxContainer.new()
		vbox.name = "VBox"
		build_menu.add_child(vbox)

	# Add header
	var header := Label.new()
	header.text = "BUILD"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	# Add separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Create grid for build buttons
	var grid := GridContainer.new()
	grid.columns = 2
	grid.name = "BuildGrid"
	vbox.add_child(grid)

	# Add build buttons for each structure type
	var structures: Array[String] = ["sandbag", "foxhole", "bunker", "mg_nest", "mortar_pit", "wire", "lz", "supply_depot"]
	var structure_names := {
		"sandbag": "Sandbag",
		"foxhole": "Foxhole",
		"bunker": "Bunker",
		"mg_nest": "MG Nest",
		"mortar_pit": "Mortar",
		"wire": "Wire",
		"lz": "LZ",
		"supply_depot": "Depot"
	}

	for struct_type in structures:
		var btn := Button.new()
		btn.name = struct_type + "_btn"
		btn.text = structure_names.get(struct_type, struct_type)
		btn.custom_minimum_size = Vector2(70, 30)
		btn.pressed.connect(_on_build_button_pressed.bind(struct_type))
		grid.add_child(btn)
		build_buttons[struct_type] = btn


func _setup_squad_panel() -> void:
	if not squad_panel:
		return

	# Create squad info display
	var vbox: Node = squad_panel.get_node_or_null("VBox")
	if not vbox:
		vbox = VBoxContainer.new()
		vbox.name = "VBox"
		squad_panel.add_child(vbox)

	# Header
	var header := Label.new()
	header.name = "SquadHeader"
	header.text = "NO SELECTION"
	vbox.add_child(header)

	# Health bar
	var health_bar := ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.max_value = 100
	health_bar.value = 100
	health_bar.custom_minimum_size.y = 20
	vbox.add_child(health_bar)

	# Ammo bar
	var ammo_bar := ProgressBar.new()
	ammo_bar.name = "AmmoBar"
	ammo_bar.max_value = 100
	ammo_bar.value = 100
	ammo_bar.custom_minimum_size.y = 20
	vbox.add_child(ammo_bar)

	# Orders buttons
	var orders_container := HBoxContainer.new()
	orders_container.name = "OrdersContainer"
	vbox.add_child(orders_container)

	var orders: Array[String] = ["Guard", "Patrol", "Attack"]
	for order in orders:
		var btn := Button.new()
		btn.text = order
		btn.pressed.connect(_on_order_button_pressed.bind(order.to_lower()))
		orders_container.add_child(btn)


func _on_selection_changed(selected_units: Array) -> void:
	if not squad_panel:
		return

	var vbox: Node = squad_panel.get_node_or_null("VBox")
	if not vbox:
		return

	var header: Label = vbox.get_node_or_null("SquadHeader")
	var health_bar: ProgressBar = vbox.get_node_or_null("HealthBar")
	var ammo_bar: ProgressBar = vbox.get_node_or_null("AmmoBar")

	if selected_units.is_empty():
		if header:
			header.text = "NO SELECTION"
		if health_bar:
			health_bar.value = 0
		if ammo_bar:
			ammo_bar.value = 0
		return

	# Show first selected unit info
	var unit = selected_units[0]

	if header:
		if unit.has_method("get") and unit.get("squad_name"):
			header.text = "%s (%d selected)" % [unit.squad_name, selected_units.size()]
		else:
			header.text = "%d units selected" % selected_units.size()

	if health_bar and unit.has_method("get_health_percent"):
		health_bar.value = unit.get_health_percent() * 100

	if ammo_bar and unit.has_method("get_ammo_percent"):
		ammo_bar.value = unit.get_ammo_percent() * 100


func _on_build_button_pressed(structure_type: String) -> void:
	if not build_system:
		build_system = get_node_or_null("/root/Main/BuildSystem")

	if build_system and build_system.has_method("start_placement"):
		build_system.start_placement(structure_type)


func _on_order_button_pressed(order: String) -> void:
	if not selection_manager:
		return

	var selected: Array = selection_manager.get_selected_units()
	for unit: Node3D in selected:
		match order:
			"guard":
				if unit.has_method("set_standing_order"):
					unit.set_standing_order(unit.StandingOrder.GUARD)
			"patrol":
				# Would need patrol waypoint system
				pass
			"attack":
				if unit.has_method("set_standing_order"):
					unit.set_standing_order(unit.StandingOrder.AGGRESSIVE)


func _on_supplies_changed(new_amount: int) -> void:
	# Update is handled in _process
	pass


func _on_low_supply_warning() -> void:
	_show_alert("LOW SUPPLIES!", Color.RED)


func _on_helicopter_dispatched() -> void:
	_show_alert("Helicopter inbound", Color.GREEN)


func _on_convoy_dispatched() -> void:
	_show_alert("Convoy dispatched", Color.YELLOW)


func _on_game_ended(victory: bool) -> void:
	if victory:
		_show_alert("VICTORY!", Color.GREEN, 10.0)
	else:
		_show_alert("DEFEAT", Color.RED, 10.0)


func _show_alert(message: String, color: Color = Color.WHITE, duration: float = 3.0) -> void:
	if not alert_system:
		return

	var alert_label := Label.new()
	alert_label.text = message
	alert_label.add_theme_color_override("font_color", color)
	alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alert_label.add_theme_font_size_override("font_size", 24)
	alert_system.add_child(alert_label)

	# Fade out and remove
	var tween := create_tween()
	tween.tween_interval(duration - 1.0)
	tween.tween_property(alert_label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(alert_label.queue_free)
