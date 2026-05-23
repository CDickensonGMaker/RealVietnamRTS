extends Node
class_name AIDirector

## AI Director - Controls game pacing, difficulty scaling, and enemy coordination
## Manages tension cycles, wave timing, and strategic enemy decisions

signal difficulty_changed(new_level: float)
signal tension_phase_changed(phase: TensionPhase)
signal assault_ordered(target: Node3D, enemy_count: int)
signal retreat_ordered(reason: String)

enum TensionPhase { CALM, BUILDUP, ASSAULT, AFTERMATH }
enum GamePhase { EARLY, MID, LATE, ENDGAME }

## Difficulty settings
@export var base_difficulty: float = 1.0
@export var difficulty_scaling: float = 0.1  # Increase per minute
@export var max_difficulty: float = 3.0

## Tension cycle settings
@export var min_calm_duration: float = 30.0
@export var max_calm_duration: float = 90.0
@export var buildup_duration: float = 20.0
@export var assault_min_duration: float = 60.0
@export var aftermath_duration: float = 15.0

## Current state
var current_difficulty: float = 1.0
var tension_phase: TensionPhase = TensionPhase.CALM
var game_phase: GamePhase = GamePhase.EARLY
var game_time: float = 0.0
var phase_timer: float = 0.0
var current_phase_duration: float = 60.0

## Threat assessment
var player_strength: float = 1.0
var enemy_strength: float = 0.5
var player_firebase_count: int = 0
var player_unit_count: int = 0
var enemy_unit_count: int = 0

## Enemy controllers
var vc_controller: Node = null
var nva_controller: Node = null

## Strategic state
var assault_target: Node3D = null
var pending_reinforcements: int = 0
var successful_assaults: int = 0
var failed_assaults: int = 0

## L4D-style Stress System (PRD Phase 6)
var player_stress: float = 0.0  # 0.0 = relaxed, 1.0 = overwhelmed
var _recent_casualties: int = 0  # Casualties in last 30 seconds
var _casualty_timer: float = 0.0
var _firebase_under_attack: bool = false
var _supply_critical: bool = false
const STRESS_DECAY_RATE: float = 0.05  # Stress decays per second when conditions improve
const STRESS_CASUALTY_WEIGHT: float = 0.15  # Per casualty
const STRESS_FIREBASE_ATTACK_WEIGHT: float = 0.3
const STRESS_SUPPLY_CRITICAL_WEIGHT: float = 0.2
const STRESS_LOW_MORALE_WEIGHT: float = 0.25
const LOW_STRESS_THRESHOLD: float = 0.3  # Below this = player doing well
const HIGH_STRESS_THRESHOLD: float = 0.7  # Above this = ease off


func _ready() -> void:
	_find_controllers()
	_connect_stress_signals()
	_start_calm_phase()
	print("[AIDirector] Initialized - Difficulty %.1f, Stress System Active" % current_difficulty)


func _connect_stress_signals() -> void:
	"""Connect to signals that affect player stress"""
	if BattleSignals:
		BattleSignals.unit_died.connect(_on_player_unit_died)
		BattleSignals.firebase_under_attack.connect(_on_firebase_attacked)
		BattleSignals.supply_depleted.connect(_on_supply_depleted) if BattleSignals.has_signal("supply_depleted") else null
		BattleSignals.unit_routing.connect(_on_unit_routing)


func _on_player_unit_died(unit: Node3D, _killer: Node3D) -> void:
	"""Track player casualties for stress"""
	if unit.is_in_group("player_units"):
		_recent_casualties += 1
		player_stress = minf(player_stress + STRESS_CASUALTY_WEIGHT, 1.0)


func _on_firebase_attacked(firebase: Node3D, _attacker: Node3D) -> void:
	"""Firebase under attack increases stress"""
	_firebase_under_attack = true
	player_stress = minf(player_stress + STRESS_FIREBASE_ATTACK_WEIGHT, 1.0)


func _on_supply_depleted() -> void:
	"""Critical supply increases stress"""
	_supply_critical = true
	player_stress = minf(player_stress + STRESS_SUPPLY_CRITICAL_WEIGHT, 1.0)


