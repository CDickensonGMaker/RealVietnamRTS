extends Node
## InsertionManager - Coordinates helicopter insertions and extractions
## Accessed globally via InsertionManager autoload (no class_name needed)

# Preload dependent classes to ensure they're available at parse time
const HeliMissionClass = preload("res://helicopter_system/heli_mission.gd")
const LandingZoneClass = preload("res://helicopter_system/landing_zone.gd")

signal insertion_queued(mission)
signal insertion_launched(flight)
signal insertion_complete(flight, lz)
signal extraction_requested(position: Vector3, priority: int)
signal extraction_complete(team: Node3D)

# Active operations
var insertion_queue: Array = []  # Array of HeliMission
var active_flights: Array = []   # Array of HeliFlightGroup
var pending_extractions: Array[Dictionary] = []

# Available helicopters
var available_transport_hueys: int = 4
var available_gunship_hueys: int = 2
var available_cobras: int = 2
var available_chinooks: int = 1

# Spawn/despawn positions (off-map)
var helicopter_spawn_position := Vector3(-500, 50, 0)
var helicopter_despawn_position := Vector3(-500, 50, 0)

func _ready() -> void:
	BattleSignals.sog_extraction_requested.connect(_on_extraction_requested)

func _process(delta: float) -> void:
	_process_insertion_queue()
	_process_active_flights(delta)
	_process_extractions()

# =============================================================================
# INSERTION OPERATIONS
# =============================================================================

func queue_insertion(request):
	## Queue a helicopter insertion for reinforcements
	## Returns a HeliMission instance
	var mission := HeliMissionClass.new()
	mission.mission_type = GameEnums.HeliMissionType.TROOP_ROTATION
	mission.destination_lz = request.destination
	mission.cargo = [request]
	mission.priority = request.priority

	insertion_queue.append(mission)
	insertion_queued.emit(mission)

	return mission

func create_insertion(squads: Array, lz, escort: bool = false):
	## Create a custom insertion mission
	## lz: LandingZone, returns HeliMission
	var mission := HeliMissionClass.new()
	mission.mission_type = GameEnums.HeliMissionType.TROOP_ROTATION
	mission.destination_lz = lz
	mission.cargo = squads

	# Add escort if LZ is hot
	if escort or (lz and lz.get_threat_level() > 0.5):
		mission.escort_count = 2

	insertion_queue.append(mission)
	insertion_queued.emit(mission)

	return mission

func _process_insertion_queue() -> void:
	if insertion_queue.is_empty():
		return

	# Sort by priority
	insertion_queue.sort_custom(func(a, b): return a.priority > b.priority)

	# Try to launch next mission
	var mission = insertion_queue[0]  # HeliMission

	# Check helicopter availability
	var needed_hueys := ceili(mission.cargo.size() / 8.0)  # 8 troops per Huey
	if available_transport_hueys < needed_hueys:
		return

	# Check escort availability
	if mission.escort_count > available_cobras:
		mission.escort_count = available_cobras

	# Launch!
	insertion_queue.remove_at(0)
	_launch_insertion(mission)

func _launch_insertion(mission) -> void:  # mission: HeliMission
	var flight := HeliFlightGroup.new()

	# Allocate helicopters
	var huey_count := ceili(mission.cargo.size() / 8.0)
	flight.transport_count = huey_count
	available_transport_hueys -= huey_count

	flight.escort_count = mission.escort_count
	available_cobras -= mission.escort_count

	# Create flight
	flight.mission = mission
	flight.destination = mission.destination_lz
	flight.spawn_position = helicopter_spawn_position
	flight.formation = GameEnums.FormationType.V_FORMATION
	flight.phase = HeliFlightGroup.Phase.INBOUND

	# Prep fire for hot LZ
	if mission.destination_lz and mission.destination_lz.get_threat_level() > 0.7:
		_call_prep_fire(mission.destination_lz.global_position)

	active_flights.append(flight)
	insertion_launched.emit(flight)

func _call_prep_fire(position: Vector3) -> void:
	# Call artillery prep before insertion
	# This would interface with ArtilleryManager or AirSupportManager
	if AirSupportManager.can_call_strike(GameEnums.AirStrikeType.CLOSE_AIR_SUPPORT):
		AirSupportManager.request_airstrike(
			GameEnums.AirStrikeType.CLOSE_AIR_SUPPORT,
			position
		)

# =============================================================================
# FLIGHT MANAGEMENT
# =============================================================================

func _process_active_flights(delta: float) -> void:
	var completed: Array = []  # Array of HeliFlightGroup

	for flight in active_flights:
		flight.timer += delta

		match flight.phase:
			HeliFlightGroup.Phase.INBOUND:
				_process_inbound(flight, delta)
			HeliFlightGroup.Phase.LANDING:
				_process_landing(flight, delta)
			HeliFlightGroup.Phase.UNLOADING:
				_process_unloading(flight, delta)
			HeliFlightGroup.Phase.TAKEOFF:
				_process_takeoff(flight, delta)
			HeliFlightGroup.Phase.OUTBOUND:
				_process_outbound(flight, delta)
				if flight.timer > 60.0:  # Back to base
					completed.append(flight)

	for flight in completed:
		_complete_flight(flight)
		active_flights.erase(flight)

func _process_inbound(flight: HeliFlightGroup, delta: float) -> void:
	# Simulate approach time
	if flight.timer > 45.0:  # 45 seconds approach
		flight.phase = HeliFlightGroup.Phase.LANDING
		flight.timer = 0.0

