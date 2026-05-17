extends Node
## Game Enumerations - All enums for Vietnam Firebase Defense
## Accessed globally via GameEnums autoload (no class_name needed)

# =============================================================================
# FACTIONS
# =============================================================================
enum Faction {
	US_ARMY,
	ARVN,           # South Vietnamese allies
	VC,             # Viet Cong guerrillas
	NVA,            # North Vietnamese Army regulars
}

# =============================================================================
# UNIT TYPES
# =============================================================================
enum UnitType {
	# US Forces
	RIFLE_PLATOON,      # Standard infantry (M16, M60, M79)
	WEAPONS_SQUAD,      # Heavy weapons (mortars, recoilless rifles)
	ENGINEERS,          # Construction, demolition, flamethrowers
	BULLDOZER,          # D7 Caterpillar, terrain clearing/flattening
	ARMOR,              # M48 Patton, M113 APC
	HUEY_TRANSPORT,     # UH-1 Slick
	HUEY_GUNSHIP,       # UH-1 with door guns
	COBRA,              # AH-1 attack helicopter
	CHINOOK,            # CH-47 heavy lift
	SOG_TEAM,           # Special ops, 6-man recon teams

	# VC Forces (Guerrilla)
	VC_INFANTRY,        # AK-47, light weapons
	VC_SAPPERS,         # Breach wire, plant explosives
	VC_MORTAR,          # 82mm mortars, hit and run
	VC_LOCAL_FORCE,     # Militia, weaker but numerous

	# NVA Forces (Regular Army)
	NVA_INFANTRY,       # Well-equipped, disciplined
	NVA_HEAVY_WEAPONS,  # DShK, mortars, rockets
	NVA_ARMOR,          # PT-76 light tanks, T-54
	NVA_AAA,            # Anti-aircraft guns
	NVA_SAPPERS,        # Elite engineers
}

# =============================================================================
# WEAPON CLASSES
# =============================================================================
enum WeaponClass {
	# US Infantry Weapons
	M16,              # Standard rifle
	M60,              # Medium MG
	M79,              # Grenade launcher
	M14,              # Marksman rifle
	M1911,            # Sidearm
	M72_LAW,          # Light anti-tank
	M2_BROWNING,      # Heavy MG (.50 cal)
	M102_HOWITZER,    # 105mm artillery

	# Air Support
	NAPALM,           # Area denial, jungle clearing
	HE_BOMBS,         # High explosive
	CLUSTER_BOMBS,    # Anti-personnel
	ROCKET_POD,       # Helicopter rockets
	MINIGUN,          # Helicopter/Spooky

	# VC/NVA Weapons
	AK47,
	SKS,
	RPD,              # Light MG
	RPG7,             # Anti-armor
	DSHK,             # Heavy MG (12.7mm)
	MORTAR_82MM,
	MORTAR_120MM,     # NVA heavy mortar
	B40_ROCKET,       # Recoilless
}

# =============================================================================
# AIR STRIKE TYPES
# =============================================================================
enum AirStrikeType {
	NAPALM_RUN,       # F-4 Phantom napalm strike
	ROLLING_THUNDER,  # B-52 carpet bombing
	CLOSE_AIR_SUPPORT,# A-1 Skyraider
	SPOOKY,           # AC-47 gunship loiter
	ARC_LIGHT,        # B-52 strategic strike
}

# =============================================================================
# TERRAIN TYPES
# =============================================================================
enum TerrainType {
	TRIPLE_CANOPY_JUNGLE,  # Dense, -70% speed, max concealment
	TRIPLE_CANOPY,         # Alias for TRIPLE_CANOPY_JUNGLE
	SINGLE_CANOPY,         # Light jungle, -40% speed
	BAMBOO,                # Dense but cuttable
	RICE_PADDY,            # Open, wet, -30% speed
	ELEPHANT_GRASS,        # Concealment, fire hazard
	VILLAGE,               # Buildings, civilians
	RIVER,                 # Fordable or bridge only
	HILL,                  # Height advantage
	MOUNTAIN,              # Steep terrain, -60% speed
	CLEARED_FIREBASE,      # Player-cleared area
	CLEARED,               # Alias for CLEARED_FIREBASE
	ROAD,                  # +25% speed, ambush magnet
	TRAIL,                 # Ho Chi Minh trail variants
	WATER,                 # Open water, impassable by ground
	SWAMP,                 # Coastal/delta marshland, -50% speed
}

