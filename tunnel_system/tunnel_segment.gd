class_name TunnelSegment extends Node3D
## Tunnel Segment - A section of the VC underground tunnel network.
## Connects tunnel entrances and allows units to traverse underground.
## Can be discovered, collapsed, or flooded.
##
## Part of the asymmetric warfare system - VC uses tunnels for:
## - Hidden movement between positions
## - Supply storage and caching
## - Surprise emergence attacks on US positions

signal segment_discovered(segment: TunnelSegment, by_unit: Node3D)
signal segment_collapsed(segment: TunnelSegment)
signal segment_flooded(segment: TunnelSegment)
signal unit_traversing(segment: TunnelSegment, unit: Node3D)
signal supply_cached(segment: TunnelSegment, amount: float)

enum State { HIDDEN, DISCOVERED, COLLAPSED, FLOODED }
enum SegmentType {
	PASSAGE,      # Simple connection tunnel
	CHAMBER,      # Larger room - can hide units
	STORAGE,      # Supply cache
	HOSPITAL,     # Underground medical facility
	COMMAND,      # VC command post
	TRAP_ROOM,    # Contains booby traps
}

@export var segment_type: SegmentType = SegmentType.PASSAGE
@export var entrance_a: Node3D = null  # Connected TunnelEntrance
@export var entrance_b: Node3D = null  # Connected TunnelEntrance

## State
var state: State = State.HIDDEN
var structural_integrity: float = 100.0  # 0 = collapsed

## Dimensions
@export var length: float = 50.0  # meters
@export var width: float = 0.8  # meters (tight squeeze)
@export var depth: float = 3.0  # meters underground

## Contents
var hidden_units: Array[Node3D] = []
var supply_cache: float = 0.0
var max_supply: float = 100.0
var booby_traps: int = 0

## Traversal
var traversal_speed: float = 3.0  # m/s - slower than surface
var max_capacity: int = 10  # Max units in segment at once

## Discovery
var discovery_progress: float = 0.0  # 0-1, how close to being found
const DISCOVERY_THRESHOLD: float = 1.0


func _ready() -> void:
	add_to_group("tunnel_segments")

	_configure_by_type()
	_build_visual()


func _configure_by_type() -> void:
	match segment_type:
		SegmentType.PASSAGE:
			max_capacity = 5
			max_supply = 0.0
		SegmentType.CHAMBER:
			max_capacity = 15
			max_supply = 50.0
			width = 2.0
		SegmentType.STORAGE:
			max_capacity = 3
			max_supply = 500.0
			width = 1.5
		SegmentType.HOSPITAL:
			max_capacity = 20
			max_supply = 200.0
			width = 2.5
		SegmentType.COMMAND:
			max_capacity = 10
			max_supply = 100.0
			width = 2.0
		SegmentType.TRAP_ROOM:
			max_capacity = 5
			max_supply = 0.0
			booby_traps = 3


func _build_visual() -> void:
	# Underground segments are invisible by default
	# Only show when discovered (for player visibility)

	if state == State.HIDDEN:
		return

	# Create visual representation
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = width / 2.0
	capsule.height = length
	mesh.mesh = capsule
	mesh.rotation_degrees = Vector3(90, 0, 0)
	mesh.position.y = -depth

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.25, 0.2, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat

	add_child(mesh)


func _show_discovered_visual() -> void:
	# Clear existing visuals
	for child in get_children():
		if child is MeshInstance3D:
			child.queue_free()

	# Show discovered tunnel
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, 1.0, length)
	mesh.mesh = box
	mesh.position.y = -depth + 0.5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.3, 0.2, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat

	add_child(mesh)

	# Direction indicator (line between entrances)
	if entrance_a and entrance_b:
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(0.1, 0.1, length)
		line.mesh = line_mesh
		line.position.y = 0.1
		line.look_at(entrance_b.global_position - entrance_a.global_position)

		var line_mat := StandardMaterial3D.new()
		line_mat.albedo_color = Color(1.0, 0.5, 0.0)
		line.material_override = line_mat

		add_child(line)


# =============================================================================
# PUBLIC API - Discovery
# =============================================================================

func add_discovery_progress(amount: float, by_unit: Node3D = null) -> void:
	if state != State.HIDDEN:
		return

	discovery_progress += amount

	if discovery_progress >= DISCOVERY_THRESHOLD:
		discover(by_unit)


func discover(by_unit: Node3D = null) -> void:
	if state != State.HIDDEN:
		return

	state = State.DISCOVERED
	segment_discovered.emit(self, by_unit)

	# Emit to central signal bus
	if BattleSignals and entrance_a:
		BattleSignals.tunnel_discovered.emit(entrance_a, by_unit)

	_show_discovered_visual()

	# Also discover connected entrances
	if entrance_a and entrance_a.has_method("discover"):
		entrance_a.discover()
	if entrance_b and entrance_b.has_method("discover"):
		entrance_b.discover()


