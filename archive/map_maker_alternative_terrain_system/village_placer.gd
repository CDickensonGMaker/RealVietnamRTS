## village_placer.gd - Procedural village placement for Vietnam maps
## Places Vietnamese villages based on terrain and strategic considerations
class_name VillagePlacer
extends RefCounted


## =============================================================================
## VILLAGE TYPE DEFINITIONS
## =============================================================================
const VILLAGE_TYPES: Dictionary = {
	"hamlet": {
		"name": "Hamlet",
		"population_range": Vector2i(20, 50),
		"building_count": Vector2i(3, 6),
		"services": ["well"],
		"vc_sympathy_base": 0.4,
	},
	"village": {
		"name": "Village",
		"population_range": Vector2i(50, 200),
		"building_count": Vector2i(6, 15),
		"services": ["well", "market", "temple"],
		"vc_sympathy_base": 0.3,
	},
	"town": {
		"name": "Town",
		"population_range": Vector2i(200, 1000),
		"building_count": Vector2i(15, 40),
		"services": ["well", "market", "temple", "hospital", "school"],
		"vc_sympathy_base": 0.2,
	},
	"district_capital": {
		"name": "District Capital",
		"population_range": Vector2i(1000, 5000),
		"building_count": Vector2i(40, 100),
		"services": ["well", "market", "temple", "hospital", "school", "police", "government"],
		"vc_sympathy_base": 0.1,
	},
}


## =============================================================================
## BUILDING TYPE DEFINITIONS
## =============================================================================
const BUILDING_TYPES: Dictionary = {
	"hooch": {
		"name": "Hooch (Hut)",
		"size": Vector2(4.0, 6.0),
		"residents": Vector2i(4, 8),
		"can_hide_vc": true,
	},
	"longhouse": {
		"name": "Longhouse",
		"size": Vector2(6.0, 12.0),
		"residents": Vector2i(8, 16),
		"can_hide_vc": true,
	},
	"temple": {
		"name": "Buddhist Temple",
		"size": Vector2(10.0, 15.0),
		"residents": Vector2i(0, 2),
		"sacred": true,
	},
	"market": {
		"name": "Market Stall",
		"size": Vector2(3.0, 3.0),
		"residents": Vector2i(0, 0),
		"trade": true,
	},
	"well": {
		"name": "Village Well",
		"size": Vector2(2.0, 2.0),
		"residents": Vector2i(0, 0),
		"critical": true,
	},
	"rice_barn": {
		"name": "Rice Storage",
		"size": Vector2(5.0, 8.0),
		"residents": Vector2i(0, 0),
		"supplies_vc": true,
	},
}


## =============================================================================
## VILLAGE CLASS
## =============================================================================
class VillageData:
	var id: String = ""
	var name: String = ""
	var village_type: String = "hamlet"
	var coords: Vector2i = Vector2i.ZERO
	var population: int = 0
	var buildings: Array[Dictionary] = []  # {type, position, rotation}
	var services: Array[String] = []

	# Allegiance system
	var vc_sympathy: float = 0.3  # 0-1, how much they support VC
	var us_trust: float = 0.3     # 0-1, how much they trust US/ARVN
	var fear_level: float = 0.0   # 0-1, fear from violence

	# Strategic info
	var known_vc_presence: bool = false
	var has_tunnel_entrance: bool = false
	var last_vc_tax_day: int = -1
	var last_civic_action_day: int = -1

	func get_allegiance() -> int:  # Returns GameEnums.VillageAllegiance
		if vc_sympathy > 0.7:
			return 2  # PRO_VC
		elif us_trust > 0.7:
			return 1  # PRO_US
		elif absf(vc_sympathy - us_trust) < 0.2:
			return 3  # CONTESTED
		else:
			return 0  # NEUTRAL


## =============================================================================
## STATE
## =============================================================================
static var _villages: Dictionary = {}  # village_id -> VillageData
static var _cell_villages: Dictionary = {}  # Vector2i -> village_id
static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## =============================================================================
## VIETNAMESE VILLAGE NAMES
## =============================================================================
const VILLAGE_NAME_PREFIXES: Array[String] = [
	"Ap", "An", "Binh", "Cam", "Dong", "Gia", "Hoa", "Kien",
	"Lac", "Long", "My", "Phu", "Tan", "Thanh", "Thuan", "Vinh",
]

