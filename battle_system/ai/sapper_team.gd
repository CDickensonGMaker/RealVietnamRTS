extends Node3D
class_name SapperTeam

## NVA/VC Sapper Team - Elite assault engineers
## Specialize in breaching perimeters, destroying structures, and planting explosives

signal perimeter_breached(position: Vector3)
signal structure_destroyed(structure: Node3D)
signal explosive_planted(position: Vector3, fuse_time: float)
signal sapper_died(sapper: SapperTeam)
signal detected(by_unit: Node3D)

const Squad = preload("res://battle_system/nodes/squad.gd")

enum SapperState { INFILTRATING, BREACHING, PLANTING, ATTACKING, RETREATING, DEAD }
enum TargetType { WIRE, BUNKER, ARTILLERY, AMMO_DUMP, HELICOPTER, ANY_STRUCTURE }

## Configuration
@export var team_size: int = 6
@export var stealth_rating: float = 0.8  # Harder to detect
@export var breach_time: float = 5.0     # Time to cut wire
@export var plant_time: float = 8.0      # Time to plant satchel charge
@export var explosive_damage: float = 200.0
@export var move_speed: float = 4.0

## State
var state: SapperState = SapperState.INFILTRATING
var current_health: float = 100.0
var max_health: float = 100.0
var current_target: Node3D = null
var target_position: Vector3 = Vector3.ZERO
var target_type: TargetType = TargetType.ANY_STRUCTURE
var _action_timer: float = 0.0
var _detection_check_timer: float = 0.0
var _members_alive: int = 6
var _satchel_charges: int = 3
var _velocity: Vector3 = Vector3.ZERO
var velocity: Vector3:
	get: return _velocity

## Visual
var _mesh: MeshInstance3D = null


func _ready() -> void:
	add_to_group("sapper_teams")
	add_to_group("enemy_units")

	_members_alive = team_size
	current_health = float(team_size) * 15.0
	max_health = current_health

	_create_visual()

	print("[SapperTeam] Initialized with %d members" % team_size)


func _create_visual() -> void:
	"""Create sapper team visual"""
	_mesh = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.4
	_mesh.mesh = capsule

	# Dark uniform (sappers operate at night)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.1)
	_mesh.material_override = mat
	_mesh.position.y = 0.7

	add_child(_mesh)

	# Collision
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.4
	collision.shape = shape
	collision.position.y = 0.7
	add_child(collision)


func _process(delta: float) -> void:
	if state == SapperState.DEAD:
		return

	# Detection checks
	_detection_check_timer += delta
	if _detection_check_timer >= 1.0:
		_detection_check_timer = 0.0
		_check_detection()

	# State processing
	match state:
		SapperState.INFILTRATING:
			_process_infiltrating(delta)
		SapperState.BREACHING:
			_process_breaching(delta)
		SapperState.PLANTING:
			_process_planting(delta)
		SapperState.ATTACKING:
			_process_attacking(delta)
		SapperState.RETREATING:
			_process_retreating(delta)


func _process_infiltrating(delta: float) -> void:
	"""Move toward target while avoiding detection"""
	if target_position == Vector3.ZERO:
		return

	var direction: Vector3 = (target_position - global_position).normalized()
	var distance: float = global_position.distance_to(target_position)

	if distance > 2.0:
		# Move at reduced speed for stealth
		_velocity = direction * move_speed * 0.7
		global_position += _velocity * delta
	else:
		# Arrived at target
		_velocity = Vector3.ZERO
		_determine_action()


func _process_breaching(delta: float) -> void:
	"""Cut through wire obstacle"""
	_action_timer += delta

	if _action_timer >= breach_time:
		_action_timer = 0.0
		perimeter_breached.emit(global_position)

		# Destroy the wire if it's our target
		if is_instance_valid(current_target) and current_target.is_in_group("wire_obstacles"):
			if current_target.has_method("destroy"):
				current_target.destroy()
			else:
				current_target.queue_free()

		print("[SapperTeam] Perimeter breached at %s" % global_position)

		# Find next target
		_find_next_target()


