extends Node
## Supply Chain Manager - Automatic road construction between Supply Depots.
##
## Serves Pillar 3 (Physical Supply Chains) - Auto-connects depots with roads
## so convoys have paved routes for efficient supply delivery.
##
## When a Supply Depot completes construction, this system:
## 1. Finds the nearest existing depot
## 2. Plans a route with waypoints every 20m
## 3. Creates BUILD_ROAD jobs for workers to construct

const UnifiedJobClass = preload("res://firebase_system/job_system/unified_job.gd")
const BuildingDataClass = preload("res://firebase_system/building_data.gd")

## Signals
signal road_construction_started(from_pos: Vector3, to_pos: Vector3)
signal road_construction_completed(from_pos: Vector3, to_pos: Vector3)
signal depot_registered(depot: Node3D, is_main_base: bool)
signal depot_unregistered(depot: Node3D)

## Constants
const ROAD_SEGMENT_LENGTH: float = 20.0  # Meters per road segment job
const ROAD_WIDTH: float = 6.0  # Width of constructed roads
const MIN_ROAD_DISTANCE: float = 10.0  # Don't build roads shorter than this

## Tracked Supply Depots
var _supply_depots: Array[Node3D] = []
var _main_base_depot: Node3D = null

## Pending road construction jobs for tracking completion
## Key: from_pos string, Value: {to_pos: Vector3, jobs: Array[int], completed: int}
var _pending_roads: Dictionary = {}

## Reference to systems
var _job_system: Node = null
var _road_network: Node = null


func _ready() -> void:
	add_to_group("supply_chain_managers")

	# Get system references
	_job_system = get_node_or_null("/root/JobSystem")
	_road_network = get_node_or_null("/root/RoadNetwork")

	# Connect to JobSystem for completion tracking
	if _job_system:
		if _job_system.has_signal("job_completed"):
			_job_system.job_completed.connect(_on_job_completed)
		print("[SupplyChainManager] Connected to JobSystem")
	else:
		push_warning("[SupplyChainManager] JobSystem not found - road construction disabled")

	# Connect to BattleSignals for construction events
	if BattleSignals:
		BattleSignals.construction_complete.connect(_on_construction_complete)
		print("[SupplyChainManager] Connected to BattleSignals.construction_complete")

	# Connect to JobSystem for BUILD_STRUCTURE job creation
	# This triggers road building IMMEDIATELY when depot is placed (not waiting for completion)
	if _job_system and _job_system.has_signal("job_created"):
		_job_system.job_created.connect(_on_job_created)
		print("[SupplyChainManager] Connected to JobSystem.job_created")

	print("[SupplyChainManager] Initialized")


## =============================================================================
## JOB CREATION HANDLING (Triggers road building immediately when depot placed)
## =============================================================================

func _on_job_created(job: UnifiedJobClass) -> void:
	"""Handle new job creation - trigger road building when supply depot is placed"""
	if not is_instance_valid(job):
		return

	# Only care about BUILD_STRUCTURE jobs
	if job.job_type != UnifiedJobClass.Type.BUILD_STRUCTURE:
		return

	# Check if this is a Supply Depot
	var building_type: int = job.metadata.get("building_type", -1)
	if _is_supply_depot_type(building_type):
		var depot_pos: Vector3 = job.center
		print("[SupplyChainManager] Supply depot build job created at %v - triggering road construction" % depot_pos)

		# Trigger road building immediately (don't wait for construction to complete)
		_auto_build_road_to_position(depot_pos)


func _is_supply_depot_type(building_type: int) -> bool:
	"""Check if building type is a Supply Depot"""
	return building_type == BuildingDataClass.BuildingType.SUPPLY_DEPOT


## =============================================================================
## JOB COMPLETION HANDLING
## =============================================================================

func _on_job_completed(job: UnifiedJobClass) -> void:
	"""Handle completed jobs - check if Supply Depot or road segment"""
	if not is_instance_valid(job):
		return

	# Check for road completion
	if job.job_type == UnifiedJobClass.Type.BUILD_ROAD:
		_check_road_completion(job)


