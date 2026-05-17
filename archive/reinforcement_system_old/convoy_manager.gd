extends Node
## ConvoyManager - Manages ground convoys for reinforcements and supplies
## Accessed globally via ConvoyManager autoload (no class_name needed)

signal convoy_created(convoy: Convoy)
signal convoy_departed(convoy: Convoy)
signal convoy_arrived(convoy: Convoy)
signal convoy_ambushed(convoy: Convoy, position: Vector3)
signal convoy_destroyed(convoy: Convoy)

# Active convoys
var active_convoys: Array = []  # Array of Convoy

# Convoy spawn points (off-map)
var spawn_point := Vector3(-100, 0, 100)
var despawn_point := Vector3(-100, 0, 100)

# Routes
var supply_routes: Dictionary = {}  # route_id -> Array[Vector3]

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	_process_convoys(delta)

# =============================================================================
# CONVOY CREATION
# =============================================================================

func create_supply_convoy(destination: Node3D, supplies: int):  # Returns Convoy
	var convoy := Convoy.new()
	convoy.convoy_type = Convoy.ConvoyType.SUPPLY
	convoy.supplies_carried = supplies
	convoy.destination = destination
	convoy.spawn_position = spawn_point

	_setup_convoy(convoy)
	return convoy

func create_reinforcement_convoy(destination: Node3D, units: Array):  # Returns Convoy
	var convoy := Convoy.new()
	convoy.convoy_type = Convoy.ConvoyType.REINFORCEMENT
	convoy.cargo_units = units
	convoy.destination = destination
	convoy.spawn_position = spawn_point

	_setup_convoy(convoy)
	return convoy

func _setup_convoy(convoy) -> void:  # convoy: Convoy
	convoy.global_position = spawn_point

	# Generate route
	convoy.route = _generate_route(spawn_point, convoy.destination.global_position)

	# Spawn vehicles
	convoy.vehicles = _spawn_convoy_vehicles(convoy)

	get_tree().current_scene.add_child(convoy)
	active_convoys.append(convoy)

	# Connect signals
	convoy.arrived.connect(func(): _on_convoy_arrived(convoy))
	convoy.ambushed.connect(func(pos): _on_convoy_ambushed(convoy, pos))
	convoy.destroyed.connect(func(): _on_convoy_destroyed(convoy))

	convoy_created.emit(convoy)
	convoy_departed.emit(convoy)

func _spawn_convoy_vehicles(convoy) -> Array[Node3D]:  # convoy: Convoy
	var vehicles: Array[Node3D] = []

	# Lead vehicle (APC)
	var lead := _create_vehicle("apc")
	vehicles.append(lead)

	# Cargo trucks
	var truck_count := 2
	if convoy.convoy_type == Convoy.ConvoyType.SUPPLY:
		truck_count = ceili(convoy.supplies_carried / 50.0)

	for i in range(truck_count):
		var truck := _create_vehicle("truck")
		vehicles.append(truck)

	# Rear guard (APC)
	var rear := _create_vehicle("apc")
	vehicles.append(rear)

	return vehicles

func _create_vehicle(vehicle_type: String) -> Node3D:
	# Placeholder - would load actual vehicle scenes
	var vehicle := Node3D.new()
	vehicle.set_meta("vehicle_type", vehicle_type)
	return vehicle

func _generate_route(from: Vector3, to: Vector3) -> Array[Vector3]:
	var route: Array[Vector3] = []

	# Simple route - follow road
	route.append(from)

	# Add intermediate waypoints along road
	var distance := from.distance_to(to)
	var waypoint_count := int(distance / 50.0)

	for i in range(1, waypoint_count):
		var t := float(i) / float(waypoint_count)
		var waypoint := from.lerp(to, t)
		# Add some variation to follow road curves
		waypoint.x += randf_range(-5, 5)
		waypoint.z += randf_range(-5, 5)
		route.append(waypoint)

	route.append(to)
	return route

# =============================================================================
# CONVOY PROCESSING
# =============================================================================

func _process_convoys(delta: float) -> void:
	for convoy in active_convoys:
		if not is_instance_valid(convoy):
			continue

		convoy.process_movement(delta)

		# Check for ambush
		if not convoy.is_ambushed:
			_check_ambush(convoy)

func _check_ambush(convoy: Convoy) -> void:
	# Check for enemies near convoy
	var enemies := SpatialHashGrid.get_enemies_in_radius(
		convoy.global_position, 50.0, GameEnums.Faction.US_ARMY
	)

	if enemies.size() >= 5:  # Significant enemy force
		convoy.trigger_ambush(convoy.global_position)

# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_convoy_arrived(convoy) -> void:  # convoy: Convoy
	active_convoys.erase(convoy)
	convoy_arrived.emit(convoy)
	BattleSignals.convoy_arrived.emit(convoy, convoy.destination)

