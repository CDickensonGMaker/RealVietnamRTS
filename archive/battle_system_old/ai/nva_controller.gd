extends Node
class_name NVAController
## NVAController - North Vietnamese Army conventional AI
## Manages artillery, armor, AAA, and coordinated assaults
## NVA uses conventional military tactics with combined arms doctrine

signal offensive_started(target: Node3D)
signal offensive_phase_changed(offensive: Dictionary, new_phase: String)
signal artillery_barrage_started(target: Vector3, duration: float)
signal armor_assault_launched(units: Array)
signal aaa_umbrella_active(positions: Array)
signal nva_unit_spawned(unit: Node3D)
signal probing_attack_launched(target: Node3D)
signal flanking_maneuver_started(target: Node3D, direction: String)
signal forces_retreating(units: Array)
signal mortar_harassment_started(target: Vector3)
signal ambush_set(position: Vector3)
signal supply_convoy_dispatched(origin: Vector3, destination: Vector3)

# Strategic state machine
enum StrategicState {
	DEFENSIVE,           # Hold positions, probe only
	BUILDUP,             # Amassing forces for offensive
	OFFENSIVE,           # Active assault operations
	EXPLOITATION,        # Pursuing retreating enemy
	WITHDRAWAL,          # Retreating after failed offensive
}

var strategic_state: StrategicState = StrategicState.DEFENSIVE

# NVA resources
var manpower: int = 200
var armor_count: int = 5
var artillery_rounds: int = 100
var mortar_rounds: int = 200
var aaa_batteries: int = 3
var rocket_batteries: int = 2  # 122mm rockets
var sappers_available: int = 20

# Experience and morale
var unit_experience: float = 0.5  # 0-1, affects accuracy and morale
var overall_morale: float = 80.0  # 0-100
var casualties_sustained: int = 0

# Bases and positions
var forward_bases: Array[Node3D] = []
var artillery_positions: Array[Node3D] = []
var mortar_positions: Array[Node3D] = []
var armor_companies: Array[Node3D] = []
var aaa_positions: Array[Node3D] = []
var staging_areas: Array[Vector3] = []
var ambush_sites: Array[Dictionary] = []

# Active operations
var active_offensives: Array[Dictionary] = []
var active_barrages: Array[Dictionary] = []
var active_probes: Array[Dictionary] = []
var mortar_harassment_targets: Array[Dictionary] = []
var flanking_maneuvers: Array[Dictionary] = []

# Strategic state
var aggression_level: float = 0.5
var preparation_phase: bool = false
var assault_cooldown: float = 0.0
var probe_cooldown: float = 0.0
var mortar_cooldown: float = 0.0

# Intelligence
var known_enemy_positions: Array[Dictionary] = []
var firebase_intel: Dictionary = {}  # firebase -> {strength, supplies, last_updated}
var patrol_routes: Array[Dictionary] = []

# Timers
var reconnaissance_timer: float = 0.0
var resupply_timer: float = 0.0
var strategic_assessment_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemy_controllers")
	add_to_group("nva_forces")

	# Connect to battle signals
	BattleSignals.unit_died.connect(_on_unit_died)
	BattleSignals.firebase_established.connect(_on_firebase_established)

func _process(delta: float) -> void:
	_update_timers(delta)
	_update_strategic_state(delta)
	_process_barrages(delta)
	_process_active_operations(delta)
	_process_sapper_operations(delta)
	_process_probing_attacks(delta)
	_process_mortar_harassment(delta)
	_process_flanking_maneuvers(delta)
	_check_assault_opportunities()

func _update_timers(delta: float) -> void:
	reconnaissance_timer += delta
	resupply_timer += delta
	strategic_assessment_timer += delta

	if assault_cooldown > 0:
		assault_cooldown -= delta
	if probe_cooldown > 0:
		probe_cooldown -= delta
	if mortar_cooldown > 0:
		mortar_cooldown -= delta

	# Periodic reconnaissance
	if reconnaissance_timer > 30.0:
		reconnaissance_timer = 0.0
		_conduct_reconnaissance()

	# Resupply
	if resupply_timer > 300.0:
		resupply_timer = 0.0
		_resupply()

	# Strategic assessment
	if strategic_assessment_timer > 60.0:
		strategic_assessment_timer = 0.0
		_assess_strategic_situation()

