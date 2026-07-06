extends Node
class_name DoctrineManager
## DoctrineManager - Enforces doctrine restrictions on units and buildings
## Singleton that validates requests against the active doctrine

signal doctrine_changed(doctrine: DoctrineData)
signal unit_request_denied(unit_type: int, reason: String)
signal building_request_denied(building_type: int, reason: String)

const DoctrineData = preload("res://battle_system/data/doctrine_data.gd")

## Active doctrine
var current_doctrine: DoctrineData = null

## Unit tracking
var _unit_counts: Dictionary = {}  # unit_type -> count
var _vehicle_count: int = 0
var _helicopter_count: int = 0


func _ready() -> void:
	# Connect to battle signals
	if BattleSignals:
		BattleSignals.unit_spawned.connect(_on_unit_spawned)
		BattleSignals.unit_died.connect(_on_unit_died)

	print("[DoctrineManager] Initialized")


## Set the active doctrine
func set_doctrine(doctrine: DoctrineData) -> void:
	current_doctrine = doctrine
	doctrine_changed.emit(doctrine)
	print("[DoctrineManager] Doctrine set: %s" % doctrine.doctrine_name)


## Set doctrine by ID
func set_doctrine_by_id(doctrine_id: String) -> void:
	var doctrine := DoctrineData.get_doctrine(doctrine_id)
	set_doctrine(doctrine)


## Get active doctrine
func get_doctrine() -> DoctrineData:
	return current_doctrine


## Check if a unit type can be requested
func can_request_unit(unit_type: int) -> bool:
	if not current_doctrine:
		return true  # No doctrine = no restrictions

	# Check if unit is available in doctrine
	if not current_doctrine.is_unit_available(unit_type):
		return false

	# Check unit limit
	var limit: int = current_doctrine.get_unit_limit(unit_type)
	if limit >= 0:
		var current: int = _unit_counts.get(unit_type, 0)
		if current >= limit:
			return false

	# Check vehicle/helicopter limits
	if _is_vehicle_unit(unit_type):
		if _vehicle_count >= current_doctrine.max_vehicles:
			return false
	elif _is_helicopter_unit(unit_type):
		if _helicopter_count >= current_doctrine.max_helicopters:
			return false

	return true


## Request a unit (returns false with reason if denied)
func request_unit(unit_type: int) -> Dictionary:
	"""Request a unit. Returns {allowed: bool, reason: String}"""
	if not current_doctrine:
		return {"allowed": true, "reason": ""}

	# Check availability
	if not current_doctrine.is_unit_available(unit_type):
		var reason := "Unit not available in %s doctrine" % current_doctrine.doctrine_name
		unit_request_denied.emit(unit_type, reason)
		return {"allowed": false, "reason": reason}

	# Check limit
	var limit: int = current_doctrine.get_unit_limit(unit_type)
	if limit >= 0:
		var current: int = _unit_counts.get(unit_type, 0)
		if current >= limit:
			var reason := "Unit limit reached (%d/%d)" % [current, limit]
			unit_request_denied.emit(unit_type, reason)
			return {"allowed": false, "reason": reason}

	# Check vehicle limit
	if _is_vehicle_unit(unit_type):
		if _vehicle_count >= current_doctrine.max_vehicles:
			var reason := "Vehicle limit reached (%d/%d)" % [_vehicle_count, current_doctrine.max_vehicles]
			unit_request_denied.emit(unit_type, reason)
			return {"allowed": false, "reason": reason}

	# Check helicopter limit
	if _is_helicopter_unit(unit_type):
		if _helicopter_count >= current_doctrine.max_helicopters:
			var reason := "Helicopter limit reached (%d/%d)" % [_helicopter_count, current_doctrine.max_helicopters]
			unit_request_denied.emit(unit_type, reason)
			return {"allowed": false, "reason": reason}

	return {"allowed": true, "reason": ""}


## Check if a building type can be built
func can_build(building_type: int) -> bool:
	if not current_doctrine:
		return true

	return current_doctrine.is_building_available(building_type)


