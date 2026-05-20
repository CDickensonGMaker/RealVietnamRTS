extends Node
## JobSystem - Single Authoritative Job Manager
## Replaces: JobManager + BuilderAI job management + ConstructionManager job parts
##
## KEY PRINCIPLE: This is the ONLY system that creates, tracks, and manages jobs.
## Workers find jobs via heuristic scoring (bottom-up), not assigned by manager (top-down).
##
## NODE-BASED ARCHITECTURE:
## Each job type creates a corresponding visual node:
## - CLEAR_TERRAIN -> ClearingZoneNode (via TreeNodeManager)
## - BUILD_STRUCTURE -> ConstructionSiteNode
## - DIG_TRENCH -> TrenchNode
## - LAY_WIRE -> WireObstacleNode
## - BUILD_ROAD -> RoadSegmentNode
## - FILL_CRATER -> (targets existing CraterNode)

const GridCoordsClass = preload("res://terrain/core/grid_coords.gd")
const GridResultClass = preload("res://terrain/core/grid_result.gd")
const UnifiedJobClass = preload("res://firebase_system/job_system/unified_job.gd")

# Node class preloads
const ConstructionSiteNodeClass = preload("res://firebase_system/nodes/construction_site_node.gd")
const TrenchNodeClass = preload("res://firebase_system/nodes/trench_node.gd")
const WireObstacleNodeClass = preload("res://firebase_system/nodes/wire_obstacle_node.gd")
const RoadSegmentNodeClass = preload("res://firebase_system/nodes/road_segment_node.gd")
const CraterNodeClass = preload("res://terrain/nodes/crater_node.gd")
const BuildingDataClass = preload("res://firebase_system/building_data.gd")

## Signals
signal job_created(job: UnifiedJobClass)
signal job_completed(job: UnifiedJobClass)
signal job_cancelled(job: UnifiedJobClass)
signal job_ready(job: UnifiedJobClass)  # Emitted when prerequisites complete
signal worker_needed(job: UnifiedJobClass)  # Job has room for more workers

## All active jobs (indexed by job_id)
var jobs: Dictionary = {}  # int -> UnifiedJob

## Spatial index for fast region queries
var _job_grid: Dictionary = {}  # Vector2i (cell) -> Array[UnifiedJob]

## Jobs by state for quick filtering
var _pending_jobs: Array[UnifiedJobClass] = []
var _ready_jobs: Array[UnifiedJobClass] = []
var _in_progress_jobs: Array[UnifiedJobClass] = []

## Configuration
@export var job_update_interval: float = 0.1  # How often to check job states
var _update_timer: float = 0.0

## Container for job-related nodes
var _node_container: Node3D = null


func _ready() -> void:
	# Create container for job nodes
	_node_container = Node3D.new()
	_node_container.name = "JobNodes"
	add_child(_node_container)

	# Connect to terrain system signals
	_connect_terrain_signals()
	print("[JobSystem] Initialized - Single authority job management with node-based architecture")


func _connect_terrain_signals() -> void:
	"""Connect to terrain signals for job position updates"""
	# Try UnifiedTerrain first (new system)
	var unified_terrain: Node = get_node_or_null("/root/UnifiedTerrain")
	if unified_terrain:
		if unified_terrain.has_signal("terrain_modified"):
			unified_terrain.terrain_modified.connect(_on_terrain_modified)
			print("[JobSystem] Connected to UnifiedTerrain.terrain_modified")
		if unified_terrain.has_signal("vegetation_changed"):
			unified_terrain.vegetation_changed.connect(_on_vegetation_changed)
			print("[JobSystem] Connected to UnifiedTerrain.vegetation_changed")
		return

	# Fallback to TerrainIntegration
	var terrain_intg: Node = get_node_or_null("/root/TerrainIntegration")
	if terrain_intg:
		# Check for terrain_grid cell_updated signal
		var terrain_grid = terrain_intg.get("terrain_grid")
		if terrain_grid and terrain_grid.has_signal("cell_updated"):
			terrain_grid.cell_updated.connect(_on_terrain_modified)
			print("[JobSystem] Connected to TerrainGrid.cell_updated")


func _on_terrain_modified(region: Rect2i) -> void:
	"""Handle terrain modification - refresh job work positions and check completion"""
	# Refresh work positions for affected jobs
	var affected_jobs: Array[UnifiedJobClass] = get_jobs_in_region(region)
	for job in affected_jobs:
		if is_instance_valid(job):
			job.refresh_work_positions()

	# Check if jobs can now be worked or are complete
	on_terrain_updated(region)


func _on_vegetation_changed(region: Rect2i) -> void:
	"""Handle vegetation changes - check clearing job completion"""
	var affected_jobs: Array[UnifiedJobClass] = get_jobs_in_region(region)
	for job in affected_jobs:
		if not is_instance_valid(job):
			continue
		if job.job_type == UnifiedJobClass.Type.CLEAR_TERRAIN:
			_check_clearing_complete(job)


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= job_update_interval:
		_update_timer = 0.0
		_update_job_states()


func _update_job_states() -> void:
	"""Check for jobs that have become ready or need workers"""
	# Check pending jobs for prerequisite completion
	var newly_ready: Array[UnifiedJobClass] = []

	for job in _pending_jobs:
		if not is_instance_valid(job):
			continue
		if job.can_be_worked():
			newly_ready.append(job)

	# Move newly ready jobs
	for job in newly_ready:
		_pending_jobs.erase(job)
		_ready_jobs.append(job)
		job.set_state(UnifiedJobClass.State.READY)
		job_ready.emit(job)

		# Signal that workers are needed
		if job.assigned_workers.size() < job.max_workers:
			worker_needed.emit(job)

	# Check ready/in-progress jobs for worker needs
	for job in _ready_jobs + _in_progress_jobs:
		if not is_instance_valid(job):
			continue
		if job.assigned_workers.size() < job.max_workers:
			worker_needed.emit(job)


## =============================================================================
## JOB CREATION
## =============================================================================

func create_job(type: UnifiedJobClass.Type, center: Vector3, size: Vector2 = Vector2(4, 4), priority: UnifiedJobClass.Priority = UnifiedJobClass.Priority.NORMAL) -> UnifiedJobClass:
	"""Create a new job at the specified location"""
	var job: UnifiedJobClass = UnifiedJobClass.create(type, center, size)
	job.priority = priority

	# Create the appropriate visual node for this job type
	_create_job_node(job, center, size)

	_register_job(job)

	print("[JobSystem] Created job #%d: %s at %s (size: %s)" % [
		job.job_id,
		UnifiedJobClass.get_type_name(type),
		center,
		size
	])

	return job