func _update_strategic_state(delta: float) -> void:
	## Update strategic state based on current situation
	match strategic_state:
		StrategicState.DEFENSIVE:
			# Transition to buildup if resources sufficient
			if can_launch_offensive() and overall_morale > 60.0:
				strategic_state = StrategicState.BUILDUP
				preparation_phase = true

		StrategicState.BUILDUP:
			# Transition to offensive when ready
			if manpower >= 100 and artillery_rounds >= 50:
				strategic_state = StrategicState.OFFENSIVE
				preparation_phase = false

		StrategicState.OFFENSIVE:
			# Transition based on casualties
			if casualties_sustained > manpower * 0.3:
				# Heavy casualties - consider withdrawal
				if overall_morale < 40.0:
					strategic_state = StrategicState.WITHDRAWAL
			elif active_offensives.is_empty():
				strategic_state = StrategicState.DEFENSIVE

		StrategicState.WITHDRAWAL:
			# Recover and rebuild
			if overall_morale > 60.0 and casualties_sustained == 0:
				strategic_state = StrategicState.DEFENSIVE

func _assess_strategic_situation() -> void:
	## Assess overall strategic situation
	var enemy_strength := _estimate_enemy_strength()
	var our_strength := manpower + (armor_count * 20)

	# Adjust aggression based on force ratio
	var force_ratio := float(our_strength) / maxf(1.0, enemy_strength)

	if force_ratio > 2.0:
		aggression_level = minf(1.0, aggression_level + 0.1)
	elif force_ratio < 0.5:
		aggression_level = maxf(0.0, aggression_level - 0.1)

	# Update morale based on recent events
	if casualties_sustained > 0:
		overall_morale = maxf(0.0, overall_morale - casualties_sustained * 0.5)
		casualties_sustained = 0  # Reset counter

func _estimate_enemy_strength() -> float:
	var strength := 0.0

	for fb_data in firebase_intel.values():
		strength += fb_data.get("strength", 0)

	# Add known patrol units
	for pos_data in known_enemy_positions:
		strength += pos_data.get("estimated_strength", 10)

	return strength

func _on_unit_died(unit: Node3D, killer: Node3D) -> void:
	if unit.is_in_group("nva_units"):
		casualties_sustained += 1
		overall_morale = maxf(0.0, overall_morale - 2.0)

func _on_firebase_established(firebase: Node3D) -> void:
	# New firebase detected - update intel
	_update_firebase_intel(firebase)

# =============================================================================
# OFFENSIVE OPERATIONS
# =============================================================================

func launch_offensive(target: Node3D) -> void:
	## Launch coordinated offensive against target
	if assault_cooldown > 0:
		return

	var offensive := {
		"target": target,
		"phase": "preparation",
		"timer": 0.0,
		"infantry_battalions": [],
		"armor_support": [],
		"artillery_support": [],
	}

	# Phase 1: Artillery preparation
	var barrage_duration := 120.0  # 2 minutes
	call_artillery_barrage(target.global_position, barrage_duration)
	offensive.timer = barrage_duration

	# Phase 2: Activate AAA to deny air support
	_activate_aaa_umbrella()

	# Phase 3: Prepare assault forces
	offensive.infantry_battalions = _spawn_assault_force(2)  # 2 battalions
	if armor_count > 0:
		offensive.armor_support = _spawn_armor_support()

	active_offensives.append(offensive)
	assault_cooldown = 600.0  # 10 minute cooldown between offensives

	offensive_started.emit(target)
	BattleSignals.nva_offensive_started.emit(target)

