extends Node
## JobManager - Autoload singleton managing all construction jobs
##
## Owns all active JobNodes, handles registration, dependency resolution,
## cancellation, and completion. Provides factory methods for creating jobs.
##
## Access via: JobManager.create_job(type, area, ...)

const JobTypes = preload("res://firebase_system/jobs/job_types.gd")
const JobNode = preload("res://firebase_system/jobs/job_node.gd")
const JobNodeVisual = preload("res://firebase_system/jobs/job_node_visual.gd")

## Signals
signal job_created(job: JobNode)
signal job_started(job: JobNode)
signal job_completed(job: JobNode)
signal job_cancelled(job: JobNode)

## All active jobs
var active_jobs: Array[JobNode] = []

## Job ID counter
var _next_job_id: int = 1

## Container for job nodes (keeps scene tree clean)
var _job_container: Node3D = null


func _ready() -> void:
	_job_container = Node3D.new()
	_job_container.name = "JobNodes"
	add_child(_job_container)

	print("[JobManager] Initialized")


func _process(_delta: float) -> void:
	# Clean up completed/cancelled jobs from tracking
	var to_remove: Array[JobNode] = []
	for job in active_jobs:
		if not is_instance_valid(job):
			to_remove.append(job)
		elif job.completion_state == JobTypes.CompletionState.COMPLETE:
			# Keep for a bit so visuals can fade
			pass
		elif job.completion_state == JobTypes.CompletionState.CANCELLED:
			to_remove.append(job)

	for job in to_remove:
		active_jobs.erase(job)


## Create an area job (CLEAR_TERRAIN, FLATTEN_AREA)
func create_area_job(
	job_type: JobTypes.JobType,
	min_corner: Vector3,
	max_corner: Vector3,
	auto_resolve_dependencies: bool = true
) -> JobNode:
	var bounds := AABB(min_corner, max_corner - min_corner)

	var job := JobNode.create_area_job(job_type, bounds)
	_register_job(job)

	# Auto-resolve dependencies for terrain jobs
	if auto_resolve_dependencies:
		_resolve_area_dependencies(job, bounds)

	return job


## Create a road job (BUILD_ROAD)
func create_road_job(
	points: PackedVector3Array,
	auto_resolve_dependencies: bool = true
) -> JobNode:
	var job := JobNode.create_road_job(points)
	_register_job(job)

	# Roads may need clearing along the path
	if auto_resolve_dependencies:
		_resolve_road_dependencies(job, points)

	return job


## Create a structure job (BUILD_STRUCTURE)
func create_build_job(
	position: Vector3,
	building_type: int,
	rotation: float = 0.0,
	footprint_size: Vector2 = Vector2(4.0, 4.0),
	auto_resolve_dependencies: bool = true
) -> JobNode:
	var metadata := {
		"building_type": building_type,
		"rotation": rotation,
		"footprint_size": footprint_size,
	}

	var job := JobNode.create_point_job(
		JobTypes.JobType.BUILD_STRUCTURE,
		position,
		metadata
	)
	_register_job(job)

	# Building needs clear and flatten first
	if auto_resolve_dependencies:
		_resolve_build_dependencies(job, position, footprint_size)

	return job


## Create a crater fill job (FILL_CRATER)
func create_fill_job(position: Vector3) -> JobNode:
	var job := JobNode.create_point_job(
		JobTypes.JobType.FILL_CRATER,
		position
	)
	_register_job(job)
	return job


## Get all jobs in a given area
func get_jobs_in_area(bounds: AABB) -> Array[JobNode]:
	var result: Array[JobNode] = []
	for job in active_jobs:
		if not is_instance_valid(job):
			continue

		var centroid: Vector3 = job.get_centroid()
		if bounds.has_point(centroid):
			result.append(job)

	return result


## Get all jobs of a specific type
func get_jobs_by_type(job_type: JobTypes.JobType) -> Array[JobNode]:
	var result: Array[JobNode] = []
	for job in active_jobs:
		if is_instance_valid(job) and job.job_type == job_type:
			result.append(job)
	return result


## Get all jobs that need workers
func get_jobs_needing_workers(worker_class: String = "") -> Array[JobNode]:
	var result: Array[JobNode] = []
	for job in active_jobs:
		if not is_instance_valid(job):
			continue

		if not job.can_be_worked():
			continue

		if job.assigned_workers.size() >= job.max_workers:
			continue

		# Check worker class compatibility
		if worker_class != "":
			if not JobTypes.can_worker_do_job(worker_class, job.job_type):
				continue

		result.append(job)

	return result


## Get the nearest job that needs a specific worker type
func get_nearest_job_for_worker(worker: Node3D, worker_class: String) -> JobNode:
	var available_jobs := get_jobs_needing_workers(worker_class)

	if available_jobs.is_empty():
		return null

	var worker_pos: Vector3 = worker.global_position
	var nearest: JobNode = null
	var nearest_dist: float = INF

	for job in available_jobs:
		var dist: float = worker_pos.distance_to(job.get_centroid())
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = job

	return nearest