func _process_landing(flight: HeliFlightGroup, delta: float) -> void:
	if flight.timer > 10.0:  # 10 seconds to land
		flight.phase = HeliFlightGroup.Phase.UNLOADING
		flight.timer = 0.0

func _process_unloading(flight: HeliFlightGroup, delta: float) -> void:
	if flight.timer > 15.0:  # 15 seconds to unload
		# Spawn units at LZ
		_spawn_cargo(flight)

		flight.phase = HeliFlightGroup.Phase.TAKEOFF
		flight.timer = 0.0

		insertion_complete.emit(flight, flight.destination)

func _process_takeoff(flight: HeliFlightGroup, delta: float) -> void:
	if flight.timer > 10.0:  # 10 seconds takeoff
		flight.phase = HeliFlightGroup.Phase.OUTBOUND
		flight.timer = 0.0

func _process_outbound(flight: HeliFlightGroup, delta: float) -> void:
	pass  # Just timer until completion

func _spawn_cargo(flight: HeliFlightGroup) -> void:
	if not flight.destination:
		return

	var spawn_pos: Vector3 = flight.destination.global_position

	for cargo in flight.mission.cargo:
		# Handle ReinforcementRequest (use duck typing to avoid class_name resolution issues)
		if cargo and cargo.has_method("get_status_string"):
			var unit := _create_unit(cargo.unit_type)
			if unit:
				unit.global_position = spawn_pos + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
				get_tree().current_scene.add_child(unit)

				ReinforcementManager.on_reinforcement_arrived(cargo, [unit])

func _create_unit(unit_type: int) -> Node3D:
	# Load unit scene based on type
	var scenes := {
		GameEnums.UnitType.RIFLE_PLATOON: "res://battle_system/nodes/squad.tscn",
		GameEnums.UnitType.WEAPONS_SQUAD: "res://battle_system/nodes/weapons_squad.tscn",
		GameEnums.UnitType.ENGINEERS: "res://battle_system/nodes/engineer_squad.tscn",
		GameEnums.UnitType.SOG_TEAM: "res://sog_system/sog_team.tscn",
	}

	var scene_path: String = scenes.get(unit_type, "")
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		# Create placeholder
		var placeholder := Node3D.new()
		placeholder.name = "Squad"
		return placeholder

	var scene := load(scene_path) as PackedScene
	return scene.instantiate()

func _complete_flight(flight: HeliFlightGroup) -> void:
	# Return helicopters to pool
	available_transport_hueys += flight.transport_count
	available_cobras += flight.escort_count

# =============================================================================
# EXTRACTION OPERATIONS
# =============================================================================

func request_extraction(position: Vector3, units: Array,
						priority: int = 1, emergency: bool = false) -> Dictionary:
	## Request helicopter extraction for units
	## Returns dictionary with eta and extraction_id

	# Calculate ETA based on distance and priority
	var distance := position.distance_to(helicopter_spawn_position)
	var base_eta := distance / 50.0  # 50 m/s helicopter speed
	if emergency:
		base_eta *= 0.7  # Faster for emergencies

	# Check helicopter availability
	var eta: float
	if available_transport_hueys > 0:
		eta = base_eta
	else:
		# Need to wait for helicopters to return
		eta = base_eta + 120.0  # Add 2 minutes

	var extraction_id := randi()

	var extraction := {
		"id": extraction_id,
		"position": position,
		"units": units,
		"priority": priority,
		"emergency": emergency,
		"timer": 0.0,
		"eta": eta,
	}

	pending_extractions.append(extraction)
	extraction_requested.emit(position, priority)
	BattleSignals.sog_extraction_requested.emit(units[0] if not units.is_empty() else null, priority)

	# Notify units of ETA
	for unit in units:
		if unit and unit.has_method("on_extraction_helicopter_inbound"):
			unit.on_extraction_helicopter_inbound(eta)

	return {"eta": eta, "extraction_id": extraction_id}

func _process_extractions() -> void:
	if pending_extractions.is_empty():
		return

	# Sort by priority (emergency first)
	pending_extractions.sort_custom(func(a, b):
		if a.emergency != b.emergency:
			return a.emergency
		return a.priority > b.priority
	)

	# Try to launch extraction
	if available_transport_hueys > 0:
		var extraction: Dictionary = pending_extractions.pop_front()
		_launch_extraction(extraction)

func _launch_extraction(extraction: Dictionary) -> void:
	available_transport_hueys -= 1

	# For emergency extractions, send escort
	if extraction.emergency and available_cobras > 0:
		available_cobras -= 1

	# Simulate extraction flight
	# In full implementation, this would create actual helicopter nodes

func _on_extraction_requested(team: Node3D, priority: int) -> void:
	if team:
		request_extraction(team.global_position, [team], priority, priority > 5)


# =============================================================================
# HELI FLIGHT GROUP CLASS
# =============================================================================

class HeliFlightGroup:
	extends RefCounted

	enum Phase { FORMING, INBOUND, LANDING, UNLOADING, LOADING, TAKEOFF, OUTBOUND }

	var mission  # HeliMission
	var transport_count: int = 1
	var escort_count: int = 0
	var destination  # LandingZone
	var spawn_position: Vector3
	var formation: int = GameEnums.FormationType.V_FORMATION
	var phase: Phase = Phase.FORMING
	var timer: float = 0.0