## Request to build (returns false with reason if denied)
func request_build(building_type: int) -> Dictionary:
	"""Request to build. Returns {allowed: bool, reason: String}"""
	if not current_doctrine:
		return {"allowed": true, "reason": ""}

	if not current_doctrine.is_building_available(building_type):
		var reason := "Building not available in %s doctrine" % current_doctrine.doctrine_name
		building_request_denied.emit(building_type, reason)
		return {"allowed": false, "reason": reason}

	return {"allowed": true, "reason": ""}


## Get reinforcement cooldown modified by doctrine
func get_modified_cooldown(base_cooldown: float, unit_type: int) -> float:
	if not current_doctrine:
		return base_cooldown

	var is_vehicle: bool = _is_vehicle_unit(unit_type)
	var is_helo: bool = _is_helicopter_unit(unit_type)

	return current_doctrine.get_reinforcement_cooldown(base_cooldown, is_vehicle, is_helo)


## Get initial reinforcement delay
func get_initial_delay() -> float:
	if not current_doctrine:
		return 60.0
	return current_doctrine.initial_reinforcement_delay


## Get damage modifier for infantry
func get_infantry_damage_modifier() -> float:
	if not current_doctrine:
		return 1.0
	return current_doctrine.infantry_damage_modifier


## Get armor modifier for vehicles
func get_vehicle_armor_modifier() -> float:
	if not current_doctrine:
		return 1.0
	return current_doctrine.vehicle_armor_modifier


## Check if special ability is available
func can_call_napalm() -> bool:
	if not current_doctrine:
		return true
	return current_doctrine.can_call_napalm


func can_call_arc_light() -> bool:
	if not current_doctrine:
		return false
	return current_doctrine.can_call_arc_light


func has_rapid_insertion() -> bool:
	if not current_doctrine:
		return false
	return current_doctrine.has_rapid_insertion


# =============================================================================
# INTERNAL
# =============================================================================

func _is_vehicle_unit(unit_type: int) -> bool:
	"""Check if unit type is a ground vehicle"""
	return unit_type >= 20 and unit_type < 30


func _is_helicopter_unit(unit_type: int) -> bool:
	"""Check if unit type is a helicopter"""
	return unit_type >= 10 and unit_type < 20


func _on_unit_spawned(unit: Node3D, _faction: int) -> void:
	"""Track unit spawns"""
	if not unit.is_in_group("player_units"):
		return

	var unit_type: int = -1
	if unit.has_method("get") and unit.get("unit_type") != null:
		unit_type = unit.unit_type

	if unit_type < 0:
		return

	# Increment count
	_unit_counts[unit_type] = _unit_counts.get(unit_type, 0) + 1

	if _is_vehicle_unit(unit_type):
		_vehicle_count += 1
	elif _is_helicopter_unit(unit_type):
		_helicopter_count += 1


func _on_unit_died(unit: Node3D, _killer: Node3D) -> void:
	"""Track unit deaths"""
	if not unit.is_in_group("player_units"):
		return

	var unit_type: int = -1
	if unit.has_method("get") and unit.get("unit_type") != null:
		unit_type = unit.unit_type

	if unit_type < 0:
		return

	# Decrement count
	_unit_counts[unit_type] = maxi(_unit_counts.get(unit_type, 0) - 1, 0)

	if _is_vehicle_unit(unit_type):
		_vehicle_count = maxi(_vehicle_count - 1, 0)
	elif _is_helicopter_unit(unit_type):
		_helicopter_count = maxi(_helicopter_count - 1, 0)


# =============================================================================
# UI HELPERS
# =============================================================================

## Get doctrine info for UI
func get_doctrine_info() -> Dictionary:
	if not current_doctrine:
		return {}

	return {
		"name": current_doctrine.doctrine_name,
		"description": current_doctrine.description,
		"max_vehicles": current_doctrine.max_vehicles,
		"max_helicopters": current_doctrine.max_helicopters,
		"current_vehicles": _vehicle_count,
		"current_helicopters": _helicopter_count,
	}


## Get available doctrines for selection UI
static func get_available_doctrines() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for doctrine in DoctrineData.get_all_doctrines():
		result.append({
			"id": doctrine.doctrine_id,
			"name": doctrine.doctrine_name,
			"type": doctrine.doctrine_type,
			"description": doctrine.description,
		})

	return result
