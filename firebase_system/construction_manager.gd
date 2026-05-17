extends Node
## ConstructionManager - Autoload singleton
## Access via: ConstructionManager.build_immediately(firebase, type)
##
## ROLE CLARIFICATION (2026-05-16):
## - ConstructionManager handles LEGACY ConstructionZone system (firebase building slots)
## - BuilderAI handles NEW JobNode system (paintable clearing/building jobs)
## - Worker assignment is EXCLUSIVELY handled by BuilderAI to prevent conflicts
## - Job work processing is EXCLUSIVELY handled by BuilderAI._process_job_work()
##
## This manager still handles:
## - Construction queues for firebase zones
## - ConstructionZone work processing (old system)
## - Job registration (tracking only, not processing)
## - Creating firebases

signal construction_queued(firebase: Node3D, building_type: int)
signal construction_started(firebase: Node3D, zone: Node3D)
signal construction_progress(zone: Node3D, progress: float)
signal construction_complete(firebase: Node3D, building: Node3D)
signal construction_failed(firebase: Node3D, reason: String)

const Firebase = preload("res://firebase_system/firebase.gd")
const ConstructionZone = preload("res://firebase_system/construction_zone.gd")
const BuildingData = preload("res://firebase_system/building_data.gd")
const JobTypes = preload("res://firebase_system/jobs/job_types.gd")
const JobNode = preload("res://firebase_system/jobs/job_node.gd")

## Construction queue (per firebase)
var construction_queues: Dictionary = {}  # firebase -> Array of building_types

## Active constructions
var active_constructions: Array[ConstructionZone] = []

## Active JobNodes (for the new job system)
var active_job_nodes: Array[JobNode] = []

## Engineer work rate
const ENGINEER_WORK_RATE := 1.0  # Work units per second per engineer
const BULLDOZER_WORK_RATE := 3.0  # Bulldozers work faster on terrain jobs

## Auto-build configuration
@export var auto_assign_enabled: bool = true
@export var auto_assign_radius: float = 50.0  # Search radius for idle engineers
@export var max_engineers_per_zone: int = 4
@export var max_workers_per_job: int = 4


func _ready() -> void:
	# Connect to our own signal for auto-assignment
	construction_started.connect(_on_construction_started)
	print("[ConstructionManager] Initialized (auto-assign: %s)" % auto_assign_enabled)


func _process(delta: float) -> void:
	_process_active_constructions(delta)
	# NOTE: Job processing disabled - BuilderAI._process_job_work() is now authoritative
	# for applying work to JobNodes. This prevents double-work being applied to jobs.
	# _process_job_nodes(delta)
	_process_queues()
	# NOTE: Auto-assignment disabled - BuilderAI is now authoritative for worker assignment
	# This prevents duplicate assignment conflicts. See BuilderAI._on_job_created() and
	# BuilderAI._auto_assign_work() for the single source of worker assignment.
	# _auto_assign_workers_to_jobs()


func _process_active_constructions(delta: float) -> void:
	"""Update all active construction zones"""
	var completed: Array[ConstructionZone] = []

	for zone in active_constructions:
		if not is_instance_valid(zone):
			completed.append(zone)
			continue

		# Calculate work from assigned engineers
		var work: float = zone.assigned_engineers.size() * ENGINEER_WORK_RATE * delta

		if work > 0:
			zone.add_work(work)

		# Check if complete
		if zone.is_complete():
			completed.append(zone)

			# Find parent firebase
			var firebase: Node3D = _find_firebase_for_zone(zone)
			if firebase:
				construction_complete.emit(firebase, zone.completed_building)

	# Remove completed zones from active list
	for zone in completed:
		active_constructions.erase(zone)


func _process_queues() -> void:
	"""Process construction queues for each firebase"""
	for firebase in construction_queues:
		if not is_instance_valid(firebase):
			continue

		var queue: Array = construction_queues[firebase]
		if queue.is_empty():
			continue

		# Try to start next building in queue
		var building_type: int = queue[0]
		var result: bool = _try_start_construction(firebase, building_type)

		if result:
			queue.pop_front()