func _on_construction_complete(building: Node3D) -> void:
	"""Handle completed building construction - register depot for tracking"""
	if not is_instance_valid(building):
		return

	# Check if this is a Supply Depot
	var building_type: int = -1

	# Try to get building type from metadata or property
	if building.has_meta("building_type"):
		building_type = building.get_meta("building_type")
	elif "building_type" in building:
		building_type = building.building_type

	# Check if it's a Supply Depot
	if _is_supply_depot_type(building_type):
		_register_depot(building)


## =============================================================================
## DEPOT REGISTRATION
## =============================================================================

func _register_depot(depot: Node3D) -> void:
	"""Register a new Supply Depot and trigger auto-road building"""
	if not is_instance_valid(depot):
		return

	if depot in _supply_depots:
		print("[SupplyChainManager] Depot already registered: %s" % depot.name)
		return

	var is_main_base: bool = false

	# First depot becomes main base
	if _main_base_depot == null:
		_main_base_depot = depot
		is_main_base = true
		print("[SupplyChainManager] Main base depot established at %v" % depot.global_position)

	_supply_depots.append(depot)
	depot_registered.emit(depot, is_main_base)

	print("[SupplyChainManager] Supply depot registered: %s at %v (total: %d)" % [
		depot.name, depot.global_position, _supply_depots.size()
	])

	# Auto-build road to nearest existing depot (if not the first depot)
	if _supply_depots.size() > 1:
		_auto_build_road_to_depot(depot.global_position)


func _unregister_depot(depot: Node3D) -> void:
	"""Remove a destroyed or removed depot from tracking"""
	if depot in _supply_depots:
		_supply_depots.erase(depot)
		depot_unregistered.emit(depot)

		# If main base was destroyed, promote next oldest depot
		if depot == _main_base_depot:
			if _supply_depots.is_empty():
				_main_base_depot = null
				push_warning("[SupplyChainManager] Main base depot destroyed, no depots remaining")
			else:
				_main_base_depot = _supply_depots[0]
				print("[SupplyChainManager] Main base depot destroyed, promoted: %s" % _main_base_depot.name)

		print("[SupplyChainManager] Supply depot unregistered: %s (remaining: %d)" % [
			depot.name, _supply_depots.size()
		])


## =============================================================================
## AUTO-ROAD BUILDING
## =============================================================================

