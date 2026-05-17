extends RefCounted
class_name HeliMission

## Helicopter Mission - Defines automated helicopter operations
## Supply runs, medevac, troop rotation, gunship support

enum MissionType {
	SUPPLY_RUN,        # Automated supply delivery
	MEDEVAC_STANDBY,   # Auto-extract wounded when called
	TROOP_ROTATION,    # Regular reinforcement runs
	INSERTION,         # One-time troop insertion
	EXTRACTION,        # One-time troop extraction
	RECON_ORBIT,       # Circle area, spot enemies
	GUNSHIP_CAP,       # Combat air patrol
	ESCORT_DUTY,       # Protect other helicopters
}

enum MissionState { PENDING, ACTIVE, PAUSED, COMPLETE, ABORTED }

## Mission configuration
var mission_type: MissionType = MissionType.INSERTION
var mission_name: String = "Mission"
var priority: int = 1  # Higher = more important

## Waypoints and targets
var waypoints: Array[Vector3] = []
var origin_lz: Node3D = null  # Starting LZ
var destination_lz: Node3D = null  # Target LZ

## Timing
var repeat: bool = false
var repeat_interval: float = 120.0  # Seconds between repeats
var time_since_complete: float = 0.0

## State
var state: MissionState = MissionState.PENDING
var assigned_helicopters: Array[Node3D] = []
var cargo_manifest: Array[Node3D] = []  # Troops/supplies to transport

## Rules of engagement
var weapons_free: bool = false
var abort_if_hot: bool = false  # Abort if LZ becomes hot


static func create_insertion(
	origin: Node3D,
	destination: Node3D,
	troops: Array[Node3D],
	name: String = "Insertion"
) -> HeliMission:
	"""Create a troop insertion mission"""
	var mission := HeliMission.new()
	mission.mission_type = MissionType.INSERTION
	mission.mission_name = name
	mission.origin_lz = origin
	mission.destination_lz = destination
	mission.cargo_manifest = troops
	mission.repeat = false
	return mission


static func create_extraction(
	pickup_lz: Node3D,
	dropoff_lz: Node3D,
	name: String = "Extraction"
) -> HeliMission:
	"""Create a troop extraction mission"""
	var mission := HeliMission.new()
	mission.mission_type = MissionType.EXTRACTION
	mission.mission_name = name
	mission.origin_lz = pickup_lz
	mission.destination_lz = dropoff_lz
	mission.repeat = false
	return mission


static func create_supply_run(
	origin: Node3D,
	destination: Node3D,
	interval: float = 120.0,
	name: String = "Supply Run"
) -> HeliMission:
	"""Create a repeating supply run mission"""
	var mission := HeliMission.new()
	mission.mission_type = MissionType.SUPPLY_RUN
	mission.mission_name = name
	mission.origin_lz = origin
	mission.destination_lz = destination
	mission.repeat = true
	mission.repeat_interval = interval
	return mission


static func create_medevac_standby(
	base_lz: Node3D,
	name: String = "Medevac Standby"
) -> HeliMission:
	"""Create a medevac standby mission"""
	var mission := HeliMission.new()
	mission.mission_type = MissionType.MEDEVAC_STANDBY
	mission.mission_name = name
	mission.origin_lz = base_lz
	mission.repeat = true
	return mission


static func create_gunship_cap(
	patrol_center: Vector3,
	patrol_radius: float = 50.0,
	name: String = "Gunship CAP"
) -> HeliMission:
	"""Create a gunship combat air patrol mission"""
	var mission := HeliMission.new()
	mission.mission_type = MissionType.GUNSHIP_CAP
	mission.mission_name = name
	mission.repeat = true
	mission.weapons_free = true

	# Generate patrol waypoints in a circle
	for i in 4:
		var angle: float = (TAU / 4.0) * float(i)
		var offset := Vector3(cos(angle), 0, sin(angle)) * patrol_radius
		mission.waypoints.append(patrol_center + offset)

	return mission


func start() -> void:
	"""Start the mission"""
	state = MissionState.ACTIVE
	time_since_complete = 0.0


func pause() -> void:
	"""Pause the mission"""
	state = MissionState.PAUSED


func resume() -> void:
	"""Resume a paused mission"""
	if state == MissionState.PAUSED:
		state = MissionState.ACTIVE


func complete() -> void:
	"""Mark mission as complete"""
	state = MissionState.COMPLETE


func abort() -> void:
	"""Abort the mission"""
	state = MissionState.ABORTED


func can_repeat() -> bool:
	"""Check if mission should repeat"""
	return repeat and state == MissionState.COMPLETE and time_since_complete >= repeat_interval


func update(delta: float) -> void:
	"""Update mission timer"""
	if state == MissionState.COMPLETE and repeat:
		time_since_complete += delta
