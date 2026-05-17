## trail_network.gd - Ho Chi Minh Trail and road network generation
## Generates trail networks connecting strategic points
class_name TrailNetwork
extends RefCounted


## =============================================================================
## TRAIL TYPE DEFINITIONS
## =============================================================================
const TRAIL_TYPES: Dictionary = {
	"main_trail": {
		"name": "Main Supply Trail",
		"width": 4.0,
		"visibility": 0.3,
		"speed_bonus": 0.25,
		"vehicle_passable": false,
		"ambush_risk": 0.6,
	},
	"supply_route": {
		"name": "Supply Route",
		"width": 6.0,
		"visibility": 0.5,
		"speed_bonus": 0.35,
		"vehicle_passable": true,
		"ambush_risk": 0.7,
	},
	"footpath": {
		"name": "Footpath",
		"width": 2.0,
		"visibility": 0.1,
		"speed_bonus": 0.15,
		"vehicle_passable": false,
		"ambush_risk": 0.4,
	},
	"road": {
		"name": "Road",
		"width": 8.0,
		"visibility": 1.0,
		"speed_bonus": 0.40,
		"vehicle_passable": true,
		"ambush_risk": 0.8,
	},
	"tunnel": {
		"name": "Underground Tunnel",
		"width": 1.5,
		"visibility": 0.0,
		"speed_bonus": 0.1,
		"vehicle_passable": false,
		"ambush_risk": 0.0,  # Can't be ambushed in tunnels
		"underground": true,
	},
}


## =============================================================================
## HO CHI MINH TRAIL PRESETS
## =============================================================================
const HCM_TRAIL_SEGMENTS: Dictionary = {
	# Main trail segments based on real geography
	"laos_entry_north": {
		"start": Vector2i(-10, -15),
		"end": Vector2i(-5, -10),
		"trail_type": "supply_route",
		"waypoints": [Vector2i(-8, -12)],
	},
	"a_shau_branch": {
		"start": Vector2i(-5, -10),
		"end": Vector2i(0, -5),
		"trail_type": "main_trail",
		"waypoints": [Vector2i(-3, -8), Vector2i(-1, -6)],
	},
	"central_highlands_route": {
		"start": Vector2i(-5, -10),
		"end": Vector2i(-5, 5),
		"trail_type": "supply_route",
		"waypoints": [Vector2i(-6, -5), Vector2i(-5, 0)],
	},
	"cambodia_branch": {
		"start": Vector2i(-5, 5),
		"end": Vector2i(5, 15),
		"trail_type": "supply_route",
		"waypoints": [Vector2i(0, 10)],
	},
}


## =============================================================================
## TRAIL SEGMENT CLASS
## =============================================================================
class TrailSegment:
	var id: String = ""
	var trail_type: String = "footpath"
	var path: Array[Vector2i] = []
	var width: float = 2.0
	var is_active: bool = true
	var damage_level: float = 0.0  # 0-1, from bombing

	func get_properties() -> Dictionary:
		return TRAIL_TYPES.get(trail_type, TRAIL_TYPES["footpath"])

	func get_speed_bonus() -> float:
		var props: Dictionary = get_properties()
		return props.get("speed_bonus", 0.0) * (1.0 - damage_level)

	func can_use_vehicles() -> bool:
		var props: Dictionary = get_properties()
		return props.get("vehicle_passable", false) and damage_level < 0.5


## =============================================================================
## NETWORK STATE
## =============================================================================
static var _segments: Dictionary = {}  # segment_id -> TrailSegment
static var _cell_trails: Dictionary = {}  # Vector2i -> Array of segment_ids


## =============================================================================
## INITIALIZATION
## =============================================================================

## Initialize trail network for a campaign
static func initialize(campaign_id: String) -> void:
	_segments.clear()
	_cell_trails.clear()

	# Generate HCM trail if appropriate campaign
	if campaign_id in ["a_shau", "central_highlands", "ia_drang"]:
		_generate_hcm_trail()

	# Generate local trails based on campaign features
	_generate_local_trails(campaign_id)


## =============================================================================
## TRAIL GENERATION
## =============================================================================

