extends Node
## AIDirector - Enemy theater commander
## Manages assault waves, enemy positioning, and strategic decisions
## Inspired by Left 4 Dead's AI Director + Total War campaign AI

signal assault_wave_starting(wave_number: int, direction: Vector3)
signal assault_wave_ended(wave_number: int, success: bool)
signal enemy_reinforced(position_id: int)
signal difficulty_escalated

# Wave configuration
@export var initial_wave_delay: float = 120.0  # 2 minutes before first wave
@export var wave_interval_base: float = 180.0  # 3 minutes between waves
@export var wave_interval_variance: float = 60.0  # +/- 1 minute randomness

# Difficulty scaling
var current_difficulty: float = 1.0
var difficulty_escalation_rate: float = 0.1  # Per wave
var max_difficulty: float = 3.0

# Wave tracking
var current_wave: int = 0
var wave_timer: float = 0.0
var wave_active: bool = false
var next_wave_time: float = 0.0

# Enemy positions (registered by enemy camp nodes)
var enemy_positions: Dictionary = {}  # id -> { node, type, strength, destroyed }
var next_position_id: int = 0

# Player strength assessment
var estimated_player_strength: float = 100.0
var player_firebase_position: Vector3 = Vector3.ZERO

# Assault planning
var assault_groups: Array = []
var preferred_attack_directions: Array[Vector3] = []

# Enemy unit pools (what the director can spawn)
var available_infantry: int = 50
var available_mortars: int = 3
var available_sappers: int = 5


func _ready() -> void:
	# Set initial wave time
	next_wave_time = initial_wave_delay
	wave_timer = 0.0


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	wave_timer += delta

	if not wave_active:
		_check_wave_trigger()
	else:
		_manage_active_assault()

	_update_player_strength_estimate()
	_manage_enemy_positions()


func _check_wave_trigger() -> void:
	if wave_timer >= next_wave_time:
		_launch_assault_wave()


func _launch_assault_wave() -> void:
	current_wave += 1
	wave_active = true

	# Calculate wave composition based on difficulty and remaining positions
	var wave_strength := _calculate_wave_strength()
	var attack_direction := _choose_attack_direction()

	# Spawn assault groups
	_spawn_assault_force(wave_strength, attack_direction)

	assault_wave_starting.emit(current_wave, attack_direction)
	print("AIDirector: Wave %d launched from direction %s" % [current_wave, attack_direction])


func _calculate_wave_strength() -> Dictionary:
	var base_infantry := 10 + (current_wave * 3)
	var strength := {
		"infantry": int(base_infantry * current_difficulty),
		"mortars": current_wave >= 3 and _has_mortar_positions(),
		"sappers": current_wave >= 5 and randf() < 0.3
	}

	# Reduce strength if enemy positions destroyed
	var position_modifier := _get_remaining_position_modifier()
	strength.infantry = int(strength.infantry * position_modifier)

	return strength


func _choose_attack_direction() -> Vector3:
	# Analyze player defenses to find weak spots
	var attack_angles: Array[float] = []

	# Default: random direction if no intel
	if preferred_attack_directions.is_empty():
		var angle := randf() * TAU
		return Vector3(cos(angle), 0, sin(angle))

	# Choose from known weak directions
	var idx: int = randi() % preferred_attack_directions.size()
	var weak_direction: Vector3 = preferred_attack_directions[idx]

	# Add some randomness
	var variance := randf_range(-0.5, 0.5)
	weak_direction = weak_direction.rotated(Vector3.UP, variance)

	return weak_direction.normalized()


func _spawn_assault_force(strength: Dictionary, direction: Vector3) -> void:
	# Calculate spawn position (off-map in the attack direction)
	var spawn_distance := 80.0
	var spawn_center := player_firebase_position - direction * spawn_distance

	# Create assault groups
	var infantry_count: int = strength.infantry
	var groups_count := ceili(infantry_count / 10.0)

	for i in groups_count:
		var group := {
			"size": mini(10, infantry_count),
			"spawn_pos": spawn_center + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10)),
			"target": player_firebase_position,
			"state": "advancing"
		}
		assault_groups.append(group)
		infantry_count -= group.size
		available_infantry -= group.size


