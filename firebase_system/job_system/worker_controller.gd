class_name WorkerController
extends Node
## WorkerController - Per-unit worker AI
## Attaches to engineer/bulldozer units to give them autonomous work-finding behavior.
##
## KEY PRINCIPLE: Workers FIND jobs (bottom-up), they are not assigned (top-down).
## This prevents dual-authority conflicts and gives natural Rimworld-style behavior.

const UnifiedJobClass = preload("res://firebase_system/job_system/unified_job.gd")
const GridCoordsClass = preload("res://terrain/core/grid_coords.gd")
const PrintThrottleClass = preload("res://battle_system/utils/print_throttle.gd")

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

## Job commitment parameters (Company of Heroes style)
## Once committed to a job, worker stays focused instead of constantly re-evaluating
var _job_committed: bool = false
var _commitment_timer: float = 0.0
@export var commitment_duration: float = 5.0  # Seconds before re-evaluation allowed
@export var critical_override_enabled: bool = true  # CRITICAL jobs can steal after 50% commitment

## Movement parameters
@export var move_speed: float = 8.0
@export var arrival_threshold: float = 3.0  # Must match work_range to prevent oscillation

## Timers
var _job_search_timer: float = 0.0
var _work_timer: float = 0.0
var _stuck_timer: float = 0.0  # Track how long we've been stuck

## Tree-felling state (CLEAR_TERRAIN jobs - worker walks to and chops individual trees)
var _target_tree: Node3D = null  # The tree currently being chopped
var _chop_timer: float = 0.0     # Time spent chopping the current tree
var _reach_timer: float = 0.0    # Time spent trying to reach the current tree
const CHOP_TIME: float = 0.4          # Seconds chopping before a tree topples
const TREE_CHOP_STANDOFF: float = 2.5  # How far from a tree the worker stands to chop
const TREE_REACH_TIMEOUT: float = 4.0  # Give up walking and fell from here if unreachable

## Cached trees for the current clearing job (avoids O(n) iteration every frame)
## Populated once when job is claimed, trees removed as they're felled
var _cached_job_trees: Array[Node3D] = []

## Terrain-carving state (FLATTEN_AREA jobs - bulldozers carve hillsides cell by cell)
var _carve_cell: Vector2i = Vector2i.ZERO
var _has_carve_cell: bool = false
var _carve_timer: float = 0.0
var _carve_reach_timer: float = 0.0
var _flatten_target: float = 0.0
const CARVE_TICK: float = 0.1          # Apply a carve pass this often (visible, not instant)
const CARVE_STEP: float = 0.18         # Lerp fraction toward target per pass (scaled by worker rate)
const CARVE_RADIUS: float = 3.0        # Terrain modify radius around the cell
const CARVE_TOLERANCE: float = 0.3     # Within this of target height = cell done
const CELL_STANDOFF: float = 2.5       # How far from the cell centre the worker stands
const CARVE_REACH_TIMEOUT: float = 4.0 # Give up walking and carve from here if unreachable

