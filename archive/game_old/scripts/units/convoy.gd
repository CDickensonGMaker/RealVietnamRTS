extends CharacterBody3D
class_name Convoy
## Convoy - Ground supply vehicle
## Travels along roads from rear area to firebase, delivers supplies

signal convoy_arriving
signal convoy_arrived
signal supplies_delivered(amount: int)
signal convoy_ambushed
signal convoy_destroyed
signal escort_requested

enum ConvoyState { INBOUND, UNLOADING, OUTBOUND, UNDER_ATTACK, DESTROYED }

# Configuration
@export var supply_capacity: int = 150
@export var move_speed: float = 8.0
@export var unload_time: float = 20.0
@export var max_health: float = 80.0
@export var armor: float = 5.0

# State
var current_state: ConvoyState = ConvoyState.INBOUND
var current_health: float = 80.0
var supplies_carried: int = 150

# Navigation
var nav_agent: NavigationAgent3D
var spawn_position: Vector3 = Vector3.ZERO
var destination: Vector3 = Vector3.ZERO
var waypoints: Array[Vector3] = []
var current_waypoint_index: int = 0

# Combat
var under_fire_timer: float = 0.0
var escort_squad: Node3D = null

# Timers
var state_timer: float = 0.0


func _ready() -> void:
	add_to_group("convoys")
	add_to_group("player_units")
	current_health = max_health

	# Setup navigation
	nav_agent = NavigationAgent3D.new()
	nav_agent.path_desired_distance = 2.0
	nav_agent.target_desired_distance = 5.0
	nav_agent.avoidance_enabled = true
	add_child(nav_agent)


func _physics_process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	state_timer += delta
	under_fire_timer -= delta

	match current_state:
		ConvoyState.INBOUND:
			_process_inbound(delta)
		ConvoyState.UNLOADING:
			_process_unloading(delta)
		ConvoyState.OUTBOUND:
			_process_outbound(delta)
		ConvoyState.UNDER_ATTACK:
			_process_under_attack(delta)


func _process_inbound(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		# Arrived at destination
		current_state = ConvoyState.UNLOADING
		state_timer = 0.0
		convoy_arrived.emit()
		return

	# Move along path
	var next_pos := nav_agent.get_next_path_position()
	var direction := (next_pos - global_position).normalized()
	direction.y = 0

	velocity = direction * move_speed
	move_and_slide()

	# Face movement direction
	if direction.length() > 0.1:
		var target_rot := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rot, 3.0 * delta)


func _process_unloading(delta: float) -> void:
	if state_timer >= unload_time:
		# Deliver supplies
		GameManager.add_supplies(supplies_carried)
		supplies_delivered.emit(supplies_carried)
		supplies_carried = 0

		# Head back
		current_state = ConvoyState.OUTBOUND
		nav_agent.target_position = spawn_position


func _process_outbound(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		# Reached spawn point, despawn
		queue_free()
		return

	# Move along path
	var next_pos := nav_agent.get_next_path_position()
	var direction := (next_pos - global_position).normalized()
	direction.y = 0

	velocity = direction * move_speed
	move_and_slide()

	# Face movement direction
	if direction.length() > 0.1:
		var target_rot := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rot, 3.0 * delta)


func _process_under_attack(delta: float) -> void:
	# Stop moving while under attack
	velocity = Vector3.ZERO

	# Check if attack has subsided
	if under_fire_timer <= 0:
		# Resume previous course
		if supplies_carried > 0:
			current_state = ConvoyState.INBOUND
		else:
			current_state = ConvoyState.OUTBOUND


func take_damage(amount: float, attacker: Node = null) -> void:
	var actual_damage := maxf(0, amount - armor)
	current_health -= actual_damage

	under_fire_timer = 3.0  # Consider under fire for 3 seconds

	if current_state != ConvoyState.UNDER_ATTACK:
		current_state = ConvoyState.UNDER_ATTACK
		convoy_ambushed.emit()

		# Request escort if we don't have one
		if not is_instance_valid(escort_squad):
			escort_requested.emit()

	if current_health <= 0:
		_destroy()


func _destroy() -> void:
	current_state = ConvoyState.DESTROYED
	convoy_destroyed.emit()

	# Supplies lost
	supplies_carried = 0

	# Explosion effect
	_spawn_explosion()

	queue_free()


func _spawn_explosion() -> void:
	var explosion := CSGSphere3D.new()
	explosion.radius = 3.0
	explosion.global_position = global_position + Vector3(0, 1, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.5, 0)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.3, 0)
	mat.emission_energy_multiplier = 4.0
	explosion.material = mat

	get_tree().current_scene.add_child(explosion)

	var tween := create_tween()
	tween.tween_property(explosion, "radius", 5.0, 0.3)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tween.tween_callback(explosion.queue_free)


# Setup function called by SupplyDirector
func setup(spawn_pos: Vector3, target_pos: Vector3, supplies: int) -> void:
	spawn_position = spawn_pos
	destination = target_pos
	supplies_carried = supplies
	global_position = spawn_pos
	current_state = ConvoyState.INBOUND

	# Set navigation target
	await get_tree().process_frame
	nav_agent.target_position = destination


func assign_escort(squad: Node3D) -> void:
	escort_squad = squad
	if squad.has_method("set_standing_order"):
		# Set squad to escort mode
		pass


func get_health_percent() -> float:
	return current_health / max_health


func is_enemy() -> bool:
	return false


func select() -> void:
	var indicator: Node = get_node_or_null("SelectionIndicator")
	if indicator:
		indicator.visible = true


func deselect() -> void:
	var indicator: Node = get_node_or_null("SelectionIndicator")
	if indicator:
		indicator.visible = false
