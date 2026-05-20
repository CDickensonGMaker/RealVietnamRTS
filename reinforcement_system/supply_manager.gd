extends Node
class_name SupplyManager

## Supply Manager - Handles logistics and supply delivery
## Manages supply points, delivery routes, and consumption

signal supply_requested(destination: Node3D, amount: float)
signal supply_delivered(destination: Node3D, amount: float)
signal supply_shortage(location: Node3D)
signal supply_route_established(origin: Node3D, destination: Node3D)
signal global_supply_changed(new_amount: float)

## Supply network
var supply_points: Array[Node3D] = []  # Firebases, depots, etc.
var supply_routes: Array[SupplyRoute] = []

## Global supply pool (main base camp)
var global_supply: float = 1000.0
var max_global_supply: float = 5000.0

## Configuration
@export var auto_resupply: bool = true
@export var resupply_threshold: float = 0.3  # Trigger resupply when below 30%
@export var resupply_check_interval: float = 10.0

## Timer
var _resupply_timer: float = 0.0


class SupplyRoute:
	var origin: Node3D
	var destination: Node3D
	var supply_per_delivery: float
	var delivery_interval: float
	var time_since_delivery: float
	var is_active: bool

	func _init(orig: Node3D, dest: Node3D) -> void:
		origin = orig
		destination = dest
		supply_per_delivery = 50.0
		delivery_interval = 60.0
		time_since_delivery = 0.0
		is_active = true


func _ready() -> void:
	# Add to group so SupplyDepot can find us
	add_to_group("supply_managers")

	# Find existing supply points (firebases and depots)
	_discover_supply_points()
	print("[SupplyManager] Initialized with %d supply points" % supply_points.size())


func _discover_supply_points() -> void:
	"""Find firebases and depots in the scene"""
	# Find firebases
	var firebases: Array[Node] = get_tree().get_nodes_in_group("firebases")
	for fb in firebases:
		if fb is Node3D and fb not in supply_points:
			supply_points.append(fb as Node3D)

	# Find supply depots
	var depots: Array[Node] = get_tree().get_nodes_in_group("supply_depots")
	for depot in depots:
		if depot is Node3D and depot not in supply_points:
			supply_points.append(depot as Node3D)


func _process(delta: float) -> void:
	# Update supply routes
	_update_supply_routes(delta)

	# Check for auto-resupply
	if auto_resupply:
		_resupply_timer += delta
		if _resupply_timer >= resupply_check_interval:
			_resupply_timer = 0.0
			_check_auto_resupply()


func _update_supply_routes(delta: float) -> void:
	"""Process automated supply deliveries"""
	for route in supply_routes:
		if not route.is_active:
			continue

		route.time_since_delivery += delta

		if route.time_since_delivery >= route.delivery_interval:
			route.time_since_delivery = 0.0
			_execute_supply_delivery(route)


func _execute_supply_delivery(route: SupplyRoute) -> void:
	"""Execute a supply delivery along a route"""
	if not is_instance_valid(route.destination):
		return

	# Check if we have supplies to send
	if global_supply < route.supply_per_delivery:
		supply_shortage.emit(route.origin)
		return

	# Deduct from global pool
	global_supply -= route.supply_per_delivery

	# Deliver to destination
	if route.destination.has_method("add_supply"):
		route.destination.add_supply(route.supply_per_delivery)

	supply_delivered.emit(route.destination, route.supply_per_delivery)

	if BattleSignals:
		BattleSignals.supply_delivered.emit(route.destination, route.supply_per_delivery)


func _check_auto_resupply() -> void:
	"""Check supply points and request resupply if needed"""
	for point in supply_points:
		if not is_instance_valid(point):
			continue

		# Check supply level
		var current: float = 0.0
		var maximum: float = 100.0

		if point.has_method("get") and point.get("supply_level") != null:
			current = point.supply_level
		if point.has_method("get") and point.get("max_supply") != null:
			maximum = point.max_supply

		var ratio: float = current / maximum if maximum > 0 else 0.0

		if ratio < resupply_threshold:
			# Request resupply
			var needed: float = maximum - current
			request_supply(point, needed * 0.5)  # Request half of deficit


