extends RefCounted
class_name AIContext
## AI Context - Shared battlefield state for AI decision-making.
##
## Updated once per AI tick and shared across all AI layers.
## Provides efficient access to common queries without repeated tree traversal.
##
## Usage:
##   var context := AIContext.new()
##   context.update(delta)
##   var isolated := context.get_isolated_player_units()


# =============================================================================
# BATTLEFIELD STATE
# =============================================================================

## Aggregate strength values
var player_strength: float = 0.0
var enemy_strength: float = 0.0
var player_firebase_count: int = 0

## Unit positions (updated each tick)
var player_unit_positions: Array[Vector3] = []
var enemy_unit_positions: Array[Vector3] = []
var firebase_positions: Array[Vector3] = []

## Cached unit references
var player_units: Array[Node3D] = []
var enemy_units: Array[Node3D] = []
var firebases: Array[Node3D] = []

## Vulnerable targets (damaged, isolated, or high-value)
var vulnerable_player_targets: Array[Node3D] = []
var vulnerable_enemy_targets: Array[Node3D] = []

# =============================================================================
# GAME STATE
# =============================================================================

## Current game phase from AIDirector
var game_phase: int = 0  # AIDirector.GamePhase

## Current tension phase
var tension_phase: int = 0  # AIDirector.TensionPhase

## Current difficulty level
var difficulty: float = 1.0

## Time of day (0.0 = midnight, 0.5 = noon)
var time_of_day: float = 0.5

## Weather condition
var weather: int = 0  # GameEnums.WeatherCondition

## Elapsed mission time in seconds
var mission_time: float = 0.0

# =============================================================================
# FACTION-SPECIFIC STATE
# =============================================================================

## VC state
var vc_tunnel_count: int = 0
var vc_trap_count: int = 0
var vc_hidden_unit_count: int = 0

## NVA state
var nva_artillery_ready: bool = false
var nva_artillery_cooldown: float = 0.0
var nva_aa_coverage: float = 0.0  # 0.0-1.0 coverage of player positions
var nva_siege_active: bool = false

# =============================================================================
# CONFIGURATION
# =============================================================================

## Minimum distance for safe spawning (fairness rule)
const MIN_SPAWN_DISTANCE: float = 150.0

## Distance to consider a unit "isolated"
const ISOLATION_RADIUS: float = 40.0

## Strength value per unit health point
const STRENGTH_PER_HP: float = 1.0

## Strength value per firebase
const STRENGTH_PER_FIREBASE: float = 500.0

## Update throttle (don't update more often than this)
var _update_cooldown: float = 0.0
const UPDATE_INTERVAL: float = 0.5


# =============================================================================
# UPDATE
# =============================================================================

## Update all context data. Call once per AI tick.
func update(delta: float) -> void:
	_update_cooldown -= delta
	if _update_cooldown > 0.0:
		return

	_update_cooldown = UPDATE_INTERVAL
	mission_time += UPDATE_INTERVAL

	_update_unit_lists()
	_update_positions()
	_update_strength()
	_update_vulnerable_targets()
	_update_director_state()
	_update_faction_state()


func _update_unit_lists() -> void:
	player_units.clear()
	enemy_units.clear()
	firebases.clear()

	# Get units from groups
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		return

	for node in tree.get_nodes_in_group("player_units"):
		if node is Node3D and is_instance_valid(node):
			player_units.append(node as Node3D)

	for node in tree.get_nodes_in_group("enemy_units"):
		if node is Node3D and is_instance_valid(node):
			enemy_units.append(node as Node3D)

	for node in tree.get_nodes_in_group("firebases"):
		if node is Node3D and is_instance_valid(node):
			firebases.append(node as Node3D)

	player_firebase_count = firebases.size()


func _update_positions() -> void:
	player_unit_positions.clear()
	enemy_unit_positions.clear()
	firebase_positions.clear()

	for unit in player_units:
		player_unit_positions.append(unit.global_position)

	for unit in enemy_units:
		enemy_unit_positions.append(unit.global_position)

	for fb in firebases:
		firebase_positions.append(fb.global_position)


func _update_strength() -> void:
	player_strength = 0.0
	enemy_strength = 0.0

	# Sum player unit health
	for unit in player_units:
		if unit.has_method("get") and unit.get("current_health") != null:
			player_strength += float(unit.current_health) * STRENGTH_PER_HP
		elif "current_health" in unit:
			player_strength += float(unit.current_health) * STRENGTH_PER_HP

	# Add firebase strength
	player_strength += player_firebase_count * STRENGTH_PER_FIREBASE

	# Sum enemy unit health
	for unit in enemy_units:
		if unit.has_method("get") and unit.get("current_health") != null:
			enemy_strength += float(unit.current_health) * STRENGTH_PER_HP
		elif "current_health" in unit:
			enemy_strength += float(unit.current_health) * STRENGTH_PER_HP


func _update_vulnerable_targets() -> void:
	vulnerable_player_targets.clear()
	vulnerable_enemy_targets.clear()

	# Find vulnerable player units
	for unit in player_units:
		if _is_unit_vulnerable(unit, player_units):
			vulnerable_player_targets.append(unit)

	# Find vulnerable enemy units
	for unit in enemy_units:
		if _is_unit_vulnerable(unit, enemy_units):
			vulnerable_enemy_targets.append(unit)