# =============================================================================
# CLEARING STATES
# =============================================================================
enum ClearingState {
	JUNGLE,           # Dense vegetation
	PARTIALLY_CLEARED,# Trees down, stumps remain
	CLEARED,          # Flat, buildable
	FORTIFIED,        # Firebase perimeter
}

# =============================================================================
# BUILDING TYPES
# =============================================================================
enum BuildingType {
	# -------------------------------------------------------------------------
	# FIREBASE PERIMETER (0-10)
	# -------------------------------------------------------------------------
	SANDBAG_LIGHT,          # 0 - Light field sandbags (infantry/engineer placeable)
	SANDBAG_HEAVY,          # 1 - Heavy fortification sandbags (bulldozer only)
	BUNKER,                 # 2 - Hardened fighting position
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
	MEDICAL_STATION,        # 17 - Aid Station
	TOC,                    # 18 - Tactical Operations Center (HQ)
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
	CONEX_CELL,             # 106 - Solitary confinement box

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
}

# =============================================================================
# FIREBASE LEVELS
# =============================================================================
enum FirebaseLevel {
	PATROL_BASE,       # 4 building slots
	FIRE_SUPPORT_BASE, # 8 building slots
	MAJOR_FIREBASE,    # 12 building slots
}

# =============================================================================
# HELICOPTER MISSION TYPES
# =============================================================================
enum HeliMissionType {
	# Automated loops
	SUPPLY_RUN,           # Ammo/supply delivery between firebases
	MEDEVAC_STANDBY,      # Auto-extract wounded when called
	TROOP_ROTATION,       # Regular reinforcement runs
	RECON_ORBIT,          # Circle area, spot enemies

	# Combat support
	GUNSHIP_CAP,          # Combat air patrol, engage on sight
	HUNTER_KILLER,        # Seek and destroy
	ESCORT_DUTY,          # Protect convoys/insertions
}

# =============================================================================
# SOG MISSION TYPES
# =============================================================================
enum SOGMissionType {
	RECON,              # Observe and report
	PRISONER_SNATCH,    # Capture enemy officer
	WIRE_TAP,           # Tap enemy comms
	BDA,                # Bomb damage assessment
	TRAIL_WATCH,        # Monitor Ho Chi Minh trail
	DIRECT_ACTION,      # Raid enemy installation
}

# =============================================================================
# WEATHER CONDITIONS
# =============================================================================
enum WeatherCondition {
	CLEAR,         # Full operations
	OVERCAST,      # Reduced air support accuracy
	MONSOON,       # -50% visibility, no air support, +VC morale
	FOG,           # No air support, reduced arty accuracy
	NIGHT,         # -80% visibility, +VC advantage, flares needed
}

# =============================================================================
# VILLAGE ALLEGIANCE
# =============================================================================
enum VillageAllegiance {
	NEUTRAL,
	PRO_US,
	PRO_VC,
	CONTESTED,
}

# =============================================================================
# RULES OF ENGAGEMENT
# =============================================================================
enum ROE {
	WEAPONS_FREE,     # Engage all hostiles
	WEAPONS_TIGHT,    # Engage only threats
	WEAPONS_HOLD,     # Defensive only
}

# =============================================================================
# LZ STATUS
# =============================================================================
enum LZStatus {
	COLD,      # No enemy contact
	WARM,      # Light contact expected
	HOT,       # Active enemy fire
}

# =============================================================================
# FORMATION TYPES
# =============================================================================
enum FormationType {
	LINE,
	COLUMN,
	WEDGE,
	V_FORMATION,
	STAGGERED_COLUMN,
}

# =============================================================================
# CONSTRUCTION STAGES
# =============================================================================
enum ConstructionStage {
	FOUNDATION,
	STRUCTURE,
	FINISHING,
	COMPLETE,
}

# =============================================================================
# WAYPOINT ACTIONS
# =============================================================================
enum WaypointAction {
	MOVE_TO,
	LOAD,
	UNLOAD,
	ATTACK,
	PATROL,
	LAND,
	HOVER,
}

