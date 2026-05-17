extends EnemyAIController
class_name NVAController

## North Vietnamese Army AI Controller
## Conventional tactics: massed infantry, coordinated attacks, artillery support
## Siege operations, sapper assaults, AA umbrella, human wave attacks

const SquadDataScript = preload("res://battle_system/data/squad_data.gd")
const SapperTeam = preload("res://battle_system/ai/sapper_team.gd")
const AAEmplacement = preload("res://battle_system/ai/aa_emplacement.gd")
const SiegeManager = preload("res://battle_system/ai/siege_manager.gd")

signal human_wave_launched(position: Vector3, count: int)
signal artillery_barrage_called(position: Vector3)
signal sapper_assault_launched(count: int)
signal aa_umbrella_established(position: Vector3)
signal siege_initiated(target: Node3D)

enum StrategicState {
	BUILDUP,           # Accumulating forces
	PROBING,           # Testing defenses
	ARTILLERY_PREP,    # Softening target
	MAIN_ASSAULT,      # Full attack
	EXPLOITATION,      # Following up success
	WITHDRAWAL,        # Retreating
}

## NVA-specific settings
@export var coordination_radius: float = 25.0
@export var artillery_support: bool = true
@export var artillery_cooldown: float = 45.0
@export var min_attack_group_size: int = 3
@export var human_wave_threshold: int = 15   # Units needed for human wave
@export var sapper_teams_max: int = 3
@export var aa_positions_max: int = 4

## Strategic state
var strategic_state: StrategicState = StrategicState.BUILDUP
var _state_timer: float = 0.0

## Timing
var artillery_timer: float = 0.0
var reconnaissance_timer: float = 0.0
var resupply_timer: float = 0.0
var strategic_assessment_timer: float = 0.0

## Force composition
var infantry_units: Array[Node3D] = []
var sapper_teams: Array[Node3D] = []
var aa_emplacements: Array[Node3D] = []
var mortar_teams: Array[Node3D] = []

## Siege management
var siege_manager: SiegeManager = null
var active_siege: RefCounted = null

## Unit data for spawning
var nva_infantry_data: Resource = null
var nva_heavy_weapons_data: Resource = null

## Target tracking
var primary_target: Node3D = null
var target_firebase: Node3D = null


func _ready() -> void:
	faction = GameEnums.Faction.NVA
	aggression = 0.8
	detection_range = 50.0
	attack_range = 30.0
	retreat_health_threshold = 0.2  # NVA holds longer

	# Larger waves for conventional warfare
	units_per_wave = 10
	wave_interval = 50.0

	# Load unit data
	_load_unit_data()

	# Set spawn points - NVA attacks from concentrated direction
	spawn_points = [
		Vector3(30, 0, -5),
		Vector3(30, 0, 0),
		Vector3(30, 0, 5),
		Vector3(35, 0, -3),
		Vector3(35, 0, 3),
		Vector3(40, 0, 0),
	]

	# Create siege manager
	siege_manager = SiegeManager.new()
	add_child(siege_manager)
	siege_manager.human_wave_launched.connect(_on_siege_human_wave)
	siege_manager.siege_broken.connect(_on_siege_broken)

	super._ready()
	print("[NVAController] Initialized - Conventional tactics, siege warfare enabled")


func _load_unit_data() -> void:
	"""Load NVA unit data resources"""
	# Try to load NVA-specific data, fallback to VC
	var infantry_path := "res://battle_system/data/units/nva_infantry.tres"
	var heavy_path := "res://battle_system/data/units/nva_heavy_weapons.tres"

	if ResourceLoader.exists(infantry_path):
		nva_infantry_data = load(infantry_path)
	else:
		nva_infantry_data = load("res://battle_system/data/units/vc_infantry.tres")

	if ResourceLoader.exists(heavy_path):
		nva_heavy_weapons_data = load(heavy_path)
	else:
		nva_heavy_weapons_data = nva_infantry_data


func _process(delta: float) -> void:
	super._process(delta)

	_state_timer += delta
	artillery_timer += delta
	reconnaissance_timer += delta
	strategic_assessment_timer += delta

	# Strategic assessment
	if strategic_assessment_timer >= 15.0:
		strategic_assessment_timer = 0.0
		_assess_strategic_situation()

	# State-specific processing
	match strategic_state:
		StrategicState.BUILDUP:
			_process_buildup(delta)
		StrategicState.PROBING:
			_process_probing(delta)
		StrategicState.ARTILLERY_PREP:
			_process_artillery_prep(delta)
		StrategicState.MAIN_ASSAULT:
			_process_main_assault(delta)
		StrategicState.EXPLOITATION:
			_process_exploitation(delta)
		StrategicState.WITHDRAWAL:
			_process_withdrawal(delta)


