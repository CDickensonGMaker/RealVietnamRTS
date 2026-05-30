extends Node
## Note: No class_name to avoid conflict with autoload singleton name "TestDaemon"
## TestDaemon - File-based command interface for Claude testing
##
## Claude writes commands to commands.jsonl, this daemon executes them
## and writes results to results.jsonl. Enables autonomous game testing.
##
## Command format: {"id": int, "cmd": string, "args": {}}
## Result format: {"id": int, "status": "ok"|"error", "data": {}}

# Real-time signals for in-engine agent communication (no file I/O needed)
signal command_executed(cmd_id: int, cmd_name: String, result: Dictionary)
signal job_status_changed(job_id: int, status: String, progress: float)
signal health_alert(frozen: bool, fps: float, memory_mb: float)
signal state_changed(state_type: String, data: Dictionary)

const POLL_INTERVAL := 1.0  # Check once per second (reduced from 10x to prevent freezing)
const COMMANDS_FILE := "user://test_daemon/commands.jsonl"
const RESULTS_FILE := "user://test_daemon/results.jsonl"
const STATE_FILE := "user://test_daemon/state_snapshot.json"
const HEALTH_FILE := "user://test_daemon/health.json"

var _poll_timer: float = 0.0
var _processed_ids: Dictionary = {}  # Track processed command IDs
var _results_file: FileAccess = null
var _enabled: bool = true
var _command_count: int = 0
var _is_processing: bool = false  # Prevent concurrent command processing
var _processing_start_time: float = 0.0  # For timeout detection
const PROCESSING_TIMEOUT := 10.0  # Reset flag if stuck for 10 seconds

# Health monitoring
var _fps_samples: Array[float] = []
var _fps_sample_timer: float = 0.0
const FPS_SAMPLE_INTERVAL := 0.5  # Sample FPS every 0.5 seconds
const FPS_SAMPLE_COUNT := 20  # Keep 10 seconds of FPS history
var _health_write_timer: float = 0.0
const HEALTH_WRITE_INTERVAL := 2.0  # Write health file every 2 seconds
var _last_frame: int = 0
var _startup_time: float = 0.0

# Job progress tracking for anomaly detection
var _job_progress_snapshots: Dictionary = {}  # job_id -> Array of {time, progress, workers}
const MAX_PROGRESS_HISTORY: int = 20  # Keep last 20 snapshots per job
const PROGRESS_SAMPLE_INTERVAL: float = 2.0  # Sample every 2 seconds
var _progress_sample_timer: float = 0.0

# References to game systems
var _selection_manager: Node = null
var _job_system: Node = null
var _supply_manager: Node = null
var _construction_manager: Node = null


func _ready() -> void:
	# Ensure directory exists
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("test_daemon"):
		dir.make_dir("test_daemon")

	# Get system references
	_selection_manager = get_node_or_null("/root/SelectionManager")
	_job_system = get_node_or_null("/root/JobSystem")
	_supply_manager = get_node_or_null("/root/SupplyManager")
	_construction_manager = get_node_or_null("/root/ConstructionManager")

	# Clear old results
	if FileAccess.file_exists(RESULTS_FILE):
		DirAccess.remove_absolute(RESULTS_FILE)

	# Clear old commands to prevent re-execution on scene reload
	# Without this, clearing _processed_ids causes all old commands to re-run
	if FileAccess.file_exists(COMMANDS_FILE):
		DirAccess.remove_absolute(COMMANDS_FILE)
		print("[TestDaemon] Cleared old commands file on scene reload")

	# Clear processed IDs on scene reload
	_processed_ids.clear()

	# Initialize health monitoring
	_startup_time = Time.get_unix_time_from_system()
	_write_health_file()

	print("[TestDaemon] Initialized - listening for commands at %s" % COMMANDS_FILE)
	print("[TestDaemon] User data dir: %s" % OS.get_user_data_dir())


## Reset for scene reloads - clears command queue to prevent re-execution
## Call this from test scene _reset_persistent_state() functions
func reset() -> void:
	_processed_ids.clear()
	_startup_complete = false
	_poll_timer = 0.0
	_is_processing = false

	# Clear command files to prevent re-execution
	if FileAccess.file_exists(COMMANDS_FILE):
		DirAccess.remove_absolute(COMMANDS_FILE)
	if FileAccess.file_exists(RESULTS_FILE):
		DirAccess.remove_absolute(RESULTS_FILE)

	print("[TestDaemon] Reset - cleared commands and processed IDs")


var _startup_complete: bool = false
const STARTUP_DELAY := 2.0

func _process(delta: float) -> void:
	# Health monitoring - runs always
	_update_health_monitoring(delta)

	if not _enabled:
		return

	_poll_timer += delta

	# Wait for startup delay before first poll
	if not _startup_complete:
		if _poll_timer >= STARTUP_DELAY:
			_startup_complete = true
			_poll_timer = 0.0
			print("[TestDaemon] Startup complete, beginning continuous polling...")
		return

	# Continuous polling after startup
	if _poll_timer >= POLL_INTERVAL:
		_poll_timer = 0.0
		_check_commands()


func _update_health_monitoring(delta: float) -> void:
	"""Track FPS, job progress, and write health file periodically"""
	# Sample FPS
	_fps_sample_timer += delta
	if _fps_sample_timer >= FPS_SAMPLE_INTERVAL:
		_fps_sample_timer = 0.0
		var current_fps: float = Engine.get_frames_per_second()
		_fps_samples.append(current_fps)
		if _fps_samples.size() > FPS_SAMPLE_COUNT:
			_fps_samples.pop_front()

	# Sample job progress for anomaly detection
	_progress_sample_timer += delta
	if _progress_sample_timer >= PROGRESS_SAMPLE_INTERVAL:
		_progress_sample_timer = 0.0
		_sample_job_progress()

	# Write health file
	_health_write_timer += delta
	if _health_write_timer >= HEALTH_WRITE_INTERVAL:
		_health_write_timer = 0.0
		_write_health_file()


func _write_health_file() -> void:
	"""Write current health status to file"""
	var current_frame: int = Engine.get_process_frames()
	var frames_since_last: int = current_frame - _last_frame
	_last_frame = current_frame

	var health := {
		"timestamp": Time.get_unix_time_from_system(),
		"uptime": Time.get_unix_time_from_system() - _startup_time,
		"frame": current_frame,
		"frames_delta": frames_since_last,
		"fps_current": Engine.get_frames_per_second(),
		"fps_avg": _get_avg_fps(),
		"fps_min": _get_min_fps(),
		"frozen": _is_frozen(),
		"memory_mb": OS.get_static_memory_usage() / 1048576.0,
	}

	var file := FileAccess.open(HEALTH_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(health, "\t"))
		file.close()

	# Emit alert signal if performance issues detected
	var is_frozen: bool = health.frozen
	var avg_fps: float = health.fps_avg
	var memory: float = health.memory_mb
	if is_frozen or avg_fps < 30.0 or memory > 2000.0:
		health_alert.emit(is_frozen, avg_fps, memory)


func _get_avg_fps() -> float:
	if _fps_samples.is_empty():
		return 0.0
	var total: float = 0.0
	for fps in _fps_samples:
		total += fps
	return total / _fps_samples.size()


