class_name UnifiedJob
extends RefCounted
## UnifiedJob - Grid-aligned job data structure
## Replaces JobNode's scattered data with a clean, grid-aware structure.
## Jobs are always aligned to GridCoords.GAMEPLAY_CELL_SIZE (4m) cells.

const GridCoordsClass = preload("res://terrain/core/grid_coords.gd")
const GridResultClass = preload("res://terrain/core/grid_result.gd")

## Job types - unified from JobTypes.gd
enum Type {
	CLEAR_TERRAIN,    # Remove vegetation
	FLATTEN_AREA,     # Level terrain for construction
	BUILD_STRUCTURE,  # Construct a building
	BUILD_ROAD,       # Create road segment
	FILL_CRATER,      # Repair terrain damage
	DIG_TRENCH,       # Create defensive position
	LAY_WIRE,         # Place wire obstacles
}

## Job states - linear progression
enum State {
	PENDING,          # Waiting for prerequisites
	READY,            # Prerequisites met, can be worked
	IN_PROGRESS,      # Workers actively working
	COMPLETE,         # Job finished successfully
	CANCELLED,        # Job cancelled by player
	FAILED,           # Job failed (blocked, etc.)
}

## Job priority (lower = more urgent)
enum Priority {
	CRITICAL = 0,     # Combat/emergency repairs
	HIGH = 1,         # Player-ordered construction
	NORMAL = 2,       # Automatic prerequisite jobs
	LOW = 3,          # Background maintenance
}

## Unique job identifier
var job_id: int = 0

## Job type
var job_type: Type = Type.CLEAR_TERRAIN

## Current state
var state: State = State.PENDING

## Priority level
var priority: Priority = Priority.NORMAL

## Grid cell rectangle this job covers (in gameplay cells)
var cell_rect: Rect2i = Rect2i()

## Flat array of affected cell indices (for quick iteration)
var affected_cells: PackedInt64Array = PackedInt64Array()

## World-space bounds (for spatial queries)
var world_bounds: AABB = AABB()

## Work stages - progressive stages of completion
## Each stage has: {name: String, work_required: float, work_done: float}
var stages: Array[Dictionary] = []
var current_stage_index: int = 0

## Total work done vs required
var work_done: float = 0.0
var work_required: float = 100.0

## Prerequisite jobs that must complete before this job can start
var prerequisites: Array[UnifiedJob] = []

## Jobs blocked by this job (will be notified when this completes)
var blocked_jobs: Array[UnifiedJob] = []

## Workers currently assigned to this job
var assigned_workers: Array[Node3D] = []

## Maximum workers that can work on this job simultaneously
var max_workers: int = 4

## Work positions for workers (perimeter points for area jobs)
var work_positions: PackedVector3Array = PackedVector3Array()

## Claimed positions: worker_id (int) -> position_index (int)
## Prevents multiple workers from targeting the same position
var _claimed_positions: Dictionary = {}

## Metadata for job-specific data
var metadata: Dictionary = {}

## Reference to ClearingZoneNode (for CLEAR_TERRAIN jobs)
## Workers add work to this zone, which expands and clears trees
var clearing_zone: Node = null

## Reference to job visual node (ConstructionSiteNode, TrenchNode, etc.)
## This is the node-based visual representation of the job
var job_node: Node = null

## Signals
signal state_changed(job: UnifiedJob, old_state: State, new_state: State)
signal progress_updated(job: UnifiedJob, progress: float)
signal stage_completed(job: UnifiedJob, stage_index: int)
signal job_completed(job: UnifiedJob)
signal job_cancelled(job: UnifiedJob)
signal worker_assigned(job: UnifiedJob, worker: Node3D)
signal worker_unassigned(job: UnifiedJob, worker: Node3D)
signal prerequisite_completed(job: UnifiedJob, prereq: UnifiedJob)

## Static job ID counter
static var _next_job_id: int = 1