func _assess_strategic_situation() -> void:
	"""Assess the strategic situation and potentially change state"""
	var our_strength: int = controlled_units.size()
	var enemy_strength: int = _count_enemy_strength()

	# Find target firebase if we don't have one
	if not is_instance_valid(target_firebase):
		_find_target_firebase()

	match strategic_state:
		StrategicState.BUILDUP:
			# Ready to attack when we have enough forces
			if our_strength >= human_wave_threshold:
				_change_state(StrategicState.PROBING)

		StrategicState.PROBING:
			# After probing, prepare artillery
			if _state_timer >= 30.0:
				if artillery_support and our_strength >= human_wave_threshold:
					_change_state(StrategicState.ARTILLERY_PREP)
				elif our_strength >= human_wave_threshold * 0.7:
					_change_state(StrategicState.MAIN_ASSAULT)

		StrategicState.ARTILLERY_PREP:
			# After artillery prep, assault
			if _state_timer >= 45.0:
				_change_state(StrategicState.MAIN_ASSAULT)

		StrategicState.MAIN_ASSAULT:
			# Check assault progress
			if our_strength < human_wave_threshold * 0.3:
				_change_state(StrategicState.WITHDRAWAL)
			elif not is_instance_valid(target_firebase):
				_change_state(StrategicState.EXPLOITATION)

		StrategicState.EXPLOITATION:
			# After exploitation, rebuild
			if _state_timer >= 60.0:
				_change_state(StrategicState.BUILDUP)

		StrategicState.WITHDRAWAL:
			# After withdrawal, rebuild
			if _state_timer >= 90.0:
				_change_state(StrategicState.BUILDUP)


func _change_state(new_state: StrategicState) -> void:
	"""Change strategic state"""
	var old_state: StrategicState = strategic_state
	strategic_state = new_state
	_state_timer = 0.0

	print("[NVAController] State change: %s -> %s" % [
		StrategicState.keys()[old_state],
		StrategicState.keys()[new_state]
	])


func _process_buildup(delta: float) -> void:
	"""Accumulate forces for assault"""
	# Spawn additional units if below threshold
	if controlled_units.size() < human_wave_threshold:
		# Increase spawn rate during buildup
		wave_timer += delta * 0.5  # 50% faster spawning

	# Deploy AA positions
	if aa_emplacements.size() < aa_positions_max:
		if _state_timer >= 20.0 and aa_emplacements.size() == 0:
			_deploy_aa_position()

	# Create sapper teams
	if sapper_teams.size() < sapper_teams_max:
		if _state_timer >= 30.0 and sapper_teams.size() == 0:
			_spawn_sapper_team()


func _process_probing(delta: float) -> void:
	"""Send probing attacks to test defenses"""
	# Send small groups to probe
	if _state_timer >= 10.0 and _state_timer < 12.0:
		_launch_probing_attack()


func _process_artillery_prep(delta: float) -> void:
	"""Soften target with artillery"""
	# Call artillery on target
	if artillery_timer >= artillery_cooldown:
		artillery_timer = 0.0
		_call_artillery_on_target()


func _process_main_assault(delta: float) -> void:
	"""Coordinate main assault"""
	# Launch human wave
	if _state_timer < 2.0 and _state_timer > 0.0:
		_launch_human_wave()

	# Send in sappers
	if _state_timer >= 5.0 and _state_timer < 7.0:
		_launch_sapper_assault()

	# Continue waves
	if int(_state_timer) % 30 == 0 and int(_state_timer) > 0:
		if controlled_units.size() >= human_wave_threshold * 0.5:
			_launch_human_wave()


func _process_exploitation(delta: float) -> void:
	"""Follow up successful assault"""
	# Move all units to captured position
	if is_instance_valid(target_firebase):
		for unit in controlled_units:
			if is_instance_valid(unit) and unit.has_method("move_to"):
				unit.move_to(target_firebase.global_position)


func _process_withdrawal(delta: float) -> void:
	"""Withdraw forces"""
	# Order retreat
	for unit in controlled_units:
		if is_instance_valid(unit):
			_order_retreat(unit)


