extends Resource
class_name BuildingData
## BuildingData - Construction and gameplay data for all structures

@export_group("Identification")
@export var building_name: String = "Sandbag Wall"
@export var building_type: int = GameEnums.BuildingType.SANDBAG_WALL
@export var building_icon: Texture2D
@export var description: String = ""

@export_group("Construction")
@export var supply_cost: int = 5
@export var work_stages: Array[int] = [20, 20, 10]  # Work required per stage
@export var requires_cleared_terrain: bool = true
@export var requires_engineers: bool = true
@export var construction_slots: int = 1  # Firebase slots consumed

@export_group("Dimensions")
@export var footprint_size: Vector2 = Vector2(4, 4)  # Meters
@export var height: float = 1.5

@export_group("Defense")
@export var max_health: float = 100.0
@export var armor: float = 0.0
@export var provides_cover: float = 0.5  # 0-1, damage reduction for garrisoned units
@export var garrison_capacity: int = 0
@export var auto_attacks: bool = false
@export var attack_range: float = 0.0
@export var damage_per_second: float = 0.0
@export var weapon_class: int = -1

@export_group("Support Functions")
@export var sight_bonus: float = 0.0
@export var supply_storage: int = 0
@export var ammo_storage: int = 0
@export var resupply_range: float = 0.0
@export var healing_rate: float = 0.0
@export var enables_air_support: bool = false
@export var enables_reinforcements: bool = false
@export var is_landing_zone: bool = false
@export var lz_capacity: int = 0  # Number of helicopters

@export_group("Special")
@export var slows_enemies: bool = false
@export var slow_factor: float = 0.0
@export var damages_enemies: bool = false
@export var damage_to_enemies: float = 0.0
@export var blocks_line_of_sight: bool = false
@export var is_destructible: bool = true


# =============================================================================
# STATIC BUILDING DEFINITIONS
# =============================================================================

static var _buildings_cache: Dictionary = {}


static func get_building(building_type: int) -> BuildingData:
	if _buildings_cache.is_empty():
		_initialize_buildings()
	return _buildings_cache.get(building_type, _buildings_cache.get(GameEnums.BuildingType.SANDBAG_WALL))


static func _initialize_buildings() -> void:
	# Perimeter defenses
	_buildings_cache[GameEnums.BuildingType.SANDBAG_WALL] = _create_sandbag_wall()
	_buildings_cache[GameEnums.BuildingType.BUNKER] = _create_bunker()
	_buildings_cache[GameEnums.BuildingType.MACHINE_GUN_NEST] = _create_mg_nest()
	_buildings_cache[GameEnums.BuildingType.MORTAR_PIT] = _create_mortar_pit()
	_buildings_cache[GameEnums.BuildingType.WIRE_OBSTACLE] = _create_wire_obstacle()
	_buildings_cache[GameEnums.BuildingType.CLAYMORE_LINE] = _create_claymore_line()
	_buildings_cache[GameEnums.BuildingType.WATCHTOWER] = _create_watchtower()

	# Support structures
	_buildings_cache[GameEnums.BuildingType.HELIPAD] = _create_helipad()
	_buildings_cache[GameEnums.BuildingType.AMMO_BUNKER] = _create_ammo_bunker()
	_buildings_cache[GameEnums.BuildingType.FUEL_DEPOT] = _create_fuel_depot()
	_buildings_cache[GameEnums.BuildingType.MEDICAL_STATION] = _create_medical_station()
	_buildings_cache[GameEnums.BuildingType.TOC] = _create_toc()
	_buildings_cache[GameEnums.BuildingType.COMMO_BUNKER] = _create_commo_bunker()

	# Heavy
	_buildings_cache[GameEnums.BuildingType.ARTILLERY_PIT] = _create_artillery_pit()
	_buildings_cache[GameEnums.BuildingType.TANK_REVETMENT] = _create_tank_revetment()


# =============================================================================
# PERIMETER DEFENSES
# =============================================================================

static func _create_sandbag_wall() -> BuildingData:
	var b := BuildingData.new()
	b.building_name = "Sandbag Wall"
	b.building_type = GameEnums.BuildingType.SANDBAG_WALL
	b.description = "Basic defensive barrier providing light cover"
	b.supply_cost = 5
	b.work_stages = [20, 20, 10]
	b.footprint_size = Vector2(4, 1)
	b.height = 1.0
	b.max_health = 80.0
	b.provides_cover = 0.3
	b.blocks_line_of_sight = false
	return b


static func _create_bunker() -> BuildingData:
	var b := BuildingData.new()
	b.building_name = "Bunker"
	b.building_type = GameEnums.BuildingType.BUNKER
	b.description = "Hardened fighting position with overhead cover"
	b.supply_cost = 40
	b.work_stages = [40, 60, 40]
	b.footprint_size = Vector2(6, 6)
	b.height = 2.5
	b.max_health = 300.0
	b.armor = 10.0
	b.provides_cover = 0.7
	b.garrison_capacity = 8
	b.blocks_line_of_sight = true
	return b


