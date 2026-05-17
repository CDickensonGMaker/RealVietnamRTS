extends Node3D
## class_name Firebase  # Commented out - conflicts with main firebase.gd
## Firebase - A fortified base with construction zones and defensive structures
## Implements auto-defense, adjacency bonuses, supply consumption, artillery support,
## medical treatment, and perimeter defense systems

signal firebase_established()
signal firebase_upgraded(new_level: int)
signal firebase_under_attack(attacker: Node3D)
signal perimeter_breached(breach_point: Vector3)
signal building_added(building: Node3D)
signal alert_level_changed(new_level: int)
signal supplies_critical(supply_type: String)
signal artillery_fired(target: Vector3)
signal casualty_treated(unit: Node3D)
signal auto_defense_engaged(target: Node3D)

# =============================================================================
# ENUMS
# =============================================================================
enum AlertLevel {
	GREEN,       # Peacetime, normal operations
	YELLOW,      # Heightened awareness
	RED,         # Active combat
	BROKEN_ARROW # Overrun, danger close authorized
}

enum DefensePosture {
	HOLD_FIRE,         # Do not engage
	WEAPONS_TIGHT,     # Engage only if directly attacked
	WEAPONS_FREE,      # Engage all enemies
}

# Preloaded classes (avoid forward reference issues)
const ConstructionZoneClass = preload("res://firebase_system/construction_zone.gd")

# Firebase identification
@export var firebase_name: String = "Firebase Alpha"
@export var firebase_callsign: String = "ALPHA"
@export var faction: int = GameEnums.Faction.US_ARMY

# Firebase level
var level: int = GameEnums.FirebaseLevel.PATROL_BASE

# Components
var construction_zones: Array = []  # Array of ConstructionZone
var buildings: Array[Node3D] = []
var garrison: Array[Node3D] = []  # Units stationed here
var perimeter: Node3D = null  # Perimeter defense area

# Supply system (detailed)
var supplies: Dictionary = {
	"ammunition": 100.0,
	"fuel": 100.0,
	"rations": 100.0,
	"medical": 100.0,
	"construction": 50.0,
}
var supply_consumption_rates: Dictionary = {
	"ammunition": 0.5,  # Per garrison member per minute
	"fuel": 0.2,
	"rations": 0.3,
	"medical": 0.1,
	"construction": 0.0,  # Only consumed on build
}

# Legacy compatibility
var supply_level: float:
	get: return supplies.ammunition
	set(v): supplies.ammunition = v
var ammo_level: float:
	get: return supplies.ammunition
	set(v): supplies.ammunition = v

# Combat status
var under_attack: bool = false
var attack_timer: float = 0.0
var alert_level: AlertLevel = AlertLevel.GREEN
var defense_posture: DefensePosture = DefensePosture.WEAPONS_TIGHT
var last_attack_direction: Vector3 = Vector3.ZERO

# Auto-defense system
var defensive_weapons: Array[Node3D] = []  # MG nests, mortars, etc.
var auto_defense_enabled: bool = true
var auto_defense_range: float = 150.0
var engaged_targets: Dictionary = {}  # Target -> weapon engaging

# Artillery system
var artillery_pieces: Array[Node3D] = []
var artillery_cooldown: float = 0.0
var artillery_ammo: int = 50
var fire_missions_available: int = 3

# Medical system
var wounded_queue: Array[Node3D] = []
var treatment_rate: float = 10.0  # HP healed per second
var medical_capacity: int = 4  # Simultaneous patients
var currently_treating: Array[Node3D] = []

# Perimeter defense
var wire_segments: Array[Dictionary] = []  # {start, end, hp}
var claymore_positions: Array[Dictionary] = []  # {position, direction, armed}
var perimeter_radius: float = 50.0

# Landing zones
var landing_zones: Array[Node3D] = []

# Adjacency bonuses
var adjacency_bonuses: Dictionary = {}

