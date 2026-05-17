## river_generator.gd - River and waterway generation for Vietnam maps
## Generates rivers, streams, and canal networks
## class_name RiverGenerator  # ARCHIVED - class_name removed to prevent duplicate
extends RefCounted


## =============================================================================
## RIVER TYPE DEFINITIONS
## =============================================================================
const RIVER_TYPES: Dictionary = {
	"major_river": {
		"name": "Major River",
		"width": 50.0,
		"depth": 8.0,
		"current_speed": 2.0,
		"fordable": false,
		"bridge_required": true,
		"boat_passable": true,
	},
	"river": {
		"name": "River",
		"width": 25.0,
		"depth": 4.0,
		"current_speed": 1.5,
		"fordable": false,
		"bridge_required": true,
		"boat_passable": true,
	},
	"stream": {
		"name": "Stream",
		"width": 8.0,
		"depth": 1.5,
		"current_speed": 1.0,
		"fordable": true,
		"ford_speed_penalty": 0.5,
		"boat_passable": false,
	},
	"canal": {
		"name": "Canal",
		"width": 15.0,
		"depth": 2.0,
		"current_speed": 0.5,
		"fordable": false,
		"bridge_required": true,
		"boat_passable": true,
	},
	"irrigation": {
		"name": "Irrigation Ditch",
		"width": 3.0,
		"depth": 0.5,
		"current_speed": 0.2,
		"fordable": true,
		"ford_speed_penalty": 0.2,
		"boat_passable": false,
	},
}


## =============================================================================
## FAMOUS VIETNAM RIVERS
## =============================================================================
const FAMOUS_RIVERS: Dictionary = {
	"perfume_river": {
		"name": "Perfume River (Song Huong)",
		"type": "major_river",
		"campaign": "hue",
		"source": Vector2i(8, 0),
		"mouth": Vector2i(15, 5),
		"waypoints": [Vector2i(10, 2), Vector2i(12, 3), Vector2i(14, 4)],
	},
	"ia_drang_river": {
		"name": "Ia Drang River",
		"type": "stream",
		"campaign": "ia_drang",
		"source": Vector2i(3, 0),
		"mouth": Vector2i(8, 4),
		"waypoints": [Vector2i(5, 2), Vector2i(7, 3)],
	},
	"rao_quan_river": {
		"name": "Rao Quan River",
		"type": "river",
		"campaign": "khe_sanh",
		"source": Vector2i(-6, -9),
		"mouth": Vector2i(-2, -5),
		"waypoints": [Vector2i(-4, -7)],
	},
	"mekong_branch": {
		"name": "Mekong River Branch",
		"type": "major_river",
		"campaign": "mekong_delta",
		"source": Vector2i(5, 15),
		"mouth": Vector2i(20, 30),
		"waypoints": [Vector2i(10, 20), Vector2i(15, 25)],
	},
}


## =============================================================================
## RIVER SEGMENT CLASS
## =============================================================================
class RiverSegment:
	var id: String = ""
	var river_type: String = "stream"
	var path: Array[Vector2i] = []
	var width: float = 8.0
	var has_bridge: bool = false
	var bridge_locations: Array[Vector2i] = []
	var ford_locations: Array[Vector2i] = []

	func get_properties() -> Dictionary:
		return RIVER_TYPES.get(river_type, RIVER_TYPES["stream"])

	func is_fordable() -> bool:
		return get_properties().get("fordable", false)

	func requires_bridge() -> bool:
		return get_properties().get("bridge_required", false)

	func can_use_boats() -> bool:
		return get_properties().get("boat_passable", false)


## =============================================================================
## STATE
## =============================================================================
static var _rivers: Dictionary = {}  # river_id -> RiverSegment
static var _cell_rivers: Dictionary = {}  # Vector2i -> Array of river_ids
static var _bridges: Dictionary = {}  # Vector2i -> bridge data


## =============================================================================
## INITIALIZATION
## =============================================================================

## Initialize rivers for a campaign
static func initialize(campaign_id: String) -> void:
	_rivers.clear()
	_cell_rivers.clear()
	_bridges.clear()

	# Generate famous rivers for this campaign
	for river_id in FAMOUS_RIVERS.keys():
		var river_data: Dictionary = FAMOUS_RIVERS[river_id]
		if river_data.get("campaign", "") == campaign_id:
			_generate_famous_river(river_id, river_data)

	# Generate random streams based on terrain
	_generate_procedural_streams(campaign_id)

	# Generate canals for Mekong Delta
	if campaign_id == "mekong_delta":
		_generate_canal_network()


## =============================================================================
## RIVER GENERATION
## =============================================================================