## Path clearing state (for auto-flattening blocked terrain)
var _original_job: UnifiedJobClass = null  # Job we're trying to reach
var _original_move_target: Vector3 = Vector3.ZERO  # Original destination
var _path_clear_job: UnifiedJobClass = null  # Current flatten job
var _last_position: Vector3 = Vector3.ZERO  # For stuck detection
var _path_clear_attempts: int = 0  # Track path-clearing attempts per job
var _proactive_check_done: bool = false  # Track if we've done proactive terrain check
const STUCK_THRESHOLD: float = 2.0  # Seconds before considering worker stuck
const FLATTEN_SIZE: float = 6.0  # Size of path-clearing flatten area
const MAX_PATH_CLEAR_ATTEMPTS: int = 3  # Abandon job after this many failed attempts
const PROACTIVE_CHECK_DISTANCE: float = 15.0  # How far ahead to check for jungle
const PROACTIVE_CHECK_INTERVAL: float = 5.0  # Meters between sample points

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
	# Update commitment timer even when idle (for proper reset tracking)
	if _job_committed:
		_commitment_timer += delta
		if _commitment_timer >= commitment_duration:
			_reset_commitment()

	_job_search_timer += delta
	if _job_search_timer >= job_search_interval:
		# Add random jitter to prevent workers from synchronizing searches over time
		# This spreads job evaluations apart so crowding penalties have time to take effect
		_job_search_timer = randf_range(-0.05, 0.05)

		# Only search for work if not committed or commitment has expired
		if not _job_committed:
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

	# Proactive terrain check: detect jungle before getting stuck
	# Only check once per movement start, then periodically
	if not _proactive_check_done:
		_proactive_check_done = true
		if _check_terrain_ahead():
			_start_path_clearing()
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
		PrintThrottleClass.log("worker_arrival", "[WorkerController] %s arrived at job, starting work" % worker.name)
		return

	# Stuck detection: check if we're making progress
	var pos_diff: Vector3 = worker.global_position - _last_position
	pos_diff.y = 0
	if pos_diff.length() < 0.1:
		_stuck_timer += delta
		if _stuck_timer >= STUCK_THRESHOLD:
			# Not moving. If we're already within working range, we're not blocked -
			# crowding just stalled us a few meters short. Start working instead of
			# spawning a phantom path-clearing job.
			if current_job.is_worker_in_range(worker, work_range + 1.0):
				_stuck_timer = 0.0
				_set_state(State.WORKING)
				started_work.emit(current_job)
				PrintThrottleClass.log("worker_stall", "[WorkerController] %s stalled near job, starting work" % worker.name)
				return
			# Genuinely stuck far from the job - terrain is blocking. Clear a path.
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
			# Squad movement already applies separation steering; sending an extra
			# nudged target here double-applied it and pushed workers off their goal.
			worker.move_to(move_target)
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

	# Clearing jobs are worked by felling individual trees, not abstract work units
	if current_job.job_type == UnifiedJobClass.Type.CLEAR_TERRAIN:
		_process_chopping(delta)
		return

	# Flatten jobs are worked by carving terrain cell by cell
	if current_job.job_type == UnifiedJobClass.Type.FLATTEN_AREA:
		_process_carving(delta)
		return

	# Check if we're still in range (use extra margin to prevent oscillation)
	# Worker arrives at work_range, but we only re-move if they drift beyond work_range + 1.0
	if not current_job.is_worker_in_range(worker, work_range + 1.0):
		# Move closer
		move_target = current_job.get_work_position(worker)
		_set_state(State.MOVING_TO_JOB)
		return

	# Add work to job
	_work_timer += delta
	if _work_timer >= 0.1:  # Apply work every 0.1 seconds
		var old_progress: float = current_job.get_progress()
		_apply_work(_work_timer)
		var new_progress: float = current_job.get_progress()
		if new_progress > old_progress:
			print("[WorkerController] %s applied work: job #%d progress %.1f%% -> %.1f%%" % [
				worker.name, current_job.job_id, old_progress * 100, new_progress * 100
			])
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

