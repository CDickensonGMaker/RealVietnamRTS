extends Node
## ReinforcementManager - Manages off-map reinforcement requests
## Units come from base camp, not spawned from buildings
## Accessed globally via ReinforcementManager autoload (no class_name needed)

signal reinforcement_requested(request)  # ReinforcementRequest
signal reinforcement_dispatched(request)  # ReinforcementRequest
signal reinforcement_arrived(request)  # ReinforcementRequest
signal reinforcement_lost(request)  # ReinforcementRequest

# Reinforcement pool (what's available at base camp)
var available_reinforcements := {
	GameEnums.UnitType.RIFLE_PLATOON: 5,
	GameEnums.UnitType.WEAPONS_SQUAD: 3,
	GameEnums.UnitType.ENGINEERS: 2,
	GameEnums.UnitType.ARMOR: 2,
	GameEnums.UnitType.SOG_TEAM: 2,
}

# Units that can be transported by helicopter
const AIRBORNE_UNITS: Array[int] = [
	GameEnums.UnitType.RIFLE_PLATOON,
	GameEnums.UnitType.WEAPONS_SQUAD,
	GameEnums.UnitType.ENGINEERS,
	GameEnums.UnitType.SOG_TEAM,
]

# Pending requests
var pending_requests: Array = []  # Array of ReinforcementRequest
var active_requests: Array = []  # Array of ReinforcementRequest

# Cooldown between requests
var request_cooldown: float = 0.0
const REQUEST_COOLDOWN_TIME := 30.0  # 30 seconds between requests

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if request_cooldown > 0:
		request_cooldown -= delta

	_process_pending_requests()

# =============================================================================
# REINFORCEMENT REQUESTS
# =============================================================================

func request_reinforcements(unit_type: int, destination: Node3D,
							priority: int = 1):  # Returns ReinforcementRequest
	## Request reinforcements from base camp
	var request: ReinforcementRequest = ReinforcementRequest.new()
	request.unit_type = unit_type
	request.destination = destination
	request.priority = priority
	request.status = ReinforcementRequest.Status.PENDING

	# Check availability
	if available_reinforcements.get(unit_type, 0) <= 0:
		request.status = ReinforcementRequest.Status.UNAVAILABLE
		return request

	# Check cooldown
	if request_cooldown > 0:
		request.status = ReinforcementRequest.Status.ON_COOLDOWN
		return request

	# Calculate ETA
	if unit_type in AIRBORNE_UNITS:
		request.delivery_method = ReinforcementRequest.DeliveryMethod.HELICOPTER
		request.eta = 60.0  # 1 minute for helicopter
	else:
		request.delivery_method = ReinforcementRequest.DeliveryMethod.CONVOY
		request.eta = 180.0  # 3 minutes for convoy

	pending_requests.append(request)
	reinforcement_requested.emit(request)

	return request

func can_request_unit(unit_type: int) -> bool:
	return available_reinforcements.get(unit_type, 0) > 0 and request_cooldown <= 0

func get_available_count(unit_type: int) -> int:
	return available_reinforcements.get(unit_type, 0)

# =============================================================================
# REQUEST PROCESSING
# =============================================================================

func _process_pending_requests() -> void:
	var dispatched: Array = []  # Array of ReinforcementRequest

	for request in pending_requests:
		if request.status == ReinforcementRequest.Status.PENDING:
			_dispatch_request(request)
			dispatched.append(request)

	for request in dispatched:
		pending_requests.erase(request)
		active_requests.append(request)

func _dispatch_request(request) -> void:  # request: ReinforcementRequest
	# Consume from pool
	available_reinforcements[request.unit_type] -= 1

	# Start cooldown
	request_cooldown = REQUEST_COOLDOWN_TIME

	request.status = ReinforcementRequest.Status.EN_ROUTE

	# Dispatch via appropriate method
	match request.delivery_method:
		ReinforcementRequest.DeliveryMethod.HELICOPTER:
			# Use call() for runtime method resolution on autoload
			InsertionManager.call("queue_insertion", request)
		ReinforcementRequest.DeliveryMethod.CONVOY:
			_dispatch_convoy(request)

	reinforcement_dispatched.emit(request)
	BattleSignals.reinforcement_dispatched.emit(request.unit_type, request.eta)

func _dispatch_convoy(request: ReinforcementRequest) -> void:
	# Create convoy for ground reinforcements
	# This would interface with ConvoyManager
	pass

# =============================================================================
# ARRIVAL HANDLING
# =============================================================================

func on_reinforcement_arrived(request, units: Array) -> void:  # request: ReinforcementRequest
	## Called when reinforcements successfully arrive
	request.status = ReinforcementRequest.Status.ARRIVED
	request.delivered_units = units
	active_requests.erase(request)

	reinforcement_arrived.emit(request)
	BattleSignals.reinforcement_arrived.emit(units, request.destination)

func on_reinforcement_lost(request) -> void:  # request: ReinforcementRequest
	## Called when reinforcements are lost in transit
	request.status = ReinforcementRequest.Status.LOST
	active_requests.erase(request)

	reinforcement_lost.emit(request)

# =============================================================================
# POOL MANAGEMENT
# =============================================================================

func replenish_pool(unit_type: int, count: int) -> void:
	## Add units back to the reinforcement pool
	if available_reinforcements.has(unit_type):
		available_reinforcements[unit_type] += count

func get_pool_status() -> Dictionary:
	return available_reinforcements.duplicate()


# =============================================================================
# REINFORCEMENT REQUEST CLASS
# =============================================================================

class ReinforcementRequest:
	extends RefCounted

	enum Status { PENDING, ON_COOLDOWN, UNAVAILABLE, EN_ROUTE, ARRIVED, LOST }
	enum DeliveryMethod { HELICOPTER, CONVOY }

	var unit_type: int
	var destination: Node3D
	var priority: int = 1
	var eta: float = 60.0
	var status: Status = Status.PENDING
	var delivery_method: DeliveryMethod = DeliveryMethod.HELICOPTER
	var delivered_units: Array = []

	func get_status_string() -> String:
		match status:
			Status.PENDING: return "Pending"
			Status.ON_COOLDOWN: return "On Cooldown"
			Status.UNAVAILABLE: return "Unavailable"
			Status.EN_ROUTE: return "En Route"
			Status.ARRIVED: return "Arrived"
			Status.LOST: return "Lost"
			_: return "Unknown"