## Generate a trail connecting two points
static func generate_trail(
	start: Vector2i,
	end: Vector2i,
	trail_type: String,
	segment_id: String = ""
) -> TrailSegment:
	var segment := TrailSegment.new()
	segment.id = segment_id if segment_id != "" else _generate_segment_id()
	segment.trail_type = trail_type
	segment.width = TRAIL_TYPES.get(trail_type, {}).get("width", 2.0)

	# Generate path using A* that prefers valleys and jungle cover
	segment.path = _find_trail_path(start, end, trail_type)

	# Register segment
	_segments[segment.id] = segment

	# Register cells along path
	for cell_coords in segment.path:
		if not _cell_trails.has(cell_coords):
			_cell_trails[cell_coords] = []
		_cell_trails[cell_coords].append(segment.id)

		# Update cell data to mark as having trail
		var cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(cell_coords)
		cell.has_trail = true

	return segment


## Generate trail network connecting multiple points
static func generate_trail_network(
	points: Array[Vector2i],
	trail_type: String,
	network_id: String = ""
) -> Array[TrailSegment]:
	var segments: Array[TrailSegment] = []

	for i in range(points.size() - 1):
		var seg_id: String = "%s_%d" % [network_id, i] if network_id != "" else ""
		var segment: TrailSegment = generate_trail(points[i], points[i + 1], trail_type, seg_id)
		segments.append(segment)

	return segments


## =============================================================================
## PATHFINDING FOR TRAILS
## =============================================================================

static func _find_trail_path(
	start: Vector2i,
	end: Vector2i,
	trail_type: String
) -> Array[Vector2i]:
	var open_set: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0.0}
	var f_score: Dictionary = {start: _trail_heuristic(start, end)}

	while not open_set.is_empty():
		# Find node with lowest f_score
		var current: Vector2i = open_set[0]
		var lowest_f: float = f_score.get(current, INF)
		for node in open_set:
			var f: float = f_score.get(node, INF)
			if f < lowest_f:
				lowest_f = f
				current = node

		if current == end:
			return _reconstruct_path(came_from, current)

		open_set.erase(current)

		for neighbor in VietnamWorldGrid.get_neighbors(current):
			var cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(neighbor)

			# Check passability
			if not cell.is_passable and not TRAIL_TYPES.get(trail_type, {}).get("underground", false):
				continue

			# Calculate cost based on terrain suitability for trails
			var terrain_cost: float = _get_trail_terrain_cost(cell.terrain_type, trail_type)
			var tentative_g: float = g_score.get(current, INF) + terrain_cost

			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _trail_heuristic(neighbor, end)

				if not open_set.has(neighbor):
					open_set.append(neighbor)

	# No path found - return direct line
	return _direct_path(start, end)


static func _get_trail_terrain_cost(
	terrain_type: VietnamTerrain.TerrainType,
	trail_type: String
) -> float:
	var props: Dictionary = TRAIL_TYPES.get(trail_type, {})
	var prefers_cover: bool = props.get("visibility", 1.0) < 0.5

	# Base cost
	var cost: float = 1.0

	# Terrain-specific adjustments
	match terrain_type:
		VietnamTerrain.TerrainType.TRIPLE_CANOPY:
			cost = 1.5 if prefers_cover else 3.0  # Good cover but slow
		VietnamTerrain.TerrainType.SINGLE_CANOPY:
			cost = 1.0 if prefers_cover else 1.5
		VietnamTerrain.TerrainType.MOUNTAIN:
			cost = 4.0  # Hard to traverse
		VietnamTerrain.TerrainType.HILL:
			cost = 2.0 if not prefers_cover else 2.5  # Exposed
		VietnamTerrain.TerrainType.RICE_PADDY:
			cost = 2.5  # Wet, slow
		VietnamTerrain.TerrainType.SWAMP:
			cost = 3.5
		VietnamTerrain.TerrainType.ROAD:
			cost = 0.5  # Use existing roads
		VietnamTerrain.TerrainType.CLEARED:
			cost = 0.8 if not prefers_cover else 2.0  # Easy but exposed

	return cost


static func _trail_heuristic(a: Vector2i, b: Vector2i) -> float:
	return float((a - b).length())


static func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.insert(0, current)
	return path


