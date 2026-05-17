extends Node
class_name InsertionManager

## Insertion Manager - Manages all helicopter operations
## Handles missions, helicopter allocation, flight coordination

signal mission_started(mission: HeliMission)
signal mission_completed(mission: HeliMission)
signal helicopter_dispatched(helicopter: Node3D, mission: HeliMission)
signal insertion_complete(troops: Array, lz: Node3D)
signal extraction_complete(troops: Array, lz: Node3D)

const Helicopter = preload("res://helicopter_system/helicopter.gd")
const HeliMission = preload("res://helicopter_system/heli_mission.gd")
const LandingZone = preload("res://helicopter_system/landing_zone.gd")

## Helicopter pool
var available_helicopters: Array[Node3D] = []
var active_helicopters: Array[Node3D] = []

## Mission queue
var active_missions: Array[HeliMission] = []
var pending_missions: Array[HeliMission] = []

## Configuration
@export var max_helicopters: int = 8
@export var helicopter_respawn_time: float = 60.0

## State
var _respawn_timers: Array[float] = []


func _ready() -> void:
	print("[InsertionManager] Initialized")

	# Connect to signals
	if BattleSignals:
		BattleSignals.request_medevac.connect(_on_medevac_requested)


func _process(delta: float) -> void:
	# Update missions
	_update_missions(delta)

	# Process respawn timers
	_update_respawns(delta)

	# Try to assign helicopters to pending missions
	_process_pending_missions()


func _update_missions(delta: float) -> void:
	"""Update all active missions"""
	var completed: Array[HeliMission] = []

	for mission in active_missions:
		mission.update(delta)

		if mission.state == HeliMission.MissionState.COMPLETE:
			if mission.can_repeat():
				mission.start()
			else:
				completed.append(mission)

	# Remove completed non-repeating missions
	for mission in completed:
		active_missions.erase(mission)
		mission_completed.emit(mission)


func _update_respawns(delta: float) -> void:
	"""Handle helicopter respawn timers"""
	var i: int = _respawn_timers.size() - 1
	while i >= 0:
		_respawn_timers[i] -= delta
		if _respawn_timers[i] <= 0:
			_respawn_timers.remove_at(i)
			_spawn_helicopter()
		i -= 1


func _process_pending_missions() -> void:
	"""Try to assign helicopters to pending missions"""
	if pending_missions.is_empty() or available_helicopters.is_empty():
		return

	# Sort by priority
	pending_missions.sort_custom(func(a, b): return a.priority > b.priority)

	var to_start: Array[HeliMission] = []

	for mission in pending_missions:
		var helis_needed: int = _get_helicopters_needed(mission)

		if available_helicopters.size() >= helis_needed:
			# Assign helicopters
			for j in helis_needed:
				var heli: Node3D = available_helicopters.pop_front()
				mission.assigned_helicopters.append(heli)
				active_helicopters.append(heli)

			to_start.append(mission)

	# Start assigned missions
	for mission in to_start:
		pending_missions.erase(mission)
		active_missions.append(mission)
		mission.start()
		mission_started.emit(mission)
		_execute_mission(mission)


func _get_helicopters_needed(mission: HeliMission) -> int:
	"""Determine how many helicopters a mission needs"""
	match mission.mission_type:
		HeliMission.MissionType.INSERTION, HeliMission.MissionType.EXTRACTION:
			var troop_count: int = mission.cargo_manifest.size()
			return ceili(float(troop_count) / 8.0)  # 8 troops per Huey
		HeliMission.MissionType.SUPPLY_RUN:
			return 1
		HeliMission.MissionType.MEDEVAC_STANDBY:
			return 1
		HeliMission.MissionType.GUNSHIP_CAP:
			return 2
		HeliMission.MissionType.ESCORT_DUTY:
			return 2
		_:
			return 1


func _execute_mission(mission: HeliMission) -> void:
	"""Execute a mission with assigned helicopters"""
	for heli in mission.assigned_helicopters:
		helicopter_dispatched.emit(heli, mission)

	match mission.mission_type:
		HeliMission.MissionType.INSERTION:
			_execute_insertion(mission)
		HeliMission.MissionType.EXTRACTION:
			_execute_extraction(mission)
		HeliMission.MissionType.SUPPLY_RUN:
			_execute_supply_run(mission)
		HeliMission.MissionType.GUNSHIP_CAP:
			_execute_gunship_cap(mission)


func _execute_insertion(mission: HeliMission) -> void:
	"""Execute troop insertion"""
	if mission.assigned_helicopters.is_empty():
		return

	var heli: Node3D = mission.assigned_helicopters[0]
	if not heli is Helicopter:
		return

	# Load troops
	heli.load_troops(mission.cargo_manifest)

	# Fly to destination
	if mission.destination_lz:
		heli.landed.connect(_on_insertion_landed.bind(mission), CONNECT_ONE_SHOT)
		heli.fly_to(mission.destination_lz.global_position, mission.destination_lz)


func _on_insertion_landed(helicopter: Node3D, _lz: Node3D, mission: HeliMission) -> void:
	"""Handle helicopter landed for insertion"""
	if helicopter is Helicopter:
		var troops: Array[Node3D] = helicopter.unload_troops()
		insertion_complete.emit(troops, mission.destination_lz)

		# Return helicopter to pool after departure
		helicopter.took_off.connect(_on_helicopter_returned.bind(mission), CONNECT_ONE_SHOT)
		helicopter.take_off()


func _execute_extraction(mission: HeliMission) -> void:
	"""Execute troop extraction"""
	if mission.assigned_helicopters.is_empty():
		return

	var heli: Node3D = mission.assigned_helicopters[0]
	if not heli is Helicopter:
		return

	# Fly to pickup
	if mission.origin_lz:
		heli.landed.connect(_on_extraction_pickup.bind(mission), CONNECT_ONE_SHOT)
		heli.fly_to(mission.origin_lz.global_position, mission.origin_lz)


