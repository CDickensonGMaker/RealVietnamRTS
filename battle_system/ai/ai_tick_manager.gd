extends Node
## Autoload singleton - do not use class_name (causes "hides autoload" error)

const __ThreatHeatmap = preload("res://battle_system/ai/threat_heatmap.gd")

## AI Tick Manager - Coordinates staggered AI processing for performance.
## Ported from BP RTS DARK SHADOWS and adapted for Vietnam RTS squad-based combat.
##
## Uses a 4-group stagger system:
## - Squads are divided into 4 groups
## - Each group processes on a different tick (0.5s intervals)
## - Results in each squad updating every 2.0s, distributed across frames
## - Prevents frame spikes with many units

signal ai_tick_fast           # 0.1s - For urgent checks (suppression response)
signal ai_tick_commander      # 0.5s - Squad commander AI decisions
signal ai_tick_director       # 3.0s - AI Director strategic decisions

## Tick intervals (seconds)
const FAST_TICK_RATE: float = 0.1
const COMMANDER_TICK_RATE: float = 0.5
const DIRECTOR_TICK_RATE: float = 3.0

## Stagger configuration
const STAGGER_GROUPS: int = 4  # Number of groups to distribute processing

## Tick timers
var _fast_tick_timer: float = 0.0
var _commander_tick_timer: float = 0.0
var _director_tick_timer: float = 0.0

## Current stagger group index (cycles 0 to STAGGER_GROUPS-1)
var _stagger_index: int = 0

## Registered squad commander AIs
var _commander_ais: Array = []  # Array of SquadCommanderAI

## Threat heatmap for spatial awareness
var threat_heatmap = null  # Type: __ThreatHeatmap (preloaded)

## Performance monitoring
var _last_commander_tick_ms: float = 0.0
var _perf_warnings: int = 0


func _ready() -> void:
	# Initialize threat heatmap
	threat_heatmap = __ThreatHeatmap.new()

	# Connect to battle signals for squad tracking
	if BattleSignals:
		BattleSignals.unit_spawned.connect(_on_unit_spawned)
		BattleSignals.unit_died.connect(_on_unit_died)


func _process(delta: float) -> void:
	# Fast tick (0.1s) - urgent AI responses
	_fast_tick_timer += delta
	if _fast_tick_timer >= FAST_TICK_RATE:
		_fast_tick_timer -= FAST_TICK_RATE
		ai_tick_fast.emit()

	# Commander tick (0.5s) - tactical decisions, staggered
	_commander_tick_timer += delta
	if _commander_tick_timer >= COMMANDER_TICK_RATE:
		_commander_tick_timer -= COMMANDER_TICK_RATE
		_process_commander_tick()

	# Director tick (3.0s) - strategic decisions
	_director_tick_timer += delta
	if _director_tick_timer >= DIRECTOR_TICK_RATE:
		_director_tick_timer -= DIRECTOR_TICK_RATE
		ai_tick_director.emit()
		_update_threat_heatmap()


## Process commander AI tick with staggered groups.
## Each tick processes 25% of commanders to distribute load.
func _process_commander_tick() -> void:
	if _commander_ais.is_empty():
		ai_tick_commander.emit()
		return

	var start_time: int = Time.get_ticks_usec()

	# Calculate which commanders to process this tick
	var total: int = _commander_ais.size()
	var group_size: int = ceili(float(total) / float(STAGGER_GROUPS))
	var start_idx: int = _stagger_index * group_size
	var end_idx: int = mini(start_idx + group_size, total)

	# Process this group's commanders
	for i in range(start_idx, end_idx):
		var commander = _commander_ais[i]
		if is_instance_valid(commander) and commander.has_method("tick"):
			commander.tick(COMMANDER_TICK_RATE * STAGGER_GROUPS)

	# Advance stagger index
	_stagger_index = (_stagger_index + 1) % STAGGER_GROUPS

	# Emit signal
	ai_tick_commander.emit()

	# Performance monitoring
	var elapsed_ms: float = float(Time.get_ticks_usec() - start_time) / 1000.0
	_last_commander_tick_ms = elapsed_ms
	if elapsed_ms > 16.0:  # > 16ms = frame drop territory
		_perf_warnings += 1
		if _perf_warnings <= 10 or _perf_warnings % 100 == 0:
			push_warning("[AITickManager] Commander tick took %.1fms (warning #%d)" % [elapsed_ms, _perf_warnings])


