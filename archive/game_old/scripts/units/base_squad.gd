extends CharacterBody3D
class_name BaseSquad
## BaseSquad - Base class for all squad types
## Handles movement, combat, morale, and standing orders

signal squad_selected
signal squad_deselected
signal contact_spotted(position: Vector3, contact_type: String)
signal taking_fire
signal squad_destroyed
signal ammo_low

# Squad configuration
@export var squad_name: String = "Rifle Squad"
@export var squad_size: int = 10
@export var max_squad_size: int = 10
@export var supply_cost: int = 20

# Movement
@export var move_speed: float = 5.0
@export var run_speed: float = 8.0
@export var rotation_speed: float = 5.0

# Combat stats
@export var sight_range: float = 30.0
@export var attack_range: float = 25.0
@export var damage_per_second: float = 10.0
@export var accuracy: float = 0.7

# Ammo
@export var max_ammo: int = 100
var current_ammo: int = 100

# Health and morale
var squad_health: float = 100.0
var morale: float = 100.0
var suppression: float = 0.0  # 0-100, affects accuracy and movement

# State
enum SquadState { IDLE, MOVING, ATTACKING, SUPPRESSED, BUILDING, GARRISONED }
var current_state: SquadState = SquadState.IDLE

# Standing orders
enum StandingOrder { GUARD, PATROL, AGGRESSIVE, RECON, ESCORT }
var standing_order: StandingOrder = StandingOrder.GUARD

# Navigation
var nav_agent: NavigationAgent3D
var move_target: Vector3 = Vector3.ZERO
var waypoint_queue: Array[Vector3] = []
var patrol_waypoints: Array[Vector3] = []
var current_patrol_index: int = 0

# Combat
var current_target: Node3D = null
var enemies_in_sight: Array[Node3D] = []

# Selection visual
var is_selected: bool = false
@onready var selection_indicator: Node3D = $SelectionIndicator if has_node("SelectionIndicator") else null


func _ready() -> void:
	add_to_group("squads")
	add_to_group("player_units")

	# Setup navigation agent
	nav_agent = NavigationAgent3D.new()
	nav_agent.path_desired_distance = 1.0
	nav_agent.target_desired_distance = 2.0
	add_child(nav_agent)

	nav_agent.velocity_computed.connect(_on_velocity_computed)

	# Register with game manager
	GameManager.register_squad(self)


func _exit_tree() -> void:
	GameManager.unregister_squad(self)


func _physics_process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	_update_suppression(delta)
	_update_state(delta)
	_scan_for_enemies()

	match current_state:
		SquadState.MOVING:
			_process_movement(delta)
		SquadState.ATTACKING:
			_process_combat(delta)
		SquadState.IDLE:
			_process_idle(delta)


func _update_suppression(delta: float) -> void:
	# Suppression decays over time when not taking fire
	suppression = max(0, suppression - 10 * delta)

	# Apply suppression effects
	if suppression > 80:
		current_state = SquadState.SUPPRESSED


func _update_state(delta: float) -> void:
	# Recover from suppression
	if current_state == SquadState.SUPPRESSED and suppression < 50:
		current_state = SquadState.IDLE


func _process_movement(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		_on_destination_reached()
		return

	var next_pos := nav_agent.get_next_path_position()
	var direction := (next_pos - global_position).normalized()

	# Face movement direction
	if direction.length() > 0.1:
		var target_rotation := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)

	# Move slower when suppressed
	var speed_modifier := 1.0 - (suppression / 200.0)
	var final_speed := move_speed * speed_modifier

	velocity = direction * final_speed
	nav_agent.set_velocity(velocity)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()


func _process_combat(delta: float) -> void:
	if not is_instance_valid(current_target):
		current_target = null
		current_state = SquadState.IDLE
		return

	# Face target
	var direction := (current_target.global_position - global_position).normalized()
	var target_rotation := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)

	# Check range
	var distance := global_position.distance_to(current_target.global_position)
	if distance > attack_range:
		# Move closer
		move_to(current_target.global_position)
		return

	# Fire
	if current_ammo > 0:
		_fire_at_target(delta)
	else:
		ammo_low.emit()


func _fire_at_target(delta: float) -> void:
	if not current_target or not is_instance_valid(current_target):
		return

	# Calculate hit chance
	var hit_chance := accuracy
	hit_chance *= (1.0 - suppression / 150.0)  # Suppression reduces accuracy

	# Apply damage
	if randf() < hit_chance:
		var damage := damage_per_second * delta
		if current_target.has_method("take_damage"):
			current_target.take_damage(damage)

	# Consume ammo
	current_ammo -= 1
	if current_ammo <= max_ammo * 0.2:
		ammo_low.emit()


func _process_idle(delta: float) -> void:
	# Execute standing orders
	match standing_order:
		StandingOrder.GUARD:
			_guard_behavior()
		StandingOrder.PATROL:
			_patrol_behavior()
		StandingOrder.AGGRESSIVE:
			_aggressive_behavior()