# Timers
var supply_tick_timer: float = 0.0
var auto_defense_scan_timer: float = 0.0
var medical_tick_timer: float = 0.0

func _ready() -> void:
	add_to_group("firebases")
	add_to_group("us_structures")

	# Create initial construction zones based on level
	_create_construction_zones()
	_calculate_perimeter_radius()
	_connect_signals()

	firebase_established.emit()
	BattleSignals.firebase_established.emit(self)

func _connect_signals() -> void:
	BattleSignals.unit_damaged.connect(_on_any_unit_damaged)
	BattleSignals.explosion.connect(_on_explosion_nearby)

func _process(delta: float) -> void:
	# Attack status management
	if under_attack:
		attack_timer += delta
		# Auto-resolve attack status after no contact
		if attack_timer > 30.0:
			under_attack = false
			_lower_alert_level()

	# Supply consumption
	supply_tick_timer += delta
	if supply_tick_timer >= 60.0:  # Every minute
		supply_tick_timer = 0.0
		_process_supply_consumption()

	# Auto-defense system
	auto_defense_scan_timer += delta
	if auto_defense_scan_timer >= 1.0:
		auto_defense_scan_timer = 0.0
		if auto_defense_enabled and alert_level >= AlertLevel.YELLOW:
			_process_auto_defense()

	# Medical system
	medical_tick_timer += delta
	if medical_tick_timer >= 1.0:
		medical_tick_timer = 0.0
		_process_medical_treatment(1.0)

	# Artillery cooldown
	if artillery_cooldown > 0:
		artillery_cooldown -= delta

func _physics_process(_delta: float) -> void:
	# Check for enemies crossing perimeter
	if alert_level >= AlertLevel.YELLOW:
		_check_perimeter_intrusions()

# =============================================================================
# LEVEL MANAGEMENT
# =============================================================================

func get_level() -> int:
	return level

func get_level_name() -> String:
	match level:
		GameEnums.FirebaseLevel.PATROL_BASE:
			return "Patrol Base"
		GameEnums.FirebaseLevel.FIRE_SUPPORT_BASE:
			return "Fire Support Base"
		GameEnums.FirebaseLevel.MAJOR_FIREBASE:
			return "Major Firebase"
		_:
			return "Unknown"

func get_available_slots() -> int:
	return GameEnums.get_firebase_slots(level)

func get_used_slots() -> int:
	return buildings.size()

func get_free_slots() -> int:
	return get_available_slots() - get_used_slots()

func can_upgrade() -> bool:
	match level:
		GameEnums.FirebaseLevel.PATROL_BASE:
			return buildings.size() >= 3
		GameEnums.FirebaseLevel.FIRE_SUPPORT_BASE:
			return buildings.size() >= 6
		_:
			return false

func upgrade() -> bool:
	if not can_upgrade():
		return false

	match level:
		GameEnums.FirebaseLevel.PATROL_BASE:
			level = GameEnums.FirebaseLevel.FIRE_SUPPORT_BASE
		GameEnums.FirebaseLevel.FIRE_SUPPORT_BASE:
			level = GameEnums.FirebaseLevel.MAJOR_FIREBASE

	_create_construction_zones()  # Add new zones

	firebase_upgraded.emit(level)
	BattleSignals.firebase_upgraded.emit(self, level)

	return true

# =============================================================================
# CONSTRUCTION ZONES
# =============================================================================

func _create_construction_zones() -> void:
	var slots := get_available_slots()
	var existing := construction_zones.size()

	# Create new zones for additional slots
	for i in range(existing, slots):
		var angle := (TAU / slots) * i
		var radius := 20.0 + (level * 10)  # Bigger firebase = larger perimeter
		var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)

		var zone := ConstructionZoneClass.new()
		zone.global_position = global_position + pos
		zone.zone_size = Vector2(8, 8)
		add_child(zone)
		construction_zones.append(zone)

		# Connect signals
		zone.construction_complete.connect(_on_construction_complete)

