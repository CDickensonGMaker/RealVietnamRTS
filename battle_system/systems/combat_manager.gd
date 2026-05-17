extends Node

## CombatManager - Handles weapon firing, hit resolution, and damage.
## Designed for Vietnam-era infantry combat with high volume of fire.
## Integrates with BattleSignals for event broadcasting.

const VietnamWeaponDataScript = preload("res://battle_system/data/vietnam_weapon_data.gd")
const ProjectilePoolScript = preload("res://battle_system/combat/projectile_pool.gd")

## Signals
signal combat_started(attacker: Node, defender: Node)
signal damage_dealt(target: Node, amount: float, source: Node, weapon: String)
signal unit_suppressed(target: Node, amount: float)
signal unit_killed(target: Node, killer: Node)

## Combat constants
const HIT_CHANCE_BASE: float = 0.7
const HIT_CHANCE_MIN: float = 0.1
const HIT_CHANCE_MAX: float = 0.95
const COVER_BONUS: float = 0.3  # 30% hit reduction in cover
const PRONE_BONUS: float = 0.2  # 20% hit reduction when prone
# Suppression accuracy penalty now uses the 4-state system from GameEnums.SUPPRESSION_EFFECTS

## Range falloff thresholds
const POINT_BLANK_RANGE: float = 10.0  # Full damage
const EFFECTIVE_RANGE_RATIO: float = 0.6  # Full accuracy within 60% of max range

## Damage modifiers
const ARMOR_DAMAGE_REDUCTION: float = 0.02  # 2% per armor point
const MAX_ARMOR_REDUCTION: float = 0.7  # Max 70% reduction

## Height advantage (Broken Arrow style)
const HEIGHT_ADVANTAGE_PER_METER: float = 0.01  # 1% accuracy bonus per meter elevation
const HEIGHT_ADVANTAGE_MAX: float = 0.2  # Max 20% accuracy bonus from height
const HEIGHT_DAMAGE_BONUS_PER_METER: float = 0.005  # 0.5% damage bonus per meter
const HEIGHT_DAMAGE_BONUS_MAX: float = 0.15  # Max 15% damage bonus
const HEIGHT_SIGNIFICANT_THRESHOLD: float = 2.0  # Min height diff to matter

## Projectile pool
var projectile_pool: Node = null

## Cached autoload references (performance optimization)
var _cover_system: Node = null
var _veterancy_tracker: Node = null

## Active combat engagements
#var _active_engagements: Array[Dictionary] = []  # Reserved for future use

## Combat statistics
var _total_shots: int = 0
var _total_hits: int = 0
var _total_damage: float = 0.0


func _ready() -> void:
	# Create projectile pool
	projectile_pool = ProjectilePoolScript.new()
	add_child(projectile_pool)

	# Cache autoload references for performance
	_cover_system = get_node_or_null("/root/CoverSystem")
	_veterancy_tracker = get_node_or_null("/root/VeterancyTracker")

	print("[CombatManager] Initialized with projectile pool")


## Fire a weapon from attacker at target.
func fire_weapon(attacker: Node, target: Node, weapon_id: String) -> void:
	var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(weapon_id)
	if not weapon:
		push_warning("[CombatManager] Unknown weapon: %s" % weapon_id)
		return

	# Get attacker faction
	var attacker_faction: int = 0
	if attacker.has_method("get") and attacker.get("data"):
		attacker_faction = attacker.data.faction

	# Calculate target position with prediction
	var target_pos: Vector3 = _predict_target_position(attacker, target, weapon)

	# Fire based on weapon fire pattern
	match weapon.fire_pattern:
		VietnamWeaponDataScript.FirePattern.SINGLE:
			_fire_single(attacker, target, target_pos, weapon_id, attacker_faction)
		VietnamWeaponDataScript.FirePattern.BURST:
			_fire_burst(attacker, target, target_pos, weapon_id, attacker_faction, weapon)
		VietnamWeaponDataScript.FirePattern.AUTO:
			_fire_auto(attacker, target, target_pos, weapon_id, attacker_faction, weapon)
		VietnamWeaponDataScript.FirePattern.VOLLEY:
			_fire_volley(attacker, target, target_pos, weapon_id, attacker_faction)
		VietnamWeaponDataScript.FirePattern.STAGGER:
			_fire_stagger(attacker, target, target_pos, weapon_id, attacker_faction, weapon)

	_total_shots += 1

	# Emit combat started signal
	combat_started.emit(attacker, target)
	if BattleSignals:
		BattleSignals.unit_attacked.emit(attacker, target, weapon_id)


