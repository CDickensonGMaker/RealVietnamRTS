class_name MissionObjective extends Resource
## Mission Objective - A single goal within a mission.
## Can be timed, have prerequisites, and track various completion conditions.
## Supports the Five Pillars by defining goals that require pillar-based play.

signal objective_updated(objective: MissionObjective, progress: float)
signal objective_completed(objective: MissionObjective)
signal objective_failed(objective: MissionObjective)
signal objective_revealed(objective: MissionObjective)

enum ObjectiveType {
	# Position-based
	CAPTURE_POSITION,     # Move unit to location
	HOLD_POSITION,        # Keep units at location for duration
	DEFEND_POSITION,      # Prevent enemy from reaching location

	# Construction
	BUILD_STRUCTURE,      # Build specific building type
	ESTABLISH_FIREBASE,   # Build firebase at location
	CLEAR_LZ,             # Clear landing zone
	BUILD_ROAD,           # Connect two points with road

	# Combat
	DESTROY_ENEMY,        # Kill specific number of enemies
	DESTROY_STRUCTURE,    # Destroy enemy building
	ELIMINATE_FORCE,      # Destroy all enemies in area
	DESTROY_TUNNELS,      # Find and destroy tunnel network

	# Survival
	SURVIVE_DURATION,     # Keep HQ alive for time
	PROTECT_UNIT,         # Keep specific unit alive
	MAINTAIN_SUPPLY,      # Keep supply above threshold

	# Intel/Recon
	SCOUT_AREA,           # Reveal area with recon
	IDENTIFY_ENEMY,       # Spot enemy units
	GATHER_INTEL,         # Complete recon mission

	# Support
	EVACUATE_WOUNDED,     # Medevac casualties
	RESUPPLY_FIREBASE,    # Deliver supplies to firebase
	ESCORT_CONVOY,        # Protect convoy to destination
}

@export_group("Identity")
@export var objective_id: String = "obj_01"
@export var objective_name: String = "Objective"
@export var objective_type: ObjectiveType = ObjectiveType.CAPTURE_POSITION
@export_multiline var description: String = ""

@export_group("Requirements")
@export var is_critical: bool = true  # Failure = mission failure
@export var is_hidden: bool = false  # Not shown until triggered
@export var prerequisite_ids: Array[String] = []  # Must complete these first
@export var time_limit_seconds: float = 0.0  # 0 = no limit
@export var reveal_trigger: String = ""  # Event that reveals hidden objective

@export_group("Target")
@export var target_position: Vector3 = Vector3.ZERO
@export var target_radius: float = 50.0
@export var target_node_path: String = ""  # Path to target node
@export var target_count: int = 1  # Number of things to do
@export var target_unit_type: int = -1  # Specific unit type required
@export var target_building_type: int = -1  # Specific building type

@export_group("Completion")
@export var required_duration: float = 0.0  # Seconds to hold/survive
@export var required_amount: float = 0.0  # Amount of supply/kills/etc
@export var allow_partial: bool = false  # Can partially complete

## Runtime state
var is_active: bool = false
var is_completed: bool = false
var is_failed: bool = false
var is_revealed: bool = true
var current_progress: float = 0.0
var current_count: int = 0
var elapsed_time: float = 0.0
var hold_timer: float = 0.0

## Tracked entities
var _tracked_units: Array[Node3D] = []
var _tracked_buildings: Array[Node3D] = []


func reset() -> void:
	is_active = not is_hidden
	is_completed = false
	is_failed = false
	is_revealed = not is_hidden
	current_progress = 0.0
	current_count = 0
	elapsed_time = 0.0
	hold_timer = 0.0
	_tracked_units.clear()
	_tracked_buildings.clear()


func reveal() -> void:
	if is_revealed:
		return

	is_revealed = true
	is_active = true
	objective_revealed.emit(self)