func _on_extraction_pickup(helicopter: Node3D, _lz: Node3D, mission: HeliMission) -> void:
	"""Handle helicopter landed for extraction pickup"""
	if not helicopter is Helicopter:
		return

	# Find troops at LZ to extract
	var troops_at_lz: Array[Node3D] = _find_troops_at_lz(mission.origin_lz)
	helicopter.load_troops(troops_at_lz)

	# Fly to dropoff
	if mission.destination_lz:
		helicopter.landed.connect(_on_extraction_dropoff.bind(mission), CONNECT_ONE_SHOT)
		helicopter.take_off()

		# Wait for takeoff then fly
		await helicopter.took_off
		helicopter.fly_to(mission.destination_lz.global_position, mission.destination_lz)


func _on_extraction_dropoff(helicopter: Node3D, _lz: Node3D, mission: HeliMission) -> void:
	"""Handle helicopter landed for extraction dropoff"""
	if helicopter is Helicopter:
		var troops: Array[Node3D] = helicopter.unload_troops()
		extraction_complete.emit(troops, mission.destination_lz)

		helicopter.took_off.connect(_on_helicopter_returned.bind(mission), CONNECT_ONE_SHOT)
		helicopter.take_off()


func _execute_supply_run(mission: HeliMission) -> void:
	"""Execute automated supply run"""
	# Simplified: just fly between LZs
	if mission.assigned_helicopters.is_empty():
		return

	var heli: Node3D = mission.assigned_helicopters[0]
	if mission.destination_lz:
		heli.fly_to(mission.destination_lz.global_position, mission.destination_lz)


func _execute_gunship_cap(mission: HeliMission) -> void:
	"""Execute gunship combat air patrol"""
	if mission.waypoints.is_empty():
		return

	for heli in mission.assigned_helicopters:
		# Fly to first waypoint
		heli.fly_to(mission.waypoints[0])


func _on_helicopter_returned(_helicopter: Node3D, mission: HeliMission) -> void:
	"""Return helicopter to available pool"""
	for heli in mission.assigned_helicopters:
		active_helicopters.erase(heli)
		available_helicopters.append(heli)

	mission.assigned_helicopters.clear()
	mission.complete()


func _find_troops_at_lz(lz: Node3D) -> Array[Node3D]:
	"""Find friendly troops near an LZ"""
	var troops: Array[Node3D] = []
	var radius: float = 20.0

	if lz is LandingZone:
		radius = lz.lz_radius

	var all_units: Array[Node] = get_tree().get_nodes_in_group("player_units")
	for unit in all_units:
		if is_instance_valid(unit) and unit.global_position.distance_to(lz.global_position) <= radius:
			troops.append(unit as Node3D)

	return troops


func _spawn_helicopter() -> Node3D:
	"""Spawn a new helicopter"""
	var heli := Helicopter.new()
	heli.name = "Helicopter_%d" % available_helicopters.size()
	heli.position = Vector3(-50, 30, 0)  # Spawn off-map
	get_tree().current_scene.add_child(heli)
	available_helicopters.append(heli)

	# Connect destruction signal
	heli.destroyed.connect(_on_helicopter_destroyed)

	return heli


func _on_helicopter_destroyed(helicopter: Node3D) -> void:
	"""Handle helicopter destruction"""
	available_helicopters.erase(helicopter)
	active_helicopters.erase(helicopter)

	# Start respawn timer
	_respawn_timers.append(helicopter_respawn_time)


func _on_medevac_requested(position: Vector3, _unit: Node3D) -> void:
	"""Handle medevac request"""
	# Find nearest LZ or create temp one
	var lz: Node3D = _find_nearest_lz(position)
	if not lz:
		return

	# Find available medevac helicopter
	if available_helicopters.is_empty():
		return

	# Create extraction mission
	var mission := HeliMission.create_extraction(lz, null, "Emergency Medevac")
	mission.priority = 10  # High priority
	queue_mission(mission)


func _find_nearest_lz(position: Vector3) -> Node3D:
	"""Find the nearest landing zone"""
	var lzs: Array[Node] = get_tree().get_nodes_in_group("landing_zones")
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for lz in lzs:
		var dist: float = position.distance_to(lz.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = lz as Node3D

	return nearest


## Public API

func queue_mission(mission: HeliMission) -> void:
	"""Add a mission to the queue"""
	pending_missions.append(mission)


func request_insertion(
	troops: Array[Node3D],
	destination: Node3D,
	origin: Node3D = null
) -> HeliMission:
	"""Request troop insertion"""
	var mission := HeliMission.create_insertion(origin, destination, troops)
	queue_mission(mission)
	return mission


func request_extraction(pickup_lz: Node3D, dropoff_lz: Node3D = null) -> HeliMission:
	"""Request troop extraction"""
	var mission := HeliMission.create_extraction(pickup_lz, dropoff_lz)
	queue_mission(mission)
	return mission


func request_supply_run(origin: Node3D, destination: Node3D) -> HeliMission:
	"""Request automated supply run"""
	var mission := HeliMission.create_supply_run(origin, destination)
	queue_mission(mission)
	return mission


func spawn_initial_helicopters(count: int) -> void:
	"""Spawn initial helicopter pool"""
	for i in count:
		_spawn_helicopter()
	print("[InsertionManager] Spawned %d helicopters" % count)


func get_available_helicopter_count() -> int:
	return available_helicopters.size()


func get_active_mission_count() -> int:
	return active_missions.size()
