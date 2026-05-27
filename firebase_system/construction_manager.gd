extends Node
## ConstructionManager - Autoload singleton
## Access via: ConstructionManager.build_immediately(firebase, type)
##
## ROLE CLARIFICATION (2026-05-19):
## - ConstructionManager handles ConstructionZone system (firebase building slots)
## - JobSystem handles clearing/building jobs via WorkerController
## - Worker assignment handled by WorkerController (bottom-up job finding)
##
## This manager handles:
## - Construction queues for firebase zones
## - ConstructionZone work processing
## - Creating firebases

signal construction_queued(firebase: Node3D, building_type: int)
signal construction_started(firebase: Node3D, zone: Node3D)
signal construction_progress(zone: Node3D, progress: float)
signal construction_complete(firebase: Node3D, building: Node3D)
signal construction_failed(firebase: Node3D, reason: String)

const Firebase = preload("res://firebase_system/firebase.gd")
const ConstructionZone = preload("res://firebase_system/construction_zone.gd")
const BuildingData = preload("res://firebase_system/building_data.gd")
const UnifiedJob = preload("res://firebase_system/job_system/unified_job.gd")

## Construction queue (per firebase)
var construction_queues: Dictionary = {}  # firebase -> Array of building_types

## Active constructions
var active_constructions: Array[ConstructionZone] = []

## Active jobs (for the new job system)
var active_jobs: Array[UnifiedJob] = []

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
	# NOTE: Job processing handled by JobSystem and WorkerController
	_process_queues()
	# NOTE: Worker assignment is handled by WorkerController (bottom-up job finding)
	# Workers autonomously find and claim available jobs - no manual assignment needed


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


func _process_job_nodes(_delta: float) -> void:
	"""DEPRECATED: Job processing now handled by JobSystem and WorkerController"""
	pass


func _auto_assign_workers_to_jobs() -> void:
	"""DEPRECATED: Worker assignment now handled by WorkerController (bottom-up job finding)"""
	pass


func _get_worker_class(worker: Node3D) -> String:
	"""Determine if a worker is an engineer or bulldozer"""
	if worker.has_method("get"):
		var data: Resource = worker.get("data")
		if data:
			if "is_vehicle" in data and data.is_vehicle:
				return "bulldozer"
	return "engineer"


func _find_idle_workers_for_job(_position: Vector3, _required_class: String) -> Array[Node3D]:
	"""DEPRECATED: Worker finding now handled by WorkerController"""
	return []


func _is_worker_assigned_to_job(_worker: Node3D) -> bool:
	"""DEPRECATED: Job assignment now handled by WorkerController"""
	return false


func _send_worker_to_job(_worker: Node3D, _job: UnifiedJob) -> void:
	"""DEPRECATED: Worker movement now handled by WorkerController"""
	pass


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

	# Check supply affordability via SupplyManager (single source of truth)
	var supply_mgr := get_node_or_null("/root/SupplyManager")
	if supply_mgr and supply_mgr.has_method("can_afford"):
		if not supply_mgr.can_afford(data.supply_cost):
			construction_failed.emit(firebase, "Insufficient supplies")
			return false
	elif firebase.supply_level < data.supply_cost:
		# Fallback to firebase supply_level if SupplyManager unavailable
		construction_failed.emit(firebase, "Insufficient supplies")
		return false

	# Check terrain clearing if required
	if data.requires_cleared_terrain:
		var clearing_system: Node = get_node_or_null("/root/TerrainClearingSystem")
		if clearing_system and not clearing_system.is_cleared(zone.global_position):
			# Instead of failing, route through JobSystem which handles prerequisites
			var job_system := get_node_or_null("/root/JobSystem")
			if job_system:
				print("[ConstructionManager] Terrain not cleared - creating job with prerequisites")
				var job: UnifiedJob = job_system.create_build_job(
					zone.global_position,
					building_type,
					0.0,  # rotation
					data.footprint_size
				)
				if job:
					# Store zone reference for when job completes
					job.metadata["construction_zone"] = zone
					job.metadata["firebase"] = firebase
					register_job(job)
					# Emit progress signal instead of failure
					construction_queued.emit(firebase, building_type)
					return true  # Job created successfully, will auto-clear then build
			# Fallback if JobSystem not available
			construction_failed.emit(firebase, "Terrain not cleared")
			return false

	# Consume supply via SupplyManager (single source of truth)
	# Note: supply_mgr already fetched at line 162
	if supply_mgr and supply_mgr.has_method("consume_global_supply"):
		if not supply_mgr.consume_global_supply(data.supply_cost):
			construction_failed.emit(firebase, "Insufficient supplies")
			return false
	else:
		# Fallback to firebase supply_level if SupplyManager unavailable
		firebase.supply_level -= data.supply_cost

	# Start construction
	zone.start_construction(data)
	active_constructions.append(zone)

	construction_started.emit(firebase, zone)

	# Emit supply consumed signal for HUD updates
	if BattleSignals:
		BattleSignals.supply_consumed.emit(firebase, data.supply_cost, data.display_name)

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