static func _create_mg_nest() -> BuildingData:
	var b := BuildingData.new()
	b.building_name = "Machine Gun Nest"
	b.building_type = GameEnums.BuildingType.MACHINE_GUN_NEST
	b.description = "Emplaced M60 or M2 with sandbag protection"
	b.supply_cost = 30
	b.work_stages = [30, 40, 30]
	b.footprint_size = Vector2(4, 4)
	b.height = 1.2
	b.max_health = 120.0
	b.provides_cover = 0.5
	b.garrison_capacity = 3
	b.auto_attacks = true
	b.attack_range = 50.0
	b.damage_per_second = 25.0
	b.weapon_class = GameEnums.WeaponClass.M60
	return b


static func _create_mortar_pit() -> BuildingData:
	var b := BuildingData.new()
	b.building_name = "Mortar Pit"
	b.building_type = GameEnums.BuildingType.MORTAR_PIT
	b.description = "81mm mortar position for indirect fire support"
	b.supply_cost = 35
	b.work_stages = [30, 50, 30]
	b.footprint_size = Vector2(5, 5)
	b.height = 0.5
	b.max_health = 100.0
	b.provides_cover = 0.4
	b.garrison_capacity = 4
	b.auto_attacks = true
	b.attack_range = 100.0
	b.damage_per_second = 40.0
	b.weapon_class = GameEnums.WeaponClass.MORTAR_82MM
	return b


static func _create_wire_obstacle() -> BuildingData:
	var b := BuildingData.new()
	b.building_name = "Concertina Wire"
	b.building_type = GameEnums.BuildingType.WIRE_OBSTACLE
	b.description = "Barbed wire obstacle that slows and damages enemies"
	b.supply_cost = 10
	b.work_stages = [15, 15, 10]
	b.footprint_size = Vector2(8, 2)
	b.height = 0.8
	b.max_health = 50.0
	b.slows_enemies = true
	b.slow_factor = 0.7  # 70% slow
	b.damages_enemies = true
	b.damage_to_enemies = 2.0  # DPS while crossing
	return b


static func _create_claymore_line() -> BuildingData:
	var b := BuildingData.new()
	b.building_name = "Claymore Line"
	b.building_type = GameEnums.BuildingType.CLAYMORE_LINE
	b.description = "Directional anti-personnel mines along perimeter"
	b.supply_cost = 25
	b.work_stages = [20, 30, 15]
	b.footprint_size = Vector2(6, 1)
	b.height = 0.3
	b.max_health = 30.0
	b.damages_enemies = true
	b.damage_to_enemies = 150.0  # Triggered damage
	return b


static func _create_watchtower() -> BuildingData:
	var b := BuildingData.new()
	b.building_name = "Watchtower"
	b.building_type = GameEnums.BuildingType.WATCHTOWER
	b.description = "Elevated observation post with extended sight range"
	b.supply_cost = 25
	b.work_stages = [25, 35, 25]
	b.footprint_size = Vector2(3, 3)
	b.height = 8.0
	b.max_health = 80.0
	b.provides_cover = 0.3
	b.garrison_capacity = 2
	b.sight_bonus = 30.0  # +30m sight
	return b


# =============================================================================
# SUPPORT STRUCTURES
# =============================================================================

static func _create_helipad() -> BuildingData:
	var b := BuildingData.new()
	b.building_name = "Helipad"
	b.building_type = GameEnums.BuildingType.HELIPAD
	b.description = "Landing zone for helicopter operations"
	b.supply_cost = 50
	b.work_stages = [40, 50, 30]
	b.footprint_size = Vector2(15, 15)
	b.height = 0.1
	b.max_health = 100.0
	b.is_landing_zone = true
	b.lz_capacity = 2
	b.enables_reinforcements = true
	return b


static func _create_ammo_bunker() -> BuildingData:
	var b := BuildingData.new()
	b.building_name = "Ammo Bunker"
	b.building_type = GameEnums.BuildingType.AMMO_BUNKER
	b.description = "Ammunition storage and resupply point"
	b.supply_cost = 45
	b.work_stages = [35, 50, 35]
	b.footprint_size = Vector2(6, 6)
	b.height = 2.0
	b.max_health = 150.0
	b.armor = 5.0
	b.ammo_storage = 500
	b.resupply_range = 30.0
	return b


static func _create_fuel_depot() -> BuildingData:
	var b := BuildingData.new()
	b.building_name = "Fuel Depot"
	b.building_type = GameEnums.BuildingType.FUEL_DEPOT
	b.description = "Fuel storage for vehicles and helicopters"
	b.supply_cost = 40
	b.work_stages = [30, 45, 30]
	b.footprint_size = Vector2(8, 8)
	b.height = 3.0
	b.max_health = 100.0
	b.supply_storage = 300
	return b


static func _create_medical_station() -> BuildingData:
	var b := BuildingData.new()
	b.building_name = "Aid Station"
	b.building_type = GameEnums.BuildingType.MEDICAL_STATION
	b.description = "Medical treatment facility for wounded soldiers"
	b.supply_cost = 50
	b.work_stages = [40, 55, 35]
	b.footprint_size = Vector2(8, 8)
	b.height = 2.5
	b.max_health = 120.0
	b.provides_cover = 0.4
	b.healing_rate = 5.0  # HP per second for units in range
	b.resupply_range = 20.0
	return b


