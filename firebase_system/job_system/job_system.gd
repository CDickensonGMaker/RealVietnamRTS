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

## DEBUG: Multiplier for work speed (set to 1.0 for normal, 50.0 for 5000% speed)
const DEBUG_WORK_MULTIPLIER: float = 1.0

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
	print("[JobSystem] create_build_job called: type=%d, center=%v, skip_validation=%s" % [
		building_type, center, skip_validation
	])

	# Get building data for supply cost
	var data: BuildingDataClass = BuildingDataClass.get_building_data(building_type)
	if not data:
		push_error("[JobSystem] Unknown building type: %d" % building_type)
		return null

	print("[JobSystem] create_build_job: building=%s, supply_cost=%d" % [data.display_name, data.supply_cost])

	# Validate placement (overlap, slope, water)
	if not skip_validation:
		print("[JobSystem] create_build_job: running validation...")
		var validation: Dictionary = validate_placement(center, footprint_size, building_type)
		print("[JobSystem] create_build_job: validation result = %s" % validation)
		if not validation.valid:
			push_warning("[JobSystem] Cannot build %s: %s" % [data.display_name, validation.message])
			return null

	# Find nearest firebase (for zone checks, not supply)
	var firebase: Node = _get_nearest_firebase(center)
	var supply_cost: int = data.supply_cost

	# Check global supply for construction costs
	# Firebase local supply is for unit resupply (water, fuel), not building costs
	# HQ buildings can be built without supply - they bootstrap new firebases
	var is_hq: bool = data.is_hq_building if "is_hq_building" in data else false
	if supply_cost > 0 and not is_hq:
		var supply_mgr: Node = get_node_or_null("/root/SupplyManager")
		if supply_mgr:
			if not supply_mgr.can_afford(float(supply_cost)):
				push_warning("[JobSystem] Insufficient global supply for %s (need %d, have %.0f)" % [
					data.display_name, supply_cost, supply_mgr.get_global_supply()
				])
				return null
			# Deduct from global supply
			supply_mgr.consume_global_supply(float(supply_cost))
			print("[JobSystem] Deducted %d global supply for %s (%.0f remaining)" % [
				supply_cost, data.display_name, supply_mgr.get_global_supply()
			])
			# Emit supply consumed signal for HUD update
			if BattleSignals:
				BattleSignals.supply_consumed.emit(firebase, float(supply_cost), "construction: " + data.display_name)
		else:
			push_warning("[JobSystem] SupplyManager not found - allowing build without supply check")
	elif is_hq:
		print("[JobSystem] HQ building %s bypasses supply check (creates new firebase)" % data.display_name)

	# Create prerequisite jobs with HIGH priority to match the build job
	# For buildings: only create flatten job if slope is too steep (>0.25 ≈ 15 degrees)
	var prereqs: Dictionary = _create_prerequisites(center, footprint_size, rotation, UnifiedJobClass.Priority.HIGH, true, 0.25)

	# Create build job - we need to set metadata BEFORE _create_job_node runs
	# because ConstructionSiteNode needs building_type and rotation during creation.
	# So we manually create the job instead of using create_job() helper.
	var build_job: UnifiedJobClass = UnifiedJobClass.create(
		UnifiedJobClass.Type.BUILD_STRUCTURE,
		center,
		footprint_size
	)
	build_job.priority = UnifiedJobClass.Priority.HIGH

	# Set metadata BEFORE creating the visual node
	build_job.metadata["building_type"] = building_type
	build_job.metadata["rotation"] = rotation

	# Now create the ConstructionSiteNode (it will read the metadata we just set)
	_create_job_node(build_job, center, footprint_size)

	# Register the job with the system
	_register_job(build_job)

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