func _update_unit_ai(unit: Node3D) -> void:
	"""NVA-specific AI - coordinated attacks"""
	# Skip if already in combat during assault
	if unit.state == Squad.State.COMBAT and strategic_state == StrategicState.MAIN_ASSAULT:
		return  # Let them fight

	# Use coordinated behavior
	if strategic_state in [StrategicState.MAIN_ASSAULT, StrategicState.PROBING]:
		var target: Node3D = _find_nearest_player_unit(unit)
		if not target:
			return

		var distance: float = unit.global_position.distance_to(target.global_position)

		# Attack when detected
		if distance <= detection_range:
			var nearby_count: int = _count_nearby_friendlies(unit)

			if nearby_count >= min_attack_group_size or distance <= attack_range * 0.5:
				if unit.has_method("attack"):
					unit.attack(target)
					_coordinate_nearby_attack(unit, target)
			else:
				# Advance toward target
				var approach_pos: Vector3 = unit.global_position.lerp(target.global_position, 0.4)
				if unit.has_method("move_to"):
					unit.move_to(approach_pos)
	else:
		super._update_unit_ai(unit)


func _count_nearby_friendlies(unit: Node3D) -> int:
	"""Count friendly units within coordination radius"""
	var count: int = 0
	for friendly in controlled_units:
		if friendly == unit or not is_instance_valid(friendly):
			continue
		if friendly.state == Squad.State.DEAD:
			continue
		if unit.global_position.distance_to(friendly.global_position) <= coordination_radius:
			count += 1
	return count


func _coordinate_nearby_attack(leader: Node3D, target: Node3D) -> void:
	"""Order all nearby units to attack the same target"""
	for unit in controlled_units:
		if unit == leader or not is_instance_valid(unit):
			continue
		if unit.state == Squad.State.DEAD or unit.state == Squad.State.COMBAT:
			continue
		if leader.global_position.distance_to(unit.global_position) <= coordination_radius:
			if unit.has_method("attack"):
				unit.attack(target)


func _count_enemy_strength() -> int:
	"""Estimate enemy strength"""
	var player_units: Array[Node] = get_tree().get_nodes_in_group("player_units")
	var count: int = 0
	for unit in player_units:
		if is_instance_valid(unit):
			if unit.has_method("get") and unit.get("state") != Squad.State.DEAD:
				count += 1
	return count


func _find_target_firebase() -> void:
	"""Find a firebase to target"""
	var firebases: Array[Node] = get_tree().get_nodes_in_group("firebases")
	if not firebases.is_empty():
		target_firebase = firebases[0] as Node3D
		print("[NVAController] Target firebase: %s" % target_firebase.name)


func _launch_human_wave() -> void:
	"""Launch massed infantry assault"""
	if not is_instance_valid(target_firebase):
		_find_target_firebase()
		if not is_instance_valid(target_firebase):
			return

	var target_pos: Vector3 = target_firebase.global_position
	var attacking: int = 0

	for unit in controlled_units:
		if not is_instance_valid(unit) or unit.state == Squad.State.DEAD:
			continue

		# All units charge
		if unit.has_method("move_to"):
			unit.move_to(target_pos)
		attacking += 1

		# Attack any enemies in path
		var nearest: Node3D = _find_nearest_player_unit(unit)
		if nearest and unit.has_method("attack"):
			var dist: float = unit.global_position.distance_to(nearest.global_position)
			if dist < detection_range:
				unit.attack(nearest)

	human_wave_launched.emit(target_pos, attacking)

	if BattleSignals:
		BattleSignals.wave_incoming.emit(-2, attacking)  # -2 = human wave

	print("[NVAController] Human wave launched: %d units" % attacking)


func _launch_probing_attack() -> void:
	"""Send small group to probe defenses"""
	var probe_size: int = mini(3, controlled_units.size())
	var probing: Array[Node3D] = []

	for i in probe_size:
		if i < controlled_units.size():
			probing.append(controlled_units[i])

	if not is_instance_valid(target_firebase):
		return

	for unit in probing:
		if is_instance_valid(unit) and unit.has_method("move_to"):
			unit.move_to(target_firebase.global_position)

	print("[NVAController] Probing attack: %d units" % probing.size())


func _call_artillery_on_target() -> void:
	"""Call artillery strike on target"""
	if not CombatManager:
		return

	var target_pos: Vector3 = Vector3.ZERO

	if is_instance_valid(target_firebase):
		target_pos = target_firebase.global_position
	else:
		# Find cluster of player units
		var player_units: Array[Node] = get_tree().get_nodes_in_group("player_units")
		if player_units.is_empty():
			return

		var center: Vector3 = Vector3.ZERO
		var valid_count: int = 0
		for unit in player_units:
			if is_instance_valid(unit) and unit.state != Squad.State.DEAD:
				center += unit.global_position
				valid_count += 1

		if valid_count == 0:
			return
		target_pos = center / float(valid_count)

	# Add scatter
	target_pos += Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))

	artillery_barrage_called.emit(target_pos)
	CombatManager.call_artillery_strike(target_pos, "mortar_82mm", 8, null, GameEnums.Faction.NVA)

	print("[NVAController] Artillery barrage on %s" % target_pos)


