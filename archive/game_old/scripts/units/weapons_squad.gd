extends BaseSquad
class_name WeaponsSquad
## WeaponsSquad - Heavy weapons team with MG and mortar
## Provides fire support, excels at suppression

signal mg_firing(target: Node3D)
signal mortar_firing(target_position: Vector3)
signal setting_up
signal packed_up

# Weapons Squad specific
@export var mg_range: float = 45.0
@export var mg_damage: float = 12.0
@export var mg_suppression: float = 25.0
@export var mortar_range: float = 60.0
@export var mortar_min_range: float = 20.0
@export var mortar_damage: float = 35.0
@export var setup_time: float = 3.0
@export var pack_time: float = 2.0

# State
var is_deployed: bool = false
var setup_progress: float = 0.0
var mortar_cooldown: float = 0.0
var mortar_reload_time: float = 5.0

# Mortar target
var mortar_target_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	super._ready()
	squad_name = "Weapons Squad"
	squad_size = 8
	max_squad_size = 8
	supply_cost = 35

	# Weapons squad stats
	move_speed = 4.0  # Slower due to heavy equipment
	sight_range = 35.0
	attack_range = 40.0  # MG range
	damage_per_second = 12.0  # MG damage
	accuracy = 0.6


func _physics_process(delta: float) -> void:
	# Handle deployment
	if is_deployed:
		mortar_cooldown -= delta

	super._physics_process(delta)


func _fire_at_target(delta: float) -> void:
	if not current_target or not is_instance_valid(current_target):
		return

	# Must be deployed to fire effectively
	if not is_deployed:
		# Try to deploy
		_start_deploy()
		return

	# MG fire with enhanced suppression
	var hit_chance := accuracy * (1.0 - suppression / 150.0)

	if randf() < hit_chance:
		var damage := mg_damage * delta
		if current_target.has_method("take_damage"):
			current_target.take_damage(damage)

		mg_firing.emit(current_target)

	# Apply heavy suppression
	if current_target.get("suppression") != null:
		current_target.suppression = min(100, current_target.suppression + mg_suppression * delta)

	current_ammo -= 1
	if current_ammo <= max_ammo * 0.2:
		ammo_low.emit()


func _start_deploy() -> void:
	if is_deployed:
		return

	current_state = SquadState.BUILDING  # Reuse building state for setup
	setup_progress = 0.0
	setting_up.emit()


func _process_deploy(delta: float) -> void:
	setup_progress += delta

	if setup_progress >= setup_time:
		is_deployed = true
		current_state = SquadState.IDLE


func move_to(target: Vector3, queue: bool = false) -> void:
	# Must pack up before moving
	if is_deployed:
		_pack_up()
		# Queue the move for after packing
		await get_tree().create_timer(pack_time).timeout

	super.move_to(target, queue)


func _pack_up() -> void:
	is_deployed = false
	packed_up.emit()


func fire_mortar(target_position: Vector3) -> bool:
	## Manually fire mortar at a position
	if not is_deployed:
		push_warning("WeaponsSquad: Must be deployed to fire mortar")
		return false

	var distance := global_position.distance_to(target_position)
	if distance < mortar_min_range or distance > mortar_range:
		push_warning("WeaponsSquad: Target out of mortar range")
		return false

	if mortar_cooldown > 0:
		push_warning("WeaponsSquad: Mortar reloading")
		return false

	if current_ammo < 5:
		push_warning("WeaponsSquad: Insufficient ammo")
		return false

	# Fire mortar
	mortar_target_position = target_position
	mortar_cooldown = mortar_reload_time
	current_ammo -= 5

	mortar_firing.emit(target_position)
	_apply_mortar_damage(target_position)

	return true


func _apply_mortar_damage(impact_pos: Vector3) -> void:
	var splash_radius := 5.0

	for unit_node: Node in get_tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(unit_node):
			continue

		var unit := unit_node as Node3D
		if not unit:
			continue

		var distance := impact_pos.distance_to(unit.global_position)
		if distance <= splash_radius:
			var damage_mult := 1.0 - (distance / splash_radius)
			var dmg := mortar_damage * damage_mult

			if unit.has_method("take_damage"):
				unit.call("take_damage", dmg)


func get_mortar_cooldown() -> float:
	return mortar_cooldown


func can_fire_mortar() -> bool:
	return is_deployed and mortar_cooldown <= 0 and current_ammo >= 5