func _create_job_node(job: UnifiedJobClass, center: Vector3, size: Vector2) -> void:
	"""Create the visual node corresponding to job type"""
	match job.job_type:
		UnifiedJobClass.Type.CLEAR_TERRAIN:
			# ClearingZoneNode via TreeNodeManager
			var tree_mgr: Node = get_node_or_null("/root/TreeNodeManager")
			if tree_mgr and tree_mgr.has_method("prepare_clearing_zone"):
				var radius: float = maxf(size.x, size.y) * 0.5
				var zone: Node = tree_mgr.prepare_clearing_zone(center, radius)
				job.clearing_zone = zone
				job.metadata["job_node"] = zone
			# NOTE: mark_area_cleared() is now called in _on_job_completed() so
			# billboards remain visible until workers actually finish the job

		UnifiedJobClass.Type.BUILD_STRUCTURE:
			# ConstructionSiteNode
			var building_type: int = job.metadata.get("building_type", 0)
			var rotation: float = job.metadata.get("rotation", 0.0)
			var site: Node = ConstructionSiteNodeClass.create(center, building_type, rotation, size)
			_node_container.add_child(site)
			job.metadata["job_node"] = site
			# Wire signals
			site.construction_complete.connect(_on_construction_complete.bind(job))

		UnifiedJobClass.Type.DIG_TRENCH:
			# TrenchNode
			var trench_rotation: float = job.metadata.get("rotation", 0.0)
			var trench: Node = TrenchNodeClass.create(center, size.x, size.y, trench_rotation)
			_node_container.add_child(trench)
			job.metadata["job_node"] = trench
			# Wire signals
			trench.trench_complete.connect(_on_trench_complete.bind(job))

		UnifiedJobClass.Type.LAY_WIRE:
			# WireObstacleNode
			var wire_type: int = job.metadata.get("wire_type", 0)  # WireType.BARBED
			var faction: int = job.metadata.get("faction", 0)  # GameEnums.Faction.US_ARMY
			var wire_rotation: float = job.metadata.get("rotation", 0.0)
			var wire: Node = WireObstacleNodeClass.create(center, wire_type, size.x, faction, wire_rotation)
			_node_container.add_child(wire)
			job.metadata["job_node"] = wire
			# Wire signals
			wire.wire_complete.connect(_on_wire_complete.bind(job))

		UnifiedJobClass.Type.BUILD_ROAD:
			# RoadSegmentNode - needs path points
			var points: PackedVector3Array = job.metadata.get("path_points", PackedVector3Array())
			if points.is_empty():
				# Create simple two-point path from job bounds
				var half_x: float = size.x * 0.5
				points.append(center + Vector3(-half_x, 0, 0))
				points.append(center + Vector3(half_x, 0, 0))
			var road: Node = RoadSegmentNodeClass.create(points, size.y)  # width from size.y
			_node_container.add_child(road)
			job.metadata["job_node"] = road
			job.metadata["path_points"] = points
			# Wire signals
			road.road_complete.connect(_on_road_complete.bind(job))

		UnifiedJobClass.Type.FILL_CRATER:
			# Find existing CraterNode at location
			var crater: Node = _find_crater_at(center)
			if crater:
				job.metadata["job_node"] = crater
			# No new node created - we're filling an existing crater

		UnifiedJobClass.Type.FLATTEN_AREA:
			# No visual node for flattening - terrain system handles visuals
			pass


func create_area_job(type: UnifiedJobClass.Type, min_corner: Vector3, max_corner: Vector3, priority: UnifiedJobClass.Priority = UnifiedJobClass.Priority.NORMAL) -> UnifiedJobClass:
	"""Create a job covering a rectangular area"""
	var center: Vector3 = (min_corner + max_corner) / 2.0
	var size := Vector2(
		absf(max_corner.x - min_corner.x),
		absf(max_corner.z - min_corner.z)
	)
	return create_job(type, center, size, priority)


func create_build_job(center: Vector3, building_type: int, rotation: float = 0.0, footprint_size: Vector2 = Vector2(4, 4), skip_validation: bool = false) -> UnifiedJobClass:
	"""Create a building construction job with automatic clear/flatten prerequisites.
	Returns null if validation fails or insufficient supply at nearest firebase.
	Set skip_validation=true to bypass placement checks (for testing)."""
	# Get building data for supply cost
	var data: BuildingDataClass = BuildingDataClass.get_building_data(building_type)
	if not data:
		push_error("[JobSystem] Unknown building type: %d" % building_type)
		return null

	# Validate placement (overlap, slope, water)
	if not skip_validation:
		var validation: Dictionary = validate_placement(center, footprint_size, building_type)
		if not validation.valid:
			push_warning("[JobSystem] Cannot build %s: %s" % [data.display_name, validation.message])
			return null

	# Find nearest firebase for supply check
	var firebase: Node = _get_nearest_firebase(center)
	var supply_cost: int = data.supply_cost

	# Check supply (skip for free buildings like light sandbags)
	if supply_cost > 0:
		if not firebase:
			push_warning("[JobSystem] No firebase found for supply check - building %s" % data.display_name)
			# Allow building anyway but warn (for testing without firebase)
		elif firebase.supply_level < supply_cost:
			push_warning("[JobSystem] Insufficient supply for %s (need %d, have %.0f)" % [
				data.display_name, supply_cost, firebase.supply_level
			])
			return null
		else:
			# Deduct supply now (not when ghost placed)
			firebase.supply_level -= supply_cost
			print("[JobSystem] Deducted %d supply for %s (%.0f remaining)" % [
				supply_cost, data.display_name, firebase.supply_level
			])
			# Emit supply consumed signal for HUD update
			if BattleSignals:
				BattleSignals.supply_consumed.emit(firebase, float(supply_cost), "construction: " + data.display_name)

	# Create prerequisite jobs
	var prereqs: Dictionary = _create_prerequisites(center, footprint_size, rotation)

	# Create build job
	var build_job: UnifiedJobClass = create_job(
		UnifiedJobClass.Type.BUILD_STRUCTURE,
		center,
		footprint_size,
		UnifiedJobClass.Priority.HIGH
	)
	build_job.metadata["building_type"] = building_type
	build_job.metadata["rotation"] = rotation

	# Store supply info for refund on cancel (Phase 4)
	build_job.metadata["supply_cost"] = supply_cost
	if firebase:
		build_job.metadata["firebase"] = firebase

	# Add prerequisites
	if prereqs.flatten_job:
		build_job.add_prerequisite(prereqs.flatten_job)
	elif prereqs.clear_job:
		build_job.add_prerequisite(prereqs.clear_job)

	print("[JobSystem] Created build job #%d (%s) with %d prerequisites" % [
		build_job.job_id,
		data.display_name,
		build_job.get_all_prerequisites().size()
	])

	return build_job


