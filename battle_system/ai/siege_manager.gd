extends Node
class_name SiegeManager

## Siege Manager - Coordinates NVA siege operations against firebases
## Handles encirclement, supply line interdiction, artillery coordination

signal siege_started(target: Node3D)
signal siege_broken(target: Node3D, success: bool)
signal supply_line_cut(firebase: Node3D)
signal supply_line_restored(firebase: Node3D)
signal human_wave_launched(target: Node3D, unit_count: int)
signal artillery_prep_started(target: Vector3, duration: float)
signal sapper_assault_launched(target: Node3D, sapper_count: int)

const Squad = preload("res://battle_system/nodes/squad.gd")

enum SiegePhase {
	NONE,
	RECONNAISSANCE,     # Scout firebase defenses
	ENCIRCLEMENT,       # Position forces around firebase
	ARTILLERY_PREP,     # Soften defenses with artillery
	SAPPER_ASSAULT,     # Breach perimeter with sappers
	HUMAN_WAVE,         # Mass infantry assault
	EXPLOITATION,       # Follow-up and consolidation
	WITHDRAWAL,         # Retreat if assault fails
}

## Active sieges
var active_sieges: Array = []

## Configuration
@export var min_siege_force: int = 20          # Minimum units to start siege
@export var encirclement_radius: float = 80.0  # Distance to encircle at
@export var artillery_prep_duration: float = 30.0
@export var wave_interval: float = 45.0        # Seconds between human waves
@export var max_waves_per_assault: int = 3


class SiegeOperation:
	var target: Node3D  # Firebase or position
	var target_position: Vector3
	var phase: int = 0  # SiegePhase.NONE
	var assigned_units: Array = []
	var sapper_teams: Array = []
	var artillery_units: Array = []
	var aa_positions: Array = []
	var phase_timer: float = 0.0
	var waves_launched: int = 0
	var supply_lines_cut: bool = false
	var encirclement_positions: Array = []
	var breach_points: Array = []
	var casualties: int = 0
	var enemy_casualties: int = 0

	func _init(t: Node3D) -> void:
		target = t
		if is_instance_valid(t):
			target_position = t.global_position

	func get_strength() -> int:
		var count: int = 0
		for unit in assigned_units:
			if is_instance_valid(unit) and unit.state != Squad.State.DEAD:
				count += 1
		return count

	func get_sapper_count() -> int:
		var count: int = 0
		for sapper in sapper_teams:
			if is_instance_valid(sapper) and sapper.state != Squad.State.DEAD:
				count += 1
		return count


func _ready() -> void:
	print("[SiegeManager] Initialized")


func _process(delta: float) -> void:
	for siege in active_sieges:
		_update_siege(siege, delta)

	# Clean up completed sieges
	active_sieges = active_sieges.filter(func(s): return s.phase != SiegePhase.NONE)


func _update_siege(siege: SiegeOperation, delta: float) -> void:
	"""Update a siege operation"""
	siege.phase_timer += delta

	match siege.phase:
		SiegePhase.RECONNAISSANCE:
			_process_reconnaissance(siege, delta)
		SiegePhase.ENCIRCLEMENT:
			_process_encirclement(siege, delta)
		SiegePhase.ARTILLERY_PREP:
			_process_artillery_prep(siege, delta)
		SiegePhase.SAPPER_ASSAULT:
			_process_sapper_assault(siege, delta)
		SiegePhase.HUMAN_WAVE:
			_process_human_wave(siege, delta)
		SiegePhase.EXPLOITATION:
			_process_exploitation(siege, delta)
		SiegePhase.WITHDRAWAL:
			_process_withdrawal(siege, delta)


func _process_reconnaissance(siege: SiegeOperation, _delta: float) -> void:
	"""Scout the firebase defenses"""
	# After 15 seconds, move to encirclement
	if siege.phase_timer >= 15.0:
		_advance_phase(siege, SiegePhase.ENCIRCLEMENT)


func _process_encirclement(siege: SiegeOperation, _delta: float) -> void:
	"""Position forces around the firebase"""
	# Calculate encirclement positions if not done
	if siege.encirclement_positions.is_empty():
		_calculate_encirclement_positions(siege)

	# Move units to encirclement positions
	var in_position: int = 0
	for i in siege.assigned_units.size():
		var unit: Node3D = siege.assigned_units[i]
		if not is_instance_valid(unit) or unit.state == Squad.State.DEAD:
			continue

		var target_pos: Vector3 = siege.encirclement_positions[i % siege.encirclement_positions.size()]
		var dist: float = unit.global_position.distance_to(target_pos)

		if dist > 5.0:
			if unit.has_method("move_to"):
				unit.move_to(target_pos)
		else:
			in_position += 1

	# Check if enough units are in position
	var required: int = int(siege.assigned_units.size() * 0.7)
	if in_position >= required or siege.phase_timer >= 60.0:
		# Cut supply lines
		siege.supply_lines_cut = true
		supply_line_cut.emit(siege.target)

		# Move to artillery prep
		_advance_phase(siege, SiegePhase.ARTILLERY_PREP)