func _on_unit_routing(unit: Node3D) -> void:
	"""Units routing increases stress"""
	if unit.is_in_group("player_units"):
		player_stress = minf(player_stress + STRESS_LOW_MORALE_WEIGHT, 1.0)


func _find_controllers() -> void:
	"""Find enemy AI controllers in scene"""
	var controllers: Array[Node] = get_tree().get_nodes_in_group("enemy_controllers")
	for ctrl in controllers:
		if ctrl.get_class() == "VCController" or ctrl.name.contains("VC"):
			vc_controller = ctrl
		elif ctrl.get_class() == "NVAController" or ctrl.name.contains("NVA"):
			nva_controller = ctrl

	# Also search by class name
	for child in get_tree().current_scene.get_children():
		if child is Node and child.get_script():
			var script_path: String = child.get_script().resource_path
			if "vc_controller" in script_path:
				vc_controller = child
			elif "nva_controller" in script_path:
				nva_controller = child


func _process(delta: float) -> void:
	game_time += delta
	phase_timer += delta

	# Update stress system (L4D-style)
	_update_stress(delta)

	# Update difficulty over time
	_update_difficulty(delta)

	# Update game phase
	_update_game_phase()

	# Assess battlefield
	_assess_battlefield()

	# Process tension cycle (adjusted by stress)
	_process_tension_cycle(delta)


func _update_stress(delta: float) -> void:
	"""Update player stress level based on current conditions"""
	# Decay casualty counter
	_casualty_timer += delta
	if _casualty_timer >= 30.0:
		_casualty_timer = 0.0
		_recent_casualties = 0

	# Calculate current stress factors
	var target_stress: float = 0.0

	# Factor 1: Recent casualties
	target_stress += minf(_recent_casualties * 0.1, 0.4)

	# Factor 2: Firebase health
	var firebases: Array[Node] = get_tree().get_nodes_in_group("firebases")
	var avg_firebase_health: float = 1.0
	if not firebases.is_empty():
		var total_health_ratio: float = 0.0
		for fb in firebases:
			if fb.has_method("get") and fb.get("current_health") != null:
				var ratio: float = fb.current_health / fb.total_health if fb.total_health > 0 else 1.0
				total_health_ratio += ratio
		avg_firebase_health = total_health_ratio / firebases.size()
		target_stress += (1.0 - avg_firebase_health) * 0.3

	# Factor 3: Unit health/morale
	var player_units: Array[Node] = get_tree().get_nodes_in_group("player_units")
	var broken_count: int = 0
	var low_health_count: int = 0
	for unit in player_units:
		if unit.has_method("is_morale_broken") and unit.is_morale_broken():
			broken_count += 1
		if unit.has_method("get") and unit.get("current_health") != null:
			var hp_ratio: float = unit.current_health / unit.max_health if unit.max_health > 0 else 1.0
			if hp_ratio < 0.3:
				low_health_count += 1

	if player_units.size() > 0:
		target_stress += float(broken_count) / float(player_units.size()) * 0.3
		target_stress += float(low_health_count) / float(player_units.size()) * 0.2

	# Factor 4: Enemy pressure
	if enemy_unit_count > player_unit_count * 1.5:
		target_stress += 0.2

	# Smoothly interpolate stress toward target
	if target_stress > player_stress:
		player_stress = minf(player_stress + delta * 0.2, target_stress)
	else:
		player_stress = maxf(player_stress - STRESS_DECAY_RATE * delta, target_stress)

	player_stress = clampf(player_stress, 0.0, 1.0)

	# Clear temporary flags
	_firebase_under_attack = false


func _update_difficulty(delta: float) -> void:
	"""Gradually increase difficulty"""
	var old_difficulty: float = current_difficulty

	# Time-based scaling
	current_difficulty = base_difficulty + (game_time / 60.0) * difficulty_scaling

	# Adjust based on player performance
	if player_strength > enemy_strength * 2.0:
		current_difficulty += 0.2  # Player dominating
	elif enemy_strength > player_strength * 2.0:
		current_difficulty -= 0.1  # Player struggling

	current_difficulty = clampf(current_difficulty, 0.5, max_difficulty)

	if abs(current_difficulty - old_difficulty) > 0.1:
		difficulty_changed.emit(current_difficulty)


