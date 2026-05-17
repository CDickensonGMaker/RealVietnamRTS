extends Node
class_name TunnelNetwork

## Tunnel Network - Manages the VC underground tunnel system
## Handles unit movement, resupply, and emergence attacks

signal tunnel_attack_launched(entrance: Node3D, units: Array)
signal supply_delivered(entrance: Node3D, amount: float)
signal tunnel_network_damaged(entrances_lost: int)
signal unit_moved_underground(unit: Node3D, from: Node3D, to: Node3D)

const TunnelEntrance = preload("res://tunnel_system/tunnel_entrance.gd")

## All tunnel entrances
var entrances: Array = []

## Units currently moving underground
var _traveling_units: Array = []

## Configuration
@export var underground_speed: float = 5.0  # m/s
@export var max_network_supply: float = 500.0
@export var supply_regen_rate: float = 2.0  # Per second

## Network resources
var network_supply: float = 200.0


class TravelingUnit:
	var unit: Node3D
	var origin: Node3D  # TunnelEntrance
	var destination: Node3D  # TunnelEntrance
	var travel_time: float
	var elapsed: float

	func _init(u: Node3D, orig: Node3D, dest: Node3D) -> void:
		unit = u
		origin = orig
		destination = dest
		travel_time = orig.global_position.distance_to(dest.global_position) / 5.0
		elapsed = 0.0


func _ready() -> void:
	# Find existing tunnel entrances
	_collect_entrances()
	print("[TunnelNetwork] Initialized with %d entrances" % entrances.size())


func _process(delta: float) -> void:
	# Regenerate supply
	network_supply = minf(network_supply + supply_regen_rate * delta, max_network_supply)

	# Update traveling units
	_update_traveling_units(delta)


func _collect_entrances() -> void:
	"""Find all tunnel entrances in scene"""
	entrances.clear()
	var nodes: Array[Node] = get_tree().get_nodes_in_group("tunnel_entrances")
	for node in nodes:
		if node is TunnelEntrance:
			_register_entrance(node)


func _register_entrance(entrance: TunnelEntrance) -> void:
	"""Register an entrance with the network"""
	if entrance in entrances:
		return

	entrances.append(entrance)
	entrance.tunnel_network = self

	# Connect signals
	entrance.entrance_destroyed.connect(_on_entrance_destroyed)
	entrance.entrance_discovered.connect(_on_entrance_discovered)


func _on_entrance_destroyed(entrance: TunnelEntrance) -> void:
	"""Handle entrance destruction"""
	entrances.erase(entrance)

	# Remove from all connections
	for other in entrances:
		other.connected_tunnels.erase(entrance)

	tunnel_network_damaged.emit(1)


func _on_entrance_discovered(entrance: TunnelEntrance) -> void:
	"""Handle entrance discovery"""
	# Could trigger defensive response
	pass


func _update_traveling_units(delta: float) -> void:
	"""Update units traveling through tunnels"""
	var arrived: Array = []

	for travel in _traveling_units:
		travel.elapsed += delta

		if travel.elapsed >= travel.travel_time:
			arrived.append(travel)

	for travel in arrived:
		_traveling_units.erase(travel)
		_complete_travel(travel)


func _complete_travel(travel: TravelingUnit) -> void:
	"""Complete underground travel"""
	if not is_instance_valid(travel.unit):
		return

	if not is_instance_valid(travel.destination):
		# Destination destroyed, unit lost
		if is_instance_valid(travel.unit) and travel.unit.has_method("take_damage"):
			travel.unit.take_damage(9999, null)
		return

	# Emerge at destination
	travel.destination.emerge_unit(travel.unit)
	unit_moved_underground.emit(travel.unit, travel.origin, travel.destination)


## Public API - Network Management

func create_entrance(position: Vector3, entrance_type: int = 0) -> TunnelEntrance:
	"""Create a new tunnel entrance"""
	var entrance := TunnelEntrance.new()
	entrance.entrance_type = entrance_type
	entrance.position = position
	entrance.tunnel_network = self

	get_tree().current_scene.add_child(entrance)
	_register_entrance(entrance)

	return entrance


func connect_entrances(entrance_a: TunnelEntrance, entrance_b: TunnelEntrance) -> void:
	"""Connect two tunnel entrances"""
	entrance_a.connect_to(entrance_b)


func auto_connect_nearby(max_distance: float = 100.0) -> void:
	"""Automatically connect nearby entrances"""
	for i in entrances.size():
		for j in range(i + 1, entrances.size()):
			var dist: float = entrances[i].global_position.distance_to(entrances[j].global_position)
			if dist <= max_distance:
				connect_entrances(entrances[i], entrances[j])