func _process_artillery_prep(siege: SiegeOperation, _delta: float) -> void:
	"""Bombard firebase with artillery before assault"""
	# Start artillery if not already
	if siege.phase_timer < 1.0:
		artillery_prep_started.emit(siege.target_position, artillery_prep_duration)
		_call_artillery_barrage(siege)

	# Continue bombardment for duration
	if siege.phase_timer >= artillery_prep_duration:
		# Move to sapper assault if we have sappers
		if siege.get_sapper_count() > 0:
			_advance_phase(siege, SiegePhase.SAPPER_ASSAULT)
		else:
			_advance_phase(siege, SiegePhase.HUMAN_WAVE)


func _process_sapper_assault(siege: SiegeOperation, _delta: float) -> void:
	"""Send sappers to breach the perimeter"""
	# Start sapper assault
	if siege.phase_timer < 1.0:
		sapper_assault_launched.emit(siege.target, siege.get_sapper_count())
		_launch_sapper_assault(siege)

	# Check if sappers have breached (or died)
	var active_sappers: int = siege.get_sapper_count()

	# After 30 seconds or all sappers done, launch human wave
	if siege.phase_timer >= 30.0 or active_sappers == 0:
		_advance_phase(siege, SiegePhase.HUMAN_WAVE)


func _process_human_wave(siege: SiegeOperation, _delta: float) -> void:
	"""Launch massed infantry assault"""
	# Launch wave at start and then periodically
	var should_launch: bool = false

	if siege.waves_launched == 0:
		should_launch = true
	elif siege.phase_timer >= wave_interval * float(siege.waves_launched):
		if siege.waves_launched < max_waves_per_assault:
			should_launch = true

	if should_launch:
		_launch_human_wave(siege)
		siege.waves_launched += 1

	# Check assault status
	var strength: int = siege.get_strength()

	# If we've lost too many, withdraw
	if strength < int(min_siege_force * 0.3):
		_advance_phase(siege, SiegePhase.WITHDRAWAL)
		return

	# If target is destroyed/captured, exploit
	if not is_instance_valid(siege.target):
		_advance_phase(siege, SiegePhase.EXPLOITATION)
		return

	# Max waves launched, check if we should withdraw
	if siege.waves_launched >= max_waves_per_assault:
		if siege.phase_timer >= wave_interval * float(max_waves_per_assault) + 30.0:
			_advance_phase(siege, SiegePhase.WITHDRAWAL)


func _process_exploitation(siege: SiegeOperation, _delta: float) -> void:
	"""Consolidate gains after successful assault"""
	# Move remaining units to firebase position
	for unit in siege.assigned_units:
		if is_instance_valid(unit) and unit.state != Squad.State.DEAD:
			if unit.has_method("move_to"):
				unit.move_to(siege.target_position)

	# After 30 seconds, end siege
	if siege.phase_timer >= 30.0:
		siege_broken.emit(siege.target, true)
		siege.phase = SiegePhase.NONE


func _process_withdrawal(siege: SiegeOperation, _delta: float) -> void:
	"""Retreat from failed assault"""
	# Order all units to retreat
	for unit in siege.assigned_units:
		if is_instance_valid(unit) and unit.state != Squad.State.DEAD:
			if unit.has_method("move_to"):
				# Retreat away from firebase
				var retreat_dir: Vector3 = (unit.global_position - siege.target_position).normalized()
				var retreat_pos: Vector3 = unit.global_position + retreat_dir * 50.0
				unit.move_to(retreat_pos)

	# Restore supply lines
	if siege.supply_lines_cut:
		siege.supply_lines_cut = false
		supply_line_restored.emit(siege.target)

	# After 20 seconds, end siege
	if siege.phase_timer >= 20.0:
		siege_broken.emit(siege.target, false)
		siege.phase = SiegePhase.NONE


func _advance_phase(siege: SiegeOperation, new_phase: SiegePhase) -> void:
	"""Advance to next siege phase"""
	siege.phase = new_phase
	siege.phase_timer = 0.0
	print("[SiegeManager] Siege advancing to phase: %s" % SiegePhase.keys()[new_phase])