func reset() -> void:
	"""Hard reset for scene reloads. This autoload survives scene changes, so without
	this every reload inherits the previous run's jobs and their visual nodes.
	Frees nodes directly (no supply refund / cancel signals) - it's a clean slate."""
	# Free each job's visual node (construction sites, clearing zones, trenches, etc.)
	for job in jobs.values():
		if not is_instance_valid(job):
			continue
		var node: Node = job.metadata.get("job_node")
		if is_instance_valid(node):
			node.queue_free()

	# Free anything still parented to the container as a safety net
	if is_instance_valid(_node_container):
		for child in _node_container.get_children():
			child.queue_free()

	jobs.clear()
	_job_grid.clear()
	_pending_jobs.clear()
	_ready_jobs.clear()
	_in_progress_jobs.clear()
	_validation_cache.clear()
	_validation_cache_frame = -1

	print("[JobSystem] Reset - cleared all jobs and freed job nodes")


## =============================================================================
## JOB QUERIES
## =============================================================================

func get_job(job_id: int) -> UnifiedJobClass:
	"""Get a job by ID"""
	return jobs.get(job_id) as UnifiedJobClass


func get_all_jobs() -> Array[UnifiedJobClass]:
	"""Get all jobs as an array (for daemon enumeration)"""
	var result: Array[UnifiedJobClass] = []
	for job in jobs.values():
		if is_instance_valid(job):
			result.append(job)
	return result


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


func get_job_at_position(position: Vector3, tolerance: float = 2.0) -> UnifiedJobClass:
	"""Find a job at/near a specific position (for click-to-assign workers)"""
	var closest_job: UnifiedJobClass = null
	var closest_dist: float = tolerance

	# Check both ready and in-progress jobs
	for job in _ready_jobs + _in_progress_jobs:
		if not is_instance_valid(job):
			continue
		var job_pos: Vector3 = job.center_position
		var dist: float = Vector2(position.x - job_pos.x, position.z - job_pos.z).length()
		if dist < closest_dist:
			closest_dist = dist
			closest_job = job

	return closest_job


func get_job_for_site(site: Node3D) -> UnifiedJobClass:
	"""Find the job associated with a construction site node"""
	if not is_instance_valid(site):
		return null

	# Check for meta job_id on the site
	if site.has_meta("job_id"):
		var job_id: int = site.get_meta("job_id")
		return get_job(job_id)

	# Fallback: find job at site position
	return get_job_at_position(site.global_position)


func get_jobs_needing_workers(worker_class: String = "") -> Array[UnifiedJobClass]:
	"""Get jobs that need workers, optionally filtered by worker class"""
	var result: Array[UnifiedJobClass] = []

	# Debug: Show state of job lists (disabled - causes console spam)
	#if _ready_jobs.size() > 0 or _in_progress_jobs.size() > 0:
	#	print("[JobSystem] get_jobs_needing_workers(%s): %d ready, %d in_progress" % [
	#		worker_class, _ready_jobs.size(), _in_progress_jobs.size()
	#	])

	for job in _ready_jobs + _in_progress_jobs:
		if not is_instance_valid(job):
			continue
		if job.assigned_workers.size() >= job.max_workers:
			continue
		if not job.can_be_worked():
			# Debug disabled - causes console spam
			#print("[JobSystem] Job #%d not workable (state=%d, prereqs=%d)" % [
			#	job.job_id, job.state, job.prerequisites.size()
			#])
			continue

		# Filter by worker class if specified
		if worker_class != "":
			if not can_worker_do_job(worker_class, job.job_type):
				# Debug disabled - causes console spam
				#print("[JobSystem] Job #%d type %d not for worker class %s" % [
				#	job.job_id, job.job_type, worker_class
				#])
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

		# Score = priority_weight + capacity_bonus - distance_penalty - crowding_penalty
		# Lower priority value = higher weight
		var priority_weight: float = (4 - job.priority) * 50.0  # 200 for CRITICAL, 50 for LOW
		var distance_penalty: float = dist * 2.0  # Strong distance penalty to favor nearest jobs

		# Capacity-based scoring (StarCraft fix):
		# - Bonus for jobs that need workers (+5 per open slot)
		# - Small bonus for unclaimed jobs to start work quickly
		var capacity_bonus: float = capacity_remaining * 5.0
		if job.assigned_workers.size() == 0:
			capacity_bonus += 20.0  # Extra bonus to start new jobs

		# Crowding penalty: strongly discourage multiple workers from piling onto same job
		# This spreads workers across available jobs even when they evaluate simultaneously
		# The penalty scales with worker count to make subsequent assignments progressively worse
		var workers_on_job: int = job.assigned_workers.size()
		var crowding_penalty: float = workers_on_job * 40.0  # -40 per worker already assigned
		if workers_on_job >= 2:
			crowding_penalty += (workers_on_job - 1) * 20.0  # Extra penalty for 3+ workers

		var score: float = priority_weight + capacity_bonus - distance_penalty - crowding_penalty

		# Priority multiplier for urgent jobs
		if job.priority == UnifiedJobClass.Priority.CRITICAL:
			score *= 1.5
		elif job.priority == UnifiedJobClass.Priority.HIGH:
			score *= 1.2

		# Small random noise to break ties and prevent deterministic bunching
		# ±10 points of noise helps spread workers when jobs have similar scores
		score += randf_range(-10.0, 10.0)

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

	# Use generous range (4.0m) to match WorkerController's arrival threshold
	# Prevents workers from arriving but failing to apply work due to range mismatch
	if not job.is_worker_in_range(worker, 4.0):
		return  # Silent early return - debug print removed for performance

	# Calculate work rate based on worker type
	var worker_class: String = get_worker_class(worker)
	var base_rate: float = 1.0

	if worker_class == "bulldozer":
		base_rate = 3.0

	# Apply job-type multiplier
	var multiplier: float = get_work_rate_multiplier(worker_class, job.job_type)
	var work_amount: float = base_rate * multiplier * delta * DEBUG_WORK_MULTIPLIER

	job.add_work(work_amount)

	# Forward work to the job's visual node
	_add_work_to_node(job, work_amount)