func _get_nearest_firebase(position: Vector3, max_distance: float = 200.0) -> Node:
	"""Find the nearest firebase to a position"""
	var firebases: Array[Node] = []
	for node in get_tree().get_nodes_in_group("firebases"):
		if is_instance_valid(node):
			firebases.append(node)

	if firebases.is_empty():
		return null

	var nearest: Node = null
	var nearest_dist: float = INF

	for fb in firebases:
		var dist: float = fb.global_position.distance_to(position)
		if dist < nearest_dist and dist < max_distance:
			nearest_dist = dist
			nearest = fb

	return nearest


func _register_job(job: UnifiedJobClass) -> void:
	"""Register a job in all tracking structures"""
	jobs[job.job_id] = job

	# Add to spatial index
	for x in range(job.cell_rect.position.x, job.cell_rect.end.x):
		for z in range(job.cell_rect.position.y, job.cell_rect.end.y):
			var cell := Vector2i(x, z)
			if cell not in _job_grid:
				_job_grid[cell] = []
			_job_grid[cell].append(job)

	# Add to state list
	if job.can_be_worked():
		_ready_jobs.append(job)
		job.set_state(UnifiedJobClass.State.READY)
	else:
		_pending_jobs.append(job)

	# Connect signals
	job.state_changed.connect(_on_job_state_changed)
	job.job_completed.connect(_on_job_completed)
	job.job_cancelled.connect(_on_job_cancelled)

	job_created.emit(job)


func _unregister_job(job: UnifiedJobClass) -> void:
	"""Remove a job from all tracking structures"""
	if job.job_id in jobs:
		jobs.erase(job.job_id)

	# Remove from spatial index
	for x in range(job.cell_rect.position.x, job.cell_rect.end.x):
		for z in range(job.cell_rect.position.y, job.cell_rect.end.y):
			var cell := Vector2i(x, z)
			if cell in _job_grid:
				_job_grid[cell].erase(job)

	# Remove from state lists
	_pending_jobs.erase(job)
	_ready_jobs.erase(job)
	_in_progress_jobs.erase(job)


## =============================================================================
## JOB QUERIES
## =============================================================================

func get_job(job_id: int) -> UnifiedJobClass:
	"""Get a job by ID"""
	return jobs.get(job_id) as UnifiedJobClass


func get_jobs_at_cell(cell: Vector2i) -> Array[UnifiedJobClass]:
	"""Get all jobs covering a specific grid cell"""
	var result: Array[UnifiedJobClass] = []
	if cell in _job_grid:
		for job in _job_grid[cell]:
			if is_instance_valid(job):
				result.append(job)
	return result


func get_jobs_in_region(region: Rect2i) -> Array[UnifiedJobClass]:
	"""Get all jobs overlapping a grid region"""
	var result: Array[UnifiedJobClass] = []
	var seen: Dictionary = {}  # Avoid duplicates

	for x in range(region.position.x, region.end.x):
		for z in range(region.position.y, region.end.y):
			var cell := Vector2i(x, z)
			if cell in _job_grid:
				for job in _job_grid[cell]:
					if is_instance_valid(job) and job.job_id not in seen:
						seen[job.job_id] = true
						result.append(job)

	return result


func get_jobs_in_world_bounds(bounds: AABB) -> Array[UnifiedJobClass]:
	"""Get all jobs overlapping world-space bounds"""
	var result: Array[UnifiedJobClass] = []

	# Convert bounds to grid region
	var min_cell: Vector2i = GridCoordsClass.world_to_gameplay_clamped(bounds.position)
	var max_cell: Vector2i = GridCoordsClass.world_to_gameplay_clamped(bounds.end)
	var region := Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)

	for job in get_jobs_in_region(region):
		if job.overlaps_world_bounds(bounds):
			result.append(job)

	return result


func get_jobs_in_area(center: Vector3, radius: float) -> Array[UnifiedJobClass]:
	"""Get all jobs within radius of center position (convenience wrapper)"""
	var half := Vector3(radius, 50.0, radius)  # Use large Y to catch all heights
	var bounds := AABB(center - half, half * 2.0)
	return get_jobs_in_world_bounds(bounds)


func get_jobs_needing_workers(worker_class: String = "") -> Array[UnifiedJobClass]:
	"""Get jobs that need workers, optionally filtered by worker class"""
	var result: Array[UnifiedJobClass] = []

	for job in _ready_jobs + _in_progress_jobs:
		if not is_instance_valid(job):
			continue
		if job.assigned_workers.size() >= job.max_workers:
			continue
		if not job.can_be_worked():
			continue

		# Filter by worker class if specified
		if worker_class != "":
			if not can_worker_do_job(worker_class, job.job_type):
				continue

		result.append(job)

	# Sort by priority (lower = more urgent)
	result.sort_custom(func(a: UnifiedJobClass, b: UnifiedJobClass):
		return a.priority < b.priority
	)

	return result


func get_best_job_for_worker(worker: Node3D, worker_class: String, max_distance: float = 200.0) -> UnifiedJobClass:
	"""Find the best job for a worker based on priority, distance, and capacity.
	Prioritizes jobs with remaining capacity - more workers = faster completion."""
	var jobs_needing_workers: Array[UnifiedJobClass] = get_jobs_needing_workers(worker_class)

	if jobs_needing_workers.is_empty():
		return null

	var worker_pos: Vector3 = worker.global_position
	var best_job: UnifiedJobClass = null
	var best_score: float = -INF

	for job in jobs_needing_workers:
		# Skip jobs at capacity
		var capacity_remaining: int = job.max_workers - job.assigned_workers.size()
		if capacity_remaining <= 0:
			continue

		var dist: float = worker_pos.distance_to(job.get_centroid())
		if dist > max_distance:
			continue

		# Score = priority_weight + capacity_bonus - distance_penalty
		# Lower priority value = higher weight
		var priority_weight: float = (4 - job.priority) * 50.0  # 200 for CRITICAL, 50 for LOW
		var distance_penalty: float = dist * 0.5

		# Capacity-based scoring (StarCraft fix):
		# - Bonus for jobs that need workers (+5 per open slot)
		# - Small bonus for unclaimed jobs to start work quickly
		var capacity_bonus: float = capacity_remaining * 5.0
		if job.assigned_workers.size() == 0:
			capacity_bonus += 20.0  # Extra bonus to start new jobs

		var score: float = priority_weight + capacity_bonus - distance_penalty

		# Priority multiplier for urgent jobs
		if job.priority == UnifiedJobClass.Priority.CRITICAL:
			score *= 1.5
		elif job.priority == UnifiedJobClass.Priority.HIGH:
			score *= 1.2

		if score > best_score:
			best_score = score
			best_job = job

	return best_job