func _update_game_phase() -> void:
	"""Update overall game phase based on time and state"""
	var old_phase: GamePhase = game_phase

	if game_time < 180.0:  # First 3 minutes
		game_phase = GamePhase.EARLY
	elif game_time < 600.0:  # 3-10 minutes
		game_phase = GamePhase.MID
	elif game_time < 1200.0:  # 10-20 minutes
		game_phase = GamePhase.LATE
	else:
		game_phase = GamePhase.ENDGAME

	if game_phase != old_phase:
		_on_game_phase_changed()


func _on_game_phase_changed() -> void:
	"""Handle game phase transitions"""
	match game_phase:
		GamePhase.MID:
			# Enable NVA involvement
			if nva_controller and nva_controller.has_method("set"):
				nva_controller.enable_waves = true
		GamePhase.LATE:
			# Increase enemy aggression
			if vc_controller and vc_controller.has_method("set"):
				vc_controller.aggression = 0.7
			if nva_controller and nva_controller.has_method("set"):
				nva_controller.aggression = 0.9
		GamePhase.ENDGAME:
			# All-out assault
			_order_final_assault()


func _assess_battlefield() -> void:
	"""Assess current battlefield state"""
	# Count player units
	var player_units: Array[Node] = get_tree().get_nodes_in_group("player_units")
	player_unit_count = 0
	var player_health_total: float = 0.0

	for unit in player_units:
		if is_instance_valid(unit):
			player_unit_count += 1
			if unit.has_method("get") and unit.get("current_health") != null:
				player_health_total += unit.current_health

	# Count enemy units
	var enemy_units: Array[Node] = get_tree().get_nodes_in_group("enemy_units")
	enemy_unit_count = 0
	var enemy_health_total: float = 0.0

	for unit in enemy_units:
		if is_instance_valid(unit):
			enemy_unit_count += 1
			if unit.has_method("get") and unit.get("current_health") != null:
				enemy_health_total += unit.current_health

	# Count firebases
	var firebases: Array[Node] = get_tree().get_nodes_in_group("firebases")
	player_firebase_count = firebases.size()

	# Calculate relative strengths
	player_strength = player_health_total + (player_firebase_count * 500.0)
	enemy_strength = enemy_health_total


func _process_tension_cycle(_delta: float) -> void:
	"""Process the tension/release cycle (stress-adjusted)"""
	# High stress = extend calm phases, delay assaults
	var stress_time_modifier: float = 1.0
	if player_stress > HIGH_STRESS_THRESHOLD:
		stress_time_modifier = 1.5  # 50% longer calm/aftermath when overwhelmed
	elif player_stress < LOW_STRESS_THRESHOLD:
		stress_time_modifier = 0.8  # 20% shorter calm when player is dominating

	var adjusted_duration: float = current_phase_duration * stress_time_modifier

	if phase_timer >= adjusted_duration:
		_advance_tension_phase()


func _advance_tension_phase() -> void:
	"""Move to next tension phase"""
	var old_phase: TensionPhase = tension_phase

	match tension_phase:
		TensionPhase.CALM:
			_start_buildup_phase()
		TensionPhase.BUILDUP:
			_start_assault_phase()
		TensionPhase.ASSAULT:
			_start_aftermath_phase()
		TensionPhase.AFTERMATH:
			_start_calm_phase()

	if tension_phase != old_phase:
		tension_phase_changed.emit(tension_phase)


func _start_calm_phase() -> void:
	"""Begin calm/recovery phase"""
	tension_phase = TensionPhase.CALM
	phase_timer = 0.0
	current_phase_duration = randf_range(min_calm_duration, max_calm_duration)

	# Reduce enemy aggression during calm
	_set_enemy_aggression(0.3)

	print("[AIDirector] Calm phase - %.0fs" % current_phase_duration)


func _start_buildup_phase() -> void:
	"""Begin buildup to assault"""
	tension_phase = TensionPhase.BUILDUP
	phase_timer = 0.0
	current_phase_duration = buildup_duration

	# Probe attacks, scouting
	_order_probing_attacks()

	# Gradually increase enemy presence
	_spawn_buildup_forces()

	print("[AIDirector] Buildup phase - assault incoming")


