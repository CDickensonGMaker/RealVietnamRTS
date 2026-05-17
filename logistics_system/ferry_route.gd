class_name FerryRoute extends RefCounted
## FerryRoute - Supreme Commander-style automated transport route
##
## Creates continuous automated transport between two points:
## - Helicopters shuttle between LZs
## - Trucks shuttle between bases on roads
##
## LESSONS FROM SUPREME COMMANDER:
## - Ferry points allow automated unit transport
## - Transports continuously loop between points
## - Units queue at pickup point, get ferried automatically
## - Very effective for reinforcing distant positions
##
## USAGE:
##   var route = FerryRoute.new()
##   route.setup_helicopter_route(base_lz, firebase_lz)
##   route.activate()
##   # Units at base_lz will be auto-ferried to firebase_lz

signal route_activated
signal route_deactivated
signal cargo_loaded(cargo: Array[Node3D], at_point: Node3D)
signal cargo_delivered(cargo: Array[Node3D], at_point: Node3D)
signal transport_departed(transport: Node3D, from_point: Node3D)
signal transport_arrived(transport: Node3D, at_point: Node3D)

enum RouteType {
	HELICOPTER,  # Air transport between LZs
	CONVOY,      # Ground transport on roads
	NAVAL,       # River/coastal transport
}

enum RouteState {
	INACTIVE,
	ACTIVE,
	PAUSED,
	BLOCKED,  # Route cut by enemy
}

## Configuration
var route_name: String = "Ferry Route"
var route_type: RouteType = RouteType.HELICOPTER
var priority: int = 5  # Higher = more transports assigned

## Route points
var origin_point: Node3D = null  # Pickup location
var destination_point: Node3D = null  # Dropoff location
var waypoints: Array[Vector3] = []  # Intermediate waypoints (for convoy routes)

## Transport allocation
var assigned_transports: Array[Node3D] = []
var max_transports: int = 2  # Max simultaneous transports on this route

## Cargo settings
var auto_load: bool = true  # Automatically load waiting units
var cargo_filter_groups: Array[String] = ["player_units"]  # Which units to ferry
var max_cargo_per_trip: int = 8  # Huey capacity

## State
var state: RouteState = RouteState.INACTIVE
var trips_completed: int = 0
var units_ferried: int = 0

## Queues
var pickup_queue: Array[Node3D] = []  # Units waiting at origin
var _check_interval: float = 2.0
var _time_since_check: float = 0.0


func setup_helicopter_route(origin_lz: Node3D, dest_lz: Node3D, name: String = "") -> void:
	"""Setup a helicopter ferry route between two LZs"""
	route_type = RouteType.HELICOPTER
	origin_point = origin_lz
	destination_point = dest_lz
	route_name = name if name else "Heli Route: %s -> %s" % [origin_lz.name, dest_lz.name]


func setup_convoy_route(origin_base: Node3D, dest_base: Node3D, road_waypoints: Array[Vector3] = [], name: String = "") -> void:
	"""Setup a ground convoy ferry route"""
	route_type = RouteType.CONVOY
	origin_point = origin_base
	destination_point = dest_base
	waypoints = road_waypoints
	route_name = name if name else "Convoy Route: %s -> %s" % [origin_base.name, dest_base.name]


func activate() -> void:
	"""Activate the ferry route"""
	if state == RouteState.INACTIVE:
		state = RouteState.ACTIVE
		route_activated.emit()
		print("[FerryRoute] Activated: %s" % route_name)


func deactivate() -> void:
	"""Deactivate the ferry route"""
	state = RouteState.INACTIVE
	route_deactivated.emit()
	print("[FerryRoute] Deactivated: %s" % route_name)


func pause() -> void:
	"""Temporarily pause the route"""
	if state == RouteState.ACTIVE:
		state = RouteState.PAUSED


func resume() -> void:
	"""Resume a paused route"""
	if state == RouteState.PAUSED:
		state = RouteState.ACTIVE


func mark_blocked() -> void:
	"""Mark route as blocked by enemy activity"""
	state = RouteState.BLOCKED


func is_active() -> bool:
	return state == RouteState.ACTIVE


func update(delta: float) -> void:
	"""Update ferry route (called by FerryManager)"""
	if state != RouteState.ACTIVE:
		return

	_time_since_check += delta
	if _time_since_check >= _check_interval:
		_time_since_check = 0.0
		_check_for_cargo()


func _check_for_cargo() -> void:
	"""Check for units waiting at origin point"""
	if not auto_load or not origin_point:
		return

	pickup_queue.clear()

	# Find units at origin point
	var pickup_radius: float = 20.0
	if origin_point.has_method("get") and origin_point.get("lz_radius"):
		pickup_radius = origin_point.lz_radius

	# Query units in pickup area
	for group_name in cargo_filter_groups:
		var scene_tree: SceneTree = origin_point.get_tree()
		if not scene_tree:
			continue

		var units: Array[Node] = scene_tree.get_nodes_in_group(group_name)
		for unit in units:
			if not is_instance_valid(unit):
				continue

			# Check if within pickup radius
			var dist: float = unit.global_position.distance_to(origin_point.global_position)
			if dist > pickup_radius:
				continue

			# Check if unit wants to be ferried (has ferry destination)
			if _should_ferry_unit(unit):
				pickup_queue.append(unit)

	# Limit queue size
	if pickup_queue.size() > max_cargo_per_trip * 2:
		pickup_queue.resize(max_cargo_per_trip * 2)


func _should_ferry_unit(unit: Node3D) -> bool:
	"""Check if a unit should be ferried"""
	# Skip if already being transported
	if unit.has_method("get") and unit.get("is_being_transported"):
		if unit.is_being_transported:
			return false

	# Skip if not flagged for ferry
	# Units can be flagged by player command or AI decision
	if unit.has_method("get") and "ferry_destination" in unit:
		return unit.ferry_destination != null

	# Default: ferry all units at pickup point if route is supply-focused
	return true


func assign_transport(transport: Node3D) -> void:
	"""Assign a transport vehicle/helicopter to this route"""
	if transport not in assigned_transports:
		assigned_transports.append(transport)


func unassign_transport(transport: Node3D) -> void:
	"""Remove a transport from this route"""
	assigned_transports.erase(transport)


func get_next_cargo_batch() -> Array[Node3D]:
	"""Get the next batch of cargo to transport"""
	var batch: Array[Node3D] = []

	for i in mini(pickup_queue.size(), max_cargo_per_trip):
		batch.append(pickup_queue[i])

	# Remove from queue
	for unit in batch:
		pickup_queue.erase(unit)

	return batch


func record_delivery(cargo: Array[Node3D]) -> void:
	"""Record successful cargo delivery"""
	trips_completed += 1
	units_ferried += cargo.size()
	cargo_delivered.emit(cargo, destination_point)


func get_stats() -> Dictionary:
	return {
		"name": route_name,
		"type": route_type,
		"state": state,
		"trips_completed": trips_completed,
		"units_ferried": units_ferried,
		"queue_size": pickup_queue.size(),
		"transports": assigned_transports.size(),
	}
