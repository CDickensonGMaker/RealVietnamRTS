extends Node
## BuilderAI autoload - Automatically manages engineers and bulldozers
## Reduces micromanagement by auto-assigning work

signal work_assigned(unit: Node3D, task: Dictionary)
signal work_completed(unit: Node3D, task: Dictionary)
signal firebase_construction_started(position: Vector3)

const ConstructionZone = preload("res://firebase_system/construction_zone.gd")
const Firebase = preload("res://firebase_system/firebase.gd")
const JobTypes = preload("res://firebase_system/jobs/job_types.gd")
const JobNode = preload("res://firebase_system/jobs/job_node.gd")

enum TaskType { IDLE, CLEARING, BUILDING, MOVING, WORKING_JOB }
enum UnitType { ENGINEER, BULLDOZER }

## Registered builder units
var engineers: Array[Node3D] = []
var bulldozers: Array[Node3D] = []

## Task assignments (unit -> task dict)
var unit_tasks: Dictionary = {}

## Pending work
var pending_clearing_sites: Array[Vector3] = []
var pending_firebase_sites: Array[Dictionary] = []  # {position, name}

## Configuration
@export var auto_assign_interval: float = 0.5
@export var engineer_speed: float = 8.0
@export var bulldozer_speed: float = 5.0

## Clearing rates (balanced for 3.5 sec/tree for engineer, 7 sec/tree for bulldozer)
## Tree clearing work units: 1.0 per tree, engineers clear at 0.286/sec (1/3.5)
## Bulldozers clear at 0.143/sec (1/7), which is HALF the engineer rate
@export var engineer_work_rate: float = 0.286  # 1 tree / 3.5 seconds = 0.286 work/sec
@export var bulldozer_clear_rate: float = 0.143  # 1 tree / 7 seconds = 0.143 work/sec (half engineer speed)

## Auto-build mode toggle - when false, only responds to explicit requests
## Default TRUE for auto-battler style gameplay
var auto_mode_enabled: bool = true

var _assign_timer: float = 0.0

# Cached autoload references
var _terrain_system: Node = null
var _construction_mgr: Node = null


func _ready() -> void:
	# Cache autoload references
	_terrain_system = get_node_or_null("/root/_terrain_system")
	_construction_mgr = get_node_or_null("/root/_construction_mgr")

	# Connect to JobManager for auto-assignment when jobs are created
	var job_mgr = get_node_or_null("/root/JobManager")
	if job_mgr and job_mgr.has_signal("job_created"):
		job_mgr.job_created.connect(_on_job_created)
		print("[BuilderAI] Connected to JobManager for auto-assignment")

	print("[BuilderAI] Initialized - Auto-assignment enabled")


func _process(delta: float) -> void:
	# Always update existing tasks
	_update_unit_tasks(delta)

	# Only auto-assign new work if enabled
	if not auto_mode_enabled:
		return

	_assign_timer += delta
	if _assign_timer >= auto_assign_interval:
		_assign_timer = 0.0
		_auto_assign_work()


func _auto_assign_work() -> void:
	"""Automatically assign idle units to available work"""
	# Get idle units
	var idle_engineers: Array[Node3D] = []
	var idle_bulldozers: Array[Node3D] = []

	for eng in engineers:
		if _is_unit_idle(eng):
			idle_engineers.append(eng)

	for bull in bulldozers:
		if _is_unit_idle(bull):
			idle_bulldozers.append(bull)

	# Exit early if no idle workers
	if idle_engineers.is_empty() and idle_bulldozers.is_empty():
		return

	# Priority 1: Assign to JobManager jobs that need workers
	_assign_workers_to_pending_jobs(idle_engineers, idle_bulldozers)

	# Priority 2: Assign bulldozers to clearing sites (legacy API)
	for site_pos in pending_clearing_sites.duplicate():
		if idle_bulldozers.is_empty() and idle_engineers.is_empty():
			break

		# Check if already being cleared
		if _is_site_being_worked(site_pos):
			continue

		# Prefer bulldozers for clearing
		if not idle_bulldozers.is_empty():
			var bulldozer: Node3D = _get_closest_unit(idle_bulldozers, site_pos)
			_assign_clearing_task(bulldozer, site_pos, UnitType.BULLDOZER)
			idle_bulldozers.erase(bulldozer)
		elif not idle_engineers.is_empty():
			var engineer: Node3D = _get_closest_unit(idle_engineers, site_pos)
			_assign_clearing_task(engineer, site_pos, UnitType.ENGINEER)
			idle_engineers.erase(engineer)

	# Priority 3: Assign engineers to construction zones
	var active_zones: Array[ConstructionZone] = _get_active_construction_zones()
	for zone in active_zones:
		if idle_engineers.is_empty():
			break

		# Check how many engineers already assigned
		var assigned_count: int = _count_units_at_zone(zone)
		if assigned_count >= 3:  # Max 3 engineers per zone
			continue

		var engineer: Node3D = _get_closest_unit(idle_engineers, zone.global_position)
		_assign_building_task(engineer, zone)
		idle_engineers.erase(engineer)

	# Priority 4: Start new firebase if we have pending sites and cleared terrain
	for site_data in pending_firebase_sites.duplicate():
		var pos: Vector3 = site_data["position"]
		if _terrain_system and _terrain_system.is_cleared(pos):
			_create_firebase_at_site(site_data)
			pending_firebase_sites.erase(site_data)