func _check_assault_opportunities() -> void:
	# Look for weakened firebases to attack
	if assault_cooldown > 0 or preparation_phase:
		return

	var firebases := get_tree().get_nodes_in_group("firebases")

	for firebase_node: Node in firebases:
		var firebase := firebase_node as Node3D
		if not firebase:
			continue

		# Check if firebase is weakened
		if firebase.has_method("get_garrison_strength"):
			var strength: int = firebase.get_garrison_strength()
			if strength < 30 and randf() < aggression_level:
				launch_offensive(firebase)
				break

func _process_active_operations(delta: float) -> void:
	for offensive in active_offensives:
		offensive.timer -= delta

		match offensive.phase:
			"preparation":
				if offensive.timer <= 0:
					offensive.phase = "assault"
					_begin_assault(offensive)

			"assault":
				_process_assault(offensive, delta)

func _begin_assault(offensive: Dictionary) -> void:
	var target: Node3D = offensive.target
	if not is_instance_valid(target):
		return

	# Order all forces to attack
	for battalion in offensive.infantry_battalions:
		for unit in battalion:
			if is_instance_valid(unit) and unit.has_method("attack"):
				unit.attack(target)

	for armor in offensive.armor_support:
		if is_instance_valid(armor) and armor.has_method("attack"):
			armor.attack(target)

func _process_assault(offensive: Dictionary, delta: float) -> void:
	# Check assault progress
	var remaining_forces := 0

	for battalion in offensive.infantry_battalions:
		for unit in battalion:
			if is_instance_valid(unit):
				remaining_forces += 1

	for armor in offensive.armor_support:
		if is_instance_valid(armor):
			remaining_forces += 1

	# Assault failed if forces depleted
	if remaining_forces == 0:
		active_offensives.erase(offensive)

# =============================================================================
# ARTILLERY SYSTEM
# =============================================================================

func call_artillery_barrage(target: Vector3, duration: float) -> void:
	if artillery_rounds <= 0:
		return

	var barrage := {
		"target": target,
		"duration": duration,
		"timer": 0.0,
		"rounds_fired": 0,
		"interval": 2.0,  # Rounds every 2 seconds
	}

	active_barrages.append(barrage)

	artillery_barrage_started.emit(target, duration)
	BattleSignals.nva_artillery_barrage.emit(target, duration)

func _process_barrages(delta: float) -> void:
	var completed: Array[int] = []

	for i in range(active_barrages.size()):
		var barrage: Dictionary = active_barrages[i]
		barrage.timer += delta

		if barrage.timer >= barrage.duration:
			completed.append(i)
			continue

		# Fire rounds
		var rounds_due := int(barrage.timer / barrage.interval) - barrage.rounds_fired

		for j in range(rounds_due):
			if artillery_rounds <= 0:
				break

			_fire_artillery_round(barrage.target)
			barrage.rounds_fired += 1
			artillery_rounds -= 1

	for i in range(completed.size() - 1, -1, -1):
		active_barrages.remove_at(completed[i])

func _fire_artillery_round(target: Vector3) -> void:
	# Random dispersion
	var impact := target + Vector3(
		randf_range(-20, 20),
		0,
		randf_range(-20, 20)
	)

	# Apply damage
	CombatManager.apply_area_damage(impact, 15.0, 120.0, 80.0)

# =============================================================================
# ARMOR OPERATIONS
# =============================================================================

func _spawn_armor_support() -> Array[Node3D]:
	var armor_units: Array[Node3D] = []

	var count := mini(2, armor_count)
	armor_count -= count

	for i in range(count):
		var armor := _create_nva_unit(GameEnums.UnitType.NVA_ARMOR)
		if armor:
			# Spawn from forward base
			if not forward_bases.is_empty():
				var base: Node3D = forward_bases[0]
				armor.global_position = base.global_position + Vector3(
					randf_range(-10, 10), 0, randf_range(-10, 10)
				)
			get_tree().current_scene.add_child(armor)
			armor_units.append(armor)
			nva_unit_spawned.emit(armor)

	armor_assault_launched.emit(armor_units)
	BattleSignals.nva_armor_spotted.emit(armor_units[0].global_position if not armor_units.is_empty() else Vector3.ZERO, armor_units.size())

	return armor_units

# =============================================================================
# AAA UMBRELLA
# =============================================================================