func _process_job_nodes(delta: float) -> void:
	"""Process all active job nodes - apply work from assigned workers"""
	var completed: Array[JobNode] = []

	for job in active_job_nodes:
		if not is_instance_valid(job):
			completed.append(job)
			continue

		# Skip if job can't be worked
		if not job.can_be_worked():
			continue

		# Calculate work from assigned workers
		var work: float = 0.0
		for worker in job.assigned_workers:
			if not is_instance_valid(worker):
				continue

			# Only count workers who are in range
			if not job.is_worker_in_range(worker):
				continue

			# Determine worker class and rate
			var worker_class := _get_worker_class(worker)
			var rate: float = ENGINEER_WORK_RATE
			if worker_class == JobTypes.WORKER_BULLDOZER:
				rate = BULLDOZER_WORK_RATE

			# Apply work rate multiplier
			var multiplier: float = JobTypes.get_work_rate_multiplier(worker_class, job.job_type)
			work += rate * multiplier * delta

		if work > 0:
			job.add_work(work)

		# Check completion
		if job.completion_state == JobTypes.CompletionState.COMPLETE:
			completed.append(job)

	# Remove completed jobs
	for job in completed:
		active_job_nodes.erase(job)


func _auto_assign_workers_to_jobs() -> void:
	"""Auto-assign idle workers to pending jobs"""
	if not auto_assign_enabled:
		return

	# Get jobs needing workers
	var job_mgr := get_node_or_null("/root/JobManager")
	if not job_mgr:
		return

	var jobs_needing_workers: Array = job_mgr.get_jobs_needing_workers()

	for job in jobs_needing_workers:
		if not job is JobNode:
			continue

		var job_node: JobNode = job as JobNode
		if not job_node.can_be_worked():
			continue

		if job_node.assigned_workers.size() >= max_workers_per_job:
			continue

		# Find appropriate workers
		var required_class: String = JobTypes.get_required_worker_class(job_node.job_type)
		var workers := _find_idle_workers_for_job(job_node.get_centroid(), required_class)

		# Assign up to max
		var to_assign: int = mini(
			workers.size(),
			max_workers_per_job - job_node.assigned_workers.size()
		)

		for i in to_assign:
			var worker: Node3D = workers[i]
			if job_node.assign_worker(worker):
				_send_worker_to_job(worker, job_node)


func _get_worker_class(worker: Node3D) -> String:
	"""Determine if a worker is an engineer or bulldozer"""
	if worker.has_method("get"):
		var data: Resource = worker.get("data")
		if data:
			if "is_vehicle" in data and data.is_vehicle:
				return JobTypes.WORKER_BULLDOZER
	return JobTypes.WORKER_ENGINEER


func _find_idle_workers_for_job(position: Vector3, required_class: String) -> Array[Node3D]:
	"""Find idle workers of the appropriate type near a position"""
	var result: Array[Node3D] = []

	# Use SpatialHashGrid if available
	var grid: Node = get_node_or_null("/root/SpatialHashGrid")
	var units: Array[Node3D] = []

	if grid and grid.has_method("get_units_in_radius"):
		units = grid.get_units_in_radius(position, auto_assign_radius)
	else:
		# Fallback to group search
		for node in get_tree().get_nodes_in_group("player_units"):
			if node is Node3D:
				var unit := node as Node3D
				if position.distance_to(unit.global_position) <= auto_assign_radius:
					units.append(unit)

	for unit in units:
		if not is_instance_valid(unit):
			continue

		# Check if player controlled
		if unit.has_method("get") and unit.get("is_player_controlled") != null:
			if not unit.is_player_controlled:
				continue

		# Check worker class
		var worker_class := _get_worker_class(unit)

		# Engineers can do any job, bulldozers only terrain jobs
		if required_class == JobTypes.WORKER_BULLDOZER:
			if worker_class != JobTypes.WORKER_BULLDOZER:
				continue
		elif not JobTypes.can_worker_do_job(worker_class, JobTypes.JobType.BUILD_STRUCTURE):
			# Workers that can't build can still do terrain work
			pass

		# Check if idle
		if unit.has_method("get") and unit.get("state") != null:
			var state: int = unit.state
			if state != 0:  # 0 = IDLE in Squad
				continue

		# Check if already assigned to a job
		if _is_worker_assigned_to_job(unit):
			continue

		result.append(unit)

	# Sort by distance
	result.sort_custom(func(a: Node3D, b: Node3D):
		return position.distance_squared_to(a.global_position) < position.distance_squared_to(b.global_position)
	)

	return result


