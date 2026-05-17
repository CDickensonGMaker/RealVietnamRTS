extends Node
## SupplyManager - Manages firebase supply levels, consumption, and resupply operations
## Accessed globally via SupplyManager autoload (no class_name needed)

# Preload classes to avoid parser-time dependency issues
const LandingZoneClass = preload("res://helicopter_system/landing_zone.gd")
const HeliMissionClass = preload("res://helicopter_system/heli_mission.gd")

signal supply_warning(firebase: Node3D, supply_type: int, level: float)
signal supply_critical(firebase: Node3D, supply_type: int)
signal supply_depleted(firebase: Node3D, supply_type: int)
signal supply_delivered(firebase: Node3D, supply_type: int, amount: float)
signal resupply_scheduled(firebase: Node3D, supply_type: int, eta: float)
signal resupply_cancelled(firebase: Node3D, supply_type: int)

# =============================================================================
# SUPPLY TYPES
# =============================================================================

enum SupplyType {
	AMMUNITION,     # Bullets, grenades, mortar rounds
	FUEL,           # Vehicle and helicopter fuel
	RATIONS,        # Food and water
	MEDICAL,        # Bandages, plasma, morphine
	CONSTRUCTION,   # Building materials, sandbags
}

# Warning thresholds (percentage)
const WARNING_THRESHOLD := 0.3     # 30% - schedule resupply
const CRITICAL_THRESHOLD := 0.15   # 15% - priority resupply
const DEPLETED_THRESHOLD := 0.05   # 5% - operations degraded

# Supply consumption rates per unit per minute
const CONSUMPTION_RATES := {
	SupplyType.AMMUNITION: 0.5,     # Per combat unit
	SupplyType.FUEL: 0.2,           # Per vehicle/helicopter
	SupplyType.RATIONS: 0.1,        # Per all units
	SupplyType.MEDICAL: 0.05,       # Per wounded treatment
	SupplyType.CONSTRUCTION: 0.0,   # Consumed during building
}

# Combat consumption multipliers
const COMBAT_CONSUMPTION_MULTIPLIER := 3.0  # 3x ammo during combat

# Resupply package sizes (per delivery)
const RESUPPLY_AMOUNTS := {
	SupplyType.AMMUNITION: 50.0,
	SupplyType.FUEL: 40.0,
	SupplyType.RATIONS: 30.0,
	SupplyType.MEDICAL: 25.0,
	SupplyType.CONSTRUCTION: 100.0,
}

# =============================================================================
# STATE
# =============================================================================

# Firebase supply tracking
var firebase_supplies: Dictionary = {}  # firebase_id -> SupplyData

# Pending resupply operations
var pending_resupply: Array = []  # Array of ResupplyOperation
var active_resupply: Array = []  # Array of ResupplyOperation

# Auto-resupply settings
var auto_resupply_enabled: bool = true
var auto_resupply_threshold: float = WARNING_THRESHOLD

# Main supply depot (off-map)
var depot_position: Vector3 = Vector3(-500, 0, 0)
var depot_supplies: Dictionary = {
	SupplyType.AMMUNITION: 9999.0,
	SupplyType.FUEL: 9999.0,
	SupplyType.RATIONS: 9999.0,
	SupplyType.MEDICAL: 9999.0,
	SupplyType.CONSTRUCTION: 9999.0,
}

class SupplyData:
	var firebase: Node3D
	var levels: Dictionary = {}
	var max_storage: Dictionary = {}
	var in_combat: bool = false
	var garrison_size: int = 0
	var vehicle_count: int = 0

	func _init() -> void:
		for supply_type in SupplyType.values():
			levels[supply_type] = 100.0
			max_storage[supply_type] = 100.0

	func get_level(supply_type: int) -> float:
		return levels.get(supply_type, 0.0)

	func get_percentage(supply_type: int) -> float:
		var max_val: float = max_storage.get(supply_type, 100.0)
		if max_val <= 0:
			return 0.0
		return levels.get(supply_type, 0.0) / max_val

	func consume(supply_type: int, amount: float) -> float:
		var current: float = levels.get(supply_type, 0.0)
		var consumed: float = minf(amount, current)
		levels[supply_type] = current - consumed
		return consumed

	func add(supply_type: int, amount: float) -> void:
		var current: float = levels.get(supply_type, 0.0)
		var max_val: float = max_storage.get(supply_type, 100.0)
		levels[supply_type] = minf(current + amount, max_val)


