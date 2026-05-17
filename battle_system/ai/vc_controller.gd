extends "res://battle_system/ai/enemy_ai_controller.gd"
class_name VCController

## Viet Cong AI Controller
## Guerrilla tactics: ambush, hit-and-run, tunnel attacks, village integration
## Lower aggression, higher stealth, uses terrain and civilian cover

const AmbushManagerScript = preload("res://battle_system/ai/ambush_manager.gd")
const TunnelNetworkScript = preload("res://tunnel_system/tunnel_network.gd")
const BoobyTrapScript = preload("res://tunnel_system/booby_trap.gd")

signal ambush_sprung(target: Node3D)
signal tunnel_attack_launched(position: Vector3, count: int)
signal trap_placed(position: Vector3, trap_type: int)
signal village_supplies_collected(amount: float)
signal civilian_attack_triggered(village: Node3D)

enum GuerrillaState {
	HIDING,            # Laying low, avoiding detection
	SCOUTING,          # Observing enemy movements
	PREPARING_AMBUSH,  # Setting up ambush positions
	AMBUSHING,         # Executing ambush
	HIT_AND_RUN,       # Quick attacks then retreat
	TUNNELING,         # Moving through tunnels
	RETREATING,        # Falling back
}

enum TrapType { PUNJI_PIT, TRIPWIRE, CLAYMORE, WHIP_TRAP }

## VC-specific settings
@export var ambush_chance: float = 0.4
@export var hit_and_run_threshold: float = 0.5
@export var tunnel_emerge_range: float = 20.0
@export var trap_placement_interval: float = 30.0
@export var max_traps: int = 15
@export var village_tax_interval: float = 60.0

## Guerrilla state
var guerrilla_state: GuerrillaState = GuerrillaState.HIDING
var _state_timer: float = 0.0

## Timing
var patrol_check_timer: float = 0.0
var tunnel_spawn_timer: float = 0.0
var village_tax_timer: float = 0.0
var trap_timer: float = 0.0
var scout_timer: float = 0.0
var ambush_cooldown_timer: float = 0.0

## Systems
var ambush_manager: Node = null  # AmbushManager
var tunnel_network: Node = null  # TunnelNetwork
var village_manager: Node = null

## Resources
var placed_traps: Array[Node3D] = []
var hidden_units: Array[Node3D] = []  # Units in tunnels
var supply_stockpile: float = 0.0

## Unit data for spawning
var vc_infantry_data: Resource = null
var vc_sapper_data: Resource = null


func _ready() -> void:
	faction = GameEnums.Faction.VC
	aggression = 0.4  # Less aggressive, more tactical
	detection_range = 35.0
	attack_range = 20.0
	retreat_health_threshold = 0.45  # Retreat earlier

	# Smaller, more frequent waves
	units_per_wave = 4
	wave_interval = 40.0

	# Load VC unit data
	_load_unit_data()

	# Set spawn points - VC emerges from multiple directions
	spawn_points = [
		Vector3(18, 0, 0),
		Vector3(20, 0, 10),
		Vector3(20, 0, -10),
		Vector3(-15, 0, 8),
		Vector3(-15, 0, -8),
	]

	# Create subsystems
	_setup_subsystems()

	super._ready()
	print("[VCController] Initialized - Guerrilla tactics, tunnel system enabled")


func _load_unit_data() -> void:
	"""Load VC unit data"""
	var infantry_path := "res://battle_system/data/units/vc_infantry.tres"
	if ResourceLoader.exists(infantry_path):
		vc_infantry_data = load(infantry_path)


func _setup_subsystems() -> void:
	"""Initialize VC subsystems"""
	# Create AmbushManager
	ambush_manager = AmbushManagerScript.new()
	ambush_manager.name = "AmbushManager"
	add_child(ambush_manager)
	ambush_manager.ambush_triggered.connect(_on_ambush_triggered)

	# Find or create tunnel network
	var tunnel_nodes: Array[Node] = get_tree().get_nodes_in_group("tunnel_networks")
	if not tunnel_nodes.is_empty():
		tunnel_network = tunnel_nodes[0]
	else:
		# Create tunnel network if none exists
		tunnel_network = TunnelNetworkScript.new()
		tunnel_network.name = "TunnelNetwork"
		tunnel_network.add_to_group("tunnel_networks")
		get_tree().current_scene.add_child(tunnel_network)

	# Find village manager
	var village_managers: Array[Node] = get_tree().get_nodes_in_group("village_managers")
	if not village_managers.is_empty():
		village_manager = village_managers[0]


