extends Resource
class_name BuildingData

## Building Data - Defines a constructible building type
## Comprehensive Vietnam War-era structures for RTS gameplay

# Self-reference for static factory methods (avoids circular reference during parsing)
const _Self := preload("res://firebase_system/building_data.gd")

# =============================================================================
# BUILDING TYPE ENUMERATION
# =============================================================================
enum BuildingType {
	# -------------------------------------------------------------------------
	# FIREBASE PERIMETER (0-10)
	# -------------------------------------------------------------------------
	SANDBAG_LIGHT,          # 0 - Light field sandbags (infantry/engineer placeable)
	SANDBAG_HEAVY,          # 1 - Heavy fortification sandbags (bulldozer only)
	BUNKER,                 # 2 - Hardened fighting position (existing)
	SANDBAG_BUNKER,         # 3 - Standard fighting position, overhead PSP cover
	CONEX_BUNKER,           # 4 - Converted shipping container with sandbags
	MACHINE_GUN_NEST,       # 5 - M60 emplacement with 360 deg coverage
	MORTAR_PIT,             # 6 - 81mm mortar position
	WIRE_OBSTACLE,          # 7 - Concertina wire, slows + damages
	TRIPLE_CONCERTINA,      # 8 - Pyramid wire obstacle
	CLAYMORE_LINE,          # 9 - Directional mines
	WATCHTOWER,             # 10 - Vision, sniper position

	# -------------------------------------------------------------------------
	# FIREBASE SUPPORT (10-19)
	# -------------------------------------------------------------------------
	HELIPAD,                # 10 - Landing zone
	PSP_HELIPAD,            # 11 - Steel matting landing pad
	VIP_HELIPAD,            # 12 - Small dedicated pad
	HELICOPTER_REVETMENT,   # 13 - Protective sandbag walls for helos
	AMMO_BUNKER,            # 14 - Ammunition resupply point
	FUEL_DEPOT,             # 15 - Vehicle/heli fuel
	FUEL_POINT,             # 16 - JP-4 dispensing station
	MEDICAL_STATION,        # 17 - Casualty treatment (Aid Station)
	TOC,                    # 18 - Tactical Operations Center (Command Bunker)
	COMMO_BUNKER,           # 19 - Radio, call air support

	# -------------------------------------------------------------------------
	# FIREBASE LIVING (20-26)
	# -------------------------------------------------------------------------
	HOOTCH,                 # 20 - Canvas tent with sandbag walls
	MESS_HALL,              # 21 - Wooden structure with metal roof
	LATRINE,                # 22 - Simple wooden outhouse
	SHOWER_POINT,           # 23 - Open wooden structure
	OBSERVATION_TOWER,      # 24 - Wooden watchtower with sandbag base
	GUARD_TOWER,            # 25 - Prison watchtower
	POWDER_BUNKER,          # 26 - Ammunition propellant storage

	# -------------------------------------------------------------------------
	# FIREBASE HEAVY (27-32)
	# -------------------------------------------------------------------------
	ARTILLERY_PIT,          # 27 - 105mm howitzer emplacement
	HOWITZER_PIT_105MM,     # 28 - Circular sandbagged emplacement
	HOWITZER_PIT_155MM,     # 29 - Large artillery position
	FIRE_DIRECTION_CENTER,  # 30 - Control bunker for artillery
	TANK_REVETMENT,         # 31 - Protected vehicle fighting position
	OPEN_REVETMENT,         # 32 - U-shaped earth/sandbag walls

	# -------------------------------------------------------------------------
	# VIETNAMESE VILLAGE (33-47)
	# -------------------------------------------------------------------------
	THATCHED_HUT,           # 33 - Bamboo frame, palm/straw roof
	CLAY_WALL_COTTAGE,      # 34 - Clay/straw walls with steep thatched roof
	STILT_HOUSE,            # 35 - Raised on wooden stilts
	THREE_ROOM_HOUSE,       # 36 - Traditional 3-compartment layout
	COMMUNAL_HOUSE,         # 37 - Large Dinh, village center
	VILLAGE_WELL,           # 38 - Stone/brick circular well
	RICE_STORAGE_SHED,      # 39 - Elevated bamboo granary
	WATER_BUFFALO_SHED,     # 40 - Simple bamboo shelter
	BAMBOO_FENCE,           # 41 - Woven bamboo perimeter
	VILLAGE_GATE,           # 42 - Wooden arch gateway
	VILLAGE_PAGODA,         # 43 - Small rural temple
	TAM_QUAN_GATE,          # 44 - Three-door temple entrance
	BELL_TOWER,             # 45 - Temple bell structure
	MONK_QUARTERS,          # 46 - Simple living building
	STONE_BUDDHA,           # 47 - Seated Buddha statue

	# -------------------------------------------------------------------------
	# AIRFIELD STRUCTURES (48-66)
	# -------------------------------------------------------------------------
	RUNWAY_CONCRETE,        # 48 - Standard concrete runway segment
	RUNWAY_PSP,             # 49 - Pierced steel planking
	RUNWAY_AM2,             # 50 - AM-2 aluminum matting
	TAXIWAY_SECTION,        # 51 - Connecting runway to apron
	RUNWAY_CRATER,          # 52 - Bomb damage crater
	WONDERARCH_SHELTER,     # 53 - Concrete aircraft shelter
	PSP_REVETMENT,          # 54 - Steel planking aircraft bay
	AIRCRAFT_HANGAR,        # 55 - Large maintenance building
	MAINTENANCE_SHOP,       # 56 - Engine/airframe repair
	CONTROL_TOWER,          # 57 - Air traffic control
	RADAR_DOME,             # 58 - Ground control approach
	OPERATIONS_BUILDING,    # 59 - Flight planning/briefing
	POL_STORAGE,            # 60 - Fuel tanks and pumps
	FIRE_STATION,           # 61 - Crash/rescue equipment
	AMMO_STORAGE_AIRFIELD,  # 62 - Bombs/rockets bunker
	QUONSET_HUT,            # 63 - Corrugated steel arch
	SUPPLY_WAREHOUSE,       # 64 - Large storage building
	AMMO_DUMP_BUNKER,       # 65 - Earth-covered igloo
	POL_TANK_FARM,          # 66 - Multiple fuel tanks

	# -------------------------------------------------------------------------
	# FRENCH COLONIAL (67-75)
	# -------------------------------------------------------------------------
	COLONIAL_VILLA,         # 67 - Two-story with balconies
	PLANTATION_HOUSE,       # 68 - Large estate house with veranda
	GOVERNMENT_BUILDING,    # 69 - Neoclassical with columns
	FRENCH_BARRACKS,        # 70 - Long two-story building
	COLONIAL_PRISON,        # 71 - Hoa Lo style prison
	RUBBER_PLANT,           # 72 - Factory with smokestacks
	COLONIAL_WAREHOUSE,     # 73 - Colonial storage building
	RAILWAY_STATION,        # 74 - French-style depot
	CUSTOMS_BUILDING,       # 75 - Port office

	# -------------------------------------------------------------------------
	# INFRASTRUCTURE (76-86)
	# -------------------------------------------------------------------------
	STEEL_TRUSS_BRIDGE,     # 76 - Railroad/road bridge
	WOODEN_BRIDGE,          # 77 - Simple timber crossing
	PONTOON_BRIDGE,         # 78 - Floating military bridge
	STONE_ARCH_BRIDGE,      # 79 - French colonial era
	DOCK_PIER,              # 80 - Wooden jetty
	CARGO_CRANE,            # 81 - Port crane
	CONTAINER_YARD,         # 82 - Stacked CONEX boxes
	DIRT_ROAD_SECTION,      # 83 - Unpaved village road
	LATERITE_ROAD,          # 84 - Red clay surface
	PAVED_ROAD_SECTION,     # 85 - Asphalt highway
	TRAIL_PATH,             # 86 - Jungle footpath

	# -------------------------------------------------------------------------
	# VC/NVA SPECIAL (87-94)
	# -------------------------------------------------------------------------
	TUNNEL_ENTRANCE_HIDDEN, # 87 - Camouflaged trap door
	TUNNEL_ENTRANCE_EXPOSED,# 88 - Discovered/blown open
	SPIDER_HOLE,            # 89 - One-man fighting position
	PUNJI_PIT,              # 90 - Concealed spike trap
	UNDERGROUND_HOSPITAL,   # 91 - Bunker complex entrance
	WEAPONS_CACHE,          # 92 - Hidden storage
	STOCKADE_COMPOUND,      # 93 - Barbed wire prison area
	PRISONER_TENT,          # 94 - POW tent

	# -------------------------------------------------------------------------
	# RUINS & DESTRUCTION (95-106)
	# -------------------------------------------------------------------------
	CRATER_FIELD,           # 95 - Multiple overlapping bomb craters
	COLLAPSED_BUILDING,     # 96 - Walls fallen, roof destroyed
	BURNED_STRUCTURE,       # 97 - Charred frame, no roof
	PARTIAL_RUINS,          # 98 - 1-2 walls standing
	FOUNDATION_ONLY,        # 99 - Just floor/foundation remains
	DESTROYED_VILLAGE,      # 100 - 3-5 burned huts, crater
	BOMBED_PAGODA,          # 101 - Collapsed roof, broken walls
	CRATERED_RUNWAY,        # 102 - Runway section with 3+ craters
	BURNED_BUNKER,          # 103 - Blackened sandbags, collapsed roof
	DESTROYED_BRIDGE,       # 104 - Collapsed span, twisted metal
	RUBBLE_PILE,            # 105 - Generic debris
	CONEX_CELL,             # 106 - Solitary confinement box (POW)

	# -------------------------------------------------------------------------
	# CHAM RUINS (107-109)
	# -------------------------------------------------------------------------
	CHAM_TEMPLE_TOWER,      # 107 - Brick tower ruin (My Son style)
	CHAM_TEMPLE_BASE,       # 108 - Foundation platform
	CHAM_BROKEN_COLUMN,     # 109 - Fallen masonry