const VILLAGE_NAME_SUFFIXES: Array[String] = [
	"Bac", "Do", "Duong", "Hai", "Hoa", "Khe", "Lam", "Long",
	"My", "Nam", "Ninh", "Phu", "Thanh", "Thuan", "Trang", "Xuyen",
]


## =============================================================================
## INITIALIZATION
## =============================================================================

## Initialize villages for a campaign
static func initialize(campaign_id: String) -> void:
	_villages.clear()
	_cell_villages.clear()
	_rng.seed = hash(campaign_id + "_villages")

	var preset: Dictionary = VietnamWorldGrid.LOCATION_PRESETS.get(campaign_id, {})
	if preset.is_empty():
		return

	var grid_start: Vector2i = preset.get("grid_start", Vector2i.ZERO)
	var grid_end: Vector2i = preset.get("grid_end", Vector2i.ZERO)
	var default_terrain: VietnamTerrain.TerrainType = preset.get(
		"default_terrain",
		VietnamTerrain.TerrainType.SINGLE_CANOPY
	)

	# Determine village density based on campaign
	var village_density: float = _get_campaign_village_density(campaign_id)

	# Calculate total area and number of villages
	var area: int = (grid_end.x - grid_start.x) * (grid_end.y - grid_start.y)
	var target_villages: int = int(area * village_density)
	target_villages = clampi(target_villages, 3, 50)

	# Place villages
	_place_villages(grid_start, grid_end, target_villages, campaign_id)


static func _get_campaign_village_density(campaign_id: String) -> float:
	match campaign_id:
		"mekong_delta":
			return 0.15  # Dense population
		"hue":
			return 0.2   # Urban area
		"central_highlands":
			return 0.03  # Sparse, tribal
		"ia_drang":
			return 0.02  # Remote area
		"a_shau":
			return 0.01  # Very remote
		"khe_sanh":
			return 0.02
		"hamburger_hill":
			return 0.01
		_:
			return 0.05


## =============================================================================
## VILLAGE PLACEMENT
## =============================================================================

static func _place_villages(
	grid_start: Vector2i,
	grid_end: Vector2i,
	count: int,
	campaign_id: String
) -> void:
	var attempts: int = 0
	var max_attempts: int = count * 10
	var placed: int = 0
	var min_distance: int = 3  # Minimum cells between villages

	while placed < count and attempts < max_attempts:
		attempts += 1

		# Random position
		var coords := Vector2i(
			_rng.randi_range(grid_start.x, grid_end.x),
			_rng.randi_range(grid_start.y, grid_end.y)
		)

		# Check if valid placement
		if not _is_valid_village_location(coords, min_distance):
			continue

		# Determine village type based on location
		var village_type: String = _determine_village_type(coords, campaign_id)

		# Create village
		var village: VillageData = _create_village(coords, village_type)
		_register_village(village)
		placed += 1


static func _is_valid_village_location(coords: Vector2i, min_distance: int) -> bool:
	# Check terrain
	var cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(coords)

	# Villages can't be on water, mountains, or swamps
	if cell.terrain_type in [
		VietnamTerrain.TerrainType.WATER,
		VietnamTerrain.TerrainType.RIVER,
		VietnamTerrain.TerrainType.MOUNTAIN,
		VietnamTerrain.TerrainType.SWAMP,
	]:
		return false

	# Already has special feature
	if cell.feature_id != "":
		return false

	# Check distance to other villages
	for village_coords in _cell_villages.keys():
		if (coords - village_coords).length() < min_distance:
			return false

	return true


static func _determine_village_type(coords: Vector2i, campaign_id: String) -> String:
	var cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(coords)

	# Near roads = larger villages
	var near_road: bool = _is_near_road(coords)

	# Rice paddies = larger agricultural villages
	var near_paddy: bool = cell.terrain_type == VietnamTerrain.TerrainType.RICE_PADDY

	# Mekong Delta has larger settlements
	if campaign_id == "mekong_delta":
		if near_road:
			return "town" if _rng.randf() < 0.3 else "village"
		else:
			return "village" if _rng.randf() < 0.5 else "hamlet"

	# Hue has urban areas
	if campaign_id == "hue":
		return "district_capital" if _rng.randf() < 0.1 else "town"

	# Highlands have smaller settlements
	if campaign_id in ["central_highlands", "ia_drang", "a_shau", "hamburger_hill"]:
		if near_paddy:
			return "village" if _rng.randf() < 0.3 else "hamlet"
		else:
			return "hamlet"

	# Default
	if near_road and _rng.randf() < 0.2:
		return "village"
	return "hamlet"


