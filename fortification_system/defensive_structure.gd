class_name DefensiveStructure extends Node3D
## DefensiveStructure - Auto-targeting defense component for bunkers, MG nests, mortar pits
##
## Attach to any building to enable automatic enemy engagement.
## Works standalone (emplaced weapon) or with garrisoned infantry for bonus.
##
## USAGE:
##   var defense = DefensiveStructure.new()
##   defense.weapon_type = "m60"
##   defense.attack_range = 500.0
##   building.add_child(defense)

signal target_acquired(target: Node3D)
signal target_lost
signal weapon_fired(target: Node3D)
signal out_of_ammo

enum DefenseType {
	MG_NEST,      # M60 or similar - direct fire, high ROF
	BUNKER,       # Garrison bonus, moderate firepower
	MORTAR_PIT,   # Indirect fire, area effect
	WATCHTOWER,   # Detection bonus, light firepower
	ARTILLERY,    # Long range indirect fire
}

## Configuration
@export var defense_type: DefenseType = DefenseType.MG_NEST
@export var weapon_type: String = "m60"  # VietnamWeaponData ID
@export var attack_range: float = 500.0  # Engagement range in meters
@export var detection_range: float = 600.0  # Can see enemies this far
@export var rotation_speed: float = 90.0  # Degrees per second turret rotation
@export var requires_garrison: bool = false  # If true, needs infantry to operate
@export var garrison_damage_bonus: float = 0.25  # +25% damage per garrisoned soldier (max 4)

## Ammo (mortar/artillery only)
@export var max_ammo: int = -1  # -1 = unlimited (MG nest draws from firebase)
@export var current_ammo: int = -1

## State
var current_target: Node3D = null
var attack_cooldown: float = 0.0
var current_rotation: float = 0.0  # Turret facing direction
var is_active: bool = true
var detected_enemies: Array[Node3D] = []

## References
var _garrison_component: Node = null  # GarrisonableStructure if present
var _parent_building: Node3D = null
var _firebase: Node3D = null

## Scan timer (don't scan every frame)
var _scan_timer: float = 0.0
const SCAN_INTERVAL: float = 0.25  # Scan 4 times per second

## Weapon data cache
var _weapon_data: RefCounted = null


func _ready() -> void:
	_parent_building = get_parent()

	# Find garrison component if present
	_garrison_component = _parent_building.get_node_or_null("GarrisonableStructure")

	# Find parent firebase
	_find_firebase()

	# Load weapon data
	var weapon_script = load("res://battle_system/data/vietnam_weapon_data.gd")
	if weapon_script:
		_weapon_data = weapon_script.get_weapon(weapon_type)

	# Set range from weapon data if available
	if _weapon_data and attack_range == 500.0:  # Default value
		attack_range = _weapon_data.effective_range

	add_to_group("defensive_structures")


func _physics_process(delta: float) -> void:
	if not is_active:
		return

	# Check if operational
	if not _is_operational():
		return

	# Update cooldown
	if attack_cooldown > 0.0:
		attack_cooldown -= delta

	# Periodic enemy scan
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		_scan_for_enemies()

	# Process targeting
	_process_targeting(delta)

	# Fire if ready
	if current_target and attack_cooldown <= 0.0:
		_fire_at_target()


func _is_operational() -> bool:
	"""Check if defense can operate"""
	# Requires garrison but none present
	if requires_garrison:
		if not _garrison_component:
			return false
		if _garrison_component.garrisoned_units.is_empty():
			return false

	# Check ammo for mortar/artillery
	if max_ammo > 0 and current_ammo <= 0:
		return false

	return true


func _find_firebase() -> void:
	"""Find parent firebase for supply"""
	var firebases: Array[Node] = get_tree().get_nodes_in_group("firebases")
	var my_pos: Vector3 = global_position

	for fb in firebases:
		if not is_instance_valid(fb):
			continue
		if fb.global_position.distance_to(my_pos) < 100.0:
			_firebase = fb
			break


# =============================================================================
# TARGETING
# =============================================================================

func _scan_for_enemies() -> void:
	"""Scan for enemies within detection range"""
	detected_enemies.clear()

	# Get enemies from spatial hash grid
	var grid: Node = get_node_or_null("/root/SpatialHashGrid")
	if grid and grid.has_method("get_enemies_in_radius"):
		# Assume we're US/ARVN faction (buildings are player-owned)
		var enemies: Array = grid.get_enemies_in_radius(global_position, detection_range, GameEnums.Faction.US_ARMY)
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy is Node3D:
				detected_enemies.append(enemy)
	else:
		# Fallback: scan enemy groups directly
		var enemy_groups: Array[String] = ["enemy_units"]
		for group_name in enemy_groups:
			var enemies: Array[Node] = get_tree().get_nodes_in_group(group_name)
			for enemy in enemies:
				if not is_instance_valid(enemy) or not enemy is Node3D:
					continue
				var dist: float = global_position.distance_to(enemy.global_position)
				if dist <= detection_range:
					detected_enemies.append(enemy)


func _process_targeting(delta: float) -> void:
	"""Select and track target"""
	# Validate current target
	if current_target:
		if not _is_valid_target(current_target):
			_lose_target()

	# Acquire new target if needed
	if not current_target:
		current_target = _select_best_target()
		if current_target:
			target_acquired.emit(current_target)

	# Rotate toward target
	if current_target:
		_rotate_toward_target(delta)


func _is_valid_target(target: Node3D) -> bool:
	"""Check if target is still valid"""
	if not is_instance_valid(target):
		return false

	# Check if dead
	if target.has_method("get") and target.get("state") != null:
		var state_val: int = target.get("state")
		if state_val == 4:  # State.DEAD (usually index 4)
			return false

	# Check range
	var dist: float = global_position.distance_to(target.global_position)
	if dist > attack_range:
		return false

	# Check LOS for direct fire weapons
	if defense_type != DefenseType.MORTAR_PIT and defense_type != DefenseType.ARTILLERY:
		if not _has_line_of_sight(target):
			return false

	return true


