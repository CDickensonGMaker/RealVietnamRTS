class_name WorkerController
extends Node
## WorkerController - Per-unit worker AI
## Attaches to engineer/bulldozer units to give them autonomous work-finding behavior.
##
## KEY PRINCIPLE: Workers FIND jobs (bottom-up), they are not assigned (top-down).
## This prevents dual-authority conflicts and gives natural Rimworld-style behavior.

const UnifiedJobClass = preload("res://firebase_system/job_system/unified_job.gd")

## Worker states
enum State {
	IDLE,           # Not doing anything
	MOVING_TO_JOB,  # Walking to job location
	WORKING,        # Actively working on a job
	RETURNING,      # Moving back to idle position
	CLEARING_PATH,  # Creating/working on path-clearing job to reach destination
}

## The unit this controller is attached to
var worker: Node3D = null

## Worker class: "engineer" or "bulldozer"
var worker_class: String = "engineer"

## Current state
var state: State = State.IDLE

## Current job being worked on
var current_job: UnifiedJobClass = null

## Target position for movement
var move_target: Vector3 = Vector3.ZERO

## Work-finding parameters
@export var search_radius: float = 100.0
@export var job_search_interval: float = 0.15  # Fast re-acquisition (was 0.5)
@export var work_range: float = 3.0

## Movement parameters
@export var move_speed: float = 8.0
@export var arrival_threshold: float = 3.0  # Must match work_range to prevent oscillation

## Timers
var _job_search_timer: float = 0.0
var _work_timer: float = 0.0
var _stuck_timer: float = 0.0  # Track how long we've been stuck

## Path clearing state (for auto-flattening blocked terrain)
var _original_job: UnifiedJobClass = null  # Job we're trying to reach
var _original_move_target: Vector3 = Vector3.ZERO  # Original destination
var _path_clear_job: UnifiedJobClass = null  # Current flatten job
var _last_position: Vector3 = Vector3.ZERO  # For stuck detection
var _path_clear_attempts: int = 0  # Track path-clearing attempts per job
const STUCK_THRESHOLD: float = 2.0  # Seconds before considering worker stuck
const FLATTEN_SIZE: float = 6.0  # Size of path-clearing flatten area
const MAX_PATH_CLEAR_ATTEMPTS: int = 3  # Abandon job after this many failed attempts

## Cached references
var _job_system: Node = null
var _terrain: Node = null

## Signals
signal started_work(job: UnifiedJobClass)
signal completed_work(job: UnifiedJobClass)
signal job_abandoned(job: UnifiedJobClass, reason: String)
signal state_changed(old_state: State, new_state: State)


func _ready() -> void:
	# Get parent as worker unit
	worker = get_parent() as Node3D
	if not worker:
		push_error("[WorkerController] Must be child of a Node3D unit")
		return

	# Determine worker class
	_determine_worker_class()

	# Cache autoload references
	_job_system = get_node_or_null("/root/JobSystem")
	_terrain = get_node_or_null("/root/TerrainIntegration")

	# Connect to job system signals
	if _job_system:
		if _job_system.has_signal("worker_needed"):
			_job_system.worker_needed.connect(_on_worker_needed)

	# Connect to worker's path_blocked signal for auto path-clearing
	if worker.has_signal("path_blocked_by_slope"):
		worker.path_blocked_by_slope.connect(_on_path_blocked)
		print("[WorkerController] Connected to path_blocked_by_slope signal")

	# Add to workers group for separation steering
	worker.add_to_group("workers")

	# Initialize position tracking for stuck detection
	_last_position = worker.global_position

	# Stagger job search timer to prevent all workers searching in same frame
	_job_search_timer = randf() * job_search_interval

	print("[WorkerController] Attached to %s as %s" % [worker.name, worker_class])


func _process(delta: float) -> void:
	if not is_instance_valid(worker):
		return

	match state:
		State.IDLE:
			_process_idle(delta)
		State.MOVING_TO_JOB:
			_process_moving(delta)
		State.WORKING:
			_process_working(delta)
		State.RETURNING:
			_process_returning(delta)
		State.CLEARING_PATH:
			_process_clearing_path(delta)


## =============================================================================
## STATE PROCESSING
## =============================================================================

func _process_idle(delta: float) -> void:
	"""Look for work when idle"""
	_job_search_timer += delta
	if _job_search_timer >= job_search_interval:
		_job_search_timer = 0.0
		_find_work()