func _activate_aaa_umbrella() -> void:
	## Activate all AAA positions to deny US air support
	var positions: Array[Vector3] = []

	for aaa in aaa_positions:
		if is_instance_valid(aaa):
			positions.append(aaa.global_position)
			if aaa.has_method("activate"):
				aaa.activate()

	if not positions.is_empty():
		aaa_umbrella_active.emit(positions)
		for pos in positions:
			BattleSignals.nva_aaa_active.emit(pos)

func add_aaa_position(position: Vector3) -> Node3D:
	var aaa := _create_nva_unit(GameEnums.UnitType.NVA_AAA)
	if aaa:
		aaa.global_position = position
		get_tree().current_scene.add_child(aaa)
		aaa_positions.append(aaa)
	return aaa

# =============================================================================
# FORCE SPAWNING
# =============================================================================

func _spawn_assault_force(battalion_count: int) -> Array:
	var battalions: Array = []

	for i in range(battalion_count):
		var battalion: Array[Node3D] = []
		var infantry_count := mini(40, manpower)  # ~40 men per battalion

		for j in range(infantry_count):
			var unit := _create_nva_unit(GameEnums.UnitType.NVA_INFANTRY)
			if unit:
				# Spawn from forward base
				if not forward_bases.is_empty():
					var base: Node3D = forward_bases[randi() % forward_bases.size()]
					unit.global_position = base.global_position + Vector3(
						randf_range(-20, 20), 0, randf_range(-20, 20)
					)
				get_tree().current_scene.add_child(unit)
				battalion.append(unit)
				nva_unit_spawned.emit(unit)
				manpower -= 1

		battalions.append(battalion)

	return battalions

func _create_nva_unit(unit_type: int) -> Node3D:
	var scenes := {
		GameEnums.UnitType.NVA_INFANTRY: "res://battle_system/nodes/nva_squad.tscn",
		GameEnums.UnitType.NVA_HEAVY_WEAPONS: "res://battle_system/nodes/nva_heavy.tscn",
		GameEnums.UnitType.NVA_ARMOR: "res://battle_system/nodes/nva_armor.tscn",
		GameEnums.UnitType.NVA_AAA: "res://battle_system/nodes/nva_aaa.tscn",
		GameEnums.UnitType.NVA_SAPPERS: "res://battle_system/nodes/nva_sappers.tscn",
	}

	var scene_path: String = scenes.get(unit_type, "")
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		# Create placeholder
		var placeholder := CharacterBody3D.new()
		placeholder.add_to_group("enemy_units")
		placeholder.add_to_group("nva_units")
		placeholder.set_meta("faction", GameEnums.Faction.NVA)
		return placeholder

	var scene := load(scene_path) as PackedScene
	return scene.instantiate()

# =============================================================================
# PROBING ATTACKS
# =============================================================================

func launch_probing_attack(target: Node3D) -> void:
	## Send small force to probe enemy defenses and gather intel
	if probe_cooldown > 0 or manpower < 10:
		return

	var probe_size := randi_range(5, 10)
	var probers: Array[Node3D] = []

	for i in range(probe_size):
		var unit := _create_nva_unit(GameEnums.UnitType.NVA_INFANTRY)
		if unit:
			if not forward_bases.is_empty():
				var base: Node3D = forward_bases[randi() % forward_bases.size()]
				unit.global_position = base.global_position + Vector3(
					randf_range(-15, 15), 0, randf_range(-15, 15)
				)
			get_tree().current_scene.add_child(unit)
			probers.append(unit)
			manpower -= 1

	var probe := {
		"target": target,
		"units": probers,
		"phase": "approach",
		"timer": 0.0,
		"intel_gathered": {},
		"casualties": 0,
	}

	active_probes.append(probe)
	probe_cooldown = 120.0  # 2 minute cooldown

	probing_attack_launched.emit(target)