func _check_terrain_ahead() -> bool:
	"""Proactively check terrain along path to job. Returns true if clearing is needed."""
	if not worker or not _terrain:
		return false

	var clearing_sys: Node = get_node_or_null("/root/ClearingSystem")
	if not clearing_sys or not clearing_sys.has_method("is_position_cleared"):
		return false

	# Direction to target
	var direction: Vector3 = (move_target - worker.global_position)
	direction.y = 0
	var distance: float = direction.length()

	if distance < PROACTIVE_CHECK_INTERVAL:
		return false  # Too close, no need to check

	direction = direction.normalized()

	# Sample points along the path
	var check_distance: float = minf(distance, PROACTIVE_CHECK_DISTANCE)
	var sample_pos: Vector3 = worker.global_position

	var step: float = PROACTIVE_CHECK_INTERVAL
	while step < check_distance:
		sample_pos = worker.global_position + direction * step
		if not clearing_sys.is_position_cleared(sample_pos):
			# Found jungle/uncleared terrain ahead - start clearing
			print("[WorkerController] %s detected uncleared terrain at %v, starting proactive clearing" % [
				worker.name, sample_pos])
			return true
		step += PROACTIVE_CHECK_INTERVAL

	return false


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
		print("[WorkerController] %s: No JobSystem reference!" % worker.name)
		return

	# Score available jobs and pick the best one
	var best_job: UnifiedJobClass = _job_system.get_best_job_for_worker(
		worker,
		worker_class,
		search_radius
	)

	if best_job:
		print("[WorkerController] %s found job #%d (type %d)" % [worker.name, best_job.job_id, best_job.job_type])
		_claim_job(best_job)
	else:
		# Debug: Check what jobs exist
		var all_jobs = _job_system.get_all_jobs()
		var ready_jobs = _job_system.get_jobs_needing_workers(worker_class)
		if all_jobs.size() > 0 or ready_jobs.size() > 0:
			print("[WorkerController] %s (%s): %d total jobs, %d need workers, none selected" % [
				worker.name, worker_class, all_jobs.size(), ready_jobs.size()
			])


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

	# Set commitment state (Company of Heroes style - stay focused on this job)
	_job_committed = true
	_commitment_timer = 0.0

	current_job = job

	# Clearing jobs: walk to and chop individual trees one at a time
	if job.job_type == UnifiedJobClass.Type.CLEAR_TERRAIN:
		# Cache trees in the job bounds ONCE when claiming (avoids O(n) iteration per frame)
		if not job.metadata.has("clear_tree_total"):
			_cache_trees_in_job()
			job.metadata["clear_tree_total"] = _cached_job_trees.size()
		if not _acquire_next_tree():
			# No standing trees in the footprint - the clearing is already done
			_finish_clear_job()
		return

	# Flatten jobs: carve the area cell by cell toward a neighbour-blended target height
	if job.job_type == UnifiedJobClass.Type.FLATTEN_AREA:
		if not job.metadata.has("carve_total"):
			job.metadata["carve_total"] = _count_carve_cells()
			job.metadata["carve_done"] = {}
			job.metadata["carve_claimed"] = {}
		if _job_system:
			_flatten_target = _job_system.get_flatten_target_height(job)
		if not _acquire_next_cell():
			_finish_flatten_job()
		return

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
	_release_target_tree()
	_release_carve_cell()
	_clear_tree_cache()
	_reset_commitment()

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
	_release_target_tree()
	_release_carve_cell()
	_clear_tree_cache()
	_reset_commitment()

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
## TREE FELLING (CLEAR_TERRAIN jobs - Age-of-Empires style)
## =============================================================================

func _process_chopping(delta: float) -> void:
	"""Walk to the claimed tree, chop it until it topples, then move to the next."""
	# Lost our tree (felled, or claimed tree vanished) - grab the next one
	if not is_instance_valid(_target_tree) or _tree_is_felling(_target_tree):
		if not _acquire_next_tree():
			_finish_clear_job()
		return

	# Not close enough yet? Keep walking to the tree (the Squad moves via its move order).
	# Stay in WORKING and re-issue the move rather than flipping states, which would
	# oscillate forever if a tree is hard to reach.
	var to_tree: Vector3 = _target_tree.global_position - worker.global_position
	to_tree.y = 0.0
	if to_tree.length() > TREE_CHOP_STANDOFF + 1.0:
		_reach_timer += delta
		if worker.has_method("move_to"):
			worker.move_to(move_target)
		# Truly unreachable - fell it from here so clearing isn't blocked
		if _reach_timer >= TREE_REACH_TIMEOUT:
			_fell_tree(_target_tree)
		return

	# In range - chop until the tree topples
	_reach_timer = 0.0
	_chop_timer += delta
	if _chop_timer >= CHOP_TIME:
		_chop_timer = 0.0
		_fell_tree(_target_tree)


func _fell_tree(tree: Node3D) -> void:
	"""Topple a tree and advance the clearing job by its share of the work."""
	if tree.has_method("_start_clear"):
		tree._start_clear()  # plays the fall tween, then frees itself
	elif is_instance_valid(tree):
		tree.queue_free()

	_target_tree = null
	_chop_timer = 0.0

	# Advance job progress by one tree's share so the job completes when all are felled
	var total: int = current_job.metadata.get("clear_tree_total", 0)
	if total > 0:
		current_job.add_work(current_job.work_required / float(total))
	_sync_zone_progress()

	if current_job.state == UnifiedJobClass.State.COMPLETE:
		_job_completed()
	elif not _acquire_next_tree():
		_finish_clear_job()


func _acquire_next_tree() -> bool:
	"""Claim the nearest standing tree in the job area and move to it. False if none left."""
	_release_target_tree()

	var tree: Node3D = _find_nearest_unclaimed_tree()
	if not tree:
		return false

	if tree.has_method("claim") and not tree.claim(worker):
		return false
	_target_tree = tree

	# Stand a short distance from the tree on the side the worker approaches from
	var to_worker: Vector3 = worker.global_position - tree.global_position
	to_worker.y = 0.0
	if to_worker.length() < 0.1:
		to_worker = Vector3.FORWARD
	move_target = tree.global_position + to_worker.normalized() * TREE_CHOP_STANDOFF
	_snap_target_to_terrain()

	_set_state(State.MOVING_TO_JOB)
	if worker.has_method("move_to"):
		worker.move_to(move_target)
	return true