func _start_assault_phase() -> void:
	"""Begin main assault (stress-adjusted intensity)"""
	tension_phase = TensionPhase.ASSAULT
	phase_timer = 0.0

	# Duration based on difficulty
	current_phase_duration = assault_min_duration * current_difficulty

	# Select assault target
	assault_target = _select_assault_target()

	# Aggression scaled by inverse of stress (high stress = lighter attacks)
	var aggression: float = 0.9
	if player_stress > HIGH_STRESS_THRESHOLD:
		aggression = 0.5  # Lighter assault when player is overwhelmed
		print("[AIDirector] High stress detected (%.2f) - reducing assault intensity" % player_stress)
	elif player_stress < LOW_STRESS_THRESHOLD:
		aggression = 1.0  # Full assault when player is dominating
		print("[AIDirector] Low stress detected (%.2f) - full assault intensity" % player_stress)

	_set_enemy_aggression(aggression)

	# Order coordinated assault
	_order_main_assault()

	print("[AIDirector] ASSAULT PHASE - Target: %s, Stress: %.2f" % [
		assault_target.name if assault_target else "player",
		player_stress
	])


func _start_aftermath_phase() -> void:
	"""Begin aftermath/regrouping"""
	tension_phase = TensionPhase.AFTERMATH
	phase_timer = 0.0
	current_phase_duration = aftermath_duration

	# Evaluate assault success
	if enemy_unit_count < 3:
		failed_assaults += 1
	else:
		successful_assaults += 1

	# Pull back surviving forces
	_order_retreat()

	print("[AIDirector] Aftermath phase - regrouping")


func _set_enemy_aggression(level: float) -> void:
	"""Set aggression on all enemy controllers"""
	if vc_controller and vc_controller.has_method("set"):
		vc_controller.aggression = level * 0.8  # VC slightly less aggressive
	if nva_controller and nva_controller.has_method("set"):
		nva_controller.aggression = level


func _select_assault_target() -> Node3D:
	"""Select target for assault"""
	# Prioritize firebases
	var firebases: Array[Node] = get_tree().get_nodes_in_group("firebases")
	if not firebases.is_empty():
		# Pick weakest or most isolated firebase
		var best_target: Node3D = null
		var best_score: float = 0.0

		for fb in firebases:
			if not is_instance_valid(fb):
				continue

			var score: float = _evaluate_target(fb as Node3D)
			if score > best_score:
				best_score = score
				best_target = fb as Node3D

		if best_target:
			return best_target

	# Fallback: find player unit concentration
	var player_units: Array[Node] = get_tree().get_nodes_in_group("player_units")
	if not player_units.is_empty():
		return player_units[0] as Node3D

	return null


func _evaluate_target(target: Node3D) -> float:
	"""Evaluate how good a target is for assault"""
	var score: float = 1.0

	# Prefer damaged targets
	if target.has_method("get") and target.get("current_health") != null:
		var health_ratio: float = target.current_health / target.max_health if target.max_health > 0 else 1.0
		score += (1.0 - health_ratio) * 2.0

	# Prefer isolated targets (few friendly units nearby)
	if SpatialHashGrid:
		var nearby_friendlies: int = SpatialHashGrid.get_unit_count_in_area(
			target.global_position - Vector3(30, 0, 30),
			target.global_position + Vector3(30, 0, 30),
			GameEnums.Faction.US_ARMY
		)
		score += maxf(0.0, 3.0 - float(nearby_friendlies)) * 0.5

	return score


func _order_probing_attacks() -> void:
	"""Order small probing attacks during buildup"""
	if vc_controller and vc_controller.has_method("trigger_ambush"):
		# Small VC probing force
		var player_units: Array[Node] = get_tree().get_nodes_in_group("player_units")
		if not player_units.is_empty():
			var target_pos: Vector3 = player_units[0].global_position
			vc_controller.trigger_ambush(target_pos, 2)