func _process_probing_attacks(delta: float) -> void:
	var completed: Array[int] = []

	for i in range(active_probes.size()):
		var probe: Dictionary = active_probes[i]
		probe.timer += delta

		# Clean up dead units
		var alive: Array[Node3D] = []
		for unit in probe.units:
			if is_instance_valid(unit):
				alive.append(unit)
			else:
				probe.casualties += 1
		probe.units = alive

		if probe.units.is_empty():
			completed.append(i)
			_analyze_probe_results(probe)
			continue

		var target: Node3D = probe.target
		if not is_instance_valid(target):
			# Order retreat
			_order_probe_retreat(probe)
			completed.append(i)
			continue

		match probe.phase:
			"approach":
				_probe_approach(probe, delta)
				if probe.timer > 30.0:
					probe.phase = "engage"
					probe.timer = 0.0

			"engage":
				_probe_engage(probe, delta)
				# Retreat after brief engagement or heavy casualties
				if probe.timer > 20.0 or probe.casualties > len(probe.units) * 0.5:
					probe.phase = "retreat"
					probe.timer = 0.0

			"retreat":
				_probe_retreat(probe, delta)
				if probe.timer > 30.0:
					_analyze_probe_results(probe)
					completed.append(i)

	for i in range(completed.size() - 1, -1, -1):
		active_probes.remove_at(completed[i])

func _probe_approach(probe: Dictionary, delta: float) -> void:
	var target: Node3D = probe.target
	for unit in probe.units:
		if is_instance_valid(unit):
			var dir := (target.global_position - unit.global_position).normalized()
			unit.global_position += dir * 5.0 * delta

func _probe_engage(probe: Dictionary, delta: float) -> void:
	var target: Node3D = probe.target

	# Gather intel while engaging
	if target.has_method("get_garrison_strength"):
		probe.intel_gathered["garrison_strength"] = target.get_garrison_strength()
	if target.has_method("get_defensive_positions"):
		probe.intel_gathered["defensive_positions"] = target.get_defensive_positions()

	# Units fire at target
	for unit in probe.units:
		if is_instance_valid(unit) and unit.has_method("attack"):
			unit.attack(target)

func _probe_retreat(probe: Dictionary, delta: float) -> void:
	# Move back toward forward base
	if forward_bases.is_empty():
		return

	var retreat_point: Vector3 = forward_bases[0].global_position

	for unit in probe.units:
		if is_instance_valid(unit):
			var dir := (retreat_point - unit.global_position).normalized()
			unit.global_position += dir * 7.0 * delta

func _order_probe_retreat(probe: Dictionary) -> void:
	probe.phase = "retreat"
	probe.timer = 0.0
	forces_retreating.emit(probe.units)

func _analyze_probe_results(probe: Dictionary) -> void:
	## Update intel based on probe results
	var target: Node3D = probe.target
	if not is_instance_valid(target):
		return

	firebase_intel[target] = {
		"strength": probe.intel_gathered.get("garrison_strength", 0),
		"last_updated": Time.get_ticks_msec(),
		"probe_casualties": probe.casualties,
		"defensive_positions": probe.intel_gathered.get("defensive_positions", []),
	}

# =============================================================================
# MORTAR HARASSMENT
# =============================================================================

func start_mortar_harassment(target: Vector3, duration: float = 60.0) -> void:
	## Begin harassing fire on target position
	if mortar_cooldown > 0 or mortar_rounds < 10:
		return

	var harassment := {
		"target": target,
		"duration": duration,
		"timer": 0.0,
		"interval": 5.0,  # Rounds every 5 seconds
		"rounds_fired": 0,
	}

	mortar_harassment_targets.append(harassment)
	mortar_cooldown = 180.0  # 3 minute cooldown

	mortar_harassment_started.emit(target)

func _process_mortar_harassment(delta: float) -> void:
	var completed: Array[int] = []

	for i in range(mortar_harassment_targets.size()):
		var harassment: Dictionary = mortar_harassment_targets[i]
		harassment.timer += delta

		if harassment.timer >= harassment.duration or mortar_rounds <= 0:
			completed.append(i)
			continue

		# Fire rounds at interval
		var rounds_due := int(harassment.timer / harassment.interval) - harassment.rounds_fired

		for j in range(rounds_due):
			if mortar_rounds <= 0:
				break
			_fire_mortar_round(harassment.target)
			harassment.rounds_fired += 1
			mortar_rounds -= 1

	for i in range(completed.size() - 1, -1, -1):
		mortar_harassment_targets.remove_at(completed[i])

