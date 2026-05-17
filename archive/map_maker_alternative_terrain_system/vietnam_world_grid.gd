## vietnam_world_grid.gd - Campaign map data and location presets
## Single source of truth for Vietnam War map locations
class_name VietnamWorldGrid
extends RefCounted


## Cell size in world units
const CELL_SIZE: float = 200.0


## =============================================================================
## REAL VIETNAM LOCATION PRESETS
## =============================================================================
const LOCATION_PRESETS: Dictionary = {
	# Ia Drang Valley - 1965
	"ia_drang": {
		"name": "Ia Drang Valley",
		"grid_start": Vector2i(4, 0),
		"grid_end": Vector2i(8, 4),
		"campaign_year": 1965,
		"preset": "ia_drang",
		"features": {
			"lz_xray": Vector2i(5, 2),
			"lz_albany": Vector2i(6, 3),
			"chu_pong_massif": Vector2i(4, 1),
			"plei_me": Vector2i(7, 4),
		},
		"default_terrain": VietnamTerrain.TerrainType.TRIPLE_CANOPY,
	},

	# A Shau Valley - Multiple operations
	"a_shau": {
		"name": "A Shau Valley",
		"grid_start": Vector2i(0, -10),
		"grid_end": Vector2i(2, -2),
		"campaign_year": 1966,
		"preset": "a_shau_valley",
		"features": {
			"valley_floor": Vector2i(1, -6),
			"ho_chi_minh_trail": Vector2i(0, -5),
			"firebase_bastogne": Vector2i(2, -8),
		},
		"default_terrain": VietnamTerrain.TerrainType.TRIPLE_CANOPY,
	},

	# Khe Sanh - 1968 Siege
	"khe_sanh": {
		"name": "Khe Sanh Combat Base",
		"grid_start": Vector2i(-5, -8),
		"grid_end": Vector2i(-2, -5),
		"campaign_year": 1968,
		"preset": "khe_sanh",
		"features": {
			"combat_base": Vector2i(-4, -6),
			"hill_881s": Vector2i(-5, -7),
			"hill_861": Vector2i(-3, -7),
			"hill_881n": Vector2i(-5, -8),
			"lang_vei": Vector2i(-2, -5),
		},
		"default_terrain": VietnamTerrain.TerrainType.HILL,
	},

	# Hue City - Tet Offensive 1968
	"hue": {
		"name": "Hue City",
		"grid_start": Vector2i(10, 0),
		"grid_end": Vector2i(15, 5),
		"campaign_year": 1968,
		"preset": "hue",
		"features": {
			"citadel": Vector2i(12, 2),
			"perfume_river": Vector2i(11, 3),
			"macv_compound": Vector2i(13, 3),
			"university": Vector2i(14, 2),
		},
		"default_terrain": VietnamTerrain.TerrainType.VILLAGE,
	},

	# Hamburger Hill - 1969
	"hamburger_hill": {
		"name": "Hamburger Hill (Ap Bia)",
		"grid_start": Vector2i(0, -4),
		"grid_end": Vector2i(2, -2),
		"campaign_year": 1969,
		"preset": "hamburger_hill",
		"features": {
			"hill_937": Vector2i(1, -3),
			"firebase_airborne": Vector2i(2, -2),
		},
		"default_terrain": VietnamTerrain.TerrainType.TRIPLE_CANOPY,
	},

	# Central Highlands - Multiple operations
	"central_highlands": {
		"name": "Central Highlands",
		"grid_start": Vector2i(-10, -5),
		"grid_end": Vector2i(10, 10),
		"campaign_year": 1965,
		"preset": "central_highlands",
		"features": {
			"pleiku": Vector2i(-5, 0),
			"kontum": Vector2i(-3, -3),
			"an_khe": Vector2i(2, 2),
		},
		"default_terrain": VietnamTerrain.TerrainType.SINGLE_CANOPY,
	},

	# Mekong Delta
	"mekong_delta": {
		"name": "Mekong Delta",
		"grid_start": Vector2i(5, 15),
		"grid_end": Vector2i(20, 30),
		"campaign_year": 1967,
		"preset": "mekong_delta",
		"features": {
			"can_tho": Vector2i(10, 20),
			"my_tho": Vector2i(8, 18),
		},
		"default_terrain": VietnamTerrain.TerrainType.RICE_PADDY,
	},
}


## =============================================================================
## CELL DATA STRUCTURE
## =============================================================================
class CellInfo:
	var coords: Vector2i
	var terrain_type: VietnamTerrain.TerrainType
	var preset_name: String
	var location_name: String
	var is_passable: bool
	var is_road: bool
	var has_trail: bool
	var clearing_state: int  # GameEnums.ClearingState
	var feature_id: String  # e.g., "lz_xray", "hill_881s"
	var danger_level: int  # 1-10
	var vc_presence: float  # 0.0-1.0
	var nva_presence: float  # 0.0-1.0

	func _init() -> void:
		coords = Vector2i.ZERO
		terrain_type = VietnamTerrain.TerrainType.SINGLE_CANOPY
		preset_name = "default"
		location_name = ""
		is_passable = true
		is_road = false
		has_trail = false
		clearing_state = 0  # JUNGLE
		feature_id = ""
		danger_level = 5
		vc_presence = 0.0
		nva_presence = 0.0


