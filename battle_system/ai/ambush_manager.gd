extends Node
class_name AmbushManager

## Ambush Manager - Coordinates VC ambush attacks
## Sets up ambush positions, triggers ambushes, manages trap placement

signal ambush_prepared(position: Vector3, unit_count: int)
signal ambush_triggered(position: Vector3, targets: Array)
signal ambush_concluded(success: bool, casualties: int)
signal trap_line_placed(start: Vector3, end: Vector3, trap_count: int)

const BoobyTrap = preload("res://tunnel_system/booby_trap.gd")

## Active ambushes
var _prepared_ambushes: Array = []
var _active_ambushes: Array = []

## Configuration
@export var min_ambush_units: int = 3
@export var max_ambush_units: int = 8
@export var ambush_trigger_range: float = 15.0
@export var trap_spacing: float = 5.0


class AmbushSite:
	var position: Vector3
	var ambush_units: Array  # Node3D
	var trap_positions: Array  # Vector3
	var trigger_radius: float
	var is_active: bool
	var is_triggered: bool

	func _init(pos: Vector3) -> void:
		position = pos
		ambush_units = []
		trap_positions = []
		trigger_radius = 15.0
		is_active = true
		is_triggered = false


func _ready() -> void:
	print("[AmbushManager] Initialized")


func _process(_delta: float) -> void:
	_check_ambush_triggers()
	_cleanup_completed_ambushes()


func _check_ambush_triggers() -> void:
	"""Check if any ambushes should trigger"""
	var player_units: Array[Node] = get_tree().get_nodes_in_group("player_units")

	for ambush in _prepared_ambushes:
		if ambush.is_triggered:
			continue

		for unit in player_units:
			if not is_instance_valid(unit):
				continue

			var dist: float = ambush.position.distance_to(unit.global_position)
			if dist <= ambush.trigger_radius:
				_trigger_ambush(ambush, unit)
				break


func _trigger_ambush(ambush: AmbushSite, trigger_unit: Node3D) -> void:
	"""Trigger an ambush"""
	ambush.is_triggered = true

	# Find all targets in kill zone
	var targets: Array[Node3D] = []
	var player_units: Array[Node] = get_tree().get_nodes_in_group("player_units")

	for unit in player_units:
		if not is_instance_valid(unit):
			continue
		var dist: float = ambush.position.distance_to(unit.global_position)
		if dist <= ambush.trigger_radius * 1.5:
			targets.append(unit as Node3D)

	# Order ambush units to attack
	for vc_unit in ambush.ambush_units:
		if not is_instance_valid(vc_unit):
			continue

		# Make visible
		vc_unit.visible = true
		vc_unit.set_physics_process(true)

		# Attack nearest target
		var nearest: Node3D = _find_nearest(vc_unit, targets)
		if nearest and vc_unit.has_method("attack"):
			vc_unit.attack(nearest)

	# Move to active list
	_prepared_ambushes.erase(ambush)
	_active_ambushes.append(ambush)

	ambush_triggered.emit(ambush.position, targets)

	if BattleSignals:
		BattleSignals.vc_ambush_triggered.emit(ambush.position, targets.size())

	print("[AmbushManager] Ambush triggered at %s - %d VC vs %d targets" % [
		ambush.position, ambush.ambush_units.size(), targets.size()
	])


func _cleanup_completed_ambushes() -> void:
	"""Clean up finished ambushes"""
	var to_remove: Array = []

	for ambush in _active_ambushes:
		var alive_count: int = 0
		for unit in ambush.ambush_units:
			if is_instance_valid(unit):
				if unit.has_method("get") and unit.get("state") != null:
					# Check if dead
					if unit.state != 4:  # Assuming 4 = DEAD
						alive_count += 1
				else:
					alive_count += 1

		# Ambush over if all units dead or fled
		if alive_count == 0:
			to_remove.append(ambush)

	for ambush in to_remove:
		_active_ambushes.erase(ambush)
		ambush_concluded.emit(false, ambush.ambush_units.size())