	# -------------------------------------------------------------------------
	# COMMERCIAL / MARKETPLACE (110-113)
	# -------------------------------------------------------------------------
	MARKET_HALL,            # 110 - Covered market structure
	SHOP_HOUSE,             # 111 - Two-story merchant building
	MARKET_STALL,           # 112 - Simple vendor booth
	FOOD_VENDOR_CART,       # 113 - Mobile street food

	# -------------------------------------------------------------------------
	# FIREBASE LOGISTICS (114+)
	# -------------------------------------------------------------------------
	SUPPLY_DEPOT,           # 114 - Main supply storage and distribution hub

	# -------------------------------------------------------------------------
	# ADDITIONAL FIREBASE DEFENSES (115-117)
	# -------------------------------------------------------------------------
	TANK_TRAP,              # 115 - Anti-vehicle obstacle (Czech hedgehog style)
	FOXHOLE,                # 116 - Individual fighting position with sandbags
	TRENCH,                 # 117 - Linear defensive earthwork

	# -------------------------------------------------------------------------
	# SUPPLY CHAIN / LOGISTICS (118-119)
	# -------------------------------------------------------------------------
	TRUCK_STAGING_AREA,     # 118 - Supply convoy spawn point
	MODULAR_BRIDGE,         # 119 - Spans water/ravines
}

# =============================================================================
# DESTRUCTION STATES
# =============================================================================
enum DestructionState {
	INTACT,
	DAMAGED,
	BURNED,
	RUINS,
	DESTROYED,
	EXPLODED,
	COLLAPSED,
	CRATERED,
}

# =============================================================================
# BUILDING CATEGORY
# =============================================================================
enum BuildingCategory {
	FIREBASE_PERIMETER,
	FIREBASE_SUPPORT,
	FIREBASE_LIVING,
	FIREBASE_HEAVY,
	VIETNAMESE_VILLAGE,
	AIRFIELD,
	FRENCH_COLONIAL,
	INFRASTRUCTURE,
	VC_NVA_SPECIAL,
	RUINS,
	CHAM_RUINS,
	COMMERCIAL,
}

# =============================================================================
# EXPORTED PROPERTIES
# =============================================================================

@export var building_type: BuildingType = BuildingType.SANDBAG_LIGHT
@export var display_name: String = "Sandbag (Light)"
@export var description: String = ""
@export var category: BuildingCategory = BuildingCategory.FIREBASE_PERIMETER

## Cost and Construction
@export var supply_cost: int = 5
@export var build_time: float = 30.0
@export var stage_work: Array[float] = [20.0, 20.0, 10.0]

## Physical Dimensions (in meters)
@export var footprint_size: Vector2 = Vector2(3, 3)
@export var height: float = 2.0

## Combat Stats
@export var health: float = 100.0
@export var armor: float = 0.0
@export var garrison_capacity: int = 0
@export var sight_range: float = 0.0
@export var provides_cover: bool = true
@export var cover_value: float = 0.5

## Logistics System (Three Pillars)
@export var morale_bonus: int = 0  ## QoL buildings provide morale
@export var is_water_source: bool = false  ## Provides water to firebase

## Requirements
@export var requires_cleared_terrain: bool = true
@export var requires_firebase_level: int = 0
@export var construction_slots: int = 1

## Destruction States Available
@export var destruction_states: Array[DestructionState] = [DestructionState.INTACT]

## Special Properties
@export var slows_enemies: bool = false
@export var slow_factor: float = 0.0
@export var damages_enemies: bool = false
@export var damage_to_enemies: float = 0.0
@export var auto_attacks: bool = false
@export var attack_range: float = 0.0
@export var weapon_class: int = -1  # WeaponClass enum from game_enums
@export var defense_weapon: String = ""  # VietnamWeaponData ID for auto-defense
@export var defense_type: int = 0  # DefensiveStructure.DefenseType enum
@export var requires_garrison_to_fire: bool = false  # If true, needs infantry to operate
@export var is_flammable: bool = false
@export var is_explosive: bool = false

## Directional Fire Arc (Weapon Emplacements)
@export var fire_arc: float = 360.0  # Firing arc in degrees - 360 = full rotation
@export var weapon_range: float = 0.0  # Weapon range in meters - 0 = no arc display
@export var rotatable_post_placement: bool = false  # Can rotate after placement (artillery)
@export var initial_facing: float = 0.0  # Facing direction set during placement (degrees)

## HQ Building (PRD Phase 4 - Firebase Influence)
@export var is_hq_building: bool = false  ## If true, activates firebase influence radius
@export var influence_radius: float = 150.0  ## Influence radius when this HQ is active (per PRD)

## Placement Properties
## CoH-style linear placement implemented in PlacementController (firebase_system/placement_controller.gd)
## - Click start, drag to end, preview shows segments along line with per-segment validation
## - Workers auto-assign to build jobs via WorkerController (bottom-up job finding)
@export var is_linear_placement: bool = false  # Can be placed in lines (sandbags, wire)
@export var requires_bulldozer: bool = false   # Only bulldozer can place this
@export var can_place_anywhere: bool = false   # Can be placed outside firebases (field defenses)


# =============================================================================
# STATIC FACTORY METHODS
# =============================================================================