## Cancel all jobs in an area
func cancel_jobs_in_area(bounds: AABB) -> int:
	var jobs := get_jobs_in_area(bounds)
	for job in jobs:
		job.cancel()
	return jobs.size()


## Cancel a specific job by ID
func cancel_job(job_id: int) -> bool:
	for job in active_jobs:
		if is_instance_valid(job) and job.job_id == job_id:
			job.cancel()
			return true
	return false


## Get job by ID
func get_job_by_id(job_id: int) -> JobNode:
	for job in active_jobs:
		if is_instance_valid(job) and job.job_id == job_id:
			return job
	return null


## Get count of active jobs
func get_active_job_count() -> int:
	var count := 0
	for job in active_jobs:
		if is_instance_valid(job) and job.completion_state != JobTypes.CompletionState.COMPLETE:
			count += 1
	return count


## Internal: register a job
func _register_job(job: JobNode) -> void:
	job.job_id = _next_job_id
	_next_job_id += 1

	# Add to scene tree
	_job_container.add_child(job)

	# Create visual
	var visual := JobNodeVisual.new()
	visual.name = "JobVisual_%d" % job.job_id
	job.add_child(visual)
	job.visual = visual
	visual.setup(job)

	# Connect signals
	job.job_started.connect(_on_job_started.bind(job))
	job.job_completed.connect(_on_job_completed)
	job.job_cancelled.connect(_on_job_cancelled)

	# Track
	active_jobs.append(job)

	job_created.emit(job)
	print("[JobManager] Created job #%d: %s at %s" % [
		job.job_id,
		JobTypes.get_job_name(job.job_type),
		job.get_centroid()
	])


## Internal: resolve dependencies for area jobs
func _resolve_area_dependencies(job: JobNode, _bounds: AABB) -> void:
	# FLATTEN needs CLEAR first (if on jungle terrain)
	if job.job_type == JobTypes.JobType.FLATTEN_AREA:
		if _is_terrain_jungle(job.get_centroid()):
			var clear_job := JobNode.create_area_job(
				JobTypes.JobType.CLEAR_TERRAIN,
				job.area_bounds
			)
			_register_job(clear_job)
			job.add_prerequisite(clear_job)


## Internal: resolve dependencies for road jobs
func _resolve_road_dependencies(job: JobNode, points: PackedVector3Array) -> void:
	# Check if road passes through jungle
	var needs_clearing := false
	for pt in points:
		if _is_terrain_jungle(pt):
			needs_clearing = true
			break

	if needs_clearing:
		# Create a clear job covering the road corridor
		var min_pos := Vector3(INF, INF, INF)
		var max_pos := Vector3(-INF, -INF, -INF)

		for pt in points:
			min_pos.x = minf(min_pos.x, pt.x - 2.0)
			min_pos.z = minf(min_pos.z, pt.z - 2.0)
			max_pos.x = maxf(max_pos.x, pt.x + 2.0)
			max_pos.z = maxf(max_pos.z, pt.z + 2.0)

		min_pos.y = 0
		max_pos.y = 0

		var clear_bounds := AABB(min_pos, max_pos - min_pos)
		var clear_job := JobNode.create_area_job(
			JobTypes.JobType.CLEAR_TERRAIN,
			clear_bounds
		)
		_register_job(clear_job)
		job.add_prerequisite(clear_job)


## Internal: resolve dependencies for build jobs
func _resolve_build_dependencies(job: JobNode, position: Vector3, footprint_size: Vector2) -> void:
	# Calculate bounds for the building footprint
	var half_size := Vector3(footprint_size.x * 0.5, 0, footprint_size.y * 0.5)
	var min_pos := position - half_size
	var max_pos := position + half_size
	min_pos.y = 0
	max_pos.y = 0

	var bounds := AABB(min_pos, max_pos - min_pos)

	# Check if terrain needs clearing
	var needs_clearing := _is_terrain_jungle(position)

	# Check if terrain needs flattening
	var needs_flattening := _is_terrain_uneven(position, footprint_size)

	if needs_clearing:
		# Create clear job
		var clear_job := JobNode.create_area_job(
			JobTypes.JobType.CLEAR_TERRAIN,
			bounds
		)
		_register_job(clear_job)

		if needs_flattening:
			# Flatten depends on clear
			var flatten_job := JobNode.create_area_job(
				JobTypes.JobType.FLATTEN_AREA,
				bounds
			)
			_register_job(flatten_job)
			flatten_job.add_prerequisite(clear_job)
			job.add_prerequisite(flatten_job)
		else:
			job.add_prerequisite(clear_job)

	elif needs_flattening:
		var flatten_job := JobNode.create_area_job(
			JobTypes.JobType.FLATTEN_AREA,
			bounds
		)
		_register_job(flatten_job)
		job.add_prerequisite(flatten_job)


## Check if position is in jungle terrain
func _is_terrain_jungle(position: Vector3) -> bool:
	var clearing_system := get_node_or_null("/root/TerrainClearingSystem")
	if clearing_system and clearing_system.has_method("is_cleared"):
		return not clearing_system.is_cleared(position)

	# Also check TerrainIntegration
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_vegetation_density"):
		var density: float = terrain.get_vegetation_density(position)
		return density > 0.3

	# Default: assume cleared if we can't check
	return false