# =============================================================================
# DAMAGE TYPES
# =============================================================================
enum DamageType {
	SMALL_ARMS,      # Rifles, pistols, SMGs
	HEAVY_MG,        # .50 cal, DShK
	EXPLOSIVE,       # Grenades, mortars
	SHAPED_CHARGE,   # RPG, LAW, recoilless
	ARTILLERY,       # Howitzer, heavy mortar
	NAPALM,          # Incendiary
	FRAGMENTATION,   # Air-burst, cluster
}

# =============================================================================
# FEAR TYPES (Spring 1944 inspired)
# =============================================================================
enum FearType {
	SMALL_ARMS,      # Rifles, SMGs - low suppression
	MACHINE_GUN,     # MGs - high sustained suppression
	MORTAR,          # Small explosions - moderate AOE
	ARTILLERY,       # Large explosions - high AOE
	NAPALM,          # Extreme - terror effect
	SNIPER,          # Precision fear - "someone's watching"
}

# Fear values - base suppression per source type
const FEAR_VALUES: Dictionary = {
	FearType.SMALL_ARMS: 2,
	FearType.MACHINE_GUN: 5,
	FearType.MORTAR: 8,
	FearType.ARTILLERY: 15,
	FearType.NAPALM: 25,
	FearType.SNIPER: 10,
}

# Fear AOE radii in meters - suppression affects units within this radius
const FEAR_AOE: Dictionary = {
	FearType.SMALL_ARMS: 3.0,    # Minimal
	FearType.MACHINE_GUN: 8.0,   # Beat zone
	FearType.MORTAR: 15.0,
	FearType.ARTILLERY: 25.0,
	FearType.NAPALM: 30.0,
	FearType.SNIPER: 5.0,
}

# =============================================================================
# SUPPRESSION STATES
# =============================================================================
enum SuppressionState {
	NORMAL,      # 0.0 - 0.3: Full effectiveness
	CAUTIOUS,    # 0.3 - 0.5: Reduced accuracy, seeking cover
	SUPPRESSED,  # 0.5 - 0.8: Prone, minimal fire, won't advance
	PINNED,      # 0.8 - 1.0: Can't fire, frozen in place
}

# Suppression state thresholds
const SUPPRESSION_THRESHOLDS: Dictionary = {
	SuppressionState.NORMAL: 0.0,
	SuppressionState.CAUTIOUS: 0.3,
	SuppressionState.SUPPRESSED: 0.5,
	SuppressionState.PINNED: 0.8,
}

# Effects per suppression state [accuracy_mult, speed_mult, can_fire, can_move]
const SUPPRESSION_EFFECTS: Dictionary = {
	SuppressionState.NORMAL: {"accuracy": 1.0, "speed": 1.0, "can_fire": true, "can_move": true},
	SuppressionState.CAUTIOUS: {"accuracy": 0.75, "speed": 0.8, "can_fire": true, "can_move": true},
	SuppressionState.SUPPRESSED: {"accuracy": 0.4, "speed": 0.5, "can_fire": true, "can_move": true},  # Crawl only
	SuppressionState.PINNED: {"accuracy": 0.1, "speed": 0.0, "can_fire": false, "can_move": false},
}

# =============================================================================
# ARTILLERY STATES
# =============================================================================
enum ArtilleryState {
	PACKED,      # 0 - Ready to move, not fireable
	PACKING,     # 1 - Transitioning to packed
	UNPACKING,   # 2 - Transitioning to deployed
	DEPLOYING,   # 3 - Setting up fire position
	DEPLOYED,    # 4 - Ready to fire
	FIRING,      # 5 - Currently firing
	RELOADING,   # 6 - Reloading ammunition
}

# =============================================================================
# AIRPLANE STATES
# =============================================================================
enum AirplaneState {
	IDLE_AT_AIRPORT,  # 0 - On ground, ready for takeoff
	TAKING_OFF,       # 1 - Departure sequence
	PATROLLING,       # 2 - In air, awaiting orders
	ATTACK_RUN,       # 3 - Executing attack run
	RETURNING,        # 4 - RTB (Return to Base)
	LANDING,          # 5 - Landing sequence
	CRASHED,          # 6 - Destroyed
}