func check_completion() -> void:
	if is_completed or is_failed or not is_active:
		return

	# Check time limit
	if time_limit_seconds > 0.0 and elapsed_time >= time_limit_seconds:
		if not is_completed:
			fail()
		return

	# Check prerequisites
	if not _prerequisites_met():
		return

	# Type-specific completion checks
	match objective_type:
		ObjectiveType.CAPTURE_POSITION:
			_check_capture_position()
		ObjectiveType.HOLD_POSITION:
			_check_hold_position()
		ObjectiveType.DEFEND_POSITION:
			_check_defend_position()
		ObjectiveType.BUILD_STRUCTURE:
			_check_build_structure()
		ObjectiveType.ESTABLISH_FIREBASE:
			_check_establish_firebase()
		ObjectiveType.CLEAR_LZ:
			_check_clear_lz()
		ObjectiveType.BUILD_ROAD:
			_check_build_road()
		ObjectiveType.DESTROY_ENEMY:
			_check_destroy_enemy()
		ObjectiveType.DESTROY_STRUCTURE:
			_check_destroy_structure()
		ObjectiveType.ELIMINATE_FORCE:
			_check_eliminate_force()
		ObjectiveType.DESTROY_TUNNELS:
			_check_destroy_tunnels()
		ObjectiveType.SURVIVE_DURATION:
			_check_survive_duration()
		ObjectiveType.PROTECT_UNIT:
			_check_protect_unit()
		ObjectiveType.MAINTAIN_SUPPLY:
			_check_maintain_supply()
		ObjectiveType.SCOUT_AREA:
			_check_scout_area()
		ObjectiveType.EVACUATE_WOUNDED:
			_check_evacuate_wounded()
		ObjectiveType.RESUPPLY_FIREBASE:
			_check_resupply_firebase()
		ObjectiveType.ESCORT_CONVOY:
			_check_escort_convoy()


func _prerequisites_met() -> bool:
	if prerequisite_ids.is_empty():
		return true

	# Check parent mission for completed objectives
	# This would typically be checked against the Mission's completed_objectives array
	# For now, return true if no prerequisites
	return true


func complete() -> void:
	if is_completed:
		return

	is_completed = true
	is_active = false
	current_progress = 1.0
	objective_completed.emit(self)


func fail() -> void:
	if is_failed or is_completed:
		return

	is_failed = true
	is_active = false
	objective_failed.emit(self)


func update_progress(progress: float) -> void:
	current_progress = clampf(progress, 0.0, 1.0)
	objective_updated.emit(self, current_progress)


func increment_count(amount: int = 1) -> void:
	current_count += amount
	current_progress = float(current_count) / float(target_count) if target_count > 0 else 1.0
	objective_updated.emit(self, current_progress)

	if current_count >= target_count:
		complete()


# =============================================================================
# TYPE-SPECIFIC CHECKS
# =============================================================================

func _check_capture_position() -> void:
	var tree := Engine.get_main_loop()
	if not tree or not tree is SceneTree:
		return

	var player_units: Array[Node] = (tree as SceneTree).get_nodes_in_group("player_units")

	for unit in player_units:
		if not is_instance_valid(unit):
			continue

		var dist: float = unit.global_position.distance_to(target_position)
		if dist <= target_radius:
			complete()
			return


func _check_hold_position() -> void:
	var tree := Engine.get_main_loop()
	if not tree or not tree is SceneTree:
		return

	var player_units: Array[Node] = (tree as SceneTree).get_nodes_in_group("player_units")
	var units_in_zone: int = 0

	for unit in player_units:
		if not is_instance_valid(unit):
			continue

		var dist: float = unit.global_position.distance_to(target_position)
		if dist <= target_radius:
			units_in_zone += 1

	if units_in_zone >= target_count:
		# Timer ticks while holding
		hold_timer += 0.1  # Assuming check runs ~10 times/sec
		current_progress = hold_timer / required_duration

		if hold_timer >= required_duration:
			complete()
	else:
		# Reset timer if not enough units
		hold_timer = maxf(0.0, hold_timer - 0.2)
		current_progress = hold_timer / required_duration


func _check_defend_position() -> void:
	var tree := Engine.get_main_loop()
	if not tree or not tree is SceneTree:
		return

	var enemy_units: Array[Node] = (tree as SceneTree).get_nodes_in_group("enemy_units")

	for enemy in enemy_units:
		if not is_instance_valid(enemy):
			continue

		var dist: float = enemy.global_position.distance_to(target_position)
		if dist <= target_radius:
			fail()
			return

	# Update time-based progress for defend objectives
	if required_duration > 0.0:
		elapsed_time += 0.1
		current_progress = elapsed_time / required_duration

		if elapsed_time >= required_duration:
			complete()