func _on_convoy_ambushed(convoy, position: Vector3) -> void:  # convoy: Convoy
	convoy_ambushed.emit(convoy, position)
	BattleSignals.convoy_ambushed.emit(convoy, position)

func _on_convoy_destroyed(convoy) -> void:  # convoy: Convoy
	active_convoys.erase(convoy)
	convoy_destroyed.emit(convoy)
	BattleSignals.convoy_destroyed.emit(convoy)

# =============================================================================
# ROUTE MANAGEMENT
# =============================================================================

func register_supply_route(route_id: String, waypoints: Array[Vector3]) -> void:
	supply_routes[route_id] = waypoints

func get_route(route_id: String) -> Array[Vector3]:
	return supply_routes.get(route_id, [])

func assess_route_danger(route: Array[Vector3]) -> Dictionary:
	## Assess danger level of a route
	var total_threat := 0.0
	var danger_points: Array[Dictionary] = []

	for i in range(route.size()):
		var waypoint: Vector3 = route[i]
		var enemies := SpatialHashGrid.get_enemies_in_radius(
			waypoint, 100.0, GameEnums.Faction.US_ARMY
		)

		if not enemies.is_empty():
			var threat := enemies.size() * 10.0
			total_threat += threat
			danger_points.append({
				"position": waypoint,
				"index": i,
				"threat": threat,
				"enemy_count": enemies.size(),
			})

	# Check for terrain dangers (jungle/ambush zones)
	var ambush_zones := 0
	for waypoint in route:
		if _is_ambush_terrain(waypoint):
			ambush_zones += 1
			total_threat += 5.0

	var danger_level := "LOW"
	if total_threat > 50:
		danger_level = "HIGH"
	elif total_threat > 20:
		danger_level = "MEDIUM"

	return {
		"total_threat": total_threat,
		"danger_level": danger_level,
		"danger_points": danger_points,
		"ambush_zones": ambush_zones,
		"recommended_escort": _calculate_escort_strength(total_threat),
	}

func _is_ambush_terrain(position: Vector3) -> bool:
	## Check if position is prone to ambush
	# Would check terrain system in real implementation
	# For now, random check based on position
	return randf() < 0.2

func _calculate_escort_strength(threat_level: float) -> Dictionary:
	if threat_level > 50:
		return {"infantry": 2, "armor": 1, "gunship": true}
	elif threat_level > 20:
		return {"infantry": 1, "armor": 0, "gunship": false}
	else:
		return {"infantry": 0, "armor": 0, "gunship": false}

func find_safest_route(from: Vector3, to: Vector3) -> Array[Vector3]:
	## Generate multiple routes and pick the safest

	var routes: Array[Array] = []

	# Direct route
	routes.append(_generate_route(from, to))

	# Northern detour
	var north_mid := (from + to) / 2 + Vector3(0, 0, 50)
	routes.append(_generate_route_via(from, to, north_mid))

	# Southern detour
	var south_mid := (from + to) / 2 + Vector3(0, 0, -50)
	routes.append(_generate_route_via(from, to, south_mid))

	# Assess each route
	var best_route: Array[Vector3] = routes[0]
	var best_threat := INF

	for route: Array in routes:
		var assessment := assess_route_danger(route)
		if assessment.total_threat < best_threat:
			best_threat = assessment.total_threat
			best_route = route

	return best_route

func _generate_route_via(from: Vector3, to: Vector3, via: Vector3) -> Array[Vector3]:
	var route: Array[Vector3] = []
	route.append(from)

	# First leg to via point
	var leg1_count := int(from.distance_to(via) / 50.0)
	for i in range(1, leg1_count):
		var t := float(i) / float(leg1_count)
		route.append(from.lerp(via, t))

	route.append(via)

	# Second leg to destination
	var leg2_count := int(via.distance_to(to) / 50.0)
	for i in range(1, leg2_count):
		var t := float(i) / float(leg2_count)
		route.append(via.lerp(to, t))

	route.append(to)
	return route

# =============================================================================
# ESCORT MANAGEMENT
# =============================================================================

func assign_escort(convoy, escort_units: Array[Node3D]) -> void:  # convoy: Convoy
	convoy.escort = escort_units
	for unit in escort_units:
		if is_instance_valid(unit) and unit.has_method("set_escort_target"):
			unit.set_escort_target(convoy)

func request_gunship_escort(convoy) -> void:  # convoy: Convoy
	## Request helicopter gunship escort
	BattleSignals.helicopter_launched.emit(null, GameEnums.MissionType.ESCORT_DUTY)

# =============================================================================
# AMBUSH RESPONSE
# =============================================================================

