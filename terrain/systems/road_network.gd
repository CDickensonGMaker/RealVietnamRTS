extends Node
## Road Network - Waypoint-based road system for supply convoys.
##
## Serves Pillar 3 (Physical Supply Chains) - Roads are the arteries of logistics.
## Convoys move faster on intact roads; cratered roads slow or block passage.
##
## Integration points:
##   - SupplyTruck calls find_path() for route generation
##   - ConvoyManager queries road state for route planning
##   - DamageSystem calls damage_road_at() when explosions hit roads
##   - EngineeringSystem calls repair_road_segment() for repairs

signal road_damaged(segment_id: int, position: Vector3)
signal road_repaired(segment_id: int)
signal road_blocked(segment_id: int)
signal path_found(from: Vector3, to: Vector3, waypoints: Array[Vector3])

## Road segment state
enum RoadState {
	INTACT,      # Full speed (1.25x terrain bonus)
	DAMAGED,     # Reduced speed (0.75x)
	CRATERED,    # Severely damaged (0.4x), needs engineer repair
	BLOCKED,     # Impassable until cleared
}

## Road type affects base speed multiplier
enum RoadType {
	DIRT_TRAIL,   # 1.0x - basic jungle path
	LATERITE,     # 1.15x - red clay road
	GRAVEL,       # 1.2x - improved surface
	PAVED,        # 1.25x - asphalt/concrete
	PSP_MATTING,  # 1.3x - pierced steel planking (airfield/firebase)
}

## Speed multipliers by road state
const STATE_SPEED_MULT: Dictionary = {
	RoadState.INTACT: 1.0,
	RoadState.DAMAGED: 0.75,
	RoadState.CRATERED: 0.4,
	RoadState.BLOCKED: 0.0,
}

## Speed multipliers by road type (applied when INTACT)
const TYPE_SPEED_MULT: Dictionary = {
	RoadType.DIRT_TRAIL: 1.0,
	RoadType.LATERITE: 1.15,
	RoadType.GRAVEL: 1.2,
	RoadType.PAVED: 1.25,
	RoadType.PSP_MATTING: 1.3,
}

## Repair work required by state (engineer work units)
const REPAIR_WORK_REQUIRED: Dictionary = {
	RoadState.DAMAGED: 20.0,
	RoadState.CRATERED: 50.0,
	RoadState.BLOCKED: 100.0,
}

## Road segment data structure
class RoadSegment:
	var id: int = -1
	var start: Vector3 = Vector3.ZERO
	var end: Vector3 = Vector3.ZERO
	var road_type: int = RoadType.DIRT_TRAIL
	var state: int = RoadState.INTACT
	var repair_progress: float = 0.0
	var length: float = 0.0
	var connected_segments: Array[int] = []
	var is_bridge: bool = false  # True if this segment spans water/ravine
	var spline: RefCounted = null  # Optional TerrainSpline for smooth curves

	func _init(seg_id: int, p_start: Vector3, p_end: Vector3, p_type: int = RoadType.DIRT_TRAIL, p_is_bridge: bool = false) -> void:
		id = seg_id
		start = p_start
		end = p_end
		road_type = p_type
		state = RoadState.INTACT
		repair_progress = 0.0
		length = start.distance_to(end)
		is_bridge = p_is_bridge

	## Get actual length (uses spline if available)
	func get_length() -> float:
		if spline and spline.has_method("get_total_length"):
			return spline.get_total_length()
		return length

	## Set spline for this segment (overrides linear length)
	func set_spline(p_spline: RefCounted) -> void:
		spline = p_spline
		if spline and spline.has_method("get_total_length"):
			length = spline.get_total_length()

	## Get position at distance along segment (uses spline if available)
	func get_position_at_distance(dist: float) -> Vector3:
		if spline and spline.has_method("get_position_at_distance"):
			return spline.get_position_at_distance(dist)
		# Fallback to linear interpolation
		var t: float = clampf(dist / maxf(0.001, length), 0.0, 1.0)
		return start.lerp(end, t)

	## Get tangent at distance (uses spline if available)
	func get_tangent_at_distance(dist: float) -> Vector3:
		if spline and spline.has_method("get_tangent_at_distance"):
			return spline.get_tangent_at_distance(dist)
		# Fallback to linear direction
		return (end - start).normalized()

	## Get midpoint for damage checks
	func get_midpoint() -> Vector3:
		return start.lerp(end, 0.5)

	## Check if a world position is on this segment
	func contains_point(pos: Vector3, tolerance: float = 8.0) -> bool:
		# Project point onto line segment
		var segment_dir: Vector3 = (end - start).normalized()
		var to_point: Vector3 = pos - start
		var projection_length: float = to_point.dot(segment_dir)

		# Check if within segment bounds
		if projection_length < 0.0 or projection_length > length:
			return false

		# Check perpendicular distance
		var closest_point: Vector3 = start + segment_dir * projection_length
		var distance: float = pos.distance_to(closest_point)
		return distance <= tolerance

	## Get speed multiplier for this segment
	func get_speed_multiplier() -> float:
		var state_mult: float = STATE_SPEED_MULT.get(state, 1.0)
		if state == RoadState.INTACT:
			var type_mult: float = TYPE_SPEED_MULT.get(road_type, 1.0)
			return state_mult * type_mult
		return state_mult


