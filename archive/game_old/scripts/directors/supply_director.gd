extends Node
## SupplyDirector - Manages automated supply logistics
## Handles helicopter schedules, convoy dispatch, and priority allocation

signal helicopter_dispatched
signal helicopter_arrived
signal convoy_dispatched
signal convoy_arrived
signal convoy_ambushed
signal low_supply_warning

# Supply schedule configuration
var air_supply_interval: float = 180.0  # 3 minutes
var ground_supply_interval: float = 300.0  # 5 minutes
var air_supply_amount: int = 50
var ground_supply_amount: int = 150

# Priority allocation (must sum to 1.0)
var priority_ammo: float = 0.6
var priority_materials: float = 0.2
var priority_reinforcements: float = 0.2

# Timers
var air_supply_timer: float = 0.0
var ground_supply_timer: float = 0.0

# State
var active_helicopters: Array = []
var active_convoys: Array = []
var landing_zones: Array[Node3D] = []
var supply_depots: Array[Node3D] = []

# Thresholds
var low_supply_threshold: int = 30


func _ready() -> void:
	# Start timers at halfway point so first supplies arrive sooner
	air_supply_timer = air_supply_interval * 0.5
	ground_supply_timer = ground_supply_interval * 0.5


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	# Update supply timers
	air_supply_timer += delta
	ground_supply_timer += delta

	# Check for scheduled dispatches
	if air_supply_timer >= air_supply_interval:
		_dispatch_helicopter()
		air_supply_timer = 0.0

	if ground_supply_timer >= ground_supply_interval:
		_dispatch_convoy()
		ground_supply_timer = 0.0

	# Check supply levels
	if GameManager.supplies <= low_supply_threshold:
		low_supply_warning.emit()


func _dispatch_helicopter() -> void:
	if landing_zones.is_empty():
		push_warning("SupplyDirector: No landing zones available for helicopter dispatch")
		return

	# Find best LZ (closest to command post, not under fire)
	var best_lz = _find_best_landing_zone()
	if best_lz:
		helicopter_dispatched.emit()
		_spawn_helicopter(best_lz)
		print("SupplyDirector: Helicopter dispatched to LZ")


func _spawn_helicopter(lz: Node3D) -> void:
	var helicopter_scene := load("res://scenes/units/helicopter.tscn") as PackedScene
	if not helicopter_scene:
		push_warning("SupplyDirector: Could not load helicopter scene")
		return

	var helicopter := helicopter_scene.instantiate()

	# Spawn from off-map edge
	var spawn_pos := Vector3(-50, 30, 100)  # West side, high altitude

	# Find helicopter container
	var heli_container: Node = get_tree().current_scene.get_node_or_null("GameWorld/SupplyRoutes/Helicopters")
	if heli_container:
		heli_container.add_child(helicopter)
	else:
		get_tree().current_scene.add_child(helicopter)

	# Setup helicopter mission
	if helicopter.has_method("setup"):
		helicopter.setup(lz, spawn_pos, air_supply_amount)

	active_helicopters.append(helicopter)

	# Connect signals
	helicopter.helicopter_destroyed.connect(_on_helicopter_destroyed.bind(helicopter))
	helicopter.supplies_delivered.connect(_on_supplies_delivered)


func _dispatch_convoy() -> void:
	convoy_dispatched.emit()
	_spawn_convoy()
	print("SupplyDirector: Convoy dispatched from rear area")


func _spawn_convoy() -> void:
	var convoy_scene := load("res://scenes/units/convoy.tscn") as PackedScene
	if not convoy_scene:
		push_warning("SupplyDirector: Could not load convoy scene")
		return

	var convoy := convoy_scene.instantiate()

	# Spawn from map edge (south side, simulating rear area road)
	var spawn_pos := Vector3(100, 0, 220)  # South edge

	# Target is command post or nearest supply depot
	var target_pos := Vector3(100, 0, 100)  # Default firebase center
	if GameManager.command_post:
		target_pos = GameManager.command_post.global_position

	# Find convoy container
	var convoy_container: Node = get_tree().current_scene.get_node_or_null("GameWorld/SupplyRoutes/Convoys")
	if convoy_container:
		convoy_container.add_child(convoy)
	else:
		get_tree().current_scene.add_child(convoy)

	# Setup convoy mission
	if convoy.has_method("setup"):
		convoy.setup(spawn_pos, target_pos, ground_supply_amount)

	active_convoys.append(convoy)

	# Connect signals
	convoy.convoy_destroyed.connect(_on_convoy_destroyed.bind(convoy))
	convoy.supplies_delivered.connect(_on_convoy_supplies_delivered)
	convoy.convoy_ambushed.connect(_on_convoy_ambushed)


func _find_best_landing_zone() -> Node3D:
	if landing_zones.is_empty():
		return null

	# For now, return first available LZ
	# TODO: Evaluate threat levels, distance to HQ
	return landing_zones[0]


func register_landing_zone(lz: Node3D) -> void:
	if lz not in landing_zones:
		landing_zones.append(lz)


func unregister_landing_zone(lz: Node3D) -> void:
	landing_zones.erase(lz)


func register_supply_depot(depot: Node3D) -> void:
	if depot not in supply_depots:
		supply_depots.append(depot)
		# Increase max storage
		GameManager.max_supply_storage += 100


func unregister_supply_depot(depot: Node3D) -> void:
	supply_depots.erase(depot)
	GameManager.max_supply_storage -= 100


func get_time_until_air_supply() -> float:
	return air_supply_interval - air_supply_timer


func get_time_until_ground_supply() -> float:
	return ground_supply_interval - ground_supply_timer


func set_priorities(ammo: float, materials: float, reinforcements: float) -> void:
	var total := ammo + materials + reinforcements
	if total > 0:
		priority_ammo = ammo / total
		priority_materials = materials / total
		priority_reinforcements = reinforcements / total


func _on_helicopter_destroyed(helicopter: Node) -> void:
	active_helicopters.erase(helicopter)
	# Delay next helicopter dispatch as penalty
	air_supply_timer = -60.0  # Extra minute delay


func _on_supplies_delivered(amount: int) -> void:
	helicopter_arrived.emit()


func _on_convoy_destroyed(convoy: Node) -> void:
	active_convoys.erase(convoy)
	# Delay next convoy as penalty
	ground_supply_timer = -120.0  # Extra 2 minute delay


func _on_convoy_supplies_delivered(amount: int) -> void:
	convoy_arrived.emit()


func _on_convoy_ambushed() -> void:
	convoy_ambushed.emit()
