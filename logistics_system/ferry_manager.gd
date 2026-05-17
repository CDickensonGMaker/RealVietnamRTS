extends Node
class_name FerryManager
## FerryManager - Coordinates Supreme Commander-style ferry routes
##
## Manages automated transport routes between bases:
## - Creates and tracks ferry routes
## - Assigns available transports to routes
## - Coordinates helicopter and convoy ferries
##
## USAGE:
##   # As autoload or add to scene
##   var route = FerryManager.create_heli_route(base_lz, firebase_lz)
##   route.activate()

signal route_created(route: FerryRoute)
signal route_removed(route: FerryRoute)
signal ferry_started(route: FerryRoute, transport: Node3D)
signal ferry_completed(route: FerryRoute, cargo_count: int)

const FerryRouteScript = preload("res://logistics_system/ferry_route.gd")

## All managed routes
var routes: Array[FerryRoute] = []

## Available transports by type
var available_helicopters: Array[Node3D] = []
var available_trucks: Array[Node3D] = []

## Active ferry operations
var active_ferries: Dictionary = {}  # {transport_id: FerryRoute}

## Configuration
@export var auto_assign_transports: bool = true
@export var transport_check_interval: float = 5.0

## Timing
var _time_since_check: float = 0.0


func _ready() -> void:
	print("[FerryManager] Initialized")


func _process(delta: float) -> void:
	# Update all routes
	for route in routes:
		route.update(delta)

	# Check for transport assignment
	if auto_assign_transports:
		_time_since_check += delta
		if _time_since_check >= transport_check_interval:
			_time_since_check = 0.0
			_assign_available_transports()


func _assign_available_transports() -> void:
	"""Assign available transports to routes that need them"""
	# Sort routes by priority
	var active_routes: Array[FerryRoute] = []
	for route in routes:
		if route.is_active() and route.pickup_queue.size() > 0:
			active_routes.append(route)

	active_routes.sort_custom(func(a, b): return a.priority > b.priority)

	for route in active_routes:
		# Skip if route has enough transports
		if route.assigned_transports.size() >= route.max_transports:
			continue

		# Find available transport of matching type
		var transport: Node3D = _get_available_transport(route.route_type)
		if transport:
			_start_ferry_run(route, transport)


func _get_available_transport(route_type: int) -> Node3D:
	"""Get an available transport for the given route type"""
	match route_type:
		FerryRoute.RouteType.HELICOPTER:
			if not available_helicopters.is_empty():
				return available_helicopters.pop_front()
		FerryRoute.RouteType.CONVOY:
			if not available_trucks.is_empty():
				return available_trucks.pop_front()
	return null


func _start_ferry_run(route: FerryRoute, transport: Node3D) -> void:
	"""Start a ferry run with the given transport"""
	route.assign_transport(transport)
	active_ferries[transport.get_instance_id()] = route

	# Get cargo
	var cargo: Array[Node3D] = route.get_next_cargo_batch()
	if cargo.is_empty():
		# No cargo, return transport
		_return_transport(transport, route)
		return

	route.cargo_loaded.emit(cargo, route.origin_point)
	ferry_started.emit(route, transport)

	# Execute based on route type
	match route.route_type:
		FerryRoute.RouteType.HELICOPTER:
			_execute_heli_ferry(route, transport, cargo)
		FerryRoute.RouteType.CONVOY:
			_execute_convoy_ferry(route, transport, cargo)


func _execute_heli_ferry(route: FerryRoute, helicopter: Node3D, cargo: Array[Node3D]) -> void:
	"""Execute helicopter ferry operation"""
	# Load troops onto helicopter
	if helicopter.has_method("load_troops"):
		helicopter.load_troops(cargo)

	# Fly to destination
	if helicopter.has_method("fly_to") and route.destination_point:
		# Connect to landed signal
		if helicopter.has_signal("landed"):
			helicopter.landed.connect(
				_on_heli_ferry_arrived.bind(route, cargo),
				CONNECT_ONE_SHOT
			)
		helicopter.fly_to(route.destination_point.global_position, route.destination_point)


func _on_heli_ferry_arrived(helicopter: Node3D, _lz: Node3D, route: FerryRoute, cargo: Array[Node3D]) -> void:
	"""Handle helicopter arrival at destination"""
	# Unload troops
	if helicopter.has_method("unload_troops"):
		helicopter.unload_troops()

	route.record_delivery(cargo)
	ferry_completed.emit(route, cargo.size())

	# Return to origin for next run
	if helicopter.has_signal("took_off"):
		helicopter.took_off.connect(
			_on_heli_returned_to_origin.bind(route),
			CONNECT_ONE_SHOT
		)

	if helicopter.has_method("take_off"):
		helicopter.take_off()

	# After takeoff, fly back to origin
	if helicopter.has_method("fly_to") and route.origin_point:
		# Small delay before return flight
		await helicopter.get_tree().create_timer(1.0).timeout
		helicopter.fly_to(route.origin_point.global_position, route.origin_point)