## Road waypoint node (intersection or endpoint)
class RoadNode:
	var id: int = -1
	var position: Vector3 = Vector3.ZERO
	var connected_nodes: Array[int] = []  # IDs of connected RoadNodes
	var connected_segments: Array[int] = []  # IDs of connecting RoadSegments

	func _init(node_id: int, pos: Vector3) -> void:
		id = node_id
		position = pos


## Road network data
var _segments: Dictionary = {}  # segment_id -> RoadSegment
var _nodes: Dictionary = {}  # node_id -> RoadNode
var _next_segment_id: int = 0
var _next_node_id: int = 0

## Spatial lookup grid for fast queries
var _segment_grid: Dictionary = {}  # Vector2i -> Array[int] (segment IDs)
const GRID_CELL_SIZE: float = 50.0

## Pathfinding cache (cleared when road state changes)
var _path_cache: Dictionary = {}  # "from_to" string -> Array[Vector3]
const MAX_CACHE_SIZE: int = 100


func _ready() -> void:
	add_to_group("road_networks")
	print("[RoadNetwork] Initialized")


# =============================================================================
# ROAD CREATION API
# =============================================================================

## Create a road node (intersection/endpoint)
func create_node(position: Vector3) -> int:
	var node := RoadNode.new(_next_node_id, position)
	_nodes[_next_node_id] = node
	_next_node_id += 1
	return node.id


## Create a road segment connecting two nodes
func create_segment(start_node_id: int, end_node_id: int, road_type: int = RoadType.DIRT_TRAIL) -> int:
	if not _nodes.has(start_node_id) or not _nodes.has(end_node_id):
		push_warning("[RoadNetwork] Invalid node IDs for segment creation")
		return -1

	var start_node: RoadNode = _nodes[start_node_id]
	var end_node: RoadNode = _nodes[end_node_id]

	var segment := RoadSegment.new(
		_next_segment_id,
		start_node.position,
		end_node.position,
		road_type
	)

	_segments[_next_segment_id] = segment

	# Update node connections
	start_node.connected_nodes.append(end_node_id)
	start_node.connected_segments.append(_next_segment_id)
	end_node.connected_nodes.append(start_node_id)
	end_node.connected_segments.append(_next_segment_id)

	# Add to spatial grid
	_add_segment_to_grid(segment)

	_next_segment_id += 1
	return segment.id