## =============================================================================
## WORK MANAGEMENT
## =============================================================================

func add_work(job: UnifiedJobClass, worker: Node3D, delta: float) -> void:
	"""Add work to a job from a worker"""
	if not is_instance_valid(job) or not is_instance_valid(worker):
		return

	if not job.is_worker_in_range(worker):
		return

	# Calculate work rate based on worker type
	var worker_class: String = get_worker_class(worker)
	var base_rate: float = 1.0

	if worker_class == "bulldozer":
		base_rate = 3.0

	# Apply job-type multiplier
	var multiplier: float = get_work_rate_multiplier(worker_class, job.job_type)
	var work_amount: float = base_rate * multiplier * delta

	job.add_work(work_amount)

	# Forward work to the job's visual node
	_add_work_to_node(job, work_amount)


func _add_work_to_node(job: UnifiedJobClass, work_amount: float) -> void:
	"""Forward work progress to the job's visual node"""
	var node: Node = job.metadata.get("job_node")

	# Normalize work amount to 0-1 progress based on job work required
	var progress_amount: float = work_amount / job.work_required if job.work_required > 0 else 0.0

	match job.job_type:
		UnifiedJobClass.Type.CLEAR_TERRAIN:
			# ClearingZoneNode
			if is_instance_valid(job.clearing_zone) and job.clearing_zone.has_method("add_work"):
				var zone_complete: bool = job.clearing_zone.add_work(progress_amount)
				if zone_complete:
					job.set_state(UnifiedJobClass.State.COMPLETE)

		UnifiedJobClass.Type.BUILD_STRUCTURE:
			# ConstructionSiteNode
			if is_instance_valid(node) and node.has_method("add_work"):
				var complete: bool = node.add_work(progress_amount)
				if complete:
					job.set_state(UnifiedJobClass.State.COMPLETE)

		UnifiedJobClass.Type.DIG_TRENCH:
			# TrenchNode
			if is_instance_valid(node) and node.has_method("add_work"):
				var complete: bool = node.add_work(progress_amount)
				if complete:
					job.set_state(UnifiedJobClass.State.COMPLETE)

		UnifiedJobClass.Type.LAY_WIRE:
			# WireObstacleNode
			if is_instance_valid(node) and node.has_method("add_work"):
				var complete: bool = node.add_work(progress_amount)
				if complete:
					job.set_state(UnifiedJobClass.State.COMPLETE)

		UnifiedJobClass.Type.BUILD_ROAD:
			# RoadSegmentNode
			if is_instance_valid(node) and node.has_method("add_work"):
				var complete: bool = node.add_work(progress_amount)
				if complete:
					job.set_state(UnifiedJobClass.State.COMPLETE)

		UnifiedJobClass.Type.FILL_CRATER:
			# CraterNode
			if is_instance_valid(node) and node.has_method("add_work"):
				var complete: bool = node.add_work(progress_amount)
				if complete:
					job.set_state(UnifiedJobClass.State.COMPLETE)

		UnifiedJobClass.Type.FLATTEN_AREA:
			# Progressive terrain flattening - actually modify terrain mesh
			_apply_progressive_flattening(job, progress_amount)


func get_work_positions(job: UnifiedJobClass, worker_count: int) -> PackedVector3Array:
	"""Get optimal work positions for a number of workers"""
	if not is_instance_valid(job):
		return PackedVector3Array()

	var positions: PackedVector3Array = job.work_positions

	if positions.size() <= worker_count:
		return positions

	# Distribute workers evenly around perimeter
	var result: PackedVector3Array = PackedVector3Array()
	var step: int = maxi(1, positions.size() / worker_count)

	for i in range(worker_count):
		var idx: int = (i * step) % positions.size()
		result.append(positions[idx])

	return result


## =============================================================================
## TERRAIN FLATTENING
## =============================================================================

func _apply_progressive_flattening(job: UnifiedJobClass, progress_amount: float) -> void:
	"""Apply progressive terrain flattening as workers do work"""
	# Get terrain engine
	var terrain: Node = get_node_or_null("/root/UnifiedTerrain")
	if not terrain:
		# Fallback to TerrainIntegration
		terrain = get_node_or_null("/root/TerrainIntegration")
	if not terrain or not terrain.has_method("flatten_area"):
		# Check if it has modify_terrain instead
		if not terrain or not terrain.has_method("modify_terrain"):
			return

	# Calculate current progress
	var current_progress: float = job.work_done / job.work_required if job.work_required > 0 else 0.0

	# Store target height on first flattening call
	if not job.metadata.has("flatten_target_height"):
		if terrain.has_method("get_height_at"):
			job.metadata["flatten_target_height"] = terrain.get_height_at(job.get_centroid())
		else:
			job.metadata["flatten_target_height"] = 0.0
		job.metadata["last_flatten_progress"] = 0.0

	var target_height: float = job.metadata.get("flatten_target_height", 0.0) as float
	var last_progress: float = job.metadata.get("last_flatten_progress", 0.0) as float

	# Only flatten if progress has increased significantly (every 10%)
	var progress_threshold: float = 0.1
	if current_progress - last_progress >= progress_threshold or current_progress >= 1.0:
		# Calculate flattening strength based on progress (0-1)
		var flatten_strength: float = minf(current_progress, 1.0)

		# Get job bounds
		var center: Vector3 = job.get_centroid()
		var size: Vector2 = Vector2(job.world_bounds.size.x, job.world_bounds.size.z)

		# Apply flattening to terrain
		if terrain.has_method("flatten_area"):
			# Use flatten_area if available (UnifiedTerrainEngine)
			terrain.flatten_area(center, size * flatten_strength, target_height)
		elif terrain.has_method("modify_terrain"):
			# Fallback to modify_terrain with custom modifier
			var radius: float = maxf(size.x, size.y) * 0.5 * flatten_strength
			var modifier := func(h: float, falloff: float) -> float:
				return lerpf(h, target_height, falloff * flatten_strength)
			terrain.modify_terrain(center, radius, modifier)

		job.metadata["last_flatten_progress"] = current_progress
		print("[JobSystem] Flattened terrain at %v (progress: %.0f%%)" % [center, current_progress * 100])

	# Check if flattening is complete
	if job.work_done >= job.work_required:
		job.set_state(UnifiedJobClass.State.COMPLETE)


