extends Node
class_name MissionManager
## MissionManager - Orchestrates mission flow, objectives, and win/loss conditions
## Singleton that runs the active mission and displays results

signal mission_started(mission: Mission)
signal mission_ended(victory: bool)
signal objective_updated(objective: MissionObjective)
signal time_warning(seconds_remaining: int)

const Mission = preload("res://campaign/mission.gd")
const MissionObjective = preload("res://campaign/mission_objective.gd")

## Current mission
var current_mission: Mission = null
var is_mission_active: bool = false

## UI references (set by scene)
var mission_hud: Control = null
var victory_screen: Control = null
var defeat_screen: Control = null

## Stats tracking
var mission_start_time: float = 0.0


func _ready() -> void:
	# Connect to battle signals
	if BattleSignals:
		BattleSignals.unit_died.connect(_on_unit_died)
		BattleSignals.construction_complete.connect(_on_building_constructed)

	add_to_group("mission_manager")
	print("[MissionManager] Initialized")


func _process(delta: float) -> void:
	if is_mission_active and current_mission:
		current_mission.update(delta)


## Start a new mission
func start_mission(mission: Mission) -> void:
	if is_mission_active:
		push_warning("[MissionManager] Mission already active, ending current mission")
		end_mission(false)

	current_mission = mission
	is_mission_active = true
	mission_start_time = Time.get_ticks_msec() / 1000.0

	# Connect mission signals
	mission.mission_ended.connect(_on_mission_ended)
	mission.objective_completed.connect(_on_objective_completed)
	mission.objective_failed.connect(_on_objective_failed)
	mission.time_warning.connect(_on_time_warning)

	# Start the mission
	mission.start()

	# Emit signals
	mission_started.emit(mission)
	if BattleSignals:
		BattleSignals.mission_started.emit(mission.mission_name)

	# Update HUD
	if mission_hud and mission_hud.has_method("show_mission"):
		mission_hud.show_mission(mission)

	print("[MissionManager] Mission started: %s" % mission.mission_name)


## End the current mission
func end_mission(victory: bool) -> void:
	if not is_mission_active:
		return

	is_mission_active = false

	# Disconnect signals
	if current_mission:
		if current_mission.mission_ended.is_connected(_on_mission_ended):
			current_mission.mission_ended.disconnect(_on_mission_ended)
		if current_mission.objective_completed.is_connected(_on_objective_completed):
			current_mission.objective_completed.disconnect(_on_objective_completed)
		if current_mission.objective_failed.is_connected(_on_objective_failed):
			current_mission.objective_failed.disconnect(_on_objective_failed)
		if current_mission.time_warning.is_connected(_on_time_warning):
			current_mission.time_warning.disconnect(_on_time_warning)

	# Emit signals
	mission_ended.emit(victory)
	if BattleSignals:
		BattleSignals.mission_complete.emit(victory)

	# Show result screen
	_show_result_screen(victory)

	print("[MissionManager] Mission ended - %s" % ("VICTORY" if victory else "DEFEAT"))


## Show victory or defeat screen
func _show_result_screen(victory: bool) -> void:
	# Pause game
	get_tree().paused = true

	if victory and victory_screen:
		victory_screen.visible = true
		if victory_screen.has_method("show_stats"):
			victory_screen.show_stats(current_mission.get_mission_stats())
	elif not victory and defeat_screen:
		defeat_screen.visible = true
		if defeat_screen.has_method("show_stats"):
			defeat_screen.show_stats(current_mission.get_mission_stats())
	else:
		# No UI - just print to console
		var stats: Dictionary = current_mission.get_mission_stats() if current_mission else {}
		print("=".repeat(50))
		print("MISSION %s" % ("VICTORY" if victory else "DEFEAT"))
		print("=".repeat(50))
		print("Time: %.0f seconds" % stats.get("elapsed_time", 0))
		print("Units Lost: %d" % stats.get("units_lost", 0))
		print("Enemies Killed: %d" % stats.get("enemies_killed", 0))
		print("Buildings Constructed: %d" % stats.get("buildings_constructed", 0))
		print("Primary Objectives: %d/%d" % [stats.get("primary_complete", 0), stats.get("primary_total", 0)])
		print("=".repeat(50))


## Signal handlers
func _on_mission_ended(mission: Mission, victory: bool) -> void:
	end_mission(victory)


func _on_objective_completed(objective: MissionObjective) -> void:
	objective_updated.emit(objective)

	if mission_hud and mission_hud.has_method("update_objective"):
		mission_hud.update_objective(objective)

	print("[MissionManager] Objective complete: %s" % objective.objective_name)


