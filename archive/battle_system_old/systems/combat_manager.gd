extends Node
## CombatManager - Handles combat resolution, damage calculation, and morale effects
## Accessed globally via CombatManager autoload (no class_name needed)

# Preload WeaponData for type annotations (needed since this is an autoload)
const WeaponDataClass := preload("res://battle_system/data/weapon_data.gd")

# =============================================================================
# CONFIGURATION
# =============================================================================

# Terrain concealment modifiers
const TERRAIN_CONCEALMENT := {
	GameEnums.TerrainType.TRIPLE_CANOPY_JUNGLE: 0.9,
	GameEnums.TerrainType.SINGLE_CANOPY: 0.6,
	GameEnums.TerrainType.BAMBOO: 0.7,
	GameEnums.TerrainType.RICE_PADDY: 0.1,
	GameEnums.TerrainType.ELEPHANT_GRASS: 0.5,
	GameEnums.TerrainType.VILLAGE: 0.4,
	GameEnums.TerrainType.CLEARED_FIREBASE: 0.0,
	GameEnums.TerrainType.ROAD: 0.0,
	GameEnums.TerrainType.TRAIL: 0.2,
	GameEnums.TerrainType.HILL: 0.2,
}

# Armor damage reduction
const ARMOR_EFFECTIVENESS := {
	GameEnums.DamageType.SMALL_ARMS: 0.1,     # Rifles do 10% to armor
	GameEnums.DamageType.HEAVY_MG: 0.25,      # .50 cal does 25%
	GameEnums.DamageType.EXPLOSIVE: 0.5,       # Explosives do 50%
	GameEnums.DamageType.SHAPED_CHARGE: 1.0,   # AT weapons full damage
	GameEnums.DamageType.ARTILLERY: 0.8,       # Artillery does 80%
	GameEnums.DamageType.NAPALM: 0.3,          # Napalm 30% (crew casualty)
	GameEnums.DamageType.FRAGMENTATION: 0.4,   # Cluster 40%
}

# =============================================================================
# REFERENCES
# =============================================================================

var _cover_system: Node = null
var _pathfinding_cost_manager: Node = null

func _ready() -> void:
	# Connect to battle signals for combat events
	if BattleSignals:
		BattleSignals.weapon_fired.connect(_on_weapon_fired)
		BattleSignals.grenade_thrown.connect(_on_grenade_thrown)

	# Get references to other systems
	_cover_system = get_node_or_null("/root/CoverSystem")
	_pathfinding_cost_manager = get_node_or_null("/root/PathfindingCostManager")

# =============================================================================
# MAIN COMBAT API
# =============================================================================

func resolve_attack(shooter: Node3D, target: Node3D, weapon_class: int) -> Dictionary:
	## Main combat resolution - returns detailed result
	var result := {
		"hit": false,
		"damage": 0.0,
		"suppression": 0.0,
		"critical": false,
		"cover_blocked": false,
		"out_of_range": false,
		"blocked_by_terrain": false,
	}

	# Get weapon data
	var weapon := WeaponDataClass.get_weapon(weapon_class)
	if not weapon:
		return result

	var distance := shooter.global_position.distance_to(target.global_position)

	# Range check
	if distance > weapon.max_range:
		result.out_of_range = true
		return result

	# Min range check (explosives have arm distance)
	if distance < weapon.min_range:
		return result

	# Line of sight check
	var los := check_line_of_sight(shooter.global_position, target.global_position, [shooter, target])
	if not los.clear:
		result.blocked_by_terrain = true
		# Suppression still applies for near misses
		result.suppression = weapon.suppression_value * 0.3
		_apply_suppression_to_target(target, result.suppression)
		return result

	# Calculate hit chance
	var hit_chance := _calculate_hit_chance(shooter, target, weapon, distance)

	# Roll for hit
	result.hit = randf() < hit_chance

	if result.hit:
		# Calculate damage
		result.damage = _calculate_final_damage(shooter, target, weapon, distance)

		# Check for critical hit (headshot, engine hit, etc.)
		if randf() < 0.1:  # 10% crit chance
			result.critical = true
			result.damage *= 1.5

		# Apply damage
		if target.has_method("take_damage"):
			target.take_damage(result.damage, shooter)
			BattleSignals.unit_damaged.emit(target, result.damage, shooter)

	# Suppression always applies (near misses suppress)
	result.suppression = weapon.suppression_value
	if not result.hit:
		result.suppression *= 0.5  # Half suppression for misses
	_apply_suppression_to_target(target, result.suppression)

	# Emit combat event
	BattleSignals.combat_resolved.emit(shooter, target, result)

	return result