func _process_moving(delta: float) -> void:
	"""Move toward job location - delegates to worker's movement system"""
	if not is_instance_valid(current_job):
		_abandon_job("Job became invalid")
		return

	# Check if job is still workable
	if not current_job.can_be_worked():
		if current_job.state == UnifiedJobClass.State.COMPLETE:
			_job_completed()
		else:
			_abandon_job("Job no longer workable")
		return

	# Check arrival distance
	var direction: Vector3 = (move_target - worker.global_position)
	direction.y = 0
	var distance: float = direction.length()

	if distance <= arrival_threshold:
		# Arrived - start working
		_stuck_timer = 0.0
		_set_state(State.WORKING)
		started_work.emit(current_job)
		print("[WorkerController] %s arrived at job, starting work" % worker.name)
		return

	# Stuck detection: check if we're making progress
	var pos_diff: Vector3 = worker.global_position - _last_position
	pos_diff.y = 0
	if pos_diff.length() < 0.1:
		_stuck_timer += delta
		if _stuck_timer >= STUCK_THRESHOLD:
			# We're stuck! Start path clearing
			print("[WorkerController] %s stuck for %.1fs, initiating path clearing" % [worker.name, _stuck_timer])
			_start_path_clearing()
			return
	else:
		_stuck_timer = 0.0
	_last_position = worker.global_position

	# Use worker's move_to() method if available (Squad integration)
	if worker.has_method("move_to"):
		# Check if worker is stuck (has move order but velocity is zero)
		var is_stuck: bool = false
		if "velocity" in worker and "has_move_order" in worker:
			if worker.has_move_order:
				var vel: Vector3 = worker.velocity
				vel.y = 0
				if vel.length() < 0.1:
					is_stuck = true

		# Re-issue move command if not moving or stuck
		var needs_move_order: bool = true
		if "move_target" in worker and "has_move_order" in worker:
			if worker.has_move_order and not is_stuck:
				var target_diff: Vector3 = move_target - worker.move_target
				target_diff.y = 0
				if target_diff.length() < 2.0:
					needs_move_order = false  # Already heading to right place

		if needs_move_order:
			# Apply separation steering to target to avoid clumping
			var separation := _calculate_separation()
			var adjusted_target := move_target
			if separation.length() > 0.1:
				adjusted_target += separation * 1.5  # Nudge target sideways from neighbors
			worker.move_to(adjusted_target)
			print("[WorkerController] %s moving to job at %s (dist: %.1f)" % [worker.name, move_target, distance])
	else:
		# Fallback: direct movement for non-Squad workers
		direction = direction.normalized()

		# Separation steering: avoid overlapping with nearby workers
		var separation := _calculate_separation()
		if separation.length() > 0.1:
			direction = (direction + separation * 0.5).normalized()

		worker.global_position += direction * move_speed * delta

		# Snap to terrain
		_snap_to_terrain()

		# Face movement direction
		if direction.length_squared() > 0.01:
			worker.look_at(worker.global_position + direction, Vector3.UP)


func _process_working(delta: float) -> void:
	"""Work on the current job"""
	if not is_instance_valid(current_job):
		_abandon_job("Job became invalid")
		return

	# Check if job is complete
	if current_job.state == UnifiedJobClass.State.COMPLETE:
		_job_completed()
		return

	# Check if job was cancelled
	if current_job.state == UnifiedJobClass.State.CANCELLED:
		_abandon_job("Job was cancelled")
		return

	# Check if we're still in range
	if not current_job.is_worker_in_range(worker, work_range):
		# Move closer
		move_target = current_job.get_work_position(worker)
		_set_state(State.MOVING_TO_JOB)
		return

	# Add work to job
	_work_timer += delta
	if _work_timer >= 0.1:  # Apply work every 0.1 seconds
		_apply_work(_work_timer)
		_work_timer = 0.0


func _process_returning(delta: float) -> void:
	"""Return to idle position (or just go idle if no designated spot)"""
	# For now, just go idle immediately
	# Could add rally point behavior later
	_set_state(State.IDLE)


