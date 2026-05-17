extends Node
## TerrainClearingSystem - Autoload singleton
## Access via: TerrainClearingSystem.is_cleared(pos)
##
## Thin wrapper around ClearingSystem autoload.
## Maintains backward compatibility with firebase construction code
## while delegating actual clearing logic to the new terrain engine.

## Terrain Clearing System - Manages jungle clearing for firebase construction
## Engineers must clear terrain before buildings can be placed

signal clearing_started(position: Vector3, radius: float)
signal clearing_progress(position: Vector3, progress: float)
signal clearing_complete(position: Vector3, radius: float)

## Local ClearingState enum maps 1:1 to ClearingSystem.ClearingStage
enum ClearingState {
	JUNGLE,              # Dense vegetation - cannot build
	PARTIALLY_CLEARED,   # Trees down, stumps remain
	CLEARED,             # Flat, buildable
	FORTIFIED,           # Firebase perimeter established
}

## Configuration (used for work-to-progress conversion)
const CLEARING_RATE := 2.0  # Work units per engineer per second
const JUNGLE_WORK := 50.0   # Work to clear jungle
const STUMPS_WORK := 30.0   # Work to remove stumps


## Wrapper class maintaining backward compatibility with engineer assignment
class ClearingOperation:
	var center: Vector3
	var radius: float
	var state: int  # ClearingState
	var zone_id: int = -1  # ID in ClearingSystem
	var work_done: float = 0.0
	var work_required: float
	var assigned_engineers: Array[Node3D] = []

	func _init(pos: Vector3, r: float, z_id: int) -> void:
		center = pos
		radius = r
		zone_id = z_id
		state = 0  # ClearingState.JUNGLE
		work_required = JUNGLE_WORK * r * r * 0.1  # Scale with area


## Active clearing operations (zone_id -> ClearingOperation)
var _operations: Dictionary = {}

## Cleared areas cache (position key -> data)
var cleared_areas: Dictionary = {}


func _ready() -> void:
	# Connect to ClearingSystem signals
	if ClearingSystem:
		ClearingSystem.clearing_started.connect(_on_clearing_system_started)
		ClearingSystem.clearing_progress.connect(_on_clearing_system_progress)
		ClearingSystem.clearing_completed.connect(_on_clearing_system_completed)
	else:
		push_warning("[TerrainClearingSystem] ClearingSystem autoload not found")

	print("[TerrainClearingSystem] Initialized (delegating to ClearingSystem)")


func _process(delta: float) -> void:
	_update_clearing_operations(delta)


func _update_clearing_operations(delta: float) -> void:
	"""Update all active clearing operations by delegating work to ClearingSystem"""
	for zone_id: int in _operations:
		var op: ClearingOperation = _operations[zone_id]

		# Calculate work from engineers
		var engineer_count: int = op.assigned_engineers.size()
		if engineer_count == 0:
			continue

		var work: float = engineer_count * CLEARING_RATE * delta
		op.work_done += work

		# Convert work to progress (0-1) and delegate to ClearingSystem
		if op.work_required > 0.0:
			var progress_delta: float = work / op.work_required
			if ClearingSystem:
				ClearingSystem.advance_clearing(op.zone_id, progress_delta)


## Signal handlers from ClearingSystem

func _on_clearing_system_started(zone_id: int, position: Vector3) -> void:
	# Only forward if we created this zone (has operation)
	if _operations.has(zone_id):
		var op: ClearingOperation = _operations[zone_id]
		clearing_started.emit(position, op.radius)


func _on_clearing_system_progress(zone_id: int, progress: float) -> void:
	if not _operations.has(zone_id):
		return

	var op: ClearingOperation = _operations[zone_id]

	# Update local state from ClearingSystem zone
	if ClearingSystem and ClearingSystem.zones.has(zone_id):
		var zone: ClearingSystem.ClearingZone = ClearingSystem.zones[zone_id]
		op.state = _map_stage_to_state(zone.stage)

		# Update work required for current stage
		match op.state:
			ClearingState.JUNGLE:
				op.work_required = JUNGLE_WORK * op.radius * op.radius * 0.1
			ClearingState.PARTIALLY_CLEARED:
				op.work_required = STUMPS_WORK * op.radius * op.radius * 0.1
			_:
				op.work_required = 0.0

		# Reset work done when stage changes
		if zone.progress < 0.1:  # Stage just changed
			op.work_done = 0.0

	clearing_progress.emit(op.center, progress)


func _on_clearing_system_completed(zone_id: int) -> void:
	if not _operations.has(zone_id):
		return

	var op: ClearingOperation = _operations[zone_id]
	op.state = ClearingState.FORTIFIED

	# Register as cleared area
	_register_cleared_area(op.center, op.radius, ClearingState.CLEARED)

	# Emit local signal
	clearing_complete.emit(op.center, op.radius)

	# Forward to BattleSignals
	if BattleSignals:
		BattleSignals.terrain_cleared.emit(op.center, op.radius)

	# Clean up operation
	_operations.erase(zone_id)