func _get_distance_to_bounds(job: UnifiedJobClass, worker: Node3D) -> float:
	"""Helper to calculate distance to job bounds for debugging"""
	var worker_pos: Vector3 = worker.global_position
	var closest: Vector3 = Vector3(
		clampf(worker_pos.x, job.world_bounds.position.x, job.world_bounds.end.x),
		worker_pos.y,
		clampf(worker_pos.z, job.world_bounds.position.z, job.world_bounds.end.z)
	)
	return worker_pos.distance_to(closest)


func _add_work_to_node(job: UnifiedJobClass, work_amount: float) -> void:
	"""Forward work progress to the job's visual node"""
	var node: Node = job.metadata.get("job_node")

	# Visual nodes expect a 0-1 progress fraction (1.0 = complete)
	var progress_0_to_1: float = (work_amount / job.work_required) if job.work_required > 0 else 0.0

	match job.job_type:
		UnifiedJobClass.Type.CLEAR_TERRAIN:
			# Trees are felled individually by workers (see WorkerController._process_chopping).
			# The zone is now just a footprint decal + progress bar driven by felled/total.
			if is_instance_valid(job.clearing_zone) and job.clearing_zone.has_method("set_progress"):
				job.clearing_zone.set_progress(job.get_progress())

		UnifiedJobClass.Type.BUILD_STRUCTURE:
			# ConstructionSiteNode handles visual progress only
			# Job completion is handled by job.add_work() when work_done >= work_required
			# Do NOT use node's return value - it completes based on internal progress, not work units
			if is_instance_valid(node) and node.has_method("add_work"):
				node.add_work(progress_0_to_1)

		UnifiedJobClass.Type.DIG_TRENCH:
			# TrenchNode handles visual progress only
			# Job completion is handled by job.add_work() when work_done >= work_required
			if is_instance_valid(node) and node.has_method("add_work"):
				node.add_work(progress_0_to_1)

		UnifiedJobClass.Type.LAY_WIRE:
			# WireObstacleNode handles visual progress only
			# Job completion is handled by job.add_work() when work_done >= work_required
			if is_instance_valid(node) and node.has_method("add_work"):
				node.add_work(progress_0_to_1)

		UnifiedJobClass.Type.BUILD_ROAD:
			# RoadSegmentNode handles visual progress only
			# Job completion is handled by job.add_work() when work_done >= work_required
			if is_instance_valid(node) and node.has_method("add_work"):
				node.add_work(progress_0_to_1)

		UnifiedJobClass.Type.FILL_CRATER:
			# CraterNode handles visual progress only
			# Job completion is handled by job.add_work() when work_done >= work_required
			if is_instance_valid(node) and node.has_method("add_work"):
				node.add_work(progress_0_to_1)

		UnifiedJobClass.Type.FLATTEN_AREA:
			# Carving is worker/cell-driven (WorkerController._process_carving); no AOE here.
			pass


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