static func create(type: Type, center_world: Vector3, size_world: Vector2 = Vector2(4, 4)) -> UnifiedJob:
	"""Factory method to create a job with proper grid alignment"""
	var job := UnifiedJob.new()
	job.job_id = _next_job_id
	_next_job_id += 1
	job.job_type = type

	# Convert world position to grid cells
	var cell_size: float = GridCoordsClass.GAMEPLAY_CELL_SIZE

	# Calculate half-size in cells (minimum 1 cell)
	var half_cells := Vector2i(
		maxi(1, int(ceil(size_world.x / cell_size / 2.0))),
		maxi(1, int(ceil(size_world.y / cell_size / 2.0)))
	)

	# Get center cell
	var center_cell: Vector2i = GridCoordsClass.world_to_gameplay_clamped(center_world)

	# Build cell rect
	job.cell_rect = Rect2i(
		center_cell.x - half_cells.x,
		center_cell.y - half_cells.y,
		half_cells.x * 2,
		half_cells.y * 2
	)

	# Set max workers based on job area (more area = more workers can help)
	# Minimum 2, maximum 16 workers per job
	var cell_count: int = job.cell_rect.get_area()
	job.max_workers = clampi(cell_count / 2, 2, 16)

	# Build affected cells array
	job._rebuild_affected_cells()

	# Build world bounds
	job._rebuild_world_bounds()

	# Calculate work positions around perimeter
	job._calculate_work_positions()

	# Set default work required based on job type and size
	job.work_required = job._calculate_default_work()

	# Initialize stages based on job type
	job._initialize_stages()

	return job


func _rebuild_affected_cells() -> void:
	"""Rebuild flat array of affected cell indices"""
	affected_cells.clear()
	for x in range(cell_rect.position.x, cell_rect.end.x):
		for z in range(cell_rect.position.y, cell_rect.end.y):
			# Pack cell coords into int64: x in high bits, z in low bits
			var packed: int = (x << 32) | (z & 0xFFFFFFFF)
			affected_cells.append(packed)


func _rebuild_world_bounds() -> void:
	"""Rebuild world-space AABB from cell rect with actual terrain heights"""
	var cell_size: float = GridCoordsClass.GAMEPLAY_CELL_SIZE
	var min_pos := Vector3(
		cell_rect.position.x * cell_size,
		0.0,
		cell_rect.position.y * cell_size
	)
	var max_pos := Vector3(
		cell_rect.end.x * cell_size,
		10.0,  # Default height range
		cell_rect.end.y * cell_size
	)

	# Try to get actual terrain heights for AABB
	var terrain: Node = Engine.get_main_loop().root.get_node_or_null("/root/UnifiedTerrain")
	if not terrain:
		terrain = Engine.get_main_loop().root.get_node_or_null("/root/TerrainIntegration")

	if terrain and terrain.has_method("get_height_at"):
		# Sample corners to get min/max terrain height
		var heights: Array[float] = []
		heights.append(terrain.get_height_at(Vector3(min_pos.x, 0, min_pos.z)))
		heights.append(terrain.get_height_at(Vector3(max_pos.x, 0, min_pos.z)))
		heights.append(terrain.get_height_at(Vector3(min_pos.x, 0, max_pos.z)))
		heights.append(terrain.get_height_at(Vector3(max_pos.x, 0, max_pos.z)))
		heights.append(terrain.get_height_at(Vector3((min_pos.x + max_pos.x) * 0.5, 0, (min_pos.z + max_pos.z) * 0.5)))

		var min_h: float = heights[0]
		var max_h: float = heights[0]
		for h: float in heights:
			min_h = minf(min_h, h)
			max_h = maxf(max_h, h)

		min_pos.y = min_h - 1.0  # Slight buffer below
		max_pos.y = max_h + 5.0  # Buffer above for workers standing

	world_bounds = AABB(min_pos, max_pos - min_pos)