func _process_clearing_path(delta: float) -> void:
	"""Work on path-clearing job, then resume original job"""
	if not is_instance_valid(_path_clear_job):
		# Path clearing job is gone - try to resume original job
		_resume_original_job()
		return

	# Check if path clearing job is complete
	if _path_clear_job.state == UnifiedJobClass.State.COMPLETE:
		print("[WorkerController] %s finished clearing path, resuming original job" % worker.name)
		_path_clear_job = null
		_resume_original_job()
		return

	# Check if path clearing job was cancelled
	if _path_clear_job.state == UnifiedJobClass.State.CANCELLED:
		print("[WorkerController] %s path clearing cancelled, resuming original job" % worker.name)
		_path_clear_job = null
		_resume_original_job()
		return

	# Check arrival at path clearing job
	var clear_target: Vector3 = _path_clear_job.get_work_position(worker)
	var direction: Vector3 = (clear_target - worker.global_position)
	direction.y = 0
	var distance: float = direction.length()

	if distance <= work_range:
		# We're close enough - work on the flatten job
		_work_timer += delta
		if _work_timer >= 0.1:
			if _job_system:
				_job_system.add_work(_path_clear_job, worker, _work_timer)
			_work_timer = 0.0
	else:
		# Move toward the flatten job
		if worker.has_method("move_to"):
			worker.move_to(clear_target)


## =============================================================================
## PATH CLEARING (AUTO-FLATTEN BLOCKED TERRAIN)
## =============================================================================

func _start_path_clearing() -> void:
	"""Create a flatten job at the blocking position to clear a path"""
	if not _job_system:
		return

	# Don't start path clearing if we're already doing it
	if is_instance_valid(_path_clear_job):
		return

	# Check if we've exceeded path-clearing attempts for this job
	_path_clear_attempts += 1
	if _path_clear_attempts > MAX_PATH_CLEAR_ATTEMPTS:
		print("[WorkerController] %s exceeded %d path-clear attempts, abandoning job" % [
			worker.name, MAX_PATH_CLEAR_ATTEMPTS])
		_abandon_job("path blocked after multiple attempts")
		return

	# Store original job so we can resume it
	_original_job = current_job
	_original_move_target = move_target

	# Calculate position to flatten (in front of the worker, toward the target)
	var to_target: Vector3 = (move_target - worker.global_position).normalized()
	var flatten_center: Vector3 = worker.global_position + to_target * (FLATTEN_SIZE * 0.5 + 1.0)
	flatten_center.y = 0  # Will be set by terrain

	# Snap flatten center to terrain height
	if _terrain and _terrain.has_method("get_height_at"):
		flatten_center.y = _terrain.get_height_at(flatten_center)

	# Create a small flatten job
	var flatten_size := Vector2(FLATTEN_SIZE, FLATTEN_SIZE)
	_path_clear_job = _job_system.create_job(
		UnifiedJobClass.Type.FLATTEN_AREA,
		flatten_center,
		flatten_size,
		UnifiedJobClass.Priority.HIGH  # High priority to clear path quickly
	)

	if _path_clear_job:
		# Assign ourselves to this job
		_path_clear_job.assign_worker(worker)
		_set_state(State.CLEARING_PATH)
		_stuck_timer = 0.0
		print("[WorkerController] %s created path-clearing flatten job #%d at %s" % [
			worker.name, _path_clear_job.job_id, flatten_center
		])
	else:
		# Failed to create job - just resume trying to reach original job
		print("[WorkerController] %s failed to create flatten job, will retry movement" % worker.name)
		_stuck_timer = 0.0


func _resume_original_job() -> void:
	"""Resume the original job after path clearing"""
	_stuck_timer = 0.0

	if is_instance_valid(_original_job) and _original_job.can_be_worked():
		# Resume the original job
		current_job = _original_job
		move_target = _original_move_target
		_original_job = null
		_original_move_target = Vector3.ZERO
		_set_state(State.MOVING_TO_JOB)

		# Re-issue move command
		if worker.has_method("move_to"):
			worker.move_to(move_target)

		print("[WorkerController] %s resuming job #%d" % [worker.name, current_job.job_id])
	else:
		# Original job is gone - go idle to find new work
		_original_job = null
		_original_move_target = Vector3.ZERO
		current_job = null
		_set_state(State.IDLE)
		print("[WorkerController] %s original job gone, going idle" % worker.name)