## Create a road segment from raw positions (creates nodes automatically)
func create_segment_from_positions(start: Vector3, end: Vector3, road_type: int = RoadType.DIRT_TRAIL) -> int:
	var start_node_id: int = _find_or_create_node(start)
	var end_node_id: int = _find_or_create_node(end)
	return create_segment(start_node_id, end_node_id, road_type)


## Find existing node near position or create new one
func _find_or_create_node(position: Vector3, merge_radius: float = 5.0) -> int:
	# Check for existing node within merge radius
	for node_id: int in _nodes:
		var node: RoadNode = _nodes[node_id]
		if node.position.distance_to(position) < merge_radius:
			return node_id

	# Create new node
	return create_node(position)


## Add segment to spatial grid for fast lookup
func _add_segment_to_grid(segment: RoadSegment) -> void:
	# Get grid cells that this segment passes through
	var cells: Array[Vector2i] = _get_segment_cells(segment)
	for cell: Vector2i in cells:
		if not _segment_grid.has(cell):
			_segment_grid[cell] = []
		_segment_grid[cell].append(segment.id)


## Get grid cells that a segment passes through
func _get_segment_cells(segment: RoadSegment) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []

	var start_cell := _world_to_grid(segment.start)
	var end_cell := _world_to_grid(segment.end)

	# Bresenham-style line through grid
	var dx: int = absi(end_cell.x - start_cell.x)
	var dz: int = absi(end_cell.y - start_cell.y)
	var sx: int = 1 if start_cell.x < end_cell.x else -1
	var sz: int = 1 if start_cell.y < end_cell.y else -1
	var err: int = dx - dz

	var x: int = start_cell.x
	var z: int = start_cell.y

	while true:
		cells.append(Vector2i(x, z))

		if x == end_cell.x and z == end_cell.y:
			break

		var e2: int = 2 * err
		if e2 > -dz:
			err -= dz
			x += sx
		if e2 < dx:
			err += dx
			z += sz

	return cells


func _world_to_grid(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(pos.x / GRID_CELL_SIZE)),
		int(floor(pos.z / GRID_CELL_SIZE))
	)


# =============================================================================
# PATHFINDING API
# =============================================================================

## Find path along road network between two world positions.
## Returns array of waypoints (Vector3). Empty if no path found.
func find_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	# Check cache first
	var cache_key: String = _make_cache_key(from, to)
	if _path_cache.has(cache_key):
		return _path_cache[cache_key].duplicate()

	# Find nearest road nodes to start/end
	var start_node_id: int = _find_nearest_node(from)
	var end_node_id: int = _find_nearest_node(to)

	if start_node_id == -1 or end_node_id == -1:
		# No road network available - return direct path
		return _make_direct_path(from, to)

	# A* pathfinding on road graph
	var path_node_ids: Array[int] = _astar_path(start_node_id, end_node_id)

	if path_node_ids.is_empty():
		return _make_direct_path(from, to)

	# Convert node IDs to world positions
	var waypoints: Array[Vector3] = []
	waypoints.append(from)  # Start from actual position

	for node_id: int in path_node_ids:
		var node: RoadNode = _nodes[node_id]
		waypoints.append(node.position)

	waypoints.append(to)  # End at actual destination

	# Cache result
	_cache_path(cache_key, waypoints)

	path_found.emit(from, to, waypoints)
	return waypoints