func _assign_workers_to_pending_jobs(idle_engineers: Array[Node3D], idle_bulldozers: Array[Node3D]) -> void:
	"""Scan JobManager for jobs that need workers and assign idle units"""
	var job_mgr = get_node_or_null("/root/JobManager")
	if not job_mgr:
		return

	# Use JobManager's get_jobs_needing_workers if available
	var jobs_needing_workers: Array = []
	if job_mgr.has_method("get_jobs_needing_workers"):
		jobs_needing_workers = job_mgr.get_jobs_needing_workers()
	else:
		# Fallback: get jobs from scene tree
		for job in get_tree().get_nodes_in_group("construction_jobs"):
			if is_instance_valid(job) and job is JobNode:
				if job.can_be_worked() and job.assigned_workers.size() < job.max_workers:
					jobs_needing_workers.append(job)

	# Assign workers to jobs that need them
	for job in jobs_needing_workers:
		if idle_engineers.is_empty() and idle_bulldozers.is_empty():
			break

		# Determine best worker type for this job
		var job_type: JobTypes.JobType = job.job_type
		var prefer_bulldozer: bool = job_type in [
			JobTypes.JobType.FLATTEN_AREA,
			JobTypes.JobType.FILL_CRATER
		]

		var job_pos: Vector3 = job.get_centroid()
		var best_worker: Node3D = null

		if prefer_bulldozer:
			best_worker = _find_nearest_idle_worker(idle_bulldozers, job_pos, job_type)
			if best_worker:
				idle_bulldozers.erase(best_worker)
			else:
				best_worker = _find_nearest_idle_worker(idle_engineers, job_pos, job_type)
				if best_worker:
					idle_engineers.erase(best_worker)
		else:
			best_worker = _find_nearest_idle_worker(idle_engineers, job_pos, job_type)
			if best_worker:
				idle_engineers.erase(best_worker)
			else:
				best_worker = _find_nearest_idle_worker(idle_bulldozers, job_pos, job_type)
				if best_worker:
					idle_bulldozers.erase(best_worker)

		if best_worker:
			assign_to_job(best_worker, job)
			print("[BuilderAI] Auto-assigned %s to %s job #%d (periodic scan)" % [
				best_worker.name, JobTypes.get_job_name(job_type), job.job_id
			])


func _update_unit_tasks(delta: float) -> void:
	"""Update all unit task progress"""
	for unit in unit_tasks.keys():
		if not is_instance_valid(unit):
			unit_tasks.erase(unit)
			continue

		var task: Dictionary = unit_tasks[unit]
		_process_unit_task(unit, task, delta)


func _process_unit_task(unit: Node3D, task: Dictionary, delta: float) -> void:
	"""Process a single unit's current task"""
	var task_type: TaskType = task.get("type", TaskType.IDLE)

	match task_type:
		TaskType.MOVING:
			_process_movement(unit, task, delta)

		TaskType.CLEARING:
			_process_clearing(unit, task, delta)

		TaskType.BUILDING:
			_process_building(unit, task, delta)

		TaskType.WORKING_JOB:
			_process_job_work(unit, task, delta)