func _process(delta: float) -> void:
	super._process(delta)

	_state_timer += delta
	patrol_check_timer += delta
	trap_timer += delta
	village_tax_timer += delta
	scout_timer += delta
	ambush_cooldown_timer += delta

	# State-specific processing
	match guerrilla_state:
		GuerrillaState.HIDING:
			_process_hiding(delta)
		GuerrillaState.SCOUTING:
			_process_scouting(delta)
		GuerrillaState.PREPARING_AMBUSH:
			_process_preparing_ambush(delta)
		GuerrillaState.AMBUSHING:
			_process_ambushing(delta)
		GuerrillaState.HIT_AND_RUN:
			_process_hit_and_run(delta)
		GuerrillaState.TUNNELING:
			_process_tunneling(delta)
		GuerrillaState.RETREATING:
			_process_retreating(delta)

	# Periodic activities
	if trap_timer >= trap_placement_interval:
		trap_timer = 0.0
		_consider_trap_placement()

	if village_tax_timer >= village_tax_interval:
		village_tax_timer = 0.0
		_collect_village_taxes()


func _process_hiding(delta: float) -> void:
	"""Hiding - wait for opportunity"""
	# Check if we should scout
	if _state_timer >= 20.0:
		_change_state(GuerrillaState.SCOUTING)
		return

	# Spawn in tunnel if available
	if tunnel_network and tunnel_network.get_active_entrance_count() > 0:
		if controlled_units.size() < units_per_wave:
			_spawn_in_tunnel()


func _process_scouting(delta: float) -> void:
	"""Scout enemy positions"""
	# Look for ambush opportunities
	var target: Node3D = _find_ambush_opportunity()

	if target and ambush_cooldown_timer >= 30.0:
		_change_state(GuerrillaState.PREPARING_AMBUSH)
		return

	# If scouting for too long, try hit and run
	if _state_timer >= 30.0:
		if controlled_units.size() >= 3:
			_change_state(GuerrillaState.HIT_AND_RUN)
		else:
			_change_state(GuerrillaState.HIDING)


func _process_preparing_ambush(delta: float) -> void:
	"""Set up ambush positions"""
	# Find a good ambush position
	var target: Node3D = _find_nearest_player_unit(controlled_units[0] if not controlled_units.is_empty() else self)
	if not target:
		_change_state(GuerrillaState.SCOUTING)
		return

	# Position units for ambush
	if ambush_manager:
		var ambush_pos: Vector3 = ambush_manager.find_good_ambush_site(target.global_position)
		ambush_manager.prepare_ambush(ambush_pos, controlled_units, tunnel_emerge_range)

	_change_state(GuerrillaState.AMBUSHING)


func _process_ambushing(delta: float) -> void:
	"""Execute ambush"""
	# Ambush manager handles triggering
	# Check if ambush is over
	if _state_timer >= 45.0:
		_change_state(GuerrillaState.RETREATING)


func _process_hit_and_run(delta: float) -> void:
	"""Quick strikes then retreat"""
	# Attack nearest enemy
	for unit in controlled_units:
		if not is_instance_valid(unit):
			continue

		var target: Node3D = _find_nearest_player_unit(unit)
		if target and unit.has_method("attack"):
			var dist: float = unit.global_position.distance_to(target.global_position)
			if dist < attack_range:
				unit.attack(target)

	# Check for retreat conditions
	var should_retreat: bool = false

	for unit in controlled_units:
		if not is_instance_valid(unit):
			continue
		if unit.has_method("get") and unit.get("current_health") != null:
			var health_ratio: float = unit.current_health / unit.max_health
			if health_ratio < hit_and_run_threshold:
				should_retreat = true
				break

	if should_retreat or _state_timer >= 20.0:
		_change_state(GuerrillaState.RETREATING)