func _spawn_buildup_forces() -> void:
	"""Spawn additional forces during buildup"""
	var spawn_count: int = int(3 * current_difficulty)

	if vc_controller and vc_controller.has_method("force_spawn_wave"):
		vc_controller.force_spawn_wave()

	if nva_controller and nva_controller.has_method("force_spawn_wave") and game_phase >= GamePhase.MID:
		nva_controller.force_spawn_wave()


func _order_main_assault() -> void:
	"""Order coordinated main assault"""
	var enemy_count: int = 0

	# VC launches ambush and tunnel attacks
	if vc_controller:
		if vc_controller.has_method("get_active_unit_count"):
			enemy_count += vc_controller.get_active_unit_count()

		# Trigger VC guerrilla actions
		if assault_target and vc_controller.has_method("launch_tunnel_attack"):
			vc_controller.launch_tunnel_attack(assault_target.global_position, 5)

		if vc_controller.has_method("place_trap_field") and assault_target:
			# Place traps around likely approach routes
			var trap_pos: Vector3 = assault_target.global_position + Vector3(
				randf_range(-30, 30), 0, randf_range(-30, 30)
			)
			vc_controller.place_trap_field(trap_pos, 15.0)

	# NVA launches conventional assault or siege
	if nva_controller and assault_target:
		if nva_controller.has_method("get_active_unit_count"):
			enemy_count += nva_controller.get_active_unit_count()

		# Choose between direct assault and siege based on force strength
		var nva_strength: int = nva_controller.get_active_unit_count() if nva_controller.has_method("get_active_unit_count") else 0

		if nva_strength >= 20 and nva_controller.has_method("initiate_siege"):
			# Launch full siege
			nva_controller.initiate_siege(assault_target)
		elif nva_controller.has_method("launch_assault"):
			nva_controller.launch_assault(assault_target.global_position)

	assault_ordered.emit(assault_target, enemy_count)

	if BattleSignals:
		BattleSignals.wave_incoming.emit(-1, enemy_count)
		if assault_target:
			BattleSignals.firebase_under_attack.emit(assault_target, null)


func _order_retreat() -> void:
	"""Order forces to pull back"""
	# Enemy controllers handle their own retreat logic
	retreat_ordered.emit("Assault concluded")


func _order_final_assault() -> void:
	"""Order final all-out assault in endgame"""
	print("[AIDirector] FINAL ASSAULT ORDERED")

	# Spawn maximum forces
	for i in 3:
		if vc_controller and vc_controller.has_method("force_spawn_wave"):
			vc_controller.force_spawn_wave()
		if nva_controller and nva_controller.has_method("force_spawn_wave"):
			nva_controller.force_spawn_wave()

	# Maximum aggression
	_set_enemy_aggression(1.0)


## Public API

func get_current_difficulty() -> float:
	return current_difficulty


func get_tension_phase_name() -> String:
	match tension_phase:
		TensionPhase.CALM:
			return "Calm"
		TensionPhase.BUILDUP:
			return "Buildup"
		TensionPhase.ASSAULT:
			return "Assault"
		TensionPhase.AFTERMATH:
			return "Aftermath"
	return "Unknown"


func get_game_phase_name() -> String:
	match game_phase:
		GamePhase.EARLY:
			return "Early Game"
		GamePhase.MID:
			return "Mid Game"
		GamePhase.LATE:
			return "Late Game"
		GamePhase.ENDGAME:
			return "Endgame"
	return "Unknown"


func force_assault() -> void:
	"""Force an immediate assault (for testing/events)"""
	_start_assault_phase()


func add_pressure(amount: float) -> void:
	"""Add pressure to speed up assault timing"""
	phase_timer += amount


func get_player_strength() -> float:
	return player_strength


func get_enemy_strength() -> float:
	return enemy_strength


func get_player_stress() -> float:
	"""Get current player stress level (0.0 = relaxed, 1.0 = overwhelmed)"""
	return player_stress


func get_stress_level_name() -> String:
	"""Get human-readable stress level"""
	if player_stress < LOW_STRESS_THRESHOLD:
		return "Relaxed"
	elif player_stress < 0.5:
		return "Moderate"
	elif player_stress < HIGH_STRESS_THRESHOLD:
		return "Stressed"
	else:
		return "Overwhelmed"
