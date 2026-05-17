extends CharacterBody3D
class_name EnemySquad
## EnemySquad - Base class for enemy unit AI
## VC/NVA infantry with jungle-focused tactics

signal squad_destroyed
signal target_spotted(target: Node3D)
signal retreating

# Squad configuration
@export var squad_type: String = "vc_infantry"  # vc_infantry, nva_regular, sapper, mortar_team
@export var squad_size: int = 8
@export var max_squad_size: int = 8

# Movement
@export var move_speed: float = 4.0
@export var stealth_speed: float = 2.0
@export var rotation_speed: float = 4.0

# Combat
@export var sight_range: float = 25.0
@export var attack_range: float = 20.0
@export var damage_per_second: float = 8.0
@export var accuracy: float = 0.6

# Health
var squad_health: float = 100.0
var morale: float = 100.0
var suppression: float = 0.0

# State
enum SquadState { IDLE, PATROLLING, ADVANCING, ATTACKING, FLANKING, RETREATING, INFILTRATING }
var current_state: SquadState = SquadState.IDLE

# Navigation
var nav_agent: NavigationAgent3D
var move_target: Vector3 = Vector3.ZERO
var assigned_target: Node3D = null  # Target from commander

# Patrol
var patrol_waypoints: Array[Vector3] = []
var current_waypoint_index: int = 0

# Combat
var current_target: Node3D = null
var enemies_in_sight: Array[Node3D] = []
var last_known_enemy_pos: Vector3 = Vector3.ZERO

# Jungle tactics
var prefer_cover: bool = true
var use_flanking: bool = true
var retreat_threshold: float = 30.0  # Morale threshold


func _ready() -> void:
	add_to_group("enemy_units")
	add_to_group("enemy")

	nav_agent = NavigationAgent3D.new()
	nav_agent.path_desired_distance = 1.5
	nav_agent.target_desired_distance = 2.0
	add_child(nav_agent)

	nav_agent.velocity_computed.connect(_on_velocity_computed)


func _physics_process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	_update_suppression(delta)
	_update_morale(delta)
	_scan_for_targets()

	match current_state:
		SquadState.IDLE:
			_process_idle(delta)
		SquadState.PATROLLING:
			_process_patrol(delta)
		SquadState.ADVANCING:
			_process_advance(delta)
		SquadState.ATTACKING:
			_process_attack(delta)
		SquadState.FLANKING:
			_process_flank(delta)
		SquadState.RETREATING:
			_process_retreat(delta)
		SquadState.INFILTRATING:
			_process_infiltrate(delta)


func _update_suppression(delta: float) -> void:
	suppression = max(0, suppression - 8 * delta)


func _update_morale(delta: float) -> void:
	# Morale recovers slowly when not in combat
	if enemies_in_sight.is_empty():
		morale = min(100, morale + 2 * delta)

	# Check retreat threshold
	if morale < retreat_threshold and current_state != SquadState.RETREATING:
		_start_retreat()


func _scan_for_targets() -> void:
	enemies_in_sight.clear()

	var potential_targets: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("player_units"):
		var unit := node as Node3D
		if unit:
			potential_targets.append(unit)
	for structure: Node3D in GameManager.structures:
		if is_instance_valid(structure):
			potential_targets.append(structure)

	for target: Node3D in potential_targets:
		if not is_instance_valid(target):
			continue

		var distance := global_position.distance_to(target.global_position)

		# Sight range affected by suppression
		var effective_sight := sight_range * (1.0 - suppression / 200.0)
		if distance > effective_sight:
			continue

		# Line of sight check
		if _has_line_of_sight(target):
			enemies_in_sight.append(target)
			target_spotted.emit(target)


func _has_line_of_sight(target: Node3D) -> bool:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP,
		target.global_position + Vector3.UP
	)
	query.exclude = [self]

	var result := space_state.intersect_ray(query)
	return result.is_empty() or result.collider == target


func _process_idle(delta: float) -> void:
	# React to spotted enemies
	if not enemies_in_sight.is_empty():
		current_target = _get_priority_target()
		current_state = SquadState.ATTACKING


func _process_patrol(delta: float) -> void:
	if patrol_waypoints.is_empty():
		current_state = SquadState.IDLE
		return

	# Check for enemies
	if not enemies_in_sight.is_empty():
		current_target = _get_priority_target()
		current_state = SquadState.ATTACKING
		return

	# Move to waypoint
	if nav_agent.is_navigation_finished():
		current_waypoint_index = (current_waypoint_index + 1) % patrol_waypoints.size()
		nav_agent.target_position = patrol_waypoints[current_waypoint_index]
	else:
		_move_toward_target(delta)


func _process_advance(delta: float) -> void:
	# Advance toward assigned target
	if assigned_target and is_instance_valid(assigned_target):
		var distance := global_position.distance_to(assigned_target.global_position)

		if distance < attack_range:
			current_target = assigned_target
			current_state = SquadState.ATTACKING
		else:
			nav_agent.target_position = assigned_target.global_position
			_move_toward_target(delta)
	else:
		current_state = SquadState.IDLE