## =============================================================================
## WORKER CLASS HELPERS
## =============================================================================

func get_worker_class(worker: Node3D) -> String:
	"""Determine if a worker is an engineer or bulldozer"""
	if not is_instance_valid(worker):
		return "engineer"

	# Check if it's a bulldozer (vehicle with is_vehicle flag)
	if worker.has_method("get"):
		var data: Resource = worker.get("data")
		if data and "is_vehicle" in data and data.is_vehicle:
			return "bulldozer"

	# Check for explicit worker_class property
	if worker.has_method("get") and worker.get("worker_class") != null:
		return worker.worker_class

	return "engineer"


func can_worker_do_job(worker_class: String, job_type: UnifiedJobClass.Type) -> bool:
	"""Check if a worker class can work on a job type"""
	match job_type:
		UnifiedJobClass.Type.CLEAR_TERRAIN:
			return true  # Both can clear
		UnifiedJobClass.Type.FLATTEN_AREA:
			return true  # Both can flatten (bulldozer faster)
		UnifiedJobClass.Type.BUILD_STRUCTURE:
			return worker_class == "engineer"  # Only engineers build
		UnifiedJobClass.Type.BUILD_ROAD:
			return worker_class == "bulldozer"  # Bulldozers build roads
		UnifiedJobClass.Type.FILL_CRATER:
			return true  # Both can fill
		UnifiedJobClass.Type.DIG_TRENCH:
			return worker_class == "engineer"  # Engineers dig
		UnifiedJobClass.Type.LAY_WIRE:
			return worker_class == "engineer"  # Engineers lay wire
		_:
			return true


func get_work_rate_multiplier(worker_class: String, job_type: UnifiedJobClass.Type) -> float:
	"""Get work rate multiplier for worker/job combination"""
	match job_type:
		UnifiedJobClass.Type.CLEAR_TERRAIN:
			# Target: Bulldozer ~0.2 sec/tree, Engineer ~0.6 sec/tree (fast clearing)
			# Work per cell = 14.0, Bulldozer base = 3.0, Engineer base = 1.0
			# 5x faster than original for snappy jungle clearing
			return 25.0  # Fast clearing - bulldozer still 3x faster via base rate
		UnifiedJobClass.Type.FLATTEN_AREA:
			return 2.0 if worker_class == "bulldozer" else 0.5  # Bulldozers much faster
		UnifiedJobClass.Type.BUILD_STRUCTURE:
			return 1.0
		UnifiedJobClass.Type.BUILD_ROAD:
			return 1.0 if worker_class == "bulldozer" else 0.3
		UnifiedJobClass.Type.FILL_CRATER:
			return 1.5 if worker_class == "bulldozer" else 0.7
		UnifiedJobClass.Type.DIG_TRENCH:
			return 1.0
		UnifiedJobClass.Type.LAY_WIRE:
			return 1.0
		_:
			return 1.0


## =============================================================================
## SIGNAL HANDLERS
## =============================================================================

func _on_job_state_changed(job: UnifiedJobClass, old_state: UnifiedJobClass.State, new_state: UnifiedJobClass.State) -> void:
	"""Handle job state transitions"""
	# Update state lists
	match old_state:
		UnifiedJobClass.State.PENDING:
			_pending_jobs.erase(job)
		UnifiedJobClass.State.READY:
			_ready_jobs.erase(job)
		UnifiedJobClass.State.IN_PROGRESS:
			_in_progress_jobs.erase(job)

	match new_state:
		UnifiedJobClass.State.PENDING:
			if job not in _pending_jobs:
				_pending_jobs.append(job)
		UnifiedJobClass.State.READY:
			if job not in _ready_jobs:
				_ready_jobs.append(job)
		UnifiedJobClass.State.IN_PROGRESS:
			if job not in _in_progress_jobs:
				_in_progress_jobs.append(job)
		UnifiedJobClass.State.COMPLETE:
			# Immediately trigger worker re-assignment for other jobs
			for ready_job in _ready_jobs + _in_progress_jobs:
				if is_instance_valid(ready_job) and ready_job.assigned_workers.size() < ready_job.max_workers:
					worker_needed.emit(ready_job)


func _on_job_completed(job: UnifiedJobClass) -> void:
	"""Handle job completion"""
	_unregister_job(job)

	# Mark terrain as cleared AFTER work is done (triggers billboard removal)
	if job.job_type == UnifiedJobClass.Type.CLEAR_TERRAIN:
		var clearing_sys: Node = get_node_or_null("/root/ClearingSystem")
		if clearing_sys and clearing_sys.has_method("mark_area_cleared"):
			var center: Vector3 = job.get_centroid()
			var radius: float = maxf(job.world_bounds.size.x, job.world_bounds.size.z) * 0.5
			clearing_sys.mark_area_cleared(center, radius)
			print("[JobSystem] Clearing complete - marking terrain as cleared at %v (radius: %.1f)" % [center, radius])

	job_completed.emit(job)

	print("[JobSystem] Job #%d completed: %s" % [
		job.job_id,
		UnifiedJobClass.get_type_name(job.job_type)
	])


func _on_job_cancelled(job: UnifiedJobClass) -> void:
	"""Handle job cancellation"""
	_unregister_job(job)
	job_cancelled.emit(job)

	print("[JobSystem] Job #%d cancelled" % job.job_id)


## =============================================================================
## JOB CANCELLATION (Public API)
## =============================================================================

func cancel_job(job: UnifiedJobClass) -> bool:
	"""Cancel a job, unassign workers, refund supply, clean up nodes. Returns true if successful."""
	if not is_instance_valid(job):
		return false

	# Can't cancel already completed/cancelled jobs
	if job.state == UnifiedJobClass.State.COMPLETE or job.state == UnifiedJobClass.State.CANCELLED:
		return false

	print("[JobSystem] Cancelling job #%d (%s)" % [job.job_id, UnifiedJobClass.get_type_name(job.job_type)])

	# Unassign all workers
	for worker in job.assigned_workers.duplicate():
		job.unassign_worker(worker)

	# Refund supply for build jobs (scaled by progress - full refund if no work done)
	if job.job_type == UnifiedJobClass.Type.BUILD_STRUCTURE:
		var supply_cost: int = job.metadata.get("supply_cost", 0) as int
		var firebase: Node = job.metadata.get("firebase")
		if supply_cost > 0 and is_instance_valid(firebase):
			# Scale refund by remaining work (100% if not started, 50% if half done, etc.)
			var progress: float = job.work_done / job.work_required if job.work_required > 0 else 0.0
			var refund_percent: float = 1.0 - progress
			var refund_amount: int = int(supply_cost * refund_percent)
			if refund_amount > 0:
				firebase.supply_level += refund_amount
				print("[JobSystem] Refunded %d supply (%.0f%% of %d) to firebase (now %.0f)" % [
					refund_amount, refund_percent * 100, supply_cost, firebase.supply_level
				])
				# Emit supply delivered signal for HUD update (refund = supply returned)
				if BattleSignals:
					BattleSignals.supply_delivered.emit(firebase, float(refund_amount))

	# Clean up job node (ConstructionSiteNode, ClearingZoneNode, etc.)
	var node: Node = job.metadata.get("job_node")
	if is_instance_valid(node):
		if node.has_method("cancel"):
			node.cancel()
		else:
			node.queue_free()
		job.metadata.erase("job_node")

	# Set state to cancelled (triggers _on_job_cancelled via signal)
	job.set_state(UnifiedJobClass.State.CANCELLED)

	return true


