extends Node
## class_name AIDirector  # ARCHIVED
## AIDirector - Controls enemy wave spawning, difficulty scaling, and threat assessment

signal wave_started(wave_number: int, enemy_count: int)
signal wave_completed(wave_number: int)
signal difficulty_changed(new_difficulty: float)
signal assault_incoming(target: Node3D, eta: float)
signal intel_updated(threat_level: float, intel_report: Dictionary)

# =============================================================================
# CONFIGURATION
# =============================================================================

@export_group("Wave Settings")
@export var base_wave_interval: float = 120.0  # Seconds between waves
@export var wave_interval_variance: float = 30.0  # Random variance
@export var min_wave_interval: float = 60.0
@export var max_wave_size: int = 50
@export var initial_wave_size: int = 8

@export_group("Difficulty")
@export var starting_difficulty: float = 1.0
@export var difficulty_ramp_per_wave: float = 0.15
@export var max_difficulty: float = 5.0
@export var player_advantage_threshold: float = 0.7  # Backs off if player too weak

@export_group("Enemy Composition")
@export var vc_to_nva_ratio: float = 0.7  # 70% VC, 30% NVA at start
@export var nva_introduction_wave: int = 5  # NVA appears after wave 5
@export var elite_chance_per_difficulty: float = 0.05

# =============================================================================
# STATE
# =============================================================================

var current_wave: int = 0
var current_difficulty: float = 1.0
var wave_timer: float = 0.0
var next_wave_time: float = 0.0

var active_enemies: Array[Node3D] = []
var player_firebase: Node3D = null
var player_strength: float = 1.0
var enemy_strength: float = 0.0

var threat_level: float = 0.0
var intel_accuracy: float = 0.5  # How accurate our intel is

var is_active: bool = false
var wave_in_progress: bool = false

# Assault planning
var planned_assaults: Array[Dictionary] = []

# Controllers
var vc_controller: VCController
var nva_controller: Node  # NVAController

func _ready() -> void:
	# Find controllers
	vc_controller = _find_controller("vc_controller")
	nva_controller = _find_controller("nva_controller")

	# Connect to signals
	BattleSignals.unit_died.connect(_on_unit_died)
	BattleSignals.firebase_established.connect(_on_firebase_established)

func _process(delta: float) -> void:
	if not is_active:
		return

	wave_timer += delta

	# Update threat assessment
	_update_threat_assessment()

	# Check for wave spawning
	if not wave_in_progress and wave_timer >= next_wave_time:
		_start_next_wave()

	# Process planned assaults
	_process_planned_assaults(delta)

	# Cleanup dead enemies
	_cleanup_dead_enemies()


# =============================================================================
# DIRECTOR CONTROL
# =============================================================================

func start(firebase: Node3D) -> void:
	player_firebase = firebase
	is_active = true
	current_wave = 0
	current_difficulty = starting_difficulty

	# Schedule first wave
	next_wave_time = base_wave_interval * 0.5  # First wave comes sooner
	wave_timer = 0.0


func stop() -> void:
	is_active = false


func pause() -> void:
	is_active = false


func resume() -> void:
	is_active = true


func set_difficulty(new_difficulty: float) -> void:
	current_difficulty = clampf(new_difficulty, 0.5, max_difficulty)
	difficulty_changed.emit(current_difficulty)


# =============================================================================
# WAVE MANAGEMENT
# =============================================================================

func _start_next_wave() -> void:
	current_wave += 1
	wave_in_progress = true

	# Calculate wave composition
	var wave_size := _calculate_wave_size()
	var composition := _calculate_wave_composition(wave_size)

	# Spawn enemies
	var spawned := _spawn_wave(composition)
	active_enemies.append_array(spawned)

	# Update difficulty for next wave
	current_difficulty = minf(max_difficulty, current_difficulty + difficulty_ramp_per_wave)

	# Schedule next wave
	var interval := base_wave_interval - (current_difficulty * 5.0)
	interval += randf_range(-wave_interval_variance, wave_interval_variance)
	next_wave_time = wave_timer + maxf(min_wave_interval, interval)

	wave_started.emit(current_wave, spawned.size())
	BattleSignals.hud_message.emit("Wave %d incoming!" % current_wave, 3.0)


func _calculate_wave_size() -> int:
	var base_size := initial_wave_size + int(current_wave * 2)
	var difficulty_bonus := int(current_difficulty * 3)
	var variance := randi_range(-2, 3)

	# Scale back if player is weak
	var strength_ratio := player_strength / maxf(0.1, enemy_strength + player_strength)
	if strength_ratio < player_advantage_threshold:
		base_size = int(base_size * 0.7)

	return clampi(base_size + difficulty_bonus + variance, 3, max_wave_size)