## A* pathfinding on road node graph
func _astar_path(start_id: int, end_id: int) -> Array[int]:
	if start_id == end_id:
		return [start_id]

	var open_set: Array[int] = [start_id]
	var came_from: Dictionary = {}  # node_id -> previous_node_id
	var g_score: Dictionary = {start_id: 0.0}  # node_id -> cost from start
	var f_score: Dictionary = {start_id: _heuristic(start_id, end_id)}

	while not open_set.is_empty():
		# Get node with lowest f_score
		var current: int = _get_lowest_f(open_set, f_score)

		if current == end_id:
			return _reconstruct_path(came_from, current)

		open_set.erase(current)

		var current_node: RoadNode = _nodes[current]
		for i: int in current_node.connected_nodes.size():
			var neighbor_id: int = current_node.connected_nodes[i]
			var segment_id: int = current_node.connected_segments[i]

			# Check if segment is passable
			var segment: RoadSegment = _segments[segment_id]
			if segment.state == RoadState.BLOCKED:
				continue

			# Calculate travel cost (distance / speed multiplier)
			# Uses get_length() which respects spline length if present
			var travel_cost: float = segment.get_length() / maxf(0.1, segment.get_speed_multiplier())
			var tentative_g: float = g_score[current] + travel_cost

			var current_g: float = g_score.get(neighbor_id, INF)
			if tentative_g < current_g:
				came_from[neighbor_id] = current
				g_score[neighbor_id] = tentative_g
				f_score[neighbor_id] = tentative_g + _heuristic(neighbor_id, end_id)

				if neighbor_id not in open_set:
					open_set.append(neighbor_id)

	# No path found
	return []


func _heuristic(from_id: int, to_id: int) -> float:
	var from_pos: Vector3 = _nodes[from_id].position
	var to_pos: Vector3 = _nodes[to_id].position
	return from_pos.distance_to(to_pos)


func _get_lowest_f(open_set: Array[int], f_score: Dictionary) -> int:
	var lowest_id: int = open_set[0]
	var lowest_f: float = f_score.get(lowest_id, INF)

	for node_id: int in open_set:
		var f: float = f_score.get(node_id, INF)
		if f < lowest_f:
			lowest_f = f
			lowest_id = node_id

	return lowest_id


func _reconstruct_path(came_from: Dictionary, current: int) -> Array[int]:
	var path: Array[int] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.insert(0, current)
	return path


