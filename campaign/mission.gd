class_name Mission extends Resource
## Mission - Defines a single campaign mission.
## Contains objectives, time limits, available forces, and win/loss conditions.
## Missions expand the playable map area progressively (per D-305).
##
## Serves all Five Pillars by providing the structured context in which
## players carve the map, build firebases, run supply chains, deploy doctrine,
## and let the war continue.

signal mission_started(mission: Mission)
signal mission_ended(mission: Mission, victory: bool)
signal objective_completed(objective: MissionObjective)
signal objective_failed(objective: MissionObjective)
signal time_warning(minutes_remaining: int)
signal map_expanded(new_bounds: Rect2)
signal reinforcements_available(unit_type: int)

enum MissionType {
	ESTABLISH_FIREBASE,   # Build and defend a new firebase
	SEARCH_AND_DESTROY,   # Clear enemy from an area
	HOLD_THE_LINE,        # Defend against waves
	RELIEF_COLUMN,        # Break through to besieged firebase
	AIR_ASSAULT,          # Helicopter insertion and capture
	TUNNEL_CLEAR,         # Find and destroy tunnel network
	CONVOY_ESCORT,        # Protect supply convoy
	FIREBASE_ASSAULT,     # Attack enemy position (VC campaign)
}

enum Difficulty {
	TUTORIAL,
	EASY,
	NORMAL,
	HARD,
	HISTORICAL,  # Accurate to real battle conditions
}

@export_group("Identity")
@export var mission_id: String = "mission_01"
@export var mission_name: String = "Firebase Alpha"
@export var mission_type: MissionType = MissionType.ESTABLISH_FIREBASE
@export var difficulty: Difficulty = Difficulty.NORMAL
@export var campaign_index: int = 0  # Position in campaign sequence

@export_group("Description")
@export_multiline var briefing: String = ""
@export_multiline var situation: String = ""
@export_multiline var objectives_text: String = ""
@export_multiline var debrief_victory: String = ""
@export_multiline var debrief_defeat: String = ""

@export_group("Timing")
@export var time_limit_minutes: float = 90.0  # 0 = no limit
@export var setup_time_minutes: float = 10.0  # Time before enemy attacks
@export var expected_duration_minutes: float = 60.0

@export_group("Map")
@export var map_scene_path: String = ""
@export var starting_bounds: Rect2 = Rect2(0, 0, 500, 500)  # Initial playable area
@export var expanded_bounds: Rect2 = Rect2(0, 0, 1000, 1000)  # After expansion trigger
@export var map_expansion_trigger: String = ""  # Objective ID that triggers expansion

@export_group("Starting Forces")
@export var starting_units: Array[Dictionary] = []  # [{type: UnitType, count: int, position: Vector3}]
@export var starting_supply: float = 1000.0
@export var starting_buildings: Array[Dictionary] = []  # [{type: BuildingType, position: Vector3}]

@export_group("Reinforcements")
@export var reinforcement_schedule: Array[Dictionary] = []  # [{time: float, type: UnitType, count: int}]
@export var reinforcement_pool: Dictionary = {}  # UnitType -> max_available
@export var reinforcement_cooldowns: Dictionary = {}  # UnitType -> cooldown_seconds

@export_group("Enemy Forces")
@export var enemy_waves: Array[Dictionary] = []  # [{time: float, units: [{type, count, spawn}], direction: Vector3}]
@export var enemy_ai_controller: String = "vc"  # "vc" or "nva"
@export var enemy_aggression: float = 0.5  # 0 = passive, 1 = relentless

@export_group("Objectives")
@export var primary_objectives: Array[MissionObjective] = []
@export var secondary_objectives: Array[MissionObjective] = []
@export var hidden_objectives: Array[MissionObjective] = []

@export_group("Special Rules")
@export var allow_air_support: bool = true
@export var allow_artillery: bool = true
@export var weather_conditions: Array[int] = [0]  # GameEnums.WeatherCondition values
@export var time_of_day: String = "afternoon"  # morning, afternoon, evening, night
@export var special_rules: Array[String] = []  # Custom rule identifiers

## Runtime state
var is_active: bool = false
var elapsed_time: float = 0.0
var supply_remaining: float = 0.0
var completed_objectives: Array[String] = []
var failed_objectives: Array[String] = []
var units_lost: int = 0
var enemies_killed: int = 0
var buildings_constructed: int = 0
var has_expanded_map: bool = false


func start() -> void:
	is_active = true
	elapsed_time = 0.0
	supply_remaining = starting_supply
	completed_objectives.clear()
	failed_objectives.clear()
	units_lost = 0
	enemies_killed = 0
	buildings_constructed = 0
	has_expanded_map = false

	mission_started.emit(self)

	# Initialize all objectives
	for obj in primary_objectives:
		if obj:
			obj.reset()
	for obj in secondary_objectives:
		if obj:
			obj.reset()
	for obj in hidden_objectives:
		if obj:
			obj.reset()