func _get_terrain() -> Node:
	"""Terrain engine for height read/write (UnifiedTerrain preferred)."""
	var terrain: Node = get_node_or_null("/root/UnifiedTerrain")
	if not terrain:
		terrain = get_node_or_null("/root/TerrainIntegration")
	return terrain


func get_terrain_height_at(world_pos: Vector3) -> float:
	"""Convenience height read for workers (carve loop checks cell height vs target)."""
	var terrain := _get_terrain()
	if terrain and terrain.has_method("get_height_at"):
		return terrain.get_height_at(world_pos)
	return 0.0


func get_flatten_target_height(job: UnifiedJobClass) -> float:
	"""Compute (once) the height a flatten job carves toward. Blends the footprint with the
	heights of adjacent ALREADY-FLAT/cleared cells so the carved pad links up with neighbours
	instead of leaving a divot. Cached in job metadata."""
	if job.metadata.has("flatten_target_height"):
		return job.metadata["flatten_target_height"]

	var terrain := _get_terrain()
	var target: float = 0.0
	if terrain and terrain.has_method("get_height_at"):
		var samples: Array[float] = [terrain.get_height_at(job.get_centroid())]

		# Sample a one-cell ring just outside the footprint; include neighbours that are
		# already cleared/flat so the pad blends to their height.
		var has_stage: bool = terrain.has_method("get_clearing_stage")
		var r: Rect2i = job.cell_rect
		for x in range(r.position.x - 1, r.end.x + 1):
			for z in range(r.position.y - 1, r.end.y + 1):
				# Perimeter ring only
				if x >= r.position.x and x < r.end.x and z >= r.position.y and z < r.end.y:
					continue
				var wp: Vector3 = GridCoordsClass.gameplay_to_world(Vector2i(x, z))
				if has_stage:
					# Only blend toward neighbours that are already flat (CLEARED+)
					var stage: int = terrain.get_clearing_stage(wp)
					if stage >= 2:  # PARTIALLY_CLEARED/CLEARED and up
						samples.append(terrain.get_height_at(wp))

		var sum: float = 0.0
		for h in samples:
			sum += h
		target = sum / float(samples.size())

	job.metadata["flatten_target_height"] = target
	return target


func carve_terrain_toward(center: Vector3, radius: float, target_height: float, amount: float) -> void:
	"""Lower/raise terrain within radius toward target_height by `amount` (0-1 per call).
	Used by a worker carving one cell over several passes."""
	var terrain := _get_terrain()
	if not terrain or not terrain.has_method("modify_terrain"):
		return

	# CRITICAL: Normalize target_height to 0-1 range before lerping with heightmap data
	# Heightmap stores normalized values (0-1), but target_height is in world meters
	var height_scale: float = 280.0  # Default
	if "height_scale" in terrain:
		height_scale = terrain.height_scale
	var normalized_target: float = target_height / height_scale

	var step: float = clampf(amount, 0.0, 1.0)
	var modifier := func(h: float, falloff: float) -> float:
		return lerpf(h, normalized_target, clampf(step * falloff, 0.0, 1.0))
	terrain.modify_terrain(center, radius, modifier)


## =============================================================================
## WORKER CLASS HELPERS
## =============================================================================

func get_worker_class(worker: Node3D) -> String:
	"""Determine if a worker is an engineer, bulldozer, or infantry (can't build)"""
	if not is_instance_valid(worker):
		return "infantry"  # Default to non-builder

	# Check for explicit worker_class property first
	if worker.has_method("get") and worker.get("worker_class") != null:
		return worker.worker_class

	# Check squad data for capabilities
	if worker.has_method("get"):
		var data: Resource = worker.get("data")
		if data:
			# Bulldozer: vehicle with is_vehicle flag
			if "is_vehicle" in data and data.is_vehicle:
				return "bulldozer"
			# Engineer: infantry with can_build flag
			if "can_build" in data and data.can_build:
				return "engineer"

	# Default: regular infantry (cannot build structures)
	return "infantry"