## Enum mapping

func _map_stage_to_state(stage: ClearingSystem.ClearingStage) -> ClearingState:
	"""Map ClearingSystem.ClearingStage to local ClearingState enum"""
	match stage:
		ClearingSystem.ClearingStage.JUNGLE:
			return ClearingState.JUNGLE
		ClearingSystem.ClearingStage.PARTIALLY_CLEARED:
			return ClearingState.PARTIALLY_CLEARED
		ClearingSystem.ClearingStage.CLEARED:
			return ClearingState.CLEARED
		ClearingSystem.ClearingStage.FORTIFIED:
			return ClearingState.FORTIFIED
		_:
			return ClearingState.JUNGLE


func _map_state_to_stage(state: ClearingState) -> ClearingSystem.ClearingStage:
	"""Map local ClearingState to ClearingSystem.ClearingStage enum"""
	match state:
		ClearingState.JUNGLE:
			return ClearingSystem.ClearingStage.JUNGLE
		ClearingState.PARTIALLY_CLEARED:
			return ClearingSystem.ClearingStage.PARTIALLY_CLEARED
		ClearingState.CLEARED:
			return ClearingSystem.ClearingStage.CLEARED
		ClearingState.FORTIFIED:
			return ClearingSystem.ClearingStage.FORTIFIED
		_:
			return ClearingSystem.ClearingStage.JUNGLE


func _register_cleared_area(center: Vector3, radius: float, state: ClearingState) -> void:
	"""Register a cleared area in local cache"""
	var key: String = "%d_%d" % [int(center.x), int(center.z)]
	cleared_areas[key] = {
		"center": center,
		"radius": radius,
		"state": state
	}


## Public API

func start_clearing(position: Vector3, radius: float = 10.0) -> ClearingOperation:
	"""Start clearing terrain at a position"""
	# Check if already cleared
	if is_cleared(position):
		return null

	# Delegate zone creation to ClearingSystem
	var zone_id: int = -1
	if ClearingSystem:
		zone_id = ClearingSystem.create_zone(position, radius)

	if zone_id < 0:
		push_error("[TerrainClearingSystem] Failed to create clearing zone")
		return null

	# Create wrapper operation for engineer assignment
	var op := ClearingOperation.new(position, radius, zone_id)
	_operations[zone_id] = op

	print("[TerrainClearingSystem] Started clearing at %s (zone_id=%d)" % [position, zone_id])

	return op


func assign_engineer_to_clearing(engineer: Node3D, operation: ClearingOperation) -> void:
	"""Assign engineer to work on clearing"""
	if operation and engineer not in operation.assigned_engineers:
		operation.assigned_engineers.append(engineer)


func unassign_engineer(engineer: Node3D, operation: ClearingOperation) -> void:
	"""Remove engineer from clearing operation"""
	if operation:
		operation.assigned_engineers.erase(engineer)


func is_cleared(position: Vector3) -> bool:
	"""Check if position is cleared for building"""
	# First check ClearingSystem zones
	if ClearingSystem:
		for zone_id: int in ClearingSystem.zones:
			var zone: ClearingSystem.ClearingZone = ClearingSystem.zones[zone_id]
			if position.distance_to(zone.center) <= zone.radius:
				return zone.stage >= ClearingSystem.ClearingStage.CLEARED

	# Fall back to local cache
	for key: String in cleared_areas:
		var area: Dictionary = cleared_areas[key]
		var center: Vector3 = area["center"]
		var radius: float = area["radius"]
		var state: int = area["state"]

		if position.distance_to(center) <= radius:
			return state >= ClearingState.CLEARED

	return false


func get_clearing_state(position: Vector3) -> ClearingState:
	"""Get the clearing state at a position"""
	# First check ClearingSystem zones
	if ClearingSystem:
		for zone_id: int in ClearingSystem.zones:
			var zone: ClearingSystem.ClearingZone = ClearingSystem.zones[zone_id]
			if position.distance_to(zone.center) <= zone.radius:
				return _map_stage_to_state(zone.stage)

	# Fall back to local cache
	for key: String in cleared_areas:
		var area: Dictionary = cleared_areas[key]
		var center: Vector3 = area["center"]
		var radius: float = area["radius"]

		if position.distance_to(center) <= radius:
			return area["state"] as ClearingState

	return ClearingState.JUNGLE


func get_active_clearing_at(position: Vector3) -> ClearingOperation:
	"""Get active clearing operation at position"""
	for zone_id: int in _operations:
		var op: ClearingOperation = _operations[zone_id]
		if position.distance_to(op.center) <= op.radius:
			return op
	return null