func cancel_job_by_id(job_id: int) -> bool:
	"""Cancel a job by its ID"""
	var job: UnifiedJobClass = get_job_by_id(job_id)
	if job:
		return cancel_job(job)
	return false


func get_job_by_id(job_id: int) -> UnifiedJobClass:
	"""Find a job by its ID"""
	for job in _pending_jobs + _ready_jobs + _in_progress_jobs:
		if is_instance_valid(job) and job.job_id == job_id:
			return job
	return null


## =============================================================================
## TERRAIN INTEGRATION
## =============================================================================

func on_terrain_updated(region: Rect2i) -> void:
	"""Called when terrain is modified - check affected jobs"""
	var affected_jobs: Array[UnifiedJobClass] = get_jobs_in_region(region)

	for job in affected_jobs:
		if not is_instance_valid(job):
			continue

		# Check if job requirements changed
		match job.job_type:
			UnifiedJobClass.Type.CLEAR_TERRAIN:
				# Check if terrain is now cleared
				_check_clearing_complete(job)

			UnifiedJobClass.Type.FLATTEN_AREA:
				# Check if terrain is now flat
				_check_flattening_complete(job)


func _check_clearing_complete(job: UnifiedJobClass) -> void:
	"""Check if a clearing job's terrain is fully cleared"""
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if not terrain or not terrain.has_method("is_cleared"):
		return

	# Check all cells in job area
	for x in range(job.cell_rect.position.x, job.cell_rect.end.x):
		for z in range(job.cell_rect.position.y, job.cell_rect.end.y):
			var world_pos: Vector3 = GridCoordsClass.gameplay_to_world(Vector2i(x, z))
			if not terrain.is_cleared(world_pos):
				return  # Not all cleared yet

	# All cleared - complete the job
	job.set_state(UnifiedJobClass.State.COMPLETE)


func _check_flattening_complete(job: UnifiedJobClass) -> void:
	"""Check if a flattening job's terrain is adequately flat"""
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if not terrain or not terrain.has_method("get_slope_at"):
		return

	# Check all cells in job area for slope
	var max_slope: float = 0.15  # 15% max slope for "flat"

	for x in range(job.cell_rect.position.x, job.cell_rect.end.x):
		for z in range(job.cell_rect.position.y, job.cell_rect.end.y):
			var world_pos: Vector3 = GridCoordsClass.gameplay_to_world(Vector2i(x, z))
			if terrain.has_method("get_slope_at"):
				var slope: float = terrain.get_slope_at(world_pos)
				if slope > max_slope:
					return  # Still too sloped

	# All flat enough - complete the job
	job.set_state(UnifiedJobClass.State.COMPLETE)


## =============================================================================
## JOB NODE HELPERS
## =============================================================================

func _find_crater_at(position: Vector3) -> Node:
	"""Find an existing CraterNode at or near the given position"""
	var craters: Array[Node] = get_tree().get_nodes_in_group("craters") as Array[Node]
	var closest: Node = null
	var closest_dist: float = INF

	for crater in craters:
		if not is_instance_valid(crater):
			continue
		var dist: float = crater.global_position.distance_to(position)
		if dist < closest_dist and dist < 5.0:  # Within 5m
			closest_dist = dist
			closest = crater

	return closest


func _on_construction_complete(_building: Node3D, job: UnifiedJobClass) -> void:
	"""Handle construction site completion"""
	if is_instance_valid(job) and job.state != UnifiedJobClass.State.COMPLETE:
		job.set_state(UnifiedJobClass.State.COMPLETE)


func _on_trench_complete(job: UnifiedJobClass) -> void:
	"""Handle trench completion"""
	if is_instance_valid(job) and job.state != UnifiedJobClass.State.COMPLETE:
		job.set_state(UnifiedJobClass.State.COMPLETE)


func _on_wire_complete(job: UnifiedJobClass) -> void:
	"""Handle wire obstacle completion"""
	if is_instance_valid(job) and job.state != UnifiedJobClass.State.COMPLETE:
		job.set_state(UnifiedJobClass.State.COMPLETE)


func _on_road_complete(job: UnifiedJobClass) -> void:
	"""Handle road segment completion"""
	if is_instance_valid(job) and job.state != UnifiedJobClass.State.COMPLETE:
		job.set_state(UnifiedJobClass.State.COMPLETE)


## =============================================================================
## CONVENIENCE JOB CREATORS
## =============================================================================

func _create_prerequisites(center: Vector3, footprint_size: Vector2, rotation_y: float = 0.0) -> Dictionary:
	"""Create clear and flatten prerequisite jobs if needed. Returns {clear_job, flatten_job}
	   When rotation_y is non-zero, computes axis-aligned bbox of rotated rectangle."""
	var terrain_grid := get_node_or_null("/root/TerrainIntegration")
	var needs_clearing: bool = true  # Default to needing clearing

	if terrain_grid and terrain_grid.has_method("is_cleared"):
		needs_clearing = not terrain_grid.is_cleared(center)

	var clear_job: UnifiedJobClass = null
	var flatten_job: UnifiedJobClass = null

	# Compute effective size - for rotated rectangles, use axis-aligned bbox
	var effective_size: Vector2 = footprint_size
	if absf(rotation_y) > 0.01:
		# Compute bounding box of rotated rectangle
		var half_w := footprint_size.x * 0.5
		var half_h := footprint_size.y * 0.5
		var cos_r := cos(rotation_y)
		var sin_r := sin(rotation_y)
		# Rotated corners (only need to check 2 opposite corners for bbox)
		var x1 := absf(half_w * cos_r - half_h * sin_r)
		var z1 := absf(half_w * sin_r + half_h * cos_r)
		var x2 := absf(half_w * cos_r + half_h * sin_r)
		var z2 := absf(half_w * sin_r - half_h * cos_r)
		effective_size = Vector2(maxf(x1, x2) * 2.0, maxf(z1, z2) * 2.0)

	# Expand clearing area by 20% for access
	var clear_size: Vector2 = effective_size * 1.2

	if needs_clearing:
		clear_job = create_job(
			UnifiedJobClass.Type.CLEAR_TERRAIN,
			center,
			clear_size,
			UnifiedJobClass.Priority.NORMAL
		)
		# Store rotation in metadata for oriented clearing (future use)
		if absf(rotation_y) > 0.01:
			clear_job.metadata["rotation"] = rotation_y

	# Always flatten for construction
	flatten_job = create_job(
		UnifiedJobClass.Type.FLATTEN_AREA,
		center,
		effective_size,
		UnifiedJobClass.Priority.NORMAL
	)
	# Store rotation in metadata for oriented flattening (future use)
	if absf(rotation_y) > 0.01:
		flatten_job.metadata["rotation"] = rotation_y

	# Flatten depends on clear
	if clear_job:
		flatten_job.add_prerequisite(clear_job)

	return {"clear_job": clear_job, "flatten_job": flatten_job}