func _calculate_encirclement_positions(siege: SiegeOperation) -> void:
	"""Calculate positions around the firebase"""
	var num_positions: int = maxi(siege.assigned_units.size(), 8)

	for i in num_positions:
		var angle: float = (TAU / float(num_positions)) * float(i)
		var offset: Vector3 = Vector3(cos(angle), 0, sin(angle)) * encirclement_radius
		siege.encirclement_positions.append(siege.target_position + offset)


func _call_artillery_barrage(siege: SiegeOperation) -> void:
	"""Call artillery on firebase"""
	if not CombatManager:
		return

	# Fire multiple salvos
	var salvos: int = int(artillery_prep_duration / 10.0)

	for i in salvos:
		var timer := get_tree().create_timer(10.0 * float(i))
		timer.timeout.connect(func():
			if siege.phase == SiegePhase.ARTILLERY_PREP:
				# Scatter around target
				var scatter_pos: Vector3 = siege.target_position + Vector3(
					randf_range(-20.0, 20.0), 0, randf_range(-20.0, 20.0)
				)
				CombatManager.call_artillery_strike(scatter_pos, "mortar_82mm", 6, null, GameEnums.Faction.NVA)
		)


func _launch_sapper_assault(siege: SiegeOperation) -> void:
	"""Send sappers to breach perimeter"""
	for sapper in siege.sapper_teams:
		if not is_instance_valid(sapper) or sapper.state == Squad.State.DEAD:
			continue

		# Move toward firebase
		if sapper.has_method("move_to"):
			# Aim for breach point
			var breach_angle: float = randf() * TAU
			var breach_pos: Vector3 = siege.target_position + Vector3(
				cos(breach_angle), 0, sin(breach_angle)
			) * 10.0  # Close to perimeter

			sapper.move_to(breach_pos)
			siege.breach_points.append(breach_pos)

		# Sappers attack structures if they have that ability
		if sapper.has_method("set_target_type"):
			sapper.set_target_type("structure")


func _launch_human_wave(siege: SiegeOperation) -> void:
	"""Launch massed infantry assault"""
	var attacking_count: int = 0

	for unit in siege.assigned_units:
		if not is_instance_valid(unit) or unit.state == Squad.State.DEAD:
			continue

		# All units charge the firebase
		if unit.has_method("move_to"):
			# Use breach points if available
			var target_pos: Vector3 = siege.target_position
			if not siege.breach_points.is_empty():
				target_pos = siege.breach_points[randi() % siege.breach_points.size()]

			unit.move_to(target_pos)
			attacking_count += 1

		# Attack any enemies encountered
		var player_units: Array[Node] = get_tree().get_nodes_in_group("player_units")
		for player_unit in player_units:
			if not is_instance_valid(player_unit):
				continue
			var dist: float = unit.global_position.distance_to(player_unit.global_position)
			if dist < 30.0 and unit.has_method("attack"):
				unit.attack(player_unit)
				break

	human_wave_launched.emit(siege.target, attacking_count)
	print("[SiegeManager] Human wave launched: %d units" % attacking_count)


## Public API

func start_siege(target: Node3D, units: Array[Node3D], sappers: Array[Node3D] = []) -> SiegeOperation:
	"""Start a siege operation against a firebase"""
	if units.size() < min_siege_force:
		push_warning("[SiegeManager] Not enough units for siege: %d < %d" % [units.size(), min_siege_force])
		return null

	var siege := SiegeOperation.new(target)
	siege.assigned_units = units
	siege.sapper_teams = sappers
	siege.phase = SiegePhase.RECONNAISSANCE

	active_sieges.append(siege)
	siege_started.emit(target)

	print("[SiegeManager] Siege started against %s with %d units, %d sappers" % [
		target.name if target else "position",
		units.size(),
		sappers.size()
	])

	return siege


func add_aa_coverage(siege: SiegeOperation, position: Vector3) -> void:
	"""Add AA gun position to deny air support"""
	siege.aa_positions.append(position)


func reinforce_siege(siege: SiegeOperation, units: Array[Node3D]) -> void:
	"""Add more units to an active siege"""
	for unit in units:
		if unit not in siege.assigned_units:
			siege.assigned_units.append(unit)


func cancel_siege(siege: SiegeOperation) -> void:
	"""Cancel a siege and order withdrawal"""
	_advance_phase(siege, SiegePhase.WITHDRAWAL)


func get_active_siege_count() -> int:
	return active_sieges.size()


func is_position_under_siege(position: Vector3, radius: float = 100.0) -> bool:
	"""Check if a position is under active siege"""
	for siege in active_sieges:
		if siege.target_position.distance_to(position) <= radius:
			return true
	return false
