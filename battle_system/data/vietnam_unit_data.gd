extends Resource
class_name VietnamUnitData
## VietnamUnitData - Data container for unit statistics

@export_group("Identification")
@export var unit_name: String = "Rifle Squad"
@export var unit_type: int = GameEnums.UnitType.RIFLE_PLATOON
@export var faction: int = GameEnums.Faction.US_ARMY
@export var icon: Texture2D

@export_group("Squad Composition")
@export var default_size: int = 10
@export var max_size: int = 12
@export var min_operational_size: int = 3  # Below this, squad is combat ineffective

@export_group("Movement")
@export var move_speed: float = 5.0
@export var run_speed: float = 8.0
@export var stealth_speed: float = 2.0
@export var rotation_speed: float = 5.0

@export_group("Combat")
@export var sight_range: float = 30.0
@export var attack_range: float = 25.0
@export var damage_per_second: float = 10.0
@export var base_accuracy: float = 0.7
@export var armor: float = 0.0  # Damage reduction

@export_group("Weapons")
@export var primary_weapon: int = GameEnums.WeaponClass.M16
@export var secondary_weapon: int = -1  # Optional
@export var support_weapon: int = -1    # Squad support weapon (M60, etc.)
@export var has_anti_armor: bool = false
@export var anti_armor_weapon: int = GameEnums.WeaponClass.M72_LAW

@export_group("Ammunition")
@export var max_ammo: int = 100
@export var ammo_consumption_rate: float = 1.0  # Multiplier

@export_group("Morale")
@export var base_morale: float = 100.0
@export var morale_recovery_rate: float = 5.0
@export var suppression_resistance: float = 0.5  # 0-1, higher = more resistant

@export_group("Special Abilities")
@export var can_build: bool = false
@export var can_heal: bool = false
@export var can_call_air_support: bool = false
@export var is_recon: bool = false
@export var is_special_ops: bool = false

@export_group("Costs")
@export var supply_cost: int = 20
@export var reinforcement_cost: int = 10  # Per replacement

# =============================================================================
# PRESET CREATION
# =============================================================================

static func create_rifle_platoon() -> VietnamUnitData:
	var data := VietnamUnitData.new()
	data.unit_name = "Rifle Platoon"
	data.unit_type = GameEnums.UnitType.RIFLE_PLATOON
	data.faction = GameEnums.Faction.US_ARMY
	data.default_size = 10
	data.max_size = 12
	data.move_speed = 5.0
	data.sight_range = 30.0
	data.attack_range = 25.0
	data.damage_per_second = 10.0
	data.primary_weapon = GameEnums.WeaponClass.M16
	data.support_weapon = GameEnums.WeaponClass.M60
	data.has_anti_armor = true
	data.supply_cost = 20
	return data

static func create_weapons_squad() -> VietnamUnitData:
	var data := VietnamUnitData.new()
	data.unit_name = "Weapons Squad"
	data.unit_type = GameEnums.UnitType.WEAPONS_SQUAD
	data.faction = GameEnums.Faction.US_ARMY
	data.default_size = 8
	data.max_size = 10
	data.move_speed = 4.0
	data.sight_range = 35.0
	data.attack_range = 40.0
	data.damage_per_second = 20.0
	data.primary_weapon = GameEnums.WeaponClass.M60
	data.secondary_weapon = GameEnums.WeaponClass.M79
	data.suppression_resistance = 0.6
	data.supply_cost = 30
	return data

static func create_engineers() -> VietnamUnitData:
	var data := VietnamUnitData.new()
	data.unit_name = "Combat Engineers"
	data.unit_type = GameEnums.UnitType.ENGINEERS
	data.faction = GameEnums.Faction.US_ARMY
	data.default_size = 8
	data.max_size = 10
	data.move_speed = 4.0
	data.sight_range = 25.0
	data.attack_range = 20.0
	data.damage_per_second = 8.0
	data.primary_weapon = GameEnums.WeaponClass.M16
	data.can_build = true
	data.supply_cost = 25
	return data

static func create_sog_team() -> VietnamUnitData:
	var data := VietnamUnitData.new()
	data.unit_name = "SOG Recon Team"
	data.unit_type = GameEnums.UnitType.SOG_TEAM
	data.faction = GameEnums.Faction.US_ARMY
	data.default_size = 6
	data.max_size = 6
	data.move_speed = 6.0
	data.stealth_speed = 3.0
	data.sight_range = 45.0
	data.attack_range = 30.0
	data.damage_per_second = 15.0
	data.base_accuracy = 0.85
	data.primary_weapon = GameEnums.WeaponClass.M16
	data.is_recon = true
	data.is_special_ops = true
	data.morale_recovery_rate = 10.0
	data.suppression_resistance = 0.8
	data.supply_cost = 50
	return data