func _check_build_structure() -> void:
	var tree := Engine.get_main_loop()
	if not tree or not tree is SceneTree:
		return

	var buildings: Array[Node] = (tree as SceneTree).get_nodes_in_group("buildings")
	var matching: int = 0

	for building in buildings:
		if not is_instance_valid(building):
			continue

		# Check building type
		if target_building_type >= 0:
			if building.has_method("get") and building.get("building_type"):
				if building.building_type != target_building_type:
					continue

		# Check position if specified
		if target_position != Vector3.ZERO:
			var dist: float = building.global_position.distance_to(target_position)
			if dist > target_radius:
				continue

		# Check if complete
		if building.has_method("get") and building.get("is_complete"):
			if building.is_complete:
				matching += 1

	current_count = matching
	current_progress = float(matching) / float(target_count) if target_count > 0 else 1.0

	if matching >= target_count:
		complete()


func _check_establish_firebase() -> void:
	var tree := Engine.get_main_loop()
	if not tree or not tree is SceneTree:
		return

	var firebases: Array[Node] = (tree as SceneTree).get_nodes_in_group("firebases")

	for firebase in firebases:
		if not is_instance_valid(firebase):
			continue

		var dist: float = firebase.global_position.distance_to(target_position)
		if dist <= target_radius:
			# Check if firebase is operational
			if firebase.has_method("is_operational") and firebase.is_operational():
				complete()
				return


func _check_clear_lz() -> void:
	var tree := Engine.get_main_loop()
	if not tree or not tree is SceneTree:
		return

	# Check if terrain is cleared at position
	var terrain_clearing := (tree as SceneTree).root.get_node_or_null("/root/TerrainClearingSystem")
	if terrain_clearing and terrain_clearing.has_method("get_clearing_state"):
		var state: int = terrain_clearing.get_clearing_state(target_position)
		if state >= 2:  # CLEARED or FORTIFIED
			complete()


func _check_build_road() -> void:
	# Road completion would be checked against road network
	# For now, simplified check
	pass


func _check_destroy_enemy() -> void:
	# This is typically updated via on_enemy_killed events
	if current_count >= target_count:
		complete()


func _check_destroy_structure() -> void:
	var tree := Engine.get_main_loop()
	if not tree or not tree is SceneTree:
		return

	# Check if target structure still exists
	if target_node_path != "":
		var target := (tree as SceneTree).root.get_node_or_null(target_node_path)
		if not target or not is_instance_valid(target):
			complete()
			return

		# Check if destroyed
		if target.has_method("get") and target.get("is_destroyed"):
			if target.is_destroyed:
				complete()


func _check_eliminate_force() -> void:
	var tree := Engine.get_main_loop()
	if not tree or not tree is SceneTree:
		return

	var enemy_units: Array[Node] = (tree as SceneTree).get_nodes_in_group("enemy_units")
	var enemies_in_area: int = 0

	for enemy in enemy_units:
		if not is_instance_valid(enemy):
			continue

		var dist: float = enemy.global_position.distance_to(target_position)
		if dist <= target_radius:
			enemies_in_area += 1

	if enemies_in_area == 0:
		complete()


func _check_destroy_tunnels() -> void:
	var tree := Engine.get_main_loop()
	if not tree or not tree is SceneTree:
		return

	var tunnel_entrances: Array[Node] = (tree as SceneTree).get_nodes_in_group("tunnel_entrances")
	var destroyed: int = 0
	var total: int = 0

	for entrance in tunnel_entrances:
		if not is_instance_valid(entrance):
			continue

		var dist: float = entrance.global_position.distance_to(target_position)
		if dist > target_radius and target_radius > 0.0:
			continue

		total += 1

		if entrance.has_method("is_destroyed") and entrance.is_destroyed():
			destroyed += 1

	if total > 0:
		current_progress = float(destroyed) / float(total)
		if destroyed >= total:
			complete()