func _select_best_target() -> Node3D:
	"""Select the best target from detected enemies"""
	var best_target: Node3D = null
	var best_priority: float = -INF

	for enemy in detected_enemies:
		if not _is_valid_target(enemy):
			continue

		var priority: float = _calculate_target_priority(enemy)
		if priority > best_priority:
			best_priority = priority
			best_target = enemy

	return best_target


func _calculate_target_priority(target: Node3D) -> float:
	"""Calculate targeting priority (higher = more important)"""
	var priority: float = 0.0
	var dist: float = global_position.distance_to(target.global_position)

	# Closer enemies have higher priority
	priority += (attack_range - dist) / attack_range * 50.0

	# Prioritize enemies attacking the firebase
	if _firebase and target.has_method("get"):
		var target_target: Node = target.get("current_target")
		if is_instance_valid(target_target) and target_target == _firebase:
			priority += 100.0

	# Prioritize low-health enemies (finish them off)
	if target.has_method("get"):
		var health_ratio: Variant = target.get("current_health")
		var max_health: Variant = target.get("max_health")
		if health_ratio is float and max_health is float and max_health > 0:
			priority += (1.0 - health_ratio / max_health) * 20.0

	# Mortars/artillery prioritize groups
	if defense_type == DefenseType.MORTAR_PIT or defense_type == DefenseType.ARTILLERY:
		var nearby_count: int = _count_enemies_near(target.global_position, 10.0)
		priority += nearby_count * 15.0

	return priority


func _count_enemies_near(pos: Vector3, radius: float) -> int:
	"""Count enemies near a position (for area weapons)"""
	var count: int = 0
	for enemy in detected_enemies:
		if is_instance_valid(enemy):
			if enemy.global_position.distance_to(pos) <= radius:
				count += 1
	return count


func _has_line_of_sight(target: Node3D) -> bool:
	"""Check if we have LOS to target"""
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if not space_state:
		return true  # Assume LOS if can't check

	var from: Vector3 = global_position + Vector3(0, 2, 0)  # Firing height
	var to: Vector3 = target.global_position + Vector3(0, 1, 0)  # Target center

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # Terrain only
	query.exclude = [self, _parent_building] if _parent_building else [self]

	var result: Dictionary = space_state.intersect_ray(query)

	# No hit = clear LOS, or hit is the target
	return result.is_empty()


func _lose_target() -> void:
	"""Clear current target"""
	current_target = null
	target_lost.emit()


func _rotate_toward_target(delta: float) -> void:
	"""Rotate turret toward target"""
	if not current_target:
		return

	var to_target: Vector3 = current_target.global_position - global_position
	to_target.y = 0

	var target_angle: float = atan2(to_target.x, to_target.z)
	var angle_diff: float = angle_difference(current_rotation, target_angle)

	var max_rotation: float = deg_to_rad(rotation_speed) * delta
	current_rotation += clampf(angle_diff, -max_rotation, max_rotation)


# =============================================================================
# FIRING
# =============================================================================

func _fire_at_target() -> void:
	"""Fire at current target"""
	if not current_target or not _weapon_data:
		return

	# Check if facing target (within 15 degrees)
	var to_target: Vector3 = current_target.global_position - global_position
	to_target.y = 0
	var target_angle: float = atan2(to_target.x, to_target.z)
	var angle_diff: float = abs(angle_difference(current_rotation, target_angle))

	if angle_diff > deg_to_rad(15.0):
		return  # Not facing target yet

	# Calculate damage
	var damage: float = _weapon_data.damage

	# Garrison bonus
	if _garrison_component and not _garrison_component.garrisoned_units.is_empty():
		var garrison_count: int = mini(_garrison_component.garrisoned_units.size(), 4)
		damage *= 1.0 + (garrison_damage_bonus * garrison_count)

	# Apply damage to target
	if current_target.has_method("take_damage"):
		current_target.take_damage(damage, _parent_building)

	# Apply suppression
	if current_target.has_method("apply_suppression"):
		current_target.apply_suppression(_weapon_data.suppression)

	# Set cooldown
	attack_cooldown = 60.0 / _weapon_data.rate_of_fire

	# Consume ammo for mortar/artillery
	if max_ammo > 0:
		current_ammo -= 1
		if current_ammo <= 0:
			out_of_ammo.emit()

	weapon_fired.emit(current_target)

	# Emit battle signal
	if BattleSignals:
		BattleSignals.unit_attacked.emit(_parent_building, current_target, weapon_type)


# =============================================================================
# PUBLIC API
# =============================================================================

## Manually set a target (for player override)
func set_target(target: Node3D) -> void:
	if _is_valid_target(target):
		current_target = target
		target_acquired.emit(target)


## Clear target
func clear_target() -> void:
	_lose_target()


## Enable/disable defense
func set_active(active: bool) -> void:
	is_active = active
	if not active:
		_lose_target()


## Reload ammo (for mortar/artillery)
func reload(amount: int) -> void:
	if max_ammo > 0:
		current_ammo = mini(current_ammo + amount, max_ammo)


## Get current target
func get_target() -> Node3D:
	return current_target


## Get detected enemy count
func get_detected_count() -> int:
	return detected_enemies.size()


## Check if defense is operational
func is_operational() -> bool:
	return _is_operational()


## Get ammo status (for UI)
func get_ammo_status() -> Dictionary:
	return {
		"current": current_ammo,
		"max": max_ammo,
		"unlimited": max_ammo < 0
	}
