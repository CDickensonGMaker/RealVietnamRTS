extends Node
class_name InsertionManager

## Insertion Manager - Manages all helicopter operations
## Handles missions, helicopter allocation, flight coordination
##
## Serves Pillar 3 (Physical Supply Chains):
##   - Helicopter supply delivery when roads are cut
##   - Emergency resupply to isolated firebases
##   - Automated supply missions to maintain firebase operations

signal mission_started(mission: HeliMission)
signal mission_completed(mission: HeliMission)
signal helicopter_dispatched(helicopter: Node3D, mission: HeliMission)
signal insertion_complete(troops: Array, lz: Node3D)
signal extraction_complete(troops: Array, lz: Node3D)
signal emergency_supply_triggered(firebase: Node3D, reason: String)
signal supply_delivered_by_air(firebase: Node3D, amount: float)

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

## Emergency supply configuration (Pillar 3)
@export var critical_supply_threshold: float = 0.25  # 25% triggers emergency
@export var emergency_supply_amount: float = 100.0  # Supply per emergency delivery
@export var supply_check_interval: float = 15.0  # How often to check cut-off firebases
@export var emergency_supply_priority: int = 8  # High priority (medevac is 10)

## State
var _respawn_timers: Array[float] = []

## Emergency supply tracking
var _road_blocked_firebases: Dictionary = {}  # firebase_node_id -> bool (roads cut)
var _pending_emergency_supply: Dictionary = {}  # firebase_node_id -> bool (supply mission queued)
var _supply_check_timer: float = 0.0


func _ready() -> void:
	print("[InsertionManager] Initialized")

	# Connect to signals
	if BattleSignals:
		BattleSignals.request_medevac.connect(_on_medevac_requested)

	# Connect to RoadNetwork for road_blocked signal (Pillar 3)
	_connect_to_road_network()

	# Connect to SupplyManager for supply_shortage signal
	_connect_to_supply_manager()


func _process(delta: float) -> void:
	# Update missions
	_update_missions(delta)

	# Process respawn timers
	_update_respawns(delta)

	# Try to assign helicopters to pending missions
	_process_pending_missions()

	# Check for emergency supply needs (Pillar 3)
	_supply_check_timer += delta
	if _supply_check_timer >= supply_check_interval:
		_supply_check_timer = 0.0
		_check_emergency_supply_needs()


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
		HeliMission.MissionType.EMERGENCY_SUPPLY:
			# Emergency supply may need multiple helicopters for large payloads
			var helis_for_payload: int = ceili(mission.supply_payload / 150.0)  # ~150 supply per Huey
			return maxi(1, helis_for_payload)
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
		HeliMission.MissionType.EMERGENCY_SUPPLY:
			_execute_emergency_supply(mission)
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
	"""Execute automated supply run (Pillar 3: Physical Supply Chains)"""
	if mission.assigned_helicopters.is_empty():
		return

	var heli: Node3D = mission.assigned_helicopters[0]
	if not heli is Helicopter:
		return

	if not mission.destination_lz:
		return

	# Fly to destination LZ
	heli.landed.connect(_on_supply_landed.bind(mission), CONNECT_ONE_SHOT)
	heli.fly_to(mission.destination_lz.global_position, mission.destination_lz)


func _on_supply_landed(helicopter: Node3D, _lz: Node3D, mission: HeliMission) -> void:
	"""Handle helicopter landed for supply delivery (Pillar 3)"""
	if not helicopter is Helicopter:
		return

	# Deliver supplies to firebase
	var supply_amount: float = mission.supply_payload
	var firebase: Node3D = _find_firebase_at_lz(mission.destination_lz)

	if firebase and firebase.has_method("add_supply"):
		firebase.add_supply(supply_amount)
		supply_delivered_by_air.emit(firebase, supply_amount)

		if BattleSignals:
			BattleSignals.supply_delivered.emit(firebase, supply_amount)

		print("[InsertionManager] Delivered %.0f supplies to %s via helicopter" % [
			supply_amount,
			firebase.name if firebase else "unknown firebase"
		])

		# Clear pending emergency supply flag
		if firebase:
			var firebase_id: int = firebase.get_instance_id()
			_pending_emergency_supply.erase(firebase_id)

	# Return helicopter to pool after departure
	helicopter.took_off.connect(_on_helicopter_returned.bind(mission), CONNECT_ONE_SHOT)
	helicopter.take_off()