func _calculate_wave_composition(total_size: int) -> Dictionary:
	var composition := {
		"vc_infantry": 0,
		"vc_sappers": 0,
		"vc_mortar": 0,
		"vc_local": 0,
		"nva_infantry": 0,
		"nva_heavy": 0,
		"nva_sappers": 0,
	}

	# Base VC ratio, decreasing as NVA shows up
	var vc_ratio := vc_to_nva_ratio
	if current_wave >= nva_introduction_wave:
		vc_ratio = maxf(0.3, vc_ratio - (current_wave - nva_introduction_wave) * 0.05)

	var vc_count := int(total_size * vc_ratio)
	var nva_count := total_size - vc_count

	# VC composition
	composition.vc_infantry = int(vc_count * 0.6)
	composition.vc_sappers = int(vc_count * 0.15)
	composition.vc_mortar = int(vc_count * 0.1)
	composition.vc_local = vc_count - composition.vc_infantry - composition.vc_sappers - composition.vc_mortar

	# NVA composition (if applicable)
	if current_wave >= nva_introduction_wave:
		composition.nva_infantry = int(nva_count * 0.7)
		composition.nva_heavy = int(nva_count * 0.2)
		composition.nva_sappers = nva_count - composition.nva_infantry - composition.nva_heavy

	return composition


func _spawn_wave(composition: Dictionary) -> Array[Node3D]:
	var spawned: Array[Node3D] = []

	if not player_firebase:
		return spawned

	# Determine spawn points (tunnels for VC, edges for NVA)
	var firebase_pos := player_firebase.global_position

	# Spawn VC from tunnels or jungle edges
	for type in ["vc_infantry", "vc_sappers", "vc_mortar", "vc_local"]:
		var count: int = composition[type]
		for i in range(count):
			var spawn_pos := _get_vc_spawn_position(firebase_pos)
			var unit := _spawn_enemy(_get_unit_type_for_key(type), spawn_pos)
			if unit:
				spawned.append(unit)

	# Spawn NVA from map edges (more conventional approach)
	for type in ["nva_infantry", "nva_heavy", "nva_sappers"]:
		var count: int = composition[type]
		for i in range(count):
			var spawn_pos := _get_nva_spawn_position(firebase_pos)
			var unit := _spawn_enemy(_get_unit_type_for_key(type), spawn_pos)
			if unit:
				spawned.append(unit)

	return spawned


func _get_unit_type_for_key(key: String) -> int:
	match key:
		"vc_infantry": return GameEnums.UnitType.VC_INFANTRY
		"vc_sappers": return GameEnums.UnitType.VC_SAPPERS
		"vc_mortar": return GameEnums.UnitType.VC_MORTAR
		"vc_local": return GameEnums.UnitType.VC_LOCAL_FORCE
		"nva_infantry": return GameEnums.UnitType.NVA_INFANTRY
		"nva_heavy": return GameEnums.UnitType.NVA_HEAVY_WEAPONS
		"nva_sappers": return GameEnums.UnitType.NVA_SAPPERS
		_: return GameEnums.UnitType.VC_INFANTRY


func _get_vc_spawn_position(target: Vector3) -> Vector3:
	# Try to spawn from tunnel
	if vc_controller:
		var tunnel := vc_controller.get_tunnel_near(target, 200.0)
		if tunnel:
			return tunnel.global_position + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))

	# Spawn from jungle edge
	var angle := randf() * TAU
	var distance := randf_range(80.0, 150.0)
	return target + Vector3(cos(angle) * distance, 0, sin(angle) * distance)


func _get_nva_spawn_position(target: Vector3) -> Vector3:
	# NVA comes from map edge in formation
	var angle := randf() * TAU
	var distance := randf_range(150.0, 250.0)
	return target + Vector3(cos(angle) * distance, 0, sin(angle) * distance)


func _spawn_enemy(unit_type: int, position: Vector3) -> Node3D:
	var unit_data := VietnamUnitData.get_unit_data(unit_type)
	var squad := Squad.new()
	squad.unit_data = unit_data
	squad.global_position = position

	# Add to scene
	var enemy_container := get_tree().current_scene.get_node_or_null("GameWorld/Units/EnemyUnits")
	if enemy_container:
		enemy_container.add_child(squad)
	else:
		get_tree().current_scene.add_child(squad)

	# Give attack order toward firebase
	if player_firebase:
		squad.move_to(player_firebase.global_position)

	return squad