func _get_min_fps() -> float:
	if _fps_samples.is_empty():
		return 0.0
	var min_fps: float = 9999.0
	for fps in _fps_samples:
		if fps < min_fps:
			min_fps = fps
	return min_fps


func _is_frozen() -> bool:
	"""Detect if game might be frozen (FPS near zero)"""
	if _fps_samples.size() < 3:
		return false
	# Check last 3 samples
	var recent_samples: int = mini(3, _fps_samples.size())
	var sum: float = 0.0
	for i in range(_fps_samples.size() - recent_samples, _fps_samples.size()):
		sum += _fps_samples[i]
	return sum / recent_samples < 5.0  # Less than 5 FPS average = likely frozen


func _check_commands() -> void:
	# Check for timeout - reset if stuck
	if _is_processing:
		var elapsed: float = Time.get_unix_time_from_system() - _processing_start_time
		if elapsed > PROCESSING_TIMEOUT:
			push_warning("[TestDaemon] Processing timeout after %.1fs, resetting" % elapsed)
			_is_processing = false
		else:
			return

	# Reset processed IDs when commands file is deleted (allows fresh batch)
	if not FileAccess.file_exists(COMMANDS_FILE):
		_processed_ids.clear()
		return

	var file := FileAccess.open(COMMANDS_FILE, FileAccess.READ)
	if not file:
		push_warning("[TestDaemon] Failed to open commands file")
		return

	# Collect commands to process (read file first, close it, then execute)
	var commands_to_process: Array[Dictionary] = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue

		var cmd = JSON.parse_string(line)
		if cmd is Dictionary:
			var cmd_id = cmd.get("id", -1)
			if cmd_id != -1 and not _processed_ids.has(cmd_id):
				commands_to_process.append(cmd)
				_processed_ids[cmd_id] = true
				_command_count += 1

	file.close()

	if commands_to_process.is_empty():
		return

	# Set processing flag and execute commands sequentially
	_is_processing = true
	_processing_start_time = Time.get_unix_time_from_system()

	for cmd in commands_to_process:
		await _execute_command(cmd)

	_is_processing = false


func _execute_command(cmd: Dictionary) -> void:
	# Note: This function is async due to screenshot command
	var cmd_id = cmd.get("id", 0)
	var cmd_type: String = cmd.get("cmd", "")
	var args: Dictionary = cmd.get("args", {})

	print("[TestDaemon] Executing: %s (id=%d)" % [cmd_type, cmd_id])

	var result := {"id": cmd_id, "status": "ok", "data": {}}

	match cmd_type:
		# State queries
		"get_state":
			result.data = _cmd_get_state()
		"get_units":
			result.data = _cmd_get_units(args)
		"get_jobs":
			result.data = _cmd_get_jobs()

		# Unit control
		"select_group":
			result.data = _cmd_select_group(args)
		"select_unit":
			result.data = _cmd_select_unit(args)
		"move_to":
			result.data = _cmd_move_to(args)
		"attack_move":
			result.data = _cmd_attack_move(args)
		"stop":
			result.data = _cmd_stop()

		# Construction
		"paint_clearing":
			result.data = _cmd_paint_clearing(args)
		"place_building":
			result.data = _cmd_place_building(args)
		"cancel_job":
			result.data = _cmd_cancel_job(args)

		# Spawning
		"spawn_engineer":
			result.data = _cmd_spawn_engineer(args)
		"spawn_bulldozer":
			result.data = _cmd_spawn_bulldozer(args)

		# Observation
		"screenshot":
			result.data = await _cmd_screenshot(args)
		"wait_seconds":
			result.data = _cmd_wait_seconds(args)

		# Control
		"clear_commands":
			result.data = _cmd_clear_commands()
		"ping":
			result.data = {"pong": true, "time": Time.get_unix_time_from_system()}

		# Health monitoring
		"get_health":
			result.data = _cmd_get_health()

		# Job diagnostics (anomaly detection)
		"get_job_anomalies":
			result.data = _cmd_get_job_anomalies()
		"get_workers":
			result.data = _cmd_get_workers()
		"validate_job_workers":
			result.data = _cmd_validate_job_workers()
		"get_job_progress_history":
			result.data = _cmd_get_job_progress_history(args)

		# Terrain diagnostics
		"get_terrain_anomalies":
			result.data = _cmd_get_terrain_anomalies(args)

		# Comprehensive game inspection
		"inspect_game":
			result.data = _cmd_inspect_game()

		# Multi-phase testing commands
		"spawn_unit":
			result.data = _cmd_spawn_unit(args)
		"create_clearing_job":
			result.data = _cmd_create_clearing_job(args)
		"create_landing_zone":
			result.data = _cmd_create_landing_zone(args)
		"order_attack":
			result.data = _cmd_order_attack(args)
		"order_garrison":
			result.data = _cmd_order_garrison(args)
		"get_unit_status":
			result.data = _cmd_get_unit_status(args)
		"get_combat_status":
			result.data = _cmd_get_combat_status()
		"get_firebase_supply":
			result.data = _cmd_get_firebase_supply()
		"wait_job_complete":
			result.data = await _cmd_wait_job_complete(args)

		_:
			result.status = "error"
			result.data = {"message": "Unknown command: %s" % cmd_type}

	_write_result(result)

	# Emit signal for real-time in-engine listeners
	command_executed.emit(cmd_id, cmd_type, result)