static func _is_near_road(coords: Vector2i) -> bool:
	# Check cell and neighbors for roads
	var cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(coords)
	if cell.is_road or cell.has_trail:
		return true

	for neighbor in VietnamWorldGrid.get_neighbors(coords):
		var neighbor_cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(neighbor)
		if neighbor_cell.is_road or neighbor_cell.has_trail:
			return true

	return false


## =============================================================================
## VILLAGE CREATION
## =============================================================================

static func _create_village(coords: Vector2i, village_type: String) -> VillageData:
	var village := VillageData.new()
	village.id = "village_%d_%d" % [coords.x, coords.y]
	village.name = _generate_village_name()
	village.village_type = village_type
	village.coords = coords

	var type_data: Dictionary = VILLAGE_TYPES.get(village_type, VILLAGE_TYPES["hamlet"])

	# Set population
	var pop_range: Vector2i = type_data.get("population_range", Vector2i(20, 50))
	village.population = _rng.randi_range(pop_range.x, pop_range.y)

	# Set allegiance values
	village.vc_sympathy = type_data.get("vc_sympathy_base", 0.3)
	village.vc_sympathy += _rng.randf_range(-0.1, 0.2)
	village.vc_sympathy = clampf(village.vc_sympathy, 0.0, 1.0)

	village.us_trust = 0.5 - village.vc_sympathy * 0.3 + _rng.randf_range(-0.1, 0.1)
	village.us_trust = clampf(village.us_trust, 0.0, 1.0)

	# Generate buildings
	var building_count_range: Vector2i = type_data.get("building_count", Vector2i(3, 6))
	var building_count: int = _rng.randi_range(building_count_range.x, building_count_range.y)

	village.buildings = _generate_buildings(building_count, village_type)
	village.services = type_data.get("services", [])

	# Check for tunnel entrance (VC sympathy increases chance)
	if village.vc_sympathy > 0.5:
		village.has_tunnel_entrance = _rng.randf() < (village.vc_sympathy - 0.3)

	return village


static func _generate_village_name() -> String:
	var prefix: String = VILLAGE_NAME_PREFIXES[_rng.randi() % VILLAGE_NAME_PREFIXES.size()]
	var suffix: String = VILLAGE_NAME_SUFFIXES[_rng.randi() % VILLAGE_NAME_SUFFIXES.size()]
	return prefix + " " + suffix


static func _generate_buildings(count: int, village_type: String) -> Array[Dictionary]:
	var buildings: Array[Dictionary] = []

	# Always add essential buildings
	buildings.append({
		"type": "well",
		"position": Vector2.ZERO,
		"rotation": 0.0,
	})

	# Add hooch/longhouses for population
	var housing_count: int = count - 1
	if village_type in ["town", "district_capital"]:
		housing_count = int(housing_count * 0.6)

	for i in range(housing_count):
		var building_type: String = "hooch" if _rng.randf() < 0.7 else "longhouse"
		var angle: float = _rng.randf() * TAU
		var distance: float = 10.0 + _rng.randf() * 30.0

		buildings.append({
			"type": building_type,
			"position": Vector2(cos(angle), sin(angle)) * distance,
			"rotation": _rng.randf() * TAU,
		})

	# Add service buildings
	if village_type in ["village", "town", "district_capital"]:
		buildings.append({
			"type": "temple",
			"position": Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-20, -10)),
			"rotation": 0.0,
		})

		for i in range(_rng.randi_range(1, 4)):
			buildings.append({
				"type": "market",
				"position": Vector2(_rng.randf_range(-15, 15), _rng.randf_range(5, 15)),
				"rotation": 0.0,
			})

	# Add rice storage
	if village_type != "district_capital":
		buildings.append({
			"type": "rice_barn",
			"position": Vector2(_rng.randf_range(-25, 25), _rng.randf_range(-25, 25)),
			"rotation": _rng.randf() * TAU,
		})

	return buildings


