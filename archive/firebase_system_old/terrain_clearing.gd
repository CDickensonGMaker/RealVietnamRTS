extends Node
## TerrainClearingSystem - Handles jungle clearing before construction
## Accessed globally via TerrainClearingSystem autoload (no class_name needed)

signal zone_clearing_started(zone: Node3D)
signal zone_clearing_progress(zone: Node3D, progress: float)
signal zone_state_changed(zone: Node3D, new_state: int)
signal tree_felled(position: Vector3, direction: Vector3)

# Clearing rates per engineer per second
const CLEARING_RATES := {
	GameEnums.ClearingState.JUNGLE: 0.5,           # Slow - machetes/chainsaws
	GameEnums.ClearingState.PARTIALLY_CLEARED: 1.0, # Faster - bulldozers
	GameEnums.ClearingState.CLEARED: 0.0,          # Already clear
}

# Napalm instant clear radius
const NAPALM_CLEAR_RADIUS := 20.0

# Active clearing operations
var active_zones: Dictionary = {}  # zone -> { engineers, progress }

func _ready() -> void:
	# Connect to napalm strikes for instant clearing
	BattleSignals.napalm_impact.connect(_on_napalm_impact)
	BattleSignals.jungle_burned.connect(_on_jungle_burned)

func _process(delta: float) -> void:
	_process_clearing_operations(delta)
	_process_road_construction(delta)

# =============================================================================
# ZONE MANAGEMENT
# =============================================================================

func create_clearing_zone(position: Vector3, size: Vector2) -> Node3D:
	## Create a new construction zone that needs clearing
	var zone := Node3D.new()
	zone.set_script(preload("res://firebase_system/construction_zone.gd"))
	zone.global_position = position
	zone.set_meta("size", size)
	zone.set_meta("state", GameEnums.ClearingState.JUNGLE)
	zone.set_meta("clearing_progress", 0.0)
	zone.set_meta("construction_stage", GameEnums.ConstructionStage.FOUNDATION)
	zone.set_meta("construction_progress", 0.0)

	return zone

func get_zone_state(zone: Node3D) -> int:
	return zone.get_meta("state", GameEnums.ClearingState.JUNGLE)

func is_zone_buildable(zone: Node3D) -> bool:
	var state: int = get_zone_state(zone)
	return state >= GameEnums.ClearingState.CLEARED

# =============================================================================
# CLEARING OPERATIONS
# =============================================================================

func assign_engineers_to_clear(zone: Node3D, engineers: Array) -> void:
	## Assign engineers to clear a zone
	if zone not in active_zones:
		active_zones[zone] = { "engineers": [], "progress": 0.0 }
		zone_clearing_started.emit(zone)

	for engineer in engineers:
		if engineer not in active_zones[zone].engineers:
			active_zones[zone].engineers.append(engineer)

func remove_engineers_from_zone(zone: Node3D, engineers: Array) -> void:
	## Remove engineers from clearing duty
	if zone in active_zones:
		for engineer in engineers:
			active_zones[zone].engineers.erase(engineer)

		if active_zones[zone].engineers.is_empty():
			active_zones.erase(zone)

func _process_clearing_operations(delta: float) -> void:
	var completed_zones: Array = []

	for zone in active_zones:
		if not is_instance_valid(zone):
			completed_zones.append(zone)
			continue

		var data: Dictionary = active_zones[zone]
		var state: int = get_zone_state(zone)

		# Can't clear already cleared zones
		if state >= GameEnums.ClearingState.CLEARED:
			completed_zones.append(zone)
			continue

		# Calculate clearing rate
		var rate: float = CLEARING_RATES.get(state, 0.0)
		var engineer_count := 0

		for engineer in data.engineers:
			if is_instance_valid(engineer):
				engineer_count += 1

		if engineer_count == 0:
			continue

		# Progress clearing
		var progress_delta := rate * engineer_count * delta
		data.progress += progress_delta
		zone.set_meta("clearing_progress", data.progress)

		zone_clearing_progress.emit(zone, data.progress)

		# Spawn visual effects (falling trees)
		if randf() < progress_delta * 0.1:
			var zone_size: Vector2 = zone.get_meta("size", Vector2(10, 10))
			var tree_pos: Vector3 = zone.global_position + Vector3(
				randf_range(-zone_size.x/2, zone_size.x/2),
				0,
				randf_range(-zone_size.y/2, zone_size.y/2)
			)
			var fall_dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			tree_felled.emit(tree_pos, fall_dir)
			BattleSignals.tree_felled.emit(tree_pos)

		# Check for state advancement
		if data.progress >= 100.0:
			_advance_zone_state(zone)
			data.progress = 0.0

	# Clean up completed zones
	for zone in completed_zones:
		active_zones.erase(zone)