func _calculate_work_positions() -> void:
	"""Calculate work positions around the perimeter for workers"""
	work_positions.clear()
	var cell_size: float = GridCoordsClass.GAMEPLAY_CELL_SIZE

	# Calculate perimeter positions at edge of job area
	var min_x: float = cell_rect.position.x * cell_size
	var max_x: float = cell_rect.end.x * cell_size
	var min_z: float = cell_rect.position.y * cell_size
	var max_z: float = cell_rect.end.y * cell_size

	# Add positions along edges (1 meter outside bounds)
	var offset: float = 1.0
	var spacing: float = cell_size  # One position per cell width

	# Top edge
	var x: float = min_x
	while x < max_x:
		work_positions.append(Vector3(x + cell_size / 2, 0, min_z - offset))
		x += spacing

	# Bottom edge
	x = min_x
	while x < max_x:
		work_positions.append(Vector3(x + cell_size / 2, 0, max_z + offset))
		x += spacing

	# Left edge
	var z: float = min_z
	while z < max_z:
		work_positions.append(Vector3(min_x - offset, 0, z + cell_size / 2))
		z += spacing

	# Right edge
	z = min_z
	while z < max_z:
		work_positions.append(Vector3(max_x + offset, 0, z + cell_size / 2))
		z += spacing

	# Sample terrain height for each position
	_apply_terrain_heights()


## Apply actual terrain heights to work positions
## Called after initial calculation and when terrain changes
func _apply_terrain_heights() -> void:
	# Try UnifiedTerrain first (new system)
	var unified_terrain: Node = Engine.get_singleton("UnifiedTerrain") if Engine.has_singleton("UnifiedTerrain") else null
	if not unified_terrain:
		unified_terrain = Engine.get_main_loop().root.get_node_or_null("/root/UnifiedTerrain")

	# Fall back to TerrainIntegration
	var terrain_integration: Node = null
	if not unified_terrain:
		terrain_integration = Engine.get_main_loop().root.get_node_or_null("/root/TerrainIntegration")

	if not unified_terrain and not terrain_integration:
		return  # No terrain system available - positions stay at Y=0

	# Update Y values for all work positions
	for i in range(work_positions.size()):
		var pos := work_positions[i]
		if unified_terrain and unified_terrain.has_method("get_height_at"):
			pos.y = unified_terrain.get_height_at(pos)
		elif terrain_integration and terrain_integration.has_method("get_height_at"):
			pos.y = terrain_integration.get_height_at(pos)
		work_positions[i] = pos


## Refresh work positions from terrain (call when terrain changes)
func refresh_work_positions() -> void:
	_apply_terrain_heights()


func _calculate_default_work() -> float:
	"""Calculate default work required based on job type and size"""
	var cell_count: int = cell_rect.get_area()

	match job_type:
		Type.CLEAR_TERRAIN:
			return cell_count * 25.0  # 25 work per cell - visible progressive clearing
		Type.FLATTEN_AREA:
			return cell_count * 15.0  # 15 work per cell
		Type.BUILD_STRUCTURE:
			return 100.0 + cell_count * 5.0  # Base + size
		Type.BUILD_ROAD:
			return cell_count * 8.0
		Type.FILL_CRATER:
			return cell_count * 12.0
		Type.DIG_TRENCH:
			return cell_count * 20.0
		Type.LAY_WIRE:
			return cell_count * 5.0
		_:
			return cell_count * 10.0


func _initialize_stages() -> void:
	"""Initialize work stages based on job type"""
	stages.clear()

	match job_type:
		Type.CLEAR_TERRAIN:
			stages.append({"name": "Clearing", "work_required": work_required, "work_done": 0.0})

		Type.FLATTEN_AREA:
			var prep := work_required * 0.3
			var level := work_required * 0.7
			stages.append({"name": "Preparation", "work_required": prep, "work_done": 0.0})
			stages.append({"name": "Leveling", "work_required": level, "work_done": 0.0})

		Type.BUILD_STRUCTURE:
			var foundation := work_required * 0.3
			var structure := work_required * 0.5
			var finishing := work_required * 0.2
			stages.append({"name": "Foundation", "work_required": foundation, "work_done": 0.0})
			stages.append({"name": "Structure", "work_required": structure, "work_done": 0.0})
			stages.append({"name": "Finishing", "work_required": finishing, "work_done": 0.0})

		_:
			stages.append({"name": "Working", "work_required": work_required, "work_done": 0.0})

	current_stage_index = 0


## State Management

func can_be_worked() -> bool:
	"""Check if this job can currently be worked on"""
	if state == State.COMPLETE or state == State.CANCELLED or state == State.FAILED:
		return false

	# Check all prerequisites are complete
	for prereq in prerequisites:
		if is_instance_valid(prereq) and prereq.state != State.COMPLETE:
			return false

	return true