func _cache_trees_in_job() -> void:
	"""Cache all trees in the job bounds ONCE when claiming the job.
	This avoids O(n) iteration over ALL trees every frame."""
	_cached_job_trees.clear()
	if not is_instance_valid(current_job):
		return

	var bounds: AABB = current_job.world_bounds
	var all_trees: Array[Node] = get_tree().get_nodes_in_group("trees") as Array[Node]
	var checked := 0
	for t in all_trees:
		if not (t is Node3D) or not is_instance_valid(t):
			continue
		checked += 1
		if _point_in_bounds(t.global_position, bounds):
			_cached_job_trees.append(t)

	print("[WorkerController] %s cached %d trees in job bounds (checked %d, bounds: %v to %v)" % [
		worker.name, _cached_job_trees.size(), checked,
		bounds.position, bounds.end
	])


func _find_nearest_unclaimed_tree() -> Node3D:
	"""Nearest standing, unclaimed tree from the cached job trees.
	Uses cached list instead of iterating all trees in the scene."""
	if not is_instance_valid(current_job):
		return null

	var best: Node3D = null
	var best_dist: float = INF

	# Clean up invalid entries as we iterate (trees that were freed)
	var valid_trees: Array[Node3D] = []
	for t: Node3D in _cached_job_trees:
		if not is_instance_valid(t):
			continue
		if _tree_is_felling(t):
			continue
		# Skip trees claimed by another worker
		if t.has_method("is_claimed") and t.is_claimed():
			if not ("claimed_by" in t and t.claimed_by == worker):
				valid_trees.append(t)  # Still valid, just claimed
				continue
		valid_trees.append(t)
		var d: float = worker.global_position.distance_squared_to(t.global_position)
		if d < best_dist:
			best_dist = d
			best = t

	# Update cache with only valid trees
	_cached_job_trees = valid_trees

	return best


func _count_trees_in_job() -> int:
	"""Count trees using the cache (fallback if cache not populated yet)."""
	if not _cached_job_trees.is_empty():
		return _cached_job_trees.size()

	# Fallback: populate cache if empty (should rarely happen)
	if not is_instance_valid(current_job):
		return 0
	_cache_trees_in_job()
	return _cached_job_trees.size()


func _finish_clear_job() -> void:
	"""No trees left to fell - drive the job to completion so terrain is marked cleared."""
	print("[WorkerController] %s: _finish_clear_job called (no more trees in job bounds)" % worker.name)

	if is_instance_valid(current_job) and current_job.can_be_worked():
		var remaining: float = current_job.work_required - current_job.work_done
		if remaining > 0.0:
			current_job.add_work(remaining)
			print("[WorkerController] %s: Added %.1f remaining work to complete clearing job" % [worker.name, remaining])
		_sync_zone_progress()

	if is_instance_valid(current_job) and current_job.state == UnifiedJobClass.State.COMPLETE:
		_job_completed()
	else:
		# Couldn't complete (e.g. prerequisites changed) - release and go idle
		print("[WorkerController] %s: Clearing job could not complete - going idle" % worker.name)
		_release_target_tree()
		current_job = null
		_set_state(State.IDLE)


func _sync_zone_progress() -> void:
	"""Keep the clearing zone's progress bar in sync with felled/total."""
	if not is_instance_valid(current_job):
		return
	var zone: Node = current_job.clearing_zone
	if is_instance_valid(zone) and zone.has_method("set_progress"):
		zone.set_progress(current_job.get_progress())


func _release_target_tree() -> void:
	if is_instance_valid(_target_tree) and _target_tree.has_method("release"):
		_target_tree.release(worker)
	_target_tree = null
	_chop_timer = 0.0
	_reach_timer = 0.0


func _clear_tree_cache() -> void:
	"""Clear the cached tree list when job ends."""
	_cached_job_trees.clear()


func _tree_is_felling(tree: Node) -> bool:
	return "is_clearing" in tree and tree.is_clearing