static func get_building_data(type: BuildingType) -> BuildingData:
	"""Get building data for a building type"""
	var data := _Self.new()
	data.building_type = type

	match type:
		# =====================================================================
		# FIREBASE PERIMETER
		# =====================================================================
		BuildingType.SANDBAG_LIGHT:
			data.display_name = "Sandbag (Light)"
			data.description = "Quick field cover - riflemen and engineers can build anywhere"
			data.category = BuildingCategory.FIREBASE_PERIMETER
			data.supply_cost = 0  # Free - quick field defense
			data.stage_work = [10.0, 10.0, 5.0]  # Fast build
			data.health = 75.0  # Lower HP than heavy
			data.provides_cover = true
			data.cover_value = 0.4
			data.footprint_size = Vector2(3, 1)
			data.height = 1.0
			data.is_linear_placement = true
			data.requires_bulldozer = false
			data.can_place_anywhere = true  # Field defenses
			data.requires_cleared_terrain = false  # Can place on any terrain
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.SANDBAG_HEAVY:
			data.display_name = "Sandbag (Heavy)"
			data.description = "Fortified sandbag wall - bulldozer placement in firebases only"
			data.category = BuildingCategory.FIREBASE_PERIMETER
			data.supply_cost = 10
			data.stage_work = [25.0, 30.0, 15.0]
			data.health = 200.0  # Higher HP
			data.armor = 2.0  # Light armor
			data.provides_cover = true
			data.cover_value = 0.6
			data.footprint_size = Vector2(4, 1.5)
			data.height = 1.2
			data.is_linear_placement = true
			data.requires_bulldozer = true  # Only bulldozer
			data.can_place_anywhere = false  # Firebase/fortified only
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.BUNKER:
			data.display_name = "Bunker"
			data.description = "Hardened fighting position - 120-degree arc from firing ports"
			data.category = BuildingCategory.FIREBASE_PERIMETER
			data.supply_cost = 40
			data.stage_work = [40.0, 60.0, 40.0]
			data.health = 400.0
			data.armor = 10.0
			data.garrison_capacity = 8
			data.footprint_size = Vector2(4, 4)
			data.height = 2.5
			data.cover_value = 0.8
			data.auto_attacks = true
			data.attack_range = 300.0
			data.defense_weapon = "m16"  # Garrison fires rifles
			data.defense_type = 1  # BUNKER
			data.requires_garrison_to_fire = true  # Needs infantry
			# Directional fire arc - fixed position after placement
			data.fire_arc = 120.0
			data.weapon_range = 300.0
			data.rotatable_post_placement = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.SANDBAG_BUNKER:
			data.display_name = "Sandbag Bunker"
			data.description = "Standard fighting position with PSP overhead cover"
			data.category = BuildingCategory.FIREBASE_PERIMETER
			data.supply_cost = 25
			data.stage_work = [25.0, 35.0, 25.0]
			data.health = 200.0
			data.armor = 5.0
			data.garrison_capacity = 4
			data.footprint_size = Vector2(3, 3)
			data.height = 2.0
			data.cover_value = 0.7
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.CONEX_BUNKER:
			data.display_name = "CONEX Bunker"
			data.description = "Converted shipping container with sandbag protection"
			data.category = BuildingCategory.FIREBASE_PERIMETER
			data.supply_cost = 45
			data.stage_work = [30.0, 50.0, 30.0]
			data.health = 500.0
			data.armor = 15.0
			data.garrison_capacity = 6
			data.footprint_size = Vector2(6, 2.5)
			data.height = 2.5
			data.cover_value = 0.9
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.MACHINE_GUN_NEST:
			data.display_name = "MG Nest"
			data.description = "M60 emplacement with 60-degree fire arc - auto-engages enemies"
			data.category = BuildingCategory.FIREBASE_PERIMETER
			data.supply_cost = 30
			data.stage_work = [30.0, 40.0, 30.0]
			data.health = 200.0
			data.garrison_capacity = 2
			data.sight_range = 40.0
			data.footprint_size = Vector2(2, 2)
			data.height = 1.0
			data.auto_attacks = true
			data.attack_range = 500.0
			# Directional fire arc - fixed position after placement
			data.fire_arc = 60.0
			data.weapon_range = 500.0
			data.rotatable_post_placement = false
			data.defense_weapon = "m60"  # M60 machine gun
			data.defense_type = 0  # MG_NEST
			data.requires_garrison_to_fire = false  # Operates standalone
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.MORTAR_PIT:
			data.display_name = "Mortar Pit"
			data.description = "81mm mortar position - 90-degree arc, indirect fire support"
			data.category = BuildingCategory.FIREBASE_PERIMETER
			data.supply_cost = 35
			data.stage_work = [30.0, 50.0, 30.0]
			data.health = 150.0
			data.garrison_capacity = 3
			data.footprint_size = Vector2(3, 3)
			data.height = 1.0
			data.auto_attacks = true
			data.attack_range = 3500.0
			data.defense_weapon = "mortar_81mm"  # 81mm mortar
			data.defense_type = 2  # MORTAR_PIT
			data.requires_garrison_to_fire = true  # Needs crew to operate
			# Directional fire arc - fixed position after placement
			data.fire_arc = 90.0
			data.weapon_range = 3500.0
			data.rotatable_post_placement = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.WIRE_OBSTACLE:
			data.display_name = "Concertina Wire"
			data.description = "Slows and damages enemies crossing"
			data.category = BuildingCategory.FIREBASE_PERIMETER
			data.supply_cost = 10
			data.stage_work = [15.0, 15.0, 10.0]
			data.health = 50.0
			data.footprint_size = Vector2(6, 1)
			data.height = 1.0
			data.provides_cover = false
			data.slows_enemies = true
			data.slow_factor = 0.3
			data.damages_enemies = true
			data.damage_to_enemies = 2.0
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]
			data.is_linear_placement = true
			data.can_place_anywhere = true
			data.requires_cleared_terrain = false

		BuildingType.TRIPLE_CONCERTINA:
			data.display_name = "Triple Concertina"
			data.description = "Pyramid wire obstacle - maximum area denial"
			data.category = BuildingCategory.FIREBASE_PERIMETER
			data.supply_cost = 15
			data.stage_work = [20.0, 20.0, 15.0]
			data.health = 80.0
			data.footprint_size = Vector2(6, 1)
			data.height = 1.0
			data.provides_cover = false
			data.slows_enemies = true
			data.slow_factor = 0.2
			data.damages_enemies = true
			data.damage_to_enemies = 4.0
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]
			data.is_linear_placement = true
			data.can_place_anywhere = true
			data.requires_cleared_terrain = false

		BuildingType.CLAYMORE_LINE:
			data.display_name = "Claymore Mines"
			data.description = "Directional anti-personnel mines"
			data.category = BuildingCategory.FIREBASE_PERIMETER
			data.supply_cost = 25
			data.stage_work = [20.0, 30.0, 20.0]
			data.health = 30.0
			data.footprint_size = Vector2(8, 1)
			data.height = 0.3
			data.provides_cover = false
			data.is_explosive = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.EXPLODED]
			data.is_linear_placement = true
			data.can_place_anywhere = true
			data.requires_cleared_terrain = false

		BuildingType.WATCHTOWER:
			data.display_name = "Watchtower"
			data.description = "Extended vision, sniper position - auto-engages enemies"
			data.category = BuildingCategory.FIREBASE_PERIMETER
			data.supply_cost = 25
			data.stage_work = [30.0, 40.0, 30.0]
			data.health = 150.0
			data.garrison_capacity = 2
			data.sight_range = 60.0
			data.footprint_size = Vector2(2, 2)
			data.height = 4.0
			data.is_flammable = true
			data.auto_attacks = true
			data.attack_range = 400.0
			data.defense_weapon = "m14"  # Accurate rifle for sniping
			data.defense_type = 3  # WATCHTOWER
			data.requires_garrison_to_fire = true  # Needs garrison to fire
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.BURNED]

		# =====================================================================
		# FIREBASE SUPPORT
		# =====================================================================
		BuildingType.HELIPAD:
			data.display_name = "Helipad"
			data.description = "Helicopter landing zone"
			data.category = BuildingCategory.FIREBASE_SUPPORT
			data.supply_cost = 50
			data.stage_work = [40.0, 50.0, 40.0]
			data.health = 100.0
			data.footprint_size = Vector2(8, 8)
			data.height = 0.2
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.PSP_HELIPAD:
			data.display_name = "PSP Helipad"
			data.description = "Steel matting landing pad"
			data.category = BuildingCategory.FIREBASE_SUPPORT
			data.supply_cost = 60
			data.stage_work = [45.0, 55.0, 45.0]
			data.health = 150.0
			data.footprint_size = Vector2(15, 15)
			data.height = 0.1
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.VIP_HELIPAD:
			data.display_name = "VIP Helipad"
			data.description = "Small dedicated landing pad"
			data.category = BuildingCategory.FIREBASE_SUPPORT
			data.supply_cost = 40
			data.stage_work = [30.0, 40.0, 30.0]
			data.health = 80.0
			data.footprint_size = Vector2(10, 10)
			data.height = 0.1
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.HELICOPTER_REVETMENT:
			data.display_name = "Helicopter Revetment"
			data.description = "Protective sandbag walls for helicopter parking"
			data.category = BuildingCategory.FIREBASE_SUPPORT
			data.supply_cost = 55
			data.stage_work = [40.0, 60.0, 40.0]
			data.health = 200.0
			data.footprint_size = Vector2(15, 12)
			data.height = 2.0
			data.cover_value = 0.6
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.AMMO_BUNKER:
			data.display_name = "Ammo Bunker"
			data.description = "Ammunition resupply point"
			data.category = BuildingCategory.FIREBASE_SUPPORT
			data.supply_cost = 45
			data.stage_work = [40.0, 60.0, 40.0]
			data.health = 300.0
			data.armor = 10.0
			data.footprint_size = Vector2(6, 4)
			data.height = 3.0
			data.is_explosive = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.EXPLODED]

		BuildingType.FUEL_DEPOT:
			data.display_name = "Fuel Depot"
			data.description = "Vehicle and helicopter fuel storage"
			data.category = BuildingCategory.FIREBASE_SUPPORT
			data.supply_cost = 40
			data.stage_work = [35.0, 50.0, 35.0]
			data.health = 150.0
			data.footprint_size = Vector2(5, 5)
			data.height = 3.0
			data.is_flammable = true
			data.is_explosive = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.BURNED, DestructionState.EXPLODED]

		BuildingType.FUEL_POINT:
			data.display_name = "Fuel Point"
			data.description = "JP-4 dispensing station"
			data.category = BuildingCategory.FIREBASE_SUPPORT
			data.supply_cost = 30
			data.stage_work = [25.0, 35.0, 25.0]
			data.health = 80.0
			data.footprint_size = Vector2(5, 5)
			data.height = 3.0
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.BURNED]

		BuildingType.MEDICAL_STATION:
			data.display_name = "Aid Station"
			data.description = "Medical tent - heals wounded soldiers"
			data.category = BuildingCategory.FIREBASE_SUPPORT
			data.supply_cost = 35
			data.stage_work = [30.0, 50.0, 30.0]
			data.health = 200.0
			data.footprint_size = Vector2(8, 6)
			data.height = 3.0
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.BURNED]

		BuildingType.TOC:
			data.display_name = "TOC"
			data.description = "Tactical Operations Center - can be placed anywhere to establish a new firebase. Creates 150m influence zone."
			data.category = BuildingCategory.FIREBASE_SUPPORT
			data.supply_cost = 80
			data.stage_work = [60.0, 80.0, 60.0]
			data.health = 500.0
			data.armor = 10.0
			data.sight_range = 100.0
			data.requires_firebase_level = 0  # TOC starts a firebase, doesn't require one
			data.footprint_size = Vector2(6, 4)
			data.height = 2.5
			data.construction_slots = 2
			data.is_hq_building = true  # PRD Phase 4: Activates firebase
			data.influence_radius = 150.0  # Per PRD: 150m influence radius
			data.can_place_anywhere = true  # TOC can be placed anywhere to start a new firebase
			data.requires_cleared_terrain = false  # Will need clearing around it, but can initiate anywhere
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.COMMO_BUNKER:
			data.display_name = "Commo Bunker"
			data.description = "Radio communications - calls air support"
			data.category = BuildingCategory.FIREBASE_SUPPORT
			data.supply_cost = 50
			data.stage_work = [40.0, 60.0, 40.0]
			data.health = 300.0
			data.armor = 5.0
			data.requires_firebase_level = 1
			data.footprint_size = Vector2(4, 4)
			data.height = 2.5
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		# =====================================================================
		# FIREBASE LIVING
		# =====================================================================
		BuildingType.HOOTCH:
			data.display_name = "Hootch"
			data.description = "Canvas tent with sandbag walls - living quarters"
			data.category = BuildingCategory.FIREBASE_LIVING
			data.supply_cost = 20
			data.stage_work = [20.0, 30.0, 20.0]
			data.health = 100.0
			data.footprint_size = Vector2(6, 4)
			data.height = 3.0
			data.is_flammable = true
			data.morale_bonus = 10  # QoL: Rest quarters
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.BURNED]

		BuildingType.MESS_HALL:
			data.display_name = "Mess Hall"
			data.description = "Wooden structure with metal roof"
			data.category = BuildingCategory.FIREBASE_LIVING
			data.supply_cost = 45
			data.stage_work = [40.0, 60.0, 40.0]
			data.health = 200.0
			data.footprint_size = Vector2(12, 8)
			data.height = 4.0
			data.is_flammable = true
			data.morale_bonus = 15  # QoL: Hot food
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.BURNED]

		BuildingType.LATRINE:
			data.display_name = "Latrine"
			data.description = "Simple wooden outhouse"
			data.category = BuildingCategory.FIREBASE_LIVING
			data.supply_cost = 5
			data.stage_work = [10.0, 10.0, 5.0]
			data.health = 30.0
			data.footprint_size = Vector2(2, 1.5)
			data.height = 2.5
			data.morale_bonus = 5  # QoL: Basic sanitation
			data.is_flammable = true
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.BURNED]

		BuildingType.SHOWER_POINT:
			data.display_name = "Shower Point"
			data.description = "Open wooden structure"
			data.category = BuildingCategory.FIREBASE_LIVING
			data.supply_cost = 10
			data.stage_work = [15.0, 15.0, 10.0]
			data.health = 40.0
			data.footprint_size = Vector2(3, 3)
			data.height = 2.5
			data.is_flammable = true
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.OBSERVATION_TOWER:
			data.display_name = "Observation Tower"
			data.description = "Tall wooden watchtower with sandbag base"
			data.category = BuildingCategory.FIREBASE_LIVING
			data.supply_cost = 30
			data.stage_work = [35.0, 45.0, 30.0]
			data.health = 180.0
			data.garrison_capacity = 2
			data.sight_range = 80.0
			data.footprint_size = Vector2(2, 2)
			data.height = 8.0
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.BURNED]

		BuildingType.GUARD_TOWER:
			data.display_name = "Guard Tower"
			data.description = "Prison/compound watchtower"
			data.category = BuildingCategory.FIREBASE_LIVING
			data.supply_cost = 25
			data.stage_work = [30.0, 40.0, 25.0]
			data.health = 150.0
			data.garrison_capacity = 2
			data.sight_range = 60.0
			data.footprint_size = Vector2(2, 2)
			data.height = 6.0
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.POWDER_BUNKER:
			data.display_name = "Powder Bunker"
			data.description = "Ammunition propellant storage"
			data.category = BuildingCategory.FIREBASE_LIVING
			data.supply_cost = 35
			data.stage_work = [30.0, 45.0, 30.0]
			data.health = 150.0
			data.armor = 5.0
			data.footprint_size = Vector2(3, 3)
			data.height = 2.0
			data.is_explosive = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.EXPLODED]

		# =====================================================================
		# FIREBASE HEAVY
		# =====================================================================
		BuildingType.ARTILLERY_PIT:
			data.display_name = "Artillery Pit"
			data.description = "105mm howitzer emplacement - 360-degree rotation, long range fire support"
			data.category = BuildingCategory.FIREBASE_HEAVY
			data.supply_cost = 100
			data.stage_work = [60.0, 100.0, 60.0]
			data.health = 250.0
			data.garrison_capacity = 5
			data.requires_firebase_level = 2
			data.footprint_size = Vector2(6, 6)
			data.height = 1.0
			data.construction_slots = 2
			data.auto_attacks = true
			data.attack_range = 11000.0
			data.defense_weapon = "m102_howitzer"  # 105mm howitzer
			data.defense_type = 4  # ARTILLERY
			data.requires_garrison_to_fire = true  # Needs crew to operate
			# Full 360-degree rotation - can rotate post-placement
			data.fire_arc = 360.0
			data.weapon_range = 11000.0
			data.rotatable_post_placement = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.HOWITZER_PIT_105MM:
			data.display_name = "105mm Howitzer Pit"
			data.description = "Circular sandbagged emplacement - 360-degree rotation"
			data.category = BuildingCategory.FIREBASE_HEAVY
			data.supply_cost = 90
			data.stage_work = [55.0, 90.0, 55.0]
			data.health = 220.0
			data.garrison_capacity = 6
			data.requires_firebase_level = 2
			data.footprint_size = Vector2(6, 6)
			data.height = 1.0
			data.construction_slots = 2
			data.auto_attacks = true
			data.attack_range = 11000.0
			# Full 360-degree rotation - can rotate post-placement
			data.fire_arc = 360.0
			data.weapon_range = 11000.0
			data.rotatable_post_placement = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.HOWITZER_PIT_155MM:
			data.display_name = "155mm Howitzer Pit"
			data.description = "Large artillery position - 360-degree rotation, 14.6km range"
			data.category = BuildingCategory.FIREBASE_HEAVY
			data.supply_cost = 120
			data.stage_work = [70.0, 120.0, 70.0]
			data.health = 280.0
			data.garrison_capacity = 8
			data.requires_firebase_level = 2
			data.footprint_size = Vector2(8, 8)
			data.height = 1.2
			data.construction_slots = 2
			data.auto_attacks = true
			data.attack_range = 14600.0
			# Full 360-degree rotation - can rotate post-placement
			data.fire_arc = 360.0
			data.weapon_range = 14600.0
			data.rotatable_post_placement = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.FIRE_DIRECTION_CENTER:
			data.display_name = "Fire Direction Center"
			data.description = "Control bunker for coordinating artillery fire"
			data.category = BuildingCategory.FIREBASE_HEAVY
			data.supply_cost = 70
			data.stage_work = [50.0, 70.0, 50.0]
			data.health = 350.0
			data.armor = 10.0
			data.requires_firebase_level = 2
			data.footprint_size = Vector2(5, 4)
			data.height = 2.5
			data.sight_range = 50.0
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.TANK_REVETMENT:
			data.display_name = "Tank Revetment"
			data.description = "Protected vehicle fighting position"
			data.category = BuildingCategory.FIREBASE_HEAVY
			data.supply_cost = 60
			data.stage_work = [50.0, 70.0, 50.0]
			data.health = 300.0
			data.requires_firebase_level = 1
			data.footprint_size = Vector2(5, 5)
			data.height = 1.5
			data.cover_value = 0.7
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.OPEN_REVETMENT:
			data.display_name = "Open Revetment"
			data.description = "U-shaped earth/sandbag walls for aircraft"
			data.category = BuildingCategory.FIREBASE_HEAVY
			data.supply_cost = 55
			data.stage_work = [45.0, 65.0, 45.0]
			data.health = 250.0
			data.footprint_size = Vector2(20, 15)
			data.height = 3.0
			data.cover_value = 0.5
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		# =====================================================================
		# VIETNAMESE VILLAGE
		# =====================================================================
		BuildingType.THATCHED_HUT:
			data.display_name = "Thatched Hut"
			data.description = "Bamboo frame with palm/straw roof and mud-daubed walls"
			data.category = BuildingCategory.VIETNAMESE_VILLAGE
			data.supply_cost = 0
			data.stage_work = [10.0, 15.0, 10.0]
			data.health = 50.0
			data.garrison_capacity = 4
			data.footprint_size = Vector2(4, 3)
			data.height = 3.0
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.BURNED]

		BuildingType.CLAY_WALL_COTTAGE:
			data.display_name = "Clay Wall Cottage"
			data.description = "Clay and straw walls with steep thatched roof"
			data.category = BuildingCategory.VIETNAMESE_VILLAGE
			data.supply_cost = 0
			data.stage_work = [15.0, 20.0, 15.0]
			data.health = 80.0
			data.garrison_capacity = 6
			data.footprint_size = Vector2(5, 4)
			data.height = 3.5
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.RUINS]

		BuildingType.STILT_HOUSE:
			data.display_name = "Stilt House"
			data.description = "Raised on wooden stilts with bamboo walls and thatched roof"
			data.category = BuildingCategory.VIETNAMESE_VILLAGE
			data.supply_cost = 0
			data.stage_work = [20.0, 25.0, 15.0]
			data.health = 60.0
			data.garrison_capacity = 6
			data.footprint_size = Vector2(6, 4)
			data.height = 5.0
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.THREE_ROOM_HOUSE:
			data.display_name = "Three-Room House"
			data.description = "Traditional 3-compartment layout with central shrine"
			data.category = BuildingCategory.VIETNAMESE_VILLAGE
			data.supply_cost = 0
			data.stage_work = [25.0, 35.0, 20.0]
			data.health = 120.0
			data.garrison_capacity = 8
			data.footprint_size = Vector2(8, 5)
			data.height = 4.0
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.BURNED]

		BuildingType.COMMUNAL_HOUSE:
			data.display_name = "Communal House"
			data.description = "Village Dinh - large axe-shaped roof, community center"
			data.category = BuildingCategory.VIETNAMESE_VILLAGE
			data.supply_cost = 0
			data.stage_work = [40.0, 60.0, 40.0]
			data.health = 200.0
			data.garrison_capacity = 20
			data.footprint_size = Vector2(12, 8)
			data.height = 8.0
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.BURNED]

		BuildingType.VILLAGE_WELL:
			data.display_name = "Village Well"
			data.description = "Stone/brick circular well with wooden frame"
			data.category = BuildingCategory.VIETNAMESE_VILLAGE
			data.supply_cost = 0
			data.stage_work = [10.0, 15.0, 10.0]
			data.health = 100.0
			data.footprint_size = Vector2(2, 2)
			data.height = 1.5
			data.requires_cleared_terrain = false
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DESTROYED]

		BuildingType.RICE_STORAGE_SHED:
			data.display_name = "Rice Storage Shed"
			data.description = "Elevated bamboo granary"
			data.category = BuildingCategory.VIETNAMESE_VILLAGE
			data.supply_cost = 0
			data.stage_work = [10.0, 15.0, 10.0]
			data.health = 40.0
			data.footprint_size = Vector2(3, 2)
			data.height = 3.0
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.BURNED]

		BuildingType.WATER_BUFFALO_SHED:
			data.display_name = "Water Buffalo Shed"
			data.description = "Simple bamboo shelter for livestock"
			data.category = BuildingCategory.VIETNAMESE_VILLAGE
			data.supply_cost = 0
			data.stage_work = [8.0, 12.0, 8.0]
			data.health = 30.0
			data.footprint_size = Vector2(4, 3)
			data.height = 2.5
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.BAMBOO_FENCE:
			data.display_name = "Bamboo Fence"
			data.description = "Woven bamboo perimeter section"
			data.category = BuildingCategory.VIETNAMESE_VILLAGE
			data.supply_cost = 0
			data.stage_work = [5.0, 5.0, 5.0]
			data.health = 20.0
			data.footprint_size = Vector2(3, 0.2)
			data.height = 1.5
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.VILLAGE_GATE:
			data.display_name = "Village Gate"
			data.description = "Wooden arch gateway"
			data.category = BuildingCategory.VIETNAMESE_VILLAGE
			data.supply_cost = 0
			data.stage_work = [10.0, 15.0, 10.0]
			data.health = 60.0
			data.footprint_size = Vector2(3, 1)
			data.height = 3.5
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.VILLAGE_PAGODA:
			data.display_name = "Village Pagoda"
			data.description = "Small rural Buddhist temple"
			data.category = BuildingCategory.VIETNAMESE_VILLAGE
			data.supply_cost = 0
			data.stage_work = [30.0, 45.0, 30.0]
			data.health = 180.0
			data.garrison_capacity = 10
			data.footprint_size = Vector2(10, 8)
			data.height = 8.0
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.RUINS]

		BuildingType.TAM_QUAN_GATE:
			data.display_name = "Tam Quan Gate"
			data.description = "Three-door temple entrance gate"
			data.category = BuildingCategory.VIETNAMESE_VILLAGE
			data.supply_cost = 0
			data.stage_work = [15.0, 20.0, 15.0]
			data.health = 120.0
			data.footprint_size = Vector2(6, 2)
			data.height = 5.0
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.BELL_TOWER:
			data.display_name = "Bell Tower"
			data.description = "Temple bell structure"
			data.category = BuildingCategory.VIETNAMESE_VILLAGE
			data.supply_cost = 0
			data.stage_work = [15.0, 20.0, 15.0]
			data.health = 100.0
			data.footprint_size = Vector2(3, 3)
			data.height = 6.0
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.MONK_QUARTERS:
			data.display_name = "Monk Quarters"
			data.description = "Simple living building for monks"
			data.category = BuildingCategory.VIETNAMESE_VILLAGE
			data.supply_cost = 0
			data.stage_work = [15.0, 20.0, 15.0]
			data.health = 80.0
			data.garrison_capacity = 6
			data.footprint_size = Vector2(8, 5)
			data.height = 4.0
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.STONE_BUDDHA:
			data.display_name = "Stone Buddha"
			data.description = "Seated Buddha statue"
			data.category = BuildingCategory.VIETNAMESE_VILLAGE
			data.supply_cost = 0
			data.stage_work = [20.0, 30.0, 20.0]
			data.health = 200.0
			data.footprint_size = Vector2(2, 2)
			data.height = 3.0
			data.requires_cleared_terrain = false
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		# =====================================================================
		# AIRFIELD STRUCTURES
		# =====================================================================
		BuildingType.RUNWAY_CONCRETE:
			data.display_name = "Concrete Runway"
			data.description = "Standard concrete runway segment"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 200
			data.stage_work = [100.0, 150.0, 100.0]
			data.health = 500.0
			data.armor = 20.0
			data.footprint_size = Vector2(50, 45)
			data.height = 0.3
			data.requires_cleared_terrain = true
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.CRATERED, DestructionState.DESTROYED]

		BuildingType.RUNWAY_PSP:
			data.display_name = "PSP Runway"
			data.description = "Pierced steel planking runway"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 150
			data.stage_work = [80.0, 120.0, 80.0]
			data.health = 350.0
			data.armor = 10.0
			data.footprint_size = Vector2(50, 45)
			data.height = 0.1
			data.requires_cleared_terrain = true
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.RUNWAY_AM2:
			data.display_name = "AM-2 Runway"
			data.description = "AM-2 aluminum matting runway section"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 120
			data.stage_work = [60.0, 100.0, 60.0]
			data.health = 280.0
			data.armor = 5.0
			data.footprint_size = Vector2(50, 45)
			data.height = 0.05
			data.requires_cleared_terrain = true
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.TAXIWAY_SECTION:
			data.display_name = "Taxiway"
			data.description = "Connecting taxiway to apron"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 80
			data.stage_work = [40.0, 60.0, 40.0]
			data.health = 250.0
			data.footprint_size = Vector2(20, 15)
			data.height = 0.2
			data.requires_cleared_terrain = true
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.CRATERED]

		BuildingType.RUNWAY_CRATER:
			data.display_name = "Runway Crater"
			data.description = "Bomb damage crater"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 1.0
			data.footprint_size = Vector2(8, 8)
			data.height = 3.0
			data.requires_cleared_terrain = false
			data.provides_cover = true
			data.cover_value = 0.3
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.WONDERARCH_SHELTER:
			data.display_name = "Wonderarch Shelter"
			data.description = "Concrete aircraft protection shelter"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 300
			data.stage_work = [150.0, 200.0, 150.0]
			data.health = 1000.0
			data.armor = 50.0
			data.footprint_size = Vector2(25, 20)
			data.height = 8.0
			data.construction_slots = 4
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.COLLAPSED]

		BuildingType.PSP_REVETMENT:
			data.display_name = "PSP Revetment"
			data.description = "Steel planking aircraft bay"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 80
			data.stage_work = [50.0, 70.0, 50.0]
			data.health = 200.0
			data.footprint_size = Vector2(18, 15)
			data.height = 3.0
			data.cover_value = 0.5
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.AIRCRAFT_HANGAR:
			data.display_name = "Aircraft Hangar"
			data.description = "Large maintenance building"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 250
			data.stage_work = [120.0, 180.0, 120.0]
			data.health = 600.0
			data.armor = 10.0
			data.footprint_size = Vector2(40, 30)
			data.height = 12.0
			data.construction_slots = 4
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.MAINTENANCE_SHOP:
			data.display_name = "Maintenance Shop"
			data.description = "Engine and airframe repair facility"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 120
			data.stage_work = [60.0, 100.0, 60.0]
			data.health = 350.0
			data.footprint_size = Vector2(20, 15)
			data.height = 6.0
			data.construction_slots = 2
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.CONTROL_TOWER:
			data.display_name = "Control Tower"
			data.description = "Air traffic control tower"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 150
			data.stage_work = [80.0, 120.0, 80.0]
			data.health = 300.0
			data.armor = 5.0
			data.sight_range = 150.0
			data.footprint_size = Vector2(6, 6)
			data.height = 15.0
			data.construction_slots = 2
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.RADAR_DOME:
			data.display_name = "Radar Dome"
			data.description = "Ground control approach radar"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 180
			data.stage_work = [90.0, 140.0, 90.0]
			data.health = 250.0
			data.sight_range = 200.0
			data.footprint_size = Vector2(8, 8)
			data.height = 8.0
			data.construction_slots = 2
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.OPERATIONS_BUILDING:
			data.display_name = "Operations Building"
			data.description = "Flight planning and briefing facility"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 100
			data.stage_work = [50.0, 80.0, 50.0]
			data.health = 280.0
			data.footprint_size = Vector2(15, 10)
			data.height = 4.0
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.POL_STORAGE:
			data.display_name = "POL Storage"
			data.description = "Fuel tanks and pumps"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 140
			data.stage_work = [70.0, 110.0, 70.0]
			data.health = 200.0
			data.footprint_size = Vector2(10, 10)
			data.height = 8.0
			data.is_flammable = true
			data.is_explosive = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.BURNED, DestructionState.DESTROYED]

		BuildingType.FIRE_STATION:
			data.display_name = "Fire Station"
			data.description = "Crash/rescue equipment station"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 90
			data.stage_work = [45.0, 70.0, 45.0]
			data.health = 250.0
			data.footprint_size = Vector2(15, 8)
			data.height = 5.0
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.AMMO_STORAGE_AIRFIELD:
			data.display_name = "Airfield Ammo Storage"
			data.description = "Bombs and rockets bunker"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 160
			data.stage_work = [80.0, 130.0, 80.0]
			data.health = 400.0
			data.armor = 20.0
			data.footprint_size = Vector2(10, 8)
			data.height = 4.0
			data.is_explosive = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.EXPLODED]

		BuildingType.QUONSET_HUT:
			data.display_name = "Quonset Hut"
			data.description = "Corrugated steel arch building"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 60
			data.stage_work = [35.0, 50.0, 35.0]
			data.health = 200.0
			data.footprint_size = Vector2(12, 6)
			data.height = 4.0
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.SUPPLY_WAREHOUSE:
			data.display_name = "Supply Warehouse"
			data.description = "Large storage building"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 130
			data.stage_work = [70.0, 100.0, 70.0]
			data.health = 350.0
			data.footprint_size = Vector2(30, 20)
			data.height = 8.0
			data.construction_slots = 3
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.BURNED]

		BuildingType.AMMO_DUMP_BUNKER:
			data.display_name = "Ammo Dump Bunker"
			data.description = "Earth-covered igloo ammunition storage"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 180
			data.stage_work = [100.0, 150.0, 100.0]
			data.health = 500.0
			data.armor = 30.0
			data.footprint_size = Vector2(15, 10)
			data.height = 6.0
			data.construction_slots = 2
			data.is_explosive = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.EXPLODED]

		BuildingType.POL_TANK_FARM:
			data.display_name = "POL Tank Farm"
			data.description = "Multiple fuel storage tanks"
			data.category = BuildingCategory.AIRFIELD
			data.supply_cost = 200
			data.stage_work = [100.0, 160.0, 100.0]
			data.health = 300.0
			data.footprint_size = Vector2(20, 20)
			data.height = 10.0
			data.construction_slots = 3
			data.is_flammable = true
			data.is_explosive = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.BURNED]

		# =====================================================================
		# FRENCH COLONIAL
		# =====================================================================
		BuildingType.COLONIAL_VILLA:
			data.display_name = "Colonial Villa"
			data.description = "Two-story French villa with balconies and shutters"
			data.category = BuildingCategory.FRENCH_COLONIAL
			data.supply_cost = 0
			data.stage_work = [60.0, 100.0, 60.0]
			data.health = 350.0
			data.garrison_capacity = 15
			data.footprint_size = Vector2(15, 12)
			data.height = 8.0
			data.requires_cleared_terrain = false
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.RUINS]

		BuildingType.PLANTATION_HOUSE:
			data.display_name = "Plantation House"
			data.description = "Large estate house with veranda"
			data.category = BuildingCategory.FRENCH_COLONIAL
			data.supply_cost = 0
			data.stage_work = [80.0, 130.0, 80.0]
			data.health = 450.0
			data.garrison_capacity = 20
			data.footprint_size = Vector2(20, 15)
			data.height = 10.0
			data.requires_cleared_terrain = false
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.GOVERNMENT_BUILDING:
			data.display_name = "Government Building"
			data.description = "Neoclassical building with columns"
			data.category = BuildingCategory.FRENCH_COLONIAL
			data.supply_cost = 0
			data.stage_work = [100.0, 160.0, 100.0]
			data.health = 600.0
			data.armor = 10.0
			data.garrison_capacity = 30
			data.footprint_size = Vector2(25, 15)
			data.height = 12.0
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.FRENCH_BARRACKS:
			data.display_name = "French Barracks"
			data.description = "Long two-story colonial barracks"
			data.category = BuildingCategory.FRENCH_COLONIAL
			data.supply_cost = 0
			data.stage_work = [80.0, 120.0, 80.0]
			data.health = 400.0
			data.garrison_capacity = 40
			data.footprint_size = Vector2(30, 10)
			data.height = 8.0
			data.requires_cleared_terrain = false
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.RUINS]

		BuildingType.COLONIAL_PRISON:
			data.display_name = "Colonial Prison"
			data.description = "Hoa Lo style prison with high walls and guard towers"
			data.category = BuildingCategory.FRENCH_COLONIAL
			data.supply_cost = 0
			data.stage_work = [120.0, 180.0, 120.0]
			data.health = 800.0
			data.armor = 20.0
			data.garrison_capacity = 50
			data.footprint_size = Vector2(40, 30)
			data.height = 10.0
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.RUBBER_PLANT:
			data.display_name = "Rubber Processing Plant"
			data.description = "Factory building with smokestacks"
			data.category = BuildingCategory.FRENCH_COLONIAL
			data.supply_cost = 0
			data.stage_work = [100.0, 150.0, 100.0]
			data.health = 500.0
			data.garrison_capacity = 20
			data.footprint_size = Vector2(30, 20)
			data.height = 10.0
			data.requires_cleared_terrain = false
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.BURNED]

		BuildingType.COLONIAL_WAREHOUSE:
			data.display_name = "Colonial Warehouse"
			data.description = "Colonial era storage building"
			data.category = BuildingCategory.FRENCH_COLONIAL
			data.supply_cost = 0
			data.stage_work = [60.0, 90.0, 60.0]
			data.health = 350.0
			data.garrison_capacity = 15
			data.footprint_size = Vector2(25, 15)
			data.height = 8.0
			data.requires_cleared_terrain = false
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.RAILWAY_STATION:
			data.display_name = "Railway Station"
			data.description = "French-style rail depot"
			data.category = BuildingCategory.FRENCH_COLONIAL
			data.supply_cost = 0
			data.stage_work = [70.0, 110.0, 70.0]
			data.health = 400.0
			data.garrison_capacity = 20
			data.footprint_size = Vector2(20, 10)
			data.height = 8.0
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.CUSTOMS_BUILDING:
			data.display_name = "Customs Building"
			data.description = "Port administration office"
			data.category = BuildingCategory.FRENCH_COLONIAL
			data.supply_cost = 0
			data.stage_work = [50.0, 80.0, 50.0]
			data.health = 280.0
			data.garrison_capacity = 10
			data.footprint_size = Vector2(15, 10)
			data.height = 5.0
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		# =====================================================================
		# INFRASTRUCTURE
		# =====================================================================
		BuildingType.STEEL_TRUSS_BRIDGE:
			data.display_name = "Steel Truss Bridge"
			data.description = "Railroad/road bridge with steel framework"
			data.category = BuildingCategory.INFRASTRUCTURE
			data.supply_cost = 0
			data.stage_work = [150.0, 250.0, 150.0]
			data.health = 800.0
			data.armor = 30.0
			data.footprint_size = Vector2(50, 8)
			data.height = 10.0
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.COLLAPSED]

		BuildingType.WOODEN_BRIDGE:
			data.display_name = "Wooden Bridge"
			data.description = "Simple timber crossing"
			data.category = BuildingCategory.INFRASTRUCTURE
			data.supply_cost = 30
			data.stage_work = [30.0, 50.0, 30.0]
			data.health = 150.0
			data.footprint_size = Vector2(15, 4)
			data.height = 3.0
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.PONTOON_BRIDGE:
			data.display_name = "Pontoon Bridge"
			data.description = "Floating military bridge"
			data.category = BuildingCategory.INFRASTRUCTURE
			data.supply_cost = 80
			data.stage_work = [50.0, 80.0, 50.0]
			data.health = 200.0
			data.footprint_size = Vector2(30, 5)
			data.height = 1.0
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.STONE_ARCH_BRIDGE:
			data.display_name = "Stone Arch Bridge"
			data.description = "French colonial era stone bridge"
			data.category = BuildingCategory.INFRASTRUCTURE
			data.supply_cost = 0
			data.stage_work = [100.0, 150.0, 100.0]
			data.health = 600.0
			data.armor = 40.0
			data.footprint_size = Vector2(20, 6)
			data.height = 8.0
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.DOCK_PIER:
			data.display_name = "Dock/Pier"
			data.description = "Wooden jetty for boats and ships"
			data.category = BuildingCategory.INFRASTRUCTURE
			data.supply_cost = 40
			data.stage_work = [40.0, 60.0, 40.0]
			data.health = 200.0
			data.footprint_size = Vector2(50, 10)
			data.height = 2.0
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.CARGO_CRANE:
			data.display_name = "Cargo Crane"
			data.description = "Port cargo handling crane"
			data.category = BuildingCategory.INFRASTRUCTURE
			data.supply_cost = 0
			data.stage_work = [80.0, 120.0, 80.0]
			data.health = 300.0
			data.footprint_size = Vector2(15, 5)
			data.height = 20.0
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.CONTAINER_YARD:
			data.display_name = "Container Yard"
			data.description = "Stacked CONEX shipping containers"
			data.category = BuildingCategory.INFRASTRUCTURE
			data.supply_cost = 0
			data.stage_work = [60.0, 100.0, 60.0]
			data.health = 400.0
			data.armor = 10.0
			data.footprint_size = Vector2(30, 30)
			data.height = 5.0
			data.cover_value = 0.8
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.DIRT_ROAD_SECTION:
			data.display_name = "Dirt Road"
			data.description = "Unpaved village road section"
			data.category = BuildingCategory.INFRASTRUCTURE
			data.supply_cost = 0
			data.stage_work = [5.0, 5.0, 5.0]
			data.health = 50.0
			data.footprint_size = Vector2(20, 4)
			data.height = 0.1
			data.requires_cleared_terrain = false
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.LATERITE_ROAD:
			data.display_name = "Laterite Road"
			data.description = "Red clay surface road"
			data.category = BuildingCategory.INFRASTRUCTURE
			data.supply_cost = 0
			data.stage_work = [10.0, 10.0, 10.0]
			data.health = 80.0
			data.footprint_size = Vector2(20, 5)
			data.height = 0.15
			data.requires_cleared_terrain = false
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.PAVED_ROAD_SECTION:
			data.display_name = "Paved Road"
			data.description = "Asphalt highway section"
			data.category = BuildingCategory.INFRASTRUCTURE
			data.supply_cost = 0
			data.stage_work = [30.0, 40.0, 30.0]
			data.health = 150.0
			data.footprint_size = Vector2(20, 8)
			data.height = 0.2
			data.requires_cleared_terrain = false
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.CRATERED]

		BuildingType.TRAIL_PATH:
			data.display_name = "Trail Path"
			data.description = "Jungle footpath"
			data.category = BuildingCategory.INFRASTRUCTURE
			data.supply_cost = 0
			data.stage_work = [3.0, 3.0, 3.0]
			data.health = 20.0
			data.footprint_size = Vector2(20, 1)
			data.height = 0.05
			data.requires_cleared_terrain = false
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT]

		# =====================================================================
		# VC/NVA SPECIAL
		# =====================================================================
		BuildingType.TUNNEL_ENTRANCE_HIDDEN:
			data.display_name = "Hidden Tunnel Entrance"
			data.description = "Camouflaged trap door entrance to tunnel network"
			data.category = BuildingCategory.VC_NVA_SPECIAL
			data.supply_cost = 0
			data.stage_work = [20.0, 30.0, 20.0]
			data.health = 30.0
			data.garrison_capacity = 2
			data.footprint_size = Vector2(0.6, 0.8)
			data.height = 0.1
			data.requires_cleared_terrain = false
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.TUNNEL_ENTRANCE_EXPOSED:
			data.display_name = "Exposed Tunnel Entrance"
			data.description = "Discovered/blown open tunnel entrance"
			data.category = BuildingCategory.VC_NVA_SPECIAL
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 50.0
			data.garrison_capacity = 2
			data.footprint_size = Vector2(1, 1)
			data.height = 0.5
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.SPIDER_HOLE:
			data.display_name = "Spider Hole"
			data.description = "One-man concealed fighting position"
			data.category = BuildingCategory.VC_NVA_SPECIAL
			data.supply_cost = 0
			data.stage_work = [10.0, 15.0, 10.0]
			data.health = 40.0
			data.garrison_capacity = 1
			data.footprint_size = Vector2(0.8, 0.8)
			data.height = 0.3
			data.requires_cleared_terrain = false
			data.cover_value = 0.9
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.PUNJI_PIT:
			data.display_name = "Punji Pit"
			data.description = "Concealed spike trap"
			data.category = BuildingCategory.VC_NVA_SPECIAL
			data.supply_cost = 0
			data.stage_work = [10.0, 15.0, 10.0]
			data.health = 20.0
			data.footprint_size = Vector2(1, 1)
			data.height = 1.0
			data.requires_cleared_terrain = false
			data.provides_cover = false
			data.damages_enemies = true
			data.damage_to_enemies = 50.0
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.UNDERGROUND_HOSPITAL:
			data.display_name = "Underground Hospital"
			data.description = "Bunker complex entrance for medical facility"
			data.category = BuildingCategory.VC_NVA_SPECIAL
			data.supply_cost = 0
			data.stage_work = [50.0, 80.0, 50.0]
			data.health = 200.0
			data.garrison_capacity = 10
			data.footprint_size = Vector2(3, 2)
			data.height = 2.0
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.WEAPONS_CACHE:
			data.display_name = "Weapons Cache"
			data.description = "Hidden weapons and ammunition storage"
			data.category = BuildingCategory.VC_NVA_SPECIAL
			data.supply_cost = 0
			data.stage_work = [20.0, 30.0, 20.0]
			data.health = 50.0
			data.footprint_size = Vector2(2, 2)
			data.height = 1.5
			data.requires_cleared_terrain = false
			data.is_explosive = true
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.STOCKADE_COMPOUND:
			data.display_name = "Stockade Compound"
			data.description = "Barbed wire prison area"
			data.category = BuildingCategory.VC_NVA_SPECIAL
			data.supply_cost = 0
			data.stage_work = [60.0, 100.0, 60.0]
			data.health = 300.0
			data.garrison_capacity = 30
			data.footprint_size = Vector2(50, 50)
			data.height = 3.0
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.PRISONER_TENT:
			data.display_name = "Prisoner Tent"
			data.description = "POW canvas tent with wood floor"
			data.category = BuildingCategory.VC_NVA_SPECIAL
			data.supply_cost = 0
			data.stage_work = [15.0, 25.0, 15.0]
			data.health = 60.0
			data.garrison_capacity = 10
			data.footprint_size = Vector2(6, 4)
			data.height = 3.0
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT]

		# =====================================================================
		# RUINS & DESTRUCTION
		# =====================================================================
		BuildingType.CRATER_FIELD:
			data.display_name = "Crater Field"
			data.description = "Multiple overlapping bomb craters"
			data.category = BuildingCategory.RUINS
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 1.0
			data.footprint_size = Vector2(30, 30)
			data.height = 4.0
			data.requires_cleared_terrain = false
			data.provides_cover = true
			data.cover_value = 0.4
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.COLLAPSED_BUILDING:
			data.display_name = "Collapsed Building"
			data.description = "Walls fallen, roof destroyed"
			data.category = BuildingCategory.RUINS
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 100.0
			data.garrison_capacity = 4
			data.footprint_size = Vector2(8, 8)
			data.height = 2.0
			data.requires_cleared_terrain = false
			data.cover_value = 0.5
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.BURNED_STRUCTURE:
			data.display_name = "Burned Structure"
			data.description = "Charred frame with no roof"
			data.category = BuildingCategory.RUINS
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 50.0
			data.garrison_capacity = 2
			data.footprint_size = Vector2(6, 5)
			data.height = 3.0
			data.requires_cleared_terrain = false
			data.cover_value = 0.3
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.PARTIAL_RUINS:
			data.display_name = "Partial Ruins"
			data.description = "1-2 walls still standing"
			data.category = BuildingCategory.RUINS
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 150.0
			data.garrison_capacity = 6
			data.footprint_size = Vector2(10, 8)
			data.height = 4.0
			data.requires_cleared_terrain = false
			data.cover_value = 0.6
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.FOUNDATION_ONLY:
			data.display_name = "Foundation Only"
			data.description = "Just floor/foundation remains"
			data.category = BuildingCategory.RUINS
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 200.0
			data.footprint_size = Vector2(10, 8)
			data.height = 0.3
			data.requires_cleared_terrain = false
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.DESTROYED_VILLAGE:
			data.display_name = "Destroyed Village"
			data.description = "3-5 burned huts with crater"
			data.category = BuildingCategory.RUINS
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 100.0
			data.garrison_capacity = 8
			data.footprint_size = Vector2(30, 30)
			data.height = 2.0
			data.requires_cleared_terrain = false
			data.cover_value = 0.4
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.BOMBED_PAGODA:
			data.display_name = "Bombed Pagoda"
			data.description = "Collapsed roof, broken walls"
			data.category = BuildingCategory.RUINS
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 250.0
			data.garrison_capacity = 10
			data.footprint_size = Vector2(15, 10)
			data.height = 6.0
			data.requires_cleared_terrain = false
			data.cover_value = 0.5
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.CRATERED_RUNWAY:
			data.display_name = "Cratered Runway"
			data.description = "Runway section with 3+ bomb craters"
			data.category = BuildingCategory.RUINS
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 100.0
			data.footprint_size = Vector2(100, 50)
			data.height = 3.0
			data.requires_cleared_terrain = false
			data.provides_cover = true
			data.cover_value = 0.3
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.BURNED_BUNKER:
			data.display_name = "Burned Bunker"
			data.description = "Blackened sandbags, collapsed roof"
			data.category = BuildingCategory.RUINS
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 80.0
			data.garrison_capacity = 2
			data.footprint_size = Vector2(3, 3)
			data.height = 1.0
			data.requires_cleared_terrain = false
			data.cover_value = 0.4
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.DESTROYED_BRIDGE:
			data.display_name = "Destroyed Bridge"
			data.description = "Collapsed span, twisted metal"
			data.category = BuildingCategory.RUINS
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 500.0
			data.footprint_size = Vector2(20, 8)
			data.height = 5.0
			data.requires_cleared_terrain = false
			data.provides_cover = true
			data.cover_value = 0.5
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.RUBBLE_PILE:
			data.display_name = "Rubble Pile"
			data.description = "Generic debris pile"
			data.category = BuildingCategory.RUINS
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 50.0
			data.garrison_capacity = 2
			data.footprint_size = Vector2(5, 5)
			data.height = 2.0
			data.requires_cleared_terrain = false
			data.cover_value = 0.4
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.CONEX_CELL:
			data.display_name = "CONEX Cell"
			data.description = "Solitary confinement shipping container"
			data.category = BuildingCategory.RUINS
			data.supply_cost = 0
			data.stage_work = [10.0, 15.0, 10.0]
			data.health = 300.0
			data.armor = 20.0
			data.garrison_capacity = 1
			data.footprint_size = Vector2(2, 2.5)
			data.height = 2.5
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT]

		# =====================================================================
		# CHAM RUINS
		# =====================================================================
		BuildingType.CHAM_TEMPLE_TOWER:
			data.display_name = "Cham Temple Tower"
			data.description = "Ancient brick tower ruin (My Son style)"
			data.category = BuildingCategory.CHAM_RUINS
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 400.0
			data.armor = 30.0
			data.garrison_capacity = 6
			data.footprint_size = Vector2(6, 6)
			data.height = 10.0
			data.requires_cleared_terrain = false
			data.cover_value = 0.7
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.CHAM_TEMPLE_BASE:
			data.display_name = "Cham Temple Base"
			data.description = "Ancient foundation platform"
			data.category = BuildingCategory.CHAM_RUINS
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 500.0
			data.armor = 40.0
			data.footprint_size = Vector2(10, 10)
			data.height = 1.0
			data.requires_cleared_terrain = false
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT]

		BuildingType.CHAM_BROKEN_COLUMN:
			data.display_name = "Cham Broken Column"
			data.description = "Fallen ancient masonry"
			data.category = BuildingCategory.CHAM_RUINS
			data.supply_cost = 0
			data.stage_work = [0.0, 0.0, 0.0]
			data.health = 200.0
			data.footprint_size = Vector2(3, 0.5)
			data.height = 0.5
			data.requires_cleared_terrain = false
			data.cover_value = 0.3
			data.destruction_states = [DestructionState.INTACT]

		# =====================================================================
		# COMMERCIAL / MARKETPLACE
		# =====================================================================
		BuildingType.MARKET_HALL:
			data.display_name = "Market Hall"
			data.description = "Covered market structure"
			data.category = BuildingCategory.COMMERCIAL
			data.supply_cost = 0
			data.stage_work = [40.0, 60.0, 40.0]
			data.health = 250.0
			data.garrison_capacity = 20
			data.footprint_size = Vector2(20, 15)
			data.height = 6.0
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.BURNED]

		BuildingType.SHOP_HOUSE:
			data.display_name = "Shop House"
			data.description = "Two-story merchant building"
			data.category = BuildingCategory.COMMERCIAL
			data.supply_cost = 0
			data.stage_work = [30.0, 50.0, 30.0]
			data.health = 180.0
			data.garrison_capacity = 8
			data.footprint_size = Vector2(6, 12)
			data.height = 7.0
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED]

		BuildingType.MARKET_STALL:
			data.display_name = "Market Stall"
			data.description = "Simple vendor booth"
			data.category = BuildingCategory.COMMERCIAL
			data.supply_cost = 0
			data.stage_work = [5.0, 10.0, 5.0]
			data.health = 30.0
			data.footprint_size = Vector2(3, 2)
			data.height = 2.5
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DESTROYED]

		BuildingType.FOOD_VENDOR_CART:
			data.display_name = "Food Vendor Cart"
			data.description = "Mobile street food cart"
			data.category = BuildingCategory.COMMERCIAL
			data.supply_cost = 0
			data.stage_work = [3.0, 5.0, 3.0]
			data.health = 15.0
			data.footprint_size = Vector2(2, 1)
			data.height = 2.0
			data.is_flammable = true
			data.requires_cleared_terrain = false
			data.provides_cover = false
			data.destruction_states = [DestructionState.INTACT]

		# =====================================================================
		# FIREBASE LOGISTICS
		# =====================================================================
		BuildingType.SUPPLY_DEPOT:
			data.display_name = "Supply Depot"
			data.description = "Main supply storage hub - stores and distributes supplies to nearby units"
			data.category = BuildingCategory.FIREBASE_SUPPORT
			data.supply_cost = 100
			data.stage_work = [50.0, 80.0, 50.0]  # ~180 work units total
			data.health = 400.0
			data.armor = 5.0
			data.footprint_size = Vector2(20, 15)
			data.height = 4.0
			data.requires_firebase_level = 0  # Can build at patrol base level
			data.construction_slots = 2
			data.is_flammable = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.BURNED, DestructionState.DESTROYED]

		# =====================================================================
		# ADDITIONAL FIREBASE DEFENSES
		# =====================================================================
		BuildingType.TANK_TRAP:
			data.display_name = "Tank Trap"
			data.description = "Anti-vehicle obstacle - blocks armor and slows vehicles"
			data.category = BuildingCategory.FIREBASE_PERIMETER
			data.supply_cost = 8
			data.stage_work = [10.0, 15.0, 10.0]
			data.health = 150.0
			data.armor = 20.0  # Steel construction
			data.footprint_size = Vector2(2, 2)
			data.height = 1.5
			data.blocks_vehicles = true
			data.is_linear_placement = true
			data.requires_cleared_terrain = false
			data.can_place_anywhere = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DESTROYED]

		BuildingType.FOXHOLE:
			data.display_name = "Foxhole"
			data.description = "Individual fighting position with sandbag cover"
			data.category = BuildingCategory.FIREBASE_PERIMETER
			data.supply_cost = 15
			data.stage_work = [15.0, 20.0, 10.0]
			data.health = 100.0
			data.garrison_capacity = 2
			data.provides_cover = true
			data.cover_value = 0.6
			data.footprint_size = Vector2(2, 2)
			data.height = 0.8
			data.is_linear_placement = true
			data.requires_cleared_terrain = false
			data.can_place_anywhere = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.TRENCH:
			data.display_name = "Trench"
			data.description = "Linear defensive earthwork - provides cover along its length. Requires firebase zone."
			data.category = BuildingCategory.FIREBASE_PERIMETER
			data.supply_cost = 12
			data.stage_work = [15.0, 25.0, 15.0]
			data.health = 200.0
			data.provides_cover = true
			data.cover_value = 0.7
			data.footprint_size = Vector2(4, 2)
			data.height = 1.0
			data.is_linear_placement = true
			data.requires_bulldozer = false
			data.can_place_anywhere = false  # Firebase Defense - requires TOC zone
			data.requires_cleared_terrain = true
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		# =====================================================================
		# SUPPLY CHAIN / LOGISTICS
		# =====================================================================
		BuildingType.TRUCK_STAGING_AREA:
			data.display_name = "Truck Staging Area"
			data.description = "Supply convoy spawn point - trucks depart from here on supply runs"
			data.category = BuildingCategory.FIREBASE_SUPPORT
			data.supply_cost = 60
			data.stage_work = [40.0, 50.0, 40.0]
			data.health = 150.0
			data.footprint_size = Vector2(10, 8)
			data.height = 2.0
			data.requires_cleared_terrain = true
			data.can_place_anywhere = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

		BuildingType.MODULAR_BRIDGE:
			data.display_name = "Modular Bridge"
			data.description = "Connects areas over water or ravines - enables road network expansion"
			data.category = BuildingCategory.INFRASTRUCTURE
			data.supply_cost = 100
			data.stage_work = [60.0, 100.0, 60.0]
			data.health = 500.0
			data.armor = 10.0
			data.footprint_size = Vector2(6, 14)
			data.height = 3.0
			data.requires_cleared_terrain = false
			data.can_place_anywhere = false
			data.destruction_states = [DestructionState.INTACT, DestructionState.DAMAGED, DestructionState.DESTROYED]

	return data


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