func _launch_sapper_assault() -> void:
	"""Send sappers to breach perimeter"""
	if sapper_teams.is_empty():
		return

	if not is_instance_valid(target_firebase):
		return

	var sappers_sent: int = 0

	for sapper in sapper_teams:
		if is_instance_valid(sapper) and sapper.is_alive():
			sapper.set_target_position(target_firebase.global_position)
			sappers_sent += 1

	if sappers_sent > 0:
		sapper_assault_launched.emit(sappers_sent)
		print("[NVAController] Sapper assault: %d teams" % sappers_sent)


func _deploy_aa_position() -> void:
	"""Deploy anti-aircraft emplacement"""
	if not is_instance_valid(target_firebase):
		return

	# Position AA between spawn and target
	var spawn_center: Vector3 = Vector3.ZERO
	for sp in spawn_points:
		spawn_center += sp
	spawn_center /= float(spawn_points.size())

	var aa_pos: Vector3 = spawn_center.lerp(target_firebase.global_position, 0.3)
	aa_pos += Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))

	var aa := AAEmplacement.new()
	aa.position = aa_pos
	get_tree().current_scene.add_child(aa)
	aa_emplacements.append(aa)

	aa_umbrella_established.emit(aa_pos)
	print("[NVAController] AA emplacement deployed at %s" % aa_pos)


func _spawn_sapper_team() -> void:
	"""Spawn a sapper team"""
	var spawn_pos: Vector3 = spawn_points[randi() % spawn_points.size()]
	spawn_pos += Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))

	var sapper := SapperTeam.new()
	sapper.position = spawn_pos
	get_tree().current_scene.add_child(sapper)
	sapper_teams.append(sapper)

	sapper.sapper_died.connect(_on_sapper_died)

	print("[NVAController] Sapper team spawned")


func _spawn_unit(spawn_pos: Vector3) -> Node3D:
	"""Spawn an NVA infantry unit"""
	if not nva_infantry_data:
		push_warning("[NVAController] No NVA infantry data loaded")
		return null

	var squad: Node3D = Squad.new()
	squad.name = "NVA_Infantry_%d" % (controlled_units.size() + 1)
	squad.data = nva_infantry_data
	squad.position = spawn_pos
	squad.is_player_controlled = false

	get_tree().current_scene.add_child(squad)
	_setup_unit(squad)
	infantry_units.append(squad)

	return squad


func _on_sapper_died(sapper: Node3D) -> void:
	"""Handle sapper team death"""
	sapper_teams.erase(sapper)


func _on_siege_human_wave(target: Node3D, count: int) -> void:
	"""Handle siege human wave event"""
	human_wave_launched.emit(target.global_position if target else Vector3.ZERO, count)


func _on_siege_broken(target: Node3D, success: bool) -> void:
	"""Handle siege completion"""
	active_siege = null
	if success:
		_change_state(StrategicState.EXPLOITATION)
	else:
		_change_state(StrategicState.WITHDRAWAL)


## Public API

func launch_assault(target_pos: Vector3) -> void:
	"""Order all units to assault a position"""
	for unit in controlled_units:
		if not is_instance_valid(unit) or unit.state == Squad.State.DEAD:
			continue

		var nearest: Node3D = _find_nearest_player_unit(unit)
		if nearest and unit.has_method("attack"):
			unit.attack(nearest)
		elif unit.has_method("move_to"):
			unit.move_to(target_pos)

	print("[NVAController] Assault launched on %s with %d units" % [target_pos, controlled_units.size()])


func initiate_siege(firebase: Node3D) -> void:
	"""Initiate a full siege operation"""
	if not siege_manager:
		return

	target_firebase = firebase
	active_siege = siege_manager.start_siege(firebase, controlled_units, sapper_teams)

	if active_siege:
		siege_initiated.emit(firebase)
		_change_state(StrategicState.MAIN_ASSAULT)


func request_artillery_support(position: Vector3) -> void:
	"""Request immediate artillery support"""
	if CombatManager:
		CombatManager.call_artillery_strike(position, "mortar_82mm", 6, null, GameEnums.Faction.NVA)


func get_strategic_state() -> String:
	return StrategicState.keys()[strategic_state]


func get_force_composition() -> Dictionary:
	return {
		"infantry": infantry_units.size(),
		"sappers": sapper_teams.size(),
		"aa_positions": aa_emplacements.size(),
		"total": controlled_units.size(),
	}