func _process_attack(delta: float) -> void:
	if not current_target or not is_instance_valid(current_target):
		current_target = _get_priority_target()
		if not current_target:
			current_state = SquadState.IDLE
			return

	var distance := global_position.distance_to(current_target.global_position)

	# Face target
	var direction := (current_target.global_position - global_position).normalized()
	var target_rotation := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)

	if distance > attack_range:
		# Move closer
		nav_agent.target_position = current_target.global_position
		_move_toward_target(delta)
	else:
		# Fire
		_fire_at_target(delta)

		# Consider flanking if pinned
		if suppression > 50 and use_flanking:
			_attempt_flank()


func _fire_at_target(delta: float) -> void:
	if not current_target or suppression > 80:
		return

	var hit_chance := accuracy * (1.0 - suppression / 150.0)

	if randf() < hit_chance:
		var damage := damage_per_second * delta
		if current_target.has_method("take_damage"):
			current_target.take_damage(damage)


func _process_flank(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		# Resume attack from new position
		current_state = SquadState.ATTACKING
		return

	_move_toward_target(delta, stealth_speed)


func _process_retreat(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		current_state = SquadState.IDLE
		morale = 50  # Partial morale recovery on reaching safety
		retreating.emit()
		return

	_move_toward_target(delta, move_speed * 1.2)


func _process_infiltrate(delta: float) -> void:
	# Sapper behavior - move slowly, avoid detection
	if nav_agent.is_navigation_finished():
		# Reached target - plant charges, etc.
		current_state = SquadState.IDLE
		return

	_move_toward_target(delta, stealth_speed)


func _move_toward_target(delta: float, speed: float = -1.0) -> void:
	if nav_agent.is_navigation_finished():
		return

	if speed < 0:
		speed = move_speed

	var next_pos := nav_agent.get_next_path_position()
	var direction := (next_pos - global_position).normalized()

	# Face movement direction
	if direction.length() > 0.1:
		var target_rotation := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)

	# Slow down when suppressed
	var speed_modifier := 1.0 - (suppression / 200.0)
	velocity = direction * speed * speed_modifier
	nav_agent.set_velocity(velocity)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()


func _get_priority_target() -> Node3D:
	if enemies_in_sight.is_empty():
		return null

	# Priority: closest enemy
	var closest: Node3D = null
	var closest_dist := INF

	for enemy in enemies_in_sight:
		var dist := global_position.distance_to(enemy.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = enemy

	return closest


func _attempt_flank() -> void:
	if not current_target:
		return

	# Calculate flanking position
	var to_target := current_target.global_position - global_position
	var flank_direction := to_target.rotated(Vector3.UP, PI / 2).normalized()

	# Randomly choose left or right flank
	if randf() < 0.5:
		flank_direction = -flank_direction

	var flank_position := global_position + flank_direction * 15.0 + to_target.normalized() * 10.0

	nav_agent.target_position = flank_position
	current_state = SquadState.FLANKING


func _start_retreat() -> void:
	# Find retreat point (away from enemies)
	var retreat_direction := Vector3.ZERO

	for enemy in enemies_in_sight:
		retreat_direction -= (enemy.global_position - global_position).normalized()

	if retreat_direction.length() < 0.1:
		retreat_direction = -global_position.direction_to(Vector3(100, 0, 100))

	var retreat_pos := global_position + retreat_direction.normalized() * 30.0
	nav_agent.target_position = retreat_pos
	current_state = SquadState.RETREATING


# Public interface

func set_patrol_route(waypoints: Array[Vector3]) -> void:
	patrol_waypoints = waypoints
	current_waypoint_index = 0
	current_state = SquadState.PATROLLING
	if not patrol_waypoints.is_empty():
		nav_agent.target_position = patrol_waypoints[0]


func advance_to(target: Node3D) -> void:
	assigned_target = target
	current_state = SquadState.ADVANCING


func infiltrate_to(position: Vector3) -> void:
	nav_agent.target_position = position
	current_state = SquadState.INFILTRATING


func take_damage(amount: float) -> void:
	squad_health -= amount

	# Suppression from incoming fire
	suppression = min(100, suppression + amount * 0.8)

	# Morale damage
	morale -= amount * 0.3

	if squad_health <= 0:
		_squad_casualty()


func _squad_casualty() -> void:
	squad_size -= 1
	squad_health = 100.0

	# Heavy morale hit from casualties
	morale -= 15

	if squad_size <= 0:
		squad_destroyed.emit()
		queue_free()


func is_enemy() -> bool:
	return true


func get_health_percent() -> float:
	return float(squad_size) / float(max_squad_size)


func apply_slow(factor: float) -> void:
	## Apply movement slow debuff
	move_speed *= factor


func remove_slow() -> void:
	## Remove movement slow debuff
	move_speed = 4.0  # Default enemy speed