static func get_category_name(category: BuildingCategory) -> String:
	"""Get display name for a building category"""
	match category:
		BuildingCategory.FIREBASE_PERIMETER: return "Firebase Perimeter"
		BuildingCategory.FIREBASE_SUPPORT: return "Firebase Support"
		BuildingCategory.FIREBASE_LIVING: return "Firebase Living"
		BuildingCategory.FIREBASE_HEAVY: return "Firebase Heavy"
		BuildingCategory.VIETNAMESE_VILLAGE: return "Vietnamese Village"
		BuildingCategory.AIRFIELD: return "Airfield"
		BuildingCategory.FRENCH_COLONIAL: return "French Colonial"
		BuildingCategory.INFRASTRUCTURE: return "Infrastructure"
		BuildingCategory.VC_NVA_SPECIAL: return "VC/NVA Special"
		BuildingCategory.RUINS: return "Ruins"
		BuildingCategory.CHAM_RUINS: return "Cham Ruins"
		BuildingCategory.COMMERCIAL: return "Commercial"
		_: return "Unknown"


static func get_buildings_by_category(category: BuildingCategory) -> Array[BuildingType]:
	"""Get all building types in a category"""
	var buildings: Array[BuildingType] = []

	match category:
		BuildingCategory.FIREBASE_PERIMETER:
			buildings = [
				BuildingType.SANDBAG_LIGHT,
				BuildingType.SANDBAG_HEAVY,
				BuildingType.BUNKER,
				BuildingType.SANDBAG_BUNKER,
				BuildingType.CONEX_BUNKER,
				BuildingType.MACHINE_GUN_NEST,
				BuildingType.MORTAR_PIT,
				BuildingType.WIRE_OBSTACLE,
				BuildingType.TRIPLE_CONCERTINA,
				BuildingType.CLAYMORE_LINE,
				BuildingType.WATCHTOWER,
			]
		BuildingCategory.FIREBASE_SUPPORT:
			buildings = [
				BuildingType.HELIPAD,
				BuildingType.PSP_HELIPAD,
				BuildingType.VIP_HELIPAD,
				BuildingType.HELICOPTER_REVETMENT,
				BuildingType.AMMO_BUNKER,
				BuildingType.FUEL_DEPOT,
				BuildingType.FUEL_POINT,
				BuildingType.MEDICAL_STATION,
				BuildingType.TOC,
				BuildingType.COMMO_BUNKER,
				BuildingType.SUPPLY_DEPOT,
			]
		BuildingCategory.FIREBASE_LIVING:
			buildings = [
				BuildingType.HOOTCH,
				BuildingType.MESS_HALL,
				BuildingType.LATRINE,
				BuildingType.SHOWER_POINT,
				BuildingType.OBSERVATION_TOWER,
				BuildingType.GUARD_TOWER,
				BuildingType.POWDER_BUNKER,
			]
		BuildingCategory.FIREBASE_HEAVY:
			buildings = [
				BuildingType.ARTILLERY_PIT,
				BuildingType.HOWITZER_PIT_105MM,
				BuildingType.HOWITZER_PIT_155MM,
				BuildingType.FIRE_DIRECTION_CENTER,
				BuildingType.TANK_REVETMENT,
				BuildingType.OPEN_REVETMENT,
			]
		BuildingCategory.VIETNAMESE_VILLAGE:
			buildings = [
				BuildingType.THATCHED_HUT,
				BuildingType.CLAY_WALL_COTTAGE,
				BuildingType.STILT_HOUSE,
				BuildingType.THREE_ROOM_HOUSE,
				BuildingType.COMMUNAL_HOUSE,
				BuildingType.VILLAGE_WELL,
				BuildingType.RICE_STORAGE_SHED,
				BuildingType.WATER_BUFFALO_SHED,
				BuildingType.BAMBOO_FENCE,
				BuildingType.VILLAGE_GATE,
				BuildingType.VILLAGE_PAGODA,
				BuildingType.TAM_QUAN_GATE,
				BuildingType.BELL_TOWER,
				BuildingType.MONK_QUARTERS,
				BuildingType.STONE_BUDDHA,
			]
		BuildingCategory.AIRFIELD:
			buildings = [
				BuildingType.RUNWAY_CONCRETE,
				BuildingType.RUNWAY_PSP,
				BuildingType.RUNWAY_AM2,
				BuildingType.TAXIWAY_SECTION,
				BuildingType.RUNWAY_CRATER,
				BuildingType.WONDERARCH_SHELTER,
				BuildingType.PSP_REVETMENT,
				BuildingType.AIRCRAFT_HANGAR,
				BuildingType.MAINTENANCE_SHOP,
				BuildingType.CONTROL_TOWER,
				BuildingType.RADAR_DOME,
				BuildingType.OPERATIONS_BUILDING,
				BuildingType.POL_STORAGE,
				BuildingType.FIRE_STATION,
				BuildingType.AMMO_STORAGE_AIRFIELD,
				BuildingType.QUONSET_HUT,
				BuildingType.SUPPLY_WAREHOUSE,
				BuildingType.AMMO_DUMP_BUNKER,
				BuildingType.POL_TANK_FARM,
			]
		BuildingCategory.FRENCH_COLONIAL:
			buildings = [
				BuildingType.COLONIAL_VILLA,
				BuildingType.PLANTATION_HOUSE,
				BuildingType.GOVERNMENT_BUILDING,
				BuildingType.FRENCH_BARRACKS,
				BuildingType.COLONIAL_PRISON,
				BuildingType.RUBBER_PLANT,
				BuildingType.COLONIAL_WAREHOUSE,
				BuildingType.RAILWAY_STATION,
				BuildingType.CUSTOMS_BUILDING,
			]
		BuildingCategory.INFRASTRUCTURE:
			buildings = [
				BuildingType.STEEL_TRUSS_BRIDGE,
				BuildingType.WOODEN_BRIDGE,
				BuildingType.PONTOON_BRIDGE,
				BuildingType.STONE_ARCH_BRIDGE,
				BuildingType.DOCK_PIER,
				BuildingType.CARGO_CRANE,
				BuildingType.CONTAINER_YARD,
				BuildingType.DIRT_ROAD_SECTION,
				BuildingType.LATERITE_ROAD,
				BuildingType.PAVED_ROAD_SECTION,
				BuildingType.TRAIL_PATH,
			]
		BuildingCategory.VC_NVA_SPECIAL:
			buildings = [
				BuildingType.TUNNEL_ENTRANCE_HIDDEN,
				BuildingType.TUNNEL_ENTRANCE_EXPOSED,
				BuildingType.SPIDER_HOLE,
				BuildingType.PUNJI_PIT,
				BuildingType.UNDERGROUND_HOSPITAL,
				BuildingType.WEAPONS_CACHE,
				BuildingType.STOCKADE_COMPOUND,
				BuildingType.PRISONER_TENT,
			]
		BuildingCategory.RUINS:
			buildings = [
				BuildingType.CRATER_FIELD,
				BuildingType.COLLAPSED_BUILDING,
				BuildingType.BURNED_STRUCTURE,
				BuildingType.PARTIAL_RUINS,
				BuildingType.FOUNDATION_ONLY,
				BuildingType.DESTROYED_VILLAGE,
				BuildingType.BOMBED_PAGODA,
				BuildingType.CRATERED_RUNWAY,
				BuildingType.BURNED_BUNKER,
				BuildingType.DESTROYED_BRIDGE,
				BuildingType.RUBBLE_PILE,
				BuildingType.CONEX_CELL,
			]
		BuildingCategory.CHAM_RUINS:
			buildings = [
				BuildingType.CHAM_TEMPLE_TOWER,
				BuildingType.CHAM_TEMPLE_BASE,
				BuildingType.CHAM_BROKEN_COLUMN,
			]
		BuildingCategory.COMMERCIAL:
			buildings = [
				BuildingType.MARKET_HALL,
				BuildingType.SHOP_HOUSE,
				BuildingType.MARKET_STALL,
				BuildingType.FOOD_VENDOR_CART,
			]

	return buildings


static func is_constructible_by_player(type: BuildingType) -> bool:
	"""Check if a building type can be constructed by the player"""
	var data := get_building_data(type)
	# Player-constructible buildings have a supply cost
	return data.supply_cost > 0


static func get_destruction_model_suffix(state: DestructionState) -> String:
	"""Get model filename suffix for destruction state"""
	match state:
		DestructionState.DAMAGED: return "_damaged"
		DestructionState.BURNED: return "_burned"
		DestructionState.RUINS: return "_ruins"
		DestructionState.DESTROYED: return "_destroyed"
		DestructionState.EXPLODED: return "_exploded"
		DestructionState.COLLAPSED: return "_collapsed"
		DestructionState.CRATERED: return "_cratered"
		_: return ""