func find_nearest_entrance(position: Vector3, include_hidden: bool = true) -> TunnelEntrance:
	"""Find nearest tunnel entrance"""
	var nearest: TunnelEntrance = null
	var nearest_dist: float = INF

	for entrance in entrances:
		if entrance.is_destroyed():
			continue
		if not include_hidden and not entrance.is_discovered():
			continue

		var dist: float = position.distance_to(entrance.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = entrance

	return nearest


func find_entrance_near_target(target_pos: Vector3, max_distance: float = 50.0) -> TunnelEntrance:
	"""Find suitable entrance for emergence attack"""
	var candidates: Array = []

	for entrance in entrances:
		if entrance.is_destroyed():
			continue

		var dist: float = entrance.global_position.distance_to(target_pos)
		if dist <= max_distance and entrance.can_accept_units():
			candidates.append(entrance)

	if candidates.is_empty():
		return null

	# Prefer closer, hidden entrances
	candidates.sort_custom(func(a, b):
		var score_a: float = a.global_position.distance_to(target_pos)
		var score_b: float = b.global_position.distance_to(target_pos)
		if not a.is_discovered():
			score_a *= 0.5  # Prefer hidden
		if not b.is_discovered():
			score_b *= 0.5
		return score_a < score_b
	)

	return candidates[0]


## Public API - Unit Operations

func move_unit_underground(unit: Node3D, origin: TunnelEntrance, destination: TunnelEntrance) -> bool:
	"""Move a unit through the tunnel network"""
	if not origin.connected_tunnels.has(destination):
		return false

	if not origin.hide_unit(unit):
		return false

	var travel := TravelingUnit.new(unit, origin, destination)
	_traveling_units.append(travel)

	return true


func launch_tunnel_attack(target_pos: Vector3, unit_count: int) -> Array[Node3D]:
	"""Launch a surprise tunnel emergence attack"""
	var entrance: TunnelEntrance = find_entrance_near_target(target_pos)
	if not entrance:
		return []

	# Gather units from network
	var units_to_emerge: Array[Node3D] = []
	var gathered: int = 0

	# First check the target entrance
	while entrance.get_hidden_count() > 0 and gathered < unit_count:
		var unit: Node3D = entrance.emerge_unit()
		if unit:
			units_to_emerge.append(unit)
			gathered += 1

	# Check connected entrances for more units
	if gathered < unit_count:
		for connected in entrance.connected_tunnels:
			while connected.get_hidden_count() > 0 and gathered < unit_count:
				var unit: Node3D = connected.emerge_unit()
				if unit:
					# Move to target entrance position
					unit.global_position = entrance.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
					units_to_emerge.append(unit)
					gathered += 1

	if not units_to_emerge.is_empty():
		tunnel_attack_launched.emit(entrance, units_to_emerge)

	return units_to_emerge


func resupply_from_network(entrance: TunnelEntrance, amount: float) -> float:
	"""Deliver supplies from network to an entrance"""
	var delivered: float = minf(amount, network_supply)
	network_supply -= delivered

	if entrance.entrance_type == TunnelEntrance.EntranceType.SUPPLY_CACHE:
		entrance.supply_cache += delivered

	supply_delivered.emit(entrance, delivered)
	return delivered


func spawn_units_at_entrance(entrance: TunnelEntrance, count: int, unit_data: Resource = null) -> Array[Node3D]:
	"""Spawn VC units at a tunnel entrance (for reinforcements)"""
	var spawned: Array[Node3D] = []

	if entrance.is_destroyed():
		return spawned

	for i in count:
		if not entrance.can_accept_units():
			break

		var unit := Node3D.new()  # Would be Squad.new() with proper data
		unit.name = "TunnelVC_%d" % i
		unit.add_to_group("enemy_units")
		unit.add_to_group("all_units")

		# Hide in entrance
		entrance.hide_unit(unit)
		spawned.append(unit)

	return spawned


## Statistics

func get_total_hidden_units() -> int:
	"""Get total units hidden in all tunnels"""
	var total: int = 0
	for entrance in entrances:
		total += entrance.get_hidden_count()
	return total


func get_active_entrance_count() -> int:
	"""Get number of non-destroyed entrances"""
	var count: int = 0
	for entrance in entrances:
		if not entrance.is_destroyed():
			count += 1
	return count


func get_discovered_entrance_count() -> int:
	"""Get number of discovered entrances"""
	var count: int = 0
	for entrance in entrances:
		if entrance.is_discovered():
			count += 1
	return count