func _process_tunneling(delta: float) -> void:
	"""Move through tunnel network"""
	# Wait for units to emerge
	if _state_timer >= 10.0:
		_change_state(GuerrillaState.AMBUSHING)


func _process_retreating(delta: float) -> void:
	"""Retreat to safety"""
	for unit in controlled_units:
		if is_instance_valid(unit):
			_order_retreat(unit)

	# Try to escape into tunnels
	if tunnel_network:
		for unit in controlled_units:
			if not is_instance_valid(unit):
				continue

			var entrance: Node3D = tunnel_network.find_nearest_entrance(unit.global_position)
			if entrance and unit.global_position.distance_to(entrance.global_position) < 10.0:
				# Hide in tunnel
				if entrance.has_method("hide_unit"):
					entrance.hide_unit(unit)
					hidden_units.append(unit)
					controlled_units.erase(unit)

	# After retreating, go to hiding
	if _state_timer >= 30.0:
		_change_state(GuerrillaState.HIDING)
		ambush_cooldown_timer = 0.0


func _change_state(new_state: GuerrillaState) -> void:
	"""Change guerrilla state"""
	guerrilla_state = new_state
	_state_timer = 0.0
	print("[VCController] State: %s" % GuerrillaState.keys()[new_state])


func _update_unit_ai(unit: Node3D) -> void:
	"""VC-specific AI behavior"""
	# Check for hit-and-run disengage
	if unit.state == Squad.State.COMBAT:
		if unit.has_method("get") and unit.get("current_health") != null:
			var health_ratio: float = unit.current_health / unit.max_health
			if health_ratio < hit_and_run_threshold:
				if unit.has_method("stop_attack"):
					unit.stop_attack()
				_order_retreat(unit)
				return

	# Guerrilla-specific behavior based on state
	match guerrilla_state:
		GuerrillaState.HIDING, GuerrillaState.RETREATING:
			# Don't engage, stay hidden
			return
		GuerrillaState.AMBUSHING:
			# Wait for trigger
			return
		_:
			# Use base AI
			super._update_unit_ai(unit)


func _find_ambush_opportunity() -> Node3D:
	"""Find a good target for ambush"""
	var player_units: Array[Node] = get_tree().get_nodes_in_group("player_units")

	for unit in player_units:
		if not is_instance_valid(unit):
			continue

		# Check if unit is isolated (no nearby friendlies)
		var nearby_friendlies: int = 0
		for other in player_units:
			if other == unit or not is_instance_valid(other):
				continue
			var dist: float = unit.global_position.distance_to(other.global_position)
			if dist < 20.0:
				nearby_friendlies += 1

		# Isolated unit = good ambush target
		if nearby_friendlies <= 1:
			return unit as Node3D

	return null


func _consider_trap_placement() -> void:
	"""Consider placing traps"""
	if placed_traps.size() >= max_traps:
		return

	# Find patrol routes or choke points
	var player_units: Array[Node] = get_tree().get_nodes_in_group("player_units")
	if player_units.is_empty():
		return

	# Place trap ahead of likely patrol route
	var unit: Node3D = player_units[randi() % player_units.size()] as Node3D
	if not is_instance_valid(unit):
		return

	# Random offset from player position (where they might go)
	var trap_pos: Vector3 = unit.global_position + Vector3(
		randf_range(-30, 30), 0, randf_range(-30, 30)
	)

	_place_trap(trap_pos, randi() % 4)


func _place_trap(position: Vector3, trap_type: int) -> void:
	"""Place a booby trap"""
	var trap := BoobyTrapScript.new()
	trap.trap_type = trap_type
	trap.position = position
	get_tree().current_scene.add_child(trap)
	placed_traps.append(trap)
	trap_placed.emit(position, trap_type)
	print("[VCController] Trap placed at %s (type: %d)" % [position, trap_type])