## Check if terrain is too uneven for building
func _is_terrain_uneven(position: Vector3, footprint_size: Vector2) -> bool:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if not terrain or not terrain.has_method("get_height_at"):
		return false

	# Sample heights at corners
	var half_x := footprint_size.x * 0.5
	var half_z := footprint_size.y * 0.5

	var heights: Array[float] = []
	heights.append(terrain.get_height_at(position + Vector3(-half_x, 0, -half_z)))
	heights.append(terrain.get_height_at(position + Vector3(half_x, 0, -half_z)))
	heights.append(terrain.get_height_at(position + Vector3(-half_x, 0, half_z)))
	heights.append(terrain.get_height_at(position + Vector3(half_x, 0, half_z)))

	var min_h: float = heights[0]
	var max_h: float = heights[0]
	for h in heights:
		min_h = minf(min_h, h)
		max_h = maxf(max_h, h)

	# More than 1m difference = uneven
	return (max_h - min_h) > 1.0


## Signal handlers
func _on_job_started(job: JobNode) -> void:
	job_started.emit(job)


func _on_job_completed(job: JobNode) -> void:
	# Execute the actual terrain effect when job completes
	_execute_job_effect(job)

	job_completed.emit(job)
	print("[JobManager] Job #%d completed: %s" % [
		job.job_id,
		JobTypes.get_job_name(job.job_type)
	])


## Execute the terrain/world effect when a job completes
func _execute_job_effect(job: JobNode) -> void:
	match job.job_type:
		JobTypes.JobType.CLEAR_TERRAIN:
			_execute_clear_effect(job)
		JobTypes.JobType.FLATTEN_AREA:
			_execute_flatten_effect(job)
		JobTypes.JobType.BUILD_ROAD:
			_execute_road_effect(job)
		# BUILD_STRUCTURE and FILL_CRATER handled by their own systems


## Clear vegetation when CLEAR_TERRAIN job completes
func _execute_clear_effect(job: JobNode) -> void:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if not terrain:
		return

	# Get the area bounds
	var center: Vector3 = job.area_bounds.get_center()
	var size: Vector3 = job.area_bounds.size
	var radius: float = maxf(size.x, size.z) * 0.5 + 2.0  # Add buffer

	# Clear vegetation in the area
	if terrain.has_method("clear_vegetation_around_building"):
		var cleared: int = terrain.clear_vegetation_around_building(center, radius)
		print("[JobManager] CLEAR_TERRAIN effect: cleared %d vegetation bundles at %s (r=%.1f)" % [
			cleared, center, radius
		])

	# Also update the clearing system's zone state
	var clearing_system := get_node_or_null("/root/TerrainClearingSystem")
	if clearing_system and clearing_system.has_method("mark_area_cleared"):
		clearing_system.mark_area_cleared(job.area_bounds)


## Flatten terrain when FLATTEN_AREA job completes
func _execute_flatten_effect(job: JobNode) -> void:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if not terrain:
		return

	var center: Vector3 = job.area_bounds.get_center()
	var size: Vector3 = job.area_bounds.size
	var radius: float = maxf(size.x, size.z) * 0.5

	# Use terrain flattening system if available
	var flattening := get_node_or_null("/root/TerrainFlatteningSystem")
	if flattening and flattening.has_method("flatten_area"):
		flattening.flatten_area(center, radius)
		print("[JobManager] FLATTEN_AREA effect: flattened terrain at %s (r=%.1f)" % [center, radius])


## Create road visual when BUILD_ROAD job completes
func _execute_road_effect(job: JobNode) -> void:
	# Road visuals are handled progressively by RoadDecalRenderer
	# This just logs completion
	print("[JobManager] BUILD_ROAD effect: road complete with %d waypoints" % job.path_points.size())


func _on_job_cancelled(job: JobNode) -> void:
	job_cancelled.emit(job)
	print("[JobManager] Job #%d cancelled: %s" % [
		job.job_id,
		JobTypes.get_job_name(job.job_type)
	])


## Helper: Create a complete build chain manually
## Returns the final build job (with all prerequisites set up)
func enqueue_build_with_prerequisites(
	position: Vector3,
	building_type: int,
	rotation: float = 0.0,
	footprint_size: Vector2 = Vector2(4.0, 4.0)
) -> JobNode:
	return create_build_job(position, building_type, rotation, footprint_size, true)


## Debug: Print all active jobs
func debug_print_jobs() -> void:
	print("=== Active Jobs ===")
	for job in active_jobs:
		if not is_instance_valid(job):
			continue
		print("  #%d: %s [%s] - %.1f%%" % [
			job.job_id,
			JobTypes.get_job_name(job.job_type),
			JobTypes.CompletionState.keys()[job.completion_state],
			job.get_progress_percent()
		])
		if job.prerequisites.size() > 0:
			var prereq_ids: PackedInt32Array = []
			for prereq in job.prerequisites:
				if is_instance_valid(prereq):
					prereq_ids.append(prereq.job_id)
			print("    Prerequisites: %s" % str(prereq_ids))
	print("===================")