static func _direct_path(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	# Bresenham line algorithm for direct path
	var path: Array[Vector2i] = []
	var dx: int = absi(end.x - start.x)
	var dy: int = absi(end.y - start.y)
	var sx: int = 1 if start.x < end.x else -1
	var sy: int = 1 if start.y < end.y else -1
	var err: int = dx - dy
	var x: int = start.x
	var y: int = start.y

	while true:
		path.append(Vector2i(x, y))
		if x == end.x and y == end.y:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy

	return path


static func _generate_segment_id() -> String:
	return "trail_%d" % randi()


## =============================================================================
## HO CHI MINH TRAIL GENERATION
## =============================================================================

static func _generate_hcm_trail() -> void:
	for segment_id in HCM_TRAIL_SEGMENTS.keys():
		var data: Dictionary = HCM_TRAIL_SEGMENTS[segment_id]
		var start: Vector2i = data["start"]
		var end: Vector2i = data["end"]
		var trail_type: String = data["trail_type"]
		var waypoints: Array = data.get("waypoints", [])

		# Generate through waypoints
		var points: Array[Vector2i] = [start]
		for wp in waypoints:
			points.append(wp as Vector2i)
		points.append(end)

		generate_trail_network(points, trail_type, "hcm_" + segment_id)


static func _generate_local_trails(campaign_id: String) -> void:
	var features: Dictionary = VietnamWorldGrid.get_features(campaign_id)

	# Connect LZs with footpaths
	var lz_coords: Array[Vector2i] = VietnamWorldGrid.get_lz_positions(campaign_id)
	if lz_coords.size() >= 2:
		for i in range(lz_coords.size() - 1):
			generate_trail(lz_coords[i], lz_coords[i + 1], "footpath", "local_lz_%d" % i)

	# Connect firebases with supply routes
	var fb_coords: Array[Vector2i] = VietnamWorldGrid.get_firebase_positions(campaign_id)
	if fb_coords.size() >= 2:
		for i in range(fb_coords.size() - 1):
			generate_trail(fb_coords[i], fb_coords[i + 1], "supply_route", "local_fb_%d" % i)


## =============================================================================
## QUERY API
## =============================================================================

## Get all trail segments passing through a cell
static func get_trails_at(coords: Vector2i) -> Array[TrailSegment]:
	var result: Array[TrailSegment] = []
	var segment_ids: Array = _cell_trails.get(coords, [])

	for seg_id in segment_ids:
		if _segments.has(seg_id):
			result.append(_segments[seg_id])

	return result


## Check if cell has any trail
static func has_trail(coords: Vector2i) -> bool:
	return _cell_trails.has(coords) and _cell_trails[coords].size() > 0


## Get speed bonus at cell (from best trail)
static func get_speed_bonus_at(coords: Vector2i) -> float:
	var trails: Array[TrailSegment] = get_trails_at(coords)
	var best_bonus: float = 0.0

	for trail in trails:
		best_bonus = maxf(best_bonus, trail.get_speed_bonus())

	return best_bonus


## Get ambush risk at cell
static func get_ambush_risk_at(coords: Vector2i) -> float:
	var trails: Array[TrailSegment] = get_trails_at(coords)
	var highest_risk: float = 0.0

	for trail in trails:
		var props: Dictionary = trail.get_properties()
		highest_risk = maxf(highest_risk, props.get("ambush_risk", 0.0))

	return highest_risk


## Damage trail segment (from bombing)
static func damage_trail(segment_id: String, damage: float) -> void:
	if _segments.has(segment_id):
		_segments[segment_id].damage_level = clampf(
			_segments[segment_id].damage_level + damage,
			0.0,
			1.0
		)


## Repair trail segment
static func repair_trail(segment_id: String, repair_amount: float) -> void:
	if _segments.has(segment_id):
		_segments[segment_id].damage_level = clampf(
			_segments[segment_id].damage_level - repair_amount,
			0.0,
			1.0
		)


## Get all segments
static func get_all_segments() -> Array[TrailSegment]:
	var result: Array[TrailSegment] = []
	for seg in _segments.values():
		result.append(seg)
	return result


## Clear all trails
static func clear() -> void:
	_segments.clear()
	_cell_trails.clear()
