extends Node
class_name ReinforcementManager

## Reinforcement Manager - Handles off-map unit reinforcements
## No barracks - units arrive via helicopter or convoy from base camp

signal reinforcement_requested(request: ReinforcementRequest)
signal reinforcement_dispatched(request: ReinforcementRequest)
signal reinforcement_arrived(units: Array, destination: Node3D)
signal request_failed(request: ReinforcementRequest, reason: String)

const Squad = preload("res://battle_system/nodes/squad.gd")

enum DeliveryMethod { HELICOPTER, CONVOY, AIRDROP }
enum RequestPriority { LOW, NORMAL, HIGH, EMERGENCY }

## Reinforcement pool (available off-map units by type)
var unit_pool: Dictionary = {}  # unit_type -> count

## Pending requests
var pending_requests: Array[ReinforcementRequest] = []
var active_requests: Array[ReinforcementRequest] = []

## Configuration
@export var base_delivery_time: float = 30.0  # Base time for reinforcements
@export var max_concurrent_deliveries: int = 3


class ReinforcementRequest:
	var id: int
	var unit_type: int
	var count: int
	var destination: Node3D
	var delivery_method: int
	var priority: int
	var eta: float
	var spawned_units: Array[Node3D]
	var state: int  # 0=pending, 1=en_route, 2=arrived, 3=failed

	static var _next_id: int = 0

	func _init() -> void:
		id = _next_id
		_next_id += 1
		spawned_units = []
		state = 0


func _ready() -> void:
	# Initialize unit pool
	_initialize_pool()
	print("[ReinforcementManager] Initialized")


func _initialize_pool() -> void:
	"""Set up initial reinforcement pool"""
	unit_pool = {
		GameEnums.UnitType.RIFLE_PLATOON: 10,
		GameEnums.UnitType.WEAPONS_SQUAD: 4,
		GameEnums.UnitType.ENGINEERS: 3,
		GameEnums.UnitType.SOG_TEAM: 2,
	}


func _process(delta: float) -> void:
	_process_pending_requests()
	_update_active_requests(delta)


func _process_pending_requests() -> void:
	"""Try to dispatch pending requests"""
	if pending_requests.is_empty():
		return

	if active_requests.size() >= max_concurrent_deliveries:
		return

	# Sort by priority
	pending_requests.sort_custom(func(a, b): return a.priority > b.priority)

	var to_dispatch: Array[ReinforcementRequest] = []

	for request in pending_requests:
		if active_requests.size() + to_dispatch.size() >= max_concurrent_deliveries:
			break

		# Check if we have units available
		if _can_fulfill_request(request):
			to_dispatch.append(request)

	for request in to_dispatch:
		pending_requests.erase(request)
		_dispatch_request(request)


func _can_fulfill_request(request: ReinforcementRequest) -> bool:
	"""Check if request can be fulfilled"""
	if request.unit_type not in unit_pool:
		return false

	return unit_pool[request.unit_type] >= request.count


func _dispatch_request(request: ReinforcementRequest) -> void:
	"""Send reinforcements"""
	# Deduct from pool
	unit_pool[request.unit_type] -= request.count

	# Calculate ETA
	request.eta = _calculate_eta(request)
	request.state = 1  # en_route

	active_requests.append(request)
	reinforcement_dispatched.emit(request)

	# Handle by delivery method
	match request.delivery_method:
		DeliveryMethod.HELICOPTER:
			_dispatch_helicopter(request)
		DeliveryMethod.CONVOY:
			_dispatch_convoy(request)
		DeliveryMethod.AIRDROP:
			_dispatch_airdrop(request)

	print("[ReinforcementManager] Dispatched %d units via %s (ETA: %.1fs)" % [
		request.count,
		_get_delivery_name(request.delivery_method),
		request.eta
	])


func _calculate_eta(request: ReinforcementRequest) -> float:
	"""Calculate delivery time"""
	var base_time: float = base_delivery_time

	# Adjust by delivery method
	match request.delivery_method:
		DeliveryMethod.HELICOPTER:
			base_time *= 0.5  # Fastest
		DeliveryMethod.CONVOY:
			base_time *= 1.5  # Slowest
		DeliveryMethod.AIRDROP:
			base_time *= 0.7

	# Priority modifier
	match request.priority:
		RequestPriority.EMERGENCY:
			base_time *= 0.5
		RequestPriority.HIGH:
			base_time *= 0.7
		RequestPriority.LOW:
			base_time *= 1.3

	return base_time


func _dispatch_helicopter(request: ReinforcementRequest) -> void:
	"""Dispatch via helicopter insertion"""
	if InsertionManager:
		# Spawn units (hidden for now)
		var units: Array[Node3D] = _spawn_units(request, true)
		request.spawned_units = units

		# Request helicopter insertion via InsertionManager instance
		var insertion_mgr: Node = get_node_or_null("/root/InsertionManager")
		if not insertion_mgr:
			# Try to find in current scene
			var mgrs: Array[Node] = get_tree().get_nodes_in_group("insertion_managers")
			if not mgrs.is_empty():
				insertion_mgr = mgrs[0]

		if insertion_mgr and insertion_mgr.has_method("request_insertion"):
			insertion_mgr.request_insertion(units, request.destination)
		else:
			push_warning("[ReinforcementManager] InsertionManager not found - cannot dispatch helicopter")