func _is_worker_assigned_to_job(worker: Node3D) -> bool:
	"""Check if a worker is already assigned to any job"""
	for job in active_job_nodes:
		if is_instance_valid(job) and worker in job.assigned_workers:
			return true
	return false


func _send_worker_to_job(worker: Node3D, job: JobNode) -> void:
	"""DEPRECATED: Use BuilderAI.walk_to_job() instead.
	This method sends workers to centroid, not edge. BuilderAI.walk_to_job()
	uses get_work_position() which sends workers to nearest edge for area jobs."""
	push_warning("[ConstructionManager] _send_worker_to_job is deprecated - use BuilderAI.walk_to_job()")
	if worker.has_method("move_to"):
		worker.move_to(job.get_centroid())
		print("[ConstructionManager] Sent %s to job #%d at %s" % [
			worker.name, job.job_id, job.get_centroid()
		])


func _try_start_construction(firebase: Node3D, building_type: int) -> bool:
	"""Try to start construction on a firebase"""
	if not firebase is Firebase:
		return false

	var zone: ConstructionZone = firebase.get_empty_zone()
	if not zone:
		construction_failed.emit(firebase, "No empty construction zones")
		return false

	var data: BuildingData = BuildingData.get_building_data(building_type)

	# Check requirements
	if data.requires_firebase_level > firebase.level:
		construction_failed.emit(firebase, "Firebase level too low")
		return false

	if firebase.supply_level < data.supply_cost:
		construction_failed.emit(firebase, "Insufficient supplies")
		return false

	# Check terrain clearing if required
	if data.requires_cleared_terrain:
		var clearing_system: Node = get_node_or_null("/root/TerrainClearingSystem")
		if clearing_system and not clearing_system.is_cleared(zone.global_position):
			construction_failed.emit(firebase, "Terrain not cleared")
			return false

	# Start construction
	firebase.supply_level -= data.supply_cost
	zone.start_construction(data)
	active_constructions.append(zone)

	construction_started.emit(firebase, zone)

	return true


func _find_firebase_for_zone(zone: ConstructionZone) -> Node3D:
	"""Find the firebase that owns a construction zone"""
	var parent: Node = zone.get_parent()
	while parent:
		if parent is Firebase:
			return parent
		parent = parent.get_parent()
	return null


## Public API

func queue_building(firebase: Node3D, building_type: int) -> void:
	"""Add building to construction queue"""
	if firebase not in construction_queues:
		construction_queues[firebase] = []

	construction_queues[firebase].append(building_type)
	construction_queued.emit(firebase, building_type)


func build_immediately(firebase: Node3D, building_type: int) -> bool:
	"""Try to start building immediately (skip queue)"""
	return _try_start_construction(firebase, building_type)


func assign_engineer(engineer: Node3D, zone: ConstructionZone) -> void:
	"""Assign an engineer to work on a construction zone"""
	if zone and zone.is_building():
		zone.assign_engineer(engineer)


func unassign_engineer(engineer: Node3D, zone: ConstructionZone) -> void:
	"""Remove engineer from construction"""
	if zone:
		zone.unassign_engineer(engineer)