func _write_result(result: Dictionary) -> void:
	var file := FileAccess.open(RESULTS_FILE, FileAccess.READ_WRITE)
	if not file:
		file = FileAccess.open(RESULTS_FILE, FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_line(JSON.stringify(result))
		file.close()


# ============================================================================
# STATE QUERIES
# ============================================================================

func _cmd_get_state() -> Dictionary:
	var state := {
		"timestamp": Time.get_unix_time_from_system(),
		"frame": Engine.get_process_frames(),
		"units": [],
		"jobs": {"pending": 0, "in_progress": 0, "completed": 0},
		"supply": 0.0,
		"selected_count": 0,
	}

	# Units
	for unit in get_tree().get_nodes_in_group("player_units"):
		var unit_data := {
			"name": unit.name,
			"position": _vec3_to_array(unit.global_position),
		}
		if "state" in unit:
			unit_data["state"] = unit.state
		if "current_health" in unit:
			unit_data["health"] = unit.current_health
		if "has_move_order" in unit:
			unit_data["moving"] = unit.has_move_order
		state.units.append(unit_data)

	# Jobs
	if _job_system and _job_system.has_method("get_job_counts"):
		state.jobs = _job_system.get_job_counts()

	# Supply
	if _supply_manager and _supply_manager.has_method("get_global_supply"):
		state.supply = _supply_manager.get_global_supply()

	# Selection
	if _selection_manager and "selected_units" in _selection_manager:
		state.selected_count = _selection_manager.selected_units.size()

	# Write full state to file
	var file := FileAccess.open(STATE_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(state, "\t"))
		file.close()

	return {"snapshot_written": true, "units": state.units.size(), "jobs": state.jobs}


func _cmd_get_units(args: Dictionary) -> Dictionary:
	var units := []
	var group: String = args.get("group", "player_units")

	for unit in get_tree().get_nodes_in_group(group):
		units.append({
			"name": unit.name,
			"position": _vec3_to_array(unit.global_position),
			"class": unit.get_class(),
		})

	return {"count": units.size(), "units": units}


func _cmd_get_jobs() -> Dictionary:
	if not _job_system:
		return {"error": "JobSystem not found"}

	var UnifiedJobClass = preload("res://firebase_system/job_system/unified_job.gd")
	var jobs_list := []

	for job in _job_system.get_all_jobs():
		if not is_instance_valid(job):
			continue

		var job_data := {
			"id": job.job_id if "job_id" in job else -1,
			"type": job.job_type if "job_type" in job else -1,
			"type_name": UnifiedJobClass.get_type_name(job.job_type) if "job_type" in job else "unknown",
			"state": job.state if "state" in job else -1,
			"state_name": UnifiedJobClass.get_state_name(job.state) if "state" in job else "unknown",
			"position": _vec3_to_array(job.get_centroid()) if job.has_method("get_centroid") else [0, 0, 0],
			"progress": job.get_progress() if job.has_method("get_progress") else 0.0,
			"work_done": job.work_done if "work_done" in job else 0.0,
			"work_required": job.work_required if "work_required" in job else 0.0,
			"workers_assigned": job.assigned_workers.size() if "assigned_workers" in job else 0,
			"max_workers": job.max_workers if "max_workers" in job else 0,
			"current_stage": job.get_current_stage_name() if job.has_method("get_current_stage_name") else "",
		}
		jobs_list.append(job_data)

	return {"count": jobs_list.size(), "jobs": jobs_list}


func _cmd_get_health() -> Dictionary:
	"""Return current health status for freeze detection"""
	return {
		"timestamp": Time.get_unix_time_from_system(),
		"uptime": Time.get_unix_time_from_system() - _startup_time,
		"frame": Engine.get_process_frames(),
		"fps_current": Engine.get_frames_per_second(),
		"fps_avg": _get_avg_fps(),
		"fps_min": _get_min_fps(),
		"frozen": _is_frozen(),
		"memory_mb": OS.get_static_memory_usage() / 1048576.0,
		"commands_processed": _command_count,
	}


# ============================================================================
# JOB DIAGNOSTICS (ANOMALY DETECTION)
# ============================================================================

func _sample_job_progress() -> void:
	"""Sample job progress for anomaly detection"""
	if not _job_system:
		return

	var current_time: float = Time.get_unix_time_from_system()

	# Track which job_ids are currently active
	var active_job_ids: Array[int] = []

	for job in _job_system.get_all_jobs():
		if not is_instance_valid(job):
			continue

		# Always use job_id consistently (never instance_id as fallback)
		if not "job_id" in job:
			continue
		var job_id: int = job.job_id
		active_job_ids.append(job_id)

		if job_id not in _job_progress_snapshots:
			_job_progress_snapshots[job_id] = []

		var snapshots: Array = _job_progress_snapshots[job_id]
		var progress: float = job.get_progress() if job.has_method("get_progress") else 0.0
		var work_done: float = job.work_done if "work_done" in job else 0.0
		var workers: int = job.assigned_workers.size() if "assigned_workers" in job else 0

		snapshots.append({
			"time": current_time,
			"progress": progress,
			"work_done": work_done,
			"workers": workers,
		})

		# Emit job status signal for real-time listeners
		var state_name: String = job.state_name if "state_name" in job else "unknown"
		job_status_changed.emit(job_id, state_name, progress)

		# Trim old snapshots per job
		while snapshots.size() > MAX_PROGRESS_HISTORY:
			snapshots.pop_front()

	# Clean up jobs that are no longer active
	var to_remove: Array[int] = []
	for job_id in _job_progress_snapshots:
		if job_id not in active_job_ids:
			to_remove.append(job_id)
	for job_id in to_remove:
		_job_progress_snapshots.erase(job_id)

	# Safety cap: limit total tracked jobs to prevent memory bloat
	const MAX_TRACKED_JOBS := 100
	if _job_progress_snapshots.size() > MAX_TRACKED_JOBS:
		var keys: Array = _job_progress_snapshots.keys()
		keys.sort()
		for i in range(keys.size() - MAX_TRACKED_JOBS):
			_job_progress_snapshots.erase(keys[i])


func _cmd_get_job_anomalies() -> Dictionary:
	"""Get all detected job anomalies - jobs with no workers or stalled progress"""
	if not _job_system:
		return {"error": "JobSystem not found"}

	var UnifiedJobClass = preload("res://firebase_system/job_system/unified_job.gd")
	var anomalies: Array = []
	var current_time: float = Time.get_unix_time_from_system()

	for job in _job_system.get_all_jobs():
		if not is_instance_valid(job):
			continue

		var job_id: int = job.job_id if "job_id" in job else -1
		var state: int = job.state if "state" in job else -1
		var issues: Array[String] = []
		var details: Dictionary = {}

		# State constants: PENDING=0, READY=1, IN_PROGRESS=2, COMPLETE=3, CANCELLED=4, FAILED=5
		var workers: int = job.assigned_workers.size() if "assigned_workers" in job else 0

		# Check for no workers on ready/in-progress jobs
		if workers == 0:
			if state == 2:  # IN_PROGRESS
				issues.append("no_workers_in_progress")
			elif state == 1:  # READY
				issues.append("no_workers_ready")

		# Check for stall using progress history
		if job_id in _job_progress_snapshots:
			var snapshots: Array = _job_progress_snapshots[job_id]
			if snapshots.size() >= 3:
				var first_snap: Dictionary = snapshots[0]
				var last_snap: Dictionary = snapshots[snapshots.size() - 1]
				var time_span: float = last_snap.time - first_snap.time
				var progress_delta: float = last_snap.progress - first_snap.progress

				# Stalled if has workers, time > 10s, progress < 1%
				if time_span > 10.0 and progress_delta < 0.01 and workers > 0:
					issues.append("stalled")
					details["stall_duration"] = time_span
					details["progress_delta"] = progress_delta

		if not issues.is_empty():
			anomalies.append({
				"job_id": job_id,
				"type": job.job_type if "job_type" in job else -1,
				"type_name": UnifiedJobClass.get_type_name(job.job_type) if "job_type" in job else "unknown",
				"state": state,
				"state_name": UnifiedJobClass.get_state_name(state),
				"issues": issues,
				"details": details,
				"workers": workers,
				"progress": job.get_progress() if job.has_method("get_progress") else 0.0,
				"position": _vec3_to_array(job.get_centroid()) if job.has_method("get_centroid") else [0, 0, 0],
			})

	return {
		"count": anomalies.size(),
		"anomalies": anomalies,
		"timestamp": current_time,
	}


func _cmd_get_workers() -> Dictionary:
	"""Get all workers and their current job assignments"""
	var workers: Array = []

	# Try "workers" group first, fallback to "player_units"
	var worker_nodes: Array = get_tree().get_nodes_in_group("workers")
	if worker_nodes.is_empty():
		worker_nodes = get_tree().get_nodes_in_group("player_units")

	for unit in worker_nodes:
		if not is_instance_valid(unit):
			continue

		var worker_data := {
			"name": unit.name,
			"position": _vec3_to_array(unit.global_position),
			"state": "unknown",
			"worker_class": "unknown",
			"current_job_id": null,
			"job_progress": 0.0,
		}

		# Try to get WorkerController child for detailed state
		for child in unit.get_children():
			# Skip children that aren't WorkerController
			if not "worker_class" in child:
				continue

			# Found WorkerController - extract data
			worker_data["worker_class"] = child.worker_class
			if "state" in child:
				worker_data["state"] = child.state
				# Try to get state name
				if child.has_method("get_state_name"):
					worker_data["state"] = child.get_state_name()
			if "current_job" in child and is_instance_valid(child.current_job):
				worker_data["current_job_id"] = child.current_job.job_id if "job_id" in child.current_job else -1
				worker_data["job_progress"] = child.current_job.get_progress() if child.current_job.has_method("get_progress") else 0.0
			break  # Found WorkerController, stop searching

		# Also try using the Squad's method to get WorkerController
		if worker_data["worker_class"] == "unknown" and unit.has_method("get_worker_controller"):
			var wc = unit.get_worker_controller()
			if wc:
				worker_data["worker_class"] = wc.worker_class if "worker_class" in wc else "unknown"
				if "state" in wc:
					worker_data["state"] = wc.get_state_name() if wc.has_method("get_state_name") else wc.state
				if "current_job" in wc and is_instance_valid(wc.current_job):
					worker_data["current_job_id"] = wc.current_job.job_id
					worker_data["job_progress"] = wc.current_job.get_progress() if wc.current_job.has_method("get_progress") else 0.0

		workers.append(worker_data)

	return {"count": workers.size(), "workers": workers}


func _cmd_validate_job_workers() -> Dictionary:
	"""Validate that jobs have appropriate worker coverage - detects mismatches"""
	if not _job_system:
		return {"error": "JobSystem not found"}

	var validation := {
		"timestamp": Time.get_unix_time_from_system(),
		"total_jobs": 0,
		"active_jobs": 0,
		"jobs_with_workers": 0,
		"jobs_without_workers": [],
		"total_workers": 0,
		"idle_workers": 0,
		"busy_workers": 0,
		"worker_utilization": 0.0,
		"potential_issues": [],
	}

	var total_worker_slots: int = 0
	var used_worker_slots: int = 0

	# Analyze jobs
	for job in _job_system.get_all_jobs():
		if not is_instance_valid(job):
			continue

		validation.total_jobs += 1
		var state: int = job.state if "state" in job else -1
		var workers: int = job.assigned_workers.size() if "assigned_workers" in job else 0
		var max_workers: int = job.max_workers if "max_workers" in job else 1

		# Only count jobs that can be worked (READY=1 or IN_PROGRESS=2)
		if state == 1 or state == 2:
			validation.active_jobs += 1
			total_worker_slots += max_workers
			used_worker_slots += workers

			if workers > 0:
				validation.jobs_with_workers += 1
			else:
				var job_id: int = job.job_id if "job_id" in job else -1
				validation.jobs_without_workers.append({
					"job_id": job_id,
					"type": job.job_type if "job_type" in job else -1,
					"state": state,
					"position": _vec3_to_array(job.get_centroid()) if job.has_method("get_centroid") else [0, 0, 0],
				})

	# Count workers and their states
	var worker_nodes: Array = get_tree().get_nodes_in_group("workers")
	if worker_nodes.is_empty():
		worker_nodes = get_tree().get_nodes_in_group("player_units")

	for unit in worker_nodes:
		if not is_instance_valid(unit):
			continue
		validation.total_workers += 1

		# Check if worker is idle (state 0 = IDLE in WorkerController)
		for child in unit.get_children():
			if "state" in child:
				if child.state == 0:  # IDLE
					validation.idle_workers += 1
				else:
					validation.busy_workers += 1
				break

	# Calculate utilization
	if total_worker_slots > 0:
		validation.worker_utilization = float(used_worker_slots) / float(total_worker_slots)

	# Identify potential issues
	if validation.active_jobs > 0 and validation.idle_workers > 0 and validation.jobs_without_workers.size() > 0:
		validation.potential_issues.append({
			"type": "idle_workers_with_unworked_jobs",
			"idle_workers": validation.idle_workers,
			"unworked_jobs": validation.jobs_without_workers.size(),
			"message": "There are %d idle workers but %d jobs have no workers assigned" % [
				validation.idle_workers, validation.jobs_without_workers.size()
			],
		})

	if validation.jobs_with_workers == 0 and validation.active_jobs > 0:
		validation.potential_issues.append({
			"type": "no_jobs_being_worked",
			"active_jobs": validation.active_jobs,
			"message": "No workers are assigned to any of the %d active jobs" % validation.active_jobs,
		})

	return validation


func _cmd_inspect_game() -> Dictionary:
	"""Comprehensive game inspection - runs all diagnostics and reports all anomalies.
	Use this for autonomous overnight testing to detect any issues."""
	var report := {
		"timestamp": Time.get_unix_time_from_system(),
		"health": {},
		"job_anomalies": [],
		"terrain_anomalies": [],
		"unit_anomalies": [],
		"visual_anomalies": [],
		"summary": {
			"total_issues": 0,
			"critical": 0,
			"warnings": 0,
		},
	}

	# 1. Health check
	report.health = _cmd_get_health()
	if report.health.get("frozen", false):
		report.summary.critical += 1
		report.summary.total_issues += 1
	if report.health.get("fps_avg", 60) < 30:
		report.summary.warnings += 1
		report.summary.total_issues += 1
	if report.health.get("memory_mb", 0) > 2000:
		report.summary.warnings += 1
		report.summary.total_issues += 1

	# 2. Job anomalies
	var job_result: Dictionary = _cmd_get_job_anomalies()
	report.job_anomalies = job_result.get("anomalies", [])
	report.summary.total_issues += report.job_anomalies.size()
	for anomaly in report.job_anomalies:
		if "stalled" in anomaly.get("issues", []):
			report.summary.warnings += 1
		if "no_workers_in_progress" in anomaly.get("issues", []):
			report.summary.warnings += 1

	# 3. Terrain anomalies
	var terrain_result: Dictionary = _cmd_get_terrain_anomalies({})
	report.terrain_anomalies = terrain_result.get("anomalies", [])
	for anomaly in report.terrain_anomalies:
		report.summary.total_issues += 1
		if anomaly.get("type") == "terrain_spike":
			report.summary.critical += 1  # Spikes are critical
		else:
			report.summary.warnings += 1

	# 4. Unit anomalies
	for unit in get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(unit):
			continue

		var issues: Array = []

		# Check for stuck units (not moving when should be)
		if "has_move_order" in unit and unit.has_move_order:
			if "velocity" in unit and unit.velocity.length() < 0.1:
				issues.append("stuck_while_moving")

		# Check for units at wrong height
		if unit.global_position.y < -10 or unit.global_position.y > 500:
			issues.append("invalid_height")

		# Check for dead units still active
		if "current_health" in unit and unit.current_health <= 0:
			issues.append("dead_but_active")

		# Check for units outside map bounds
		if abs(unit.global_position.x) > 1000 or abs(unit.global_position.z) > 1000:
			issues.append("out_of_bounds")

		if not issues.is_empty():
			report.unit_anomalies.append({
				"name": unit.name,
				"position": _vec3_to_array(unit.global_position),
				"issues": issues,
			})
			report.summary.total_issues += 1
			report.summary.warnings += 1

	# 5. Visual anomalies (objects at wrong positions, missing visuals)
	# Check flattening decals
	var flattening_system = get_node_or_null("/root/TerrainFlatteningSystem")
	if flattening_system and "_operations" in flattening_system:
		for key in flattening_system._operations:
			var op = flattening_system._operations[key]
			if op.decal_mesh and is_instance_valid(op.decal_mesh):
				var aabb: AABB = op.decal_mesh.get_aabb() if op.decal_mesh.mesh else AABB()
				# Check for extremely tall meshes (like the green tower)
				if aabb.size.y > 50:
					report.visual_anomalies.append({
						"type": "giant_mesh",
						"name": op.decal_mesh.name,
						"position": _vec3_to_array(op.center),
						"aabb_height": aabb.size.y,
						"target_height": op.target_height,
					})
					report.summary.total_issues += 1
					report.summary.critical += 1

	# Check clearing zones
	var tree_manager = get_node_or_null("/root/TreeNodeManager")
	if tree_manager and "_active_zones" in tree_manager:
		for zone in tree_manager._active_zones:
			if not is_instance_valid(zone):
				continue
			# Check for zones with visual issues
			if zone.global_position.y > 100 or zone.global_position.y < -50:
				report.visual_anomalies.append({
					"type": "zone_wrong_height",
					"name": zone.name,
					"position": _vec3_to_array(zone.global_position),
				})
				report.summary.total_issues += 1
				report.summary.warnings += 1

	return report


func _cmd_get_terrain_anomalies(args: Dictionary) -> Dictionary:
	"""Detect terrain height anomalies (spikes, unusual heights) around active jobs"""
	var anomalies: Array = []
	var sample_radius: float = args.get("radius", 50.0)
	var spike_threshold: float = args.get("spike_threshold", 20.0)  # Height diff to consider a spike

	# Get terrain reference
	var terrain_intg = get_node_or_null("/root/TerrainIntegration")
	var terrain_mgr = terrain_intg.terrain_manager if terrain_intg and "terrain_manager" in terrain_intg else null
	var heightmap = terrain_mgr.heightmap if terrain_mgr and "heightmap" in terrain_mgr else null

	if not heightmap:
		# Try scene-local terrain via group
		for node in get_tree().get_nodes_in_group("terrain_managers"):
			if node.has_method("get_height_at"):
				terrain_mgr = node
				break

	if not terrain_mgr and not heightmap:
		return {"error": "No terrain system found"}

	# Check around active flattening jobs
	var flattening_system = get_node_or_null("/root/TerrainFlatteningSystem")
	var flatten_positions: Array = []

	if flattening_system and "_operations" in flattening_system:
		for key in flattening_system._operations:
			var op = flattening_system._operations[key]
			flatten_positions.append({
				"center": op.center,
				"size": op.size,
				"target_height": op.target_height,
				"progress": op.progress,
			})

	# Sample heights around each flatten operation
	for op_data in flatten_positions:
		var center: Vector3 = op_data.center
		var target_h: float = op_data.target_height
		var heights: Array = []
		var max_height: float = -9999.0
		var min_height: float = 9999.0
		var spike_found: bool = false
		var spike_pos: Vector3 = Vector3.ZERO

		# Sample in a grid
		var step: float = 5.0
		var x: float = -sample_radius
		while x <= sample_radius:
			var z: float = -sample_radius
			while z <= sample_radius:
				var world_pos := center + Vector3(x, 0, z)
				var h: float = 0.0

				if heightmap and heightmap.has_method("sample_world"):
					h = heightmap.sample_world(world_pos.x, world_pos.z)
				elif terrain_mgr and terrain_mgr.has_method("get_height_at"):
					h = terrain_mgr.get_height_at(world_pos)

				heights.append(h)
				if h > max_height:
					max_height = h
					if h - target_h > spike_threshold:
						spike_found = true
						spike_pos = world_pos
				if h < min_height:
					min_height = h

				z += step
			x += step

		# Calculate average
		var avg_height: float = 0.0
		for h in heights:
			avg_height += h
		avg_height /= heights.size() if heights.size() > 0 else 1.0

		# Check for anomaly
		var height_range: float = max_height - min_height
		if spike_found or height_range > spike_threshold:
			anomalies.append({
				"type": "terrain_spike" if spike_found else "high_variance",
				"position": [center.x, center.y, center.z],
				"target_height": target_h,
				"max_height": max_height,
				"min_height": min_height,
				"avg_height": avg_height,
				"height_range": height_range,
				"spike_position": [spike_pos.x, spike_pos.y, spike_pos.z] if spike_found else null,
				"spike_height_diff": max_height - target_h if spike_found else 0.0,
				"progress": op_data.progress,
			})

	return {
		"count": anomalies.size(),
		"anomalies": anomalies,
		"flatten_operations": flatten_positions.size(),
		"timestamp": Time.get_unix_time_from_system(),
	}


func _cmd_get_job_progress_history(args: Dictionary) -> Dictionary:
	"""Get progress history for a specific job or all jobs with stall detection"""
	var job_id: int = args.get("job_id", -1)
	var current_time: float = Time.get_unix_time_from_system()

	if job_id >= 0:
		# Single job history
		if job_id in _job_progress_snapshots:
			return {
				"job_id": job_id,
				"snapshots": _job_progress_snapshots[job_id],
			}
		return {"error": "No history for job_id: %d" % job_id}

	# All jobs summary with stall detection
	var job_summaries: Array = []

	for jid in _job_progress_snapshots:
		var snapshots: Array = _job_progress_snapshots[jid]
		if snapshots.is_empty():
			continue

		var first_snap: Dictionary = snapshots[0]
		var last_snap: Dictionary = snapshots[snapshots.size() - 1]
		var time_span: float = last_snap.time - first_snap.time
		var progress_delta: float = last_snap.progress - first_snap.progress

		var is_stalled: bool = false
		if time_span > 10.0 and progress_delta < 0.01:  # <1% progress in 10+ seconds
			is_stalled = true

		job_summaries.append({
			"job_id": jid,
			"current_progress": last_snap.progress,
			"progress_rate": progress_delta / time_span if time_span > 0 else 0.0,
			"time_span": time_span,
			"snapshot_count": snapshots.size(),
			"is_stalled": is_stalled,
			"current_workers": last_snap.workers,
		})

	return {
		"job_count": job_summaries.size(),
		"jobs": job_summaries,
		"timestamp": current_time,
	}


# ============================================================================
# UNIT CONTROL
# ============================================================================

func _cmd_select_group(args: Dictionary) -> Dictionary:
	var group: String = args.get("group", "player_units")

	if not _selection_manager:
		return {"error": "SelectionManager not found"}

	if _selection_manager.has_method("clear_selection"):
		_selection_manager.clear_selection()

	var count := 0
	for unit in get_tree().get_nodes_in_group(group):
		if _selection_manager.has_method("add_to_selection"):
			_selection_manager.add_to_selection(unit)
			count += 1

	return {"selected": count}


func _cmd_select_unit(args: Dictionary) -> Dictionary:
	var unit_name: String = args.get("name", "")

	if not _selection_manager:
		return {"error": "SelectionManager not found"}

	var unit := _find_unit_by_name(unit_name)
	if not unit:
		return {"error": "Unit not found: %s" % unit_name}

	if _selection_manager.has_method("clear_selection"):
		_selection_manager.clear_selection()
	if _selection_manager.has_method("add_to_selection"):
		_selection_manager.add_to_selection(unit)

	return {"selected": unit.name}


func _cmd_move_to(args: Dictionary) -> Dictionary:
	var pos_array: Array = args.get("position", [0, 0, 0])
	var target := Vector3(pos_array[0], pos_array[1], pos_array[2])

	var moved := 0
	var units := _get_selected_units()

	for unit in units:
		if unit.has_method("move_to"):
			unit.move_to(target)
			moved += 1

	return {"units_moving": moved, "target": pos_array}


func _cmd_attack_move(args: Dictionary) -> Dictionary:
	var pos_array: Array = args.get("position", [0, 0, 0])
	var target := Vector3(pos_array[0], pos_array[1], pos_array[2])

	var moved := 0
	var units := _get_selected_units()

	for unit in units:
		if unit.has_method("attack_move_to"):
			unit.attack_move_to(target)
			moved += 1

	return {"units_attack_moving": moved, "target": pos_array}


func _cmd_stop() -> Dictionary:
	var stopped := 0
	var units := _get_selected_units()

	for unit in units:
		if unit.has_method("stop"):
			unit.stop()
			stopped += 1
		elif "has_move_order" in unit:
			unit.has_move_order = false
			stopped += 1

	return {"stopped": stopped}


# ============================================================================
# CONSTRUCTION
# ============================================================================

func _cmd_paint_clearing(args: Dictionary) -> Dictionary:
	var center_array: Array = args.get("center", [0, 0, 0])
	var center := Vector3(center_array[0], center_array[1], center_array[2])
	var radius: float = args.get("radius", 15.0)

	if not _job_system:
		return {"error": "JobSystem not found"}

	# Create clearing job via JobSystem
	var job_id: String = ""
	if _job_system.has_method("create_clearing_job"):
		var job = _job_system.create_clearing_job(center, radius)
		if job and "job_id" in job:
			job_id = str(job.job_id)
	elif _job_system.has_method("create_job"):
		# Try generic create_job with CLEAR_TERRAIN type
		var job = _job_system.create_job(0, center, Vector2(radius * 2, radius * 2))  # Type 0 = CLEAR
		if job and "job_id" in job:
			job_id = str(job.job_id)

	var area := PI * radius * radius
	return {"job_created": job_id, "center": center_array, "radius": radius, "area_m2": area}


func _cmd_place_building(args: Dictionary) -> Dictionary:
	var building_type_str: String = args.get("type", "bunker")
	var pos_array: Array = args.get("position", [0, 0, 0])
	var position := Vector3(pos_array[0], pos_array[1], pos_array[2])
	var rotation: float = args.get("rotation", 0.0)

	if not _job_system:
		return {"error": "JobSystem not found"}

	# Map string type to BuildingType enum
	var building_type: int = _get_building_type_from_string(building_type_str)
	if building_type == -1:
		return {"error": "Unknown building type: %s" % building_type_str}

	# Get building data for footprint
	var BuildingDataClass = preload("res://firebase_system/building_data.gd")
	var data = BuildingDataClass.get_building_data(building_type)
	if not data:
		return {"error": "No data for building type: %s" % building_type_str}

	# Create build job via JobSystem (skip validation for daemon testing)
	var job = _job_system.create_build_job(position, building_type, rotation, data.footprint_size, true)

	if job:
		return {"job_created": str(job.job_id), "type": building_type_str, "position": pos_array}
	else:
		return {"error": "Failed to create build job", "type": building_type_str}


func _get_building_type_from_string(type_str: String) -> int:
	"""Map building type string to BuildingType enum value"""
	var BuildingDataClass = preload("res://firebase_system/building_data.gd")
	match type_str.to_lower():
		# Firebase Perimeter
		"sandbag", "sandbag_light": return BuildingDataClass.BuildingType.SANDBAG_LIGHT
		"sandbag_heavy": return BuildingDataClass.BuildingType.SANDBAG_HEAVY
		"bunker": return BuildingDataClass.BuildingType.BUNKER
		"sandbag_bunker": return BuildingDataClass.BuildingType.SANDBAG_BUNKER
		"conex_bunker": return BuildingDataClass.BuildingType.CONEX_BUNKER
		"mg_nest", "machine_gun_nest": return BuildingDataClass.BuildingType.MACHINE_GUN_NEST
		"mortar_pit": return BuildingDataClass.BuildingType.MORTAR_PIT
		"wire", "wire_obstacle": return BuildingDataClass.BuildingType.WIRE_OBSTACLE
		"triple_wire", "triple_concertina": return BuildingDataClass.BuildingType.TRIPLE_CONCERTINA
		"claymore", "claymore_line": return BuildingDataClass.BuildingType.CLAYMORE_LINE
		"watchtower": return BuildingDataClass.BuildingType.WATCHTOWER
		# Firebase Support
		"helipad": return BuildingDataClass.BuildingType.HELIPAD
		"psp_helipad": return BuildingDataClass.BuildingType.PSP_HELIPAD
		"supply_depot": return BuildingDataClass.BuildingType.SUPPLY_DEPOT
		"medical", "aid_station": return BuildingDataClass.BuildingType.MEDICAL_STATION
		"toc": return BuildingDataClass.BuildingType.TOC
		"commo_bunker": return BuildingDataClass.BuildingType.COMMO_BUNKER
		# Firebase Living
		"hootch": return BuildingDataClass.BuildingType.HOOTCH
		"mess_hall": return BuildingDataClass.BuildingType.MESS_HALL
		"observation_tower": return BuildingDataClass.BuildingType.OBSERVATION_TOWER
		# Firebase Heavy
		"artillery_pit": return BuildingDataClass.BuildingType.ARTILLERY_PIT
		"howitzer_105": return BuildingDataClass.BuildingType.HOWITZER_PIT_105MM
		"howitzer_155": return BuildingDataClass.BuildingType.HOWITZER_PIT_155MM
		"tank_revetment": return BuildingDataClass.BuildingType.TANK_REVETMENT
		_: return -1


func _cmd_cancel_job(args: Dictionary) -> Dictionary:
	var job_id: String = args.get("job_id", "")

	if not _job_system:
		return {"error": "JobSystem not found"}

	if _job_system.has_method("cancel_job"):
		_job_system.cancel_job(job_id)
		return {"cancelled": job_id}

	return {"error": "cancel_job method not found"}


# ============================================================================
# SPAWNING
# ============================================================================

func _cmd_spawn_engineer(args: Dictionary) -> Dictionary:
	var pos_array: Array = args.get("position", [20, 0, 20])
	var position := Vector3(pos_array[0], pos_array[1], pos_array[2])

	# Find the current scene and try to spawn via its method
	var scene_root := get_tree().current_scene
	if scene_root and scene_root.has_method("_spawn_engineer"):
		scene_root._spawn_engineer(position)
		return {"spawned": true, "position": pos_array}

	return {"error": "No _spawn_engineer method in current scene"}


func _cmd_spawn_bulldozer(args: Dictionary) -> Dictionary:
	var pos_array: Array = args.get("position", [25, 0, 20])
	var position := Vector3(pos_array[0], pos_array[1], pos_array[2])

	# Find the current scene and try to spawn via its method
	var scene_root := get_tree().current_scene
	if scene_root and scene_root.has_method("_spawn_bulldozer"):
		scene_root._spawn_bulldozer(position)
		return {"spawned": true, "position": pos_array}

	return {"error": "No _spawn_bulldozer method in current scene"}


# ============================================================================
# OBSERVATION
# ============================================================================

func _cmd_screenshot(args: Dictionary) -> Dictionary:
	var filename: String = args.get("filename", "screenshot_%d.png" % Time.get_unix_time_from_system())
	var filepath := "user://test_daemon/%s" % filename

	# Get viewport and capture
	var viewport := get_viewport()
	if viewport:
		await RenderingServer.frame_post_draw
		var img := viewport.get_texture().get_image()
		var error := img.save_png(filepath)
		if error == OK:
			return {"saved": filepath, "size": [img.get_width(), img.get_height()]}
		else:
			return {"error": "Failed to save screenshot", "code": error}

	return {"error": "No viewport available"}


func _cmd_wait_seconds(args: Dictionary) -> Dictionary:
	var duration: float = args.get("duration", 1.0)
	# Note: This is a non-blocking "acknowledgment" - Claude should poll state
	return {"waiting": duration, "note": "Poll get_state to check progress"}


func _cmd_clear_commands() -> Dictionary:
	_processed_ids.clear()

	if FileAccess.file_exists(COMMANDS_FILE):
		DirAccess.remove_absolute(COMMANDS_FILE)
	if FileAccess.file_exists(RESULTS_FILE):
		DirAccess.remove_absolute(RESULTS_FILE)

	return {"cleared": true, "commands_processed": _command_count}


# ============================================================================
# MULTI-PHASE TESTING COMMANDS
# ============================================================================

func _cmd_spawn_unit(args: Dictionary) -> Dictionary:
	"""Spawn a unit of specified type at position"""
	var unit_type: String = args.get("type", "us_rifle_squad")
	var pos_array: Array = args.get("position", [100, 0, 100])
	var position := Vector3(pos_array[0], pos_array[1], pos_array[2])
	var faction_str: String = args.get("faction", "US_ARMY")
	var count: int = args.get("count", 1)

	# Map faction string to enum
	var faction: int = 0  # US_ARMY
	match faction_str.to_upper():
		"ARVN": faction = 1
		"VC": faction = 2
		"NVA": faction = 3

	var scene_root := get_tree().current_scene
	if not scene_root:
		return {"error": "No current scene"}

	var spawned_ids: Array = []

	# Try scene-specific spawning methods first
	match unit_type.to_lower():
		"engineer", "engineers", "us_engineers":
			if scene_root.has_method("_spawn_engineer"):
				for i in count:
					var offset := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
					scene_root._spawn_engineer(position + offset)
					spawned_ids.append("engineer_%d" % i)
				return {"spawned": spawned_ids, "type": unit_type, "count": count}

		"bulldozer", "us_bulldozer":
			if scene_root.has_method("_spawn_bulldozer"):
				for i in count:
					var offset := Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
					scene_root._spawn_bulldozer(position + offset)
					spawned_ids.append("bulldozer_%d" % i)
				return {"spawned": spawned_ids, "type": unit_type, "count": count}

	# Try generic unit spawning via UnitSpawner or direct Squad creation
	var unit_spawner = get_node_or_null("/root/UnitSpawner")
	if unit_spawner and unit_spawner.has_method("spawn_unit"):
		for i in count:
			var offset := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
			var unit = unit_spawner.spawn_unit(unit_type, position + offset, faction)
			if unit:
				spawned_ids.append(unit.name)
		return {"spawned": spawned_ids, "type": unit_type, "count": count}

	# Try loading squad data and creating directly
	var squad_data_path := _get_squad_data_path(unit_type)
	if squad_data_path.is_empty():
		return {"error": "Unknown unit type: %s" % unit_type}

	var squad_data = load(squad_data_path)
	if not squad_data:
		return {"error": "Failed to load data for: %s" % unit_type}

	for i in count:
		var squad := Squad.new()
		squad.name = "%s_%d" % [unit_type, Engine.get_process_frames()]
		squad.data = squad_data
		var offset := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		squad.position = position + offset
		scene_root.add_child(squad)
		spawned_ids.append(squad.name)

	return {"spawned": spawned_ids, "type": unit_type, "count": count}


func _get_squad_data_path(unit_type: String) -> String:
	"""Map unit type string to squad data resource path"""
	match unit_type.to_lower():
		"us_rifle", "us_rifle_squad", "rifle_squad":
			return "res://battle_system/data/units/us_rifle_platoon.tres"
		"us_engineers", "engineer":
			return "res://battle_system/data/units/us_engineers.tres"
		"us_bulldozer", "bulldozer":
			return "res://battle_system/data/units/us_bulldozer.tres"
		"vc_infantry", "vc_rifle", "vc_squad":
			return "res://battle_system/data/units/vc_infantry.tres"
		"nva_infantry", "nva_rifle", "nva_squad":
			return "res://battle_system/data/units/nva_infantry.tres"
		"huey", "huey_slick", "uh1":
			return "res://battle_system/data/units/us_huey_slick.tres"
		"m35", "m35_truck", "cargo_truck":
			return "res://battle_system/data/units/us_m35_truck.tres"
		_:
			return ""


func _cmd_create_clearing_job(args: Dictionary) -> Dictionary:
	"""Create a terrain clearing job at center with size"""
	var center_array: Array = args.get("center", [100, 100])
	var size_array: Array = args.get("size", [30, 30])

	if not _job_system:
		return {"error": "JobSystem not found"}

	var center := Vector3(center_array[0], 0, center_array[1]) if center_array.size() == 2 else Vector3(center_array[0], center_array[1], center_array[2])
	var size := Vector2(size_array[0], size_array[1])

	# Get terrain height at center
	var terrain_intg = get_node_or_null("/root/TerrainIntegration")
	if terrain_intg and terrain_intg.terrain_manager and terrain_intg.terrain_manager.heightmap:
		center.y = terrain_intg.terrain_manager.heightmap.sample_world(center.x, center.z)

	var job = _job_system.create_job(0, center, size)  # Type 0 = CLEAR_TERRAIN
	if job:
		return {
			"job_id": job.job_id,
			"type": "CLEAR_TERRAIN",
			"center": _vec3_to_array(center),
			"size": [size.x, size.y],
		}

	return {"error": "Failed to create clearing job"}


func _cmd_create_landing_zone(args: Dictionary) -> Dictionary:
	"""Create a helicopter landing zone at position"""
	var pos_array: Array = args.get("position", [100, 100])
	var position := Vector3(pos_array[0], 0, pos_array[1]) if pos_array.size() == 2 else Vector3(pos_array[0], pos_array[1], pos_array[2])

	# Try InsertionManager to create LZ
	var insertion_mgr = get_node_or_null("/root/InsertionManager")
	if insertion_mgr and insertion_mgr.has_method("create_lz"):
		var lz = insertion_mgr.create_lz(position)
		if lz:
			return {"created": true, "lz_name": lz.name, "position": _vec3_to_array(position)}

	# Try placing a helipad building instead
	if _job_system and _job_system.has_method("create_build_job"):
		var BuildingDataClass = preload("res://firebase_system/building_data.gd")
		var job = _job_system.create_build_job(
			position,
			BuildingDataClass.BuildingType.HELIPAD,
			0.0,
			Vector2(15, 15),
			true
		)
		if job:
			return {"created": true, "job_id": job.job_id, "type": "helipad_build_job", "position": _vec3_to_array(position)}

	return {"error": "InsertionManager not found and build job failed"}


func _cmd_order_attack(args: Dictionary) -> Dictionary:
	"""Order a unit to attack-move to target position"""
	var unit_name: String = args.get("unit_name", "")
	var target_array: Array = args.get("target_position", [0, 0, 0])
	var target := Vector3(target_array[0], target_array[1], target_array[2])

	var unit := _find_unit_by_name(unit_name)
	if not unit:
		return {"error": "Unit not found: %s" % unit_name}

	if unit.has_method("attack_move_to"):
		unit.attack_move_to(target)
		return {"ordered": unit_name, "target": target_array, "order": "attack_move"}
	elif unit.has_method("move_to"):
		unit.move_to(target)
		return {"ordered": unit_name, "target": target_array, "order": "move", "note": "attack_move not available"}

	return {"error": "Unit has no move methods"}


func _cmd_order_garrison(args: Dictionary) -> Dictionary:
	"""Order a unit to garrison a building"""
	var unit_name: String = args.get("unit_name", "")
	var building_name: String = args.get("building_name", "")

	var unit := _find_unit_by_name(unit_name)
	if not unit:
		return {"error": "Unit not found: %s" % unit_name}

	# Find building by name
	var building: Node3D = null
	for node in get_tree().get_nodes_in_group("buildings"):
		if node.name == building_name:
			building = node
			break

	if not building:
		return {"error": "Building not found: %s" % building_name}

	if unit.has_method("garrison"):
		unit.garrison(building)
		return {"ordered": unit_name, "building": building_name, "order": "garrison"}
	elif unit.has_method("enter_building"):
		unit.enter_building(building)
		return {"ordered": unit_name, "building": building_name, "order": "enter_building"}

	return {"error": "Unit has no garrison method"}


func _cmd_get_unit_status(args: Dictionary) -> Dictionary:
	"""Get detailed status of a specific unit"""
	var unit_name: String = args.get("unit_name", "")

	var unit := _find_unit_by_name(unit_name)
	if not unit:
		return {"error": "Unit not found: %s" % unit_name}

	var status := {
		"name": unit.name,
		"position": _vec3_to_array(unit.global_position),
		"alive": true,
		"health": 100.0,
		"max_health": 100.0,
		"state": "unknown",
		"in_combat": false,
		"target": null,
		"squad_size": 1,
	}

	# Check for health
	if "current_health" in unit:
		status.health = unit.current_health
	if "max_health" in unit:
		status.max_health = unit.max_health
	if "health" in unit:
		status.health = unit.health

	# Check for squad data
	if "data" in unit and unit.data:
		if "squad_size" in unit.data:
			status.squad_size = unit.data.squad_size

	# Check for state
	if "state" in unit:
		status.state = str(unit.state)
	if "current_state" in unit:
		status.state = str(unit.current_state)

	# Check for combat state
	if "in_combat" in unit:
		status.in_combat = unit.in_combat
	if "current_target" in unit and is_instance_valid(unit.current_target):
		status.target = unit.current_target.name

	# Check if unit is dead
	if status.health <= 0:
		status.alive = false

	return status


func _cmd_get_combat_status() -> Dictionary:
	"""Get status of all active combat engagements"""
	var combat_mgr = get_node_or_null("/root/CombatManager")

	var status := {
		"timestamp": Time.get_unix_time_from_system(),
		"active_engagements": 0,
		"units_in_combat": [],
		"recent_casualties": [],
	}

	if combat_mgr:
		if "active_engagements" in combat_mgr:
			status.active_engagements = combat_mgr.active_engagements.size() if combat_mgr.active_engagements is Array else 0
		if combat_mgr.has_method("get_combat_summary"):
			var summary = combat_mgr.get_combat_summary()
			if summary is Dictionary:
				status.merge(summary, true)

	# Check all units for combat state
	for unit in get_tree().get_nodes_in_group("player_units"):
		if not is_instance_valid(unit):
			continue
		if "in_combat" in unit and unit.in_combat:
			status.units_in_combat.append(unit.name)

	for unit in get_tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(unit):
			continue
		if "in_combat" in unit and unit.in_combat:
			status.units_in_combat.append(unit.name)

	return status


func _cmd_get_firebase_supply() -> Dictionary:
	"""Get current firebase supply levels"""
	var result := {
		"timestamp": Time.get_unix_time_from_system(),
		"global_supply": 0,
		"firebases": [],
	}

	# Try SupplyManager
	if _supply_manager:
		if _supply_manager.has_method("get_global_supply"):
			result.global_supply = _supply_manager.get_global_supply()
		if _supply_manager.has_method("get_all_depots"):
			var depots = _supply_manager.get_all_depots()
			for depot in depots:
				if is_instance_valid(depot):
					result.firebases.append({
						"name": depot.name,
						"supply": depot.current_supply if "current_supply" in depot else 0,
						"max_supply": depot.max_supply if "max_supply" in depot else 0,
					})

	# Also check scene root for supply tracking
	var scene_root := get_tree().current_scene
	if scene_root and "current_supply" in scene_root:
		result.global_supply = scene_root.current_supply

	return result


func _cmd_wait_job_complete(args: Dictionary) -> Dictionary:
	"""Check job completion status (non-blocking - poll this repeatedly)"""
	var job_id: int = args.get("job_id", -1)

	if not _job_system:
		return {"error": "JobSystem not found"}

	if job_id < 0:
		return {"error": "Invalid job_id"}

	var job = _job_system.get_job(job_id) if _job_system.has_method("get_job") else null

	if not is_instance_valid(job):
		return {"completed": true, "job_id": job_id, "reason": "job_removed"}

	var state: int = job.state if "state" in job else -1
	# COMPLETE = 3, CANCELLED = 4, FAILED = 5
	if state >= 3:
		var state_name: String = "COMPLETE" if state == 3 else ("CANCELLED" if state == 4 else "FAILED")
		return {"completed": true, "job_id": job_id, "final_state": state_name}

	# Not done yet - caller should poll again
	var progress: float = job.get_progress() if job.has_method("get_progress") else 0.0
	var workers: int = job.assigned_workers.size() if "assigned_workers" in job else 0
	return {"completed": false, "job_id": job_id, "progress": progress, "workers": workers, "poll_again": true}


# ============================================================================
# HELPERS
# ============================================================================

func _get_selected_units() -> Array[Node3D]:
	var units: Array[Node3D] = []
	if _selection_manager and "selected_units" in _selection_manager:
		for unit in _selection_manager.selected_units:
			if unit is Node3D:
				units.append(unit)
	return units


func _find_unit_by_name(unit_name: String) -> Node3D:
	for unit in get_tree().get_nodes_in_group("player_units"):
		if unit.name == unit_name:
			return unit as Node3D
	return null


func _vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