func set_state(new_state: State) -> void:
	"""Change job state with signal emission"""
	if new_state == state:
		return

	var old_state: State = state
	state = new_state
	state_changed.emit(self, old_state, new_state)

	if new_state == State.COMPLETE:
		job_completed.emit(self)
		_notify_blocked_jobs()
	elif new_state == State.CANCELLED:
		job_cancelled.emit(self)


func _notify_blocked_jobs() -> void:
	"""Notify jobs blocked by this one that it's complete"""
	for blocked in blocked_jobs:
		if is_instance_valid(blocked):
			blocked.prerequisite_completed.emit(blocked, self)
			# Check if blocked job is now ready
			if blocked.can_be_worked() and blocked.state == State.PENDING:
				blocked.set_state(State.READY)


## Work Management

func add_work(amount: float) -> void:
	"""Add work to the job, advancing stages as needed"""
	if not can_be_worked():
		return

	if state == State.READY:
		set_state(State.IN_PROGRESS)

	# Add to current stage
	var stage: Dictionary = stages[current_stage_index]
	stage.work_done += amount
	work_done += amount

	# Check if stage complete
	while current_stage_index < stages.size():
		stage = stages[current_stage_index]
		if stage.work_done >= stage.work_required:
			# Stage complete
			stage_completed.emit(self, current_stage_index)
			current_stage_index += 1

			if current_stage_index >= stages.size():
				# All stages complete
				set_state(State.COMPLETE)
				return
		else:
			break

	progress_updated.emit(self, get_progress())


func get_progress() -> float:
	"""Get overall progress 0.0 to 1.0"""
	if work_required <= 0:
		return 1.0
	return clampf(work_done / work_required, 0.0, 1.0)


func get_stage_progress() -> float:
	"""Get current stage progress 0.0 to 1.0"""
	if current_stage_index >= stages.size():
		return 1.0
	var stage: Dictionary = stages[current_stage_index]
	if stage.work_required <= 0:
		return 1.0
	return clampf(stage.work_done / stage.work_required, 0.0, 1.0)


func get_current_stage_name() -> String:
	"""Get name of current work stage"""
	if current_stage_index >= stages.size():
		return "Complete"
	return stages[current_stage_index].get("name", "Working")


## Worker Management

func assign_worker(worker: Node3D) -> bool:
	"""Assign a worker to this job"""
	if not is_instance_valid(worker):
		return false

	if worker in assigned_workers:
		return true  # Already assigned

	if assigned_workers.size() >= max_workers:
		return false  # No room

	assigned_workers.append(worker)
	worker_assigned.emit(self, worker)
	return true


func unassign_worker(worker: Node3D) -> void:
	"""Remove a worker from this job"""
	if worker in assigned_workers:
		assigned_workers.erase(worker)
		# Release claimed position
		var worker_id: int = worker.get_instance_id()
		if _claimed_positions.has(worker_id):
			_claimed_positions.erase(worker_id)
		worker_unassigned.emit(self, worker)


func get_work_position(worker: Node3D) -> Vector3:
	"""Get the best work position for a worker (nearest UNCLAIMED perimeter point)"""
	if work_positions.is_empty():
		return get_centroid()

	if not is_instance_valid(worker):
		return work_positions[0]

	var worker_id: int = worker.get_instance_id()

	# If worker already has a claimed position, return it
	if _claimed_positions.has(worker_id):
		var pos_idx: int = _claimed_positions[worker_id]
		if pos_idx < work_positions.size():
			return work_positions[pos_idx]

	# Clean up stale claims (workers that no longer exist)
	var stale_ids: Array = []
	for claimed_worker_id in _claimed_positions:
		# instance_from_id returns null if object no longer exists
		if not is_instance_valid(instance_from_id(claimed_worker_id)):
			stale_ids.append(claimed_worker_id)
	for stale_id in stale_ids:
		_claimed_positions.erase(stale_id)

	# Build set of claimed position indices
	var claimed_indices: Dictionary = {}
	for claimed_worker_id in _claimed_positions:
		claimed_indices[_claimed_positions[claimed_worker_id]] = true

	# Find nearest UNCLAIMED position
	var best_pos: Vector3 = work_positions[0]
	var best_idx: int = 0
	var best_dist_sq: float = INF
	var found_unclaimed: bool = false

	for i in range(work_positions.size()):
		# Skip claimed positions
		if claimed_indices.has(i):
			continue

		found_unclaimed = true
		var pos: Vector3 = work_positions[i]
		var dist_sq: float = worker.global_position.distance_squared_to(pos)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_pos = pos
			best_idx = i

	# If all positions claimed, fall back to nearest (will share position)
	if not found_unclaimed:
		for i in range(work_positions.size()):
			var pos: Vector3 = work_positions[i]
			var dist_sq: float = worker.global_position.distance_squared_to(pos)
			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				best_pos = pos
				best_idx = i

	# Claim this position for the worker
	_claimed_positions[worker_id] = best_idx

	return best_pos