static func _create_toc() -> BuildingData:
	var b := BuildingData.new()
	b.building_name = "Tactical Operations Center"
	b.building_type = GameEnums.BuildingType.TOC
	b.description = "Command center enabling advanced coordination"
	b.supply_cost = 80
	b.work_stages = [60, 80, 60]
	b.footprint_size = Vector2(10, 10)
	b.height = 3.0
	b.max_health = 250.0
	b.armor = 8.0
	b.provides_cover = 0.6
	b.garrison_capacity = 6
	b.sight_bonus = 50.0
	b.enables_air_support = true
	b.enables_reinforcements = true
	b.blocks_line_of_sight = true
	return b


static func _create_commo_bunker() -> BuildingData:
	var b := BuildingData.new()
	b.building_name = "Communications Bunker"
	b.building_type = GameEnums.BuildingType.COMMO_BUNKER
	b.description = "Radio station for calling air support and reinforcements"
	b.supply_cost = 60
	b.work_stages = [45, 60, 40]
	b.footprint_size = Vector2(6, 6)
	b.height = 2.5
	b.max_health = 180.0
	b.armor = 5.0
	b.provides_cover = 0.5
	b.garrison_capacity = 4
	b.enables_air_support = true
	b.enables_reinforcements = true
	return b


# =============================================================================
# HEAVY STRUCTURES
# =============================================================================

static func _create_artillery_pit() -> BuildingData:
	var b := BuildingData.new()
	b.building_name = "Artillery Pit"
	b.building_type = GameEnums.BuildingType.ARTILLERY_PIT
	b.description = "Emplacement for 105mm howitzer"
	b.supply_cost = 100
	b.work_stages = [60, 100, 60]
	b.construction_slots = 2
	b.footprint_size = Vector2(12, 12)
	b.height = 1.0
	b.max_health = 200.0
	b.provides_cover = 0.5
	b.garrison_capacity = 6
	b.auto_attacks = true
	b.attack_range = 200.0  # Scaled for gameplay
	b.damage_per_second = 80.0
	b.weapon_class = GameEnums.WeaponClass.M102_HOWITZER
	return b


static func _create_tank_revetment() -> BuildingData:
	var b := BuildingData.new()
	b.building_name = "Tank Revetment"
	b.building_type = GameEnums.BuildingType.TANK_REVETMENT
	b.description = "Protective emplacement for armored vehicles"
	b.supply_cost = 70
	b.work_stages = [50, 70, 50]
	b.construction_slots = 2
	b.footprint_size = Vector2(10, 10)
	b.height = 2.0
	b.max_health = 250.0
	b.armor = 15.0
	b.provides_cover = 0.8
	b.garrison_capacity = 1  # One vehicle
	return b


# =============================================================================
# UTILITY METHODS
# =============================================================================

func get_total_work() -> int:
	var total := 0
	for work in work_stages:
		total += work
	return total


func get_stage_count() -> int:
	return work_stages.size()


func is_defensive() -> bool:
	return auto_attacks or provides_cover > 0.3


func is_support() -> bool:
	return enables_air_support or enables_reinforcements or healing_rate > 0 or resupply_range > 0


func is_obstacle() -> bool:
	return slows_enemies or damages_enemies


static func get_all_buildings() -> Array[BuildingData]:
	if _buildings_cache.is_empty():
		_initialize_buildings()

	var buildings: Array[BuildingData] = []
	for building in _buildings_cache.values():
		buildings.append(building)
	return buildings


static func get_buildings_by_category(category: String) -> Array[BuildingData]:
	var result: Array[BuildingData] = []

	match category:
		"perimeter":
			result = [
				get_building(GameEnums.BuildingType.SANDBAG_WALL),
				get_building(GameEnums.BuildingType.BUNKER),
				get_building(GameEnums.BuildingType.MACHINE_GUN_NEST),
				get_building(GameEnums.BuildingType.MORTAR_PIT),
				get_building(GameEnums.BuildingType.WIRE_OBSTACLE),
				get_building(GameEnums.BuildingType.CLAYMORE_LINE),
				get_building(GameEnums.BuildingType.WATCHTOWER),
			]
		"support":
			result = [
				get_building(GameEnums.BuildingType.HELIPAD),
				get_building(GameEnums.BuildingType.AMMO_BUNKER),
				get_building(GameEnums.BuildingType.FUEL_DEPOT),
				get_building(GameEnums.BuildingType.MEDICAL_STATION),
				get_building(GameEnums.BuildingType.TOC),
				get_building(GameEnums.BuildingType.COMMO_BUNKER),
			]
		"heavy":
			result = [
				get_building(GameEnums.BuildingType.ARTILLERY_PIT),
				get_building(GameEnums.BuildingType.TANK_REVETMENT),
			]

	return result
