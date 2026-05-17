class_name JobNode
extends Node3D
## JobNode - Persistent world node representing a construction job
##
## A JobNode is a visible marker in the 3D world representing pending or
## in-progress construction work. Engineers and bulldozers physically walk
## to the job and work on it over time.
##
## Jobs can have prerequisites (e.g., a BUILD_STRUCTURE job requires
## CLEAR_TERRAIN and FLATTEN_AREA to complete first).

const JobTypes = preload("res://firebase_system/jobs/job_types.gd")

## Signals
signal job_started()
signal job_progress_updated(progress: float)
signal job_completed(job: JobNode)
signal job_cancelled(job: JobNode)
signal prerequisite_resolved(prerequisite: JobNode)
signal worker_assigned(worker: Node3D)
signal worker_unassigned(worker: Node3D)

## Job type from JobTypes enum
@export var job_type: JobTypes.JobType = JobTypes.JobType.CLEAR_TERRAIN

## Area bounds for rect-area jobs (CLEAR_TERRAIN, FLATTEN_AREA)
@export var area_bounds: AABB = AABB()

## Path points for line jobs (BUILD_ROAD)
@export var path_points: PackedVector3Array = PackedVector3Array()

## Center position for point jobs (BUILD_STRUCTURE, FILL_CRATER)
@export var center_position: Vector3 = Vector3.ZERO

## Work tracking
@export var total_work: float = 100.0
@export var current_progress: float = 0.0

## Worker management
@export var max_workers: int = 4
var assigned_workers: Array[Node3D] = []

## Prerequisites - must all be complete before this job can be worked
var prerequisites: Array[JobNode] = []

## Jobs that are blocked by this job
var blocks: Array[JobNode] = []

## Completion state
var completion_state: JobTypes.CompletionState = JobTypes.CompletionState.PENDING

## Job-specific metadata (e.g., building_type, rotation for BUILD_STRUCTURE)
var metadata: Dictionary = {}

## Visual representation (managed by JobNodeVisual)
var visual: Node3D = null

## Unique job ID for tracking
var job_id: int = -1

## Work radius - workers must be within this distance to work
const WORK_RADIUS := 3.0


func _ready() -> void:
	# Add to jobs group for easy lookup
	add_to_group("construction_jobs")


func _exit_tree() -> void:
	# Clean up: unassign all workers
	for worker in assigned_workers.duplicate():
		unassign_worker(worker)

	# Remove from prerequisites' blocks lists
	for prereq in prerequisites:
		if is_instance_valid(prereq):
			prereq.blocks.erase(self)


## Add work to the job (called by builder_ai per tick)
func add_work(amount: float) -> void:
	if completion_state != JobTypes.CompletionState.IN_PROGRESS:
		return

	if not can_be_worked():
		return

	var old_progress: float = current_progress
	current_progress = minf(current_progress + amount, total_work)

	if current_progress != old_progress:
		job_progress_updated.emit(current_progress)

	# Check for completion
	if current_progress >= total_work:
		_complete()


## Assign a worker to this job
func assign_worker(worker: Node3D) -> bool:
	if not is_instance_valid(worker):
		return false

	if assigned_workers.size() >= max_workers:
		return false

	if worker in assigned_workers:
		return false

	assigned_workers.append(worker)
	worker_assigned.emit(worker)

	# Transition to IN_PROGRESS if this is the first worker
	if completion_state == JobTypes.CompletionState.PENDING:
		completion_state = JobTypes.CompletionState.IN_PROGRESS
		job_started.emit()

	return true


## Remove a worker from this job
func unassign_worker(worker: Node3D) -> void:
	if worker in assigned_workers:
		assigned_workers.erase(worker)
		worker_unassigned.emit(worker)


## Check if the job can be worked on
func can_be_worked() -> bool:
	# Already complete or cancelled
	if completion_state == JobTypes.CompletionState.COMPLETE:
		return false
	if completion_state == JobTypes.CompletionState.CANCELLED:
		return false

	# Check prerequisites
	for prereq in prerequisites:
		if is_instance_valid(prereq):
			if prereq.completion_state != JobTypes.CompletionState.COMPLETE:
				return false

	return true


## Get the centroid position for worker pathfinding
func get_centroid() -> Vector3:
	match job_type:
		JobTypes.JobType.CLEAR_TERRAIN, JobTypes.JobType.FLATTEN_AREA:
			return area_bounds.get_center()

		JobTypes.JobType.BUILD_ROAD:
			if path_points.size() > 0:
				# Return midpoint of path
				var total := Vector3.ZERO
				for pt in path_points:
					total += pt
				return total / float(path_points.size())
			return global_position

		JobTypes.JobType.BUILD_STRUCTURE, JobTypes.JobType.FILL_CRATER:
			return center_position

		_:
			return global_position