func _auto_build_road_to_position(new_depot_pos: Vector3) -> void:
	"""Build a road from a new depot position to the nearest firebase or existing depot.
	Called when the depot BUILD JOB is created (before construction completes)."""

	# Find nearest target: either a firebase or an existing depot
	var target_pos: Vector3 = Vector3.ZERO
	var target_name: String = ""
	var target_dist: float = INF

	# Fallback anchor: nearest firebase IGNORING MIN_ROAD_DISTANCE (i.e. the
	# depot's own parent firebase). Used only when no proper anchor is found so
	# a lone firebase's first depot still produces a BUILD_ROAD job for the
	# bulldozer instead of silently returning with nothing to cut.
	var fallback_pos: Vector3 = Vector3.ZERO
	var fallback_name: String = ""
	var fallback_dist: float = INF

	# Check firebases first (using EntityCache for efficiency)
	var entity_cache: Node = get_node_or_null("/root/EntityCache")
	if entity_cache and entity_cache.has_method("get_nearest_firebase"):
		var firebase: Node = entity_cache.get_nearest_firebase(new_depot_pos, false)
		if is_instance_valid(firebase):
			var dist: float = new_depot_pos.distance_to(firebase.global_position)
			# Remember as fallback anchor even when closer than MIN_ROAD_DISTANCE.
			if dist > 2.0 and dist < fallback_dist:
				fallback_pos = firebase.global_position
				fallback_name = str(firebase.name) if firebase.name else "firebase"
				fallback_dist = dist
			if dist > MIN_ROAD_DISTANCE and dist < target_dist:
				target_pos = firebase.global_position
				target_name = str(firebase.name) if firebase.name else "firebase"
				target_dist = dist

	# Also check existing depots (might be closer)
	var nearest_depot: Node3D = _find_nearest_depot(new_depot_pos)
	if is_instance_valid(nearest_depot):
		var depot_dist: float = new_depot_pos.distance_to(nearest_depot.global_position)
		if depot_dist > MIN_ROAD_DISTANCE and depot_dist < target_dist:
			target_pos = nearest_depot.global_position
			target_name = str(nearest_depot.name) if nearest_depot.name else "depot"
			target_dist = depot_dist

	# No proper anchor beyond MIN_ROAD_DISTANCE - fall back to the parent
	# firebase so the first road is still tasked. Only give up if there is
	# genuinely nothing to anchor to.
	if target_dist == INF:
		if fallback_dist < INF:
			target_pos = fallback_pos
			target_name = fallback_name + " (fallback anchor)"
			target_dist = fallback_dist
			push_warning("[SupplyChainManager] No depot/firebase beyond %.0fm of %v; anchoring first road to nearest firebase '%s' at %.1fm" % [
				MIN_ROAD_DISTANCE, new_depot_pos, fallback_name, fallback_dist
			])
		else:
			push_warning("[SupplyChainManager] No firebase or depot to anchor a road from %v (searched EntityCache nearest firebase + %d registered depots)" % [
				new_depot_pos, _supply_depots.size()
			])
			return

	# Plan and create road
	var waypoints: Array[Vector3] = _plan_road_route(new_depot_pos, target_pos)
	if waypoints.size() < 2:
		push_warning("[SupplyChainManager] Failed to plan route to %s" % target_name)
		return

	print("[SupplyChainManager] Auto-building road from depot at %v to %s (%.1fm, %d segments)" % [
		new_depot_pos, target_name, target_dist, waypoints.size() - 1
	])

	# Create road jobs (JobSystem auto-creates CLEAR_TERRAIN prerequisites for jungle)
	_create_road_jobs(waypoints, new_depot_pos, target_pos)
	road_construction_started.emit(new_depot_pos, target_pos)


func _auto_build_road_to_depot(new_depot_pos: Vector3) -> void:
	"""Build a road from the new depot to the nearest existing depot.
	Called when depot construction COMPLETES."""
	var nearest_depot: Node3D = _find_nearest_depot(new_depot_pos)

	if not is_instance_valid(nearest_depot):
		print("[SupplyChainManager] No existing depot to connect to")
		return

	var nearest_pos: Vector3 = nearest_depot.global_position
	var distance: float = new_depot_pos.distance_to(nearest_pos)

	# Skip if too short
	if distance < MIN_ROAD_DISTANCE:
		print("[SupplyChainManager] Distance too short for road: %.1fm" % distance)
		return

	# Plan the route with waypoints
	var waypoints: Array[Vector3] = _plan_road_route(new_depot_pos, nearest_pos)

	if waypoints.size() < 2:
		push_warning("[SupplyChainManager] Failed to plan route")
		return

	print("[SupplyChainManager] Planning road from new depot to %s (%.1fm, %d waypoints)" % [
		nearest_depot.name, distance, waypoints.size()
	])

	# Create road jobs
	_create_road_jobs(waypoints, new_depot_pos, nearest_pos)

	road_construction_started.emit(new_depot_pos, nearest_pos)


func _find_nearest_depot(from_pos: Vector3) -> Node3D:
	"""Find the nearest existing depot (excluding the one at from_pos)"""
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for depot: Node3D in _supply_depots:
		if not is_instance_valid(depot):
			continue

		var dist: float = depot.global_position.distance_to(from_pos)

		# Skip self (depot at same position)
		if dist < 5.0:
			continue

		if dist < nearest_dist:
			nearest_dist = dist
			nearest = depot

	return nearest