static func create_vc_infantry() -> VietnamUnitData:
	var data := VietnamUnitData.new()
	data.unit_name = "VC Infantry"
	data.unit_type = GameEnums.UnitType.VC_INFANTRY
	data.faction = GameEnums.Faction.VC
	data.default_size = 10
	data.max_size = 15
	data.move_speed = 5.5  # Faster in jungle
	data.sight_range = 25.0
	data.attack_range = 20.0
	data.damage_per_second = 8.0
	data.base_accuracy = 0.6
	data.primary_weapon = GameEnums.WeaponClass.AK47
	data.morale_recovery_rate = 3.0
	data.supply_cost = 10
	return data

static func create_vc_sappers() -> VietnamUnitData:
	var data := VietnamUnitData.new()
	data.unit_name = "VC Sappers"
	data.unit_type = GameEnums.UnitType.VC_SAPPERS
	data.faction = GameEnums.Faction.VC
	data.default_size = 6
	data.max_size = 8
	data.move_speed = 4.0
	data.stealth_speed = 3.0
	data.sight_range = 20.0
	data.attack_range = 5.0
	data.damage_per_second = 50.0  # High damage vs structures
	data.primary_weapon = GameEnums.WeaponClass.AK47
	data.can_build = true  # Can plant explosives
	data.supply_cost = 15
	return data

static func create_nva_infantry() -> VietnamUnitData:
	var data := VietnamUnitData.new()
	data.unit_name = "NVA Infantry"
	data.unit_type = GameEnums.UnitType.NVA_INFANTRY
	data.faction = GameEnums.Faction.NVA
	data.default_size = 10
	data.max_size = 12
	data.move_speed = 5.0
	data.sight_range = 28.0
	data.attack_range = 25.0
	data.damage_per_second = 10.0
	data.base_accuracy = 0.65
	data.primary_weapon = GameEnums.WeaponClass.AK47
	data.has_anti_armor = true
	data.anti_armor_weapon = GameEnums.WeaponClass.RPG7
	data.suppression_resistance = 0.5
	data.supply_cost = 12
	return data

static func create_nva_heavy_weapons() -> VietnamUnitData:
	var data := VietnamUnitData.new()
	data.unit_name = "NVA Heavy Weapons"
	data.unit_type = GameEnums.UnitType.NVA_HEAVY_WEAPONS
	data.faction = GameEnums.Faction.NVA
	data.default_size = 8
	data.max_size = 10
	data.move_speed = 3.5
	data.sight_range = 35.0
	data.attack_range = 50.0
	data.damage_per_second = 25.0
	data.primary_weapon = GameEnums.WeaponClass.DSHK
	data.secondary_weapon = GameEnums.WeaponClass.MORTAR_82MM
	data.suppression_resistance = 0.6
	data.supply_cost = 25
	return data


static func create_vc_mortar() -> VietnamUnitData:
	var data := VietnamUnitData.new()
	data.unit_name = "VC Mortar Team"
	data.unit_type = GameEnums.UnitType.VC_MORTAR
	data.faction = GameEnums.Faction.VC
	data.default_size = 4
	data.max_size = 6
	data.move_speed = 3.5
	data.sight_range = 20.0
	data.attack_range = 80.0  # Indirect fire
	data.damage_per_second = 30.0
	data.primary_weapon = GameEnums.WeaponClass.MORTAR_82MM
	data.secondary_weapon = GameEnums.WeaponClass.AK47
	data.morale_recovery_rate = 2.0  # Hit and run mentality
	data.supply_cost = 20
	return data


static func create_vc_local_force() -> VietnamUnitData:
	var data := VietnamUnitData.new()
	data.unit_name = "VC Local Force"
	data.unit_type = GameEnums.UnitType.VC_LOCAL_FORCE
	data.faction = GameEnums.Faction.VC
	data.default_size = 15
	data.max_size = 20
	data.min_operational_size = 5
	data.move_speed = 5.0
	data.sight_range = 20.0
	data.attack_range = 15.0
	data.damage_per_second = 5.0
	data.base_accuracy = 0.4
	data.primary_weapon = GameEnums.WeaponClass.SKS
	data.base_morale = 60.0  # Lower morale than regulars
	data.morale_recovery_rate = 2.0
	data.suppression_resistance = 0.3
	data.supply_cost = 5
	return data


static func create_nva_sappers() -> VietnamUnitData:
	var data := VietnamUnitData.new()
	data.unit_name = "NVA Sappers"
	data.unit_type = GameEnums.UnitType.NVA_SAPPERS
	data.faction = GameEnums.Faction.NVA
	data.default_size = 8
	data.max_size = 10
	data.move_speed = 4.5
	data.stealth_speed = 3.5
	data.sight_range = 25.0
	data.attack_range = 8.0
	data.damage_per_second = 60.0  # Very high vs structures
	data.base_accuracy = 0.7
	data.primary_weapon = GameEnums.WeaponClass.AK47
	data.can_build = true  # Explosives, bangalore torpedoes
	data.base_morale = 90.0
	data.suppression_resistance = 0.7
	data.supply_cost = 30
	return data