func instant_clear(position: Vector3, radius: float = 10.0) -> void:
	"""Instantly clear an area (for napalm, explosions, etc.)"""
	# Create zone and immediately set to CLEARED stage
	if ClearingSystem:
		var zone_id: int = ClearingSystem.create_zone(position, radius)
		ClearingSystem.set_zone_stage(zone_id, ClearingSystem.ClearingStage.CLEARED)

	# Register locally
	_register_cleared_area(position, radius, ClearingState.CLEARED)

	# Emit signals
	clearing_complete.emit(position, radius)

	if BattleSignals:
		BattleSignals.terrain_cleared.emit(position, radius)

	print("[TerrainClearingSystem] Instant clear at %s" % position)


func get_cleared_area_count() -> int:
	"""Get total number of cleared areas"""
	if ClearingSystem:
		return ClearingSystem.zones.size()
	return cleared_areas.size()


## Additional utility methods

func get_operation_by_zone_id(zone_id: int) -> ClearingOperation:
	"""Get operation by its ClearingSystem zone ID"""
	return _operations.get(zone_id, null)


func get_all_active_operations() -> Array[ClearingOperation]:
	"""Get all active clearing operations"""
	var result: Array[ClearingOperation] = []
	for zone_id: int in _operations:
		result.append(_operations[zone_id])
	return result


## =============================================================================
## VISUAL PROGRESS FOR JOB NODES
## =============================================================================

## Dictionary of clearing visuals (zone_id -> ClearingVisualData)
var _clearing_visuals: Dictionary = {}


class ClearingVisualData:
	var zone_center: Vector3
	var zone_radius: float
	var stumps: Array[MeshInstance3D] = []
	var progress: float = 0.0


## Set visual progress for a clearing zone (0.0 to 1.0)
## Creates placeholder stumps that shrink as progress increases
func set_clearing_visual_progress(position: Vector3, radius: float, progress: float) -> void:
	var key: String = "%d_%d" % [int(position.x), int(position.z)]

	if key not in _clearing_visuals:
		_create_clearing_visual(position, radius, key)

	var visual: ClearingVisualData = _clearing_visuals[key]
	visual.progress = clampf(progress, 0.0, 1.0)

	_update_clearing_visual(visual)


func _create_clearing_visual(position: Vector3, radius: float, key: String) -> void:
	"""Create placeholder vegetation stumps for a clearing zone"""
	var visual := ClearingVisualData.new()
	visual.zone_center = position
	visual.zone_radius = radius
	visual.progress = 0.0

	# Create stump meshes in a grid pattern
	var stump_spacing := 4.0
	var half_radius := radius * 0.8
	var terrain := get_node_or_null("/root/TerrainIntegration")

	var x := -half_radius
	while x <= half_radius:
		var z := -half_radius
		while z <= half_radius:
			# Check if within circle
			if Vector2(x, z).length() <= half_radius:
				var stump := _create_stump_mesh()
				var stump_pos := position + Vector3(x, 0, z)

				# Add random offset
				stump_pos.x += randf_range(-1.0, 1.0)
				stump_pos.z += randf_range(-1.0, 1.0)

				# Get terrain height
				if terrain and terrain.has_method("get_height_at"):
					stump_pos.y = terrain.get_height_at(stump_pos)

				stump.global_position = stump_pos
				stump.scale = Vector3(1.0, randf_range(0.8, 1.5), 1.0)

				get_tree().current_scene.add_child(stump)
				visual.stumps.append(stump)

			z += stump_spacing
		x += stump_spacing

	_clearing_visuals[key] = visual


func _create_stump_mesh() -> MeshInstance3D:
	"""Create a placeholder tree stump mesh"""
	var stump := MeshInstance3D.new()
	stump.name = "TreeStump"

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.4
	cyl.height = 1.5
	stump.mesh = cyl

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.35, 0.25)  # Brown
	stump.material_override = mat

	return stump


func _update_clearing_visual(visual: ClearingVisualData) -> void:
	"""Update stump scales based on clearing progress"""
	# Stumps shrink as progress increases
	var scale_factor: float = 1.0 - visual.progress

	for stump in visual.stumps:
		if is_instance_valid(stump):
			var base_height: float = stump.scale.y
			stump.scale = Vector3(scale_factor, base_height * scale_factor, scale_factor)

			# Hide when very small
			stump.visible = scale_factor > 0.1

	# Remove visuals when complete
	if visual.progress >= 1.0:
		_remove_clearing_visual(visual)


func _remove_clearing_visual(visual: ClearingVisualData) -> void:
	"""Remove all stump meshes for a clearing zone"""
	for stump in visual.stumps:
		if is_instance_valid(stump):
			stump.queue_free()
	visual.stumps.clear()


func clear_all_visuals() -> void:
	"""Remove all clearing visual effects"""
	for key in _clearing_visuals:
		var visual: ClearingVisualData = _clearing_visuals[key]
		_remove_clearing_visual(visual)
	_clearing_visuals.clear()