func _process_movement(unit: Node3D, task: Dictionary, delta: float) -> void:
	"""Move unit toward target"""
	var target: Vector3 = task.get("target", unit.global_position)
	var speed: float = task.get("speed", engineer_speed)
	var unit_type: UnitType = task.get("unit_type", UnitType.ENGINEER)

	var direction: Vector3 = (target - unit.global_position)
	direction.y = 0
	var distance: float = direction.length()

	if distance < 1.0:
		# Check if we have more waypoints to follow
		var waypoints: Variant = task.get("waypoints")
		var waypoint_idx: int = task.get("waypoint_index", 0)

		if waypoints != null and waypoints is PackedVector3Array:
			var wp_array: PackedVector3Array = waypoints as PackedVector3Array
			if waypoint_idx < wp_array.size() - 1:
				# More waypoints - go to next
				waypoint_idx += 1
				task["waypoint_index"] = waypoint_idx
				task["target"] = wp_array[waypoint_idx]
				return

		# Arrived at final destination or no waypoints - switch to actual work
		var next_type: TaskType = task.get("next_task", TaskType.IDLE)
		task["type"] = next_type

		# Check if we were doing path clearing and have an original target
		var original_target: Variant = task.get("original_target")
		if original_target != null and original_target is Vector3:
			var orig: Vector3 = original_target as Vector3
			if unit.global_position.distance_to(orig) > 2.0:
				# Still need to reach original target - continue moving
				task["type"] = TaskType.MOVING
				task["target"] = orig
				task.erase("original_target")
		return

	direction = direction.normalized()

	# Check for obstacles in path (both bulldozers AND engineers auto-clear)
	var blocked_pos: Vector3 = _check_path_blocked(unit.global_position, direction)
	if blocked_pos != Vector3.INF:
		# Vegetation in the way - create a small clearing job
		if _create_path_clearing_job(unit, blocked_pos, unit_type):
			# Update target to blocked position for now
			if not task.has("original_target"):
				task["original_target"] = target
			task["target"] = blocked_pos
			return

	unit.global_position += direction * speed * delta

	# Snap to terrain height (prevents Y-drift on uneven terrain)
	_snap_unit_to_terrain(unit)

	# Face movement direction
	if direction.length() > 0.1:
		unit.look_at(unit.global_position + direction, Vector3.UP)


func _process_clearing(unit: Node3D, task: Dictionary, delta: float) -> void:
	"""Process terrain clearing work"""
	var site_pos: Vector3 = task.get("site_position", Vector3.ZERO)
	var unit_type: UnitType = task.get("unit_type", UnitType.ENGINEER)

	# Get or create clearing operation
	var clearing_op = null
	if _terrain_system:
		clearing_op = _terrain_system.get_active_clearing_at(site_pos)
		if not clearing_op:
			clearing_op = _terrain_system.start_clearing(site_pos, 15.0)

	if clearing_op:
		# Add work based on unit type
		var work_rate: float = bulldozer_clear_rate if unit_type == UnitType.BULLDOZER else engineer_work_rate
		clearing_op.work_done += work_rate * delta

		# Check if complete
		if _terrain_system and _terrain_system.is_cleared(site_pos):
			_complete_task(unit, task)
			pending_clearing_sites.erase(site_pos)


func _process_building(unit: Node3D, task: Dictionary, delta: float) -> void:
	"""Process construction work"""
	var zone: ConstructionZone = task.get("zone")

	if not is_instance_valid(zone):
		_complete_task(unit, task)
		return

	if zone.is_complete():
		_complete_task(unit, task)
		return

	if zone.is_building():
		zone.add_work(engineer_work_rate * delta)


func _process_job_work(unit: Node3D, task: Dictionary, delta: float) -> void:
	"""Process JobNode work"""
	var job: JobNode = task.get("job")

	if not is_instance_valid(job):
		_complete_task(unit, task)
		return

	# Check if job is complete or cancelled
	if job.completion_state == JobTypes.CompletionState.COMPLETE:
		_complete_task(unit, task)
		return

	if job.completion_state == JobTypes.CompletionState.CANCELLED:
		_complete_task(unit, task)
		return

	# Check if job can be worked (prerequisites met)
	if not is_job_ready_for_work(job, unit):
		return  # Keep waiting

	# Check if worker is in range
	if not job.is_worker_in_range(unit):
		return  # Still walking

	# Worker is in range and job is ready - add work
	var unit_type: UnitType = task.get("unit_type", UnitType.ENGINEER)
	var work_rate: float = bulldozer_clear_rate if unit_type == UnitType.BULLDOZER else engineer_work_rate

	# Apply rate multiplier based on worker class and job type
	var worker_class: String = JobTypes.WORKER_BULLDOZER if unit_type == UnitType.BULLDOZER else JobTypes.WORKER_ENGINEER
	var multiplier: float = JobTypes.get_work_rate_multiplier(worker_class, job.job_type)

	job.add_work(work_rate * multiplier * delta)


func _complete_task(unit: Node3D, task: Dictionary) -> void:
	"""Mark task as complete and set unit to idle"""
	work_completed.emit(unit, task)
	unit_tasks[unit] = {"type": TaskType.IDLE}