func is_worker_in_range(worker: Node3D, work_range: float = 3.0) -> bool:
	"""Check if worker is close enough to work on this job"""
	if not is_instance_valid(worker):
		return false

	# Check if within range of job bounds
	var worker_pos: Vector3 = worker.global_position
	var closest: Vector3 = Vector3(
		clampf(worker_pos.x, world_bounds.position.x, world_bounds.end.x),
		worker_pos.y,
		clampf(worker_pos.z, world_bounds.position.z, world_bounds.end.z)
	)

	return worker_pos.distance_to(closest) <= work_range


## Spatial Queries

func get_centroid() -> Vector3:
	"""Get center point of job area"""
	return world_bounds.get_center()


func overlaps_region(region: Rect2i) -> bool:
	"""Check if this job overlaps with a grid region"""
	return cell_rect.intersects(region)


func contains_cell(cell: Vector2i) -> bool:
	"""Check if job contains a specific grid cell"""
	return cell_rect.has_point(cell)


func overlaps_world_bounds(bounds: AABB) -> bool:
	"""Check if job overlaps with world-space bounds"""
	return world_bounds.intersects(bounds)


## Prerequisites

func add_prerequisite(prereq: UnifiedJob) -> void:
	"""Add a prerequisite job that must complete before this one"""
	if prereq and prereq not in prerequisites:
		prerequisites.append(prereq)
		prereq.blocked_jobs.append(self)


func remove_prerequisite(prereq: UnifiedJob) -> void:
	"""Remove a prerequisite"""
	if prereq in prerequisites:
		prerequisites.erase(prereq)
		prereq.blocked_jobs.erase(self)


func get_all_prerequisites() -> Array[UnifiedJob]:
	"""Get all prerequisites recursively"""
	var result: Array[UnifiedJob] = []
	var to_check: Array[UnifiedJob] = prerequisites.duplicate()

	while not to_check.is_empty():
		var prereq: UnifiedJob = to_check.pop_back()
		if is_instance_valid(prereq) and prereq not in result:
			result.append(prereq)
			for nested in prereq.prerequisites:
				if is_instance_valid(nested) and nested not in result:
					to_check.append(nested)

	return result


## Type Helpers

static func get_type_name(type: Type) -> String:
	"""Get display name for job type"""
	match type:
		Type.CLEAR_TERRAIN: return "Clear Terrain"
		Type.FLATTEN_AREA: return "Flatten Area"
		Type.BUILD_STRUCTURE: return "Build Structure"
		Type.BUILD_ROAD: return "Build Road"
		Type.FILL_CRATER: return "Fill Crater"
		Type.DIG_TRENCH: return "Dig Trench"
		Type.LAY_WIRE: return "Lay Wire"
		_: return "Unknown"


static func get_state_name(s: State) -> String:
	"""Get display name for job state"""
	match s:
		State.PENDING: return "Pending"
		State.READY: return "Ready"
		State.IN_PROGRESS: return "In Progress"
		State.COMPLETE: return "Complete"
		State.CANCELLED: return "Cancelled"
		State.FAILED: return "Failed"
		_: return "Unknown"


func _to_string() -> String:
	return "UnifiedJob #%d (%s) [%s] %.0f%%" % [
		job_id,
		UnifiedJob.get_type_name(job_type),
		UnifiedJob.get_state_name(state),
		get_progress() * 100
	]