class ResupplyOperation:
	var firebase: Node3D
	var supply_type: int
	var amount: float
	var priority: int = 1
	var method: int = 0  # 0 = auto, 1 = helicopter, 2 = convoy
	var eta: float = 0.0
	var is_active: bool = false
	var assigned_transport: Node3D = null

func _ready() -> void:
	# Connect to relevant signals
	BattleSignals.firebase_established.connect(_on_firebase_established)
	BattleSignals.firebase_destroyed.connect(_on_firebase_destroyed)
	BattleSignals.convoy_arrived.connect(_on_convoy_arrived)

func _process(delta: float) -> void:
	_process_consumption(delta)
	_check_supply_levels()
	_process_resupply_operations(delta)

# =============================================================================
# FIREBASE REGISTRATION
# =============================================================================

func register_firebase(firebase: Node3D) -> void:
	var data: SupplyData = SupplyData.new()
	data.firebase = firebase

	# Set max storage based on firebase level
	var firebase_level: int = 0
	if firebase.has_method("get_level"):
		firebase_level = firebase.get_level()

	var storage_multiplier: float = 1.0 + firebase_level * 0.5
	for supply_type in SupplyType.values():
		data.max_storage[supply_type] = 100.0 * storage_multiplier
		data.levels[supply_type] = 100.0 * storage_multiplier  # Start full

	firebase_supplies[firebase.get_instance_id()] = data

func unregister_firebase(firebase: Node3D) -> void:
	firebase_supplies.erase(firebase.get_instance_id())
	# Cancel any pending resupply
	_cancel_resupply_for_firebase(firebase)

func get_supply_data(firebase: Node3D):  # Returns SupplyData
	return firebase_supplies.get(firebase.get_instance_id(), null)

# =============================================================================
# SUPPLY QUERIES
# =============================================================================

func get_supply_level(firebase: Node3D, supply_type: int) -> float:
	var data = get_supply_data(firebase)  # SupplyData
	return data.get_level(supply_type) if data else 0.0

func get_supply_percentage(firebase: Node3D, supply_type: int) -> float:
	var data = get_supply_data(firebase)  # SupplyData
	return data.get_percentage(supply_type) if data else 0.0

func get_all_supply_levels(firebase: Node3D) -> Dictionary:
	var data = get_supply_data(firebase)  # SupplyData
	return data.levels.duplicate() if data else {}

func get_supply_status(firebase: Node3D) -> Dictionary:
	var data = get_supply_data(firebase)  # SupplyData
	if not data:
		return {}

	var status: Dictionary = {}
	for supply_type in SupplyType.values():
		var pct: float = data.get_percentage(supply_type)
		var level_str: String = "normal"
		if pct <= DEPLETED_THRESHOLD:
			level_str = "depleted"
		elif pct <= CRITICAL_THRESHOLD:
			level_str = "critical"
		elif pct <= WARNING_THRESHOLD:
			level_str = "warning"

		status[supply_type] = {
			"level": data.get_level(supply_type),
			"percentage": pct,
			"status": level_str,
		}

	return status

# =============================================================================
# CONSUMPTION
# =============================================================================

func _process_consumption(delta: float) -> void:
	var consumption_delta: float = delta / 60.0  # Convert to per-minute rate

	for fb_id in firebase_supplies:
		var data = firebase_supplies[fb_id]  # SupplyData
		if not is_instance_valid(data.firebase):
			continue

		# Update garrison/vehicle counts
		_update_firebase_counts(data)

		# Process each supply type
		for supply_type in SupplyType.values():
			var base_rate: float = CONSUMPTION_RATES.get(supply_type, 0.0)
			var consumption: float = 0.0

			match supply_type:
				SupplyType.AMMUNITION:
					consumption = base_rate * data.garrison_size * consumption_delta
					if data.in_combat:
						consumption *= COMBAT_CONSUMPTION_MULTIPLIER

				SupplyType.FUEL:
					consumption = base_rate * data.vehicle_count * consumption_delta

				SupplyType.RATIONS:
					consumption = base_rate * data.garrison_size * consumption_delta

				SupplyType.MEDICAL:
					# Medical consumed when treating wounded
					consumption = 0.0  # Handled separately

				SupplyType.CONSTRUCTION:
					# Consumed during building
					consumption = 0.0  # Handled separately

			if consumption > 0:
				data.consume(supply_type, consumption)