# =============================================================================
# HELICOPTER STATES
# =============================================================================
enum HelicopterState {
	IDLE_ON_PAD,      # 0 - On ground at LZ
	TAKING_OFF,       # 1 - Lifting off
	EN_ROUTE,         # 2 - Flying to destination
	LANDING,          # 3 - Approaching LZ
	HOVERING,         # 4 - Stationary in air
	ATTACKING,        # 5 - Gunship attack run
	LOADING,          # 6 - Loading troops/supplies
	UNLOADING,        # 7 - Unloading troops/supplies
	CRASHED,          # 8 - Destroyed
}

# =============================================================================
# TRAINING LEVELS (Warno inspired)
# =============================================================================
enum TrainingLevel {
	CONSCRIPT,    # Poorly trained militia
	REGULAR,      # Standard infantry
	VETERAN,      # Experienced soldiers
	ELITE,        # Special forces, Rangers
}

# Training modifiers - affects suppression intake and recovery
const TRAINING_MODIFIERS: Dictionary = {
	TrainingLevel.CONSCRIPT: {
		"suppression_mult": 1.5,    # Takes 50% more suppression
		"recovery_mult": 0.5,       # Recovers 50% slower
		"break_threshold": 0.6,     # Breaks at 60% suppression
		"accuracy_bonus": 0.0,
	},
	TrainingLevel.REGULAR: {
		"suppression_mult": 1.0,
		"recovery_mult": 1.0,
		"break_threshold": 0.8,
		"accuracy_bonus": 0.0,
	},
	TrainingLevel.VETERAN: {
		"suppression_mult": 0.8,
		"recovery_mult": 1.3,
		"break_threshold": 0.9,
		"accuracy_bonus": 0.1,
	},
	TrainingLevel.ELITE: {
		"suppression_mult": 0.5,
		"recovery_mult": 2.0,
		"break_threshold": 1.0,  # Never breaks, only pins
		"accuracy_bonus": 0.2,
	},
}

# =============================================================================
# COVER TYPES (Warno inspired)
# =============================================================================
enum CoverType {
	NONE,        # Open ground
	LIGHT,       # Hedgerow, light vegetation
	HEAVY,       # Forest, solid cover
	FORTIFIED,   # Urban, bunker
}

# Cover damage reduction (infantry only, per Warno research)
const COVER_DAMAGE_REDUCTION: Dictionary = {
	CoverType.NONE: 0.0,
	CoverType.LIGHT: 0.4,       # 40% reduction
	CoverType.HEAVY: 0.6,       # 60% reduction
	CoverType.FORTIFIED: 0.7,   # 70% reduction
}

# Cover stealth bonus
const COVER_STEALTH_BONUS: Dictionary = {
	CoverType.NONE: 0.0,
	CoverType.LIGHT: 0.5,
	CoverType.HEAVY: 0.8,
	CoverType.FORTIFIED: 0.9,
}

# Cover suppression reduction (reduces incoming suppression)
const COVER_SUPPRESSION_REDUCTION: Dictionary = {
	CoverType.NONE: 1.0,
	CoverType.LIGHT: 0.7,       # 30% less suppression
	CoverType.HEAVY: 0.4,       # 60% less suppression
	CoverType.FORTIFIED: 0.2,   # 80% less suppression
}

# =============================================================================
# MORALE STATES
# =============================================================================
enum MoraleState {
	HIGH,      # > 0.8: Aggressive, willing to assault
	STEADY,    # 0.5 - 0.8: Normal operations
	SHAKEN,    # 0.3 - 0.5: Defensive only, no assault
	BROKEN,    # < 0.3: Retreating, ignores orders
}