func can_worker_do_job(worker_class: String, job_type: UnifiedJobClass.Type) -> bool:
	"""Check if a worker class can work on a job type.
	Worker classes: 'engineer' (can build), 'bulldozer' (vehicles), 'infantry' (combat only)"""
	# Infantry cannot do any construction jobs
	if worker_class == "infantry":
		return false

	match job_type:
		UnifiedJobClass.Type.CLEAR_TERRAIN:
			return worker_class in ["engineer", "bulldozer"]  # Both can clear
		UnifiedJobClass.Type.FLATTEN_AREA:
			return worker_class in ["engineer", "bulldozer"]  # Both can flatten (bulldozer faster)
		UnifiedJobClass.Type.BUILD_STRUCTURE:
			return worker_class in ["engineer", "bulldozer"]  # Both can build structures
		UnifiedJobClass.Type.BUILD_ROAD:
			return worker_class == "bulldozer"  # Bulldozers build roads
		UnifiedJobClass.Type.FILL_CRATER:
			return worker_class in ["engineer", "bulldozer"]  # Both can fill
		UnifiedJobClass.Type.DIG_TRENCH:
			return worker_class == "engineer"  # Engineers dig
		UnifiedJobClass.Type.LAY_WIRE:
			return worker_class == "engineer"  # Engineers lay wire
		_:
			return false  # Unknown job types: no one can do by default


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
			return 1.0 if worker_class == "engineer" else 0.7  # Bulldozers slower at fine construction
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

func _create_prerequisites(center: Vector3, footprint_size: Vector2, rotation_y: float = 0.0,
						   priority: UnifiedJobClass.Priority = UnifiedJobClass.Priority.NORMAL,
						   check_slope_for_flatten: bool = false,
						   max_slope_for_building: float = 0.25) -> Dictionary:
	"""Create clear and flatten prerequisite jobs if needed. Returns {clear_job, flatten_job}
	   When rotation_y is non-zero, computes axis-aligned bbox of rotated rectangle.
	   Prerequisites inherit the parent job's priority for proper worker assignment.
	   When check_slope_for_flatten=true, only creates flatten job if slope exceeds max_slope_for_building.
	   Slope is 0-1 normalized (0=flat, 1=cliff). 0.25 ≈ 15 degree slope."""
	var clearing_system := get_node_or_null("/root/ClearingSystem")
	var terrain_grid := get_node_or_null("/root/TerrainIntegration")
	var needs_clearing: bool = false  # Default to NOT needing clearing (optimistic)

	# Check ClearingSystem first (authoritative for clearing state)
	if clearing_system and clearing_system.has_method("is_cleared"):
		needs_clearing = not clearing_system.is_cleared(center)
	elif terrain_grid and terrain_grid.has_method("is_cleared"):
		needs_clearing = not terrain_grid.is_cleared(center)
	elif terrain_grid and terrain_grid.has_method("get"):
		# Check TerrainGrid via TerrainIntegration
		var tg = terrain_grid.get("terrain_grid")
		if tg and tg.has_method("is_cleared"):
			needs_clearing = not tg.is_cleared(center)

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
			priority
		)
		# Store rotation in metadata for oriented clearing (future use)
		if absf(rotation_y) > 0.01:
			clear_job.metadata["rotation"] = rotation_y

	# Determine if flatten is needed
	var needs_flatten: bool = true  # Default for trenches and explicit flatten jobs

	if check_slope_for_flatten:
		# For buildings: only flatten if slope is too steep
		needs_flatten = false
		if terrain_grid and terrain_grid.has_method("get_slope_at"):
			var slope: float = terrain_grid.get_slope_at(center)
			needs_flatten = slope > max_slope_for_building
		elif terrain_grid and terrain_grid.has_method("get"):
			var tg = terrain_grid.get("terrain_grid")
			if tg and tg.has_method("get_slope_at"):
				var slope: float = tg.get_slope_at(center)
				needs_flatten = slope > max_slope_for_building

	if needs_flatten:
		flatten_job = create_job(
			UnifiedJobClass.Type.FLATTEN_AREA,
			center,
			effective_size,
			priority
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

	# Create prerequisite jobs (with rotation for oriented clearing, inherit priority)
	var prereqs: Dictionary = _create_prerequisites(center, size, rotation_y, priority)

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
	INSUFFICIENT_SUPPLY, # Not enough supply (handled in create_build_job)
	OUT_OF_BOUNDS,      # Position is outside playable map area
	OUTSIDE_FIREBASE,   # Firebase Defense building not within TOC influence zone
	INVALID_BRIDGE_SPAN # Bridge not spanning water or ravine properly
}