func update(delta: float) -> void:
	if not is_active:
		return

	elapsed_time += delta

	# Check time limit
	if time_limit_minutes > 0.0:
		var remaining: float = (time_limit_minutes * 60.0) - elapsed_time
		if remaining <= 0.0:
			_check_victory_on_timeout()
		elif remaining <= 300.0 and int(remaining) % 60 == 0:  # 5 minute warnings
			time_warning.emit(int(remaining / 60.0))

	# Check objectives
	_check_objectives()

	# Check for map expansion
	if not has_expanded_map and map_expansion_trigger != "":
		if map_expansion_trigger in completed_objectives:
			_expand_map()


func _check_objectives() -> void:
	var all_primary_complete: bool = true
	var any_primary_failed: bool = false

	for obj in primary_objectives:
		if not obj:
			continue

		obj.check_completion()

		if obj.is_completed and obj.objective_id not in completed_objectives:
			completed_objectives.append(obj.objective_id)
			objective_completed.emit(obj)

		if obj.is_failed and obj.objective_id not in failed_objectives:
			failed_objectives.append(obj.objective_id)
			objective_failed.emit(obj)
			if obj.is_critical:
				any_primary_failed = true

		if not obj.is_completed:
			all_primary_complete = false

	# Check secondary objectives
	for obj in secondary_objectives:
		if not obj:
			continue

		obj.check_completion()

		if obj.is_completed and obj.objective_id not in completed_objectives:
			completed_objectives.append(obj.objective_id)
			objective_completed.emit(obj)

	# Check hidden objectives
	for obj in hidden_objectives:
		if not obj:
			continue

		obj.check_completion()

		if obj.is_completed and obj.objective_id not in completed_objectives:
			completed_objectives.append(obj.objective_id)
			objective_completed.emit(obj)

	# Victory/defeat conditions
	if any_primary_failed:
		end_mission(false)
	elif all_primary_complete:
		end_mission(true)


func _check_victory_on_timeout() -> void:
	# Determine outcome based on objective completion
	var primary_done: int = 0
	for obj in primary_objectives:
		if obj and obj.is_completed:
			primary_done += 1

	# Win if majority of primary objectives complete
	var victory: bool = primary_done >= ceili(primary_objectives.size() / 2.0)
	end_mission(victory)


func end_mission(victory: bool) -> void:
	is_active = false
	mission_ended.emit(self, victory)


func _expand_map() -> void:
	has_expanded_map = true
	map_expanded.emit(expanded_bounds)


# =============================================================================
# QUERIES
# =============================================================================

func get_time_remaining() -> float:
	if time_limit_minutes <= 0.0:
		return -1.0  # No limit
	return maxf(0.0, (time_limit_minutes * 60.0) - elapsed_time)


func get_primary_objectives_status() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for obj in primary_objectives:
		if obj:
			result.append({
				"id": obj.objective_id,
				"name": obj.objective_name,
				"description": obj.description,
				"completed": obj.is_completed,
				"failed": obj.is_failed,
				"progress": obj.get_progress(),
			})
	return result


func get_secondary_objectives_status() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for obj in secondary_objectives:
		if obj:
			result.append({
				"id": obj.objective_id,
				"name": obj.objective_name,
				"description": obj.description,
				"completed": obj.is_completed,
				"progress": obj.get_progress(),
			})
	return result


func get_mission_stats() -> Dictionary:
	return {
		"elapsed_time": elapsed_time,
		"time_remaining": get_time_remaining(),
		"supply_remaining": supply_remaining,
		"units_lost": units_lost,
		"enemies_killed": enemies_killed,
		"buildings_constructed": buildings_constructed,
		"primary_complete": completed_objectives.filter(func(id): return _is_primary_objective(id)).size(),
		"primary_total": primary_objectives.size(),
		"secondary_complete": completed_objectives.filter(func(id): return _is_secondary_objective(id)).size(),
		"secondary_total": secondary_objectives.size(),
	}


func _is_primary_objective(obj_id: String) -> bool:
	for obj in primary_objectives:
		if obj and obj.objective_id == obj_id:
			return true
	return false


func _is_secondary_objective(obj_id: String) -> bool:
	for obj in secondary_objectives:
		if obj and obj.objective_id == obj_id:
			return true
	return false


func get_available_reinforcements() -> Dictionary:
	return reinforcement_pool.duplicate()


func can_request_reinforcement(unit_type: int) -> bool:
	if not reinforcement_pool.has(unit_type):
		return false
	return reinforcement_pool[unit_type] > 0


func request_reinforcement(unit_type: int) -> bool:
	if not can_request_reinforcement(unit_type):
		return false

	reinforcement_pool[unit_type] -= 1
	return true


# =============================================================================
# EVENT HANDLERS (called by game systems)
# =============================================================================

func on_unit_killed(unit: Node3D, was_player: bool) -> void:
	if was_player:
		units_lost += 1
	else:
		enemies_killed += 1


func on_building_constructed(building: Node3D) -> void:
	buildings_constructed += 1


func on_supply_consumed(amount: float) -> void:
	supply_remaining = maxf(0.0, supply_remaining - amount)


func on_supply_delivered(amount: float) -> void:
	supply_remaining += amount