func _process_planting(delta: float) -> void:
	"""Plant explosive charge"""
	_action_timer += delta

	if _action_timer >= plant_time:
		_action_timer = 0.0

		if _satchel_charges > 0:
			_satchel_charges -= 1
			_detonate_charge()

		# Find next target or retreat
		if _satchel_charges > 0:
			_find_next_target()
		else:
			state = SapperState.RETREATING


func _process_attacking(delta: float) -> void:
	"""Direct combat (last resort)"""
	if not is_instance_valid(current_target):
		_find_next_target()
		return

	var distance: float = global_position.distance_to(current_target.global_position)

	if distance > 5.0:
		# Move toward target
		var direction: Vector3 = (current_target.global_position - global_position).normalized()
		_velocity = direction * move_speed
		global_position += _velocity * delta
	else:
		# Attack
		_velocity = Vector3.ZERO
		if current_target.has_method("take_damage"):
			current_target.take_damage(10.0, self)


func _process_retreating(delta: float) -> void:
	"""Retreat after mission or when detected"""
	# Move away from firebase center
	var retreat_direction: Vector3 = global_position.normalized()
	if retreat_direction.length_squared() < 0.1:
		retreat_direction = Vector3(1, 0, 0)

	_velocity = retreat_direction * move_speed
	global_position += _velocity * delta

	# After moving far enough, despawn
	if global_position.length() > 100.0:
		queue_free()


func _determine_action() -> void:
	"""Determine what action to take at current position"""
	# Check if at wire obstacle
	var nearby: Array[Node] = _get_nearby_targets(5.0)

	for node in nearby:
		if node.is_in_group("wire_obstacles"):
			current_target = node
			state = SapperState.BREACHING
			_action_timer = 0.0
			print("[SapperTeam] Breaching wire obstacle")
			return

		if node.is_in_group("buildings") or node.is_in_group("firebase_buildings"):
			current_target = node
			state = SapperState.PLANTING
			_action_timer = 0.0
			print("[SapperTeam] Planting charge on %s" % node.name)
			return

	# No valid target, continue infiltrating or find new target
	_find_next_target()


