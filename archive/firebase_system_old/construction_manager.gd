extends Node
## ConstructionManager - Manages firebase construction and building placement
## Accessed globally via ConstructionManager autoload (no class_name needed)

signal building_started(zone: Node3D, building_type: int)
signal building_progress(zone: Node3D, progress: float)
signal building_complete(building: Node3D)
signal building_cancelled(zone: Node3D)

# Building definitions
const BUILDING_DEFS := {
	GameEnums.BuildingType.SANDBAG_WALL: {
		"name": "Sandbag Wall",
		"supply_cost": 5,
		"stage_requirements": [20.0, 20.0, 10.0],  # Foundation, Structure, Finishing
		"footprint": Vector2(4, 1),
		"requires_clearing": false,
		"provides_cover": "medium",
	},
	GameEnums.BuildingType.BUNKER: {
		"name": "Bunker",
		"supply_cost": 40,
		"stage_requirements": [40.0, 60.0, 40.0],
		"footprint": Vector2(5, 5),
		"requires_clearing": true,
		"provides_cover": "heavy",
		"garrison_capacity": 8,
	},
	GameEnums.BuildingType.MACHINE_GUN_NEST: {
		"name": "MG Nest",
		"supply_cost": 30,
		"stage_requirements": [30.0, 40.0, 30.0],
		"footprint": Vector2(3, 3),
		"requires_clearing": true,
		"provides_cover": "heavy",
		"garrison_capacity": 3,
	},
	GameEnums.BuildingType.MORTAR_PIT: {
		"name": "Mortar Pit",
		"supply_cost": 35,
		"stage_requirements": [30.0, 50.0, 30.0],
		"footprint": Vector2(4, 4),
		"requires_clearing": true,
		"provides_cover": "medium",
	},
	GameEnums.BuildingType.WIRE_OBSTACLE: {
		"name": "Concertina Wire",
		"supply_cost": 10,
		"stage_requirements": [15.0, 15.0, 10.0],
		"footprint": Vector2(6, 1),
		"requires_clearing": false,
		"slows_enemies": true,
		"damages_enemies": true,
	},
	GameEnums.BuildingType.CLAYMORE_LINE: {
		"name": "Claymore Mines",
		"supply_cost": 25,
		"stage_requirements": [20.0, 30.0, 20.0],
		"footprint": Vector2(6, 2),
		"requires_clearing": false,
		"is_trap": true,
	},
	GameEnums.BuildingType.WATCHTOWER: {
		"name": "Watchtower",
		"supply_cost": 25,
		"stage_requirements": [25.0, 40.0, 25.0],
		"footprint": Vector2(3, 3),
		"requires_clearing": true,
		"sight_bonus": 50.0,
		"garrison_capacity": 2,
	},
	GameEnums.BuildingType.HELIPAD: {
		"name": "Helipad",
		"supply_cost": 50,
		"stage_requirements": [50.0, 60.0, 40.0],
		"footprint": Vector2(12, 12),
		"requires_clearing": true,
		"is_lz": true,
	},
	GameEnums.BuildingType.AMMO_BUNKER: {
		"name": "Ammo Bunker",
		"supply_cost": 35,
		"stage_requirements": [30.0, 50.0, 30.0],
		"footprint": Vector2(4, 4),
		"requires_clearing": true,
		"provides_cover": "heavy",
		"ammo_storage": 500,
	},
	GameEnums.BuildingType.FUEL_DEPOT: {
		"name": "Fuel Depot",
		"supply_cost": 40,
		"stage_requirements": [35.0, 50.0, 35.0],
		"footprint": Vector2(5, 5),
		"requires_clearing": true,
		"fuel_storage": 1000,
	},
	GameEnums.BuildingType.MEDICAL_STATION: {
		"name": "Aid Station",
		"supply_cost": 45,
		"stage_requirements": [35.0, 55.0, 40.0],
		"footprint": Vector2(5, 4),
		"requires_clearing": true,
		"provides_cover": "medium",
		"heals_units": true,
	},
	GameEnums.BuildingType.TOC: {
		"name": "Tactical Operations Center",
		"supply_cost": 80,
		"stage_requirements": [60.0, 80.0, 60.0],
		"footprint": Vector2(6, 6),
		"requires_clearing": true,
		"provides_cover": "heavy",
		"is_hq": true,
		"sight_bonus": 100.0,
	},
	GameEnums.BuildingType.COMMO_BUNKER: {
		"name": "Communications Bunker",
		"supply_cost": 50,
		"stage_requirements": [40.0, 60.0, 40.0],
		"footprint": Vector2(4, 4),
		"requires_clearing": true,
		"provides_cover": "heavy",
		"enables_air_support": true,
	},
	GameEnums.BuildingType.ARTILLERY_PIT: {
		"name": "Artillery Pit",
		"supply_cost": 100,
		"stage_requirements": [60.0, 100.0, 60.0],
		"footprint": Vector2(8, 8),
		"requires_clearing": true,
		"provides_cover": "medium",
	},
	GameEnums.BuildingType.TANK_REVETMENT: {
		"name": "Tank Revetment",
		"supply_cost": 60,
		"stage_requirements": [50.0, 70.0, 40.0],
		"footprint": Vector2(7, 5),
		"requires_clearing": true,
		"provides_cover": "heavy",
		"vehicle_shelter": true,
	},
}

