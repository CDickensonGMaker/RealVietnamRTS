class_name DoctrineData extends Resource
## DoctrineData - Defines a faction doctrine (force composition and capabilities)
## Selected pre-mission to determine available units and buildings
## Per PRD Phase 7: MVP has Air Cavalry and Mechanized doctrines

enum DoctrineType {
	AIR_CAVALRY,    # Helicopter-focused, fast insertion
	MECHANIZED,     # Armor and APCs, road-dependent
	LIGHT_INFANTRY, # SOG-style, stealth and recon
	FIREBASE,       # Artillery-focused, defensive
}

@export_group("Identity")
@export var doctrine_id: String = "air_cav"
@export var doctrine_name: String = "Air Cavalry"
@export var doctrine_type: DoctrineType = DoctrineType.AIR_CAVALRY
@export_multiline var description: String = ""

@export_group("Available Units")
## Unit types available to this doctrine (GameEnums.UnitType values)
@export var available_units: Array[int] = []
## Unit limits per type (-1 = unlimited)
@export var unit_limits: Dictionary = {}

@export_group("Available Buildings")
## Building types available to this doctrine
@export var available_buildings: Array[int] = []
## Buildings that are restricted (cannot build)
@export var restricted_buildings: Array[int] = []

@export_group("Helicopters")
@export var max_helicopters: int = 8
@export var helicopter_types: Array[String] = []  # ["huey", "cobra", "loach"]

@export_group("Vehicles")
@export var max_vehicles: int = 4
@export var vehicle_types: Array[String] = []  # ["m113", "m48", "jeep"]

@export_group("Reinforcement Modifiers")
@export var infantry_cooldown_modifier: float = 1.0  # Multiplier on reinf cooldown
@export var vehicle_cooldown_modifier: float = 1.0
@export var helicopter_cooldown_modifier: float = 1.0
@export var initial_reinforcement_delay: float = 60.0  # Seconds before first reinforcement

@export_group("Combat Modifiers")
@export var infantry_damage_modifier: float = 1.0
@export var vehicle_armor_modifier: float = 1.0
@export var suppression_resistance: float = 1.0

@export_group("Special Abilities")
@export var can_call_napalm: bool = true
@export var can_call_arc_light: bool = false  # B-52 strikes
@export var can_build_advanced_firebase: bool = true
@export var has_rapid_insertion: bool = false  # Fast helicopter ops


## Check if a unit type is available
func is_unit_available(unit_type: int) -> bool:
	return unit_type in available_units


## Check if a building type is available
func is_building_available(building_type: int) -> bool:
	if building_type in restricted_buildings:
		return false
	if available_buildings.is_empty():
		return true  # No restrictions
	return building_type in available_buildings


## Get unit limit for a type
func get_unit_limit(unit_type: int) -> int:
	if unit_limits.has(unit_type):
		return unit_limits[unit_type]
	return -1  # Unlimited


## Get reinforcement cooldown for a unit type
func get_reinforcement_cooldown(base_cooldown: float, is_vehicle: bool = false, is_helicopter: bool = false) -> float:
	if is_helicopter:
		return base_cooldown * helicopter_cooldown_modifier
	elif is_vehicle:
		return base_cooldown * vehicle_cooldown_modifier
	else:
		return base_cooldown * infantry_cooldown_modifier


# =============================================================================
# FACTORY METHODS - Create MVP doctrines
# =============================================================================

static func create_air_cavalry() -> DoctrineData:
	"""Create Air Cavalry doctrine - helicopter-focused"""
	var doctrine := DoctrineData.new()
	doctrine.doctrine_id = "air_cav"
	doctrine.doctrine_name = "Air Cavalry"
	doctrine.doctrine_type = DoctrineType.AIR_CAVALRY
	doctrine.description = "1st Cavalry Division (Airmobile). Fast helicopter insertion, aggressive air support. Limited ground vehicles but excellent mobility."

	# Units: Infantry-focused with helicopter support
	doctrine.available_units = [
		0,   # RIFLE_SQUAD
		1,   # WEAPONS_SQUAD
		2,   # RECON_TEAM
		3,   # ENGINEER_SQUAD
		10,  # HUEY (transport)
		11,  # COBRA (gunship)
		12,  # LOACH (scout)
	]

	# Limited vehicles
	doctrine.max_vehicles = 2
	doctrine.vehicle_types = ["jeep"]

	# Strong helicopter presence
	doctrine.max_helicopters = 10
	doctrine.helicopter_types = ["huey", "cobra", "loach"]
	doctrine.helicopter_cooldown_modifier = 0.7  # 30% faster helo reinforcement

	# Infantry bonus for air assault
	doctrine.infantry_cooldown_modifier = 0.8
	doctrine.vehicle_cooldown_modifier = 1.5  # Slower vehicle reinforcement

	# No tanks allowed
	doctrine.restricted_buildings = [
		30,  # TANK_REVETMENT (can't build, no tanks)
	]

	# Special abilities
	doctrine.can_call_napalm = true
	doctrine.has_rapid_insertion = true
	doctrine.initial_reinforcement_delay = 30.0  # Fast first reinforcement

	return doctrine


static func create_mechanized() -> DoctrineData:
	"""Create Mechanized doctrine - armor and APCs"""
	var doctrine := DoctrineData.new()
	doctrine.doctrine_id = "mech"
	doctrine.doctrine_name = "Mechanized Infantry"
	doctrine.doctrine_type = DoctrineType.MECHANIZED
	doctrine.description = "25th Infantry Division (Mechanized). Strong armor support, M113 APCs for mobility. Road-dependent but powerful in direct combat."

	# Units: Infantry with vehicle support
	doctrine.available_units = [
		0,   # RIFLE_SQUAD
		1,   # WEAPONS_SQUAD
		2,   # RECON_TEAM
		3,   # ENGINEER_SQUAD
		20,  # M113_APC
		21,  # M48_PATTON
		22,  # M551_SHERIDAN
		10,  # HUEY (limited)
	]

	# Strong vehicle presence
	doctrine.max_vehicles = 8
	doctrine.vehicle_types = ["m113", "m48", "m551", "jeep"]
	doctrine.vehicle_cooldown_modifier = 0.7  # 30% faster vehicle reinforcement

	# Limited helicopters
	doctrine.max_helicopters = 4
	doctrine.helicopter_types = ["huey"]
	doctrine.helicopter_cooldown_modifier = 1.5  # Slower helo reinforcement

	# Infantry slower
	doctrine.infantry_cooldown_modifier = 1.0

	# Can build tank revetments
	doctrine.restricted_buildings = []

	# Combat bonuses
	doctrine.vehicle_armor_modifier = 1.2  # 20% more armor

	# Special abilities
	doctrine.can_call_napalm = true
	doctrine.can_call_arc_light = true  # B-52 access
	doctrine.initial_reinforcement_delay = 90.0  # Slower initial deployment

	return doctrine


static func get_doctrine(doctrine_id: String) -> DoctrineData:
	"""Get a doctrine by ID"""
	match doctrine_id:
		"air_cav":
			return create_air_cavalry()
		"mech":
			return create_mechanized()
		_:
			push_warning("Unknown doctrine: %s" % doctrine_id)
			return create_air_cavalry()  # Default


static func get_all_doctrines() -> Array[DoctrineData]:
	"""Get all available doctrines"""
	return [
		create_air_cavalry(),
		create_mechanized(),
	]