func _fire_single(attacker: Node, target: Node, target_pos: Vector3,
		weapon_id: String, attacker_faction: int) -> void:
	projectile_pool.fire_weapon(weapon_id, attacker, target_pos, attacker_faction, target)


func _fire_burst(attacker: Node, _target: Node, target_pos: Vector3,
		weapon_id: String, attacker_faction: int, weapon: RefCounted) -> void:
	projectile_pool.fire_burst(weapon_id, attacker, target_pos,
		weapon.burst_count, weapon.burst_delay, attacker_faction)


func _fire_auto(attacker: Node, target: Node, target_pos: Vector3,
		weapon_id: String, attacker_faction: int, weapon: RefCounted) -> void:
	# Continuous fire - fire multiple rounds based on ROF
	var rounds_per_second: float = weapon.rate_of_fire / 60.0
	var _fire_interval: float = 1.0 / rounds_per_second

	# Fire 1 second of sustained fire (will be controlled by squad behavior)
	var rounds_to_fire: int = mini(int(rounds_per_second), 10)  # Cap at 10 per call

	for i in rounds_to_fire:
		# Add slight variation to target position for spread effect
		var spread_pos: Vector3 = target_pos + Vector3(
			randf_range(-1.0, 1.0),
			0.0,
			randf_range(-1.0, 1.0)
		)
		projectile_pool.fire_weapon(weapon_id, attacker, spread_pos, attacker_faction, target)


func _fire_volley(attacker: Node, _target: Node, target_pos: Vector3,
		weapon_id: String, attacker_faction: int) -> void:
	# Single coordinated shot (for artillery)
	projectile_pool.fire_weapon(weapon_id, attacker, target_pos, attacker_faction)


func _fire_stagger(attacker: Node, _target: Node, target_pos: Vector3,
		weapon_id: String, attacker_faction: int, weapon: RefCounted) -> void:
	# Staggered fire - spread shots over time (MG teams)
	var rounds: int = 3  # 3-round stagger
	var interval: float = 60.0 / weapon.rate_of_fire

	var tween := get_tree().create_tween()
	for i in rounds:
		tween.tween_callback(func():
			if is_instance_valid(attacker):
				projectile_pool.fire_weapon(weapon_id, attacker, target_pos, attacker_faction)
		).set_delay(interval * float(i))


func _predict_target_position(attacker: Node, target: Node, weapon: RefCounted) -> Vector3:
	var target_pos: Vector3 = target.global_position

	# Only predict for moving targets and non-instant weapons
	if target.has_method("get") and target.get("velocity"):
		var target_velocity: Vector3 = target.velocity
		if target_velocity.length_squared() > 0.1:
			# Calculate flight time
			var distance: float = attacker.global_position.distance_to(target_pos)
			var flight_time: float = distance / weapon.projectile_speed

			# Add prediction
			target_pos += target_velocity * flight_time * 0.5  # 50% prediction

	# Add random offset for scatter
	if weapon.scatter_angle > 0.0:
		var scatter_dist: float = tan(deg_to_rad(weapon.scatter_angle)) * attacker.global_position.distance_to(target_pos)
		target_pos += Vector3(
			randf_range(-scatter_dist, scatter_dist),
			0.0,
			randf_range(-scatter_dist, scatter_dist)
		)

	return target_pos


## Calculate hit chance for an attack.
func calculate_hit_chance(attacker: Node, target: Node, weapon_id: String) -> float:
	var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(weapon_id)
	if not weapon:
		return HIT_CHANCE_BASE

	var distance: float = attacker.global_position.distance_to(target.global_position)

	# Base accuracy from weapon
	var hit_chance: float = VietnamWeaponDataScript.calculate_accuracy(weapon_id, distance, _is_moving(attacker))

	# Target modifiers - use CoverSystem for terrain-based cover
	if _cover_system and _cover_system.has_method("get_cover_for_unit"):
		var cover_type: int = _cover_system.get_cover_for_unit(target)
		# Hit penalty increases with cover quality (LIGHT=10%, HEAVY=20%, FORTIFIED=30%)
		match cover_type:
			GameEnums.CoverType.LIGHT:
				hit_chance -= 0.1
			GameEnums.CoverType.HEAVY:
				hit_chance -= 0.2
			GameEnums.CoverType.FORTIFIED:
				hit_chance -= 0.3
	elif _is_in_cover(target):
		# Fallback to legacy check
		hit_chance -= COVER_BONUS

	if _is_prone(target):
		hit_chance -= PRONE_BONUS
	if _is_moving(target):
		hit_chance -= 0.1  # Moving target penalty

	# Attacker suppression modifier (uses 4-state system)
	var suppression_accuracy_mult: float = _get_suppression_accuracy_modifier(attacker)
	hit_chance *= suppression_accuracy_mult

	# Range bonus at close range
	if distance < POINT_BLANK_RANGE:
		hit_chance += 0.15

	# Height advantage (Broken Arrow style - high ground matters)
	var height_data: Dictionary = _calculate_height_advantage(attacker, target)
	hit_chance += height_data.accuracy_mod

	return clampf(hit_chance, HIT_CHANCE_MIN, HIT_CHANCE_MAX)