func _find_firebase_at_lz(lz: Node3D) -> Node3D:
	"""Find the firebase associated with a landing zone"""
	if not lz:
		return null

	# Check if LZ has a firebase reference
	if lz.has_method("get") and lz.get("firebase") != null:
		return lz.firebase

	# Search for nearest firebase
	var firebases: Array[Node] = get_tree().get_nodes_in_group("firebases")
	var nearest: Node3D = null
	var nearest_dist: float = 100.0  # Max search radius

	for fb in firebases:
		if not is_instance_valid(fb):
			continue
		var dist: float = lz.global_position.distance_to(fb.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = fb as Node3D

	return nearest


func _execute_emergency_supply(mission: HeliMission) -> void:
	"""Execute emergency supply delivery (Pillar 3: roads cut, supply critical)

	Emergency supply missions:
	- High priority (8/10)
	- Do not abort if LZ is hot
	- Deliver supplies even under fire
	"""
	if mission.assigned_helicopters.is_empty():
		return

	var heli: Node3D = mission.assigned_helicopters[0]
	if not heli is Helicopter:
		return

	if not mission.destination_lz:
		# No LZ available - abort mission
		print("[InsertionManager] Emergency supply aborted - no LZ available")
		_on_helicopter_returned(heli, mission)
		return

	# Emergency supply does not abort for hot LZ (must get supplies through)
	# Set default payload if not specified
	if mission.supply_payload <= 0.0:
		mission.supply_payload = emergency_supply_amount

	# Fly to destination LZ
	heli.landed.connect(_on_supply_landed.bind(mission), CONNECT_ONE_SHOT)
	heli.fly_to(mission.destination_lz.global_position, mission.destination_lz)

	print("[InsertionManager] Emergency supply helicopter dispatched to %s" % mission.mission_name)


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


# =============================================================================
# EMERGENCY SUPPLY SYSTEM (Pillar 3: Physical Supply Chains)
# =============================================================================

func _connect_to_road_network() -> void:
	"""Connect to RoadNetwork signals for road_blocked events"""
	# Try autoload first
	var road_network: Node = get_node_or_null("/root/RoadNetwork")
	if not road_network:
		# Try scene group
		var networks: Array[Node] = get_tree().get_nodes_in_group("road_networks")
		if not networks.is_empty():
			road_network = networks[0]

	if road_network:
		if road_network.has_signal("road_blocked"):
			road_network.road_blocked.connect(_on_road_blocked)
		if road_network.has_signal("road_repaired"):
			road_network.road_repaired.connect(_on_road_repaired)
		print("[InsertionManager] Connected to RoadNetwork for supply triggers")


func _connect_to_supply_manager() -> void:
	"""Connect to SupplyManager signals for shortage events"""
	var supply_mgr: Node = get_node_or_null("/root/SupplyManager")
	if not supply_mgr:
		var mgrs: Array[Node] = get_tree().get_nodes_in_group("supply_managers")
		if not mgrs.is_empty():
			supply_mgr = mgrs[0]

	if supply_mgr:
		if supply_mgr.has_signal("supply_shortage"):
			supply_mgr.supply_shortage.connect(_on_supply_shortage)
		print("[InsertionManager] Connected to SupplyManager for shortage triggers")


func _on_road_blocked(segment_id: int) -> void:
	"""Handle road blocked signal - check if any firebase is cut off"""
	# When a road is blocked, check all firebases for access
	var firebases: Array[Node] = get_tree().get_nodes_in_group("firebases")

	for fb in firebases:
		if not is_instance_valid(fb):
			continue

		if _is_firebase_road_cut(fb as Node3D):
			var firebase_id: int = fb.get_instance_id()
			_road_blocked_firebases[firebase_id] = true

			# Emit signal for road cut
			if BattleSignals and BattleSignals.has_signal("supply_line_cut"):
				BattleSignals.supply_line_cut.emit(fb)

			# Trigger immediate supply check for this firebase
			_check_firebase_supply_critical(fb as Node3D)


func _on_road_repaired(segment_id: int) -> void:
	"""Handle road repaired signal - update cut-off status"""
	var firebases: Array[Node] = get_tree().get_nodes_in_group("firebases")

	for fb in firebases:
		if not is_instance_valid(fb):
			continue

		var firebase_id: int = fb.get_instance_id()

		# Check if firebase now has road access
		if not _is_firebase_road_cut(fb as Node3D):
			if _road_blocked_firebases.has(firebase_id):
				_road_blocked_firebases.erase(firebase_id)

				# Emit signal for road restored
				if BattleSignals and BattleSignals.has_signal("supply_line_restored"):
					BattleSignals.supply_line_restored.emit(fb)


func _on_supply_shortage(location: Node3D) -> void:
	"""Handle supply shortage signal - trigger emergency supply if needed"""
	if not location:
		return

	# Check if this is a firebase with cut roads
	if location.is_in_group("firebases"):
		_check_firebase_supply_critical(location)


func _is_firebase_road_cut(firebase: Node3D) -> bool:
	"""Check if a firebase has road access to supply depot"""
	var road_network: Node = get_node_or_null("/root/RoadNetwork")
	if not road_network:
		var networks: Array[Node] = get_tree().get_nodes_in_group("road_networks")
		if not networks.is_empty():
			road_network = networks[0]

	if not road_network or not road_network.has_method("is_route_passable"):
		return false

	# Find nearest supply depot
	var supply_mgr: Node = get_node_or_null("/root/SupplyManager")
	if not supply_mgr:
		var mgrs: Array[Node] = get_tree().get_nodes_in_group("supply_managers")
		if not mgrs.is_empty():
			supply_mgr = mgrs[0]

	if not supply_mgr or not supply_mgr.has_method("find_nearest_depot"):
		return false

	var depot: Node3D = supply_mgr.find_nearest_depot(firebase.global_position)
	if not depot:
		# No depot found - consider roads cut (isolated)
		return true

	# Check if route is passable
	var is_passable: bool = road_network.is_route_passable(
		depot.global_position,
		firebase.global_position
	)

	return not is_passable


func _check_emergency_supply_needs() -> void:
	"""Periodic check for firebases needing emergency supply"""
	# Only check firebases with blocked roads
	for firebase_id: int in _road_blocked_firebases:
		var firebase: Node3D = instance_from_id(firebase_id) as Node3D
		if not is_instance_valid(firebase):
			_road_blocked_firebases.erase(firebase_id)
			continue

		_check_firebase_supply_critical(firebase)


func _check_firebase_supply_critical(firebase: Node3D) -> bool:
	"""Check if a firebase needs emergency helicopter supply"""
	if not is_instance_valid(firebase):
		return false

	var firebase_id: int = firebase.get_instance_id()

	# Skip if already has pending emergency supply mission
	if _pending_emergency_supply.get(firebase_id, false):
		return false

	# Check if roads are cut
	var roads_cut: bool = _road_blocked_firebases.get(firebase_id, false)
	if not roads_cut:
		# Double-check road status
		roads_cut = _is_firebase_road_cut(firebase)
		if roads_cut:
			_road_blocked_firebases[firebase_id] = true

	if not roads_cut:
		return false

	# Check supply level
	var supply_level: float = 0.0
	var max_supply: float = 100.0

	if firebase.has_method("get") and firebase.get("supply_level") != null:
		supply_level = firebase.supply_level
	if firebase.has_method("get") and firebase.get("max_supply") != null:
		max_supply = firebase.max_supply

	var supply_ratio: float = supply_level / maxf(max_supply, 1.0)

	# Trigger emergency supply if below critical threshold
	if supply_ratio < critical_supply_threshold:
		_trigger_emergency_supply(firebase)
		return true

	return false


func _trigger_emergency_supply(firebase: Node3D) -> void:
	"""Create emergency helicopter supply mission for cut-off firebase"""
	if not is_instance_valid(firebase):
		return

	var firebase_id: int = firebase.get_instance_id()

	# Mark as pending
	_pending_emergency_supply[firebase_id] = true

	# Find LZ at firebase
	var lz: Node3D = _find_firebase_lz(firebase)
	if not lz:
		print("[InsertionManager] No LZ found for emergency supply to %s" % firebase.name)
		_pending_emergency_supply.erase(firebase_id)
		return

	# Create emergency supply mission
	var mission := HeliMission.create_emergency_supply(
		null,  # Origin (off-map base)
		lz,
		emergency_supply_amount,
		"Emergency Supply - %s" % firebase.name
	)
	mission.priority = emergency_supply_priority

	queue_mission(mission)

	emergency_supply_triggered.emit(firebase, "roads_cut_supply_critical")

	print("[InsertionManager] Emergency supply mission queued for %s (supply critical, roads cut)" % firebase.name)


func _find_firebase_lz(firebase: Node3D) -> Node3D:
	"""Find a landing zone at or near a firebase"""
	# Check if firebase has a direct LZ reference
	if firebase.has_method("get") and firebase.get("landing_zone") != null:
		return firebase.landing_zone

	# Check for helipad building
	if firebase.has_method("has_building_type"):
		# GameEnums.BuildingType.HELIPAD = 8, PSP_HELIPAD = 9
		if firebase.has_building_type(8) or firebase.has_building_type(9):
			# Find LZ within firebase radius
			return _find_nearest_lz(firebase.global_position)

	# Fall back to nearest LZ
	var lz: Node3D = _find_nearest_lz(firebase.global_position)

	# Verify LZ is within reasonable range of firebase
	if lz:
		var dist: float = lz.global_position.distance_to(firebase.global_position)
		if dist > 150.0:  # Too far, not associated with this firebase
			return null

	return lz


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


func request_emergency_supply(firebase: Node3D, supply_amount: float = -1.0) -> HeliMission:
	"""Request emergency helicopter supply delivery to a firebase (Pillar 3)

	Use when:
	- Roads to firebase are blocked/cut
	- Firebase supply is critically low
	- Immediate resupply is needed

	Returns the mission, or null if no LZ available.
	"""
	if not is_instance_valid(firebase):
		return null

	# Find LZ at firebase
	var lz: Node3D = _find_firebase_lz(firebase)
	if not lz:
		push_warning("[InsertionManager] Cannot request emergency supply - no LZ at firebase %s" % firebase.name)
		return null

	# Use default amount if not specified
	if supply_amount <= 0.0:
		supply_amount = emergency_supply_amount

	var mission := HeliMission.create_emergency_supply(
		null,
		lz,
		supply_amount,
		"Emergency Supply - %s" % firebase.name
	)
	mission.priority = emergency_supply_priority

	queue_mission(mission)

	print("[InsertionManager] Manual emergency supply requested for %s (%.0f supplies)" % [
		firebase.name,
		supply_amount
	])

	return mission


func is_firebase_cut_off(firebase: Node3D) -> bool:
	"""Check if a firebase has no road access to supply depots"""
	return _is_firebase_road_cut(firebase)


func get_cut_off_firebases() -> Array[Node3D]:
	"""Get all firebases currently cut off from road supply"""
	var result: Array[Node3D] = []

	for firebase_id: int in _road_blocked_firebases:
		var firebase: Node3D = instance_from_id(firebase_id) as Node3D
		if is_instance_valid(firebase):
			result.append(firebase)

	return result


func spawn_initial_helicopters(count: int) -> void:
	"""Spawn initial helicopter pool"""
	for i in count:
		_spawn_helicopter()
	print("[InsertionManager] Spawned %d helicopters" % count)


func get_available_helicopter_count() -> int:
	return available_helicopters.size()


func get_active_mission_count() -> int:
	return active_missions.size()