func _find_next_target() -> void:
	"""Find the next priority target"""
	var targets: Array[Node] = []

	# Prioritize based on target type
	match target_type:
		TargetType.WIRE:
			targets = get_tree().get_nodes_in_group("wire_obstacles").duplicate()
		TargetType.BUNKER:
			targets = get_tree().get_nodes_in_group("bunkers").duplicate()
		TargetType.ARTILLERY:
			targets = get_tree().get_nodes_in_group("artillery").duplicate()
		TargetType.AMMO_DUMP:
			targets = get_tree().get_nodes_in_group("ammo_bunkers").duplicate()
		TargetType.HELICOPTER:
			targets = get_tree().get_nodes_in_group("helicopters").duplicate()
		TargetType.ANY_STRUCTURE:
			targets = get_tree().get_nodes_in_group("buildings").duplicate()
			targets.append_array(get_tree().get_nodes_in_group("firebase_buildings"))

	# Filter for player-owned and find nearest
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for target in targets:
		if not is_instance_valid(target):
			continue
		if not target.is_in_group("player_units") and not target.is_in_group("player_buildings"):
			# Check if it's a player structure
			if target.has_method("get") and target.get("faction"):
				if target.faction != GameEnums.Faction.US_ARMY:
					continue

		var dist: float = global_position.distance_to(target.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = target

	if nearest:
		current_target = nearest
		target_position = nearest.global_position
		state = SapperState.INFILTRATING
	else:
		# No targets, retreat
		state = SapperState.RETREATING


func _detonate_charge() -> void:
	"""Detonate planted satchel charge"""
	explosive_planted.emit(global_position, 3.0)

	# Delayed explosion
	var timer := get_tree().create_timer(3.0)
	var explosion_pos: Vector3 = global_position
	var explosion_target: Node3D = current_target

	timer.timeout.connect(func():
		# Apply damage to target
		if is_instance_valid(explosion_target):
			if explosion_target.has_method("take_damage"):
				explosion_target.take_damage(explosive_damage, self)

			# Check if destroyed
			if explosion_target.has_method("get") and explosion_target.get("current_health"):
				if explosion_target.current_health <= 0:
					structure_destroyed.emit(explosion_target)

		# Area damage
		_apply_explosion_damage(explosion_pos)

		# Visual/audio
		if BattleSignals:
			BattleSignals.projectile_impact.emit(explosion_pos, GameEnums.DamageType.EXPLOSIVE)

		print("[SapperTeam] Satchel charge detonated at %s" % explosion_pos)
	)


func _apply_explosion_damage(position: Vector3) -> void:
	"""Apply area damage from explosion"""
	var radius: float = 10.0
	var units: Array[Node] = get_tree().get_nodes_in_group("player_units")

	for unit in units:
		if not is_instance_valid(unit):
			continue

		var dist: float = position.distance_to(unit.global_position)
		if dist <= radius:
			var falloff: float = 1.0 - (dist / radius)
			var damage: float = explosive_damage * 0.5 * falloff

			if unit.has_method("take_damage"):
				unit.take_damage(damage, self)


func _get_nearby_targets(radius: float) -> Array[Node]:
	"""Get all valid targets within radius"""
	var result: Array[Node] = []

	var all_targets: Array[Node] = []
	all_targets.append_array(get_tree().get_nodes_in_group("wire_obstacles"))
	all_targets.append_array(get_tree().get_nodes_in_group("buildings"))
	all_targets.append_array(get_tree().get_nodes_in_group("firebase_buildings"))

	for target in all_targets:
		if is_instance_valid(target):
			var dist: float = global_position.distance_to(target.global_position)
			if dist <= radius:
				result.append(target)

	return result


func _check_detection() -> void:
	"""Check if sappers are detected by player units"""
	var player_units: Array[Node] = get_tree().get_nodes_in_group("player_units")

	for unit in player_units:
		if not is_instance_valid(unit):
			continue

		var distance: float = global_position.distance_to(unit.global_position)

		# Base detection range
		var detection_range: float = 15.0

		# Reduce range based on stealth rating
		detection_range *= (1.0 - stealth_rating * 0.5)

		# Watchtowers and flares increase detection
		if unit.is_in_group("watchtowers"):
			detection_range *= 2.0

		if distance <= detection_range:
			# Detection roll
			var detect_chance: float = 0.2 * (1.0 - stealth_rating)
			if randf() < detect_chance:
				detected.emit(unit)
				# Alert nearby units
				if BattleSignals:
					BattleSignals.enemy_spotted.emit(self, unit)
				print("[SapperTeam] Detected by %s" % unit.name)


func take_damage(amount: float, source: Node = null) -> void:
	"""Take damage"""
	current_health -= amount

	# Calculate member casualties
	var prev_members: int = _members_alive
	_members_alive = maxi(0, int(current_health / 15.0))

	if _members_alive < prev_members:
		print("[SapperTeam] Lost %d members, %d remaining" % [prev_members - _members_alive, _members_alive])

	if current_health <= 0:
		_die()


func _die() -> void:
	"""Handle sapper team death"""
	state = SapperState.DEAD
	sapper_died.emit(self)

	# Visual death
	if _mesh:
		_mesh.rotation = Vector3(PI / 2, 0, 0)
		_mesh.position.y = 0.2

	# Remove from groups
	remove_from_group("sapper_teams")
	remove_from_group("enemy_units")

	print("[SapperTeam] Eliminated")


## Public API

func set_target(target: Node3D, type: TargetType = TargetType.ANY_STRUCTURE) -> void:
	"""Set the target for the sapper team"""
	current_target = target
	target_type = type
	if is_instance_valid(target):
		target_position = target.global_position
	state = SapperState.INFILTRATING


func set_target_position(pos: Vector3) -> void:
	"""Set target position for infiltration"""
	target_position = pos
	state = SapperState.INFILTRATING


func move_to(pos: Vector3) -> void:
	"""Move to position"""
	target_position = pos
	state = SapperState.INFILTRATING


func attack(target: Node3D) -> void:
	"""Attack a specific target"""
	current_target = target
	if is_instance_valid(target):
		target_position = target.global_position
	state = SapperState.ATTACKING


func retreat() -> void:
	"""Order retreat"""
	state = SapperState.RETREATING


func get_remaining_charges() -> int:
	return _satchel_charges


func is_alive() -> bool:
	return state != SapperState.DEAD


func stop_attack() -> void:
	"""Stop current attack"""
	state = SapperState.INFILTRATING