func get_nearest_empty_zone(from_position: Vector3):  # Returns ConstructionZone or null
	var nearest = null  # ConstructionZone
	var nearest_dist := INF

	for zone in construction_zones:
		if zone.can_build():
			var dist := from_position.distance_to(zone.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = zone

	return nearest

func get_zones_needing_clearing() -> Array:  # Array of ConstructionZone
	var zones: Array = []
	for zone in construction_zones:
		if not zone.is_cleared():
			zones.append(zone)
	return zones

# =============================================================================
# BUILDINGS
# =============================================================================

func _on_construction_complete(building: Node3D) -> void:
	buildings.append(building)
	building_added.emit(building)
	BattleSignals.construction_complete.emit(building)

	# Check for special buildings
	if building.has_method("is_landing_zone") and building.is_landing_zone():
		landing_zones.append(building)

	# Register defensive weapons
	var building_type := -1
	if building.has_method("get_building_type"):
		building_type = building.get_building_type()

	match building_type:
		GameEnums.BuildingType.MACHINE_GUN_NEST, \
		GameEnums.BuildingType.MORTAR_PIT:
			register_defensive_weapon(building)
		GameEnums.BuildingType.ARTILLERY_PIT:
			register_artillery(building)

	# Recalculate adjacency bonuses
	_calculate_adjacency_bonuses()

	# Expand perimeter if we upgraded
	_calculate_perimeter_radius()

func get_buildings_of_type(building_type: int) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for building in buildings:
		if building.has_method("get_building_type"):
			if building.get_building_type() == building_type:
				result.append(building)
	return result

func has_building_type(building_type: int) -> bool:
	return not get_buildings_of_type(building_type).is_empty()

func has_comms() -> bool:
	return has_building_type(GameEnums.BuildingType.COMMO_BUNKER) or \
		   has_building_type(GameEnums.BuildingType.TOC)

func has_helipad() -> bool:
	return has_building_type(GameEnums.BuildingType.HELIPAD)

func has_artillery() -> bool:
	return has_building_type(GameEnums.BuildingType.ARTILLERY_PIT)

# =============================================================================
# GARRISON
# =============================================================================

func add_to_garrison(unit: Node3D) -> void:
	if unit not in garrison:
		garrison.append(unit)

func remove_from_garrison(unit: Node3D) -> void:
	garrison.erase(unit)

func get_garrison_strength() -> int:
	var strength := 0
	for unit in garrison:
		if is_instance_valid(unit) and unit.has_method("get_squad_size"):
			strength += unit.get_squad_size()
	return strength

# =============================================================================
# COMBAT
# =============================================================================

func report_attack(attacker: Node3D) -> void:
	under_attack = true
	attack_timer = 0.0

	firebase_under_attack.emit(attacker)
	BattleSignals.firebase_under_attack.emit(self, attacker)

func report_perimeter_breach(position: Vector3) -> void:
	perimeter_breached.emit(position)

# =============================================================================
# SUPPLIES
# =============================================================================

func add_supplies(amount: float) -> void:
	supply_level = minf(100.0, supply_level + amount)

func consume_supplies(amount: float) -> bool:
	if supply_level >= amount:
		supply_level -= amount
		return true
	return false

func add_ammo(amount: float) -> void:
	ammo_level = minf(100.0, ammo_level + amount)

func get_supply_status() -> String:
	if supply_level > 70:
		return "Good"
	elif supply_level > 30:
		return "Low"
	else:
		return "Critical"

# =============================================================================
# LANDING ZONES
# =============================================================================

func get_available_lz() -> Node3D:
	for lz in landing_zones:
		if is_instance_valid(lz) and lz.has_method("is_available"):
			if lz.is_available():
				return lz
	return null

func get_all_lzs() -> Array[Node3D]:
	var valid: Array[Node3D] = []
	for lz in landing_zones:
		if is_instance_valid(lz):
			valid.append(lz)
	return valid

# =============================================================================
# AUTO-DEFENSE SYSTEM
# =============================================================================

func register_defensive_weapon(weapon: Node3D) -> void:
	if weapon not in defensive_weapons:
		defensive_weapons.append(weapon)

func _process_auto_defense() -> void:
	if defense_posture == DefensePosture.HOLD_FIRE:
		return

	# Clean up invalid weapons and targets
	defensive_weapons = defensive_weapons.filter(func(w): return is_instance_valid(w))
	for target: Node3D in engaged_targets.keys():
		if not is_instance_valid(target):
			engaged_targets.erase(target)

	# Find enemies in range
	var enemies := SpatialHashGrid.get_enemies_in_radius(
		global_position, auto_defense_range, faction
	)

	if enemies.is_empty():
		return

	# Weapons tight - only engage if they're attacking us
	if defense_posture == DefensePosture.WEAPONS_TIGHT:
		enemies = enemies.filter(func(e): return _is_attacking_firebase(e))

	# Assign weapons to targets
	for weapon in defensive_weapons:
		if not is_instance_valid(weapon):
			continue

		# Check if weapon is already engaging
		var current_target: Node3D = null
		for target: Node3D in engaged_targets.keys():
			if engaged_targets[target] == weapon:
				current_target = target
				break

		if current_target and is_instance_valid(current_target):
			# Keep engaging current target
			continue

		# Find new target
		var best_target: Node3D = null
		var best_dist := INF

		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue

			# Skip if already engaged by another weapon
			if enemy in engaged_targets:
				continue

			var dist := weapon.global_position.distance_to(enemy.global_position)
			if dist < best_dist:
				best_dist = dist
				best_target = enemy

		if best_target:
			_engage_target(weapon, best_target)

func _engage_target(weapon: Node3D, target: Node3D) -> void:
	engaged_targets[target] = weapon

	if weapon.has_method("engage_target"):
		weapon.engage_target(target)

	auto_defense_engaged.emit(target)

func _is_attacking_firebase(unit: Node3D) -> bool:
	## Check if unit is currently attacking this firebase or its garrison

	if unit.has_method("get_attack_target"):
		var target: Node3D = unit.get_attack_target()
		if target == self:
			return true
		if target in garrison:
			return true
		if target in buildings:
			return true

	return false

func set_defense_posture(posture: DefensePosture) -> void:
	defense_posture = posture

	# Clear engagements if holding fire
	if posture == DefensePosture.HOLD_FIRE:
		for weapon: Node3D in engaged_targets.values():
			if is_instance_valid(weapon) and weapon.has_method("cease_fire"):
				weapon.cease_fire()
		engaged_targets.clear()

# =============================================================================
# ALERT LEVEL MANAGEMENT
# =============================================================================

func set_alert_level(new_level: AlertLevel) -> void:
	if new_level == alert_level:
		return

	var old_level := alert_level
	alert_level = new_level

	alert_level_changed.emit(new_level)

	# Adjust defense posture automatically
	match new_level:
		AlertLevel.GREEN:
			defense_posture = DefensePosture.WEAPONS_TIGHT
		AlertLevel.YELLOW:
			defense_posture = DefensePosture.WEAPONS_TIGHT
		AlertLevel.RED:
			defense_posture = DefensePosture.WEAPONS_FREE
		AlertLevel.BROKEN_ARROW:
			defense_posture = DefensePosture.WEAPONS_FREE
			# Request immediate support
			_request_broken_arrow_support()

func _raise_alert_level() -> void:
	match alert_level:
		AlertLevel.GREEN:
			set_alert_level(AlertLevel.YELLOW)
		AlertLevel.YELLOW:
			set_alert_level(AlertLevel.RED)
		AlertLevel.RED:
			# Check if we should go to BROKEN_ARROW
			if _is_overrun():
				set_alert_level(AlertLevel.BROKEN_ARROW)

func _lower_alert_level() -> void:
	match alert_level:
		AlertLevel.BROKEN_ARROW:
			set_alert_level(AlertLevel.RED)
		AlertLevel.RED:
			set_alert_level(AlertLevel.YELLOW)
		AlertLevel.YELLOW:
			set_alert_level(AlertLevel.GREEN)

func _is_overrun() -> bool:
	## Check if firebase is being overrun

	# Count enemies inside perimeter
	var enemies_inside := SpatialHashGrid.get_enemies_in_radius(
		global_position, perimeter_radius * 0.5, faction
	)

	# If enemies outnumber garrison inside perimeter
	var garrison_inside := 0
	for unit in garrison:
		if is_instance_valid(unit):
			if unit.global_position.distance_to(global_position) < perimeter_radius:
				garrison_inside += 1

	return enemies_inside.size() > garrison_inside * 2

func _request_broken_arrow_support() -> void:
	## Request danger close air support - firebase is being overrun

	if has_comms():
		# Call in everything
		BattleSignals.airstrike_requested.emit(
			GameEnums.AirStrikeType.CLOSE_AIR_SUPPORT,
			global_position
		)

# =============================================================================
# SUPPLY SYSTEM
# =============================================================================

func _process_supply_consumption() -> void:
	var garrison_count := get_garrison_strength()
	if garrison_count == 0:
		return

	for supply_type: String in supplies.keys():
		var rate: float = supply_consumption_rates.get(supply_type, 0.0)
		var consumption := rate * garrison_count

		# Apply adjacency bonuses (Ammo Bunker reduces ammo consumption, etc.)
		if adjacency_bonuses.has(supply_type + "_efficiency"):
			consumption *= (1.0 - adjacency_bonuses[supply_type + "_efficiency"])

		supplies[supply_type] = maxf(0.0, supplies[supply_type] - consumption)

		# Check for critical levels
		if supplies[supply_type] < 20.0:
			supplies_critical.emit(supply_type)
			BattleSignals.supply_low.emit(self, supply_type)

		if supplies[supply_type] <= 0.0:
			BattleSignals.supply_depleted.emit(self, supply_type)

func get_supply(supply_type: String) -> float:
	return supplies.get(supply_type, 0.0)

func add_supply(supply_type: String, amount: float) -> void:
	if supplies.has(supply_type):
		supplies[supply_type] = minf(100.0, supplies[supply_type] + amount)
		BattleSignals.supply_delivered.emit(self, amount)

func get_supplies_needed() -> Dictionary:
	## Return dict of supplies below threshold

	var needed: Dictionary = {}
	for supply_type: String in supplies.keys():
		if supplies[supply_type] < 50.0:
			needed[supply_type] = 100.0 - supplies[supply_type]
	return needed

# =============================================================================
# ARTILLERY SUPPORT
# =============================================================================

func register_artillery(artillery: Node3D) -> void:
	if artillery not in artillery_pieces:
		artillery_pieces.append(artillery)

func request_fire_mission(target: Vector3, rounds: int = 6) -> bool:
	## Request artillery fire mission

	if artillery_pieces.is_empty():
		return false

	if artillery_cooldown > 0:
		return false

	if artillery_ammo < rounds:
		rounds = artillery_ammo

	if rounds <= 0:
		return false

	# Find available artillery
	var available: Array[Node3D] = []
	for arty in artillery_pieces:
		if is_instance_valid(arty):
			available.append(arty)

	if available.is_empty():
		return false

	# Execute fire mission
	artillery_ammo -= rounds
	artillery_cooldown = 30.0  # 30 second cooldown between missions
	fire_missions_available -= 1

	_execute_fire_mission(target, rounds, available)
	artillery_fired.emit(target)

	return true

func _execute_fire_mission(target: Vector3, rounds: int, guns: Array[Node3D]) -> void:
	## Fire artillery rounds at target with dispersion

	for i in range(rounds):
		# Distribute rounds across available guns
		var gun: Node3D = guns[i % guns.size()]

		# Calculate impact with dispersion
		var dispersion := Vector3(
			randf_range(-20, 20),
			0,
			randf_range(-20, 20)
		)
		var impact := target + dispersion

		# Schedule impact (flight time based on distance)
		var distance := gun.global_position.distance_to(target)
		var flight_time := distance / 500.0  # 500 m/s shell velocity
		var delay := flight_time + i * 1.0  # 1 second between rounds

		_schedule_artillery_impact(impact, delay, gun)

func _schedule_artillery_impact(position: Vector3, delay: float, gun: Node3D) -> void:
	await get_tree().create_timer(delay).timeout

	# 105mm howitzer stats
	var damage := 500.0
	var radius := 15.0

	# Apply damage to all units in radius
	var victims := SpatialHashGrid.get_all_units_in_radius(position, radius)
	for victim in victims:
		if is_instance_valid(victim) and victim.has_method("take_damage"):
			var dist := victim.global_position.distance_to(position)
			var falloff := 1.0 - (dist / radius)
			victim.take_damage(damage * falloff, gun)

	BattleSignals.explosion.emit(position, radius, damage)
	BattleSignals.artillery_impact.emit(position)

func get_artillery_status() -> Dictionary:
	return {
		"available": artillery_pieces.size(),
		"ammo": artillery_ammo,
		"cooldown": artillery_cooldown,
		"fire_missions": fire_missions_available,
	}

# =============================================================================
# MEDICAL SYSTEM
# =============================================================================

func request_medical(wounded_unit: Node3D) -> bool:
	## Add wounded unit to treatment queue

	if not has_building_type(GameEnums.BuildingType.MEDICAL_STATION):
		return false

	if wounded_unit in wounded_queue or wounded_unit in currently_treating:
		return false

	wounded_queue.append(wounded_unit)
	return true

func _process_medical_treatment(delta: float) -> void:
	## Process medical treatment for wounded units

	# Get medical capacity from buildings
	var total_capacity := 0
	for building in get_buildings_of_type(GameEnums.BuildingType.MEDICAL_STATION):
		total_capacity += medical_capacity

	if total_capacity == 0:
		return

	# Check medical supplies
	if supplies.medical <= 0:
		return

	# Move from queue to treatment
	while currently_treating.size() < total_capacity and not wounded_queue.is_empty():
		var unit: Node3D = wounded_queue.pop_front()
		if is_instance_valid(unit):
			currently_treating.append(unit)

	# Treat current patients
	var treated: Array[Node3D] = []
	for unit in currently_treating:
		if not is_instance_valid(unit):
			treated.append(unit)
			continue

		# Heal the unit
		var heal_amount := treatment_rate * delta

		# Adjacency bonus from Aid Station
		if adjacency_bonuses.has("healing_bonus"):
			heal_amount *= (1.0 + adjacency_bonuses.healing_bonus)

		if unit.has_method("heal"):
			unit.heal(heal_amount)
			supplies.medical -= 0.1 * delta  # Consume medical supplies

		# Check if fully healed
		var is_healed := false
		if unit.has_method("get_health_ratio"):
			is_healed = unit.get_health_ratio() >= 1.0
		elif unit.has_method("is_at_full_health"):
			is_healed = unit.is_at_full_health()

		if is_healed:
			treated.append(unit)
			casualty_treated.emit(unit)

	# Remove healed units
	for unit in treated:
		currently_treating.erase(unit)

# =============================================================================
# PERIMETER DEFENSE
# =============================================================================

func _calculate_perimeter_radius() -> void:
	## Calculate perimeter based on firebase level

	match level:
		GameEnums.FirebaseLevel.PATROL_BASE:
			perimeter_radius = 40.0
		GameEnums.FirebaseLevel.FIRE_SUPPORT_BASE:
			perimeter_radius = 60.0
		GameEnums.FirebaseLevel.MAJOR_FIREBASE:
			perimeter_radius = 80.0

func add_wire_segment(start: Vector3, end: Vector3, hp: float = 100.0) -> void:
	wire_segments.append({
		"start": start,
		"end": end,
		"hp": hp,
		"breached": false,
	})

func place_claymore(position: Vector3, direction: Vector3) -> void:
	claymore_positions.append({
		"position": position,
		"direction": direction.normalized(),
		"armed": true,
	})

func _check_perimeter_intrusions() -> void:
	## Check for enemies crossing perimeter wire

	var enemies := SpatialHashGrid.get_enemies_in_radius(
		global_position, perimeter_radius, faction
	)

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Check wire crossings
		for wire in wire_segments:
			if wire.breached:
				continue

			if _is_crossing_wire(enemy, wire):
				_wire_encounter(enemy, wire)

		# Check claymore triggers
		for claymore in claymore_positions:
			if not claymore.armed:
				continue

			if _is_in_claymore_cone(enemy, claymore):
				_trigger_claymore(claymore)

func _is_crossing_wire(unit: Node3D, wire: Dictionary) -> bool:
	## Check if unit is crossing wire segment

	var unit_pos := unit.global_position
	var wire_start: Vector3 = wire.start
	var wire_end: Vector3 = wire.end

	# Check distance to wire line
	var wire_vec := wire_end - wire_start
	var to_unit := unit_pos - wire_start
	var projection := to_unit.project(wire_vec)

	# Check if projection is on wire segment
	var proj_length := projection.length()
	var wire_length := wire_vec.length()

	if proj_length < 0 or proj_length > wire_length:
		return false

	# Check perpendicular distance
	var perp_dist := (to_unit - projection).length()
	return perp_dist < 3.0  # Within 3 meters of wire

func _wire_encounter(unit: Node3D, wire: Dictionary) -> void:
	## Unit encountered wire obstacle

	# Slow the unit
	if unit.has_method("apply_slow"):
		unit.apply_slow(0.5, 5.0)  # 50% slow for 5 seconds

	# Deal minor damage
	if unit.has_method("take_damage"):
		unit.take_damage(5.0, null)  # Wire cuts

	# Alert garrison
	_raise_alert_level()
	report_perimeter_breach(unit.global_position)

	# Sappers can cut wire
	if unit.has_method("is_sapper") and unit.is_sapper():
		wire.hp -= 20.0
		if wire.hp <= 0:
			wire.breached = true

func _is_in_claymore_cone(unit: Node3D, claymore: Dictionary) -> bool:
	## Check if unit is in claymore's kill zone

	var claymore_pos: Vector3 = claymore.position
	var direction: Vector3 = claymore.direction

	var to_unit := unit.global_position - claymore_pos
	to_unit.y = 0
	to_unit = to_unit.normalized()

	# Claymore has 60 degree cone, 50 meter range
	var dot := direction.dot(to_unit)
	var distance := unit.global_position.distance_to(claymore_pos)

	return dot > 0.5 and distance < 50.0

func _trigger_claymore(claymore: Dictionary) -> void:
	## Detonate claymore mine

	claymore.armed = false

	var position: Vector3 = claymore.position
	var direction: Vector3 = claymore.direction

	# Claymore does heavy damage in cone
	var victims := SpatialHashGrid.get_all_units_in_radius(position, 50.0)
	for victim in victims:
		if not is_instance_valid(victim):
			continue

		var to_victim := victim.global_position - position
		to_victim.y = 0
		to_victim = to_victim.normalized()

		var dot := direction.dot(to_victim)
		if dot > 0.3:  # In the cone
			var dist := victim.global_position.distance_to(position)
			var damage := 200.0 * (1.0 - dist / 50.0) * dot

			if victim.has_method("take_damage"):
				victim.take_damage(damage, null)

	BattleSignals.explosion.emit(position, 25.0, 200.0)

# =============================================================================
# ADJACENCY BONUSES
# =============================================================================

func _calculate_adjacency_bonuses() -> void:
	## Calculate bonuses from building adjacency

	adjacency_bonuses.clear()

	for building in buildings:
		if not is_instance_valid(building):
			continue

		var building_type := -1
		if building.has_method("get_building_type"):
			building_type = building.get_building_type()

		# Check what buildings are adjacent
		for other in buildings:
			if other == building or not is_instance_valid(other):
				continue

			var dist := building.global_position.distance_to(other.global_position)
			if dist > 15.0:  # Not adjacent
				continue

			var other_type := -1
			if other.has_method("get_building_type"):
				other_type = other.get_building_type()

			_apply_adjacency_bonus(building_type, other_type)

func _apply_adjacency_bonus(building_a: int, building_b: int) -> void:
	## Apply bonuses for specific building combinations

	# Ammo Bunker + MG Nest = faster reload
	if building_a == GameEnums.BuildingType.AMMO_BUNKER:
		if building_b == GameEnums.BuildingType.MACHINE_GUN_NEST:
			adjacency_bonuses["mg_reload_bonus"] = adjacency_bonuses.get("mg_reload_bonus", 0.0) + 0.2

	# Medical Station + Bunker = faster healing
	if building_a == GameEnums.BuildingType.MEDICAL_STATION:
		if building_b == GameEnums.BuildingType.BUNKER:
			adjacency_bonuses["healing_bonus"] = adjacency_bonuses.get("healing_bonus", 0.0) + 0.15

	# TOC + Commo Bunker = faster air support response
	if building_a == GameEnums.BuildingType.TOC:
		if building_b == GameEnums.BuildingType.COMMO_BUNKER:
			adjacency_bonuses["air_support_speed"] = adjacency_bonuses.get("air_support_speed", 0.0) + 0.25

	# Ammo Bunker + Artillery Pit = reduced ammo consumption
	if building_a == GameEnums.BuildingType.AMMO_BUNKER:
		if building_b == GameEnums.BuildingType.ARTILLERY_PIT:
			adjacency_bonuses["ammunition_efficiency"] = adjacency_bonuses.get("ammunition_efficiency", 0.0) + 0.15

	# Watchtower + Any defense = increased sight
	if building_a == GameEnums.BuildingType.WATCHTOWER:
		adjacency_bonuses["sight_bonus"] = adjacency_bonuses.get("sight_bonus", 0.0) + 0.1

func get_adjacency_bonus(bonus_name: String) -> float:
	return adjacency_bonuses.get(bonus_name, 0.0)

# =============================================================================
# EVENT HANDLERS
# =============================================================================

func _on_any_unit_damaged(unit: Node3D, _damage: float, source: Node3D) -> void:
	## React to nearby combat

	if unit in garrison or unit in buildings:
		report_attack(source)

func _on_explosion_nearby(position: Vector3, _radius: float, _damage: float) -> void:
	## React to explosions

	var dist := position.distance_to(global_position)
	if dist < perimeter_radius * 1.5:
		_raise_alert_level()

# =============================================================================
# STATUS & DEBUG
# =============================================================================

func get_defense_status() -> Dictionary:
	return {
		"alert_level": AlertLevel.keys()[alert_level],
		"defense_posture": DefensePosture.keys()[defense_posture],
		"garrison_strength": get_garrison_strength(),
		"under_attack": under_attack,
		"perimeter_intact": wire_segments.filter(func(w): return not w.breached).size(),
		"claymores_armed": claymore_positions.filter(func(c): return c.armed).size(),
	}

func get_full_status() -> Dictionary:
	return {
		"name": firebase_name,
		"callsign": firebase_callsign,
		"level": get_level_name(),
		"buildings": buildings.size(),
		"slots_free": get_free_slots(),
		"supplies": supplies.duplicate(),
		"defense": get_defense_status(),
		"artillery": get_artillery_status(),
		"medical_queue": wounded_queue.size(),
		"adjacency_bonuses": adjacency_bonuses.duplicate(),
	}