func validate_placement(center: Vector3, footprint_size: Vector2, building_type: int = -1, rotation_y: float = 0.0) -> Dictionary:
	"""Validate if a building can be placed at this location.
	Returns {valid: bool, error: PlacementError, message: String}"""
	# Check map bounds first (most common rejection for edge clicks)
	var bounds_error: Dictionary = _check_map_bounds(center, footprint_size)
	if not bounds_error.valid:
		return bounds_error

	# Check for overlapping buildings
	var overlap_error: Dictionary = _check_building_overlap(center, footprint_size)
	if not overlap_error.valid:
		return overlap_error

	# Check for overlapping construction jobs
	var job_overlap: Dictionary = _check_job_overlap(center, footprint_size)
	if not job_overlap.valid:
		return job_overlap

	# Special validation for bridges - must span water or ravine
	# Bridges skip standard slope/water checks since they're meant to span these
	var is_bridge: bool = building_type == BuildingDataClass.BuildingType.MODULAR_BRIDGE or building_type == BuildingDataClass.BuildingType.PONTOON_BRIDGE
	if is_bridge:
		var bridge_result: Dictionary = validate_bridge_placement(center, footprint_size, rotation_y)
		if not bridge_result.valid:
			return {
				"valid": false,
				"error": PlacementError.INVALID_BRIDGE_SPAN,
				"message": bridge_result.message
			}
		# Bridge passed - return success (skip slope/water checks)
		return {"valid": true, "error": PlacementError.NONE, "message": bridge_result.message}

	# Standard terrain checks for non-bridge buildings
	# Check terrain slope
	var slope_error: Dictionary = _check_terrain_slope(center, footprint_size)
	if not slope_error.valid:
		return slope_error

	# Check for water
	var water_error: Dictionary = _check_terrain_water(center)
	if not water_error.valid:
		return water_error

	# Check firebase zone requirements (Firebase Defense buildings need TOC influence)
	var firebase_error: Dictionary = _check_firebase_zone(center, building_type)
	if not firebase_error.valid:
		return firebase_error

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


func _check_map_bounds(center: Vector3, size: Vector2) -> Dictionary:
	"""Check if position is within playable map bounds"""
	# Get map size from GridCoords or terrain
	var map_size: float = 320.0  # Default fallback

	# Try to get actual map size from GridCoords
	var grid_coords_script = load("res://terrain/core/grid_coords.gd")
	if grid_coords_script and "map_size" in grid_coords_script:
		map_size = grid_coords_script.map_size
	else:
		# Try terrain integration
		var terrain: Node = get_node_or_null("/root/TerrainIntegration")
		if terrain and terrain.has_method("get") and "map_size" in terrain:
			map_size = terrain.map_size
		else:
			# Try unified terrain
			var unified: Node = get_node_or_null("/root/UnifiedTerrain")
			if unified and unified.has_method("get") and "map_size" in unified:
				map_size = unified.map_size

	# Account for building footprint - ensure entire building fits
	var half_x: float = size.x * 0.5
	var half_z: float = size.y * 0.5
	var margin: float = 2.0  # Small margin from edge

	var min_bound: float = margin + maxf(half_x, half_z)
	var max_bound: float = map_size - margin - maxf(half_x, half_z)

	if center.x < min_bound or center.x > max_bound or center.z < min_bound or center.z > max_bound:
		return {
			"valid": false,
			"error": PlacementError.OUT_OF_BOUNDS,
			"message": "Outside playable area (%.0f, %.0f) - map is %.0fm" % [center.x, center.z, map_size]
		}

	return {"valid": true, "error": PlacementError.NONE, "message": ""}