## =============================================================================
## GRID DATA STORAGE
## =============================================================================
static var _cell_cache: Dictionary = {}  # Vector2i -> CellInfo
static var _active_campaign: String = ""


## =============================================================================
## PUBLIC API
## =============================================================================

## Initialize grid for a campaign location
static func initialize(campaign_id: String) -> void:
	_cell_cache.clear()
	_active_campaign = campaign_id

	var preset: Dictionary = LOCATION_PRESETS.get(campaign_id, {})
	if preset.is_empty():
		push_warning("VietnamWorldGrid: Unknown campaign ID: %s" % campaign_id)
		return

	_generate_campaign_cells(campaign_id, preset)


## Get cell info at coordinates
static func get_cell(coords: Vector2i) -> CellInfo:
	if _cell_cache.has(coords):
		return _cell_cache[coords]

	# Generate cell on demand if not in cache
	var cell := _create_default_cell(coords)
	_cell_cache[coords] = cell
	return cell


## Get preset data for a campaign
static func get_preset(campaign_id: String) -> Dictionary:
	return LOCATION_PRESETS.get(campaign_id, HEIGHT_PRESETS.get("default", {}))


## Check if coordinates are within campaign bounds
static func is_in_bounds(coords: Vector2i, campaign_id: String = "") -> bool:
	var cid: String = campaign_id if campaign_id != "" else _active_campaign
	var preset: Dictionary = LOCATION_PRESETS.get(cid, {})
	if preset.is_empty():
		return true  # No bounds for unknown campaigns

	var start: Vector2i = preset.get("grid_start", Vector2i(-100, -100))
	var end: Vector2i = preset.get("grid_end", Vector2i(100, 100))

	return (coords.x >= start.x and coords.x <= end.x and
			coords.y >= start.y and coords.y <= end.y)


## Get all feature locations for a campaign
static func get_features(campaign_id: String) -> Dictionary:
	var preset: Dictionary = LOCATION_PRESETS.get(campaign_id, {})
	return preset.get("features", {})


## Get coordinates for a named feature
static func get_feature_coords(campaign_id: String, feature_id: String) -> Vector2i:
	var features: Dictionary = get_features(campaign_id)
	return features.get(feature_id, Vector2i.ZERO)


## Convert grid coordinates to world position
static func cell_to_world(coords: Vector2i) -> Vector3:
	return Vector3(
		coords.x * CELL_SIZE,
		0.0,
		coords.y * CELL_SIZE
	)


## Convert world position to grid coordinates
static func world_to_cell(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / CELL_SIZE)),
		int(floor(world_pos.z / CELL_SIZE))
	)