func _is_unit_idle(unit: Node3D) -> bool:
	"""Check if unit has no active task"""
	if unit not in unit_tasks:
		return true
	return unit_tasks[unit].get("type", TaskType.IDLE) == TaskType.IDLE


func _is_site_being_worked(position: Vector3) -> bool:
	"""Check if a clearing site already has workers"""
	for unit in unit_tasks.keys():
		var task: Dictionary = unit_tasks[unit]
		if task.get("type") == TaskType.CLEARING:
			var site_pos: Vector3 = task.get("site_position", Vector3.ZERO)
			if position.distance_to(site_pos) < 5.0:
				return true
	return false


func _count_units_at_zone(zone: ConstructionZone) -> int:
	"""Count units assigned to a construction zone"""
	var count: int = 0
	for unit in unit_tasks.keys():
		var task: Dictionary = unit_tasks[unit]
		if task.get("type") == TaskType.BUILDING:
			if task.get("zone") == zone:
				count += 1
	return count


func _get_closest_unit(units: Array[Node3D], target: Vector3) -> Node3D:
	"""Get the closest unit to a target position"""
	var closest: Node3D = null
	var closest_dist: float = INF

	for unit in units:
		var dist: float = unit.global_position.distance_to(target)
		if dist < closest_dist:
			closest_dist = dist
			closest = unit

	return closest


func _get_active_construction_zones() -> Array[ConstructionZone]:
	"""Get all zones currently under construction"""
	var zones: Array[ConstructionZone] = []

	for firebase in get_tree().get_nodes_in_group("firebases"):
		if firebase is Firebase:
			for zone in firebase.construction_zones:
				if zone.is_building():
					zones.append(zone)

	return zones


func _assign_clearing_task(unit: Node3D, site_pos: Vector3, unit_type: UnitType) -> void:
	"""Assign a terrain clearing task to a unit"""
	var speed: float = bulldozer_speed if unit_type == UnitType.BULLDOZER else engineer_speed

	unit_tasks[unit] = {
		"type": TaskType.MOVING,
		"target": site_pos,
		"speed": speed,
		"next_task": TaskType.CLEARING,
		"site_position": site_pos,
		"unit_type": unit_type
	}

	work_assigned.emit(unit, unit_tasks[unit])
	print("[BuilderAI] Assigned %s to clear terrain at %s" % [
		"bulldozer" if unit_type == UnitType.BULLDOZER else "engineer",
		site_pos
	])


func _assign_building_task(unit: Node3D, zone: ConstructionZone) -> void:
	"""Assign a construction task to an engineer"""
	unit_tasks[unit] = {
		"type": TaskType.MOVING,
		"target": zone.global_position,
		"speed": engineer_speed,
		"next_task": TaskType.BUILDING,
		"zone": zone
	}

	work_assigned.emit(unit, unit_tasks[unit])
	print("[BuilderAI] Assigned engineer to build at %s" % zone.global_position)


func _create_firebase_at_site(site_data: Dictionary) -> void:
	"""Create a firebase at a cleared site"""
	var pos: Vector3 = site_data["position"]
	var fb_name: String = site_data.get("name", "Firebase")

	if _construction_mgr:
		var firebase: Node3D = _construction_mgr.create_firebase_at(pos, fb_name)
		if firebase:
			firebase_construction_started.emit(pos)
			print("[BuilderAI] Created firebase '%s' at %s" % [fb_name, pos])


## Public API

func register_engineer(unit: Node3D) -> void:
	"""Register an engineer unit for auto-management"""
	if unit not in engineers:
		engineers.append(unit)
		unit_tasks[unit] = {"type": TaskType.IDLE}
		print("[BuilderAI] Registered engineer: %s" % unit.name)


func register_bulldozer(unit: Node3D) -> void:
	"""Register a bulldozer unit for auto-management"""
	if unit not in bulldozers:
		bulldozers.append(unit)
		unit_tasks[unit] = {"type": TaskType.IDLE}
		print("[BuilderAI] Registered bulldozer: %s" % unit.name)


func unregister_unit(unit: Node3D) -> void:
	"""Remove a unit from management"""
	engineers.erase(unit)
	bulldozers.erase(unit)
	unit_tasks.erase(unit)


func request_clearing(position: Vector3) -> void:
	"""Request terrain clearing at a position"""
	if position not in pending_clearing_sites:
		pending_clearing_sites.append(position)
		print("[BuilderAI] Clearing requested at %s" % position)