func _advance_zone_state(zone: Node3D) -> void:
	var current_state: int = get_zone_state(zone)
	var new_state := current_state

	match current_state:
		GameEnums.ClearingState.JUNGLE:
			new_state = GameEnums.ClearingState.PARTIALLY_CLEARED
		GameEnums.ClearingState.PARTIALLY_CLEARED:
			new_state = GameEnums.ClearingState.CLEARED

	zone.set_meta("state", new_state)
	zone.set_meta("clearing_progress", 0.0)

	zone_state_changed.emit(zone, new_state)
	BattleSignals.clearing_complete.emit(zone, new_state)

# =============================================================================
# INSTANT CLEARING (Napalm/Bulldozer)
# =============================================================================

func instant_clear(center: Vector3, radius: float) -> Array:
	## Instantly clear all zones within radius (napalm/bulldozer)
	var cleared_zones: Array = []

	for zone in active_zones:
		if is_instance_valid(zone):
			if zone.global_position.distance_to(center) <= radius:
				zone.set_meta("state", GameEnums.ClearingState.CLEARED)
				zone.set_meta("clearing_progress", 0.0)
				cleared_zones.append(zone)
				zone_state_changed.emit(zone, GameEnums.ClearingState.CLEARED)

	return cleared_zones

func _on_napalm_impact(position: Vector3, radius: float) -> void:
	instant_clear(position, radius)

func _on_jungle_burned(center: Vector3, radius: float) -> void:
	instant_clear(center, radius)

# =============================================================================
# TERRAIN QUERIES
# =============================================================================

func get_terrain_type_at(position: Vector3) -> int:
	## Get terrain type at world position
	# This would interface with the actual terrain/map system
	# For now, return a default
	return GameEnums.TerrainType.SINGLE_CANOPY

func get_clearing_state_at(position: Vector3) -> int:
	## Get clearing state at position
	for zone in active_zones:
		if is_instance_valid(zone):
			var size: Vector2 = zone.get_meta("size", Vector2(10, 10))
			var zone_pos: Vector3 = zone.global_position
			if absf(position.x - zone_pos.x) <= size.x/2:
				if absf(position.z - zone_pos.z) <= size.y/2:
					return get_zone_state(zone)

	return GameEnums.ClearingState.JUNGLE

func get_movement_modifier_at(position: Vector3) -> float:
	## Get movement speed modifier based on terrain
	var terrain := get_terrain_type_at(position)
	return GameEnums.get_terrain_speed_modifier(terrain)


# =============================================================================
# ROAD CONSTRUCTION SYSTEM
# =============================================================================

signal road_construction_started(road_id: int, start: Vector3, end: Vector3)
signal road_construction_progress(road_id: int, progress: float)
signal road_completed(road_id: int, start: Vector3, end: Vector3)

# Road construction rates per engineer per second
const ROAD_CLEARING_RATE := 0.3  # Slower than zone clearing
const ROAD_WIDTH := 8.0          # Wide enough for trucks

# Active road construction projects
var active_roads: Dictionary = {}  # road_id -> RoadData
var completed_roads: Array[Dictionary] = []
var _next_road_id: int = 0

class RoadData:
	var id: int
	var start: Vector3
	var end: Vector3
	var width: float
	var progress: float = 0.0
	var segments_cleared: int = 0
	var total_segments: int = 1
	var engineers: Array = []
	var is_complete: bool = false

	func get_length() -> float:
		return start.distance_to(end)

	func get_current_head() -> Vector3:
		## Get the current construction front
		var t := float(segments_cleared) / float(total_segments)
		return start.lerp(end, t)


func start_road_construction(start: Vector3, end: Vector3, engineers: Array) -> int:
	## Begin constructing a road between two points
	var road := RoadData.new()
	road.id = _next_road_id
	_next_road_id += 1

	road.start = start
	road.end = end
	road.width = ROAD_WIDTH
	road.engineers = engineers.duplicate()

	# Calculate segments based on length
	var length := road.get_length()
	road.total_segments = int(length / 10.0) + 1  # 10m per segment

	active_roads[road.id] = road

	road_construction_started.emit(road.id, start, end)
	BattleSignals.road_construction_started.emit(start, end)

	return road.id


func assign_engineers_to_road(road_id: int, engineers: Array) -> void:
	## Add engineers to road construction
	if not active_roads.has(road_id):
		return

	var road: RoadData = active_roads[road_id]
	for engineer in engineers:
		if engineer not in road.engineers:
			road.engineers.append(engineer)


func remove_engineers_from_road(road_id: int, engineers: Array) -> void:
	## Remove engineers from road construction
	if not active_roads.has(road_id):
		return

	var road: RoadData = active_roads[road_id]
	for engineer in engineers:
		road.engineers.erase(engineer)