## Generate a river following terrain
static func generate_river(
	source: Vector2i,
	mouth: Vector2i,
	river_type: String,
	waypoints: Array[Vector2i] = [],
	river_id: String = ""
) -> RiverSegment:
	var segment := RiverSegment.new()
	segment.id = river_id if river_id != "" else _generate_river_id()
	segment.river_type = river_type
	segment.width = RIVER_TYPES.get(river_type, {}).get("width", 8.0)

	# Build path through waypoints
	var all_points: Array[Vector2i] = [source]
	all_points.append_array(waypoints)
	all_points.append(mouth)

	segment.path = _generate_river_path(all_points, river_type)

	# Find ford and bridge locations
	if segment.is_fordable():
		segment.ford_locations = _find_ford_locations(segment.path)
	elif segment.requires_bridge():
		segment.bridge_locations = _find_bridge_locations(segment.path)

	# Register river
	_rivers[segment.id] = segment

	# Update cells
	for cell_coords in segment.path:
		if not _cell_rivers.has(cell_coords):
			_cell_rivers[cell_coords] = []
		_cell_rivers[cell_coords].append(segment.id)

		# Update cell terrain to river
		var cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(cell_coords)
		cell.terrain_type = VietnamTerrain.TerrainType.RIVER
		cell.is_passable = segment.is_fordable()

	return segment


static func _generate_river_path(
	waypoints: Array[Vector2i],
	river_type: String
) -> Array[Vector2i]:
	var full_path: Array[Vector2i] = []

	for i in range(waypoints.size() - 1):
		var segment_path: Array[Vector2i] = _find_water_path(
			waypoints[i],
			waypoints[i + 1],
			river_type
		)

		# Avoid duplicating waypoint
		if full_path.size() > 0 and segment_path.size() > 0:
			if full_path[-1] == segment_path[0]:
				segment_path.remove_at(0)

		full_path.append_array(segment_path)

	return full_path


static func _find_water_path(
	start: Vector2i,
	end: Vector2i,
	river_type: String
) -> Array[Vector2i]:
	# Rivers flow downhill - use A* with height preference
	var open_set: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0.0}
	var f_score: Dictionary = {start: _river_heuristic(start, end)}

	while not open_set.is_empty():
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

			# Rivers avoid mountains
			if cell.terrain_type == VietnamTerrain.TerrainType.MOUNTAIN:
				continue

			var terrain_cost: float = _get_river_terrain_cost(cell.terrain_type)
			var tentative_g: float = g_score.get(current, INF) + terrain_cost

			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _river_heuristic(neighbor, end)

				if not open_set.has(neighbor):
					open_set.append(neighbor)

	# Fallback to direct path
	return _direct_path(start, end)


static func _get_river_terrain_cost(terrain_type: VietnamTerrain.TerrainType) -> float:
	match terrain_type:
		VietnamTerrain.TerrainType.SWAMP:
			return 0.5  # Rivers like low wet areas
		VietnamTerrain.TerrainType.RICE_PADDY:
			return 0.8
		VietnamTerrain.TerrainType.SINGLE_CANOPY, VietnamTerrain.TerrainType.TRIPLE_CANOPY:
			return 1.0
		VietnamTerrain.TerrainType.HILL:
			return 2.0
		VietnamTerrain.TerrainType.MOUNTAIN:
			return 10.0
		VietnamTerrain.TerrainType.CLEARED:
			return 1.5
		_:
			return 1.0


static func _river_heuristic(a: Vector2i, b: Vector2i) -> float:
	return float((a - b).length())


static func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.insert(0, current)
	return path