func _check_firebase_zone(center: Vector3, building_type: int) -> Dictionary:
	"""Check if building requires firebase zone and if position is within one.

	Building placement rules:
	- Field Defense (can_place_anywhere=true): Placeable anywhere (sandbags, wire, claymores)
	- TOC (is_hq_building=true, can_place_anywhere=true): Placeable anywhere, creates firebase zone
	- Firebase Defense (can_place_anywhere=false): Requires being within TOC influence zone
	"""
	# No building type specified - skip check
	if building_type < 0:
		return {"valid": true, "error": PlacementError.NONE, "message": ""}

	# Get building data to check placement rules
	var building_data: BuildingDataClass = BuildingDataClass.get_building_data(building_type)
	if not building_data:
		return {"valid": true, "error": PlacementError.NONE, "message": ""}

	# Buildings that can_place_anywhere don't need firebase zone
	# This includes: Field defenses (sandbags, wire, claymores) AND TOC itself
	if building_data.can_place_anywhere:
		print("[JobSystem] _check_firebase_zone: %s can_place_anywhere=true, skipping" % building_data.display_name)
		return {"valid": true, "error": PlacementError.NONE, "message": ""}

	# Firebase Defense buildings require being within a TOC influence zone
	# Check all active firebases for influence coverage
	var firebases: Array[Node] = []
	for node in get_tree().get_nodes_in_group("firebases"):
		if is_instance_valid(node):
			firebases.append(node)

	print("[JobSystem] _check_firebase_zone: %s requires firebase, found %d firebases" % [
		building_data.display_name, firebases.size()
	])

	# Check if position is within any firebase influence zone
	for firebase in firebases:
		if firebase.has_method("is_position_in_influence"):
			var is_active: bool = firebase.is_active() if firebase.has_method("is_active") else false
			var influence_r: float = firebase.influence_radius if "influence_radius" in firebase else 0.0
			var dist: float = firebase.global_position.distance_to(center)
			var in_influence: bool = firebase.is_position_in_influence(center)
			print("[JobSystem]   Firebase '%s': is_active=%s, influence_radius=%.1f, dist=%.1f, in_influence=%s" % [
				firebase.firebase_name if "firebase_name" in firebase else "unknown",
				is_active, influence_r, dist, in_influence
			])
			if in_influence:
				return {"valid": true, "error": PlacementError.NONE, "message": ""}

	# Not within any firebase zone - placement invalid for Firebase Defense buildings
	print("[JobSystem] _check_firebase_zone: FAILED - not in any active firebase zone")
	return {
		"valid": false,
		"error": PlacementError.OUTSIDE_FIREBASE,
		"message": "Requires TOC - build a TOC first to establish firebase zone"
	}


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
		PlacementError.OUT_OF_BOUNDS:
			return "Outside playable area"
		PlacementError.OUTSIDE_FIREBASE:
			return "Requires TOC - build a TOC first"
		PlacementError.INVALID_BRIDGE_SPAN:
			return "Bridge must span water or ravine"
		_:
			return "Invalid placement"


## =============================================================================
## BRIDGE PLACEMENT VALIDATION
## =============================================================================