func request_firebase(position: Vector3, fb_name: String = "Firebase") -> void:
	"""Request a new firebase at a position (will clear terrain first if needed)"""
	# Add to pending sites
	pending_firebase_sites.append({"position": position, "name": fb_name})

	# Also request clearing if not already cleared
	if _terrain_system and not _terrain_system.is_cleared(position):
		request_clearing(position)

	print("[BuilderAI] Firebase '%s' requested at %s" % [fb_name, position])


func request_building(firebase: Node3D, building_type: int) -> bool:
	"""Request a building at a firebase (engineers will auto-assign)"""
	if firebase is Firebase:
		return firebase.start_building(building_type)
	return false


func get_unit_task(unit: Node3D) -> Dictionary:
	"""Get current task for a unit"""
	return unit_tasks.get(unit, {"type": TaskType.IDLE})


func get_idle_count() -> Dictionary:
	"""Get count of idle units by type"""
	var idle_eng: int = 0
	var idle_bull: int = 0

	for eng in engineers:
		if _is_unit_idle(eng):
			idle_eng += 1

	for bull in bulldozers:
		if _is_unit_idle(bull):
			idle_bull += 1

	return {"engineers": idle_eng, "bulldozers": idle_bull}


## =============================================================================
## JOB NODE INTEGRATION
## =============================================================================

func _on_job_created(job: JobNode) -> void:
	"""Auto-assign nearest available worker when a job is created"""
	if not is_instance_valid(job):
		return

	# Connect to prerequisite_resolved to auto-assign when job becomes workable
	if not job.prerequisite_resolved.is_connected(_on_job_prerequisite_resolved):
		job.prerequisite_resolved.connect(_on_job_prerequisite_resolved.bind(job))

	# Don't auto-assign if job already has workers
	if job.assigned_workers.size() > 0:
		return

	# Don't auto-assign if job can't be worked yet (prerequisites not met)
	if not job.can_be_worked():
		print("[BuilderAI] Job #%d (%s) waiting for prerequisites" % [
			job.job_id, JobTypes.get_job_name(job.job_type)
		])
		return

	_auto_assign_worker_to_job(job)


func _on_job_prerequisite_resolved(_prereq: JobNode, job: JobNode) -> void:
	"""Called when a job's prerequisite completes - check if job is now workable"""
	if not is_instance_valid(job):
		return

	# Check if all prerequisites are now complete
	if not job.can_be_worked():
		return  # Still waiting for other prereqs

	# Don't auto-assign if job already has workers
	if job.assigned_workers.size() > 0:
		return

	print("[BuilderAI] Job #%d (%s) prerequisites complete - auto-assigning worker" % [
		job.job_id, JobTypes.get_job_name(job.job_type)
	])
	_auto_assign_worker_to_job(job)


func _auto_assign_worker_to_job(job: JobNode) -> void:
	"""Find and assign the best available worker to a job"""
	# Determine which worker type is best for this job
	var job_type: JobTypes.JobType = job.job_type
	var prefer_bulldozer: bool = job_type in [
		JobTypes.JobType.FLATTEN_AREA,
		JobTypes.JobType.BUILD_ROAD
	]

	# Find best available worker
	var best_worker: Node3D = null
	var job_pos: Vector3 = job.get_centroid()

	if prefer_bulldozer:
		# Try bulldozers first, then engineers
		best_worker = _find_nearest_idle_worker(bulldozers, job_pos, job_type)
		if not best_worker:
			best_worker = _find_nearest_idle_worker(engineers, job_pos, job_type)
	else:
		# Try engineers first, then bulldozers
		best_worker = _find_nearest_idle_worker(engineers, job_pos, job_type)
		if not best_worker:
			best_worker = _find_nearest_idle_worker(bulldozers, job_pos, job_type)

	if best_worker:
		assign_to_job(best_worker, job)
		print("[BuilderAI] Auto-assigned %s to %s job #%d" % [
			best_worker.name, JobTypes.get_job_name(job_type), job.job_id
		])
	else:
		print("[BuilderAI] No idle workers for %s job #%d - will assign when available" % [
			JobTypes.get_job_name(job_type), job.job_id
		])