func _find_nearest(from: Node3D, targets: Array[Node3D]) -> Node3D:
	"""Find nearest target"""
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for target in targets:
		if not is_instance_valid(target):
			continue
		var dist: float = from.global_position.distance_to(target.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = target

	return nearest


## Public API

func prepare_ambush(position: Vector3, units: Array[Node3D], trigger_radius: float = -1.0) -> AmbushSite:
	"""Prepare an ambush at a position"""
	var ambush := AmbushSite.new(position)

	if trigger_radius > 0:
		ambush.trigger_radius = trigger_radius
	else:
		ambush.trigger_radius = ambush_trigger_range

	# Position units around ambush point
	var unit_count: int = units.size()
	for i in unit_count:
		var unit: Node3D = units[i]
		if not is_instance_valid(unit):
			continue

		# Calculate ambush position in arc
		var angle: float = (TAU / float(unit_count)) * float(i)
		var offset := Vector3(cos(angle), 0, sin(angle)) * (trigger_radius * 0.8)

		unit.global_position = position + offset
		unit.visible = false  # Hidden until triggered
		unit.set_physics_process(false)

		ambush.ambush_units.append(unit)

	_prepared_ambushes.append(ambush)
	ambush_prepared.emit(position, ambush.ambush_units.size())

	print("[AmbushManager] Ambush prepared at %s with %d units" % [position, unit_count])
	return ambush


func place_trap_line(start: Vector3, end: Vector3, trap_type: int = 0) -> Array[Node3D]:
	"""Place a line of traps between two points"""
	var traps: Array[Node3D] = []

	var direction: Vector3 = (end - start).normalized()
	var distance: float = start.distance_to(end)
	var trap_count: int = int(distance / trap_spacing)

	for i in trap_count:
		var pos: Vector3 = start + direction * (trap_spacing * float(i))

		var trap := BoobyTrap.new()
		trap.trap_type = trap_type
		trap.position = pos

		get_tree().current_scene.add_child(trap)
		traps.append(trap)

	trap_line_placed.emit(start, end, trap_count)
	print("[AmbushManager] Placed %d traps from %s to %s" % [trap_count, start, end])

	return traps


func place_trap_field(center: Vector3, radius: float, density: float = 0.5, trap_type: int = 0) -> Array[Node3D]:
	"""Place a field of random traps"""
	var traps: Array[Node3D] = []

	var area: float = PI * radius * radius
	var trap_count: int = int(area * density / 25.0)  # Roughly 1 trap per 25 sq meters at density 0.5

	for i in trap_count:
		var angle: float = randf() * TAU
		var dist: float = randf() * radius
		var pos := center + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

		var trap := BoobyTrap.new()
		trap.trap_type = trap_type
		trap.position = pos

		get_tree().current_scene.add_child(trap)
		traps.append(trap)

	print("[AmbushManager] Placed %d traps in field at %s" % [trap_count, center])
	return traps


func cancel_ambush(ambush: AmbushSite) -> void:
	"""Cancel a prepared ambush"""
	if ambush in _prepared_ambushes:
		_prepared_ambushes.erase(ambush)

		# Make units visible again
		for unit in ambush.ambush_units:
			if is_instance_valid(unit):
				unit.visible = true
				unit.set_physics_process(true)


func get_prepared_ambush_count() -> int:
	return _prepared_ambushes.size()


func get_active_ambush_count() -> int:
	return _active_ambushes.size()


func find_good_ambush_site(near_position: Vector3, search_radius: float = 50.0) -> Vector3:
	"""Find a good position for an ambush near a location"""
	# Look for positions along likely travel routes
	# For now, just offset from the position

	var angle: float = randf() * TAU
	var dist: float = randf_range(search_radius * 0.3, search_radius * 0.7)

	return near_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