# Construction work rate per engineer per second
const ENGINEER_WORK_RATE := 2.0

# Active construction sites
var construction_sites: Array = []  # Array of ConstructionZone

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	_process_construction_sites(delta)

# =============================================================================
# BUILDING MANAGEMENT
# =============================================================================

func get_building_info(building_type: int) -> Dictionary:
	return BUILDING_DEFS.get(building_type, {})

func get_building_cost(building_type: int) -> int:
	var info: Dictionary = get_building_info(building_type)
	return info.get("supply_cost", 0)

func can_build(building_type: int, supplies: int) -> bool:
	var cost := get_building_cost(building_type)
	return supplies >= cost

func get_all_building_types() -> Array:
	return BUILDING_DEFS.keys()

# =============================================================================
# CONSTRUCTION
# =============================================================================

func start_construction(building_type: int, zone) -> bool:  # zone: ConstructionZone
	## Start building at a construction zone
	if not zone.can_build():
		return false

	var info: Dictionary = get_building_info(building_type)
	if info.is_empty():
		return false

	# Check if clearing required
	if info.get("requires_clearing", true) and not zone.is_cleared():
		return false

	zone.start_construction(building_type)
	construction_sites.append(zone)

	building_started.emit(zone, building_type)

	return true

func cancel_construction(zone) -> void:  # zone: ConstructionZone
	## Cancel ongoing construction
	construction_sites.erase(zone)
	building_cancelled.emit(zone)

func _process_construction_sites(delta: float) -> void:
	var completed: Array = []  # Array of ConstructionZone

	for zone in construction_sites:
		if not is_instance_valid(zone):
			completed.append(zone)
			continue

		if zone.construction_stage == GameEnums.ConstructionStage.COMPLETE:
			completed.append(zone)
			building_complete.emit(zone.building_instance)
			continue

		# Get work from engineers
		var engineer_count: int = zone.get_engineer_count()
		if engineer_count == 0:
			continue

		var work := ENGINEER_WORK_RATE * engineer_count * delta
		zone.add_construction_progress(work)

		building_progress.emit(zone, zone.construction_progress)

	# Remove completed sites
	for zone in completed:
		construction_sites.erase(zone)

# =============================================================================
# BLUEPRINT SYSTEM
# =============================================================================

func get_blueprint(building_type: int) -> Dictionary:
	## Get construction blueprint for a building type
	var info: Dictionary = get_building_info(building_type)

	return {
		"type": building_type,
		"name": info.get("name", "Unknown"),
		"footprint": info.get("footprint", Vector2(4, 4)),
		"stage_requirements": info.get("stage_requirements", [100.0, 100.0, 100.0]),
		"requires_clearing": info.get("requires_clearing", true),
	}

func get_total_build_time(building_type: int, engineer_count: int) -> float:
	## Estimate total build time in seconds
	var info: Dictionary = get_building_info(building_type)
	var stages: Array = info.get("stage_requirements", [100.0, 100.0, 100.0])

	var total_work := 0.0
	for stage_req in stages:
		total_work += stage_req

	if engineer_count <= 0:
		return INF

	return total_work / (ENGINEER_WORK_RATE * engineer_count)