func resolve_area_attack(center: Vector3, weapon_class: int, source: Node3D = null) -> Array[Dictionary]:
	## Resolve area effect weapon (grenade, mortar, napalm)
	var results: Array[Dictionary] = []

	var weapon := WeaponDataClass.get_weapon(weapon_class)
	if not weapon or weapon.splash_radius <= 0:
		return results

	# Get all units in splash radius
	var units := SpatialHashGrid.get_units_in_radius(center, weapon.splash_radius)

	for unit in units:
		if not is_instance_valid(unit):
			continue

		# Don't damage self with own explosives
		if unit == source:
			continue

		var distance := center.distance_to(unit.global_position)

		# Calculate falloff damage
		var falloff := 1.0 - (distance / weapon.splash_radius) * weapon.splash_falloff
		var damage := weapon.base_damage * maxf(0.0, falloff)

		# Cover reduces explosive damage
		var cover_reduction := 0.0
		if _cover_system and _cover_system.has_method("get_damage_reduction"):
			cover_reduction = _cover_system.get_damage_reduction(unit, center)
		damage *= (1.0 - cover_reduction)

		# Armor reduction for vehicles
		if _is_armored(unit):
			var armor_factor: float = ARMOR_EFFECTIVENESS.get(weapon.damage_type, 1.0)
			damage *= armor_factor

		var result := {
			"unit": unit,
			"damage": damage,
			"suppression": weapon.get_suppression_at_distance(distance),
		}

		# Apply effects
		if unit.has_method("take_damage"):
			unit.take_damage(damage, source)
			BattleSignals.unit_damaged.emit(unit, damage, source)

		_apply_suppression_to_target(unit, result.suppression)
		results.append(result)

	# Emit explosion signal
	BattleSignals.explosion.emit(center, weapon.splash_radius, weapon.base_damage)

	# Special handling for napalm
	if weapon.damage_type == GameEnums.DamageType.NAPALM:
		BattleSignals.napalm_impact.emit(center, weapon.splash_radius)
		# Apply terror to all nearby units
		for unit in units:
			if is_instance_valid(unit):
				apply_terror(unit, "napalm")

	return results


# =============================================================================
# DAMAGE CALCULATION
# =============================================================================

func _calculate_hit_chance(shooter: Node3D, target: Node3D, weapon: WeaponDataClass,
						   distance: float) -> float:
	# Start with shooter's accuracy or weapon base
	var accuracy := weapon.base_accuracy
	if shooter.has_method("get_accuracy"):
		accuracy = shooter.get_accuracy()

	# Shooter suppression penalty
	var shooter_suppression := 0.0
	if shooter.has_method("get_suppression"):
		shooter_suppression = shooter.get_suppression()

	# Apply weapon accuracy modifiers
	var is_moving := false
	if shooter.has_method("is_moving"):
		is_moving = shooter.is_moving()

	accuracy = weapon.get_accuracy_at_range(distance, is_moving, shooter_suppression)

	# Target movement penalty
	if target.has_method("is_moving") and target.is_moving():
		accuracy *= 0.8

	# Cover accuracy penalty (firing from cover is harder)
	if _cover_system and _cover_system.has_method("get_accuracy_penalty"):
		var penalty: float = _cover_system.get_accuracy_penalty(shooter)
		accuracy *= (1.0 - penalty)

	# Target concealment from terrain
	var terrain := _get_terrain_at(target.global_position)
	var concealment: float = TERRAIN_CONCEALMENT.get(terrain, 0.0)
	accuracy *= (1.0 - concealment * 0.5)

	# Target concealment from cover
	if _cover_system and _cover_system.has_method("get_concealment_bonus"):
		var cover_concealment: float = _cover_system.get_concealment_bonus(target)
		accuracy *= (1.0 - cover_concealment * 0.3)

	# Experience bonus
	if shooter.has_method("get_veterancy"):
		var vet: int = shooter.get_veterancy()
		accuracy += vet * 0.03  # 3% per veterancy level

	return clampf(accuracy, 0.05, 0.95)