## Get neighboring cells
static func get_neighbors(coords: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	neighbors.append(Vector2i(coords.x, coords.y - 1))  # North
	neighbors.append(Vector2i(coords.x + 1, coords.y))  # East
	neighbors.append(Vector2i(coords.x, coords.y + 1))  # South
	neighbors.append(Vector2i(coords.x - 1, coords.y))  # West
	return neighbors


## Get cells in a rectangular area
static func get_cells_in_rect(rect: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			cells.append(Vector2i(x, y))
	return cells


## Update cell clearing state
static func set_clearing_state(coords: Vector2i, state: int) -> void:
	var cell: CellInfo = get_cell(coords)
	cell.clearing_state = state

	# If fully cleared, update terrain type
	if state >= 2:  # CLEARED or FORTIFIED
		cell.terrain_type = VietnamTerrain.TerrainType.CLEARED


## Get all LZ positions for a campaign
static func get_lz_positions(campaign_id: String) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	var features: Dictionary = get_features(campaign_id)

	for feature_id in features.keys():
		if feature_id.begins_with("lz_"):
			positions.append(features[feature_id])

	return positions


## Get all firebase positions for a campaign
static func get_firebase_positions(campaign_id: String) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	var features: Dictionary = get_features(campaign_id)

	for feature_id in features.keys():
		if feature_id.begins_with("firebase_"):
			positions.append(features[feature_id])

	return positions


## Calculate path between two points (A* pathfinding)
static func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var open_set: Array[Vector2i] = [from]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {from: 0}
	var f_score: Dictionary = {from: _heuristic(from, to)}

	while not open_set.is_empty():
		# Find node with lowest f_score
		var current: Vector2i = open_set[0]
		var lowest_f: float = f_score.get(current, INF)
		for node in open_set:
			var f: float = f_score.get(node, INF)
			if f < lowest_f:
				lowest_f = f
				current = node

		if current == to:
			return _reconstruct_path(came_from, current)

		open_set.erase(current)

		for neighbor in get_neighbors(current):
			var cell: CellInfo = get_cell(neighbor)
			if not cell.is_passable:
				continue

			# Calculate movement cost based on terrain
			var move_cost: float = _get_movement_cost(cell.terrain_type)
			var tentative_g: float = g_score.get(current, INF) + move_cost

			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _heuristic(neighbor, to)

				if not open_set.has(neighbor):
					open_set.append(neighbor)

	return []  # No path found


## =============================================================================
## INTERNAL METHODS
## =============================================================================

static func _generate_campaign_cells(campaign_id: String, preset: Dictionary) -> void:
	var start: Vector2i = preset.get("grid_start", Vector2i.ZERO)
	var end: Vector2i = preset.get("grid_end", Vector2i.ZERO)
	var default_terrain: VietnamTerrain.TerrainType = preset.get(
		"default_terrain",
		VietnamTerrain.TerrainType.SINGLE_CANOPY
	)
	var preset_name: String = preset.get("preset", "default")
	var features: Dictionary = preset.get("features", {})

	# Create lookup for feature coords
	var feature_lookup: Dictionary = {}
	for feature_id in features.keys():
		var coords: Vector2i = features[feature_id]
		feature_lookup[coords] = feature_id

	# Generate cells
	for x in range(start.x, end.x + 1):
		for y in range(start.y, end.y + 1):
			var coords := Vector2i(x, y)
			var cell := CellInfo.new()

			cell.coords = coords
			cell.terrain_type = default_terrain
			cell.preset_name = preset_name
			cell.is_passable = true

			# Check for special features at this location
			if feature_lookup.has(coords):
				cell.feature_id = feature_lookup[coords]
				cell.location_name = _format_feature_name(cell.feature_id)

				# Adjust terrain for specific features
				if cell.feature_id.begins_with("lz_"):
					cell.terrain_type = VietnamTerrain.TerrainType.CLEARED
					cell.clearing_state = 2  # CLEARED
				elif cell.feature_id.begins_with("hill_"):
					cell.terrain_type = VietnamTerrain.TerrainType.HILL
				elif cell.feature_id.begins_with("firebase_"):
					cell.terrain_type = VietnamTerrain.TerrainType.CLEARED
					cell.clearing_state = 3  # FORTIFIED
				elif "river" in cell.feature_id:
					cell.terrain_type = VietnamTerrain.TerrainType.RIVER
					cell.is_passable = false

			# Calculate danger level based on distance from friendly features
			cell.danger_level = _calculate_danger_level(coords, features, campaign_id)

			_cell_cache[coords] = cell


static func _create_default_cell(coords: Vector2i) -> CellInfo:
	var cell := CellInfo.new()
	cell.coords = coords
	cell.terrain_type = VietnamTerrain.TerrainType.SINGLE_CANOPY
	cell.is_passable = true
	cell.danger_level = 5
	return cell


static func _format_feature_name(feature_id: String) -> String:
	# Convert snake_case to Title Case
	var words: PackedStringArray = feature_id.split("_")
	var formatted: String = ""
	for word in words:
		if word.length() > 0:
			formatted += word[0].to_upper() + word.substr(1) + " "
	return formatted.strip_edges()


static func _calculate_danger_level(
	coords: Vector2i,
	features: Dictionary,
	campaign_id: String
) -> int:
	# Find distance to nearest friendly feature
	var min_distance: float = INF

	for feature_id in features.keys():
		if feature_id.begins_with("lz_") or feature_id.begins_with("firebase_"):
			var feature_coords: Vector2i = features[feature_id]
			var distance: float = float((coords - feature_coords).length())
			min_distance = minf(min_distance, distance)

	# Danger increases with distance
	if min_distance == INF:
		return 5

	if min_distance < 2:
		return 1
	elif min_distance < 4:
		return 3
	elif min_distance < 6:
		return 5
	elif min_distance < 10:
		return 7
	else:
		return 9


static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return float((a - b).length())


static func _get_movement_cost(terrain_type: VietnamTerrain.TerrainType) -> float:
	var speed_mod: float = VietnamTerrain.get_terrain_speed_modifier(terrain_type)
	if speed_mod <= 0.0:
		return INF  # Impassable
	return 1.0 / speed_mod


static func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.insert(0, current)
	return path


## =============================================================================
## CAMPAIGN UTILITIES
## =============================================================================

static func get_campaign_names() -> Array[String]:
	var names: Array[String] = []
	for key in LOCATION_PRESETS.keys():
		names.append(key)
	return names


static func get_campaign_display_name(campaign_id: String) -> String:
	var preset: Dictionary = LOCATION_PRESETS.get(campaign_id, {})
	return preset.get("name", campaign_id)


static func get_campaign_year(campaign_id: String) -> int:
	var preset: Dictionary = LOCATION_PRESETS.get(campaign_id, {})
	return preset.get("campaign_year", 1965)


## HEIGHT_PRESETS reference for compatibility
const HEIGHT_PRESETS: Dictionary = VietnamTerrain.HEIGHT_PRESETS