static func _register_village(village: VillageData) -> void:
	_villages[village.id] = village
	_cell_villages[village.coords] = village.id

	# Update cell data
	var cell: VietnamWorldGrid.CellInfo = VietnamWorldGrid.get_cell(village.coords)
	cell.terrain_type = VietnamTerrain.TerrainType.VILLAGE
	cell.location_name = village.name
	cell.feature_id = village.id


## =============================================================================
## VILLAGE INTERACTIONS
## =============================================================================

## Apply civic action (Hearts and Minds)
static func apply_civic_action(village_id: String, intensity: float = 1.0) -> void:
	if not _villages.has(village_id):
		return

	var village: VillageData = _villages[village_id]

	# Increase US trust
	village.us_trust = clampf(village.us_trust + 0.1 * intensity, 0.0, 1.0)

	# Slightly decrease VC sympathy
	village.vc_sympathy = clampf(village.vc_sympathy - 0.05 * intensity, 0.0, 1.0)

	# Reduce fear
	village.fear_level = clampf(village.fear_level - 0.1 * intensity, 0.0, 1.0)

	village.last_civic_action_day = 0  # Would be game day


## Apply VC taxation/intimidation
static func apply_vc_tax(village_id: String, intensity: float = 1.0) -> void:
	if not _villages.has(village_id):
		return

	var village: VillageData = _villages[village_id]

	# Increase VC sympathy (or fear makes them comply)
	village.vc_sympathy = clampf(village.vc_sympathy + 0.05 * intensity, 0.0, 1.0)
	village.fear_level = clampf(village.fear_level + 0.1 * intensity, 0.0, 1.0)

	# Decrease US trust
	village.us_trust = clampf(village.us_trust - 0.05 * intensity, 0.0, 1.0)

	village.last_vc_tax_day = 0


## Apply violence effects (bombing, firefight in village)
static func apply_violence(village_id: String, us_responsible: bool, intensity: float = 1.0) -> void:
	if not _villages.has(village_id):
		return

	var village: VillageData = _villages[village_id]

	# Increase fear
	village.fear_level = clampf(village.fear_level + 0.2 * intensity, 0.0, 1.0)

	if us_responsible:
		# US violence turns villagers against them
		village.us_trust = clampf(village.us_trust - 0.2 * intensity, 0.0, 1.0)
		village.vc_sympathy = clampf(village.vc_sympathy + 0.1 * intensity, 0.0, 1.0)
	else:
		# VC violence can go either way
		village.vc_sympathy = clampf(village.vc_sympathy - 0.1 * intensity, 0.0, 1.0)

	# Reduce population
	var casualties: int = int(village.population * 0.01 * intensity)
	village.population = maxi(0, village.population - casualties)


## =============================================================================
## QUERY API
## =============================================================================

## Get village at cell
static func get_village_at(coords: Vector2i) -> VillageData:
	if _cell_villages.has(coords):
		return _villages.get(_cell_villages[coords], null)
	return null


## Get village by ID
static func get_village(village_id: String) -> VillageData:
	return _villages.get(village_id, null)


## Get all villages
static func get_all_villages() -> Array[VillageData]:
	var result: Array[VillageData] = []
	for village in _villages.values():
		result.append(village)
	return result


## Get villages by allegiance
static func get_villages_by_allegiance(allegiance: int) -> Array[VillageData]:
	var result: Array[VillageData] = []
	for village in _villages.values():
		if village.get_allegiance() == allegiance:
			result.append(village)
	return result


## Get pro-VC villages (for VC spawning/support)
static func get_pro_vc_villages() -> Array[VillageData]:
	return get_villages_by_allegiance(2)  # PRO_VC


## Get villages with tunnel entrances
static func get_tunnel_villages() -> Array[VillageData]:
	var result: Array[VillageData] = []
	for village in _villages.values():
		if village.has_tunnel_entrance:
			result.append(village)
	return result


## Get nearest village to position
static func get_nearest_village(coords: Vector2i) -> VillageData:
	var nearest: VillageData = null
	var nearest_distance: float = INF

	for village in _villages.values():
		var distance: float = float((coords - village.coords).length())
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = village

	return nearest


## Clear all villages
static func clear() -> void:
	_villages.clear()
	_cell_villages.clear()