# Morale state thresholds
const MORALE_THRESHOLDS: Dictionary = {
	MoraleState.HIGH: 0.8,
	MoraleState.STEADY: 0.5,
	MoraleState.SHAKEN: 0.3,
	MoraleState.BROKEN: 0.0,
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

static func is_us_faction(faction: Faction) -> bool:
	return faction == Faction.US_ARMY or faction == Faction.ARVN

static func is_enemy_faction(faction: Faction) -> bool:
	return faction == Faction.VC or faction == Faction.NVA

static func get_faction_name(faction: Faction) -> String:
	match faction:
		Faction.US_ARMY: return "US Army"
		Faction.ARVN: return "ARVN"
		Faction.VC: return "Viet Cong"
		Faction.NVA: return "NVA"
		_: return "Unknown"

static func can_call_air_support(weather: WeatherCondition) -> bool:
	return weather in [WeatherCondition.CLEAR, WeatherCondition.OVERCAST]

static func get_terrain_speed_modifier(terrain: TerrainType) -> float:
	match terrain:
		TerrainType.TRIPLE_CANOPY_JUNGLE, TerrainType.TRIPLE_CANOPY: return 0.3
		TerrainType.SINGLE_CANOPY: return 0.6
		TerrainType.BAMBOO: return 0.5
		TerrainType.RICE_PADDY: return 0.7
		TerrainType.ELEPHANT_GRASS: return 0.8
		TerrainType.ROAD: return 1.25
		TerrainType.TRAIL: return 1.0
		TerrainType.CLEARED_FIREBASE, TerrainType.CLEARED: return 1.0
		TerrainType.MOUNTAIN: return 0.4
		TerrainType.SWAMP: return 0.5
		TerrainType.WATER: return 0.0  # Impassable
		_: return 1.0

static func get_firebase_slots(level: FirebaseLevel) -> int:
	match level:
		FirebaseLevel.PATROL_BASE: return 4
		FirebaseLevel.FIRE_SUPPORT_BASE: return 8
		FirebaseLevel.MAJOR_FIREBASE: return 12
		_: return 4


## Get suppression state from suppression level (0.0 to 1.0)
func get_suppression_state(level: float) -> SuppressionState:
	if level >= 0.8:
		return SuppressionState.PINNED
	elif level >= 0.5:
		return SuppressionState.SUPPRESSED
	elif level >= 0.3:
		return SuppressionState.CAUTIOUS
	else:
		return SuppressionState.NORMAL


## Get suppression effects for a given state
func get_suppression_effects(state: SuppressionState) -> Dictionary:
	return SUPPRESSION_EFFECTS.get(state, SUPPRESSION_EFFECTS[SuppressionState.NORMAL])


## Get training modifier value
func get_training_modifier(level: TrainingLevel, modifier_key: String) -> float:
	var mods: Dictionary = TRAINING_MODIFIERS.get(level, TRAINING_MODIFIERS[TrainingLevel.REGULAR])
	return mods.get(modifier_key, 1.0)


## Get morale state from morale level (0.0 to 1.0)
func get_morale_state(level: float) -> MoraleState:
	if level >= 0.8:
		return MoraleState.HIGH
	elif level >= 0.5:
		return MoraleState.STEADY
	elif level >= 0.3:
		return MoraleState.SHAKEN
	else:
		return MoraleState.BROKEN


## Get fear value for a weapon type
func get_fear_value(fear_type: FearType) -> int:
	return FEAR_VALUES.get(fear_type, 2)


## Get fear AOE radius
func get_fear_aoe(fear_type: FearType) -> float:
	return FEAR_AOE.get(fear_type, 3.0)


## Get cover damage reduction
func get_cover_damage_reduction(cover_type: CoverType) -> float:
	return COVER_DAMAGE_REDUCTION.get(cover_type, 0.0)


## Get cover suppression modifier (multiplier on incoming suppression)
func get_cover_suppression_modifier(cover_type: CoverType) -> float:
	return COVER_SUPPRESSION_REDUCTION.get(cover_type, 1.0)


## Map terrain type to cover type
func terrain_to_cover(terrain: TerrainType) -> CoverType:
	match terrain:
		TerrainType.TRIPLE_CANOPY_JUNGLE, TerrainType.TRIPLE_CANOPY:
			return CoverType.HEAVY
		TerrainType.SINGLE_CANOPY, TerrainType.BAMBOO:
			return CoverType.HEAVY
		TerrainType.ELEPHANT_GRASS:
			return CoverType.LIGHT
		TerrainType.VILLAGE:
			return CoverType.FORTIFIED
		TerrainType.CLEARED_FIREBASE, TerrainType.CLEARED:
			return CoverType.NONE
		TerrainType.ROAD, TerrainType.TRAIL:
			return CoverType.NONE
		TerrainType.RICE_PADDY:
			return CoverType.LIGHT  # Prone in paddy gives some cover
		_:
			return CoverType.NONE