func auto_assign_engineers(firebase: Node3D, engineers: Array[Node3D]) -> void:
	"""Automatically assign engineers to active construction zones"""
	if not firebase is Firebase:
		return

	# Find active construction zones in this firebase
	var active_zones: Array[ConstructionZone] = []
	for zone in firebase.construction_zones:
		if zone.is_building():
			active_zones.append(zone)

	if active_zones.is_empty():
		return

	# Distribute engineers across zones
	var zone_idx: int = 0
	for engineer in engineers:
		active_zones[zone_idx].assign_engineer(engineer)
		zone_idx = (zone_idx + 1) % active_zones.size()


func get_queue_for_firebase(firebase: Node3D) -> Array:
	"""Get construction queue for a firebase"""
	if firebase in construction_queues:
		return construction_queues[firebase]
	return []


func get_active_construction_count() -> int:
	return active_constructions.size()


func cancel_construction(zone: ConstructionZone) -> void:
	"""Cancel construction on a zone"""
	if zone in active_constructions:
		active_constructions.erase(zone)
		zone.cancel_construction()


## =============================================================================
## JOB NODE INTEGRATION
## =============================================================================

func register_job(job: JobNode) -> void:
	"""Register a JobNode for worker assignment and progress tracking"""
	if job and job not in active_job_nodes:
		active_job_nodes.append(job)

		# Connect to job signals
		job.job_completed.connect(_on_job_node_completed)
		job.job_cancelled.connect(_on_job_node_cancelled)

		print("[ConstructionManager] Registered job #%d: %s" % [
			job.job_id, JobTypes.get_job_name(job.job_type)
		])


func unregister_job(job: JobNode) -> void:
	"""Unregister a JobNode"""
	if job in active_job_nodes:
		active_job_nodes.erase(job)


func enqueue_build_with_prerequisites(
	position: Vector3,
	building_type: int,
	rotation: float = 0.0,
	footprint_size: Vector2 = Vector2(4.0, 4.0)
) -> JobNode:
	"""Create a build job with automatic prerequisite chain (Clear -> Flatten -> Build)"""
	var job_mgr := get_node_or_null("/root/JobManager")
	if not job_mgr:
		push_error("[ConstructionManager] JobManager not found")
		return null

	var job: JobNode = job_mgr.enqueue_build_with_prerequisites(
		position, building_type, rotation, footprint_size
	)

	if job:
		register_job(job)

		# Also register prerequisites
		for prereq in job.prerequisites:
			if is_instance_valid(prereq):
				register_job(prereq)
				# And nested prereqs
				for nested in prereq.prerequisites:
					if is_instance_valid(nested):
						register_job(nested)

	return job


func get_active_job_count() -> int:
	"""Get number of active job nodes"""
	var count := 0
	for job in active_job_nodes:
		if is_instance_valid(job):
			count += 1
	return count


func _on_job_node_completed(job: JobNode) -> void:
	"""Handle job completion"""
	unregister_job(job)
	print("[ConstructionManager] Job #%d completed" % job.job_id)


func _on_job_node_cancelled(job: JobNode) -> void:
	"""Handle job cancellation"""
	unregister_job(job)


## =============================================================================
## AUTO-BUILD SYSTEM
## =============================================================================

func _on_construction_started(_firebase: Node3D, zone: Node3D) -> void:
	"""Handle construction start - auto-assign idle engineers"""
	if not auto_assign_enabled:
		return

	if not zone is ConstructionZone:
		return

	var construction_zone: ConstructionZone = zone as ConstructionZone

	# Find idle engineers near the construction site
	var idle_engineers: Array[Node3D] = _find_idle_engineers(construction_zone.global_position)

	if idle_engineers.is_empty():
		return

	# Limit to max engineers per zone
	var to_assign: int = mini(idle_engineers.size(), max_engineers_per_zone)

	print("[ConstructionManager] Auto-assigning %d engineers to %s" % [
		to_assign,
		construction_zone.building_data.display_name if construction_zone.building_data else "construction"
	])

	for i in to_assign:
		var engineer: Node3D = idle_engineers[i]
		_assign_engineer_to_zone(engineer, construction_zone)