func _plan_road_route(from_pos: Vector3, to_pos: Vector3) -> Array[Vector3]:
	"""Plan a road route between two positions with regular waypoints.
	Currently uses direct route; future: pathfinding around obstacles."""
	var waypoints: Array[Vector3] = []

	# Calculate distance and number of segments
	var distance: float = from_pos.distance_to(to_pos)
	var segment_count: int = maxi(1, ceili(distance / ROAD_SEGMENT_LENGTH))

	# Create waypoints at regular intervals
	for i: int in range(segment_count + 1):
		var t: float = float(i) / float(segment_count)
		var waypoint: Vector3 = from_pos.lerp(to_pos, t)

		# Sample terrain height
		waypoint.y = _get_terrain_height(waypoint)

		waypoints.append(waypoint)

	return waypoints


func _get_terrain_height(pos: Vector3) -> float:
	"""Get terrain height at position"""
	var terrain: Node = get_node_or_null("/root/UnifiedTerrain")
	if not terrain:
		terrain = get_node_or_null("/root/TerrainIntegration")

	if terrain and terrain.has_method("get_height_at"):
		return terrain.get_height_at(pos)

	return pos.y


## =============================================================================
## ROAD JOB CREATION
## =============================================================================

func _create_road_jobs(waypoints: Array[Vector3], from_pos: Vector3, to_pos: Vector3) -> void:
	"""Create BUILD_ROAD jobs for each segment of the route"""
	if not _job_system:
		push_warning("[SupplyChainManager] No JobSystem - cannot create road jobs")
		return

	if waypoints.size() < 2:
		return

	var job_ids: Array[int] = []

	# Create a job for each segment
	for i: int in range(waypoints.size() - 1):
		var segment_start: Vector3 = waypoints[i]
		var segment_end: Vector3 = waypoints[i + 1]

		# Create segment path points
		var path_points: PackedVector3Array = PackedVector3Array()
		path_points.append(segment_start)
		path_points.append(segment_end)

		# Create the road job via JobSystem
		var job: UnifiedJobClass = null

		if _job_system.has_method("create_road_job"):
			job = _job_system.create_road_job(
				path_points,
				ROAD_WIDTH,
				UnifiedJobClass.Priority.NORMAL
			)
		else:
			# Fallback: create job manually
			var center: Vector3 = segment_start.lerp(segment_end, 0.5)
			var length: float = segment_start.distance_to(segment_end)
			var size := Vector2(length, ROAD_WIDTH)

			job = _job_system.create_job(
				UnifiedJobClass.Type.BUILD_ROAD,
				center,
				size,
				UnifiedJobClass.Priority.NORMAL
			)
			if job:
				job.metadata["path_points"] = path_points

		if job:
			job_ids.append(job.job_id)
			print("[SupplyChainManager] Created road segment job #%d: %v -> %v" % [
				job.job_id, segment_start, segment_end
			])

	# Track pending road for completion notification
	var road_key: String = _make_road_key(from_pos, to_pos)
	_pending_roads[road_key] = {
		"from_pos": from_pos,
		"to_pos": to_pos,
		"job_ids": job_ids,
		"completed": 0,
		"total": job_ids.size()
	}

	print("[SupplyChainManager] Created %d road segment jobs" % job_ids.size())


func _make_road_key(from_pos: Vector3, to_pos: Vector3) -> String:
	"""Create a unique key for a pending road"""
	return "%d_%d_%d_%d" % [
		int(from_pos.x), int(from_pos.z),
		int(to_pos.x), int(to_pos.z)
	]