func _point_in_bounds(p: Vector3, bounds: AABB) -> bool:
	return (p.x >= bounds.position.x and p.x <= bounds.end.x
		and p.z >= bounds.position.z and p.z <= bounds.end.z)


## =============================================================================
## TERRAIN CARVING (FLATTEN_AREA jobs - bulldozers carve hillsides)
## =============================================================================

func _process_carving(delta: float) -> void:
	"""Drive to the claimed cell and carve it down toward the target, then move to the next."""
	if not _has_carve_cell or _cell_is_done(_carve_cell):
		if not _acquire_next_cell():
			_finish_flatten_job()
		return

	var cell_center: Vector3 = GridCoordsClass.gameplay_to_world(_carve_cell)
	var to_cell: Vector3 = cell_center - worker.global_position
	to_cell.y = 0.0

	# Not there yet? Keep driving (stay in WORKING; carve from here if it can't be reached).
	if to_cell.length() > CELL_STANDOFF + 1.5:
		_carve_reach_timer += delta
		if worker.has_method("move_to"):
			worker.move_to(move_target)
		if _carve_reach_timer >= CARVE_REACH_TIMEOUT:
			_finish_carve_cell()
		return

	_carve_reach_timer = 0.0
	_carve_timer += delta
	if _carve_timer >= CARVE_TICK:
		_carve_timer = 0.0
		var rate: float = 1.0
		if _job_system:
			rate = _job_system.get_work_rate_multiplier(worker_class, UnifiedJobClass.Type.FLATTEN_AREA)
			_job_system.carve_terrain_toward(cell_center, CARVE_RADIUS, _flatten_target, CARVE_STEP * rate)
			# Cell reached target height?
			if absf(_job_system.get_terrain_height_at(cell_center) - _flatten_target) <= CARVE_TOLERANCE:
				_finish_carve_cell()


func _finish_carve_cell() -> void:
	"""Mark the current cell carved, advance the job, and grab the next cell."""
	if is_instance_valid(current_job):
		var done: Dictionary = current_job.metadata.get("carve_done", {})
		if not done.has(_carve_cell):
			done[_carve_cell] = true
			current_job.metadata["carve_done"] = done
			var total: int = current_job.metadata.get("carve_total", 0)
			if total > 0:
				current_job.add_work(current_job.work_required / float(total))

	_release_carve_cell()

	if is_instance_valid(current_job) and current_job.state == UnifiedJobClass.State.COMPLETE:
		_job_completed()
	elif not _acquire_next_cell():
		_finish_flatten_job()


func _acquire_next_cell() -> bool:
	"""Claim the nearest cell in the job that still needs carving and move to it."""
	_release_carve_cell()
	if not is_instance_valid(current_job):
		return false

	var r: Rect2i = current_job.cell_rect
	var claimed: Dictionary = current_job.metadata.get("carve_claimed", {})
	var done: Dictionary = current_job.metadata.get("carve_done", {})
	var my_id: int = worker.get_instance_id()

	var best: Vector2i = Vector2i.ZERO
	var best_dist: float = INF
	var found: bool = false

	# Early exit threshold: if we find a cell within ~8m (2 cells), stop searching
	# This prevents O(n) iteration for large flatten jobs
	const EARLY_EXIT_DIST_SQ: float = 64.0  # 8m squared

	for x in range(r.position.x, r.end.x):
		for z in range(r.position.y, r.end.y):
			var cell := Vector2i(x, z)
			if done.has(cell):
				continue
			if claimed.has(cell) and claimed[cell] != my_id:
				continue
			var c: Vector3 = GridCoordsClass.gameplay_to_world(cell)
			# Already flat enough? Mark done and skip (no work credited - _finish_flatten_job tops up).
			if _job_system and absf(_job_system.get_terrain_height_at(c) - _flatten_target) <= CARVE_TOLERANCE:
				done[cell] = true
				continue
			var d: float = worker.global_position.distance_squared_to(c)
			if d < best_dist:
				best_dist = d
				best = cell
				found = true
				# Early exit: found a nearby cell, good enough
				if d < EARLY_EXIT_DIST_SQ:
					break
		# Break outer loop too if we found a nearby cell
		if found and best_dist < EARLY_EXIT_DIST_SQ:
			break

	current_job.metadata["carve_done"] = done
	if not found:
		return false

	claimed[best] = my_id
	current_job.metadata["carve_claimed"] = claimed
	_carve_cell = best
	_has_carve_cell = true

	var center: Vector3 = GridCoordsClass.gameplay_to_world(best)
	var to_worker: Vector3 = worker.global_position - center
	to_worker.y = 0.0
	if to_worker.length() < 0.1:
		to_worker = Vector3.FORWARD
	move_target = center + to_worker.normalized() * CELL_STANDOFF
	_snap_target_to_terrain()

	_set_state(State.MOVING_TO_JOB)
	if worker.has_method("move_to"):
		worker.move_to(move_target)
	return true