func _update_firebase_counts(data) -> void:  # data: SupplyData
	if not is_instance_valid(data.firebase):
		return

	# Get garrison size
	if data.firebase.has_method("get_garrison_size"):
		data.garrison_size = data.firebase.get_garrison_size()
	else:
		data.garrison_size = 10  # Default

	# Get vehicle count
	if data.firebase.has_method("get_vehicle_count"):
		data.vehicle_count = data.firebase.get_vehicle_count()
	else:
		data.vehicle_count = 0

	# Check if in combat
	if data.firebase.has_method("is_under_attack"):
		data.in_combat = data.firebase.is_under_attack()
	else:
		data.in_combat = false

# =============================================================================
# SUPPLY LEVEL CHECKS
# =============================================================================

func _check_supply_levels() -> void:
	for fb_id in firebase_supplies:
		var data = firebase_supplies[fb_id]  # SupplyData
		if not is_instance_valid(data.firebase):
			continue

		for supply_type in SupplyType.values():
			var pct: float = data.get_percentage(supply_type)

			if pct <= DEPLETED_THRESHOLD:
				supply_depleted.emit(data.firebase, supply_type)
				BattleSignals.supply_depleted.emit(data.firebase, _get_supply_name(supply_type))
				_schedule_emergency_resupply(data.firebase, supply_type)

			elif pct <= CRITICAL_THRESHOLD:
				supply_critical.emit(data.firebase, supply_type)
				_schedule_priority_resupply(data.firebase, supply_type)

			elif pct <= WARNING_THRESHOLD:
				supply_warning.emit(data.firebase, supply_type, pct)
				BattleSignals.supply_low.emit(data.firebase, _get_supply_name(supply_type))
				if auto_resupply_enabled:
					_schedule_resupply(data.firebase, supply_type)

# =============================================================================
# RESUPPLY OPERATIONS
# =============================================================================

func request_resupply(firebase: Node3D, supply_type: int,
					  priority: int = 1, method: int = 0) -> bool:
	## Manually request resupply
	# Check if already pending
	for op in pending_resupply:
		if op.firebase == firebase and op.supply_type == supply_type:
			return false

	var op: ResupplyOperation = ResupplyOperation.new()
	op.firebase = firebase
	op.supply_type = supply_type
	op.amount = RESUPPLY_AMOUNTS.get(supply_type, 50.0)
	op.priority = priority
	op.method = method

	pending_resupply.append(op)
	return true

func _schedule_resupply(firebase: Node3D, supply_type: int) -> void:
	request_resupply(firebase, supply_type, 1)

func _schedule_priority_resupply(firebase: Node3D, supply_type: int) -> void:
	request_resupply(firebase, supply_type, 5)

func _schedule_emergency_resupply(firebase: Node3D, supply_type: int) -> void:
	request_resupply(firebase, supply_type, 10)

func _cancel_resupply_for_firebase(firebase: Node3D) -> void:
	pending_resupply = pending_resupply.filter(func(op): return op.firebase != firebase)
	active_resupply = active_resupply.filter(func(op): return op.firebase != firebase)

func _process_resupply_operations(delta: float) -> void:
	# Sort pending by priority
	pending_resupply.sort_custom(func(a, b): return a.priority > b.priority)

	# Try to dispatch pending operations
	while not pending_resupply.is_empty():
		var op = pending_resupply[0]  # ResupplyOperation

		if _can_dispatch_resupply(op):
			pending_resupply.remove_at(0)
			_dispatch_resupply(op)
		else:
			break  # Can't dispatch more right now

	# Update active operations
	for op in active_resupply:
		op.eta -= delta

func _can_dispatch_resupply(op) -> bool:  # op: ResupplyOperation
	# Check if transport is available
	var method: int = op.method

	if method == 0:  # Auto - choose best
		# Prefer helicopter for urgent, convoy for bulk
		if op.priority >= 5:
			method = 1  # Helicopter
		else:
			method = 2  # Convoy

	match method:
		1:  # Helicopter
			return InsertionManager.available_transport_hueys > 0
		2:  # Convoy
			return true  # Always can dispatch convoy
		_:
			return false