static func create_nva_aaa() -> VietnamUnitData:
	var data := VietnamUnitData.new()
	data.unit_name = "NVA AAA Crew"
	data.unit_type = GameEnums.UnitType.NVA_AAA
	data.faction = GameEnums.Faction.NVA
	data.default_size = 6
	data.max_size = 8
	data.move_speed = 2.0  # Heavy weapon
	data.sight_range = 60.0  # Long range AA
	data.attack_range = 80.0
	data.damage_per_second = 35.0
	data.primary_weapon = GameEnums.WeaponClass.DSHK
	data.suppression_resistance = 0.5
	data.supply_cost = 40
	return data


# =============================================================================
# ARVN UNITS
# =============================================================================

static func create_arvn_rifle() -> VietnamUnitData:
	var data := VietnamUnitData.new()
	data.unit_name = "ARVN Rifle Platoon"
	data.unit_type = GameEnums.UnitType.RIFLE_PLATOON
	data.faction = GameEnums.Faction.ARVN
	data.default_size = 10
	data.max_size = 12
	data.move_speed = 4.5
	data.sight_range = 28.0
	data.attack_range = 22.0
	data.damage_per_second = 8.0
	data.base_accuracy = 0.6
	data.primary_weapon = GameEnums.WeaponClass.M16
	data.base_morale = 70.0  # Lower morale than US
	data.morale_recovery_rate = 3.0
	data.suppression_resistance = 0.4
	data.supply_cost = 15
	return data


# =============================================================================
# MEDIC TEAM
# =============================================================================

static func create_medic_team() -> VietnamUnitData:
	var data := VietnamUnitData.new()
	data.unit_name = "Medic Team"
	data.unit_type = GameEnums.UnitType.RIFLE_PLATOON  # Use rifle as base
	data.faction = GameEnums.Faction.US_ARMY
	data.default_size = 4
	data.max_size = 6
	data.move_speed = 5.0
	data.sight_range = 25.0
	data.attack_range = 15.0
	data.damage_per_second = 5.0
	data.primary_weapon = GameEnums.WeaponClass.M1911
	data.can_heal = true
	data.supply_cost = 20
	return data


# =============================================================================
# FORWARD OBSERVER
# =============================================================================

static func create_forward_observer() -> VietnamUnitData:
	var data := VietnamUnitData.new()
	data.unit_name = "Forward Observer"
	data.unit_type = GameEnums.UnitType.RIFLE_PLATOON
	data.faction = GameEnums.Faction.US_ARMY
	data.default_size = 3
	data.max_size = 4
	data.move_speed = 5.5
	data.sight_range = 50.0  # Extended sight for spotting
	data.attack_range = 20.0
	data.damage_per_second = 6.0
	data.primary_weapon = GameEnums.WeaponClass.M16
	data.is_recon = true
	data.can_call_air_support = true
	data.supply_cost = 35
	return data


# =============================================================================
# UNIT FACTORY
# =============================================================================

static var _unit_cache: Dictionary = {}

static func get_unit_data(unit_type: int, faction: int = GameEnums.Faction.US_ARMY) -> VietnamUnitData:
	var key := "%d_%d" % [unit_type, faction]
	if _unit_cache.has(key):
		return _unit_cache[key]

	var data: VietnamUnitData = null

	match unit_type:
		GameEnums.UnitType.RIFLE_PLATOON:
			if faction == GameEnums.Faction.ARVN:
				data = create_arvn_rifle()
			else:
				data = create_rifle_platoon()
		GameEnums.UnitType.WEAPONS_SQUAD:
			data = create_weapons_squad()
		GameEnums.UnitType.ENGINEERS:
			data = create_engineers()
		GameEnums.UnitType.SOG_TEAM:
			data = create_sog_team()
		GameEnums.UnitType.VC_INFANTRY:
			data = create_vc_infantry()
		GameEnums.UnitType.VC_SAPPERS:
			data = create_vc_sappers()
		GameEnums.UnitType.VC_MORTAR:
			data = create_vc_mortar()
		GameEnums.UnitType.VC_LOCAL_FORCE:
			data = create_vc_local_force()
		GameEnums.UnitType.NVA_INFANTRY:
			data = create_nva_infantry()
		GameEnums.UnitType.NVA_HEAVY_WEAPONS:
			data = create_nva_heavy_weapons()
		GameEnums.UnitType.NVA_AAA:
			data = create_nva_aaa()
		GameEnums.UnitType.NVA_SAPPERS:
			data = create_nva_sappers()
		_:
			data = create_rifle_platoon()

	_unit_cache[key] = data
	return data


static func get_all_us_units() -> Array[VietnamUnitData]:
	return [
		create_rifle_platoon(),
		create_weapons_squad(),
		create_engineers(),
		create_sog_team(),
		create_medic_team(),
		create_forward_observer(),
	]


static func get_all_vc_units() -> Array[VietnamUnitData]:
	return [
		create_vc_infantry(),
		create_vc_sappers(),
		create_vc_mortar(),
		create_vc_local_force(),
	]


static func get_all_nva_units() -> Array[VietnamUnitData]:
	return [
		create_nva_infantry(),
		create_nva_heavy_weapons(),
		create_nva_aaa(),
		create_nva_sappers(),
	]