## Get the work position for a worker - returns nearest edge for area jobs
## This allows workers to work from the outside in, avoiding path blocking
func get_work_position(worker: Node3D) -> Vector3:
	if not is_instance_valid(worker):
		return get_centroid()

	var worker_pos: Vector3 = worker.global_position

	match job_type:
		JobTypes.JobType.CLEAR_TERRAIN, JobTypes.JobType.FLATTEN_AREA:
			# For area jobs, find the closest point on the boundary
			var min_pos: Vector3 = area_bounds.position
			var max_pos: Vector3 = area_bounds.position + area_bounds.size

			# Clamp worker position to area edges (find nearest edge point)
			var nearest_edge := Vector3.ZERO

			# If worker is outside the area, find nearest edge point
			var inside_x: bool = worker_pos.x >= min_pos.x and worker_pos.x <= max_pos.x
			var inside_z: bool = worker_pos.z >= min_pos.z and worker_pos.z <= max_pos.z

			if inside_x and inside_z:
				# Worker is inside area - they can work from their current position
				# Return a point just inside the area nearest to worker
				nearest_edge = Vector3(
					clampf(worker_pos.x, min_pos.x + WORK_RADIUS, max_pos.x - WORK_RADIUS),
					area_bounds.get_center().y,
					clampf(worker_pos.z, min_pos.z + WORK_RADIUS, max_pos.z - WORK_RADIUS)
				)
			else:
				# Worker is outside - find nearest point on perimeter
				nearest_edge.x = clampf(worker_pos.x, min_pos.x, max_pos.x)
				nearest_edge.z = clampf(worker_pos.z, min_pos.z, max_pos.z)
				nearest_edge.y = area_bounds.get_center().y

				# Move slightly inside the area (by WORK_RADIUS) so worker is "in range"
				var center: Vector3 = area_bounds.get_center()
				var to_center: Vector3 = (center - nearest_edge).normalized()
				to_center.y = 0
				if to_center.length() > 0.1:
					nearest_edge += to_center * minf(WORK_RADIUS * 0.5, area_bounds.size.x * 0.25)

			return nearest_edge

		JobTypes.JobType.BUILD_ROAD:
			# For roads, find nearest point on path
			if path_points.size() == 0:
				return global_position

			var nearest: Vector3 = path_points[0]
			var nearest_dist: float = worker_pos.distance_to(nearest)

			# Check each segment
			for i in range(path_points.size() - 1):
				var closest: Vector3 = _closest_point_on_segment(worker_pos, path_points[i], path_points[i + 1])
				var dist: float = worker_pos.distance_to(closest)
				if dist < nearest_dist:
					nearest_dist = dist
					nearest = closest

			return nearest

		JobTypes.JobType.BUILD_STRUCTURE, JobTypes.JobType.FILL_CRATER:
			# Point jobs - work position is the center
			return center_position

		_:
			return global_position


## Check if a position is within the job's work area
func is_position_in_area(pos: Vector3) -> bool:
	match job_type:
		JobTypes.JobType.CLEAR_TERRAIN, JobTypes.JobType.FLATTEN_AREA:
			# Check 2D bounds (ignore Y)
			var pos_2d := Vector2(pos.x, pos.z)
			var min_2d := Vector2(area_bounds.position.x, area_bounds.position.z)
			var max_2d := min_2d + Vector2(area_bounds.size.x, area_bounds.size.z)
			return pos_2d.x >= min_2d.x and pos_2d.x <= max_2d.x and \
				   pos_2d.y >= min_2d.y and pos_2d.y <= max_2d.y

		JobTypes.JobType.BUILD_ROAD:
			# Check distance to any path segment
			for i in range(path_points.size() - 1):
				var closest := _closest_point_on_segment(pos, path_points[i], path_points[i + 1])
				if pos.distance_to(closest) <= WORK_RADIUS * 2:
					return true
			return false

		JobTypes.JobType.BUILD_STRUCTURE, JobTypes.JobType.FILL_CRATER:
			return pos.distance_to(center_position) <= WORK_RADIUS * 2

		_:
			return pos.distance_to(global_position) <= WORK_RADIUS * 2


## Check if a worker is close enough to work
func is_worker_in_range(worker: Node3D) -> bool:
	if not is_instance_valid(worker):
		return false

	# For area jobs, worker is in range if they're inside the area OR close to any edge
	match job_type:
		JobTypes.JobType.CLEAR_TERRAIN, JobTypes.JobType.FLATTEN_AREA:
			# Check if worker is inside the area
			if is_position_in_area(worker.global_position):
				return true
			# Check if worker is close to the area boundary
			var work_pos: Vector3 = get_work_position(worker)
			return worker.global_position.distance_to(work_pos) <= WORK_RADIUS

		_:
			return worker.global_position.distance_to(get_centroid()) <= WORK_RADIUS