## Public API

func request_supply(destination: Node3D, amount: float) -> bool:
	"""Request supply delivery to a location"""
	if global_supply < amount:
		supply_shortage.emit(null)
		return false

	supply_requested.emit(destination, amount)

	# Create convoy for delivery via ConvoyManager instance
	var convoy_mgr: Node = get_node_or_null("/root/ConvoyManager")
	if not convoy_mgr:
		# Try to find in current scene
		var mgrs: Array[Node] = get_tree().get_nodes_in_group("convoy_managers")
		if not mgrs.is_empty():
			convoy_mgr = mgrs[0]

	if convoy_mgr and convoy_mgr.has_method("create_convoy"):
		var convoy = convoy_mgr.create_convoy(
			null,  # From off-map
			destination,
			0  # ConvoyType.SUPPLY = 0
		)
		if convoy_mgr.has_method("load_supplies"):
			convoy_mgr.load_supplies(convoy, amount)
		if convoy_mgr.has_method("dispatch_convoy"):
			convoy_mgr.dispatch_convoy(convoy)

		# Deduct from global supply
		global_supply -= amount
	else:
		push_warning("[SupplyManager] ConvoyManager not found - cannot dispatch supply convoy")

	return true


func establish_supply_route(origin: Node3D, destination: Node3D) -> SupplyRoute:
	"""Create automated supply route between two points"""
	var route := SupplyRoute.new(origin, destination)
	supply_routes.append(route)

	supply_route_established.emit(origin, destination)
	print("[SupplyManager] Supply route established: %s -> %s" % [
		origin.name if origin else "Base",
		destination.name if destination else "Unknown"
	])

	return route


func cancel_supply_route(route: SupplyRoute) -> void:
	"""Cancel a supply route"""
	route.is_active = false
	supply_routes.erase(route)


func register_supply_point(point: Node3D) -> void:
	"""Register a new supply point"""
	if point not in supply_points:
		supply_points.append(point)


func unregister_supply_point(point: Node3D) -> void:
	"""Remove a supply point"""
	supply_points.erase(point)


func add_global_supply(amount: float) -> void:
	"""Add to global supply pool"""
	var old_supply := global_supply
	global_supply = minf(global_supply + amount, max_global_supply)
	if global_supply != old_supply:
		global_supply_changed.emit(global_supply)


func consume_global_supply(amount: float) -> bool:
	"""Try to consume from global pool. Returns false if insufficient."""
	if amount <= 0.0:
		return true
	if global_supply < amount:
		return false
	global_supply -= amount
	global_supply_changed.emit(global_supply)
	return true


func can_afford(amount: float) -> bool:
	"""Check if global pool has enough supply."""
	return global_supply >= amount


func get_global_supply() -> float:
	return global_supply


func get_supply_at(point: Node3D) -> float:
	"""Get supply level at a point"""
	# Check for SupplyDepot first (uses current_storage)
	if point.has_method("get_available_supply"):
		return point.get_available_supply()
	# Fallback to Firebase supply_level
	if point.has_method("get") and point.get("supply_level") != null:
		return point.supply_level
	return 0.0


func get_route_count() -> int:
	return supply_routes.size()


func get_supply_point_count() -> int:
	return supply_points.size()


func get_all_supply_depots() -> Array[Node3D]:
	"""Get all registered supply depots."""
	var depots: Array[Node3D] = []
	var depot_nodes: Array[Node] = get_tree().get_nodes_in_group("supply_depots")
	for node in depot_nodes:
		if node is Node3D:
			depots.append(node as Node3D)
	return depots


func find_nearest_depot(position: Vector3) -> Node3D:
	"""Find the nearest supply depot to a position."""
	var depots: Array[Node3D] = get_all_supply_depots()
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for depot in depots:
		var dist: float = position.distance_to(depot.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = depot

	return nearest


func find_depot_with_supply(min_supply: float = 100.0) -> Node3D:
	"""Find a supply depot with at least the specified supply amount."""
	var depots: Array[Node3D] = get_all_supply_depots()

	for depot in depots:
		var available: float = get_supply_at(depot)
		if available >= min_supply:
			return depot

	return null