func _on_heli_returned_to_origin(helicopter: Node3D, route: FerryRoute) -> void:
	"""Handle helicopter returned to origin, ready for next run"""
	# Check if more cargo waiting
	if route.pickup_queue.size() > 0:
		# Start another run
		var cargo: Array[Node3D] = route.get_next_cargo_batch()
		if not cargo.is_empty():
			route.cargo_loaded.emit(cargo, route.origin_point)
			_execute_heli_ferry(route, helicopter, cargo)
			return

	# No more cargo, return transport to pool
	_return_transport(helicopter, route)


func _execute_convoy_ferry(route: FerryRoute, truck: Node3D, cargo: Array[Node3D]) -> void:
	"""Execute ground convoy ferry operation"""
	# Load troops onto truck
	if truck.has_method("load_troops"):
		truck.load_troops(cargo)

	# Move to destination via waypoints
	if truck.has_method("move_to"):
		# Set waypoint path
		var path: Array[Vector3] = route.waypoints.duplicate()
		path.append(route.destination_point.global_position)

		if truck.has_signal("arrived"):
			truck.arrived.connect(
				_on_convoy_arrived.bind(route, cargo),
				CONNECT_ONE_SHOT
			)

		truck.move_to(path[0] if not path.is_empty() else route.destination_point.global_position)


func _on_convoy_arrived(truck: Node3D, route: FerryRoute, cargo: Array[Node3D]) -> void:
	"""Handle convoy arrival at destination"""
	if truck.has_method("unload_troops"):
		truck.unload_troops()

	route.record_delivery(cargo)
	ferry_completed.emit(route, cargo.size())

	# Return to origin
	if truck.has_method("move_to") and route.origin_point:
		var return_path: Array[Vector3] = route.waypoints.duplicate()
		return_path.reverse()
		return_path.append(route.origin_point.global_position)

		if truck.has_signal("arrived"):
			truck.arrived.connect(
				_on_convoy_returned.bind(route),
				CONNECT_ONE_SHOT
			)

		truck.move_to(return_path[0] if not return_path.is_empty() else route.origin_point.global_position)


func _on_convoy_returned(truck: Node3D, route: FerryRoute) -> void:
	"""Handle convoy returned to origin"""
	if route.pickup_queue.size() > 0:
		var cargo: Array[Node3D] = route.get_next_cargo_batch()
		if not cargo.is_empty():
			route.cargo_loaded.emit(cargo, route.origin_point)
			_execute_convoy_ferry(route, truck, cargo)
			return

	_return_transport(truck, route)


func _return_transport(transport: Node3D, route: FerryRoute) -> void:
	"""Return a transport to the available pool"""
	route.unassign_transport(transport)
	active_ferries.erase(transport.get_instance_id())

	match route.route_type:
		FerryRoute.RouteType.HELICOPTER:
			available_helicopters.append(transport)
		FerryRoute.RouteType.CONVOY:
			available_trucks.append(transport)


# =============================================================================
# PUBLIC API
# =============================================================================

## Create a helicopter ferry route between two LZs
func create_heli_route(origin_lz: Node3D, destination_lz: Node3D, name: String = "") -> FerryRoute:
	var route := FerryRouteScript.new()
	route.setup_helicopter_route(origin_lz, destination_lz, name)
	routes.append(route)
	route_created.emit(route)
	return route


## Create a ground convoy ferry route
func create_convoy_route(
	origin: Node3D,
	destination: Node3D,
	waypoints: Array[Vector3] = [],
	name: String = ""
) -> FerryRoute:
	var route := FerryRouteScript.new()
	route.setup_convoy_route(origin, destination, waypoints, name)
	routes.append(route)
	route_created.emit(route)
	return route


## Remove a ferry route
func remove_route(route: FerryRoute) -> void:
	route.deactivate()
	routes.erase(route)
	route_removed.emit(route)


## Register a helicopter as available for ferry duty
func register_helicopter(helicopter: Node3D) -> void:
	if helicopter not in available_helicopters:
		available_helicopters.append(helicopter)


## Register a truck as available for ferry duty
func register_truck(truck: Node3D) -> void:
	if truck not in available_trucks:
		available_trucks.append(truck)


## Get all active routes
func get_active_routes() -> Array[FerryRoute]:
	var result: Array[FerryRoute] = []
	for route in routes:
		if route.is_active():
			result.append(route)
	return result


## Get statistics for all routes
func get_stats() -> Dictionary:
	var total_ferried: int = 0
	var total_trips: int = 0

	for route in routes:
		var stats: Dictionary = route.get_stats()
		total_ferried += stats.units_ferried
		total_trips += stats.trips_completed

	return {
		"route_count": routes.size(),
		"active_routes": get_active_routes().size(),
		"total_units_ferried": total_ferried,
		"total_trips": total_trips,
		"available_helicopters": available_helicopters.size(),
		"available_trucks": available_trucks.size(),
	}