## Resolve a direct hit on a target (called by projectile on impact).
func resolve_hit(target: Node, damage: float, source: Node, weapon_id: String = "") -> void:
	if not is_instance_valid(target):
		return

	# Get weapon data for suppression
	var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(weapon_id) if weapon_id else null

	# Get armor reduction
	var armor: float = 0.0
	if target.has_method("get") and target.get("data"):
		armor = target.data.armor if target.data else 0.0

	var armor_reduction: float = clampf(armor * ARMOR_DAMAGE_REDUCTION, 0.0, MAX_ARMOR_REDUCTION)

	# Get cover damage reduction from CoverSystem
	var cover_reduction: float = 0.0
	if _cover_system and _cover_system.has_method("get_damage_reduction"):
		cover_reduction = _cover_system.get_damage_reduction(target)

	# Apply both armor and cover reduction (multiplicative)
	var final_damage: float = damage * (1.0 - armor_reduction) * (1.0 - cover_reduction)

	# Height advantage damage bonus (Broken Arrow style)
	if is_instance_valid(source):
		var height_data: Dictionary = _calculate_height_advantage(source, target)
		if height_data.damage_mod > 0.0:
			final_damage *= (1.0 + height_data.damage_mod)

	# Apply damage
	if target.has_method("take_damage"):
		target.take_damage(final_damage, source)

	_total_hits += 1
	_total_damage += final_damage

	# Apply direct hit suppression to target
	if weapon:
		var fear_type: int = weapon.fear_type
		var hit_suppression: float = weapon.suppression
		apply_suppression_with_fear(target, hit_suppression, fear_type, source)

		# Apply AOE suppression to nearby units (the "beaten zone" effect)
		apply_aoe_suppression(target.global_position, weapon_id, source)

	# Award damage XP to attacker via VeterancyTracker
	if is_instance_valid(source) and _veterancy_tracker:
		if _veterancy_tracker.has_method("award_damage_xp"):
			_veterancy_tracker.award_damage_xp(source, final_damage)

	# Emit signals
	damage_dealt.emit(target, final_damage, source, weapon_id)
	if BattleSignals:
		BattleSignals.unit_damaged.emit(target, final_damage, source)

	# Check for kill
	if target.has_method("get") and target.get("current_health"):
		if target.current_health <= 0:
			# Award kill XP to attacker
			if is_instance_valid(source) and _veterancy_tracker:
				if _veterancy_tracker.has_method("award_kill_xp"):
					_veterancy_tracker.award_kill_xp(source)

			unit_killed.emit(target, source)
			if BattleSignals:
				BattleSignals.unit_died.emit(target, source)


## Apply suppression to a target with fear type modifier.
## fear_type: GameEnums.FearType - determines suppression impact
## amount: raw suppression value from weapon
func apply_suppression_with_fear(target: Node, amount: float, fear_type: int, source: Node = null) -> void:
	if not is_instance_valid(target):
		return

	if target.has_method("apply_suppression_with_fear"):
		target.apply_suppression_with_fear(amount, fear_type)
	elif target.has_method("apply_suppression"):
		# Fallback for units without fear type support
		target.apply_suppression(amount)

	unit_suppressed.emit(target, amount)
	if BattleSignals:
		BattleSignals.unit_suppressed.emit(target, amount, source)