func _calculate_final_damage(shooter: Node3D, target: Node3D, weapon: WeaponDataClass,
							 distance: float) -> float:
	# Base damage with range falloff
	var damage := weapon.get_damage_at_range(distance)

	# Cover damage reduction
	if _cover_system and _cover_system.has_method("get_damage_reduction"):
		var cover_red: float = _cover_system.get_damage_reduction(target, shooter.global_position)
		damage *= (1.0 - cover_red)

	# Armor reduction for vehicles
	if _is_armored(target):
		# Check penetration
		if not _can_penetrate(weapon, target):
			return 0.0  # Bounced off armor

		var armor_factor: float = ARMOR_EFFECTIVENESS.get(weapon.damage_type, 1.0)
		damage *= armor_factor

	# Veterancy damage bonus
	if shooter.has_method("get_veterancy"):
		var vet: int = shooter.get_veterancy()
		damage *= (1.0 + vet * 0.05)  # 5% per level

	return damage


func _can_penetrate(weapon: WeaponDataClass, target: Node3D) -> bool:
	## Check if weapon can penetrate target's armor
	if weapon.armor_penetration <= 0:
		return weapon.damage_type != GameEnums.DamageType.SMALL_ARMS

	var target_armor := 0.0
	if target.has_method("get_armor"):
		target_armor = target.get_armor()

	return weapon.armor_penetration >= target_armor


func _is_armored(unit: Node3D) -> bool:
	if unit.has_method("is_armored"):
		return unit.is_armored()
	if unit.has_method("get_armor"):
		return unit.get_armor() > 0
	return false


func _apply_suppression_to_target(target: Node3D, amount: float) -> void:
	if not is_instance_valid(target):
		return

	# Cover reduces suppression
	if _cover_system and _cover_system.has_method("get_suppression_reduction"):
		var reduction: float = _cover_system.get_suppression_reduction(target)
		amount *= (1.0 - reduction)

	if target.has_method("apply_suppression"):
		target.apply_suppression(amount)
		BattleSignals.unit_suppressed.emit(target, amount)


# =============================================================================
# TERRAIN QUERIES
# =============================================================================

func _get_terrain_at(position: Vector3) -> int:
	## Get terrain type at position
	if TerrainClearingSystem and TerrainClearingSystem.has_method("get_terrain_type_at"):
		return TerrainClearingSystem.get_terrain_type_at(position)
	return GameEnums.TerrainType.SINGLE_CANOPY


# =============================================================================
# LINE OF SIGHT
# =============================================================================

func check_line_of_sight(from: Vector3, to: Vector3, ignore: Array = []) -> Dictionary:
	## Check if there's clear LOS between two points
	var result := {
		"clear": true,
		"hit_point": to,
		"hit_normal": Vector3.UP,
		"collider": null,
		"blocking_terrain": false,
	}

	# Need a valid scene tree
	var scene_tree := Engine.get_main_loop()
	if not scene_tree or not scene_tree is SceneTree:
		return result

	var root := (scene_tree as SceneTree).root
	if not root:
		return result

	var world := root.get_world_3d()
	if not world:
		return result

	var space_state := world.direct_space_state
	if not space_state:
		return result

	# Offset rays slightly above ground
	var from_eye := from + Vector3.UP * 1.5
	var to_eye := to + Vector3.UP * 1.5

	var query := PhysicsRayQueryParameters3D.create(from_eye, to_eye)

	# Convert ignore array to RIDs
	var exclude_rids: Array[RID] = []
	for node in ignore:
		if is_instance_valid(node) and node is CollisionObject3D:
			exclude_rids.append(node.get_rid())
	query.exclude = exclude_rids

	# Set collision mask for terrain and structures
	query.collision_mask = 1 | 2  # Layers 1 and 2

	var hit := space_state.intersect_ray(query)

	if not hit.is_empty():
		result.clear = false
		result.hit_point = hit.get("position", to)
		result.hit_normal = hit.get("normal", Vector3.UP)
		result.collider = hit.get("collider", null)

		# Check if blocked by terrain
		if result.collider and result.collider.is_in_group("terrain"):
			result.blocking_terrain = true

	return result