func reset() -> void:
	"""Reset all construction state for scene reloads.
	Called by test scenes to clear persisted autoload state."""
	# Clear queues
	construction_queues.clear()

	# Cancel active constructions
	for zone in active_constructions:
		if is_instance_valid(zone):
			zone.cancel_construction()
	active_constructions.clear()

	# Clear active jobs (JobSystem handles the actual job cleanup)
	active_jobs.clear()

	# Clear building container
	if is_instance_valid(_building_container):
		for child in _building_container.get_children():
			child.queue_free()

	print("[ConstructionManager] Reset - cleared all construction state")


func cancel_construction(zone: ConstructionZone) -> void:
	"""Cancel construction on a zone"""
	if zone in active_constructions:
		active_constructions.erase(zone)
		zone.cancel_construction()


## =============================================================================
## JOB INTEGRATION (New JobSystem)
## =============================================================================

func register_job(job: UnifiedJob) -> void:
	"""Register a job for tracking"""
	if job and job not in active_jobs:
		active_jobs.append(job)
		print("[ConstructionManager] Registered job #%d: %s" % [
			job.job_id, UnifiedJob.get_type_name(job.job_type)
		])


func unregister_job(job: UnifiedJob) -> void:
	"""Unregister a job"""
	if job in active_jobs:
		active_jobs.erase(job)


func enqueue_build_with_prerequisites(
	position: Vector3,
	building_type: int,
	rotation: float = 0.0,
	footprint_size: Vector2 = Vector2(4.0, 4.0)
) -> UnifiedJob:
	"""Create a build job via JobSystem with automatic clear/flatten prerequisites.
	This is the preferred method for construction as it handles terrain clearing automatically."""
	var job_system := get_node_or_null("/root/JobSystem")
	if not job_system:
		push_error("[ConstructionManager] JobSystem not found")
		return null

	# Use create_build_job which handles prerequisites (CLEAR_TERRAIN → FLATTEN_AREA → BUILD)
	var job: UnifiedJob = job_system.create_build_job(
		position,
		building_type,
		rotation,
		footprint_size
	)

	if job:
		register_job(job)
		print("[ConstructionManager] Enqueued build job #%d with prerequisites for building type %d" % [
			job.job_id, building_type
		])

	return job


func get_active_job_count() -> int:
	"""Get number of active jobs"""
	var count := 0
	for job in active_jobs:
		if is_instance_valid(job):
			count += 1
	return count


func _on_job_completed(job: UnifiedJob) -> void:
	"""Handle job completion"""
	unregister_job(job)
	print("[ConstructionManager] Job #%d completed" % job.job_id)


func _on_job_cancelled(job: UnifiedJob) -> void:
	"""Handle job cancellation"""
	unregister_job(job)


## =============================================================================
## BUILDING SPAWNING (Called by ConstructionSiteNode on completion)
## =============================================================================

var _building_container: Node3D = null

func _get_building_container() -> Node3D:
	"""Get or create container for spawned buildings"""
	if not is_instance_valid(_building_container):
		_building_container = Node3D.new()
		_building_container.name = "Buildings"
		get_tree().current_scene.add_child(_building_container)
	return _building_container


func spawn_building_at(world_position: Vector3, building_type: int, rotation_y: float = 0.0) -> Node3D:
	"""Spawn a completed building at the given position.
	Called by ConstructionSiteNode when construction completes."""

	# Get building data
	var data: BuildingData = BuildingData.get_building_data(building_type)
	var display_name: String = data.display_name if data else "Building"

	# Look up model path from ConstructionZone.BUILDING_MODELS
	var model_path: String = ""
	if building_type in ConstructionZone.BUILDING_MODELS:
		model_path = ConstructionZone.BUILDING_MODELS[building_type]

	# Try to load the model
	var building: Node3D = null
	if not model_path.is_empty() and ResourceLoader.exists(model_path):
		var scene: PackedScene = load(model_path)
		if scene:
			building = scene.instantiate()
			building.name = display_name.replace(" ", "_")
			print("[ConstructionManager] Spawned %s from %s" % [display_name, model_path])

	# Fallback to placeholder box if model not found
	if not building:
		building = _create_placeholder_building(data, building_type)
		print("[ConstructionManager] Created placeholder for %s (model not found: %s)" % [display_name, model_path])

	# Position and rotate
	building.position = world_position
	building.rotation.y = rotation_y

	# Add to container
	_get_building_container().add_child(building)

	# Add to buildings group for easy lookup
	building.add_to_group("buildings")
	building.add_to_group("player_buildings")

	# Store building type as metadata
	building.set_meta("building_type", building_type)
	building.set_meta("building_data", data)

	# Initialize defensive structures with fire arc data from BuildingData
	if building.has_method("initialize_from_building_data") and data:
		building.initialize_from_building_data(data)

	# HQ BUILDING ACTIVATION: If this is an HQ building (TOC), create/activate a firebase
	if data and data.is_hq_building:
		_handle_hq_building_completion(building, data, world_position)

	return building