func create_trench_job(center: Vector3, length: float = 8.0, width: float = 2.0, rotation_y: float = 0.0, priority: UnifiedJobClass.Priority = UnifiedJobClass.Priority.NORMAL) -> UnifiedJobClass:
	"""Create a trench digging job with clear/flatten prerequisites"""
	var size := Vector2(length, width)

	# Create prerequisite jobs (with rotation for oriented clearing)
	var prereqs: Dictionary = _create_prerequisites(center, size, rotation_y)

	# Create the trench job
	var job: UnifiedJobClass = create_job(UnifiedJobClass.Type.DIG_TRENCH, center, size, priority)

	# Store rotation for node creation
	if absf(rotation_y) > 0.01:
		job.metadata["rotation"] = rotation_y

	# Add prerequisites
	if prereqs.flatten_job:
		job.add_prerequisite(prereqs.flatten_job)
	elif prereqs.clear_job:
		job.add_prerequisite(prereqs.clear_job)

	print("[JobSystem] Created trench job #%d (%.1fm @ %.1f deg) with %d prerequisites" % [
		job.job_id, length, rad_to_deg(rotation_y), job.get_all_prerequisites().size()
	])
	return job


func create_wire_job(center: Vector3, length: float = 6.0, wire_type: int = 0, faction: int = 0, rotation_y: float = 0.0, priority: UnifiedJobClass.Priority = UnifiedJobClass.Priority.NORMAL) -> UnifiedJobClass:
	"""Create a wire obstacle placement job with clear/flatten prerequisites"""
	var size := Vector2(length, 2.0)

	# Create prerequisite jobs (with rotation for oriented clearing)
	var prereqs: Dictionary = _create_prerequisites(center, size, rotation_y)

	# Create the wire job
	var job: UnifiedJobClass = create_job(UnifiedJobClass.Type.LAY_WIRE, center, size, priority)
	job.metadata["wire_type"] = wire_type
	job.metadata["faction"] = faction

	# Store rotation for node creation
	if absf(rotation_y) > 0.01:
		job.metadata["rotation"] = rotation_y

	# Add prerequisites
	if prereqs.flatten_job:
		job.add_prerequisite(prereqs.flatten_job)
	elif prereqs.clear_job:
		job.add_prerequisite(prereqs.clear_job)

	# Recreate node with correct metadata
	_create_job_node(job, center, size)

	print("[JobSystem] Created wire job #%d (%.1fm @ %.1f deg) with %d prerequisites" % [
		job.job_id, length, rad_to_deg(rotation_y), job.get_all_prerequisites().size()
	])
	return job


func create_road_job(path_points: PackedVector3Array, width: float = 4.0, priority: UnifiedJobClass.Priority = UnifiedJobClass.Priority.NORMAL) -> UnifiedJobClass:
	"""Create a road construction job along a path with clear/flatten prerequisites"""
	if path_points.size() < 2:
		push_error("[JobSystem] Road job requires at least 2 path points")
		return null

	var center: Vector3 = path_points[0].lerp(path_points[path_points.size() - 1], 0.5)
	var total_length: float = 0.0
	for i in range(path_points.size() - 1):
		total_length += path_points[i].distance_to(path_points[i + 1])

	var size := Vector2(total_length, width)

	# Create prerequisite jobs
	var prereqs: Dictionary = _create_prerequisites(center, size)

	# Create the road job
	var job: UnifiedJobClass = create_job(UnifiedJobClass.Type.BUILD_ROAD, center, size, priority)
	job.metadata["path_points"] = path_points

	# Add prerequisites
	if prereqs.flatten_job:
		job.add_prerequisite(prereqs.flatten_job)
	elif prereqs.clear_job:
		job.add_prerequisite(prereqs.clear_job)

	# Recreate node with path
	var old_node: Node = job.metadata.get("job_node")
	if is_instance_valid(old_node):
		old_node.queue_free()
	var road: Node = RoadSegmentNodeClass.create(path_points, width)
	_node_container.add_child(road)
	job.metadata["job_node"] = road
	road.road_complete.connect(_on_road_complete.bind(job))

	print("[JobSystem] Created road job #%d with %d prerequisites" % [job.job_id, job.get_all_prerequisites().size()])
	return job


func create_fill_crater_job(crater: Node, priority: UnifiedJobClass.Priority = UnifiedJobClass.Priority.NORMAL) -> UnifiedJobClass:
	"""Create a job to fill an existing crater"""
	if not is_instance_valid(crater):
		push_error("[JobSystem] Cannot create fill job for invalid crater")
		return null

	var center: Vector3 = crater.global_position
	var radius: float = crater.radius if "radius" in crater else 3.0
	var size := Vector2(radius * 2, radius * 2)

	var job: UnifiedJobClass = create_job(UnifiedJobClass.Type.FILL_CRATER, center, size, priority)
	job.metadata["job_node"] = crater
	return job


## =============================================================================
## STATISTICS
## =============================================================================

func get_job_counts() -> Dictionary:
	"""Get counts of jobs by state"""
	return {
		"pending": _pending_jobs.size(),
		"ready": _ready_jobs.size(),
		"in_progress": _in_progress_jobs.size(),
		"total": jobs.size()
	}


func get_total_work_remaining() -> float:
	"""Get total work remaining across all jobs"""
	var total: float = 0.0
	for job in jobs.values():
		if is_instance_valid(job):
			total += job.work_required - job.work_done
	return total


## =============================================================================
## BLUEPRINT PLACEMENT VALIDATION
## =============================================================================