func _dispatch_resupply(op) -> void:  # op: ResupplyOperation
	var method: int = op.method
	if method == 0:
		method = 1 if op.priority >= 5 else 2

	match method:
		1:  # Helicopter resupply
			_dispatch_helicopter_resupply(op)
		2:  # Convoy resupply
			_dispatch_convoy_resupply(op)

	op.is_active = true
	active_resupply.append(op)

	resupply_scheduled.emit(op.firebase, op.supply_type, op.eta)

func _dispatch_helicopter_resupply(op) -> void:  # op: ResupplyOperation
	# Find LZ at firebase
	var lz = null  # LandingZone
	if op.firebase.has_method("get_helipad"):
		lz = op.firebase.get_helipad()

	if not lz:
		# Use firebase position as LZ
		lz = LandingZoneClass.new()
		lz.global_position = op.firebase.global_position

	# Create supply mission
	var mission: HeliMissionClass = HeliMissionClass.new()
	mission.mission_type = GameEnums.HeliMissionType.SUPPLY_RUN
	mission.destination_lz = lz
	mission.cargo = [{"type": "supply", "supply_type": op.supply_type, "amount": op.amount}]
	mission.priority = op.priority

	InsertionManager.queue_insertion(mission)
	op.eta = 90.0  # ~1.5 minutes for helicopter

func _dispatch_convoy_resupply(op) -> void:  # op: ResupplyOperation
	# Create supply convoy (Convoy is an inner class of ConvoyManager autoload)
	var convoy = ConvoyManager.create_supply_convoy(
		op.firebase, int(op.amount)
	)

	convoy.set_meta("supply_type", op.supply_type)
	op.assigned_transport = convoy
	op.eta = 180.0  # ~3 minutes for convoy

# =============================================================================
# DELIVERY HANDLERS
# =============================================================================

func deliver_supplies(firebase: Node3D, supply_type: int, amount: float) -> void:
	## Actually add supplies to firebase
	var data = get_supply_data(firebase)  # SupplyData
	if data:
		data.add(supply_type, amount)
		supply_delivered.emit(firebase, supply_type, amount)
		BattleSignals.supply_delivered.emit(firebase, amount)

		# Remove from active resupply
		active_resupply = active_resupply.filter(func(op):
			return not (op.firebase == firebase and op.supply_type == supply_type)
		)

func consume_for_construction(firebase: Node3D, amount: float) -> bool:
	## Consume construction supplies
	var data = get_supply_data(firebase)  # SupplyData
	if not data:
		return false

	var available: float = data.get_level(SupplyType.CONSTRUCTION)
	if available < amount:
		return false

	data.consume(SupplyType.CONSTRUCTION, amount)
	return true

func consume_for_healing(firebase: Node3D, amount: float) -> bool:
	## Consume medical supplies
	var data = get_supply_data(firebase)  # SupplyData
	if not data:
		return false

	var available: float = data.get_level(SupplyType.MEDICAL)
	if available < amount:
		return false

	data.consume(SupplyType.MEDICAL, amount)
	return true

# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_firebase_established(firebase: Node3D) -> void:
	register_firebase(firebase)

func _on_firebase_destroyed(firebase: Node3D) -> void:
	unregister_firebase(firebase)

func _on_convoy_arrived(convoy: Node3D, destination: Node3D) -> void:
	if not is_instance_valid(convoy):
		return

	var supply_type: int = convoy.get_meta("supply_type", SupplyType.AMMUNITION)
	var supplies: int = 0

	if convoy.has_method("get_supplies_carried"):
		supplies = convoy.get_supplies_carried()
	elif convoy.get("supplies_carried") != null:
		supplies = convoy.supplies_carried

	deliver_supplies(destination, supply_type, float(supplies))

# =============================================================================
# UTILITIES
# =============================================================================

func _get_supply_name(supply_type: int) -> String:
	match supply_type:
		SupplyType.AMMUNITION:
			return "Ammunition"
		SupplyType.FUEL:
			return "Fuel"
		SupplyType.RATIONS:
			return "Rations"
		SupplyType.MEDICAL:
			return "Medical"
		SupplyType.CONSTRUCTION:
			return "Construction"
		_:
			return "Unknown"

func get_supply_type_icon(supply_type: int) -> String:
	match supply_type:
		SupplyType.AMMUNITION:
			return "ammo"
		SupplyType.FUEL:
			return "fuel"
		SupplyType.RATIONS:
			return "food"
		SupplyType.MEDICAL:
			return "medical"
		SupplyType.CONSTRUCTION:
			return "construction"
		_:
			return "unknown"