func _on_objective_failed(objective: MissionObjective) -> void:
	objective_updated.emit(objective)

	if mission_hud and mission_hud.has_method("update_objective"):
		mission_hud.update_objective(objective)

	print("[MissionManager] Objective failed: %s" % objective.objective_name)


func _on_time_warning(minutes_remaining: int) -> void:
	time_warning.emit(minutes_remaining * 60)
	print("[MissionManager] TIME WARNING: %d minutes remaining!" % minutes_remaining)


func _on_unit_died(unit: Node3D, _killer: Node3D) -> void:
	if not current_mission:
		return

	var was_player: bool = unit.is_in_group("player_units")
	current_mission.on_unit_killed(unit, was_player)

	# Update destroy enemy objectives
	if not was_player:
		for obj in current_mission.primary_objectives:
			if obj and obj.objective_type == MissionObjective.ObjectiveType.DESTROY_ENEMY:
				obj.on_enemy_killed(unit)
		for obj in current_mission.secondary_objectives:
			if obj and obj.objective_type == MissionObjective.ObjectiveType.DESTROY_ENEMY:
				obj.on_enemy_killed(unit)


func _on_building_constructed(building: Node3D) -> void:
	if current_mission:
		current_mission.on_building_constructed(building)


# =============================================================================
# PUBLIC API
# =============================================================================

## Get current mission
func get_current_mission() -> Mission:
	return current_mission


## Get primary objectives status
func get_objectives() -> Array[Dictionary]:
	if not current_mission:
		return []
	return current_mission.get_primary_objectives_status()


## Get secondary objectives status
func get_secondary_objectives() -> Array[Dictionary]:
	if not current_mission:
		return []
	return current_mission.get_secondary_objectives_status()


## Get time remaining in mission
func get_time_remaining() -> float:
	if not current_mission:
		return -1.0
	return current_mission.get_time_remaining()


## Get mission stats
func get_stats() -> Dictionary:
	if not current_mission:
		return {}
	return current_mission.get_mission_stats()


## Check if mission is active
func is_active() -> bool:
	return is_mission_active


## Force mission victory (cheat/debug)
func force_victory() -> void:
	if current_mission:
		current_mission.end_mission(true)


## Force mission defeat (cheat/debug)
func force_defeat() -> void:
	if current_mission:
		current_mission.end_mission(false)


# =============================================================================
# QUICK MISSION CREATION (for testing)
# =============================================================================

## Create a simple defend mission for testing
static func create_defend_mission(firebase_pos: Vector3, duration_minutes: float = 30.0) -> Mission:
	var mission := Mission.new()
	mission.mission_id = "test_defend"
	mission.mission_name = "Defend Firebase"
	mission.mission_type = Mission.MissionType.HOLD_THE_LINE
	mission.briefing = "Hold your position against enemy attacks."
	mission.time_limit_minutes = duration_minutes + 10.0  # Extra time after objective

	# Create survive objective
	var survive_obj := MissionObjective.new()
	survive_obj.objective_id = "survive"
	survive_obj.objective_name = "Hold the Firebase"
	survive_obj.objective_type = MissionObjective.ObjectiveType.SURVIVE_DURATION
	survive_obj.description = "Survive for %.0f minutes" % duration_minutes
	survive_obj.required_duration = duration_minutes * 60.0
	survive_obj.is_critical = true

	mission.primary_objectives.append(survive_obj)

	# Create secondary kill objective
	var kill_obj := MissionObjective.new()
	kill_obj.objective_id = "kills"
	kill_obj.objective_name = "Eliminate Enemy Forces"
	kill_obj.objective_type = MissionObjective.ObjectiveType.DESTROY_ENEMY
	kill_obj.description = "Kill 50 enemy soldiers"
	kill_obj.target_count = 50
	kill_obj.is_critical = false

	mission.secondary_objectives.append(kill_obj)

	return mission


## Create a simple build firebase mission for testing
static func create_build_firebase_mission(target_pos: Vector3) -> Mission:
	var mission := Mission.new()
	mission.mission_id = "test_build"
	mission.mission_name = "Establish Firebase"
	mission.mission_type = Mission.MissionType.ESTABLISH_FIREBASE
	mission.briefing = "Establish a firebase at the marked location."
	mission.time_limit_minutes = 45.0

	# Create build TOC objective
	var build_obj := MissionObjective.new()
	build_obj.objective_id = "build_toc"
	build_obj.objective_name = "Build Command Post"
	build_obj.objective_type = MissionObjective.ObjectiveType.BUILD_STRUCTURE
	build_obj.description = "Construct a TOC at the firebase"
	build_obj.target_position = target_pos
	build_obj.target_radius = 100.0
	build_obj.target_building_type = 18  # TOC
	build_obj.target_count = 1
	build_obj.is_critical = true

	mission.primary_objectives.append(build_obj)

	return mission