func get_visibility_to(observer: Node3D, target: Node3D) -> float:
	## Get visibility factor (0.0 = invisible, 1.0 = clearly visible)
	var los := check_line_of_sight(observer.global_position, target.global_position, [observer, target])

	if not los.clear:
		return 0.0

	var distance := observer.global_position.distance_to(target.global_position)

	# Base visibility based on distance
	var sight_range := 50.0
	if observer.has_method("get_sight_range"):
		sight_range = observer.get_sight_range()

	var visibility := 1.0 - (distance / sight_range)

	# Reduce by terrain concealment
	var terrain := _get_terrain_at(target.global_position)
	var concealment: float = TERRAIN_CONCEALMENT.get(terrain, 0.0)
	visibility *= (1.0 - concealment)

	# Reduce by cover concealment
	if _cover_system and _cover_system.has_method("get_concealment_bonus"):
		var cover_conceal: float = _cover_system.get_concealment_bonus(target)
		visibility *= (1.0 - cover_conceal)

	# SOG teams have reduced visibility
	if target.has_method("get_stealth_rating"):
		var stealth: float = target.get_stealth_rating()
		visibility *= (1.0 - stealth)

	return clampf(visibility, 0.0, 1.0)


# =============================================================================
# MORALE & TERROR
# =============================================================================

func apply_morale_damage(unit: Node3D, amount: float, source: String) -> void:
	## Reduce unit morale
	if not is_instance_valid(unit):
		return

	if unit.has_method("reduce_morale"):
		unit.reduce_morale(amount)

		var new_morale := 0.0
		if unit.has_method("get_morale"):
			new_morale = unit.get_morale()

		BattleSignals.unit_morale_changed.emit(unit, new_morale + amount, new_morale)

		if new_morale <= 0:
			BattleSignals.unit_routed.emit(unit)


func apply_terror(unit: Node3D, terror_source: String) -> void:
	## Apply terror effect (from napalm, air strikes, etc.)
	if not is_instance_valid(unit):
		return

	var terror_amount := 30.0

	match terror_source:
		"napalm":
			terror_amount = 50.0
		"arc_light":
			terror_amount = 80.0
		"artillery":
			terror_amount = 40.0
		"air_strike":
			terror_amount = 35.0
		"spooky":
			terror_amount = 45.0

	apply_morale_damage(unit, terror_amount, terror_source)

	if unit.has_method("apply_suppression"):
		unit.apply_suppression(terror_amount)


# =============================================================================
# SPECIAL ATTACKS
# =============================================================================

func apply_napalm_damage(center: Vector3, radius: float) -> void:
	## Special napalm damage - fire over time
	var results := resolve_area_attack(center, GameEnums.WeaponClass.NAPALM)

	# Signal terrain clearing
	BattleSignals.napalm_impact.emit(center, radius)


func resolve_artillery_strike(target: Vector3, shell_count: int,
							  accuracy: float = 0.4,
							  weapon_class: int = GameEnums.WeaponClass.M102_HOWITZER) -> void:
	## Resolve artillery barrage with scatter
	var weapon := WeaponDataClass.get_weapon(weapon_class)
	if not weapon:
		return

	for i in range(shell_count):
		# Calculate scatter based on accuracy
		var scatter_radius := weapon.splash_radius * (1.0 - accuracy)
		var scatter := Vector3(
			randf_range(-scatter_radius, scatter_radius),
			0,
			randf_range(-scatter_radius, scatter_radius)
		)
		var impact := target + scatter

		# Slight delay between shells
		await get_tree().create_timer(0.2).timeout

		resolve_area_attack(impact, weapon_class)
		BattleSignals.artillery_impact.emit(impact)


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_weapon_fired(shooter: Node3D, weapon_class: int, target_pos: Vector3) -> void:
	## Handle weapon fired event - mainly for visual/audio effects
	pass


func _on_grenade_thrown(thrower: Node3D, impact_pos: Vector3) -> void:
	## Handle grenade impact
	# Use M79 stats for grenades
	resolve_area_attack(impact_pos, GameEnums.WeaponClass.M79, thrower)


# =============================================================================
# UTILITY
# =============================================================================

func get_effective_range(weapon_class: int) -> float:
	var weapon := WeaponDataClass.get_weapon(weapon_class)
	return weapon.effective_range if weapon else 0.0


func get_max_range(weapon_class: int) -> float:
	var weapon := WeaponDataClass.get_weapon(weapon_class)
	return weapon.max_range if weapon else 0.0


func can_attack(shooter: Node3D, target: Node3D, weapon_class: int) -> bool:
	## Quick check if attack is possible
	var weapon := WeaponDataClass.get_weapon(weapon_class)
	if not weapon:
		return false

	var distance := shooter.global_position.distance_to(target.global_position)

	if distance > weapon.max_range:
		return false

	if distance < weapon.min_range:
		return false

	var los := check_line_of_sight(shooter.global_position, target.global_position, [shooter, target])
	return los.clear