func _count_carve_cells() -> int:
	if not is_instance_valid(current_job):
		return 0
	return current_job.cell_rect.get_area()


func _cell_is_done(cell: Vector2i) -> bool:
	if not is_instance_valid(current_job):
		return true
	var done: Dictionary = current_job.metadata.get("carve_done", {})
	return done.has(cell)


func _finish_flatten_job() -> void:
	"""No cells left to carve - drive the job to completion so the build prereq unblocks."""
	if is_instance_valid(current_job) and current_job.can_be_worked():
		var remaining: float = current_job.work_required - current_job.work_done
		if remaining > 0.0:
			current_job.add_work(remaining)

	if is_instance_valid(current_job) and current_job.state == UnifiedJobClass.State.COMPLETE:
		_job_completed()
	else:
		_release_carve_cell()
		current_job = null
		_set_state(State.IDLE)


func _release_carve_cell() -> void:
	if _has_carve_cell and is_instance_valid(current_job):
		var claimed: Dictionary = current_job.metadata.get("carve_claimed", {})
		if claimed.get(_carve_cell) == worker.get_instance_id():
			claimed.erase(_carve_cell)
			current_job.metadata["carve_claimed"] = claimed
	_has_carve_cell = false
	_carve_timer = 0.0
	_carve_reach_timer = 0.0


## =============================================================================
## STATE MANAGEMENT
## =============================================================================

func _set_state(new_state: State) -> void:
	"""Change state with signal emission"""
	if new_state == state:
		return

	var old_state: State = state
	state = new_state

	# Only reset work timer when going IDLE, not when transitioning between work states
	# This prevents oscillation between MOVING_TO_JOB and WORKING from resetting progress
	if new_state == State.IDLE:
		_work_timer = 0.0
		_job_search_timer = 0.0  # Start looking for work immediately

	# Reset proactive terrain check when starting new movement
	if new_state == State.MOVING_TO_JOB:
		_proactive_check_done = false

	_stuck_timer = 0.0
	_last_position = worker.global_position if worker else Vector3.ZERO

	state_changed.emit(old_state, new_state)


func _reset_commitment() -> void:
	"""Reset job commitment state - called when job ends or is abandoned"""
	_job_committed = false
	_commitment_timer = 0.0


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
	"""Called when a job needs workers - consider claiming it if idle or stealable by CRITICAL"""
	if not is_instance_valid(job) or not job.can_be_worked():
		return

	# If idle and not committed, can take any suitable job
	if state == State.IDLE and not _job_committed:
		var score: float = _score_job(job)
		if score > 0:
			_claim_job(job)
		return

	# If busy or committed, only CRITICAL priority jobs can steal workers
	# and only after 50% of commitment duration has elapsed
	if critical_override_enabled and job.priority == UnifiedJobClass.Priority.CRITICAL:
		var commitment_progress: float = _commitment_timer / commitment_duration
		if commitment_progress >= 0.5:
			# CRITICAL job can steal this worker after 50% commitment
			var score: float = _score_job(job)
			if score > 0:
				print("[WorkerController] %s stolen by CRITICAL job #%d (commitment: %.0f%%)" % [
					worker.name, job.job_id, commitment_progress * 100
				])
				# Abandon current job and take the critical one
				if current_job:
					_abandon_job("Stolen by CRITICAL priority job")
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

	# Set commitment state for forced jobs too
	_job_committed = true
	_commitment_timer = 0.0

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


func is_committed() -> bool:
	"""Check if worker is committed to current job (Company of Heroes style)"""
	return _job_committed


func get_commitment_progress() -> float:
	"""Get commitment progress as 0.0-1.0 (1.0 = can be reassigned)"""
	if not _job_committed:
		return 1.0
	return clampf(_commitment_timer / commitment_duration, 0.0, 1.0)


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