func _fire_mortar_round(target: Vector3) -> void:
	# Random dispersion (mortars less accurate than artillery)
	var impact := target + Vector3(
		randf_range(-30, 30),
		0,
		randf_range(-30, 30)
	)

	# Apply damage (lighter than artillery)
	CombatManager.apply_area_damage(impact, 10.0, 60.0, 50.0)

# =============================================================================
# FLANKING MANEUVERS
# =============================================================================

func execute_flanking_maneuver(target: Node3D, direction: String = "left") -> void:
	## Send force to attack from flank while main force engages front
	if manpower < 30:
		return

	var flank_force_size := mini(15, manpower / 3)
	var flankers: Array[Node3D] = []

	# Calculate flank position
	var target_pos := target.global_position
	var flank_offset := Vector3.ZERO

	match direction:
		"left":
			flank_offset = Vector3(-100, 0, 50)
		"right":
			flank_offset = Vector3(100, 0, 50)
		"rear":
			flank_offset = Vector3(0, 0, 100)

	var staging_pos := target_pos + flank_offset

	for i in range(flank_force_size):
		var unit := _create_nva_unit(GameEnums.UnitType.NVA_INFANTRY)
		if unit:
			if not forward_bases.is_empty():
				var base: Node3D = forward_bases[randi() % forward_bases.size()]
				unit.global_position = base.global_position
			get_tree().current_scene.add_child(unit)
			flankers.append(unit)
			manpower -= 1

	var maneuver := {
		"target": target,
		"units": flankers,
		"direction": direction,
		"staging_position": staging_pos,
		"phase": "approach",
		"timer": 0.0,
	}

	flanking_maneuvers.append(maneuver)
	flanking_maneuver_started.emit(target, direction)

func _process_flanking_maneuvers(delta: float) -> void:
	var completed: Array[int] = []

	for i in range(flanking_maneuvers.size()):
		var maneuver: Dictionary = flanking_maneuvers[i]
		maneuver.timer += delta

		# Clean up dead units
		var alive: Array[Node3D] = []
		for unit in maneuver.units:
			if is_instance_valid(unit):
				alive.append(unit)
		maneuver.units = alive

		if maneuver.units.is_empty():
			completed.append(i)
			continue

		var target: Node3D = maneuver.target
		if not is_instance_valid(target):
			completed.append(i)
			continue

		match maneuver.phase:
			"approach":
				# Move to staging position
				_move_units_to_position(maneuver.units, maneuver.staging_position, delta)
				if maneuver.timer > 45.0:
					maneuver.phase = "position"
					maneuver.timer = 0.0

			"position":
				# Get into assault position
				if maneuver.timer > 10.0:
					maneuver.phase = "assault"
					maneuver.timer = 0.0

			"assault":
				# Attack from flank
				for unit in maneuver.units:
					if is_instance_valid(unit) and unit.has_method("attack"):
						unit.attack(target)
				completed.append(i)

	for i in range(completed.size() - 1, -1, -1):
		flanking_maneuvers.remove_at(completed[i])

func _move_units_to_position(units: Array, position: Vector3, delta: float) -> void:
	for unit in units:
		if is_instance_valid(unit):
			var dir := (position - unit.global_position).normalized()
			unit.global_position += dir * 6.0 * delta

# =============================================================================
# RECONNAISSANCE & INTELLIGENCE
# =============================================================================