func _find_idle_engineers(position: Vector3) -> Array[Node3D]:
	"""Find player-controlled idle engineer units near position"""
	var result: Array[Node3D] = []

	# Use SpatialHashGrid for efficient lookup
	var grid: Node = get_node_or_null("/root/SpatialHashGrid")
	if not grid:
		# Fallback to group search
		return _find_idle_engineers_fallback(position)

	# Get all units in radius
	var units: Array[Node3D] = grid.get_units_in_radius(position, auto_assign_radius)

	for unit in units:
		if not is_instance_valid(unit):
			continue

		# Check if it's player controlled
		if unit.has_method("get") and unit.get("is_player_controlled") != null:
			if not unit.is_player_controlled:
				continue
		else:
			continue

		# Check if it's an engineer (can_build)
		if unit.has_method("can_clear") and unit.can_clear():
			# Check if idle (not moving, not in combat, not clearing)
			if unit.has_method("get") and unit.get("state") != null:
				var state = unit.state
				# State.IDLE = 0 in Squad
				if state == 0:
					result.append(unit)

	# Sort by distance
	result.sort_custom(func(a, b):
		return position.distance_squared_to(a.global_position) < position.distance_squared_to(b.global_position)
	)

	return result


func _find_idle_engineers_fallback(position: Vector3) -> Array[Node3D]:
	"""Fallback method when SpatialHashGrid not available"""
	var result: Array[Node3D] = []
	var engineers: Array[Node] = get_tree().get_nodes_in_group("player_units")

	for unit in engineers:
		if not is_instance_valid(unit) or not unit is Node3D:
			continue

		var unit_3d: Node3D = unit as Node3D

		# Check distance
		if position.distance_to(unit_3d.global_position) > auto_assign_radius:
			continue

		# Check if it's an engineer
		if unit_3d.has_method("can_clear") and unit_3d.can_clear():
			# Check if idle
			if unit_3d.has_method("get") and unit_3d.get("state") != null:
				var state = unit_3d.state
				if state == 0:  # IDLE
					result.append(unit_3d)

	# Sort by distance
	result.sort_custom(func(a, b):
		return position.distance_squared_to(a.global_position) < position.distance_squared_to(b.global_position)
	)

	return result


func _assign_engineer_to_zone(engineer: Node3D, zone: ConstructionZone) -> void:
	"""Send engineer to construction zone and assign them"""
	# Move engineer to zone
	if engineer.has_method("move_to"):
		engineer.move_to(zone.global_position)

	# Assign to zone
	zone.assign_engineer(engineer)

	# Set up arrival callback (when engineer reaches zone)
	if engineer.has_signal("arrived_at_destination"):
		engineer.arrived_at_destination.connect(
			func(): _on_engineer_arrived(engineer, zone),
			CONNECT_ONE_SHOT
		)


func _on_engineer_arrived(engineer: Node3D, zone: ConstructionZone) -> void:
	"""Called when engineer arrives at construction zone"""
	# Ensure engineer is still assigned to this zone
	if engineer in zone.assigned_engineers:
		print("[ConstructionManager] Engineer %s arrived at construction site" % engineer.name)


func create_firebase_at(position: Vector3, fb_name: String = "Firebase") -> Node3D:
	"""Create a new firebase at position"""
	# Check if terrain is cleared
	var clearing_system: Node = get_node_or_null("/root/TerrainClearingSystem")
	if clearing_system and not clearing_system.is_cleared(position):
		print("[ConstructionManager] Cannot create firebase - terrain not cleared")
		return null

	var firebase := Firebase.new()
	firebase.name = fb_name
	firebase.firebase_name = fb_name
	firebase.position = position

	get_tree().current_scene.add_child(firebase)

	print("[ConstructionManager] Created firebase '%s' at %s" % [fb_name, position])
	return firebase