func _on_path_blocked(position: Vector3, slope: float) -> void:
	"""Called when worker's movement is blocked by steep slope"""
	# Only handle if we're moving to a job
	if state != State.MOVING_TO_JOB:
		return

	# Don't start path clearing if we're already doing it
	if is_instance_valid(_path_clear_job):
		return

	print("[WorkerController] %s path blocked at %s (slope: %.2f), starting path clearing" % [
		worker.name, position, slope
	])

	_start_path_clearing()


## =============================================================================
## WORK FINDING (BOTTOM-UP APPROACH)
## =============================================================================

func _find_work() -> void:
	"""Find the best available job to work on"""
	if not _job_system:
		return

	# Score available jobs and pick the best one
	var best_job: UnifiedJobClass = _job_system.get_best_job_for_worker(
		worker,
		worker_class,
		search_radius
	)

	if best_job:
		_claim_job(best_job)


func _score_job(job: UnifiedJobClass) -> float:
	"""Score a job based on priority, distance, and compatibility"""
	if not is_instance_valid(job):
		return -INF

	if not job.can_be_worked():
		return -INF

	if job.assigned_workers.size() >= job.max_workers:
		return -INF

	# Check if this worker can do the job
	if not _job_system.can_worker_do_job(worker_class, job.job_type):
		return -INF

	# Base score from priority (CRITICAL=0 gets 400, LOW=3 gets 100)
	var priority_score: float = (4 - job.priority) * 100.0

	# Distance penalty
	var dist: float = worker.global_position.distance_to(job.get_centroid())
	var distance_penalty: float = dist * 2.0

	# Bonus for jobs already in progress
	var progress_bonus: float = 0.0
	if job.state == UnifiedJobClass.State.IN_PROGRESS:
		progress_bonus = 50.0 + job.get_progress() * 50.0

	# Worker efficiency bonus
	var efficiency: float = _job_system.get_work_rate_multiplier(worker_class, job.job_type)
	var efficiency_bonus: float = efficiency * 30.0

	return priority_score - distance_penalty + progress_bonus + efficiency_bonus


func _claim_job(job: UnifiedJobClass) -> void:
	"""Claim a job and start moving to it"""
	if not is_instance_valid(job):
		return

	# Try to assign ourselves to the job
	if not job.assign_worker(worker):
		return  # Job is full

	# Reset path-clearing counter for new job
	_path_clear_attempts = 0

	current_job = job
	move_target = job.get_work_position(worker)
	_snap_target_to_terrain()

	_set_state(State.MOVING_TO_JOB)

	# Immediately issue move command to worker's movement system
	if worker.has_method("move_to"):
		worker.move_to(move_target)

	print("[WorkerController] %s claimed job #%d (%s) at %s" % [
		worker.name,
		job.job_id,
		UnifiedJobClass.get_type_name(job.job_type),
		move_target
	])


func _abandon_job(reason: String) -> void:
	"""Abandon current job and go idle"""
	if is_instance_valid(current_job):
		current_job.unassign_worker(worker)
		job_abandoned.emit(current_job, reason)

		print("[WorkerController] %s abandoned job #%d: %s" % [
			worker.name,
			current_job.job_id if current_job else -1,
			reason
		])

	current_job = null
	_set_state(State.IDLE)


func _job_completed() -> void:
	"""Handle job completion"""
	if is_instance_valid(current_job):
		completed_work.emit(current_job)
		print("[WorkerController] %s completed job #%d" % [
			worker.name,
			current_job.job_id
		])

	current_job = null
	_set_state(State.IDLE)


## =============================================================================
## WORK APPLICATION
## =============================================================================

func _apply_work(delta: float) -> void:
	"""Apply work to current job"""
	if not _job_system or not is_instance_valid(current_job):
		return

	_job_system.add_work(current_job, worker, delta)


## =============================================================================
## STATE MANAGEMENT
## =============================================================================

func _set_state(new_state: State) -> void:
	"""Change state with signal emission"""
	if new_state == state:
		return

	var old_state: State = state
	state = new_state

	# Reset timers on state change
	_work_timer = 0.0
	_stuck_timer = 0.0
	_last_position = worker.global_position if worker else Vector3.ZERO
	if new_state == State.IDLE:
		_job_search_timer = 0.0  # Start looking for work immediately

	state_changed.emit(old_state, new_state)


