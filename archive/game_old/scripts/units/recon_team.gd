extends BaseSquad
class_name ReconTeam
## ReconTeam - Stealth scouts with extended sight range
## Observe and report, avoid engagement when possible

signal enemy_position_marked(position: Vector3, contact_type: String)
signal extraction_requested

# Recon-specific stats
@export var stealth_modifier: float = 0.5  # Harder to detect
@export var detection_range_bonus: float = 20.0

# State
var is_hidden: bool = false
var observing_target: Node3D = null
var observation_time: float = 0.0
var observation_threshold: float = 3.0  # Seconds to fully identify target


func _ready() -> void:
	super._ready()
	squad_name = "Recon Team"
	squad_size = 4
	max_squad_size = 4
	supply_cost = 15

	# Recon stats
	sight_range = 50.0
	move_speed = 6.0
	damage_per_second = 5.0  # Light weapons
	accuracy = 0.6

	# Default to recon standing order
	standing_order = StandingOrder.RECON


func _physics_process(delta: float) -> void:
	# Update sight range with bonus
	var effective_sight := sight_range + detection_range_bonus

	# Custom enemy scan with extended range
	_scan_for_enemies_extended(effective_sight)

	# Process observation
	if observing_target and is_instance_valid(observing_target):
		_process_observation(delta)

	# Parent processing
	super._physics_process(delta)


func _scan_for_enemies_extended(scan_range: float) -> void:
	var space_state := get_world_3d().direct_space_state

	for enemy_node: Node in get_tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(enemy_node):
			continue

		var enemy := enemy_node as Node3D
		if not enemy:
			continue

		var distance := global_position.distance_to(enemy.global_position)
		if distance > scan_range:
			continue

		# Recon teams can spot through light concealment
		if _has_line_of_sight_recon(enemy):
			if enemy not in enemies_in_sight:
				enemies_in_sight.append(enemy)

				# Auto-observe new contacts
				if not observing_target:
					observing_target = enemy
					observation_time = 0.0


func _has_line_of_sight_recon(target: Node3D) -> bool:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 1.5,
		target.global_position + Vector3.UP
	)
	query.exclude = [self]
	query.collision_mask = 1 | 4  # Terrain and structures only (ignore units for stealth LOS)

	var result := space_state.intersect_ray(query)
	return result.is_empty()


func _process_observation(delta: float) -> void:
	if not observing_target or not is_instance_valid(observing_target):
		observing_target = null
		observation_time = 0.0
		return

	var distance := global_position.distance_to(observing_target.global_position)

	# Must maintain line of sight
	if not _has_line_of_sight_recon(observing_target):
		observation_time = max(0, observation_time - delta)
		return

	observation_time += delta

	# Full observation - report detailed intel
	if observation_time >= observation_threshold:
		_report_contact(observing_target)
		observing_target = null
		observation_time = 0.0


func _report_contact(target: Node3D) -> void:
	var contact_type := "infantry"

	# Determine contact type from target
	if target.has_method("get") and target.get("squad_type"):
		contact_type = target.squad_type
	elif target.is_in_group("structures"):
		contact_type = "structure"

	# Report to intel director
	IntelDirector.report_contact(target.global_position, contact_type)
	enemy_position_marked.emit(target.global_position, contact_type)


func _guard_behavior() -> void:
	# Recon teams observe rather than engage
	if not enemies_in_sight.is_empty() and not observing_target:
		observing_target = enemies_in_sight[0]
		observation_time = 0.0


func _process_idle(delta: float) -> void:
	# Override parent - recon prefers not to engage
	match standing_order:
		StandingOrder.GUARD:
			_guard_behavior()
		StandingOrder.PATROL:
			_patrol_behavior()
		StandingOrder.RECON:
			_recon_behavior()
		StandingOrder.AGGRESSIVE:
			# Even on aggressive, be cautious
			if not enemies_in_sight.is_empty():
				var closest := _get_closest_enemy()
				if closest:
					# Only engage if clearly outnumber or have advantage
					attack(closest)


func _recon_behavior() -> void:
	# Move to waypoints, observe contacts, avoid engagement
	if not patrol_waypoints.is_empty():
		if current_state == SquadState.IDLE:
			var next_wp := patrol_waypoints[current_patrol_index]
			move_to(next_wp)

	# If spotted enemies, observe but don't engage
	if not enemies_in_sight.is_empty() and not observing_target:
		observing_target = enemies_in_sight[0]
		observation_time = 0.0


func take_damage(amount: float) -> void:
	super.take_damage(amount)

	# Recon teams are fragile - consider extraction
	if squad_size <= 2 or morale < 40:
		extraction_requested.emit()
		_attempt_break_contact()


func _attempt_break_contact() -> void:
	# Move away from enemies
	var escape_direction := Vector3.ZERO

	for enemy in enemies_in_sight:
		if is_instance_valid(enemy):
			escape_direction -= (enemy.global_position - global_position).normalized()

	if escape_direction.length() > 0.1:
		escape_direction = escape_direction.normalized()
		var escape_pos := global_position + escape_direction * 30.0
		move_to(escape_pos)


# Stealth detection - used by enemy AI
func get_detection_modifier() -> float:
	var modifier := stealth_modifier

	# More hidden when stationary
	if current_state == SquadState.IDLE:
		modifier *= 0.5

	# Less hidden when firing
	if current_state == SquadState.ATTACKING:
		modifier *= 3.0

	return modifier


func request_fire_mission(target_position: Vector3) -> void:
	## Call in mortar/artillery fire on observed position
	# This would interface with the mortar system
	print("Recon requesting fire mission at: ", target_position)