func _check_survive_duration() -> void:
	elapsed_time += 0.1
	current_progress = elapsed_time / required_duration

	if elapsed_time >= required_duration:
		complete()


func _check_protect_unit() -> void:
	var tree := Engine.get_main_loop()
	if not tree or not tree is SceneTree:
		return

	if target_node_path == "":
		return

	var target := (tree as SceneTree).root.get_node_or_null(target_node_path)
	if not target or not is_instance_valid(target):
		fail()
		return

	# Check if unit is alive
	if target.has_method("get") and target.get("state"):
		if target.state == 5:  # DEAD state typically
			fail()


func _check_maintain_supply() -> void:
	var tree := Engine.get_main_loop()
	if not tree or not tree is SceneTree:
		return

	# Check supply manager
	var supply_manager := (tree as SceneTree).root.get_node_or_null("/root/SupplyManager")
	if supply_manager and supply_manager.has_method("get_total_supply"):
		var current_supply: float = supply_manager.get_total_supply()
		if current_supply < required_amount:
			fail()


func _check_scout_area() -> void:
	var tree := Engine.get_main_loop()
	if not tree or not tree is SceneTree:
		return

	# Check fog of war
	var fog_of_war := (tree as SceneTree).root.get_node_or_null("/root/FogOfWar")
	if fog_of_war and fog_of_war.has_method("get_visibility_percent"):
		var visibility: float = fog_of_war.get_visibility_percent(target_position, target_radius)
		current_progress = visibility

		if visibility >= 0.8:  # 80% revealed
			complete()


func _check_evacuate_wounded() -> void:
	# Tracked via medevac events
	if current_count >= target_count:
		complete()


func _check_resupply_firebase() -> void:
	var tree := Engine.get_main_loop()
	if not tree or not tree is SceneTree:
		return

	if target_node_path == "":
		return

	var firebase := (tree as SceneTree).root.get_node_or_null(target_node_path)
	if not firebase:
		return

	if firebase.has_method("get_supply_level"):
		var supply: float = firebase.get_supply_level()
		current_progress = supply / required_amount

		if supply >= required_amount:
			complete()


func _check_escort_convoy() -> void:
	var tree := Engine.get_main_loop()
	if not tree or not tree is SceneTree:
		return

	if target_node_path == "":
		return

	var convoy := (tree as SceneTree).root.get_node_or_null(target_node_path)

	if not convoy or not is_instance_valid(convoy):
		fail()
		return

	# Check if convoy reached destination
	if convoy.has_method("get") and convoy.get("state"):
		if convoy.state == 4:  # ARRIVED state
			complete()
		elif convoy.state == 5:  # DESTROYED state
			fail()


# =============================================================================
# EVENT HANDLERS
# =============================================================================

func on_enemy_killed(enemy: Node3D) -> void:
	if objective_type == ObjectiveType.DESTROY_ENEMY:
		increment_count()


func on_patient_evacuated(patient: Node3D) -> void:
	if objective_type == ObjectiveType.EVACUATE_WOUNDED:
		increment_count()


func on_supply_delivered(amount: float) -> void:
	if objective_type == ObjectiveType.RESUPPLY_FIREBASE:
		current_count = int(amount)
		check_completion()


# =============================================================================
# QUERIES
# =============================================================================

func get_progress() -> float:
	return current_progress


func get_time_remaining() -> float:
	if time_limit_seconds <= 0.0:
		return -1.0
	return maxf(0.0, time_limit_seconds - elapsed_time)


func get_status_text() -> String:
	if is_completed:
		return "COMPLETE"
	elif is_failed:
		return "FAILED"
	elif not is_active:
		return "LOCKED"
	else:
		match objective_type:
			ObjectiveType.HOLD_POSITION, ObjectiveType.SURVIVE_DURATION:
				return "%.0f / %.0f sec" % [hold_timer if hold_timer > 0 else elapsed_time, required_duration]
			ObjectiveType.DESTROY_ENEMY, ObjectiveType.BUILD_STRUCTURE:
				return "%d / %d" % [current_count, target_count]
			_:
				return "%.0f%%" % (current_progress * 100.0)
