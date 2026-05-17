class_name ProjectilePool extends Node

## Object pool for projectiles to avoid constant instantiation.
## Vietnam combat can have hundreds of bullets in flight simultaneously.

const ProjectileScript = preload("res://battle_system/combat/projectile.gd")
const VietnamWeaponDataScript = preload("res://battle_system/data/vietnam_weapon_data.gd")

## Pool settings
const INITIAL_POOL_SIZE: int = 100
const MAX_POOL_SIZE: int = 500
const GROW_AMOUNT: int = 50

## Projectile pools
var _pool: Array[Node3D] = []
var _active_projectiles: Array[Node3D] = []
var _pool_parent: Node3D = null

## Statistics
var _total_fired: int = 0
var _pool_misses: int = 0


func _ready() -> void:
	# Create pool parent node
	_pool_parent = Node3D.new()
	_pool_parent.name = "ProjectilePool"
	add_child(_pool_parent)

	# Pre-populate pool
	_grow_pool(INITIAL_POOL_SIZE)

	print("[ProjectilePool] Initialized with %d projectiles" % _pool.size())


func _process(_delta: float) -> void:
	# Clean up inactive projectiles
	var to_remove: Array[Node3D] = []
	for proj in _active_projectiles:
		if proj.has_method("is_active") and not proj.is_active():
			to_remove.append(proj)

	for proj in to_remove:
		_active_projectiles.erase(proj)
		_pool.append(proj)


func _grow_pool(amount: int) -> void:
	var current_total: int = _pool.size() + _active_projectiles.size()
	var space: int = MAX_POOL_SIZE - current_total
	var actual_grow: int = mini(amount, space)

	for i in actual_grow:
		var proj: Node3D = ProjectileScript.new()
		proj.visible = false
		_pool_parent.add_child(proj)
		_pool.append(proj)


## Fire a projectile from the pool.
func fire(config: Dictionary) -> Node3D:
	_total_fired += 1

	# Get projectile from pool
	var proj: Node3D = null

	if _pool.size() > 0:
		proj = _pool.pop_back()
	else:
		# Pool exhausted - grow it
		_pool_misses += 1
		_grow_pool(GROW_AMOUNT)

		if _pool.size() > 0:
			proj = _pool.pop_back()
		else:
			push_warning("[ProjectilePool] Pool exhausted at max size!")
			return null

	# Fire the projectile
	if proj.has_method("fire"):
		proj.fire(config)
	_active_projectiles.append(proj)

	return proj


## Fire a weapon at a target.
func fire_weapon(weapon_id: String, source: Node, target_pos: Vector3,
		source_faction: int = 0, target_node: Node = null) -> Node3D:
	var weapon_config := VietnamWeaponDataScript.get_projectile_config(weapon_id)
	if weapon_config.is_empty():
		push_warning("[ProjectilePool] Unknown weapon: %s" % weapon_id)
		return null

	var weapon := VietnamWeaponDataScript.get_weapon(weapon_id)
	if not weapon:
		return null

	# Build fire config
	var config := {
		"start_position": source.global_position + Vector3(0, 1.0, 0),  # Muzzle height
		"target_position": target_pos,
		"source": source,
		"source_faction": source_faction,
		"target_node": target_node,

		# From weapon data
		"speed": weapon.projectile_speed,
		"lifetime": weapon.lifetime,
		"trajectory": weapon.trajectory,
		"arc_height": weapon.arc_height,
		"damage": weapon.damage,
		"damage_type": weapon.damage_type,
		"aoe_radius": weapon.aoe_radius,
		"aoe_falloff": weapon.aoe_falloff,
		"suppression": weapon.suppression,
		"suppression_radius": weapon.suppression_radius,
		"max_pierces": weapon.max_pierces,
		"pierce_falloff": weapon.pierce_falloff,
		"armor_penetration": weapon.armor_penetration,
		"anti_vehicle_bonus": weapon.anti_vehicle_bonus,
		"scatter_angle": weapon.scatter_angle,
		"weapon_category": weapon.category,
		"is_tracer": weapon.tracer_ratio > 0 and (_total_fired % weapon.tracer_ratio == 0),
	}

	return fire(config)


## Fire a burst of rounds from a weapon.
func fire_burst(weapon_id: String, source: Node, target_pos: Vector3,
		burst_count: int, burst_delay: float, source_faction: int = 0) -> void:
	# Fire first round immediately
	fire_weapon(weapon_id, source, target_pos, source_faction)

	# Schedule remaining rounds
	if burst_count > 1:
		var tween := create_tween()
		for i in range(1, burst_count):
			tween.tween_callback(func():
				if is_instance_valid(source):
					fire_weapon(weapon_id, source, target_pos, source_faction)
			).set_delay(burst_delay * float(i))


## Get pool statistics.
func get_stats() -> Dictionary:
	return {
		"pool_size": _pool.size(),
		"active_count": _active_projectiles.size(),
		"total_fired": _total_fired,
		"pool_misses": _pool_misses,
	}


## Print pool statistics.
func print_stats() -> void:
	var stats := get_stats()
	print("[ProjectilePool] Pool: %d | Active: %d | Fired: %d | Misses: %d" % [
		stats.pool_size, stats.active_count, stats.total_fired, stats.pool_misses
	])