func _is_unit_vulnerable(unit: Node3D, friendly_units: Array[Node3D]) -> bool:
	# Check health
	var health_ratio: float = 1.0
	if unit.has_method("get") and unit.get("current_health") != null and unit.get("max_health") != null:
		var max_hp: float = float(unit.max_health)
		if max_hp > 0.0:
			health_ratio = float(unit.current_health) / max_hp

	if health_ratio < 0.5:
		return true

	# Check isolation
	var nearby_count: int = 0
	for other in friendly_units:
		if other == unit:
			continue
		if unit.global_position.distance_to(other.global_position) < ISOLATION_RADIUS:
			nearby_count += 1

	return nearby_count <= 1  # Isolated if 0-1 nearby friendlies


func _update_director_state() -> void:
	# Get state from AIDirector if available
	var director: Node = Engine.get_main_loop().root.get_node_or_null("/root/AIDirector")
	if director:
		if director.has_method("get_current_difficulty"):
			difficulty = director.get_current_difficulty()
		if "tension_phase" in director:
			tension_phase = director.tension_phase
		if "game_phase" in director:
			game_phase = director.game_phase

	# Get weather if available
	var weather_system: Node = Engine.get_main_loop().root.get_node_or_null("/root/WeatherSystem")
	if weather_system and "current_weather" in weather_system:
		weather = weather_system.current_weather


func _update_faction_state() -> void:
	# VC state
	var vc_controller: Node = _find_controller("vc_controller")
	if vc_controller:
		if vc_controller.has_method("get_hidden_unit_count"):
			vc_hidden_unit_count = vc_controller.get_hidden_unit_count()
		if vc_controller.has_method("get_trap_count"):
			vc_trap_count = vc_controller.get_trap_count()

	# NVA state
	var nva_controller: Node = _find_controller("nva_controller")
	if nva_controller:
		if "artillery_cooldown" in nva_controller:
			nva_artillery_cooldown = nva_controller.artillery_cooldown
			nva_artillery_ready = nva_artillery_cooldown <= 0.0


func _find_controller(script_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		return null

	for node in tree.get_nodes_in_group("enemy_controllers"):
		var script: Script = node.get_script()
		if script and script.resource_path.ends_with(script_name + ".gd"):
			return node

	return null


# =============================================================================
# QUERIES
# =============================================================================

## Get player units that are isolated (few nearby friendlies)
func get_isolated_player_units() -> Array[Node3D]:
	var isolated: Array[Node3D] = []

	for unit in player_units:
		var nearby_count: int = 0
		for other in player_units:
			if other == unit:
				continue
			if unit.global_position.distance_to(other.global_position) < ISOLATION_RADIUS:
				nearby_count += 1

		if nearby_count <= 1:
			isolated.append(unit)

	return isolated


## Get the nearest player firebase to a position
func get_player_firebase_nearest_to(pos: Vector3) -> Node3D:
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for fb in firebases:
		var dist: float = pos.distance_to(fb.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = fb

	return nearest


## Check if a position is safe for enemy spawning (fairness rule)
func is_position_safe_for_spawn(pos: Vector3, min_distance: float = MIN_SPAWN_DISTANCE) -> bool:
	for unit_pos in player_unit_positions:
		if pos.distance_to(unit_pos) < min_distance:
			return false

	return true


## Find a safe spawn position near a desired location
func find_safe_spawn_position(desired_pos: Vector3, search_radius: float = 50.0) -> Vector3:
	# Try the desired position first
	if is_position_safe_for_spawn(desired_pos):
		return desired_pos

	# Search in expanding rings
	for ring in range(1, 5):
		var ring_radius: float = search_radius * ring
		for angle in range(0, 360, 45):
			var rad: float = deg_to_rad(angle)
			var offset := Vector3(cos(rad) * ring_radius, 0.0, sin(rad) * ring_radius)
			var test_pos: Vector3 = desired_pos + offset

			if is_position_safe_for_spawn(test_pos):
				return test_pos

	# Fallback: return position far from player
	return desired_pos + Vector3(MIN_SPAWN_DISTANCE * 1.5, 0.0, 0.0)


## Get the center of mass of player units
func get_player_center_of_mass() -> Vector3:
	if player_unit_positions.is_empty():
		return Vector3.ZERO

	var sum := Vector3.ZERO
	for pos in player_unit_positions:
		sum += pos

	return sum / float(player_unit_positions.size())


## Get the center of mass of enemy units
func get_enemy_center_of_mass() -> Vector3:
	if enemy_unit_positions.is_empty():
		return Vector3.ZERO

	var sum := Vector3.ZERO
	for pos in enemy_unit_positions:
		sum += pos

	return sum / float(enemy_unit_positions.size())


## Get strength ratio (enemy / player). < 1.0 means player is stronger.
func get_strength_ratio() -> float:
	if player_strength <= 0.0:
		return 10.0  # Player has no strength, enemy dominates

	return enemy_strength / player_strength


## Check if it's night time (for VC bonus)
func is_night() -> bool:
	return time_of_day < 0.25 or time_of_day > 0.75


## Convert context to dictionary for utility scoring
func to_dict() -> Dictionary:
	return {
		"player_strength": player_strength,
		"enemy_strength": enemy_strength,
		"strength_ratio": get_strength_ratio(),
		"player_firebase_count": player_firebase_count,
		"player_unit_count": player_units.size(),
		"enemy_unit_count": enemy_units.size(),
		"isolated_player_count": vulnerable_player_targets.size(),
		"game_phase": game_phase,
		"tension_phase": tension_phase,
		"difficulty": difficulty,
		"is_night": is_night(),
		"vc_tunnel_count": vc_tunnel_count,
		"vc_trap_count": vc_trap_count,
		"nva_artillery_ready": nva_artillery_ready,
		"nva_siege_active": nva_siege_active,
		"mission_time": mission_time,
	}