func _check_road_completion(job: UnifiedJobClass) -> void:
	"""Check if a completed road job completes a pending road"""
	var job_id: int = job.job_id

	for road_key: String in _pending_roads:
		var road_data: Dictionary = _pending_roads[road_key]
		var job_ids: Array = road_data.get("job_ids", [])

		if job_id in job_ids:
			road_data["completed"] = road_data.get("completed", 0) + 1

			# Check if all segments complete
			if road_data["completed"] >= road_data["total"]:
				var from_pos: Vector3 = road_data.get("from_pos", Vector3.ZERO)
				var to_pos: Vector3 = road_data.get("to_pos", Vector3.ZERO)

				print("[SupplyChainManager] Road construction complete: %v -> %v" % [from_pos, to_pos])
				road_construction_completed.emit(from_pos, to_pos)

				# Register the road with RoadNetwork
				_register_road_with_network(from_pos, to_pos)

				# Clean up tracking
				_pending_roads.erase(road_key)

			break


func _register_road_with_network(from_pos: Vector3, to_pos: Vector3) -> void:
	"""Register the completed road with RoadNetwork for pathfinding"""
	if not _road_network:
		return

	# Create road segment in the network
	if _road_network.has_method("create_segment_from_positions"):
		var segment_id: int = _road_network.create_segment_from_positions(
			from_pos,
			to_pos,
			_road_network.RoadType.LATERITE  # Red clay road
		)
		print("[SupplyChainManager] Registered road segment #%d with RoadNetwork" % segment_id)


## =============================================================================
## PUBLIC API
## =============================================================================

func get_depot_count() -> int:
	"""Get number of registered supply depots"""
	return _supply_depots.size()


func get_main_base() -> Node3D:
	"""Get the main base depot (first established)"""
	return _main_base_depot


func get_all_depots() -> Array[Node3D]:
	"""Get all registered supply depots"""
	var result: Array[Node3D] = []
	for depot: Node3D in _supply_depots:
		if is_instance_valid(depot):
			result.append(depot)
	return result


func find_nearest_depot_to(position: Vector3) -> Node3D:
	"""Find the nearest depot to a given position"""
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for depot: Node3D in _supply_depots:
		if not is_instance_valid(depot):
			continue

		var dist: float = depot.global_position.distance_to(position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = depot

	return nearest


func manually_register_depot(depot: Node3D) -> void:
	"""Manually register a depot (for existing depots at mission start)"""
	_register_depot(depot)


func force_build_road(from_pos: Vector3, to_pos: Vector3) -> void:
	"""Force build a road between two positions (manual override)"""
	var waypoints: Array[Vector3] = _plan_road_route(from_pos, to_pos)
	if waypoints.size() >= 2:
		_create_road_jobs(waypoints, from_pos, to_pos)
		road_construction_started.emit(from_pos, to_pos)


## =============================================================================
## CLEANUP
## =============================================================================

func _process(_delta: float) -> void:
	"""Periodic cleanup of invalid depots"""
	# Run cleanup every ~60 frames
	if Engine.get_process_frames() % 60 != 0:
		return

	# Remove destroyed depots
	var to_remove: Array[Node3D] = []
	for depot: Node3D in _supply_depots:
		if not is_instance_valid(depot):
			to_remove.append(depot)

	for depot: Node3D in to_remove:
		_unregister_depot(depot)


func reset() -> void:
	"""Reset all tracking (for scene reload)"""
	_supply_depots.clear()
	_main_base_depot = null
	_pending_roads.clear()
	print("[SupplyChainManager] Reset")


## =============================================================================
## STATISTICS
## =============================================================================

func get_stats() -> Dictionary:
	"""Get supply chain statistics"""
	return {
		"depot_count": _supply_depots.size(),
		"has_main_base": _main_base_depot != null,
		"pending_roads": _pending_roads.size(),
	}


func print_stats() -> void:
	"""Print supply chain statistics"""
	var stats: Dictionary = get_stats()
	print("[SupplyChainManager] Stats:")
	print("  Depots: %d" % stats.depot_count)
	print("  Main Base: %s" % ("Yes" if stats.has_main_base else "No"))
	print("  Pending Roads: %d" % stats.pending_roads)