func _manage_active_assault() -> void:
	# Check if assault is complete
	var active_groups := 0

	for group in assault_groups:
		if group.state != "destroyed" and group.state != "retreated":
			active_groups += 1

	if active_groups == 0:
		_end_assault_wave(false)  # Assault failed to take firebase


func _end_assault_wave(success: bool) -> void:
	wave_active = false
	assault_groups.clear()

	# Set next wave time
	var interval := wave_interval_base + randf_range(-wave_interval_variance, wave_interval_variance)
	next_wave_time = wave_timer + interval

	# Escalate difficulty
	current_difficulty = minf(current_difficulty + difficulty_escalation_rate, max_difficulty)
	difficulty_escalated.emit()

	assault_wave_ended.emit(current_wave, success)
	print("AIDirector: Wave %d ended. Next wave in %.0f seconds" % [current_wave, interval])


func _update_player_strength_estimate() -> void:
	# Estimate based on visible squads and structures
	var squad_strength: float = GameManager.player_squads.size() * 10.0
	var structure_strength: float = GameManager.structures.size() * 5.0
	var supply_strength: float = GameManager.supplies * 0.5

	estimated_player_strength = squad_strength + structure_strength + supply_strength


func _manage_enemy_positions() -> void:
	# Reinforce threatened positions
	for pos_id in enemy_positions:
		var pos: Dictionary = enemy_positions[pos_id]
		if pos.destroyed:
			continue

		# Check if position is under threat (player squads nearby)
		var under_threat := _is_position_threatened(pos)
		if under_threat and pos.strength < 20:
			_reinforce_position(pos_id)


func _is_position_threatened(position: Dictionary) -> bool:
	if not position.has("node") or not is_instance_valid(position.node):
		return false

	var pos: Vector3 = position.node.global_position

	for squad in GameManager.player_squads:
		if pos.distance_to(squad.global_position) < 50.0:
			return true

	return false


func _reinforce_position(pos_id: int) -> void:
	if available_infantry < 5:
		return

	var pos: Dictionary = enemy_positions[pos_id]
	pos.strength += 5
	available_infantry -= 5

	enemy_reinforced.emit(pos_id)


func _has_mortar_positions() -> bool:
	for pos_id in enemy_positions:
		var pos: Dictionary = enemy_positions[pos_id]
		if pos.type == "mortar" and not pos.destroyed:
			return true
	return false


func _get_remaining_position_modifier() -> float:
	var total := 0
	var remaining := 0

	for pos_id in enemy_positions:
		total += 1
		if not enemy_positions[pos_id].destroyed:
			remaining += 1

	if total == 0:
		return 1.0

	return float(remaining) / float(total)


# Public interface for enemy position registration

func register_enemy_position(node: Node3D, type: String, strength: int) -> int:
	var pos_id := next_position_id
	next_position_id += 1

	enemy_positions[pos_id] = {
		"node": node,
		"type": type,  # "camp", "mortar", "aa", "tunnel", "ammo"
		"strength": strength,
		"destroyed": false
	}

	return pos_id


func destroy_enemy_position(pos_id: int) -> void:
	if pos_id in enemy_positions:
		enemy_positions[pos_id].destroyed = true

		# Reduce available reinforcements
		var type: String = enemy_positions[pos_id].type
		match type:
			"camp":
				available_infantry = maxi(0, available_infantry - 20)
			"mortar":
				available_mortars = maxi(0, available_mortars - 1)


func set_firebase_position(pos: Vector3) -> void:
	player_firebase_position = pos


func report_weak_direction(direction: Vector3) -> void:
	## Enemy scouts report weak spots in player defenses
	if direction not in preferred_attack_directions:
		preferred_attack_directions.append(direction.normalized())

	# Keep only 4 most recent observations
	while preferred_attack_directions.size() > 4:
		preferred_attack_directions.pop_front()


func get_time_until_next_wave() -> float:
	if wave_active:
		return 0.0
	return max(0.0, next_wave_time - wave_timer)


func get_current_wave() -> int:
	return current_wave


func get_difficulty_level() -> float:
	return current_difficulty