## Cancel the job
func cancel() -> void:
	if completion_state == JobTypes.CompletionState.COMPLETE:
		return

	completion_state = JobTypes.CompletionState.CANCELLED

	# Unassign all workers
	for worker in assigned_workers.duplicate():
		unassign_worker(worker)

	job_cancelled.emit(self)

	# Also cancel any jobs that depend on this one
	for blocked_job in blocks:
		if is_instance_valid(blocked_job):
			blocked_job.cancel()


## Get progress as a percentage (0-100)
func get_progress_percent() -> float:
	if total_work <= 0:
		return 0.0
	return (current_progress / total_work) * 100.0


## Get display status text
func get_status_text() -> String:
	if completion_state == JobTypes.CompletionState.CANCELLED:
		return "Cancelled"

	if completion_state == JobTypes.CompletionState.COMPLETE:
		return "Complete"

	if not can_be_worked():
		return "Waiting for prerequisites"

	if assigned_workers.is_empty():
		return "Waiting for workers"

	# Check if workers are still walking
	var any_in_range := false
	for worker in assigned_workers:
		if is_worker_in_range(worker):
			any_in_range = true
			break

	if not any_in_range:
		return "Workers en route"

	return JobTypes.get_stage_label(job_type, get_progress_percent())


## Get the area size in square meters (for area jobs)
func get_area_size() -> float:
	match job_type:
		JobTypes.JobType.CLEAR_TERRAIN, JobTypes.JobType.FLATTEN_AREA:
			return area_bounds.size.x * area_bounds.size.z

		JobTypes.JobType.BUILD_ROAD:
			var total_length := 0.0
			for i in range(path_points.size() - 1):
				total_length += path_points[i].distance_to(path_points[i + 1])
			return total_length

		_:
			return 1.0


## Add a prerequisite job
func add_prerequisite(prereq: JobNode) -> void:
	if prereq and prereq not in prerequisites:
		prerequisites.append(prereq)
		prereq.blocks.append(self)

		# Connect to prerequisite completion
		if not prereq.job_completed.is_connected(_on_prerequisite_completed):
			prereq.job_completed.connect(_on_prerequisite_completed)


## Internal: complete the job
func _complete() -> void:
	completion_state = JobTypes.CompletionState.COMPLETE
	job_completed.emit(self)

	# Notify blocked jobs that this prerequisite is done
	for blocked_job in blocks:
		if is_instance_valid(blocked_job):
			blocked_job.prerequisite_resolved.emit(self)


## Internal: handle prerequisite completion
func _on_prerequisite_completed(prereq: JobNode) -> void:
	prerequisite_resolved.emit(prereq)


## Utility: closest point on a line segment
func _closest_point_on_segment(point: Vector3, seg_a: Vector3, seg_b: Vector3) -> Vector3:
	var ab := seg_b - seg_a
	var ap := point - seg_a
	var t := clampf(ap.dot(ab) / ab.dot(ab), 0.0, 1.0)
	return seg_a + ab * t


## Create a job from parameters (factory helper)
static func create_area_job(
	p_job_type: JobTypes.JobType,
	bounds: AABB,
	work_override: float = -1.0
) -> JobNode:
	var job := JobNode.new()
	job.job_type = p_job_type
	job.area_bounds = bounds
	job.center_position = bounds.get_center()
	job.global_position = job.center_position

	var area_size: float = bounds.size.x * bounds.size.z
	job.total_work = work_override if work_override > 0 else JobTypes.get_default_work(p_job_type, area_size)

	return job


static func create_road_job(points: PackedVector3Array, work_override: float = -1.0) -> JobNode:
	var job := JobNode.new()
	job.job_type = JobTypes.JobType.BUILD_ROAD
	job.path_points = points

	# Calculate centroid
	var total := Vector3.ZERO
	for pt in points:
		total += pt
	job.center_position = total / float(points.size()) if points.size() > 0 else Vector3.ZERO
	job.global_position = job.center_position

	# Calculate total path length
	var path_length := 0.0
	for i in range(points.size() - 1):
		path_length += points[i].distance_to(points[i + 1])

	job.total_work = work_override if work_override > 0 else JobTypes.get_default_work(
		JobTypes.JobType.BUILD_ROAD, path_length
	)

	return job


static func create_point_job(
	p_job_type: JobTypes.JobType,
	position: Vector3,
	p_metadata: Dictionary = {},
	work_override: float = -1.0
) -> JobNode:
	var job := JobNode.new()
	job.job_type = p_job_type
	job.center_position = position
	job.global_position = position
	job.metadata = p_metadata.duplicate()

	job.total_work = work_override if work_override > 0 else JobTypes.get_default_work(p_job_type, 1.0)

	return job