func _guard_behavior() -> void:
	# Attack enemies in range
	if not enemies_in_sight.is_empty():
		attack(enemies_in_sight[0])


func _patrol_behavior() -> void:
	if patrol_waypoints.is_empty():
		return

	if current_state == SquadState.IDLE:
		# Move to next waypoint
		var next_wp := patrol_waypoints[current_patrol_index]
		move_to(next_wp)


func _aggressive_behavior() -> void:
	# Pursue enemies
	if not enemies_in_sight.is_empty():
		var closest := _get_closest_enemy()
		attack(closest)


func _scan_for_enemies() -> void:
	enemies_in_sight.clear()

	# Get all enemy units in sight range
	var space_state := get_world_3d().direct_space_state

	for enemy_node: Node in get_tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(enemy_node):
			continue

		var enemy := enemy_node as Node3D
		if not enemy:
			continue

		var distance := global_position.distance_to(enemy.global_position)
		if distance > sight_range:
			continue

		# Raycast to check line of sight
		var query := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP,
			enemy.global_position + Vector3.UP
		)
		query.exclude = [self]

		var result := space_state.intersect_ray(query)
		if result and result.collider == enemy:
			enemies_in_sight.append(enemy)
			# Report contact to intel director
			contact_spotted.emit(enemy.global_position, "infantry")
			IntelDirector.report_contact(enemy.global_position, "infantry")


func _get_closest_enemy() -> Node3D:
	var closest: Node3D = null
	var closest_dist := INF

	for enemy in enemies_in_sight:
		var dist := global_position.distance_to(enemy.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = enemy

	return closest


func _on_destination_reached() -> void:
	if waypoint_queue.is_empty():
		current_state = SquadState.IDLE

		# Patrol looping
		if standing_order == StandingOrder.PATROL and not patrol_waypoints.is_empty():
			current_patrol_index = (current_patrol_index + 1) % patrol_waypoints.size()
			await get_tree().create_timer(1.0).timeout
			move_to(patrol_waypoints[current_patrol_index])
	else:
		# Move to next waypoint in queue
		var next: Vector3 = waypoint_queue.pop_front()
		_navigate_to(next)


func _navigate_to(target: Vector3) -> void:
	move_target = target
	nav_agent.target_position = target
	current_state = SquadState.MOVING


# Public interface

func move_to(target: Vector3, queue: bool = false) -> void:
	## Command squad to move to target position
	if queue:
		waypoint_queue.append(target)
	else:
		waypoint_queue.clear()
		_navigate_to(target)


func attack(target: Node3D) -> void:
	## Command squad to attack target
	if not is_instance_valid(target):
		return

	current_target = target
	current_state = SquadState.ATTACKING


func set_patrol_route(waypoints: Array[Vector3]) -> void:
	## Set looping patrol route
	patrol_waypoints = waypoints
	standing_order = StandingOrder.PATROL
	if not patrol_waypoints.is_empty():
		current_patrol_index = 0
		move_to(patrol_waypoints[0])


func set_standing_order(order: StandingOrder) -> void:
	standing_order = order


func take_damage(amount: float) -> void:
	squad_health -= amount
	taking_fire.emit()

	# Suppression from incoming fire
	suppression = min(100, suppression + amount * 0.5)

	# Casualties
	if squad_health <= 0:
		_squad_casualty()


func _squad_casualty() -> void:
	squad_size -= 1
	squad_health = 100.0

	if squad_size <= 0:
		squad_destroyed.emit()
		queue_free()


func resupply(amount: int) -> void:
	current_ammo = min(max_ammo, current_ammo + amount)


func select() -> void:
	is_selected = true
	if selection_indicator:
		selection_indicator.visible = true
	squad_selected.emit()


func deselect() -> void:
	is_selected = false
	if selection_indicator:
		selection_indicator.visible = false
	squad_deselected.emit()


func is_enemy() -> bool:
	return false


func get_ammo_percent() -> float:
	return float(current_ammo) / float(max_ammo)


func get_health_percent() -> float:
	return float(squad_size) / float(max_squad_size)


func heal(amount: float) -> void:
	## Heal squad health (not casualties, those need reinforcements)
	squad_health = min(100.0, squad_health + amount)


func add_ammo(amount: float) -> void:
	## Add ammo to squad
	current_ammo = mini(max_ammo, current_ammo + int(amount))


func apply_slow(factor: float) -> void:
	## Apply movement slow debuff (factor = 0.3 means 30% speed)
	move_speed *= factor
	run_speed *= factor


func remove_slow() -> void:
	## Remove movement slow debuff by restoring default speeds
	# Note: In a more robust system, we'd track the original values
	move_speed = 5.0  # Default
	run_speed = 8.0   # Default