enum PlacementError {
	NONE,               # Valid placement
	OVERLAPS_BUILDING,  # Would overlap existing building
	OVERLAPS_JOB,       # Would overlap existing construction job
	TERRAIN_TOO_STEEP,  # Slope exceeds buildable limit
	TERRAIN_WATER,      # Position is in water
	INSUFFICIENT_SUPPLY # Not enough supply (handled in create_build_job)
}


func validate_placement(center: Vector3, footprint_size: Vector2, _building_type: int = -1) -> Dictionary:
	"""Validate if a building can be placed at this location.
	Returns {valid: bool, error: PlacementError, message: String}"""
	# Check for overlapping buildings
	var overlap_error: Dictionary = _check_building_overlap(center, footprint_size)
	if not overlap_error.valid:
		return overlap_error

	# Check for overlapping construction jobs
	var job_overlap: Dictionary = _check_job_overlap(center, footprint_size)
	if not job_overlap.valid:
		return job_overlap

	# Check terrain slope
	var slope_error: Dictionary = _check_terrain_slope(center, footprint_size)
	if not slope_error.valid:
		return slope_error

	# Check for water
	var water_error: Dictionary = _check_terrain_water(center)
	if not water_error.valid:
		return water_error

	# All checks passed
	return {"valid": true, "error": PlacementError.NONE, "message": ""}


func _check_building_overlap(center: Vector3, size: Vector2) -> Dictionary:
	"""Check if placement would overlap existing buildings"""
	var half := Vector3(size.x * 0.5, 2.0, size.y * 0.5)
	var check_bounds := AABB(center - half, half * 2.0)

	# Check against all buildings
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building):
			continue

		# Get building bounds (try meta first, fallback to estimate)
		var bldg_size: Vector3 = Vector3(4, 3, 4)  # Default size
		if building.has_meta("footprint_size"):
			var fp: Vector2 = building.get_meta("footprint_size")
			bldg_size = Vector3(fp.x, 3.0, fp.y)
		elif building is MeshInstance3D and building.mesh:
			bldg_size = building.mesh.get_aabb().size

		var bldg_half := bldg_size * 0.5
		var bldg_bounds := AABB(building.global_position - bldg_half, bldg_size)

		if check_bounds.intersects(bldg_bounds):
			return {
				"valid": false,
				"error": PlacementError.OVERLAPS_BUILDING,
				"message": "Overlaps existing building"
			}

	return {"valid": true, "error": PlacementError.NONE, "message": ""}


func _check_job_overlap(center: Vector3, size: Vector2) -> Dictionary:
	"""Check if placement would overlap existing construction jobs"""
	var half := Vector3(size.x * 0.5, 2.0, size.y * 0.5)
	var check_bounds := AABB(center - half, half * 2.0)

	# Check against construction sites
	for site in get_tree().get_nodes_in_group("construction_sites"):
		if not is_instance_valid(site):
			continue

		var site_size: Vector2 = site.footprint_size if "footprint_size" in site else Vector2(4, 4)
		var site_half := Vector3(site_size.x * 0.5, 2.0, site_size.y * 0.5)
		var site_bounds := AABB(site.global_position - site_half, site_half * 2.0)

		if check_bounds.intersects(site_bounds):
			return {
				"valid": false,
				"error": PlacementError.OVERLAPS_JOB,
				"message": "Overlaps construction in progress"
			}

	return {"valid": true, "error": PlacementError.NONE, "message": ""}


func _check_terrain_slope(center: Vector3, size: Vector2) -> Dictionary:
	"""Check if terrain slope is acceptable for building"""
	var terrain: Node = get_node_or_null("/root/TerrainIntegration")
	if not terrain:
		return {"valid": true, "error": PlacementError.NONE, "message": ""}

	# Sample heights at corners
	var half_x := size.x * 0.5
	var half_z := size.y * 0.5
	var corners := [
		Vector3(center.x - half_x, 0, center.z - half_z),
		Vector3(center.x + half_x, 0, center.z - half_z),
		Vector3(center.x + half_x, 0, center.z + half_z),
		Vector3(center.x - half_x, 0, center.z + half_z),
		center  # Also check center
	]

	var heights: Array[float] = []
	for corner in corners:
		if terrain.has_method("get_height_at"):
			heights.append(terrain.get_height_at(corner))
		else:
			heights.append(0.0)

	if heights.is_empty():
		return {"valid": true, "error": PlacementError.NONE, "message": ""}

	# Calculate height difference
	var min_h: float = heights[0]
	var max_h: float = heights[0]
	for h in heights:
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)

	var height_diff: float = max_h - min_h
	var max_slope_diff: float = 2.0  # 2 meters max height difference across footprint

	if height_diff > max_slope_diff:
		return {
			"valid": false,
			"error": PlacementError.TERRAIN_TOO_STEEP,
			"message": "Terrain too steep (%.1fm slope)" % height_diff
		}

	return {"valid": true, "error": PlacementError.NONE, "message": ""}


func _check_terrain_water(center: Vector3) -> Dictionary:
	"""Check if position is in water"""
	var terrain: Node = get_node_or_null("/root/TerrainIntegration")
	if not terrain:
		return {"valid": true, "error": PlacementError.NONE, "message": ""}

	# Check if terrain has water detection
	if terrain.has_method("is_water_at"):
		if terrain.is_water_at(center):
			return {
				"valid": false,
				"error": PlacementError.TERRAIN_WATER,
				"message": "Cannot build in water"
			}

	# Fallback: check if height is below water level
	if terrain.has_method("get_height_at") and terrain.has_method("get"):
		var height: float = terrain.get_height_at(center)
		var water_level: float = terrain.get("water_level") if "water_level" in terrain else 0.0
		if height < water_level - 0.5:  # 0.5m buffer
			return {
				"valid": false,
				"error": PlacementError.TERRAIN_WATER,
				"message": "Cannot build in water"
			}

	return {"valid": true, "error": PlacementError.NONE, "message": ""}


func get_placement_error_string(error: PlacementError) -> String:
	"""Get human-readable error message for placement error"""
	match error:
		PlacementError.NONE:
			return ""
		PlacementError.OVERLAPS_BUILDING:
			return "Overlaps existing building"
		PlacementError.OVERLAPS_JOB:
			return "Overlaps construction in progress"
		PlacementError.TERRAIN_TOO_STEEP:
			return "Terrain too steep"
		PlacementError.TERRAIN_WATER:
			return "Cannot build in water"
		PlacementError.INSUFFICIENT_SUPPLY:
			return "Insufficient supply"
		_:
			return "Invalid placement"
