extends Node
class_name ConvoyManager

## Convoy Manager - Handles ground convoy operations
## Convoys transport supplies and troops between firebases

signal convoy_created(convoy: Convoy)
signal convoy_departed(convoy: Convoy)
signal convoy_arrived(convoy: Convoy)
signal convoy_ambushed(convoy: Convoy, attacker: Node3D)
signal convoy_destroyed(convoy: Convoy)

enum ConvoyState { LOADING, EN_ROUTE, UNLOADING, ARRIVED, AMBUSHED, DESTROYED }
enum ConvoyType { SUPPLY, TROOP_TRANSPORT, MIXED }

## Active convoys
var active_convoys: Array[Convoy] = []

## Configuration
@export var convoy_speed: float = 8.0  # m/s (~30 km/h)
@export var auto_resupply_enabled: bool = true
@export var auto_resupply_interval: float = 180.0  # 3 minutes between checks
@export var low_supply_threshold: float = 0.3  # 30% supply triggers resupply
@export var supply_per_convoy: float = 200.0  # Amount delivered per convoy

## Auto-scheduling state
var _resupply_timer: float = 0.0
var _supply_depot: Node3D = null  # Main supply depot (rear base)


class Convoy:
	var id: int
	var convoy_type: int
	var state: int
	var vehicles: Array[Node3D]
	var cargo_troops: Array[Node3D]
	var supply_amount: float
	var origin: Node3D
	var destination: Node3D
	var current_position: Vector3
	var route: Array[Vector3]
	var route_index: int
	var health: float
	var max_health: float

	static var _next_id: int = 0

	func _init() -> void:
		id = _next_id
		_next_id += 1
		vehicles = []
		cargo_troops = []
		route = []
		route_index = 0
		health = 300.0
		max_health = 300.0
		state = ConvoyState.LOADING


func _ready() -> void:
	# Add to group so SupplyDepot can find us
	add_to_group("convoy_managers")

	# Find or create supply depot
	call_deferred("_find_supply_depot")
	print("[ConvoyManager] Initialized - Auto-resupply: %s" % ("ON" if auto_resupply_enabled else "OFF"))


func _process(delta: float) -> void:
	_update_convoys(delta)

	# Auto-resupply check
	if auto_resupply_enabled:
		_resupply_timer += delta
		if _resupply_timer >= auto_resupply_interval:
			_resupply_timer = 0.0
			_check_firebase_supply_needs()


func _find_supply_depot() -> void:
	"""Find the supply depot (rear base)"""
	# Look for a node named "SupplyDepot" or tagged as such
	var depots: Array[Node] = get_tree().get_nodes_in_group("supply_depots")
	if not depots.is_empty():
		_supply_depot = depots[0] as Node3D
		return

	# Fallback: create a virtual depot at map edge
	_supply_depot = Node3D.new()
	_supply_depot.name = "VirtualSupplyDepot"
	_supply_depot.position = Vector3(-500, 0, 0)  # Off-map to the rear
	get_tree().current_scene.add_child(_supply_depot)
	_supply_depot.add_to_group("supply_depots")


func _check_firebase_supply_needs() -> void:
	"""Check all firebases and dispatch convoys to those with low supply"""
	if not _supply_depot:
		return

	var firebases: Array[Node] = get_tree().get_nodes_in_group("firebases")

	for fb in firebases:
		if not is_instance_valid(fb) or not fb is Node3D:
			continue

		# Check if firebase needs supply
		var needs_supply: bool = false
		var supply_ratio: float = 1.0

		if fb.has_method("get") and fb.get("supply_level") != null and fb.get("max_supply") != null:
			supply_ratio = fb.supply_level / fb.max_supply if fb.max_supply > 0 else 1.0
			needs_supply = supply_ratio < low_supply_threshold

		if not needs_supply:
			continue

		# Check if a convoy is already en route
		var convoy_en_route: bool = false
		for convoy in active_convoys:
			if convoy.destination == fb and convoy.state == ConvoyState.EN_ROUTE:
				convoy_en_route = true
				break

		if convoy_en_route:
			continue

		# Dispatch supply convoy
		var convoy := create_convoy(_supply_depot, fb as Node3D, ConvoyType.SUPPLY)
		load_supplies(convoy, supply_per_convoy)
		dispatch_convoy(convoy)

		print("[ConvoyManager] Auto-dispatched supply convoy to %s (supply at %.0f%%)" % [
			fb.name if fb.has_method("get") else "Firebase",
			supply_ratio * 100.0
		])


func _update_convoys(delta: float) -> void:
	"""Update all active convoys"""
	var completed: Array[Convoy] = []

	for convoy in active_convoys:
		match convoy.state:
			ConvoyState.EN_ROUTE:
				_move_convoy(convoy, delta)
			ConvoyState.ARRIVED:
				completed.append(convoy)

	for convoy in completed:
		_complete_convoy(convoy)
		active_convoys.erase(convoy)