# =============================================================================
# PUBLIC API - Destruction
# =============================================================================

func damage(amount: float) -> void:
	if state == State.COLLAPSED:
		return

	structural_integrity -= amount

	if structural_integrity <= 0.0:
		collapse()


func collapse() -> void:
	if state == State.COLLAPSED:
		return

	state = State.COLLAPSED
	segment_collapsed.emit(self)

	# Emit to central signal bus
	if BattleSignals:
		BattleSignals.tunnel_collapsed.emit(self)

	# Kill units inside
	for unit in hidden_units:
		if is_instance_valid(unit) and unit.has_method("take_damage"):
			unit.take_damage(500, self)
	hidden_units.clear()

	# Destroy supplies
	supply_cache = 0.0

	# Visual update
	for child in get_children():
		if child is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.2, 0.15, 0.1, 0.5)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			child.material_override = mat


func flood() -> void:
	if state in [State.COLLAPSED, State.FLOODED]:
		return

	state = State.FLOODED
	segment_flooded.emit(self)

	# Force units out or drown them
	for unit in hidden_units:
		if is_instance_valid(unit):
			# Try to eject to nearest entrance
			var ejected: bool = false
			if entrance_a and entrance_a.has_method("emerge_unit"):
				entrance_a.emerge_unit(unit)
				ejected = true
			elif entrance_b and entrance_b.has_method("emerge_unit"):
				entrance_b.emerge_unit(unit)
				ejected = true

			if not ejected and unit.has_method("take_damage"):
				unit.take_damage(300, self)

	hidden_units.clear()


# =============================================================================
# PUBLIC API - Unit Movement
# =============================================================================

func can_accept_unit() -> bool:
	if state in [State.COLLAPSED, State.FLOODED]:
		return false
	return hidden_units.size() < max_capacity


func enter_unit(unit: Node3D) -> bool:
	if not can_accept_unit():
		return false

	hidden_units.append(unit)
	unit.visible = false
	unit.set_physics_process(false)

	unit_traversing.emit(self, unit)
	return true


func exit_unit(unit: Node3D, exit_entrance: Node3D = null) -> bool:
	if unit not in hidden_units:
		return false

	hidden_units.erase(unit)

	# Determine exit point
	var exit: Node3D = exit_entrance
	if not exit:
		exit = entrance_a if entrance_a else entrance_b

	if exit and exit.has_method("emerge_unit"):
		exit.emerge_unit(unit)
	else:
		# Emergency surface
		unit.global_position = global_position + Vector3(0, 1, 0)
		unit.visible = true
		unit.set_physics_process(true)

	# Check for booby traps if tunnel was discovered
	if state == State.DISCOVERED and booby_traps > 0:
		_trigger_trap(unit)

	return true


func get_traversal_time() -> float:
	return length / traversal_speed


# =============================================================================
# PUBLIC API - Supplies
# =============================================================================

func store_supplies(amount: float) -> float:
	if state in [State.COLLAPSED, State.FLOODED]:
		return 0.0

	var space: float = max_supply - supply_cache
	var to_store: float = minf(amount, space)
	supply_cache += to_store

	supply_cached.emit(self, to_store)
	return to_store


func withdraw_supplies(amount: float) -> float:
	var to_withdraw: float = minf(amount, supply_cache)
	supply_cache -= to_withdraw
	return to_withdraw


# =============================================================================
# PRIVATE
# =============================================================================

func _trigger_trap(victim: Node3D) -> void:
	if booby_traps <= 0:
		return

	booby_traps -= 1

	if victim.has_method("take_damage"):
		victim.take_damage(50, self)

	# Emit trap signal
	if BattleSignals:
		BattleSignals.trap_triggered.emit(self, victim)


# =============================================================================
# QUERIES
# =============================================================================

func is_passable() -> bool:
	return state in [State.HIDDEN, State.DISCOVERED]


func is_discovered() -> bool:
	return state != State.HIDDEN


func get_hidden_count() -> int:
	return hidden_units.size()


func get_supply_amount() -> float:
	return supply_cache


func connects_to(entrance: Node3D) -> bool:
	return entrance == entrance_a or entrance == entrance_b


func get_other_entrance(entrance: Node3D) -> Node3D:
	if entrance == entrance_a:
		return entrance_b
	elif entrance == entrance_b:
		return entrance_a
	return null


func get_status() -> Dictionary:
	return {
		"state": State.keys()[state],
		"type": SegmentType.keys()[segment_type],
		"integrity": structural_integrity,
		"units": hidden_units.size(),
		"capacity": max_capacity,
		"supplies": supply_cache,
		"traps": booby_traps,
		"discovered": is_discovered(),
	}
