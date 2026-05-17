extends Resource
class_name HeliMission
## HeliMission - Defines a helicopter mission (supply run, medevac, insertion, etc.)
##
## NOTE: Type annotations for LandingZone removed to avoid parse-time dependency issues.
## LandingZone is a Node3D class that may not be loaded when this Resource is parsed.

@export var mission_type: int = GameEnums.HeliMissionType.SUPPLY_RUN
@export var priority: int = 1
@export var repeat: bool = false
@export var interval: float = 180.0  # For repeating missions
@export var rules_of_engagement: int = GameEnums.ROE.WEAPONS_FREE

# Waypoints
var waypoints: Array = []  # Array of Waypoint
var current_waypoint_index: int = 0

# Assignment
var assigned_helicopters: Array = []  # Array of Node3D (helicopters)
var escort_helicopters: Array = []  # Array of Node3D (escort helicopters)
var escort_count: int = 0

# Cargo
var cargo: Array = []  # Units or supplies

# Destinations (LandingZone instances - type annotation removed for parse compatibility)
var origin_lz = null  # LandingZone
var destination_lz = null  # LandingZone

# Status
var is_active: bool = false
var is_complete: bool = false
var timer: float = 0.0

# =============================================================================
# WAYPOINT CLASS
# =============================================================================

class Waypoint:
	var position: Vector3
	var action: int = GameEnums.WaypointAction.MOVE_TO
	var landing_zone = null  # LandingZone - type removed for parse compatibility
	var hover_duration: float = 0.0

	static func create(pos: Vector3, wp_action: int = GameEnums.WaypointAction.MOVE_TO) -> Waypoint:
		var wp := Waypoint.new()
		wp.position = pos
		wp.action = wp_action
		return wp

	static func create_lz(lz, wp_action: int) -> Waypoint:  # lz: LandingZone
		var wp := Waypoint.new()
		wp.landing_zone = lz
		wp.position = lz.global_position if lz else Vector3.ZERO
		wp.action = wp_action
		return wp

# =============================================================================
# MISSION CREATION
# =============================================================================

## Create a supply run mission between two landing zones
## from_lz, to_lz: LandingZone instances
static func create_supply_run(from_lz, to_lz):  # Returns HeliMission
	var MissionScript := preload("res://helicopter_system/heli_mission.gd")
	var mission := MissionScript.new()
	mission.mission_type = GameEnums.HeliMissionType.SUPPLY_RUN
	mission.origin_lz = from_lz
	mission.destination_lz = to_lz
	mission.repeat = true
	mission.interval = 180.0

	mission.waypoints = [
		Waypoint.create_lz(from_lz, GameEnums.WaypointAction.LOAD),
		Waypoint.create_lz(to_lz, GameEnums.WaypointAction.UNLOAD),
	]

	return mission

## Create a medevac standby mission
## lz: LandingZone instance
static func create_medevac_standby(lz):  # Returns HeliMission
	var MissionScript := preload("res://helicopter_system/heli_mission.gd")
	var mission := MissionScript.new()
	mission.mission_type = GameEnums.HeliMissionType.MEDEVAC_STANDBY
	mission.destination_lz = lz
	mission.repeat = false
	mission.priority = 10  # High priority

	return mission

## Create a recon orbit mission around a center point
static func create_recon_orbit(center: Vector3, radius: float):  # Returns HeliMission
	var MissionScript := preload("res://helicopter_system/heli_mission.gd")
	var mission := MissionScript.new()
	mission.mission_type = GameEnums.HeliMissionType.RECON_ORBIT
	mission.repeat = true

	# Create circular waypoints
	for i in range(8):
		var angle := TAU * i / 8.0
		var pos := center + Vector3(cos(angle) * radius, 30.0, sin(angle) * radius)
		mission.waypoints.append(Waypoint.create(pos, GameEnums.WaypointAction.PATROL))

	return mission

## Create a gunship combat air patrol mission
static func create_gunship_cap(area_center: Vector3, area_radius: float):  # Returns HeliMission
	var MissionScript := preload("res://helicopter_system/heli_mission.gd")
	var mission := MissionScript.new()
	mission.mission_type = GameEnums.HeliMissionType.GUNSHIP_CAP
	mission.repeat = true
	mission.rules_of_engagement = GameEnums.ROE.WEAPONS_FREE

	# Orbit waypoints
	for i in range(4):
		var angle := TAU * i / 4.0
		var pos := area_center + Vector3(cos(angle) * area_radius, 40.0, sin(angle) * area_radius)
		var wp := Waypoint.create(pos, GameEnums.WaypointAction.PATROL)
		wp.hover_duration = 15.0  # Hover and scan
		mission.waypoints.append(wp)

	return mission

## Create an insertion mission for squads at a landing zone
## lz: LandingZone instance
static func create_insertion(squads: Array, lz):  # Returns HeliMission
	var MissionScript := preload("res://helicopter_system/heli_mission.gd")
	var mission := MissionScript.new()
	mission.mission_type = GameEnums.HeliMissionType.TROOP_ROTATION
	mission.destination_lz = lz
	mission.cargo = squads
	mission.repeat = false
	mission.priority = 5

	mission.waypoints = [
		Waypoint.create_lz(lz, GameEnums.WaypointAction.LAND),
		Waypoint.create_lz(lz, GameEnums.WaypointAction.UNLOAD),
	]

	return mission

## Create a hunter-killer search mission
static func create_hunter_killer(search_area: Vector3, search_radius: float):  # Returns HeliMission
	var MissionScript := preload("res://helicopter_system/heli_mission.gd")
	var mission := MissionScript.new()
	mission.mission_type = GameEnums.HeliMissionType.HUNTER_KILLER
	mission.repeat = false
	mission.rules_of_engagement = GameEnums.ROE.WEAPONS_FREE
	mission.priority = 8

	# Search pattern waypoints
	var grid_size := 3
	for x in range(grid_size):
		for z in range(grid_size):
			var offset := Vector3(
				(x - grid_size/2) * search_radius * 0.6,
				25.0,
				(z - grid_size/2) * search_radius * 0.6
			)
			var wp := Waypoint.create(search_area + offset, GameEnums.WaypointAction.PATROL)
			wp.hover_duration = 10.0
			mission.waypoints.append(wp)

	return mission

# =============================================================================
# MISSION MANAGEMENT
# =============================================================================

func get_current_waypoint() -> Waypoint:
	if current_waypoint_index < waypoints.size():
		return waypoints[current_waypoint_index]
	return null

func advance_waypoint() -> bool:
	current_waypoint_index += 1
	if current_waypoint_index >= waypoints.size():
		if repeat:
			current_waypoint_index = 0
			return true
		else:
			is_complete = true
			return false
	return true

func get_mission_name() -> String:
	match mission_type:
		GameEnums.HeliMissionType.SUPPLY_RUN:
			return "Supply Run"
		GameEnums.HeliMissionType.MEDEVAC_STANDBY:
			return "Medevac Standby"
		GameEnums.HeliMissionType.TROOP_ROTATION:
			return "Troop Rotation"
		GameEnums.HeliMissionType.RECON_ORBIT:
			return "Recon Orbit"
		GameEnums.HeliMissionType.GUNSHIP_CAP:
			return "Gunship CAP"
		GameEnums.HeliMissionType.HUNTER_KILLER:
			return "Hunter-Killer"
		GameEnums.HeliMissionType.ESCORT_DUTY:
			return "Escort"
		_:
			return "Unknown"