static func _direct_path(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
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


static func _generate_river_id() -> String:
	return "river_%d" % randi()


## =============================================================================
## FORD AND BRIDGE LOCATIONS
## =============================================================================

static func _find_ford_locations(path: Array[Vector2i]) -> Array[Vector2i]:
	var fords: Array[Vector2i] = []

	# Find locations with gentle terrain on both sides
	for i in range(1, path.size() - 1):
		var cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(path[i])

		# Check neighbors for good approach
		var good_approach: bool = false
		for neighbor in VietnamWorldGrid.get_neighbors(path[i]):
			if not path.has(neighbor):
				var neighbor_cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(neighbor)
				if neighbor_cell.terrain_type in [
					VietnamTerrain.TerrainType.CLEARED,
					VietnamTerrain.TerrainType.ROAD,
					VietnamTerrain.TerrainType.SINGLE_CANOPY
				]:
					good_approach = true
					break

		if good_approach:
			fords.append(path[i])

	# Limit ford count
	if fords.size() > 3:
		var step: int = fords.size() / 3
		var limited: Array[Vector2i] = []
		for i in range(0, fords.size(), step):
			limited.append(fords[i])
		return limited

	return fords


static func _find_bridge_locations(path: Array[Vector2i]) -> Array[Vector2i]:
	var bridges: Array[Vector2i] = []

	# Look for locations near roads or clearings
	for i in range(1, path.size() - 1):
		for neighbor in VietnamWorldGrid.get_neighbors(path[i]):
			if not path.has(neighbor):
				var neighbor_cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(neighbor)
				if neighbor_cell.terrain_type == VietnamTerrain.TerrainType.ROAD:
					bridges.append(path[i])
					break

	# Ensure at least one bridge on major rivers
	if bridges.is_empty() and path.size() > 2:
		bridges.append(path[path.size() / 2])

	return bridges


## =============================================================================
## SPECIALIZED GENERATION
## =============================================================================

static func _generate_famous_river(river_id: String, data: Dictionary) -> void:
	var waypoints: Array[Vector2i] = []
	for wp in data.get("waypoints", []):
		waypoints.append(wp as Vector2i)

	generate_river(
		data["source"],
		data["mouth"],
		data["type"],
		waypoints,
		river_id
	)


static func _generate_procedural_streams(campaign_id: String) -> void:
	var preset: Dictionary = VietnamWorldGrid.LOCATION_PRESETS.get(campaign_id, {})
	var grid_start: Vector2i = preset.get("grid_start", Vector2i.ZERO)
	var grid_end: Vector2i = preset.get("grid_end", Vector2i.ZERO)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(campaign_id)

	# Generate a few random streams
	var stream_count: int = rng.randi_range(2, 5)

	for i in range(stream_count):
		var source := Vector2i(
			rng.randi_range(grid_start.x, grid_end.x),
			rng.randi_range(grid_start.y, grid_end.y / 2)
		)
		var mouth := Vector2i(
			rng.randi_range(grid_start.x, grid_end.x),
			rng.randi_range(grid_end.y / 2, grid_end.y)
		)

		generate_river(source, mouth, "stream", [], "stream_%s_%d" % [campaign_id, i])


static func _generate_canal_network() -> void:
	# Mekong Delta-specific canal generation
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("mekong_canals")

	# Generate grid of canals
	for x in range(6, 19, 3):
		var start := Vector2i(x, 16)
		var end := Vector2i(x, 29)
		generate_river(start, end, "canal", [], "canal_ns_%d" % x)

	for y in range(17, 28, 3):
		var start := Vector2i(6, y)
		var end := Vector2i(19, y)
		generate_river(start, end, "canal", [], "canal_ew_%d" % y)


## =============================================================================
## BRIDGE MANAGEMENT
## =============================================================================

## Build a bridge at location
static func build_bridge(coords: Vector2i) -> bool:
	if not _cell_rivers.has(coords):
		return false

	_bridges[coords] = {
		"built": true,
		"health": 100.0,
	}

	# Update river segments
	for river_id in _cell_rivers[coords]:
		if _rivers.has(river_id):
			_rivers[river_id].has_bridge = true

	# Make cell passable
	var cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(coords)
	cell.is_passable = true

	return true


## Destroy a bridge
static func destroy_bridge(coords: Vector2i) -> void:
	if _bridges.has(coords):
		_bridges.erase(coords)

		# Update passability
		var cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(coords)
		var river_segments: Array = _cell_rivers.get(coords, [])

		for river_id in river_segments:
			if _rivers.has(river_id):
				var river: RiverSegment = _rivers[river_id]
				cell.is_passable = river.is_fordable()
				break


## Check if bridge exists at location
static func has_bridge(coords: Vector2i) -> bool:
	return _bridges.has(coords)


## =============================================================================
## QUERY API
## =============================================================================

## Get rivers at cell
static func get_rivers_at(coords: Vector2i) -> Array[RiverSegment]:
	var result: Array[RiverSegment] = []
	var river_ids: Array = _cell_rivers.get(coords, [])

	for river_id in river_ids:
		if _rivers.has(river_id):
			result.append(_rivers[river_id])

	return result


## Check if cell has river
static func has_river(coords: Vector2i) -> bool:
	return _cell_rivers.has(coords) and _cell_rivers[coords].size() > 0


## Check if cell is crossable (has ford or bridge)
static func is_crossable(coords: Vector2i) -> bool:
	if has_bridge(coords):
		return true

	var rivers: Array[RiverSegment] = get_rivers_at(coords)
	for river in rivers:
		if river.is_fordable():
			return true

	return false


## Get crossing penalty
static func get_crossing_penalty(coords: Vector2i) -> float:
	if has_bridge(coords):
		return 0.0

	var rivers: Array[RiverSegment] = get_rivers_at(coords)
	for river in rivers:
		var props: Dictionary = river.get_properties()
		if river.is_fordable():
			return props.get("ford_speed_penalty", 0.5)

	return 1.0  # Impassable


## Get all rivers
static func get_all_rivers() -> Array[RiverSegment]:
	var result: Array[RiverSegment] = []
	for river in _rivers.values():
		result.append(river)
	return result


## Clear all rivers
static func clear() -> void:
	_rivers.clear()
	_cell_rivers.clear()
	_bridges.clear()