## Find nearest road node to a world position
func _find_nearest_node(pos: Vector3, max_distance: float = 100.0) -> int:
	var nearest_id: int = -1
	var nearest_dist: float = max_distance

	for node_id: int in _nodes:
		var node: RoadNode = _nodes[node_id]
		var dist: float = pos.distance_to(node.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_id = node_id

	return nearest_id


## Generate direct path when no road available
func _make_direct_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var distance: float = from.distance_to(to)
	var segments: int = int(distance / 50.0) + 1

	for i: int in range(1, segments + 1):
		var t: float = float(i) / float(segments)
		path.append(from.lerp(to, t))

	return path


func _make_cache_key(from: Vector3, to: Vector3) -> String:
	return "%d_%d_%d_%d" % [
		int(from.x / 10.0), int(from.z / 10.0),
		int(to.x / 10.0), int(to.z / 10.0)
	]


func _cache_path(key: String, path: Array[Vector3]) -> void:
	if _path_cache.size() >= MAX_CACHE_SIZE:
		# Remove oldest entry (first key)
		var first_key: String = _path_cache.keys()[0]
		_path_cache.erase(first_key)
	_path_cache[key] = path


## Invalidate path cache (called when road state changes)
func _invalidate_cache() -> void:
	_path_cache.clear()


# =============================================================================
# ROAD STATE API
# =============================================================================

## Get road segment at world position (or null)
func get_segment_at(pos: Vector3) -> RoadSegment:
	var cell := _world_to_grid(pos)

	# Check this cell and neighbors
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			var check_cell := Vector2i(cell.x + dx, cell.y + dz)
			if _segment_grid.has(check_cell):
				for seg_id: int in _segment_grid[check_cell]:
					var segment: RoadSegment = _segments[seg_id]
					if segment.contains_point(pos):
						return segment

	return null


## Get speed multiplier at world position
func get_speed_multiplier_at(pos: Vector3) -> float:
	var segment: RoadSegment = get_segment_at(pos)
	if segment:
		return segment.get_speed_multiplier()
	return 1.0  # Default terrain speed


## Check if position is on a road
func is_on_road(pos: Vector3) -> bool:
	return get_segment_at(pos) != null


## Damage road at position (called by DamageSystem)
func damage_road_at(pos: Vector3, damage_type: int = 0) -> void:
	var segment: RoadSegment = get_segment_at(pos)
	if not segment:
		return

	# Escalate damage state
	match segment.state:
		RoadState.INTACT:
			segment.state = RoadState.DAMAGED
		RoadState.DAMAGED:
			segment.state = RoadState.CRATERED
		RoadState.CRATERED:
			segment.state = RoadState.BLOCKED

	segment.repair_progress = 0.0
	_invalidate_cache()

	road_damaged.emit(segment.id, pos)

	if segment.state == RoadState.BLOCKED:
		road_blocked.emit(segment.id)


## Damage specific segment by ID
func damage_segment(segment_id: int, new_state: int = -1) -> void:
	if not _segments.has(segment_id):
		return

	var segment: RoadSegment = _segments[segment_id]

	if new_state >= 0:
		segment.state = new_state
	else:
		# Escalate damage
		segment.state = mini(segment.state + 1, RoadState.BLOCKED)

	segment.repair_progress = 0.0
	_invalidate_cache()

	road_damaged.emit(segment_id, segment.get_midpoint())


## Apply repair work to a segment
func repair_segment(segment_id: int, work_amount: float) -> bool:
	if not _segments.has(segment_id):
		return false

	var segment: RoadSegment = _segments[segment_id]

	if segment.state == RoadState.INTACT:
		return true  # Already repaired

	var work_needed: float = REPAIR_WORK_REQUIRED.get(segment.state, 50.0)
	segment.repair_progress += work_amount

	if segment.repair_progress >= work_needed:
		# Repair one state level
		segment.state = maxi(segment.state - 1, RoadState.INTACT)
		segment.repair_progress = 0.0
		_invalidate_cache()

		if segment.state == RoadState.INTACT:
			road_repaired.emit(segment_id)
			return true

	return false


## Get segment by ID
func get_segment(segment_id: int) -> RoadSegment:
	return _segments.get(segment_id, null)


## Get all segments in a radius
func get_segments_in_radius(center: Vector3, radius: float) -> Array[RoadSegment]:
	var result: Array[RoadSegment] = []

	for seg_id: int in _segments:
		var segment: RoadSegment = _segments[seg_id]
		var midpoint: Vector3 = segment.get_midpoint()
		if center.distance_to(midpoint) <= radius:
			result.append(segment)

	return result


# =============================================================================
# QUERY API FOR CONVOY MANAGER
# =============================================================================

## Check if a route between two positions is passable
func is_route_passable(from: Vector3, to: Vector3) -> bool:
	var path: Array[Vector3] = find_path(from, to)
	if path.is_empty():
		return true  # Direct path, always "passable"

	# Check all segments along path
	for i: int in range(path.size() - 1):
		var segment: RoadSegment = get_segment_at(path[i])
		if segment and segment.state == RoadState.BLOCKED:
			return false

	return true


## Get estimated travel time between positions (seconds)
func get_travel_time(from: Vector3, to: Vector3, base_speed: float = 12.0) -> float:
	var path: Array[Vector3] = find_path(from, to)
	var total_time: float = 0.0

	if path.is_empty():
		# Direct path
		return from.distance_to(to) / base_speed

	var prev_pos: Vector3 = from
	for waypoint: Vector3 in path:
		var segment_dist: float = prev_pos.distance_to(waypoint)
		var speed_mult: float = get_speed_multiplier_at(prev_pos.lerp(waypoint, 0.5))
		var segment_speed: float = base_speed * speed_mult
		total_time += segment_dist / maxf(1.0, segment_speed)
		prev_pos = waypoint

	return total_time


## Get blocked segments (for route planning)
func get_blocked_segments() -> Array[RoadSegment]:
	var result: Array[RoadSegment] = []
	for seg_id: int in _segments:
		var segment: RoadSegment = _segments[seg_id]
		if segment.state == RoadState.BLOCKED:
			result.append(segment)
	return result


## Get damaged segments (for repair prioritization)
func get_damaged_segments() -> Array[RoadSegment]:
	var result: Array[RoadSegment] = []
	for seg_id: int in _segments:
		var segment: RoadSegment = _segments[seg_id]
		if segment.state != RoadState.INTACT:
			result.append(segment)
	return result


# =============================================================================
# BULK CREATION API (for map generation)
# =============================================================================

## Create a road segment from a TerrainSpline (smooth terrain-following curve)
func create_segment_from_spline(spline: RefCounted, road_type: int = RoadType.DIRT_TRAIL) -> int:
	"""Create a road segment from a TerrainSpline.

	The spline provides smooth terrain-following curves for natural-looking roads.
	Uses spline endpoints for node connections but stores full spline for navigation.
	"""
	if not spline or not spline.has_method("get_waypoint_count"):
		push_warning("[RoadNetwork] Invalid spline provided")
		return -1

	if spline.get_waypoint_count() < 2:
		push_warning("[RoadNetwork] Spline needs at least 2 waypoints")
		return -1

	# Get start/end from spline waypoints
	var start_pos: Vector3 = spline.get_waypoint(0)
	var end_pos: Vector3 = spline.get_waypoint(spline.get_waypoint_count() - 1)

	# Find or create nodes at endpoints
	var start_node_id: int = _find_or_create_node(start_pos)
	var end_node_id: int = _find_or_create_node(end_pos)

	var start_node: RoadNode = _nodes[start_node_id]
	var end_node: RoadNode = _nodes[end_node_id]

	# Create segment with spline
	var segment := RoadSegment.new(
		_next_segment_id,
		start_node.position,
		end_node.position,
		road_type
	)
	segment.set_spline(spline)

	_segments[_next_segment_id] = segment

	# Update node connections
	start_node.connected_nodes.append(end_node_id)
	start_node.connected_segments.append(_next_segment_id)
	end_node.connected_nodes.append(start_node_id)
	end_node.connected_segments.append(_next_segment_id)

	# Add to spatial grid
	_add_segment_to_grid(segment)

	var seg_id: int = _next_segment_id
	_next_segment_id += 1

	print("[RoadNetwork] Created spline segment #%d (%.1fm)" % [seg_id, segment.get_length()])
	return seg_id


## Create a road from array of positions (for map setup)
func create_road_from_waypoints(waypoints: Array[Vector3], road_type: int = RoadType.DIRT_TRAIL) -> Array[int]:
	var segment_ids: Array[int] = []

	if waypoints.size() < 2:
		return segment_ids

	var prev_pos: Vector3 = waypoints[0]
	for i: int in range(1, waypoints.size()):
		var seg_id: int = create_segment_from_positions(prev_pos, waypoints[i], road_type)
		if seg_id >= 0:
			segment_ids.append(seg_id)
		prev_pos = waypoints[i]

	return segment_ids


## Create a circular road (for firebase perimeter)
func create_circular_road(center: Vector3, radius: float, segments: int = 12, road_type: int = RoadType.GRAVEL) -> Array[int]:
	var segment_ids: Array[int] = []
	var waypoints: Array[Vector3] = []

	for i: int in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		var pos := Vector3(
			center.x + cos(angle) * radius,
			center.y,
			center.z + sin(angle) * radius
		)
		waypoints.append(pos)

	# Close the loop
	waypoints.append(waypoints[0])

	return create_road_from_waypoints(waypoints, road_type)


## Connect two road networks at nearest points
func connect_networks(pos_a: Vector3, pos_b: Vector3, road_type: int = RoadType.DIRT_TRAIL) -> int:
	return create_segment_from_positions(pos_a, pos_b, road_type)


# =============================================================================
# BRIDGE SEGMENT CREATION
# =============================================================================

signal bridge_created(segment_id: int, start: Vector3, end: Vector3)

## Create a bridge segment (special road type that spans gaps)
## Bridges use PSP_MATTING type for military bridge plating
## Returns segment_id or -1 on failure
func create_bridge_segment(start: Vector3, end: Vector3) -> int:
	"""Create a bridge segment spanning water or ravine.

	Bridges are special road segments that:
	- Use PSP_MATTING road type (military steel planking)
	- Are marked as bridges for special handling
	- Can span gaps that regular roads cannot
	- Connect road networks across water/ravines
	"""
	var start_node_id: int = _find_or_create_node(start)
	var end_node_id: int = _find_or_create_node(end)

	if start_node_id == -1 or end_node_id == -1:
		push_warning("[RoadNetwork] Failed to create nodes for bridge segment")
		return -1

	var start_node: RoadNode = _nodes[start_node_id]
	var end_node: RoadNode = _nodes[end_node_id]

	# Create segment with bridge flag
	var segment := RoadSegment.new(
		_next_segment_id,
		start_node.position,
		end_node.position,
		RoadType.PSP_MATTING,  # Military bridge plating
		true  # is_bridge = true
	)

	_segments[_next_segment_id] = segment

	# Update node connections
	start_node.connected_nodes.append(end_node_id)
	start_node.connected_segments.append(_next_segment_id)
	end_node.connected_nodes.append(start_node_id)
	end_node.connected_segments.append(_next_segment_id)

	# Add to spatial grid
	_add_segment_to_grid(segment)

	var seg_id: int = _next_segment_id
	_next_segment_id += 1

	print("[RoadNetwork] Created bridge segment #%d from %v to %v (%.1fm)" % [
		seg_id, start, end, segment.length
	])

	bridge_created.emit(seg_id, start, end)
	return seg_id


## Get all bridge segments in the network
func get_bridge_segments() -> Array[RoadSegment]:
	var result: Array[RoadSegment] = []
	for seg_id: int in _segments:
		var segment: RoadSegment = _segments[seg_id]
		if segment.is_bridge:
			result.append(segment)
	return result


## Check if a segment is a bridge
func is_bridge_segment(segment_id: int) -> bool:
	if not _segments.has(segment_id):
		return false
	return _segments[segment_id].is_bridge


# =============================================================================
# DEBUG / STATS
# =============================================================================

## Get network statistics
func get_stats() -> Dictionary:
	var intact_count: int = 0
	var damaged_count: int = 0
	var blocked_count: int = 0
	var bridge_count: int = 0
	var total_length: float = 0.0

	for seg_id: int in _segments:
		var segment: RoadSegment = _segments[seg_id]
		total_length += segment.get_length()  # Respects spline length
		if segment.is_bridge:
			bridge_count += 1
		match segment.state:
			RoadState.INTACT:
				intact_count += 1
			RoadState.DAMAGED, RoadState.CRATERED:
				damaged_count += 1
			RoadState.BLOCKED:
				blocked_count += 1

	return {
		"total_nodes": _nodes.size(),
		"total_segments": _segments.size(),
		"total_length_meters": total_length,
		"intact_segments": intact_count,
		"damaged_segments": damaged_count,
		"blocked_segments": blocked_count,
		"bridge_segments": bridge_count,
		"cache_size": _path_cache.size(),
	}


## Print network summary
func print_stats() -> void:
	var stats: Dictionary = get_stats()
	print("[RoadNetwork] Stats:")
	print("  Nodes: %d" % stats.total_nodes)
	print("  Segments: %d (%.0fm total)" % [stats.total_segments, stats.total_length_meters])
	print("  Intact: %d, Damaged: %d, Blocked: %d" % [
		stats.intact_segments, stats.damaged_segments, stats.blocked_segments
	])