func _move_convoy(convoy: Convoy, delta: float) -> void:
	"""Move convoy along route"""
	if convoy.route_index >= convoy.route.size():
		# Reached destination
		convoy.state = ConvoyState.ARRIVED
		convoy_arrived.emit(convoy)

		if BattleSignals and convoy.destination:
			BattleSignals.convoy_arrived.emit(convoy, convoy.destination)
		return

	var target: Vector3 = convoy.route[convoy.route_index]
	var direction: Vector3 = (target - convoy.current_position).normalized()
	var distance: float = convoy.current_position.distance_to(target)
	var move_dist: float = convoy_speed * delta

	if move_dist >= distance:
		convoy.current_position = target
		convoy.route_index += 1
	else:
		convoy.current_position += direction * move_dist

	# Update vehicle positions
	_update_vehicle_positions(convoy)


func _update_vehicle_positions(convoy: Convoy) -> void:
	"""Update positions of vehicles in convoy"""
	var spacing: float = 5.0

	for i in convoy.vehicles.size():
		var vehicle: Node3D = convoy.vehicles[i]
		if is_instance_valid(vehicle):
			# Trail behind convoy position
			var offset: float = float(i) * spacing
			var back_dir: Vector3 = Vector3.BACK

			if convoy.route_index > 0 and convoy.route_index < convoy.route.size():
				var prev: Vector3 = convoy.route[convoy.route_index - 1]
				var curr: Vector3 = convoy.current_position
				back_dir = (prev - curr).normalized()

			vehicle.global_position = convoy.current_position + back_dir * offset


func _complete_convoy(convoy: Convoy) -> void:
	"""Handle convoy arrival"""
	# Unload troops
	if not convoy.cargo_troops.is_empty():
		var unload_pos: Vector3 = convoy.destination.global_position if convoy.destination else convoy.current_position

		for i in convoy.cargo_troops.size():
			var troop: Node3D = convoy.cargo_troops[i]
			if is_instance_valid(troop):
				var offset := Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
				troop.global_position = unload_pos + offset
				troop.visible = true
				troop.set_physics_process(true)

	# Deliver supplies
	if convoy.supply_amount > 0 and convoy.destination:
		if convoy.destination.has_method("add_supply"):
			convoy.destination.add_supply(convoy.supply_amount)

		if BattleSignals:
			BattleSignals.supply_delivered.emit(convoy.destination, convoy.supply_amount)

	# Clean up vehicles
	for vehicle in convoy.vehicles:
		if is_instance_valid(vehicle):
			vehicle.queue_free()

	print("[ConvoyManager] Convoy %d arrived at destination" % convoy.id)


## Public API

func create_convoy(
	origin: Node3D,
	destination: Node3D,
	convoy_type: int = ConvoyType.SUPPLY
) -> Convoy:
	"""Create a new convoy"""
	var convoy := Convoy.new()
	convoy.convoy_type = convoy_type
	convoy.origin = origin
	convoy.destination = destination

	if origin:
		convoy.current_position = origin.global_position

	# Generate route (simple straight line for now)
	convoy.route = _generate_route(origin, destination)

	# Create placeholder vehicles
	_create_convoy_vehicles(convoy)

	active_convoys.append(convoy)
	convoy_created.emit(convoy)

	return convoy


func _generate_route(origin: Node3D, destination: Node3D) -> Array[Vector3]:
	"""Generate route between two points"""
	var route: Array[Vector3] = []

	var start: Vector3 = origin.global_position if origin else Vector3.ZERO
	var end: Vector3 = destination.global_position if destination else Vector3.ZERO

	# Simple waypoints along path
	var segments: int = 5
	for i in range(1, segments + 1):
		var t: float = float(i) / float(segments)
		route.append(start.lerp(end, t))

	return route


func _create_convoy_vehicles(convoy: Convoy) -> void:
	"""Create visual vehicles for convoy"""
	var vehicle_count: int = 3

	match convoy.convoy_type:
		ConvoyType.SUPPLY:
			vehicle_count = 3
		ConvoyType.TROOP_TRANSPORT:
			vehicle_count = 4
		ConvoyType.MIXED:
			vehicle_count = 5

	for i in vehicle_count:
		var vehicle := _create_vehicle_mesh()
		vehicle.name = "Convoy%d_Vehicle%d" % [convoy.id, i]
		get_tree().current_scene.add_child(vehicle)
		convoy.vehicles.append(vehicle)


func _create_vehicle_mesh() -> Node3D:
	"""Create a placeholder vehicle"""
	var vehicle := Node3D.new()

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.5, 4.0)
	mesh.mesh = box
	mesh.position.y = 0.75

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.4, 0.25)  # Olive drab
	mesh.material_override = mat

	vehicle.add_child(mesh)
	return vehicle