func _determine_worker_class() -> void:
	"""Determine worker class from unit data"""
	if not worker:
		return

	# Check for explicit worker_class property
	if "worker_class" in worker:
		worker_class = worker.worker_class
		return

	# Check if it's a vehicle (bulldozer)
	if worker.has_method("get"):
		var data: Resource = worker.get("data")
		if data and "is_vehicle" in data and data.is_vehicle:
			worker_class = "bulldozer"
			move_speed = 5.0  # Slower for bulldozers
			return

	# Default to engineer
	worker_class = "engineer"
	move_speed = 8.0


## =============================================================================
## SEPARATION STEERING
## =============================================================================

const SEPARATION_RADIUS := 2.0  # Avoid workers within 2m
const SEPARATION_WEIGHT := 0.5  # How strongly to steer away

func _calculate_separation() -> Vector3:
	"""Calculate steering force to avoid nearby workers"""
	var separation := Vector3.ZERO

	for other in get_tree().get_nodes_in_group("workers"):
		if other == worker:
			continue
		if not is_instance_valid(other):
			continue

		var diff: Vector3 = worker.global_position - other.global_position
		diff.y = 0  # Only separate horizontally
		var dist: float = diff.length()

		if dist > 0.1 and dist < SEPARATION_RADIUS:
			# Stronger push when closer
			separation += diff.normalized() / dist

	if separation.length() > 0.1:
		return separation.normalized() * SEPARATION_WEIGHT
	return Vector3.ZERO


## =============================================================================
## TERRAIN HELPERS
## =============================================================================

func _snap_to_terrain() -> void:
	"""Snap worker Y position to terrain height"""
	if not _terrain or not _terrain.has_method("get_height_at"):
		return

	var height: float = _terrain.get_height_at(worker.global_position)
	worker.global_position.y = height


func _snap_target_to_terrain() -> void:
	"""Snap move target Y to terrain height"""
	if not _terrain or not _terrain.has_method("get_height_at"):
		return

	move_target.y = _terrain.get_height_at(move_target)


## =============================================================================
## SIGNAL HANDLERS
## =============================================================================

func _on_worker_needed(job: UnifiedJobClass) -> void:
	"""Called when a job needs workers - consider claiming it if idle"""
	if state != State.IDLE:
		return  # Already busy

	# Check if this job is better than waiting
	if is_instance_valid(job) and job.can_be_worked():
		var score: float = _score_job(job)
		if score > 0:
			_claim_job(job)


## =============================================================================
## PUBLIC API
## =============================================================================

func force_job(job: UnifiedJobClass) -> bool:
	"""Force this worker to take a specific job (player command)"""
	# Abandon current job if any
	if current_job:
		_abandon_job("Reassigned by player")

	# Claim new job
	if not is_instance_valid(job):
		return false

	if not _job_system.can_worker_do_job(worker_class, job.job_type):
		return false

	if not job.assign_worker(worker):
		return false

	current_job = job
	move_target = job.get_work_position(worker)
	_snap_target_to_terrain()

	_set_state(State.MOVING_TO_JOB)
	return true


func stop_work() -> void:
	"""Stop current work and go idle"""
	if current_job:
		_abandon_job("Stopped by player")
	_set_state(State.IDLE)


func is_busy() -> bool:
	"""Check if worker is doing something"""
	return state != State.IDLE


func get_current_job() -> UnifiedJobClass:
	"""Get current job (may be null)"""
	return current_job


func get_state_name() -> String:
	"""Get display name for current state"""
	match state:
		State.IDLE: return "Idle"
		State.MOVING_TO_JOB: return "Moving to Job"
		State.WORKING: return "Working"
		State.RETURNING: return "Returning"
		State.CLEARING_PATH: return "Clearing Path"
		_: return "Unknown"


func get_status_string() -> String:
	"""Get detailed status string for UI"""
	match state:
		State.IDLE:
			return "Idle - Looking for work"
		State.MOVING_TO_JOB:
			if current_job:
				return "Moving to %s" % UnifiedJobClass.get_type_name(current_job.job_type)
			return "Moving"
		State.WORKING:
			if current_job:
				return "%s - %.0f%%" % [
					current_job.get_current_stage_name(),
					current_job.get_progress() * 100
				]
			return "Working"
		State.RETURNING:
			return "Returning"
		State.CLEARING_PATH:
			if _path_clear_job:
				return "Clearing Path - %.0f%%" % [_path_clear_job.get_progress() * 100]
			return "Clearing Path"
		_:
			return "Unknown"