func _dispatch_convoy(request: ReinforcementRequest) -> void:
	"""Dispatch via ground convoy"""
	# Convoy takes longer, handled by timer
	pass


func _dispatch_airdrop(request: ReinforcementRequest) -> void:
	"""Dispatch via airdrop"""
	# Instant drop at location
	pass


func _update_active_requests(delta: float) -> void:
	"""Update delivery timers"""
	var completed: Array[ReinforcementRequest] = []

	for request in active_requests:
		request.eta -= delta

		if request.eta <= 0:
			_complete_request(request)
			completed.append(request)

	for request in completed:
		active_requests.erase(request)


func _complete_request(request: ReinforcementRequest) -> void:
	"""Complete a reinforcement request"""
	request.state = 2  # arrived

	# Spawn units at destination if not already spawned
	if request.spawned_units.is_empty():
		request.spawned_units = _spawn_units(request, false)

	# Make units visible and active
	for unit in request.spawned_units:
		if is_instance_valid(unit):
			unit.visible = true
			unit.set_physics_process(true)

	reinforcement_arrived.emit(request.spawned_units, request.destination)

	if BattleSignals:
		for unit in request.spawned_units:
			BattleSignals.reinforcement_arrived.emit(unit, request.destination)

	print("[ReinforcementManager] %d units arrived at %s" % [
		request.spawned_units.size(),
		request.destination.name if request.destination else "position"
	])


func _spawn_units(request: ReinforcementRequest, hidden: bool) -> Array[Node3D]:
	"""Spawn units for a request"""
	var units: Array[Node3D] = []
	var data: Resource = _get_unit_data(request.unit_type)

	if not data:
		return units

	var spawn_pos: Vector3 = Vector3.ZERO
	if request.destination:
		spawn_pos = request.destination.global_position

	for i in request.count:
		var unit := Squad.new()
		unit.name = "Reinforcement_%d_%d" % [request.id, i]
		unit.data = data

		# Offset position
		var offset := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		unit.position = spawn_pos + offset

		if hidden:
			unit.visible = false
			unit.set_physics_process(false)

		get_tree().current_scene.add_child(unit)
		units.append(unit)

		# Emit spawn signal
		var faction: int = data.faction if data.has_method("get") else GameEnums.Faction.US_ARMY
		BattleSignals.unit_spawned.emit(unit, faction)

	return units


func _get_unit_data(unit_type: int) -> Resource:
	"""Get unit data resource for a type"""
	var path: String = ""

	match unit_type:
		GameEnums.UnitType.RIFLE_PLATOON:
			path = "res://battle_system/data/units/us_rifle_platoon.tres"
		GameEnums.UnitType.WEAPONS_SQUAD:
			path = "res://battle_system/data/units/us_weapons_squad.tres"
		GameEnums.UnitType.ENGINEERS:
			path = "res://battle_system/data/units/us_engineers.tres"
		GameEnums.UnitType.SOG_TEAM:
			path = "res://battle_system/data/units/us_sog_team.tres"
		_:
			path = "res://battle_system/data/units/us_rifle_platoon.tres"

	if ResourceLoader.exists(path):
		return load(path)
	return null


func _get_delivery_name(method: int) -> String:
	match method:
		DeliveryMethod.HELICOPTER:
			return "Helicopter"
		DeliveryMethod.CONVOY:
			return "Convoy"
		DeliveryMethod.AIRDROP:
			return "Airdrop"
	return "Unknown"


## Public API

func request_reinforcements(
	unit_type: int,
	count: int,
	destination: Node3D,
	method: int = DeliveryMethod.HELICOPTER,
	priority: int = RequestPriority.NORMAL
) -> ReinforcementRequest:
	"""Request reinforcements"""
	var request := ReinforcementRequest.new()
	request.unit_type = unit_type
	request.count = count
	request.destination = destination
	request.delivery_method = method
	request.priority = priority

	pending_requests.append(request)
	reinforcement_requested.emit(request)

	if BattleSignals:
		BattleSignals.reinforcement_requested.emit(unit_type, destination)

	return request


func get_available_units(unit_type: int) -> int:
	"""Get available count for a unit type"""
	if unit_type in unit_pool:
		return unit_pool[unit_type]
	return 0


func add_to_pool(unit_type: int, count: int) -> void:
	"""Add units to the reinforcement pool"""
	if unit_type not in unit_pool:
		unit_pool[unit_type] = 0
	unit_pool[unit_type] += count


func get_pending_count() -> int:
	return pending_requests.size()


func get_active_count() -> int:
	return active_requests.size()


func cancel_request(request: ReinforcementRequest) -> bool:
	"""Cancel a pending request"""
	if request in pending_requests:
		pending_requests.erase(request)
		# Refund pool
		unit_pool[request.unit_type] += request.count
		return true
	return false
