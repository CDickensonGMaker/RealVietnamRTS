extends Node
class_name EnemyAIController

## Base Enemy AI Controller
## Handles basic AI behaviors: patrol, attack, retreat
## Extended by VCController and NVAController for faction-specific tactics

signal wave_spawned(wave_number: int, units: Array)
signal unit_spotted(enemy: Node3D, by_unit: Node3D)

const Squad = preload("res://battle_system/nodes/squad.gd")

enum AIState { IDLE, PATROL, ATTACK, RETREAT, DEFEND }

## AI Configuration
@export var faction: int = GameEnums.Faction.VC
@export var aggression: float = 0.7  # 0.0 = passive, 1.0 = aggressive
@export var detection_range: float = 40.0
@export var attack_range: float = 25.0
@export var retreat_health_threshold: float = 0.3

## Wave spawning
@export var enable_waves: bool = true
@export var wave_interval: float = 60.0  # Seconds between waves
@export var units_per_wave: int = 5
@export var max_waves: int = 10

## Managed units
var controlled_units: Array[Node3D] = []
var current_wave: int = 0
var wave_timer: float = 0.0

## Spawn configuration
var spawn_points: Array[Vector3] = []
var unit_data_pool: Array[Resource] = []


func _ready() -> void:
	# Find all enemy units already in scene
	_collect_existing_units()

	# Set up default spawn points if none configured
	if spawn_points.is_empty():
		spawn_points = [
			Vector3(20, 0, 0),
			Vector3(25, 0, 5),
			Vector3(20, 0, -5),
		]


func _process(delta: float) -> void:
	# Update wave timer
	if enable_waves and current_wave < max_waves:
		wave_timer += delta
		if wave_timer >= wave_interval:
			wave_timer = 0.0
			_spawn_wave()

	# Update AI for each controlled unit
	for unit in controlled_units:
		if is_instance_valid(unit) and unit.state != Squad.State.DEAD:
			_update_unit_ai(unit)

	# Clean up dead units
	controlled_units = controlled_units.filter(func(u):
		return is_instance_valid(u) and u.state != Squad.State.DEAD
	)


func _collect_existing_units() -> void:
	"""Find existing enemy units in scene"""
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy_units")
	for enemy in enemies:
		if enemy is Node3D and enemy not in controlled_units:
			controlled_units.append(enemy)
			_setup_unit(enemy)


func _setup_unit(unit: Node3D) -> void:
	"""Configure a unit for AI control"""
	if unit.has_signal("squad_died"):
		if not unit.squad_died.is_connected(_on_unit_died):
			unit.squad_died.connect(_on_unit_died)


func _update_unit_ai(unit: Node3D) -> void:
	"""Update AI behavior for a single unit"""
	# Skip if unit is already in combat
	if unit.state == Squad.State.COMBAT:
		# Check if target is still valid
		if unit.has_method("get") and unit.get("current_target"):
			if not is_instance_valid(unit.current_target) or unit.current_target.state == Squad.State.DEAD:
				unit.stop_attack()
		return

	# Check health for retreat
	if unit.has_method("get") and unit.get("current_health") != null:
		var health_ratio: float = unit.current_health / unit.max_health
		if health_ratio < retreat_health_threshold:
			_order_retreat(unit)
			return

	# Look for enemies to attack
	var target: Node3D = _find_nearest_player_unit(unit)
	if target:
		var distance: float = unit.global_position.distance_to(target.global_position)

		# Detection range check
		if distance <= detection_range:
			unit_spotted.emit(target, unit)

			# Attack if within attack range or aggressive enough
			if distance <= attack_range or randf() < aggression:
				if unit.has_method("attack"):
					unit.attack(target)


func _find_nearest_player_unit(from_unit: Node3D) -> Node3D:
	"""Find the nearest player-controlled unit"""
	var player_units: Array[Node] = get_tree().get_nodes_in_group("player_units")
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for player_unit in player_units:
		if not is_instance_valid(player_unit):
			continue
		if player_unit.has_method("get") and player_unit.get("state") == Squad.State.DEAD:
			continue

		var dist: float = from_unit.global_position.distance_to(player_unit.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = player_unit as Node3D

	return nearest


func _order_retreat(unit: Node3D) -> void:
	"""Order unit to retreat to spawn point"""
	if spawn_points.is_empty():
		return

	# Find nearest spawn point
	var retreat_pos: Vector3 = spawn_points[0]
	var nearest_dist: float = INF

	for sp in spawn_points:
		var dist: float = unit.global_position.distance_to(sp)
		if dist < nearest_dist:
			nearest_dist = dist
			retreat_pos = sp

	if unit.has_method("stop_attack"):
		unit.stop_attack()
	if unit.has_method("move_to"):
		unit.move_to(retreat_pos)


func _spawn_wave() -> void:
	"""Spawn a wave of enemy units"""
	current_wave += 1
	var spawned_units: Array[Node3D] = []

	for i in units_per_wave:
		var spawn_pos: Vector3 = spawn_points[i % spawn_points.size()]
		# Add some randomness to spawn position
		spawn_pos += Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))

		var unit: Node3D = _spawn_unit(spawn_pos)
		if unit:
			spawned_units.append(unit)
			controlled_units.append(unit)

	wave_spawned.emit(current_wave, spawned_units)
	if BattleSignals:
		BattleSignals.wave_incoming.emit(current_wave, spawned_units.size())

	print("[EnemyAI] Wave %d spawned: %d units" % [current_wave, spawned_units.size()])


func _spawn_unit(spawn_pos: Vector3) -> Node3D:
	"""Spawn a single enemy unit - override in subclass"""
	# Default implementation - should be overridden
	push_warning("[EnemyAI] _spawn_unit not implemented - override in subclass")
	return null


func _on_unit_died(unit: Node3D) -> void:
	"""Handle unit death"""
	controlled_units.erase(unit)


## Add a spawn point
func add_spawn_point(pos: Vector3) -> void:
	spawn_points.append(pos)


## Force spawn a wave immediately
func force_spawn_wave() -> void:
	_spawn_wave()


## Get count of active units
func get_active_unit_count() -> int:
	return controlled_units.size()