func handle_ambush_response(convoy) -> void:  # convoy: Convoy
	## Coordinate response to convoy ambush

	# Halt convoy
	convoy.is_moving = false

	# Vehicles form defensive circle
	_form_defensive_perimeter(convoy)

	# Call for support
	_request_ambush_support(convoy)

	# Escort engages
	for escort in convoy.escort:
		if is_instance_valid(escort) and escort.has_method("engage_hostiles"):
			escort.engage_hostiles()

func _form_defensive_perimeter(convoy) -> void:  # convoy: Convoy
	## Position vehicles in defensive formation
	var center: Vector3 = convoy.global_position
	for i in range(convoy.vehicles.size()):
		if is_instance_valid(convoy.vehicles[i]):
			var angle: float = (TAU / convoy.vehicles.size()) * i
			var pos: Vector3 = center + Vector3(cos(angle) * 10, 0, sin(angle) * 10)
			convoy.vehicles[i].global_position = pos

func _request_ambush_support(convoy) -> void:  # convoy: Convoy
	## Request support for ambushed convoy

	# Call artillery
	BattleSignals.airstrike_requested.emit(
		GameEnums.AirStrikeType.CLOSE_AIR_SUPPORT,
		convoy.global_position
	)

	# Request QRF
	BattleSignals.reinforcement_requested.emit(
		GameEnums.UnitType.RIFLE_PLATOON,
		convoy
	)

# =============================================================================
# CONVOY STATUS
# =============================================================================

func get_convoy_count() -> int:
	return active_convoys.size()

func get_convoys_to_destination(destination: Node3D) -> Array:  # Returns Array of Convoy
	var result: Array = []  # Array of Convoy
	for convoy in active_convoys:
		if is_instance_valid(convoy) and convoy.destination == destination:
			result.append(convoy)
	return result

func get_convoy_eta(convoy) -> float:  # convoy: Convoy
	## Estimate time to arrival in seconds
	if not is_instance_valid(convoy) or convoy.route.is_empty():
		return -1.0

	var remaining_distance := 0.0
	for i in range(convoy.current_waypoint_index, convoy.route.size()):
		if i == convoy.current_waypoint_index:
			remaining_distance += convoy.global_position.distance_to(convoy.route[i])
		elif i > 0:
			remaining_distance += convoy.route[i - 1].distance_to(convoy.route[i])

	return remaining_distance / convoy.move_speed


# =============================================================================
# CONVOY CLASS
# =============================================================================

class Convoy:
	extends Node3D

	signal arrived()
	signal ambushed(position: Vector3)
	signal destroyed()
	signal vehicle_lost(vehicle: Node3D)

	enum ConvoyType { SUPPLY, REINFORCEMENT, MIXED }

	var convoy_type: ConvoyType = ConvoyType.SUPPLY
	var supplies_carried: int = 0
	var cargo_units: Array = []

	var destination: Node3D
	var spawn_position: Vector3

	var vehicles: Array[Node3D] = []
	var escort: Array[Node3D] = []
	var route: Array[Vector3] = []
	var current_waypoint_index: int = 0

	var move_speed: float = 8.0
	var health: float = 100.0

	var is_moving: bool = true
	var is_ambushed: bool = false
	var is_destroyed: bool = false

	func _ready() -> void:
		add_to_group("convoys")
		add_to_group("player_units")

	func process_movement(delta: float) -> void:
		if not is_moving or is_destroyed:
			return

		if current_waypoint_index >= route.size():
			_arrive()
			return

		var target := route[current_waypoint_index]
		var direction := (target - global_position).normalized()
		var distance := global_position.distance_to(target)

		if distance < 2.0:
			current_waypoint_index += 1
		else:
			global_position += direction * move_speed * delta
			# Update vehicle positions
			_update_vehicle_positions()

	func _update_vehicle_positions() -> void:
		var spacing := 8.0
		for i in range(vehicles.size()):
			if is_instance_valid(vehicles[i]):
				var offset := Vector3(0, 0, -spacing * i)
				vehicles[i].global_position = global_position + offset

	func _arrive() -> void:
		is_moving = false

		# Deliver supplies/units
		if destination and is_instance_valid(destination):
			if convoy_type == ConvoyType.SUPPLY:
				if destination.has_method("add_supplies"):
					destination.add_supplies(supplies_carried)

		arrived.emit()

	func trigger_ambush(position: Vector3) -> void:
		is_ambushed = true
		is_moving = false
		ambushed.emit(position)

	func take_damage(amount: float, source: Node3D = null) -> void:
		health -= amount

		if health <= 0:
			_destroy()

	func _destroy() -> void:
		is_destroyed = true
		is_moving = false
		destroyed.emit()
		queue_free()

	func get_faction() -> int:
		return GameEnums.Faction.US_ARMY