func _process_road_construction(delta: float) -> void:
	## Process all active road construction projects
	var completed: Array[int] = []

	for road_id in active_roads:
		var road: RoadData = active_roads[road_id]

		if road.is_complete:
			completed.append(road_id)
			continue

		# Count valid engineers
		var engineer_count := 0
		for engineer in road.engineers:
			if is_instance_valid(engineer):
				engineer_count += 1

		if engineer_count == 0:
			continue

		# Progress construction
		var progress_delta := ROAD_CLEARING_RATE * engineer_count * delta
		road.progress += progress_delta

		# Check segment completion
		var segment_progress := 100.0 / float(road.total_segments)
		while road.progress >= segment_progress and road.segments_cleared < road.total_segments:
			road.segments_cleared += 1
			road.progress -= segment_progress

			# Clear terrain along this segment
			var segment_start := road.start.lerp(road.end, float(road.segments_cleared - 1) / float(road.total_segments))
			var segment_end := road.start.lerp(road.end, float(road.segments_cleared) / float(road.total_segments))
			_clear_road_segment(segment_start, segment_end, road.width)

		# Emit progress
		var total_progress := float(road.segments_cleared) / float(road.total_segments) * 100.0
		road_construction_progress.emit(road_id, total_progress)

		# Check completion
		if road.segments_cleared >= road.total_segments:
			road.is_complete = true
			_finalize_road(road)
			completed.append(road_id)

	# Move completed roads
	for road_id in completed:
		var road: RoadData = active_roads[road_id]
		completed_roads.append({
			"id": road.id,
			"start": road.start,
			"end": road.end,
			"width": road.width,
		})
		active_roads.erase(road_id)
		road_completed.emit(road_id, road.start, road.end)


func _clear_road_segment(start: Vector3, end: Vector3, width: float) -> void:
	## Clear vegetation along a road segment
	# Emit tree felling effects along the segment
	var length := start.distance_to(end)
	var dir := (end - start).normalized()
	var perpendicular := dir.cross(Vector3.UP).normalized()

	var trees_to_fell := int(length / 5.0) + 1
	for i in range(trees_to_fell):
		var t := float(i) / float(trees_to_fell)
		var pos := start.lerp(end, t)
		# Random offset perpendicular to road
		pos += perpendicular * randf_range(-width/2, width/2)

		var fall_dir := perpendicular if randf() > 0.5 else -perpendicular
		tree_felled.emit(pos, fall_dir)
		BattleSignals.tree_felled.emit(pos)


func _finalize_road(road: RoadData) -> void:
	## Complete road construction and register with pathfinding
	# Register with pathfinding cost manager
	if has_node("/root/PathfindingCostManager"):
		var pcm := get_node("/root/PathfindingCostManager")
		if pcm.has_method("register_road_segment"):
			pcm.register_road_segment(road.start, road.end, road.width)

	# Emit completion signal
	BattleSignals.road_completed.emit(road.start, road.end, road.width)

	# Create visual road (if trail network exists)
	if has_node("/root/TrailNetwork"):
		var trail_network := get_node("/root/TrailNetwork")
		if trail_network.has_signal("trail_created"):
			trail_network.emit_signal("trail_created", road.start, road.end, "road")


func is_on_road(position: Vector3) -> bool:
	## Check if a position is on any completed road
	var pos_2d := Vector2(position.x, position.z)

	for road in completed_roads:
		var start_2d := Vector2(road.start.x, road.start.z)
		var end_2d := Vector2(road.end.x, road.end.z)
		var width: float = road.width

		# Point to line segment distance
		var line_dir := (end_2d - start_2d).normalized()
		var to_point := pos_2d - start_2d
		var projection := to_point.dot(line_dir)
		var line_length := start_2d.distance_to(end_2d)

		if projection >= 0 and projection <= line_length:
			var closest := start_2d + line_dir * projection
			if pos_2d.distance_to(closest) <= width * 0.5:
				return true

	return false


func get_road_at(position: Vector3) -> Dictionary:
	## Get road data at position
	var pos_2d := Vector2(position.x, position.z)

	for road in completed_roads:
		var start_2d := Vector2(road.start.x, road.start.z)
		var end_2d := Vector2(road.end.x, road.end.z)
		var width: float = road.width

		var line_dir := (end_2d - start_2d).normalized()
		var to_point := pos_2d - start_2d
		var projection := to_point.dot(line_dir)
		var line_length := start_2d.distance_to(end_2d)

		if projection >= 0 and projection <= line_length:
			var closest := start_2d + line_dir * projection
			if pos_2d.distance_to(closest) <= width * 0.5:
				return road

	return {}