func validate_bridge_placement(center: Vector3, footprint: Vector2, rotation_y: float) -> Dictionary:
	"""Validate that bridge placement spans water or ravine.

	Bridges must be placed so that:
	- The middle of the span is over water OR significantly lower terrain (ravine)
	- The endpoints are on higher ground (not in water)

	Returns: {"valid": bool, "message": String, "span_start": Vector3, "span_end": Vector3}
	"""
	var terrain: Node = _get_terrain()
	if not terrain:
		return {"valid": false, "message": "No terrain system available", "span_start": Vector3.ZERO, "span_end": Vector3.ZERO}

	# Calculate bridge endpoints based on rotation
	# Bridge spans along its length (footprint.y = 14m for modular bridge)
	var half_length: float = footprint.y * 0.5
	var cos_r: float = cos(rotation_y)
	var sin_r: float = sin(rotation_y)

	# Direction vector along bridge span
	var span_dir := Vector3(sin_r, 0.0, cos_r)

	var span_start: Vector3 = center - span_dir * half_length
	var span_end: Vector3 = center + span_dir * half_length
	var span_middle: Vector3 = center

	# Sample terrain heights at start, middle, end
	var height_start: float = 0.0
	var height_middle: float = 0.0
	var height_end: float = 0.0

	if terrain.has_method("get_height_at"):
		height_start = terrain.get_height_at(span_start)
		height_middle = terrain.get_height_at(span_middle)
		height_end = terrain.get_height_at(span_end)

	# Check for water at endpoints (invalid - bridge needs solid ground at ends)
	var water_level: float = 0.0
	if terrain.has_method("get") and "water_level" in terrain:
		water_level = terrain.water_level

	var start_in_water: bool = height_start < water_level - 0.3
	var end_in_water: bool = height_end < water_level - 0.3
	var middle_is_water: bool = height_middle < water_level + 0.5

	if start_in_water:
		return {
			"valid": false,
			"message": "Bridge start point is in water",
			"span_start": span_start,
			"span_end": span_end
		}

	if end_in_water:
		return {
			"valid": false,
			"message": "Bridge end point is in water",
			"span_start": span_start,
			"span_end": span_end
		}

	# Check if middle is valid span point (water or ravine)
	# Ravine threshold: middle should be at least 2m lower than average of endpoints
	var endpoint_avg: float = (height_start + height_end) * 0.5
	var height_diff: float = endpoint_avg - height_middle
	var is_ravine: bool = height_diff >= 2.0

	if not middle_is_water and not is_ravine:
		return {
			"valid": false,
			"message": "Bridge must span water or ravine (middle %.1fm lower needed)" % (2.0 - height_diff),
			"span_start": span_start,
			"span_end": span_end
		}

	# Additional check: endpoints should be at roughly similar heights (< 3m difference)
	var endpoint_diff: float = absf(height_start - height_end)
	if endpoint_diff > 3.0:
		return {
			"valid": false,
			"message": "Bridge endpoints too uneven (%.1fm difference)" % endpoint_diff,
			"span_start": span_start,
			"span_end": span_end
		}

	# Valid placement
	var span_type: String = "water" if middle_is_water else "ravine"
	return {
		"valid": true,
		"message": "Valid bridge placement spanning %s" % span_type,
		"span_start": span_start,
		"span_end": span_end,
		"span_type": span_type,
		"height_diff": height_diff
	}


## =============================================================================
## REAL-TIME VALIDATION CACHE (For placement preview)
## =============================================================================

## Cache for validate_placement results (cleared each frame)
var _validation_cache: Dictionary = {}
var _validation_cache_frame: int = -1


func validate_placement_real_time(center: Vector3, footprint_size: Vector2, building_type: int = -1, rotation_y: float = 0.0) -> Dictionary:
	"""Optimized validation for real-time ghost preview updates.
	Caches results per-frame to avoid redundant terrain/overlap checks during cursor movement."""
	# Clear cache on new frame
	var current_frame: int = Engine.get_process_frames()
	if current_frame != _validation_cache_frame:
		_validation_cache.clear()
		_validation_cache_frame = current_frame

	# Create cache key (quantized to 0.5m grid for cache efficiency)
	# Include rotation in key for bridges (quantized to 15 degrees)
	var is_bridge_type: bool = building_type == BuildingDataClass.BuildingType.MODULAR_BRIDGE or building_type == BuildingDataClass.BuildingType.PONTOON_BRIDGE
	var rot_key: int = int(rotation_y * 12.0 / TAU) if is_bridge_type else 0
	var key := "%d_%d_%d_%d" % [int(center.x * 2), int(center.z * 2), building_type, rot_key]

	# Return cached result if available
	if _validation_cache.has(key):
		return _validation_cache[key]

	# Perform actual validation
	var result := validate_placement(center, footprint_size, building_type, rotation_y)

	# Cache the result
	_validation_cache[key] = result

	return result