# =============================================================================
# THREAT ASSESSMENT
# =============================================================================

func _update_threat_assessment() -> void:
	# Calculate player strength
	player_strength = _calculate_faction_strength(GameEnums.Faction.US_ARMY)

	# Calculate enemy strength
	enemy_strength = 0.0
	for enemy in active_enemies:
		if is_instance_valid(enemy) and enemy.has_method("get_squad_size"):
			enemy_strength += enemy.get_squad_size()

	# Calculate threat level (0.0 to 1.0)
	var total := player_strength + enemy_strength
	if total > 0:
		threat_level = enemy_strength / total
	else:
		threat_level = 0.0

	# Check if wave is complete
	if wave_in_progress and active_enemies.is_empty():
		wave_in_progress = false
		wave_completed.emit(current_wave)


func _calculate_faction_strength(faction: int) -> float:
	var units := SpatialHashGrid.get_all_units_of_faction(faction)
	var strength := 0.0

	for unit in units:
		if is_instance_valid(unit):
			if unit.has_method("get_squad_size"):
				strength += unit.get_squad_size()

			# Bonus for garrisoned units
			if unit.has_method("get_cover_level"):
				var cover: String = unit.get_cover_level()
				if cover != "none":
					strength *= 1.2

	return strength


func get_intel_report() -> Dictionary:
	var report := {
		"threat_level": threat_level,
		"active_enemies": active_enemies.size(),
		"estimated_enemy_strength": enemy_strength * (0.8 + randf() * 0.4) * intel_accuracy,
		"current_wave": current_wave,
		"next_wave_eta": maxf(0.0, next_wave_time - wave_timer),
		"difficulty": current_difficulty,
	}

	intel_updated.emit(threat_level, report)
	return report


# =============================================================================
# ASSAULT PLANNING
# =============================================================================

func plan_assault(target: Node3D, force_size: int, delay: float) -> void:
	var assault := {
		"target": target,
		"force_size": force_size,
		"timer": delay,
		"phase": "planning",
	}
	planned_assaults.append(assault)
	assault_incoming.emit(target, delay)


func _process_planned_assaults(delta: float) -> void:
	var completed: Array[int] = []

	for i in range(planned_assaults.size()):
		var assault: Dictionary = planned_assaults[i]
		assault.timer -= delta

		if assault.timer <= 0 and assault.phase == "planning":
			_execute_assault(assault)
			completed.append(i)

	for i in range(completed.size() - 1, -1, -1):
		planned_assaults.remove_at(completed[i])


func _execute_assault(assault: Dictionary) -> void:
	var target: Node3D = assault.target
	if not is_instance_valid(target):
		return

	# Spawn assault force
	var composition := {"nva_infantry": int(assault.force_size * 0.7), "nva_sappers": int(assault.force_size * 0.3)}
	var force := _spawn_wave(composition)

	# Artillery barrage first (if NVA)
	if nva_controller and nva_controller.has_method("call_artillery"):
		nva_controller.call_artillery(target.global_position, 30.0)
		BattleSignals.nva_artillery_barrage.emit(target.global_position, 30.0)

	# Direct force to attack
	for unit in force:
		if unit.has_method("attack"):
			unit.attack(target)

	active_enemies.append_array(force)


# =============================================================================
# CLEANUP
# =============================================================================

func _cleanup_dead_enemies() -> void:
	var alive: Array[Node3D] = []
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			alive.append(enemy)
	active_enemies = alive


func _on_unit_died(unit: Node3D, _killer: Node3D) -> void:
	active_enemies.erase(unit)


func _on_firebase_established(firebase: Node3D) -> void:
	if not player_firebase:
		player_firebase = firebase


func _find_controller(group_name: String) -> Node:
	var controllers := get_tree().get_nodes_in_group(group_name)
	if controllers.size() > 0:
		return controllers[0]
	return null


# =============================================================================
# DEBUG
# =============================================================================

func get_debug_info() -> Dictionary:
	return {
		"wave": current_wave,
		"difficulty": current_difficulty,
		"active_enemies": active_enemies.size(),
		"player_strength": player_strength,
		"enemy_strength": enemy_strength,
		"threat_level": threat_level,
		"next_wave_in": maxf(0.0, next_wave_time - wave_timer),
		"planned_assaults": planned_assaults.size(),
	}