## Apply AOE suppression to all units within radius of impact point.
## This creates the "beaten zone" effect where near misses still suppress.
func apply_aoe_suppression(impact_pos: Vector3, weapon_id: String, source: Node = null) -> void:
	var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(weapon_id)
	if not weapon:
		return

	var fear_type: int = weapon.fear_type
	var aoe_radius: float = GameEnums.get_fear_aoe(fear_type)
	var base_suppression: float = weapon.suppression_near_miss

	# Skip if no AOE suppression effect
	if aoe_radius <= 0.0 or base_suppression <= 0.0:
		return

	# Get source faction to avoid suppressing friendlies (optional)
	var _source_faction: int = -1
	if source and source.has_method("get") and source.get("data"):
		_source_faction = source.data.faction

	# Query all units in radius using SpatialHashGrid if available
	var nearby_units: Array = []
	if SpatialHashGrid and SpatialHashGrid.has_method("get_units_in_radius"):
		nearby_units = SpatialHashGrid.get_units_in_radius(impact_pos, aoe_radius)
	else:
		# Fallback: check all units (less efficient)
		nearby_units = get_tree().get_nodes_in_group("all_units")

	for unit in nearby_units:
		if not is_instance_valid(unit):
			continue

		# Skip dead units
		if unit.has_method("get") and unit.get("state"):
			if unit.state == 5:  # State.DEAD
				continue

		# Calculate distance falloff
		var distance: float = impact_pos.distance_to(unit.global_position)
		if distance > aoe_radius:
			continue

		# Suppression falls off linearly with distance
		var falloff: float = 1.0 - (distance / aoe_radius)
		var suppression_amount: float = base_suppression * falloff * 0.5  # 50% of near-miss value

		# Apply suppression
		apply_suppression_with_fear(unit, suppression_amount, fear_type, source)


## Legacy apply_suppression for backward compatibility.
func apply_suppression(target: Node, amount: float, source: Node = null) -> void:
	apply_suppression_with_fear(target, amount, GameEnums.FearType.SMALL_ARMS, source)


## Handle near-miss suppression for projectiles passing close to units.
## Called by projectiles when they pass within near_miss_radius of a unit.
func on_projectile_near_unit(_projectile_pos: Vector3, weapon_id: String, unit: Node, distance: float, source: Node = null) -> void:
	if not is_instance_valid(unit):
		return

	# Skip dead units
	if unit.has_method("get") and unit.get("state"):
		if unit.state == 5:  # State.DEAD
			return

	var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(weapon_id)
	if not weapon:
		return

	var fear_type: int = weapon.fear_type
	var near_miss_radius: float = 3.0  # Base radius for near-miss detection
	var suppression: float = weapon.suppression_near_miss

	# Calculate falloff based on how close the near-miss was
	var falloff: float = 1.0 - (distance / near_miss_radius)
	falloff = clampf(falloff, 0.0, 1.0)

	var suppression_amount: float = suppression * falloff

	if suppression_amount > 0.0:
		apply_suppression_with_fear(unit, suppression_amount, fear_type, source)


## Check if unit is in cover.
func _is_in_cover(unit: Node) -> bool:
	if unit.has_method("get") and unit.get("is_in_cover"):
		return unit.is_in_cover
	return false


## Check if unit is prone.
func _is_prone(unit: Node) -> bool:
	if unit.has_method("get") and unit.get("is_prone"):
		return unit.is_prone
	return false


## Check if unit is moving.
func _is_moving(unit: Node) -> bool:
	if unit.has_method("get") and unit.get("velocity"):
		return unit.velocity.length_squared() > 0.1
	return false


## Check if unit is suppressed.
## Get suppression accuracy modifier (1.0 = full accuracy, 0.1 = pinned)
func _get_suppression_accuracy_modifier(unit: Node) -> float:
	if unit.has_method("get_suppression_accuracy_modifier"):
		return unit.get_suppression_accuracy_modifier()
	# Fallback for units without new system
	if unit.has_method("get") and unit.get("suppression_level"):
		if unit.suppression_level > 0.8:
			return 0.1  # PINNED
		elif unit.suppression_level > 0.5:
			return 0.4  # SUPPRESSED
		elif unit.suppression_level > 0.3:
			return 0.75  # CAUTIOUS
	return 1.0  # NORMAL


## Legacy check for suppression state (deprecated, use _get_suppression_accuracy_modifier)
func _is_suppressed(unit: Node) -> bool:
	if unit.has_method("get") and unit.get("suppression_level"):
		return unit.suppression_level > 0.5
	return false