func _collect_village_taxes() -> void:
	"""Collect supplies from sympathetic villages"""
	if not village_manager:
		return

	if village_manager.has_method("get_vc_supplies"):
		var supplies: float = village_manager.get_vc_supplies()
		supply_stockpile += supplies

		if supplies > 0:
			village_supplies_collected.emit(supplies)


func _spawn_in_tunnel() -> void:
	"""Spawn unit in tunnel system"""
	if not tunnel_network:
		return

	var entrance: Node3D = tunnel_network.find_nearest_entrance(Vector3.ZERO, true)
	if not entrance:
		return

	var spawn_pos: Vector3 = entrance.global_position
	var unit: Node3D = _spawn_unit(spawn_pos)

	if unit:
		# Hide initially
		if entrance.has_method("hide_unit"):
			entrance.hide_unit(unit)
			hidden_units.append(unit)
			controlled_units.erase(unit)  # Remove from active list until emerged


func _spawn_unit(spawn_pos: Vector3) -> Node3D:
	"""Spawn a VC infantry unit"""
	if not vc_infantry_data:
		push_warning("[VCController] No VC infantry data loaded")
		return null

	var squad: Node3D = Squad.new()
	squad.name = "VC_Infantry_%d" % (controlled_units.size() + 1)
	squad.data = vc_infantry_data
	squad.position = spawn_pos

	get_tree().current_scene.add_child(squad)
	_setup_unit(squad)

	return squad


func _on_ambush_triggered(position: Vector3, targets: Array) -> void:
	"""Handle ambush trigger"""
	ambush_sprung.emit(targets[0] if not targets.is_empty() else null)

	if BattleSignals:
		BattleSignals.wave_incoming.emit(-1, controlled_units.size())  # -1 = ambush


## Public API

func trigger_ambush(target_pos: Vector3, num_units: int = 3) -> void:
	"""Spawn units in ambush positions around a target"""
	var ambush_units: Array[Node3D] = []

	for i in num_units:
		var angle: float = (TAU / float(num_units)) * float(i)
		var offset: Vector3 = Vector3(cos(angle), 0, sin(angle)) * 12.0
		var spawn_pos: Vector3 = target_pos + offset

		var unit: Node3D = _spawn_unit(spawn_pos)
		if unit:
			ambush_units.append(unit)
			controlled_units.append(unit)

			# Immediately attack
			var nearest: Node3D = _find_nearest_player_unit(unit)
			if nearest and unit.has_method("attack"):
				unit.attack(nearest)

	ambush_sprung.emit(null)
	print("[VCController] Ambush triggered: %d units" % ambush_units.size())


func launch_tunnel_attack(target_pos: Vector3, unit_count: int = 5) -> void:
	"""Launch surprise attack from tunnels"""
	if not tunnel_network:
		return

	var emerged: Array[Node3D] = tunnel_network.launch_tunnel_attack(target_pos, unit_count)

	for unit in emerged:
		if not controlled_units.has(unit):
			controlled_units.append(unit)
		hidden_units.erase(unit)

	tunnel_attack_launched.emit(target_pos, emerged.size())
	print("[VCController] Tunnel attack: %d units emerged" % emerged.size())


func trigger_civilian_attack(near_position: Vector3) -> void:
	"""Trigger fake civilian ambush from village"""
	if not village_manager:
		return

	if village_manager.has_method("trigger_civilian_ambush"):
		var attackers: Array[Node3D] = village_manager.trigger_civilian_ambush(near_position)
		if not attackers.is_empty():
			for attacker in attackers:
				if not controlled_units.has(attacker):
					controlled_units.append(attacker)
			civilian_attack_triggered.emit(null)


func place_trap_field(center: Vector3, radius: float = 20.0) -> void:
	"""Place multiple traps in an area"""
	if ambush_manager:
		var traps: Array[Node3D] = ambush_manager.place_trap_field(center, radius, 0.5, 0)
		placed_traps.append_array(traps)


func get_guerrilla_state() -> String:
	return GuerrillaState.keys()[guerrilla_state]


func get_hidden_unit_count() -> int:
	return hidden_units.size()


func get_trap_count() -> int:
	return placed_traps.size()