func _conduct_reconnaissance() -> void:
	# Gather intel on US positions
	var us_units := SpatialHashGrid.get_all_units_of_faction(GameEnums.Faction.US_ARMY)

	known_enemy_positions.clear()

	for unit in us_units:
		if is_instance_valid(unit):
			var pos_data := {
				"position": unit.global_position,
				"timestamp": Time.get_ticks_msec(),
				"estimated_strength": 10,  # Default estimate
			}

			if unit.has_method("get_squad_size"):
				pos_data.estimated_strength = unit.get_squad_size()

			known_enemy_positions.append(pos_data)

	# Update firebase intel
	var firebases := get_tree().get_nodes_in_group("firebases")
	for fb_node: Node in firebases:
		var firebase := fb_node as Node3D
		if firebase:
			_update_firebase_intel(firebase)

func _update_firebase_intel(firebase: Node3D) -> void:
	var intel := {
		"last_updated": Time.get_ticks_msec(),
		"strength": 0,
	}

	if firebase.has_method("get_garrison_strength"):
		intel.strength = firebase.get_garrison_strength()

	if firebase.has_method("get_supply_level"):
		intel["supplies"] = firebase.get_supply_level()

	if firebase.has_method("get_alert_level"):
		intel["alert_level"] = firebase.get_alert_level()

	firebase_intel[firebase] = intel

func _resupply() -> void:
	# Periodic resupply from Ho Chi Minh Trail
	var supply_amount := randi_range(10, 30)

	# Weather affects resupply
	if WeatherSystem.current_weather == GameEnums.WeatherCondition.MONSOON:
		supply_amount = int(supply_amount * 0.5)  # Rain slows logistics

	# Night is safer for resupply
	if WeatherSystem.is_night():
		supply_amount = int(supply_amount * 1.5)

	manpower += supply_amount
	mortar_rounds += randi_range(10, 30)
	artillery_rounds += randi_range(5, 15)
	armor_count += randi_range(0, 1)

	# Morale recovery
	overall_morale = minf(100.0, overall_morale + 5.0)

# =============================================================================
# BASE MANAGEMENT
# =============================================================================

func add_forward_base(base: Node3D) -> void:
	if base not in forward_bases:
		forward_bases.append(base)

func add_artillery_position(position: Node3D) -> void:
	if position not in artillery_positions:
		artillery_positions.append(position)


# =============================================================================
# SAPPER OPERATIONS
# =============================================================================

signal sapper_attack_launched(target: Node3D, sappers: Array)

var active_sapper_ops: Array[Dictionary] = []
var sapper_cooldown: float = 0.0

func launch_sapper_attack(target: Node3D) -> void:
	## Launch elite sapper attack on firebase
	if sapper_cooldown > 0 or manpower < 20:
		return

	var sapper_count := mini(6, manpower / 3)
	var sappers: Array[Node3D] = []

	for i in range(sapper_count):
		var sapper := _create_nva_unit(GameEnums.UnitType.NVA_SAPPERS)
		if sapper:
			# Sappers infiltrate from concealed positions
			var angle := TAU * float(i) / float(sapper_count)
			var infiltration_distance := 100.0
			sapper.global_position = target.global_position + Vector3(
				cos(angle) * infiltration_distance,
				0,
				sin(angle) * infiltration_distance
			)
			get_tree().current_scene.add_child(sapper)
			sappers.append(sapper)
			manpower -= 3  # Sappers are elite, cost more

	if sappers.is_empty():
		return

	var op := {
		"target": target,
		"sappers": sappers,
		"phase": "infiltration",
		"timer": 0.0,
	}

	active_sapper_ops.append(op)
	sapper_cooldown = 300.0  # 5 minute cooldown

	sapper_attack_launched.emit(target, sappers)
	BattleSignals.vc_sappers_breaching.emit(target)

func _process_sapper_operations(delta: float) -> void:
	sapper_cooldown -= delta

	var completed: Array[int] = []

	for i in range(active_sapper_ops.size()):
		var op: Dictionary = active_sapper_ops[i]
		op.timer += delta

		# Check for remaining sappers
		var alive_sappers: Array[Node3D] = []
		for sapper in op.sappers:
			if is_instance_valid(sapper):
				alive_sappers.append(sapper)
		op.sappers = alive_sappers

		if op.sappers.is_empty():
			completed.append(i)
			continue

		match op.phase:
			"infiltration":
				# Sappers move slowly toward target
				_sapper_infiltration(op, delta)
				if op.timer > 60.0:  # 1 minute infiltration
					op.phase = "breach"
					op.timer = 0.0

			"breach":
				# Sappers breach wire and place charges
				_sapper_breach(op, delta)

	for i in range(completed.size() - 1, -1, -1):
		active_sapper_ops.remove_at(completed[i])