func _find_nearest_idle_worker(workers: Array[Node3D], target_pos: Vector3, job_type: JobTypes.JobType) -> Node3D:
	"""Find nearest idle worker that can do this job type"""
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for worker in workers:
		if not is_instance_valid(worker):
			continue
		if not _is_unit_idle(worker):
			continue

		# Check if worker can do this job type
		var unit_type: UnitType = UnitType.BULLDOZER if worker in bulldozers else UnitType.ENGINEER
		var worker_class: String = JobTypes.WORKER_BULLDOZER if unit_type == UnitType.BULLDOZER else JobTypes.WORKER_ENGINEER

		if not JobTypes.can_worker_do_job(worker_class, job_type):
			continue

		var dist: float = worker.global_position.distance_to(target_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = worker

	return nearest


func walk_to_job(worker: Node3D, job: JobNode) -> void:
	"""Send a worker to walk to a JobNode's work position (nearest edge for area jobs)"""
	if not is_instance_valid(worker) or not is_instance_valid(job):
		return

	# Determine worker type
	var unit_type: UnitType = UnitType.ENGINEER
	if worker in bulldozers:
		unit_type = UnitType.BULLDOZER

	var speed: float = bulldozer_speed if unit_type == UnitType.BULLDOZER else engineer_speed

	# Assign worker to job
	job.assign_worker(worker)

	# Get work position (nearest edge for area jobs, centroid for point jobs)
	var work_position: Vector3 = job.get_work_position(worker)

	# Create task
	unit_tasks[worker] = {
		"type": TaskType.MOVING,
		"target": work_position,
		"speed": speed,
		"next_task": TaskType.WORKING_JOB,
		"job": job,
		"unit_type": unit_type
	}

	work_assigned.emit(worker, unit_tasks[worker])
	print("[BuilderAI] %s walking to job #%d work position %s (edge-based)" % [
		"Bulldozer" if unit_type == UnitType.BULLDOZER else "Engineer",
		job.job_id,
		work_position
	])


func is_job_ready_for_work(job: JobNode, worker: Node3D = null) -> bool:
	"""Check if a job can be worked on (prerequisites met, worker in range)"""
	if not is_instance_valid(job):
		return false

	# Check if job can be worked at all
	if not job.can_be_worked():
		return false

	# If worker specified, check if they're in range
	if worker and is_instance_valid(worker):
		if not job.is_worker_in_range(worker):
			return false

	return true


func assign_to_job(worker: Node3D, job: JobNode) -> bool:
	"""Assign a worker to a job (will walk there and begin work)"""
	if not is_instance_valid(worker) or not is_instance_valid(job):
		return false

	# Check if worker can do this job type
	var unit_type: UnitType = UnitType.ENGINEER
	if worker in bulldozers:
		unit_type = UnitType.BULLDOZER

	var worker_class: String = JobTypes.WORKER_BULLDOZER if unit_type == UnitType.BULLDOZER else JobTypes.WORKER_ENGINEER

	if not JobTypes.can_worker_do_job(worker_class, job.job_type):
		print("[BuilderAI] %s cannot work on %s job" % [
			worker_class, JobTypes.get_job_name(job.job_type)
		])
		return false

	# Check if job has room for more workers
	if job.assigned_workers.size() >= job.max_workers:
		return false

	walk_to_job(worker, job)
	return true


func get_workers_on_job(job: JobNode) -> Array[Node3D]:
	"""Get all workers currently assigned to a job"""
	var result: Array[Node3D] = []

	for worker in unit_tasks.keys():
		var task: Dictionary = unit_tasks[worker]
		if task.get("job") == job:
			result.append(worker)

	return result


func cancel_job_assignments(job: JobNode) -> void:
	"""Cancel all worker assignments for a job"""
	for worker in unit_tasks.keys():
		var task: Dictionary = unit_tasks[worker]
		if task.get("job") == job:
			_complete_task(worker, task)


## =============================================================================
## TERRAIN SNAPPING
## =============================================================================

func _snap_unit_to_terrain(unit: Node3D) -> void:
	"""Snap a unit's Y position to the terrain height at their current XZ position"""
	if not is_instance_valid(unit):
		return

	# Try TerrainIntegration autoload first (has get_height_at method)
	var terrain: Node = get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		var height: float = terrain.get_height_at(unit.global_position)
		if height != 0.0 or unit.global_position.y != 0.0:  # Avoid snapping to 0 if terrain not loaded
			unit.global_position.y = height
		return

	# Fallback: Try terrain_manager directly
	if terrain and terrain.has_method("get") and terrain.get("terrain_manager"):
		var tm: Node = terrain.terrain_manager
		if tm and tm.has_method("get") and tm.get("heightmap"):
			var heightmap = tm.heightmap
			if heightmap and heightmap.has_method("sample_world"):
				var height: float = heightmap.sample_world(unit.global_position.x, unit.global_position.z)
				unit.global_position.y = height
				return

	# Final fallback: Try local terrain in test scenes
	var local_terrain: Node = get_tree().current_scene.get_node_or_null("LocalTerrain")
	if local_terrain and local_terrain.has_method("get") and local_terrain.get("heightmap"):
		var heightmap = local_terrain.heightmap
		if heightmap and heightmap.has_method("sample_world"):
			var height: float = heightmap.sample_world(unit.global_position.x, unit.global_position.z)
			unit.global_position.y = height


## =============================================================================
## BULLDOZER AUTO-PATH CLEARING
## =============================================================================

func _check_path_blocked(from_pos: Vector3, direction: Vector3) -> Vector3:
	"""Check if vegetation is blocking the path ahead. Returns blocked position or Vector3.INF"""
	var terrain_system = get_node_or_null("/root/TerrainIntegration")
	if not terrain_system:
		return Vector3.INF

	# Check points ahead along the path
	var check_distances: Array[float] = [3.0, 6.0, 9.0]  # Check 3m, 6m, 9m ahead

	for dist in check_distances:
		var check_pos: Vector3 = from_pos + direction * dist

		# Check vegetation density at this point
		if terrain_system.has_method("get_vegetation_density"):
			var density: float = terrain_system.get_vegetation_density(check_pos)
			if density > 0.3:  # Blocked by vegetation
				return check_pos

		# Also check clearing state
		var clearing_system = get_node_or_null("/root/TerrainClearingSystem")
		if clearing_system and clearing_system.has_method("is_cleared"):
			if not clearing_system.is_cleared(check_pos):
				# Not cleared - check if there's actually vegetation here
				if terrain_system.has_method("get_vegetation_density"):
					var density: float = terrain_system.get_vegetation_density(check_pos)
					if density > 0.2:
						return check_pos

	return Vector3.INF


func _create_path_clearing_job(unit: Node3D, blocked_pos: Vector3, unit_type: UnitType = UnitType.ENGINEER) -> bool:
	"""Create a small clearing job at the blocked position"""
	var job_mgr = get_node_or_null("/root/JobManager")
	if not job_mgr:
		return false

	# Calculate clearing size based on unit type
	# Bulldozer: 6x6m wide path
	# Engineer: 4x4m (smaller det-cord burst)
	var clear_size: float = 6.0 if unit_type == UnitType.BULLDOZER else 4.0
	var half_size: float = clear_size * 0.5

	# Check if there's already a clearing job at this location
	if job_mgr.has_method("get_jobs_in_area"):
		var check_bounds := AABB(
			blocked_pos - Vector3(half_size, 0, half_size),
			Vector3(clear_size, 1, clear_size)
		)
		var existing_jobs: Array = job_mgr.get_jobs_in_area(check_bounds)
		for job in existing_jobs:
			if is_instance_valid(job) and job.job_type == JobTypes.JobType.CLEAR_TERRAIN:
				# Already have a clearing job here - assign unit to it
				if job.assigned_workers.size() < job.max_workers:
					assign_to_job(unit, job)
				return true

	# Create a clearing job for the path
	if job_mgr.has_method("create_area_job"):
		var min_corner := Vector3(blocked_pos.x - half_size, 0, blocked_pos.z - half_size)
		var max_corner := Vector3(blocked_pos.x + half_size, 0, blocked_pos.z + half_size)

		var job: JobNode = job_mgr.create_area_job(
			JobTypes.JobType.CLEAR_TERRAIN,
			min_corner,
			max_corner,
			false  # Don't auto-resolve dependencies for path clearing
		)

		if is_instance_valid(job):
			# Mark as a path-clearing job in metadata
			job.metadata["is_path_clearing"] = true
			job.metadata["unit"] = unit
			job.metadata["unit_type"] = "bulldozer" if unit_type == UnitType.BULLDOZER else "engineer"

			# Assign the unit immediately
			assign_to_job(unit, job)

			var unit_name: String = "bulldozer" if unit_type == UnitType.BULLDOZER else "engineer"
			print("[BuilderAI] Created path-clearing job #%d at %s for %s %s" % [
				job.job_id, blocked_pos, unit_name, unit.name
			])
			return true

	return false


func get_bulldozer_for_path_clear(target_pos: Vector3) -> Node3D:
	"""Get the nearest idle bulldozer that could clear a path to target"""
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for bull in bulldozers:
		if _is_unit_idle(bull):
			var dist: float = bull.global_position.distance_to(target_pos)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = bull

	return nearest


func _find_shortest_path_through_vegetation(from_pos: Vector3, to_pos: Vector3) -> PackedVector3Array:
	"""Find the path with minimum vegetation to clear between two points.
	Returns array of waypoints. Uses A* with vegetation cost weighting."""

	var terrain_system = get_node_or_null("/root/TerrainIntegration")
	if not terrain_system or not terrain_system.has_method("get_vegetation_density"):
		# No vegetation system - return direct path
		return PackedVector3Array([from_pos, to_pos])

	# Grid-based pathfinding
	var grid_size: float = 5.0  # 5m grid
	var direct_dist: float = from_pos.distance_to(to_pos)

	# If close enough, go direct
	if direct_dist < grid_size * 2:
		return PackedVector3Array([from_pos, to_pos])

	# Sample vegetation along multiple potential routes
	var best_path: PackedVector3Array = PackedVector3Array()
	var best_cost: float = INF

	# Test direct path
	var direct_cost: float = _calculate_path_vegetation_cost(from_pos, to_pos, terrain_system)
	if direct_cost < INF:
		best_path = PackedVector3Array([from_pos, to_pos])
		best_cost = direct_cost

	# Test detour paths (offset perpendicular to direct line)
	var direction: Vector3 = (to_pos - from_pos).normalized()
	direction.y = 0
	var perp: Vector3 = Vector3(-direction.z, 0, direction.x)

	# Try offsets: small detours left/right
	var offsets: Array[float] = [-20.0, -10.0, 10.0, 20.0]  # meters

	for offset in offsets:
		# Create waypoint at midpoint with offset
		var mid_point: Vector3 = from_pos.lerp(to_pos, 0.5) + perp * offset

		# Calculate cost: from -> mid -> to
		var cost1: float = _calculate_path_vegetation_cost(from_pos, mid_point, terrain_system)
		var cost2: float = _calculate_path_vegetation_cost(mid_point, to_pos, terrain_system)
		var total_cost: float = cost1 + cost2

		# Add distance penalty (prefer shorter paths)
		var path_length: float = from_pos.distance_to(mid_point) + mid_point.distance_to(to_pos)
		total_cost += path_length * 0.1  # Small distance penalty

		if total_cost < best_cost:
			best_cost = total_cost
			best_path = PackedVector3Array([from_pos, mid_point, to_pos])

	return best_path


func _calculate_path_vegetation_cost(from_pos: Vector3, to_pos: Vector3, terrain_system: Node) -> float:
	"""Calculate total vegetation density along a path (higher = more to clear)"""
	var direction: Vector3 = to_pos - from_pos
	var distance: float = direction.length()
	if distance < 0.1:
		return 0.0

	direction = direction.normalized()

	var total_cost: float = 0.0
	var sample_spacing: float = 3.0  # Check every 3m
	var samples: int = int(distance / sample_spacing) + 1

	for i in range(samples):
		var t: float = float(i) / float(maxf(samples - 1, 1))
		var sample_pos: Vector3 = from_pos.lerp(to_pos, t)

		if terrain_system.has_method("get_vegetation_density"):
			var density: float = terrain_system.get_vegetation_density(sample_pos)
			total_cost += density

	return total_cost


func send_unit_to_target_with_optimal_path(unit: Node3D, target: Vector3, unit_type: UnitType = UnitType.ENGINEER) -> void:
	"""Send a unit to target using the shortest path through vegetation"""
	var path: PackedVector3Array = _find_shortest_path_through_vegetation(unit.global_position, target)

	if path.size() <= 2:
		# Direct path or no path found - just move normally
		var speed: float = bulldozer_speed if unit_type == UnitType.BULLDOZER else engineer_speed
		unit_tasks[unit] = {
			"type": TaskType.MOVING,
			"target": target,
			"speed": speed,
			"next_task": TaskType.IDLE,
			"unit_type": unit_type
		}
	else:
		# Multi-waypoint path - use first waypoint, store rest
		var speed: float = bulldozer_speed if unit_type == UnitType.BULLDOZER else engineer_speed
		var waypoints: PackedVector3Array = path.slice(1)  # Skip first (current pos)

		unit_tasks[unit] = {
			"type": TaskType.MOVING,
			"target": waypoints[0],
			"speed": speed,
			"next_task": TaskType.IDLE,
			"unit_type": unit_type,
			"waypoints": waypoints,
			"waypoint_index": 0,
			"final_target": target
		}

	print("[BuilderAI] %s %s sent to %s via %d waypoints" % [
		"Bulldozer" if unit_type == UnitType.BULLDOZER else "Engineer",
		unit.name,
		target,
		path.size()
	])