func _handle_hq_building_completion(hq_building: Node3D, building_data: BuildingData, world_position: Vector3) -> void:
	"""Handle HQ building (TOC) completion - create or activate firebase.
	When a TOC completes construction, it creates a firebase zone that enables
	other buildings to be placed within its influence radius."""
	print("[ConstructionManager] HQ building completed at %v - activating firebase" % world_position)

	# Check if there's already a firebase at this location
	var existing_firebase: Node = null
	for fb in get_tree().get_nodes_in_group("firebases"):
		if not is_instance_valid(fb):
			continue
		var dist: float = fb.global_position.distance_to(world_position)
		if dist < 20.0:  # Within 20m = same firebase
			existing_firebase = fb
			break

	if existing_firebase:
		# Activate existing firebase with this HQ
		print("[ConstructionManager] Found existing firebase '%s' - activating with HQ" % (
			existing_firebase.firebase_name if "firebase_name" in existing_firebase else "unknown"
		))
		if existing_firebase.has_method("_activate_with_hq"):
			existing_firebase._activate_with_hq(hq_building, building_data)
	else:
		# Create new firebase centered on the TOC
		print("[ConstructionManager] Creating new firebase for HQ building")
		var Firebase = load("res://firebase_system/firebase.gd")
		if Firebase:
			var firebase: Node3D = Firebase.new()
			firebase.name = "Firebase_" + str(get_tree().get_nodes_in_group("firebases").size())
			firebase.position = world_position
			firebase.firebase_name = "Firebase " + _get_firebase_phonetic_name()

			# Add to scene tree
			_get_building_container().add_child(firebase)

			# Activate with the HQ building
			if firebase.has_method("_activate_with_hq"):
				firebase._activate_with_hq(hq_building, building_data)

			print("[ConstructionManager] Created and activated firebase '%s' with %.0fm influence" % [
				firebase.firebase_name, building_data.influence_radius
			])


func _get_firebase_phonetic_name() -> String:
	"""Generate a phonetic alphabet name for the firebase (Alpha, Bravo, etc.)"""
	var names: Array[String] = [
		"Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot",
		"Golf", "Hotel", "India", "Juliet", "Kilo", "Lima",
		"Mike", "November", "Oscar", "Papa", "Quebec", "Romeo",
		"Sierra", "Tango", "Uniform", "Victor", "Whiskey", "X-Ray",
		"Yankee", "Zulu"
	]
	var index: int = get_tree().get_nodes_in_group("firebases").size()
	if index < names.size():
		return names[index]
	return "Firebase" + str(index)


func _create_placeholder_building(data: BuildingData, building_type: int) -> Node3D:
	"""Create a colored placeholder box for buildings without models"""
	var placeholder := Node3D.new()
	placeholder.name = "Placeholder_" + str(building_type)

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()

	# Size from building data or default
	var size := Vector3(4, 3, 4)
	if data:
		size = Vector3(data.footprint_size.x, 3.0, data.footprint_size.y)

	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position.y = size.y * 0.5  # Raise to sit on ground

	# Color based on building category
	var mat := StandardMaterial3D.new()
	var category: int = data.category if data else 0
	match category:
		BuildingData.BuildingCategory.FIREBASE_PERIMETER:
			mat.albedo_color = Color(0.6, 0.5, 0.4)  # Brown
		BuildingData.BuildingCategory.FIREBASE_SUPPORT:
			mat.albedo_color = Color(0.4, 0.6, 0.4)  # Green
		BuildingData.BuildingCategory.FIREBASE_LIVING:
			mat.albedo_color = Color(0.5, 0.5, 0.6)  # Gray-blue
		BuildingData.BuildingCategory.FIREBASE_HEAVY:
			mat.albedo_color = Color(0.5, 0.4, 0.3)  # Dark brown
		_:
			mat.albedo_color = Color(0.5, 0.5, 0.5)  # Gray

	mesh_instance.material_override = mat
	placeholder.add_child(mesh_instance)

	return placeholder


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