func dispatch_convoy(convoy: Convoy) -> void:
	"""Start convoy movement"""
	if convoy.state == ConvoyState.LOADING:
		convoy.state = ConvoyState.EN_ROUTE
		convoy_departed.emit(convoy)

		if BattleSignals:
			BattleSignals.convoy_departed.emit(convoy)

		print("[ConvoyManager] Convoy %d departed" % convoy.id)


func load_troops(convoy: Convoy, troops: Array[Node3D]) -> void:
	"""Load troops onto convoy"""
	for troop in troops:
		if is_instance_valid(troop):
			convoy.cargo_troops.append(troop)
			troop.visible = false
			troop.set_physics_process(false)


func load_supplies(convoy: Convoy, amount: float) -> void:
	"""Load supplies onto convoy"""
	convoy.supply_amount += amount


func ambush_convoy(convoy: Convoy, attacker: Node3D) -> void:
	"""Trigger ambush on convoy"""
	if convoy.state != ConvoyState.EN_ROUTE:
		return

	convoy.state = ConvoyState.AMBUSHED
	convoy_ambushed.emit(convoy, attacker)

	# Damage convoy
	convoy.health -= 100

	if convoy.health <= 0:
		_destroy_convoy(convoy)


func _destroy_convoy(convoy: Convoy) -> void:
	"""Destroy a convoy"""
	convoy.state = ConvoyState.DESTROYED
	convoy_destroyed.emit(convoy)

	# Kill troops
	for troop in convoy.cargo_troops:
		if is_instance_valid(troop) and troop.has_method("take_damage"):
			troop.take_damage(9999, null)

	# Destroy vehicles
	for vehicle in convoy.vehicles:
		if is_instance_valid(vehicle):
			vehicle.queue_free()

	active_convoys.erase(convoy)
	print("[ConvoyManager] Convoy %d destroyed" % convoy.id)


func get_active_convoy_count() -> int:
	return active_convoys.size()


## Request a supply convoy to a specific firebase
func request_supply_convoy(destination: Node3D, supply_amount: float = -1.0) -> Convoy:
	"""Manually request a supply convoy to a firebase"""
	if not _supply_depot:
		_find_supply_depot()

	if not _supply_depot:
		push_warning("[ConvoyManager] No supply depot available")
		return null

	var convoy := create_convoy(_supply_depot, destination, ConvoyType.SUPPLY)
	var amount: float = supply_amount if supply_amount > 0 else supply_per_convoy
	load_supplies(convoy, amount)
	dispatch_convoy(convoy)

	return convoy


## Set the supply depot location
func set_supply_depot(depot: Node3D) -> void:
	_supply_depot = depot


## Find the best supply depot with available supplies
func get_best_supply_depot(min_supply: float = 100.0) -> Node3D:
	"""Find a supply depot with enough supplies for a convoy."""
	var depots: Array[Node] = get_tree().get_nodes_in_group("supply_depots")
	var best_depot: Node3D = null
	var best_supply: float = 0.0

	for depot in depots:
		if not depot is Node3D:
			continue

		var available: float = 0.0
		if depot.has_method("get_available_supply"):
			available = depot.get_available_supply()
		elif depot.has_method("get") and depot.get("current_storage") != null:
			available = depot.current_storage

		if available >= min_supply and available > best_supply:
			best_supply = available
			best_depot = depot as Node3D

	# Fallback to main supply depot
	if not best_depot and _supply_depot:
		return _supply_depot

	return best_depot


## Request a supply convoy from a specific depot to destination
func request_convoy_from_depot(origin_depot: Node3D, destination: Node3D, supply_amount: float) -> Convoy:
	"""Request a convoy from a specific supply depot."""
	if not origin_depot or not destination:
		push_warning("[ConvoyManager] Invalid origin or destination")
		return null

	# Withdraw supply from depot if it supports it
	var actual_supply: float = supply_amount
	if origin_depot.has_method("withdraw_supply"):
		actual_supply = origin_depot.withdraw_supply(supply_amount)
		if actual_supply <= 0.0:
			push_warning("[ConvoyManager] Supply depot has insufficient supplies")
			return null

	var convoy := create_convoy(origin_depot, destination, ConvoyType.SUPPLY)
	load_supplies(convoy, actual_supply)
	dispatch_convoy(convoy)

	print("[ConvoyManager] Dispatched convoy from %s with %.0f supplies" % [
		origin_depot.name, actual_supply
	])

	return convoy


## Enable/disable auto-resupply
func set_auto_resupply(enabled: bool) -> void:
	auto_resupply_enabled = enabled


## Get convoy status for UI
func get_convoy_status() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for convoy in active_convoys:
		result.append({
			"id": convoy.id,
			"type": convoy.convoy_type,
			"state": convoy.state,
			"supply": convoy.supply_amount,
			"troops": convoy.cargo_troops.size(),
			"position": convoy.current_position,
			"destination": convoy.destination.name if convoy.destination else "Unknown",
			"health_percent": convoy.health / convoy.max_health if convoy.max_health > 0 else 1.0,
		})

	return result