## Calculate height advantage for attacker shooting at target.
## Returns positive value if attacker has high ground, negative if shooting uphill.
## Broken Arrow style: terrain elevation creates significant tactical advantages.
func _calculate_height_advantage(attacker: Node, target: Node) -> Dictionary:
	var attacker_y: float = attacker.global_position.y
	var target_y: float = target.global_position.y
	var height_diff: float = attacker_y - target_y

	# Skip if height difference is negligible
	if absf(height_diff) < HEIGHT_SIGNIFICANT_THRESHOLD:
		return {"accuracy_mod": 0.0, "damage_mod": 0.0, "has_advantage": false}

	var has_advantage: bool = height_diff > 0.0

	# Accuracy modifier (shooting down is easier, up is harder)
	var accuracy_mod: float = clampf(
		height_diff * HEIGHT_ADVANTAGE_PER_METER,
		-HEIGHT_ADVANTAGE_MAX,
		HEIGHT_ADVANTAGE_MAX
	)

	# Damage modifier (gravity assists downward shots)
	var damage_mod: float = 0.0
	if has_advantage:
		damage_mod = clampf(
			height_diff * HEIGHT_DAMAGE_BONUS_PER_METER,
			0.0,
			HEIGHT_DAMAGE_BONUS_MAX
		)

	return {
		"accuracy_mod": accuracy_mod,
		"damage_mod": damage_mod,
		"has_advantage": has_advantage,
		"height_diff": height_diff
	}


## Call an artillery strike at a position.
func call_artillery_strike(target_pos: Vector3, weapon_id: String, rounds: int = 6,
		source: Node = null, source_faction: int = 0) -> void:
	var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(weapon_id)
	if not weapon:
		push_warning("[CombatManager] Unknown artillery weapon: %s" % weapon_id)
		return

	# Fire rounds with scatter
	var interval: float = weapon.reload_time / float(rounds)
	var scatter_radius: float = weapon.scatter_angle * 2.0  # Increased scatter for barrage

	for i in rounds:
		var scatter_pos: Vector3 = target_pos + Vector3(
			randf_range(-scatter_radius, scatter_radius),
			0.0,
			randf_range(-scatter_radius, scatter_radius)
		)

		# Delay each round
		var timer := get_tree().create_timer(interval * float(i))
		timer.timeout.connect(func():
			var config: Dictionary = VietnamWeaponDataScript.get_projectile_config(weapon_id)
			config["start_position"] = target_pos + Vector3(0, 200.0, 0)  # High start
			config["target_position"] = scatter_pos
			config["source"] = source
			config["source_faction"] = source_faction
			projectile_pool.fire(config)
		)

	if BattleSignals:
		BattleSignals.artillery_called.emit(target_pos, weapon_id, rounds)


## Call a napalm strike along a line.
func call_napalm_strike(start_pos: Vector3, end_pos: Vector3,
		source: Node = null, source_faction: int = 0) -> void:
	var weapon: RefCounted = VietnamWeaponDataScript.get_weapon("napalm")
	if not weapon:
		return

	# Drop canisters along the line
	var num_drops: int = 4
	for i in num_drops:
		var t: float = float(i) / float(num_drops - 1)
		var drop_pos: Vector3 = start_pos.lerp(end_pos, t)
		drop_pos.y = 0.0

		# Delay drops for aircraft travel
		var timer := get_tree().create_timer(0.3 * float(i))
		timer.timeout.connect(func():
			var config: Dictionary = VietnamWeaponDataScript.get_projectile_config("napalm")
			config["start_position"] = drop_pos + Vector3(0, 50.0, 0)
			config["target_position"] = drop_pos
			config["source"] = source
			config["source_faction"] = source_faction
			config["weapon_category"] = VietnamWeaponDataScript.WeaponCategory.AIRCRAFT_NAPALM
			projectile_pool.fire(config)
		)

	if BattleSignals:
		BattleSignals.napalm_strike_called.emit(start_pos, end_pos)


## Get combat statistics.
func get_combat_stats() -> Dictionary:
	var accuracy: float = 0.0
	if _total_shots > 0:
		accuracy = float(_total_hits) / float(_total_shots)

	return {
		"total_shots": _total_shots,
		"total_hits": _total_hits,
		"total_damage": _total_damage,
		"accuracy": accuracy,
		"projectile_pool": projectile_pool.get_stats() if projectile_pool else {},
	}


## Print combat statistics.
func print_stats() -> void:
	var stats := get_combat_stats()
	print("[CombatManager] Shots: %d | Hits: %d | Accuracy: %.1f%% | Damage: %.0f" % [
		stats.total_shots, stats.total_hits, stats.accuracy * 100.0, stats.total_damage
	])
	if projectile_pool:
		projectile_pool.print_stats()