func _sapper_infiltration(op: Dictionary, delta: float) -> void:
	var target: Node3D = op.target
	if not is_instance_valid(target):
		return

	for sapper in op.sappers:
		if not is_instance_valid(sapper):
			continue

		# Move slowly toward target
		var dir := (target.global_position - sapper.global_position).normalized()
		sapper.global_position += dir * 2.0 * delta  # Very slow, stealthy

func _sapper_breach(op: Dictionary, delta: float) -> void:
	var target: Node3D = op.target
	if not is_instance_valid(target):
		return

	for sapper in op.sappers:
		if not is_instance_valid(sapper):
			continue

		# Attack wire obstacles and structures
		var dist := sapper.global_position.distance_to(target.global_position)
		if dist < 10.0:
			# Plant charges/attack
			if sapper.has_method("attack"):
				sapper.attack(target)

# =============================================================================
# COMBINED ARMS TACTICS
# =============================================================================

func launch_human_wave(target: Node3D, wave_count: int = 3) -> void:
	## Classic NVA tactic - multiple waves of infantry
	for wave in range(wave_count):
		# Delay between waves
		get_tree().create_timer(wave * 30.0).timeout.connect(func():
			if not is_instance_valid(target):
				return

			var infantry := _spawn_infantry_wave(20)  # 20 men per wave
			for unit in infantry:
				if is_instance_valid(unit) and unit.has_method("attack"):
					unit.attack(target)
		)

func _spawn_infantry_wave(count: int) -> Array[Node3D]:
	var infantry: Array[Node3D] = []
	var actual_count := mini(count, manpower)

	for i in range(actual_count):
		var unit := _create_nva_unit(GameEnums.UnitType.NVA_INFANTRY)
		if unit:
			# Spawn from random forward base
			if not forward_bases.is_empty():
				var base: Node3D = forward_bases[randi() % forward_bases.size()]
				unit.global_position = base.global_position + Vector3(
					randf_range(-30, 30), 0, randf_range(-30, 30)
				)
			get_tree().current_scene.add_child(unit)
			infantry.append(unit)
			manpower -= 1

	return infantry

# =============================================================================
# STRATEGIC AI
# =============================================================================

func set_aggression(level: float) -> void:
	aggression_level = clampf(level, 0.0, 1.0)

func get_force_strength() -> Dictionary:
	return {
		"manpower": manpower,
		"armor": armor_count,
		"artillery_rounds": artillery_rounds,
		"aaa_batteries": aaa_batteries,
		"active_offensives": active_offensives.size(),
	}

func can_launch_offensive() -> bool:
	return assault_cooldown <= 0 and manpower >= 50 and artillery_rounds >= 20

func get_recommended_targets() -> Array[Node3D]:
	## Get list of vulnerable US positions
	var targets: Array[Node3D] = []
	var firebases := get_tree().get_nodes_in_group("firebases")

	for fb_node: Node in firebases:
		var firebase := fb_node as Node3D
		if not firebase:
			continue

		var score := 0.0

		# Prefer isolated firebases
		var nearby_friendly := SpatialHashGrid.get_all_units_of_faction(
			GameEnums.Faction.US_ARMY
		).filter(func(u): return u.global_position.distance_to(firebase.global_position) < 200)
		score -= nearby_friendly.size() * 5

		# Prefer weakened garrisons
		if firebase.has_method("get_garrison_strength"):
			var strength: int = firebase.get_garrison_strength()
			score -= strength

		# Prefer firebases with low supplies
		if firebase.has_method("get_supply_level"):
			var supplies: float = firebase.get_supply_level()
			if supplies < 30:
				score += 20

		if score > -50:  # Reasonable target
			targets.append(firebase)

	return targets