## Update threat heatmap with current squad positions.
func _update_threat_heatmap() -> void:
	if not threat_heatmap:
		return

	# Decay existing threats
	threat_heatmap.decay_threats(DIRECTOR_TICK_RATE)

	# Collect all squads and update heatmap
	var squads: Array = []
	for commander in _commander_ais:
		if is_instance_valid(commander) and commander.has_method("get_squad"):
			var squad = commander.get_squad()
			if squad:
				squads.append(squad)

	# Also get squads from groups if no commanders registered yet
	if squads.is_empty():
		squads = get_tree().get_nodes_in_group("all_units")

	threat_heatmap.update_from_squads(squads)


## Register a squad commander AI for tick processing.
func register_commander(commander) -> void:
	if commander and commander not in _commander_ais:
		_commander_ais.append(commander)


## Unregister a squad commander AI.
func unregister_commander(commander) -> void:
	var idx: int = _commander_ais.find(commander)
	if idx >= 0:
		_commander_ais.remove_at(idx)


## Get all registered commander AIs.
func get_commanders() -> Array:
	return _commander_ais


## Get the threat heatmap.
func get_threat_heatmap():  # Returns __ThreatHeatmap instance
	return threat_heatmap


## Get threat at a position for a faction.
func get_threat_at(position: Vector3, faction: int) -> float:
	if threat_heatmap:
		return threat_heatmap.get_threat_at(position, faction)
	return 0.0


## Get retreat direction at a position for a faction.
func get_retreat_direction(position: Vector3, faction: int) -> Vector3:
	if threat_heatmap:
		return threat_heatmap.get_threat_gradient(position, faction)
	return Vector3.ZERO


## Check if a squad should retreat based on threat assessment.
func should_retreat(position: Vector3, faction: int, firepower: float, hp_ratio: float) -> bool:
	if threat_heatmap:
		return threat_heatmap.should_retreat(position, faction, firepower, hp_ratio)
	return false


## Get safe retreat position.
func get_safest_retreat_position(position: Vector3, faction: int, radius: float = 60.0) -> Vector3:
	if threat_heatmap:
		return threat_heatmap.get_safest_retreat_position(position, faction, radius)
	return position + Vector3(0, 0, 60.0)  # Default: retreat backward


## Get flanking direction.
func get_flanking_direction(position: Vector3, target_pos: Vector3, faction: int) -> Vector3:
	if threat_heatmap:
		return threat_heatmap.get_flanking_direction(position, target_pos, faction)
	# Default: perpendicular to target direction
	var to_target: Vector3 = (target_pos - position).normalized()
	return Vector3(-to_target.z, 0, to_target.x)


## Handle unit spawned - register their commander if they have one.
func _on_unit_spawned(unit: Node, _faction: int = 0) -> void:
	if not is_instance_valid(unit):
		return

	# Check if unit has a commander AI component
	if unit.has_method("get_commander_ai"):
		var commander = unit.get_commander_ai()
		if commander:
			register_commander(commander)
	# Or check for squad_commander_ai property
	elif "squad_commander_ai" in unit and unit.squad_commander_ai:
		register_commander(unit.squad_commander_ai)


## Handle unit death - unregister their commander.
func _on_unit_died(unit: Node, _killer: Node) -> void:
	if not is_instance_valid(unit):
		return

	if unit.has_method("get_commander_ai"):
		var commander = unit.get_commander_ai()
		if commander:
			unregister_commander(commander)
	elif "squad_commander_ai" in unit and unit.squad_commander_ai:
		unregister_commander(unit.squad_commander_ai)


# =============================================================================
# DEBUG
# =============================================================================

## Get performance stats.
func get_perf_stats() -> Dictionary:
	return {
		"registered_commanders": _commander_ais.size(),
		"stagger_index": _stagger_index,
		"last_tick_ms": _last_commander_tick_ms,
		"perf_warnings": _perf_warnings,
		"heatmap_cells": threat_heatmap.get_debug_info().cell_count if threat_heatmap else 0
	}


## Get debug visualization data for the threat heatmap.
func get_threat_visualization() -> Array[Dictionary]:
	if threat_heatmap:
		return threat_heatmap.get_threat_visualization()
	return []
