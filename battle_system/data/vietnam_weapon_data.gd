class_name VietnamWeaponData
extends Resource

## Vietnam-era weapon definitions for modern firearm combat.
## Adapted from BP_RTS_Dark_Shadows WeaponClassData for realistic infantry combat.
## Supports rifles, machine guns, rockets, grenades, artillery, helicopter weapons, and aircraft ordnance.

## Fire pattern determines how soldiers/weapons release shots.
enum FirePattern {
	SINGLE,         # Single aimed shots (rifles, pistols)
	BURST,          # 3-round burst (M16A2 style)
	AUTO,           # Full automatic continuous fire
	VOLLEY,         # Coordinated volley (artillery barrage)
	STAGGER,        # Staggered continuous fire (MG teams)
}

## Trajectory determines arc and LOS rules.
enum Trajectory {
	FLAT,           # Direct fire, requires LOS (bullets)
	ARCING,         # Mild arc for grenades/rockets
	HIGH_ARC,       # Indirect fire for mortars/artillery
	DIVING,         # Aircraft attack run trajectory
	NAPALM,         # Low-level napalm drop with spread
}

## Damage types affect morale and special effects.
enum DamageType {
	KINETIC,        # Standard bullet/shell damage
	EXPLOSIVE,      # Explosive damage with AOE
	FIRE,           # Napalm/incendiary - causes panic
	FRAGMENTATION,  # Shrapnel from grenades/artillery
	ARMOR_PIERCING, # Anti-vehicle rounds
}

## Weapon categories for organization.
enum WeaponCategory {
	RIFLE,
	MACHINE_GUN,
	SIDEARM,
	GRENADE_LAUNCHER,
	ROCKET_LAUNCHER,
	MORTAR,
	ARTILLERY,
	TANK_MAIN_GUN,
	VEHICLE_MG,
	HELICOPTER_MINIGUN,
	HELICOPTER_ROCKET,
	AIRCRAFT_GUN,
	AIRCRAFT_BOMB,
	AIRCRAFT_NAPALM,
}

## Per-weapon definition.
class WeaponDef extends RefCounted:
	var weapon_name: String = ""
	var category: int = WeaponCategory.RIFLE
	var fire_pattern: int = FirePattern.SINGLE
	var trajectory: int = Trajectory.FLAT
	var damage_type: int = DamageType.KINETIC

	# Fear type (Spring 1944 inspired) - determines base suppression effect
	var fear_type: int = GameEnums.FearType.SMALL_ARMS

	# Fire rate and reload
	var rate_of_fire: float = 60.0      # Rounds per minute (for display)
	var reload_time: float = 3.0        # Seconds to reload magazine/belt
	var burst_count: int = 1            # Rounds per trigger pull (1=semi, 3=burst, 0=auto)
	var burst_delay: float = 0.1        # Seconds between rounds in burst

	# Damage and range
	var damage: float = 15.0            # Base damage per hit
	var effective_range: float = 300.0  # Meters (full accuracy)
	var max_range: float = 500.0        # Meters (reduced accuracy)
	var min_range: float = 0.0          # Minimum engagement range

	# Accuracy
	var base_accuracy: float = 0.7      # Base hit chance at effective range
	var accuracy_falloff: float = 0.4   # Accuracy at max range
	var scatter_angle: float = 2.0      # Degrees of scatter
	var moving_penalty: float = 0.5     # Accuracy multiplier when moving
	var accuracy_variance: float = 0.1  # Random variance in accuracy (0.0=consistent, 0.4=wildly random)
	# Low variance (0.05-0.1): Precision weapons (helicopters, jets, snipers)
	# Medium variance (0.1-0.2): Infantry rifles, MGs
	# High variance (0.2-0.4): Artillery, mortars, tank main guns

	# Suppression (morale damage)
	var suppression: float = 5.0        # Morale damage per hit
	var suppression_near_miss: float = 2.5  # Suppression from near misses (typically 50% of hit)
	var suppression_radius: float = 0.0 # AOE suppression (MGs, explosions)

	# AOE properties
	var aoe_radius: float = 0.0         # 0 = single target
	var aoe_falloff: bool = true        # Damage decreases from center

	# Projectile properties
	var projectile_speed: float = 300.0 # Very fast for bullets
	var arc_height: float = 0.0         # Arc height for arcing projectiles
	var lifetime: float = 2.0           # Projectile lifetime in seconds

	# Pierce properties (for AP rounds, large caliber)
	var max_pierces: int = 0            # How many targets can be hit
	var pierce_falloff: float = 0.3     # Damage reduction per pierce

	# Anti-armor properties
	var armor_penetration: float = 0.0  # mm of armor penetrated
	var anti_vehicle_bonus: float = 0.0 # Extra damage vs vehicles

	# Crew requirements
	var crew_required: int = 1          # Soldiers needed to operate

	# Visual/audio
	var muzzle_flash: bool = true
	var tracer_ratio: int = 5           # Every Nth round is tracer (0=none)
	var sound_profile: String = "rifle" # Audio category

	# Ammo
	var magazine_size: int = 20         # Rounds before reload
	var ammo_type: String = "5.56mm"    # For supply system


## All weapon definitions, keyed by weapon ID.
static var DEFINITIONS: Dictionary = {}
static var _initialized: bool = false


static func _init_definitions() -> void:
	if _initialized:
		return
	_initialized = true

	# ========================================
	# US INFANTRY WEAPONS
	# ========================================

	# === M16 (Standard US Rifle) ===
	var m16 := WeaponDef.new()
	m16.weapon_name = "M16"
	m16.category = WeaponCategory.RIFLE
	m16.fire_pattern = FirePattern.BURST  # 3-round burst typical
	m16.trajectory = Trajectory.FLAT
	m16.damage_type = DamageType.KINETIC
	m16.fear_type = GameEnums.FearType.SMALL_ARMS
	m16.rate_of_fire = 700.0
	m16.reload_time = 2.5
	m16.burst_count = 3
	m16.burst_delay = 0.08
	m16.damage = 15.0
	m16.effective_range = 300.0
	m16.max_range = 550.0
	m16.base_accuracy = 0.75
	m16.accuracy_falloff = 0.35
	m16.scatter_angle = 2.0
	m16.suppression = 5.0
	m16.suppression_near_miss = 2.5
	m16.projectile_speed = 400.0
	m16.magazine_size = 20
	m16.ammo_type = "5.56mm"
	m16.sound_profile = "rifle_556"
	m16.accuracy_variance = 0.1  # Infantry rifle - standard variance
	DEFINITIONS["m16"] = m16

	# === M14 (Marksman Rifle) ===
	var m14 := WeaponDef.new()
	m14.weapon_name = "M14"
	m14.category = WeaponCategory.RIFLE
	m14.fire_pattern = FirePattern.SINGLE
	m14.trajectory = Trajectory.FLAT
	m14.damage_type = DamageType.KINETIC
	m14.fear_type = GameEnums.FearType.SMALL_ARMS
	m14.rate_of_fire = 120.0
	m14.reload_time = 3.0
	m14.burst_count = 1
	m14.damage = 25.0  # Heavier round
	m14.effective_range = 400.0
	m14.max_range = 700.0
	m14.base_accuracy = 0.85
	m14.accuracy_falloff = 0.45
	m14.scatter_angle = 1.0
	m14.suppression = 6.0
	m14.suppression_near_miss = 3.0
	m14.projectile_speed = 450.0
	m14.magazine_size = 20
	m14.ammo_type = "7.62mm"
	m14.sound_profile = "rifle_762"
	m14.accuracy_variance = 0.08  # Marksman rifle - slightly more consistent
	DEFINITIONS["m14"] = m14

	# === M60 (Medium Machine Gun) ===
	var m60 := WeaponDef.new()
	m60.weapon_name = "M60"
	m60.category = WeaponCategory.MACHINE_GUN
	m60.fire_pattern = FirePattern.AUTO
	m60.trajectory = Trajectory.FLAT
	m60.damage_type = DamageType.KINETIC
	m60.fear_type = GameEnums.FearType.MACHINE_GUN
	m60.rate_of_fire = 550.0
	m60.reload_time = 8.0  # Belt change takes time
	m60.burst_count = 0  # Full auto
	m60.damage = 25.0
	m60.effective_range = 500.0
	m60.max_range = 1100.0
	m60.base_accuracy = 0.65
	m60.accuracy_falloff = 0.30
	m60.scatter_angle = 3.5  # Some spread
	m60.moving_penalty = 0.3  # Hard to fire while moving
	m60.suppression = 30.0  # High suppression
	m60.suppression_near_miss = 15.0
	m60.suppression_radius = 3.0  # Affects nearby units
	m60.projectile_speed = 450.0
	m60.tracer_ratio = 5  # Every 5th round
	m60.magazine_size = 100
	m60.ammo_type = "7.62mm_linked"
	m60.sound_profile = "mg_762"
	m60.crew_required = 2
	m60.accuracy_variance = 0.12  # MG - sustained fire has some spread
	DEFINITIONS["m60"] = m60

	# === M2 Browning (.50 cal Heavy MG) ===
	var m2 := WeaponDef.new()
	m2.weapon_name = "M2 Browning"
	m2.category = WeaponCategory.MACHINE_GUN
	m2.fire_pattern = FirePattern.AUTO
	m2.trajectory = Trajectory.FLAT
	m2.damage_type = DamageType.KINETIC
	m2.fear_type = GameEnums.FearType.MACHINE_GUN
	m2.rate_of_fire = 500.0
	m2.reload_time = 10.0
	m2.burst_count = 0
	m2.damage = 50.0  # Heavy damage
	m2.effective_range = 800.0
	m2.max_range = 1800.0
	m2.base_accuracy = 0.60
	m2.accuracy_falloff = 0.25
	m2.scatter_angle = 2.5
	m2.suppression = 50.0
	m2.suppression_near_miss = 25.0
	m2.suppression_radius = 5.0
	m2.projectile_speed = 500.0
	m2.max_pierces = 1  # Can hit through light cover
	m2.armor_penetration = 15.0  # Light vehicle armor
	m2.anti_vehicle_bonus = 0.5
	m2.tracer_ratio = 5
	m2.magazine_size = 100
	m2.ammo_type = "50cal"
	m2.sound_profile = "mg_50cal"
	m2.crew_required = 2
	m2.accuracy_variance = 0.12  # Heavy MG - sustained fire spread
	DEFINITIONS["m2_browning"] = m2

	# === M79 (Grenade Launcher) ===
	var m79 := WeaponDef.new()
	m79.weapon_name = "M79"
	m79.category = WeaponCategory.GRENADE_LAUNCHER
	m79.fire_pattern = FirePattern.SINGLE
	m79.trajectory = Trajectory.ARCING
	m79.damage_type = DamageType.FRAGMENTATION
	m79.fear_type = GameEnums.FearType.MORTAR  # Explosive, use mortar fear
	m79.rate_of_fire = 6.0  # Slow reload
	m79.reload_time = 4.0
	m79.burst_count = 1
	m79.damage = 80.0
	m79.effective_range = 150.0
	m79.max_range = 350.0
	m79.min_range = 30.0  # Arming distance
	m79.base_accuracy = 0.70
	m79.accuracy_falloff = 0.40
	m79.scatter_angle = 4.0
	m79.suppression = 40.0
	m79.suppression_near_miss = 25.0
	m79.suppression_radius = 8.0
	m79.aoe_radius = 5.0
	m79.aoe_falloff = true
	m79.projectile_speed = 80.0
	m79.arc_height = 10.0
	m79.magazine_size = 1
	m79.ammo_type = "40mm_he"
	m79.sound_profile = "grenade_launcher"
	m79.accuracy_variance = 0.15  # Grenade launcher - arc trajectory adds variance
	DEFINITIONS["m79"] = m79

	# === M72 LAW (Light Anti-Tank) ===
	var m72 := WeaponDef.new()
	m72.weapon_name = "M72 LAW"
	m72.category = WeaponCategory.ROCKET_LAUNCHER
	m72.fire_pattern = FirePattern.SINGLE
	m72.trajectory = Trajectory.FLAT
	m72.damage_type = DamageType.ARMOR_PIERCING
	m72.fear_type = GameEnums.FearType.MORTAR  # Rocket explosion
	m72.rate_of_fire = 0.5  # Disposable
	m72.reload_time = 0.0  # Can't reload - disposable
	m72.burst_count = 1
	m72.damage = 200.0
	m72.effective_range = 150.0
	m72.max_range = 200.0
	m72.min_range = 10.0
	m72.base_accuracy = 0.60
	m72.accuracy_falloff = 0.30
	m72.scatter_angle = 3.0
	m72.suppression = 50.0
	m72.suppression_near_miss = 30.0
	m72.suppression_radius = 6.0
	m72.aoe_radius = 3.0  # Small blast
	m72.projectile_speed = 150.0
	m72.armor_penetration = 200.0  # Can defeat most armor
	m72.anti_vehicle_bonus = 2.0
	m72.magazine_size = 1
	m72.ammo_type = "66mm_heat"
	m72.sound_profile = "rocket"
	m72.accuracy_variance = 0.2  # Unguided rocket - significant variance
	DEFINITIONS["m72_law"] = m72

	# ========================================
	# VC/NVA WEAPONS
	# ========================================

	# === AK-47 ===
	var ak47 := WeaponDef.new()
	ak47.weapon_name = "AK-47"
	ak47.category = WeaponCategory.RIFLE
	ak47.fire_pattern = FirePattern.AUTO
	ak47.trajectory = Trajectory.FLAT
	ak47.damage_type = DamageType.KINETIC
	ak47.fear_type = GameEnums.FearType.SMALL_ARMS
	ak47.rate_of_fire = 600.0
	ak47.reload_time = 2.8
	ak47.burst_count = 0  # Full auto
	ak47.damage = 18.0  # Slightly higher than M16
	ak47.effective_range = 250.0  # Less accurate
	ak47.max_range = 400.0
	ak47.base_accuracy = 0.65
	ak47.accuracy_falloff = 0.30
	ak47.scatter_angle = 4.0  # More spread
	ak47.suppression = 6.0
	ak47.suppression_near_miss = 3.0
	ak47.projectile_speed = 380.0
	ak47.magazine_size = 30
	ak47.ammo_type = "7.62x39mm"
	ak47.sound_profile = "rifle_762_soviet"
	ak47.accuracy_variance = 0.12  # AK - reliable but less precise than M16
	DEFINITIONS["ak47"] = ak47

	# === SKS ===
	var sks := WeaponDef.new()
	sks.weapon_name = "SKS"
	sks.category = WeaponCategory.RIFLE
	sks.fire_pattern = FirePattern.SINGLE
	sks.trajectory = Trajectory.FLAT
	sks.damage_type = DamageType.KINETIC
	sks.fear_type = GameEnums.FearType.SMALL_ARMS
	sks.rate_of_fire = 40.0
	sks.reload_time = 4.0  # Stripper clip
	sks.burst_count = 1
	sks.damage = 20.0
	sks.effective_range = 350.0
	sks.max_range = 500.0
	sks.base_accuracy = 0.75
	sks.accuracy_falloff = 0.40
	sks.scatter_angle = 2.0
	sks.suppression = 5.0
	sks.suppression_near_miss = 2.5
	sks.projectile_speed = 400.0
	sks.magazine_size = 10
	sks.ammo_type = "7.62x39mm"
	sks.sound_profile = "rifle_762_soviet"
	sks.accuracy_variance = 0.1  # SKS - standard infantry variance
	DEFINITIONS["sks"] = sks

	# === RPD (Light Machine Gun) ===
	var rpd := WeaponDef.new()
	rpd.weapon_name = "RPD"
	rpd.category = WeaponCategory.MACHINE_GUN
	rpd.fire_pattern = FirePattern.AUTO
	rpd.trajectory = Trajectory.FLAT
	rpd.damage_type = DamageType.KINETIC
	rpd.fear_type = GameEnums.FearType.MACHINE_GUN
	rpd.rate_of_fire = 700.0
	rpd.reload_time = 7.0
	rpd.burst_count = 0
	rpd.damage = 18.0
	rpd.effective_range = 400.0
	rpd.max_range = 800.0
	rpd.base_accuracy = 0.60
	rpd.accuracy_falloff = 0.30
	rpd.scatter_angle = 4.0
	rpd.suppression = 25.0
	rpd.suppression_near_miss = 12.0
	rpd.suppression_radius = 2.5
	rpd.projectile_speed = 380.0
	rpd.tracer_ratio = 5
	rpd.magazine_size = 100
	rpd.ammo_type = "7.62x39mm_linked"
	rpd.sound_profile = "mg_762_soviet"
	rpd.crew_required = 1  # Can be used by single soldier
	rpd.accuracy_variance = 0.12  # LMG - sustained fire spread
	DEFINITIONS["rpd"] = rpd

	# === DShK (Heavy Machine Gun) ===
	var dshk := WeaponDef.new()
	dshk.weapon_name = "DShK"
	dshk.category = WeaponCategory.MACHINE_GUN
	dshk.fire_pattern = FirePattern.AUTO
	dshk.trajectory = Trajectory.FLAT
	dshk.damage_type = DamageType.KINETIC
	dshk.fear_type = GameEnums.FearType.MACHINE_GUN
	dshk.rate_of_fire = 600.0
	dshk.reload_time = 12.0
	dshk.burst_count = 0
	dshk.damage = 55.0
	dshk.effective_range = 800.0
	dshk.max_range = 2000.0  # Can engage aircraft
	dshk.base_accuracy = 0.55
	dshk.accuracy_falloff = 0.25
	dshk.scatter_angle = 3.0
	dshk.suppression = 55.0
	dshk.suppression_near_miss = 30.0
	dshk.suppression_radius = 5.0
	dshk.projectile_speed = 500.0
	dshk.max_pierces = 1
	dshk.armor_penetration = 20.0
	dshk.anti_vehicle_bonus = 0.6
	dshk.tracer_ratio = 4
	dshk.magazine_size = 50
	dshk.ammo_type = "12.7mm"
	dshk.sound_profile = "mg_127mm"
	dshk.crew_required = 3
	dshk.accuracy_variance = 0.14  # Heavy MG - some variance in sustained fire
	DEFINITIONS["dshk"] = dshk

	# === RPG-7 ===
	var rpg7 := WeaponDef.new()
	rpg7.weapon_name = "RPG-7"
	rpg7.category = WeaponCategory.ROCKET_LAUNCHER
	rpg7.fire_pattern = FirePattern.SINGLE
	rpg7.trajectory = Trajectory.FLAT
	rpg7.damage_type = DamageType.ARMOR_PIERCING
	rpg7.fear_type = GameEnums.FearType.MORTAR
	rpg7.rate_of_fire = 4.0
	rpg7.reload_time = 8.0
	rpg7.burst_count = 1
	rpg7.damage = 250.0
	rpg7.effective_range = 100.0
	rpg7.max_range = 150.0  # Rockets drop at range
	rpg7.min_range = 5.0
	rpg7.base_accuracy = 0.55
	rpg7.accuracy_falloff = 0.25
	rpg7.scatter_angle = 5.0
	rpg7.suppression = 60.0
	rpg7.suppression_near_miss = 35.0
	rpg7.suppression_radius = 8.0
	rpg7.aoe_radius = 4.0
	rpg7.projectile_speed = 120.0
	rpg7.armor_penetration = 250.0
	rpg7.anti_vehicle_bonus = 2.5
	rpg7.magazine_size = 1
	rpg7.ammo_type = "pg7_heat"
	rpg7.sound_profile = "rocket_soviet"
	rpg7.accuracy_variance = 0.25  # Unguided rocket - high variance, creates tension
	DEFINITIONS["rpg7"] = rpg7

	# ========================================
	# MORTARS & ARTILLERY
	# ========================================

	# === 81mm Mortar (US) ===
	var mortar_81 := WeaponDef.new()
	mortar_81.weapon_name = "81mm Mortar"
	mortar_81.category = WeaponCategory.MORTAR
	mortar_81.fire_pattern = FirePattern.SINGLE
	mortar_81.trajectory = Trajectory.HIGH_ARC
	mortar_81.damage_type = DamageType.FRAGMENTATION
	mortar_81.fear_type = GameEnums.FearType.MORTAR
	mortar_81.rate_of_fire = 15.0
	mortar_81.reload_time = 4.0
	mortar_81.burst_count = 1
	mortar_81.damage = 120.0
	mortar_81.effective_range = 500.0
	mortar_81.max_range = 4000.0
	mortar_81.min_range = 100.0
	mortar_81.base_accuracy = 0.60
	mortar_81.accuracy_falloff = 0.35
	mortar_81.scatter_angle = 8.0  # Artillery scatter
	mortar_81.suppression = 70.0
	mortar_81.suppression_near_miss = 45.0
	mortar_81.suppression_radius = 12.0
	mortar_81.aoe_radius = 8.0
	mortar_81.aoe_falloff = true
	mortar_81.projectile_speed = 60.0
	mortar_81.arc_height = 50.0
	mortar_81.lifetime = 8.0
	mortar_81.magazine_size = 1
	mortar_81.ammo_type = "81mm_he"
	mortar_81.sound_profile = "mortar"
	mortar_81.crew_required = 3
	mortar_81.accuracy_variance = 0.3  # Mortar - indirect fire, high variance creates tension
	DEFINITIONS["mortar_81mm"] = mortar_81

	# === 82mm Mortar (NVA/VC) ===
	var mortar_82 := WeaponDef.new()
	mortar_82.weapon_name = "82mm Mortar"
	mortar_82.category = WeaponCategory.MORTAR
	mortar_82.fire_pattern = FirePattern.SINGLE
	mortar_82.trajectory = Trajectory.HIGH_ARC
	mortar_82.damage_type = DamageType.FRAGMENTATION
	mortar_82.fear_type = GameEnums.FearType.MORTAR
	mortar_82.rate_of_fire = 12.0
	mortar_82.reload_time = 5.0
	mortar_82.burst_count = 1
	mortar_82.damage = 130.0
	mortar_82.effective_range = 400.0
	mortar_82.max_range = 3000.0
	mortar_82.min_range = 80.0
	mortar_82.base_accuracy = 0.55
	mortar_82.accuracy_falloff = 0.30
	mortar_82.scatter_angle = 10.0
	mortar_82.suppression = 75.0
	mortar_82.suppression_near_miss = 50.0
	mortar_82.suppression_radius = 12.0
	mortar_82.aoe_radius = 9.0
	mortar_82.aoe_falloff = true
	mortar_82.projectile_speed = 55.0
	mortar_82.arc_height = 45.0
	mortar_82.lifetime = 8.0
	mortar_82.magazine_size = 1
	mortar_82.ammo_type = "82mm_he"
	mortar_82.sound_profile = "mortar_soviet"
	mortar_82.crew_required = 3
	mortar_82.accuracy_variance = 0.32  # Soviet mortar - slightly less accurate
	DEFINITIONS["mortar_82mm"] = mortar_82

	# === M102 Howitzer (105mm) ===
	var m102 := WeaponDef.new()
	m102.weapon_name = "M102 Howitzer"
	m102.category = WeaponCategory.ARTILLERY
	m102.fire_pattern = FirePattern.SINGLE
	m102.trajectory = Trajectory.HIGH_ARC
	m102.damage_type = DamageType.EXPLOSIVE
	m102.fear_type = GameEnums.FearType.ARTILLERY
	m102.rate_of_fire = 3.0
	m102.reload_time = 15.0
	m102.burst_count = 1
	m102.damage = 500.0
	m102.effective_range = 5000.0
	m102.max_range = 11000.0
	m102.min_range = 500.0
	m102.base_accuracy = 0.50
	m102.accuracy_falloff = 0.30
	m102.scatter_angle = 12.0
	m102.suppression = 100.0
	m102.suppression_near_miss = 70.0
	m102.suppression_radius = 20.0
	m102.aoe_radius = 15.0
	m102.aoe_falloff = true
	m102.projectile_speed = 100.0
	m102.arc_height = 80.0
	m102.lifetime = 15.0
	m102.magazine_size = 1
	m102.ammo_type = "105mm_he"
	m102.sound_profile = "artillery_105"
	m102.crew_required = 5
	m102.accuracy_variance = 0.35  # Artillery - maximum variance, shells can land anywhere in beaten zone
	DEFINITIONS["m102_howitzer"] = m102

	# ========================================
	# TANK WEAPONS
	# ========================================

	# === M48 Patton Main Gun (90mm) ===
	var m48_main := WeaponDef.new()
	m48_main.weapon_name = "90mm Tank Gun"
	m48_main.category = WeaponCategory.TANK_MAIN_GUN
	m48_main.fire_pattern = FirePattern.SINGLE
	m48_main.trajectory = Trajectory.FLAT
	m48_main.damage_type = DamageType.ARMOR_PIERCING
	m48_main.fear_type = GameEnums.FearType.ARTILLERY  # Tank shell = artillery fear
	m48_main.rate_of_fire = 7.0
	m48_main.reload_time = 8.0
	m48_main.burst_count = 1
	m48_main.damage = 400.0
	m48_main.effective_range = 1000.0
	m48_main.max_range = 2000.0
	m48_main.base_accuracy = 0.75
	m48_main.accuracy_falloff = 0.45
	m48_main.scatter_angle = 1.0
	m48_main.suppression = 80.0
	m48_main.suppression_near_miss = 50.0
	m48_main.suppression_radius = 10.0
	m48_main.aoe_radius = 6.0  # HE rounds
	m48_main.projectile_speed = 250.0
	m48_main.armor_penetration = 280.0
	m48_main.anti_vehicle_bonus = 3.0
	m48_main.magazine_size = 1
	m48_main.ammo_type = "90mm_aphe"
	m48_main.sound_profile = "tank_main"
	m48_main.accuracy_variance = 0.25  # Tank gun - direct fire but shells can vary
	DEFINITIONS["m48_main_gun"] = m48_main

	# === Coaxial MG (M73) ===
	var coax_mg := WeaponDef.new()
	coax_mg.weapon_name = "Coaxial M73"
	coax_mg.category = WeaponCategory.VEHICLE_MG
	coax_mg.fire_pattern = FirePattern.AUTO
	coax_mg.trajectory = Trajectory.FLAT
	coax_mg.damage_type = DamageType.KINETIC
	coax_mg.fear_type = GameEnums.FearType.MACHINE_GUN
	coax_mg.rate_of_fire = 600.0
	coax_mg.reload_time = 6.0
	coax_mg.burst_count = 0
	coax_mg.damage = 25.0
	coax_mg.effective_range = 500.0
	coax_mg.max_range = 1000.0
	coax_mg.base_accuracy = 0.70
	coax_mg.accuracy_falloff = 0.35
	coax_mg.scatter_angle = 2.5
	coax_mg.suppression = 30.0
	coax_mg.suppression_near_miss = 15.0
	coax_mg.suppression_radius = 3.0
	coax_mg.projectile_speed = 450.0
	coax_mg.tracer_ratio = 5
	coax_mg.magazine_size = 250
	coax_mg.ammo_type = "7.62mm_linked"
	coax_mg.sound_profile = "mg_762"
	coax_mg.accuracy_variance = 0.1  # Coax MG - stabilized on vehicle
	DEFINITIONS["coax_mg"] = coax_mg

	# ========================================
	# HELICOPTER WEAPONS
	# ========================================

	# === M134 Minigun (Door Gun) ===
	var minigun := WeaponDef.new()
	minigun.weapon_name = "M134 Minigun"
	minigun.category = WeaponCategory.HELICOPTER_MINIGUN
	minigun.fire_pattern = FirePattern.AUTO
	minigun.trajectory = Trajectory.FLAT
	minigun.damage_type = DamageType.KINETIC
	minigun.fear_type = GameEnums.FearType.MACHINE_GUN
	minigun.rate_of_fire = 4000.0  # 4000 RPM!
	minigun.reload_time = 5.0
	minigun.burst_count = 0
	minigun.damage = 12.0  # Lower per-round but volume of fire
	minigun.effective_range = 300.0
	minigun.max_range = 800.0
	minigun.base_accuracy = 0.50  # Spray weapon
	minigun.accuracy_falloff = 0.20
	minigun.scatter_angle = 8.0
	minigun.suppression = 80.0  # Devastating suppression
	minigun.suppression_near_miss = 50.0
	minigun.suppression_radius = 10.0
	minigun.projectile_speed = 400.0
	minigun.tracer_ratio = 5
	minigun.magazine_size = 2000
	minigun.ammo_type = "7.62mm_linked"
	minigun.sound_profile = "minigun"
	minigun.accuracy_variance = 0.08  # Minigun - helicopter-stabilized, precision fire support
	DEFINITIONS["m134_minigun"] = minigun

	# === 2.75" FFAR Rocket Pod ===
	var ffar := WeaponDef.new()
	ffar.weapon_name = "2.75\" FFAR"
	ffar.category = WeaponCategory.HELICOPTER_ROCKET
	ffar.fire_pattern = FirePattern.STAGGER  # Ripple fire
	ffar.trajectory = Trajectory.FLAT
	ffar.damage_type = DamageType.EXPLOSIVE
	ffar.fear_type = GameEnums.FearType.MORTAR
	ffar.rate_of_fire = 120.0
	ffar.reload_time = 0.0  # Can't reload in flight
	ffar.burst_count = 1
	ffar.damage = 150.0
	ffar.effective_range = 500.0
	ffar.max_range = 1500.0
	ffar.min_range = 100.0
	ffar.base_accuracy = 0.55
	ffar.accuracy_falloff = 0.30
	ffar.scatter_angle = 6.0
	ffar.suppression = 60.0
	ffar.suppression_near_miss = 40.0
	ffar.suppression_radius = 10.0
	ffar.aoe_radius = 8.0
	ffar.projectile_speed = 200.0
	ffar.magazine_size = 19  # Per pod
	ffar.ammo_type = "2.75_ffar"
	ffar.sound_profile = "rocket_heli"
	ffar.accuracy_variance = 0.15  # FFAR rockets - unguided but helicopter pilots are trained
	DEFINITIONS["ffar_rocket"] = ffar

	# ========================================
	# AIRCRAFT WEAPONS
	# ========================================

	# === 20mm Cannon (Aircraft) ===
	var cannon_20mm := WeaponDef.new()
	cannon_20mm.weapon_name = "20mm Cannon"
	cannon_20mm.category = WeaponCategory.AIRCRAFT_GUN
	cannon_20mm.fire_pattern = FirePattern.AUTO
	cannon_20mm.trajectory = Trajectory.DIVING
	cannon_20mm.damage_type = DamageType.KINETIC
	cannon_20mm.fear_type = GameEnums.FearType.MACHINE_GUN
	cannon_20mm.rate_of_fire = 1500.0
	cannon_20mm.reload_time = 0.0
	cannon_20mm.burst_count = 0
	cannon_20mm.damage = 35.0
	cannon_20mm.effective_range = 400.0
	cannon_20mm.max_range = 1000.0
	cannon_20mm.base_accuracy = 0.55
	cannon_20mm.accuracy_falloff = 0.25
	cannon_20mm.scatter_angle = 5.0
	cannon_20mm.suppression = 50.0
	cannon_20mm.suppression_near_miss = 30.0
	cannon_20mm.suppression_radius = 8.0
	cannon_20mm.projectile_speed = 500.0
	cannon_20mm.armor_penetration = 30.0
	cannon_20mm.anti_vehicle_bonus = 0.8
	cannon_20mm.tracer_ratio = 4
	cannon_20mm.magazine_size = 500
	cannon_20mm.ammo_type = "20mm"
	cannon_20mm.sound_profile = "cannon_aircraft"
	cannon_20mm.accuracy_variance = 0.05  # Aircraft cannon - very precise during strafing runs
	DEFINITIONS["cannon_20mm"] = cannon_20mm

	# === Napalm Canister ===
	var napalm := WeaponDef.new()
	napalm.weapon_name = "Napalm"
	napalm.category = WeaponCategory.AIRCRAFT_NAPALM
	napalm.fire_pattern = FirePattern.SINGLE
	napalm.trajectory = Trajectory.NAPALM
	napalm.damage_type = DamageType.FIRE
	napalm.fear_type = GameEnums.FearType.NAPALM  # Maximum terror
	napalm.rate_of_fire = 1.0
	napalm.reload_time = 0.0  # Single use
	napalm.burst_count = 1
	napalm.damage = 150.0
	napalm.effective_range = 100.0  # Drop zone
	napalm.max_range = 200.0
	napalm.base_accuracy = 0.80  # Area weapon
	napalm.scatter_angle = 10.0
	napalm.suppression = 100.0  # Extreme terror
	napalm.suppression_near_miss = 80.0  # Even near misses terrify
	napalm.suppression_radius = 30.0
	napalm.aoe_radius = 25.0  # Large area
	napalm.aoe_falloff = false  # Even damage in area
	napalm.projectile_speed = 80.0
	napalm.arc_height = -10.0  # Drops
	napalm.lifetime = 3.0
	napalm.magazine_size = 2  # Two canisters typical
	napalm.ammo_type = "napalm"
	napalm.sound_profile = "napalm_impact"
	napalm.accuracy_variance = 0.1  # Napalm - area weapon, spread is intentional
	DEFINITIONS["napalm"] = napalm

	# === Mark 82 GP Bomb ===
	var mk82 := WeaponDef.new()
	mk82.weapon_name = "Mk 82 Bomb"
	mk82.category = WeaponCategory.AIRCRAFT_BOMB
	mk82.fire_pattern = FirePattern.SINGLE
	mk82.trajectory = Trajectory.DIVING
	mk82.damage_type = DamageType.EXPLOSIVE
	mk82.rate_of_fire = 1.0
	mk82.reload_time = 0.0
	mk82.burst_count = 1
	mk82.damage = 400.0
	mk82.effective_range = 50.0
	mk82.max_range = 100.0
	mk82.base_accuracy = 0.70
	mk82.scatter_angle = 15.0
	mk82.suppression = 90.0
	mk82.suppression_radius = 25.0
	mk82.aoe_radius = 20.0
	mk82.aoe_falloff = true
	mk82.projectile_speed = 100.0
	mk82.arc_height = -20.0
	mk82.lifetime = 4.0
	mk82.magazine_size = 6  # Typical load
	mk82.ammo_type = "500lb_bomb"
	mk82.sound_profile = "bomb_impact"
	mk82.fear_type = GameEnums.FearType.ARTILLERY  # Large explosion
	mk82.suppression_near_miss = 45.0
	mk82.accuracy_variance = 0.18  # Gravity bomb - some variance but jet pilots are trained
	DEFINITIONS["mk82_bomb"] = mk82


## Get weapon definition by ID.
static func get_weapon(weapon_id: String) -> WeaponDef:
	if not _initialized:
		_init_definitions()
	return DEFINITIONS.get(weapon_id, null)


## Get all weapons in a category.
static func get_weapons_by_category(category: int) -> Array[WeaponDef]:
	if not _initialized:
		_init_definitions()

	var result: Array[WeaponDef] = []
	for weapon in DEFINITIONS.values():
		if weapon.category == category:
			result.append(weapon)
	return result


## Get all weapon IDs.
static func get_all_weapon_ids() -> Array[String]:
	if not _initialized:
		_init_definitions()

	var ids: Array[String] = []
	for key in DEFINITIONS.keys():
		ids.append(key)
	return ids


## Get projectile config dictionary for combat system.
static func get_projectile_config(weapon_id: String) -> Dictionary:
	var weapon := get_weapon(weapon_id)
	if not weapon:
		return {}

	return {
		"weapon_id": weapon_id,
		"weapon_name": weapon.weapon_name,
		"speed": weapon.projectile_speed,
		"arc_height": weapon.arc_height,
		"lifetime": weapon.lifetime,
		"damage": weapon.damage,
		"damage_type": weapon.damage_type,
		"aoe_radius": weapon.aoe_radius,
		"aoe_falloff": weapon.aoe_falloff,
		"max_pierces": weapon.max_pierces,
		"pierce_falloff": weapon.pierce_falloff,
		"trajectory": weapon.trajectory,
		"scatter_angle": weapon.scatter_angle,
		"suppression": weapon.suppression,
		"suppression_radius": weapon.suppression_radius,
		"armor_penetration": weapon.armor_penetration,
		"anti_vehicle_bonus": weapon.anti_vehicle_bonus,
		"tracer_ratio": weapon.tracer_ratio,
		"muzzle_flash": weapon.muzzle_flash,
		"sound_profile": weapon.sound_profile,
		"fear_type": weapon.fear_type,
		"suppression_near_miss": weapon.suppression_near_miss,
		"accuracy_variance": weapon.accuracy_variance,
	}


## Calculate effective accuracy at distance (deterministic, for display/planning).
static func calculate_accuracy(weapon_id: String, distance: float, is_moving: bool = false) -> float:
	var weapon := get_weapon(weapon_id)
	if not weapon:
		return 0.5

	var accuracy: float = weapon.base_accuracy

	# Range falloff
	if distance > weapon.effective_range and weapon.max_range > weapon.effective_range:
		var falloff_ratio: float = (distance - weapon.effective_range) / (weapon.max_range - weapon.effective_range)
		accuracy = lerpf(weapon.base_accuracy, weapon.accuracy_falloff, clampf(falloff_ratio, 0.0, 1.0))

	# Moving penalty
	if is_moving:
		accuracy *= weapon.moving_penalty

	return clampf(accuracy, 0.1, 0.95)


## Calculate accuracy with variance for actual combat resolution.
## This adds randomness based on weapon type:
## - Artillery/mortars/tanks: High variance (tension - you never know if shells will land true)
## - Helicopters/jets: Low variance (precision fire support)
## - Infantry weapons: Medium variance
static func calculate_accuracy_with_variance(weapon_id: String, distance: float, is_moving: bool = false) -> float:
	var base_accuracy: float = calculate_accuracy(weapon_id, distance, is_moving)
	var weapon := get_weapon(weapon_id)
	if not weapon:
		return base_accuracy

	# Apply variance: accuracy can swing ± (variance/2) around base
	var variance: float = weapon.accuracy_variance
	if variance <= 0.0:
		return base_accuracy

	# Random value between -variance/2 and +variance/2
	var random_offset: float = randf_range(-variance * 0.5, variance * 0.5)
	var final_accuracy: float = base_accuracy + random_offset

	return clampf(final_accuracy, 0.05, 0.95)


## Check if target is in range.
static func is_in_range(weapon_id: String, distance: float) -> bool:
	var weapon := get_weapon(weapon_id)
	if not weapon:
		return false
	return distance >= weapon.min_range and distance <= weapon.max_range


## Get damage category name for UI.
static func get_damage_type_name(damage_type: int) -> String:
	match damage_type:
		DamageType.KINETIC: return "Kinetic"
		DamageType.EXPLOSIVE: return "Explosive"
		DamageType.FIRE: return "Fire"
		DamageType.FRAGMENTATION: return "Fragmentation"
		DamageType.ARMOR_PIERCING: return "Armor-Piercing"
		_: return "Unknown"


## Get weapon category name for UI.
static func get_category_name(category: int) -> String:
	match category:
		WeaponCategory.RIFLE: return "Rifle"
		WeaponCategory.MACHINE_GUN: return "Machine Gun"
		WeaponCategory.SIDEARM: return "Sidearm"
		WeaponCategory.GRENADE_LAUNCHER: return "Grenade Launcher"
		WeaponCategory.ROCKET_LAUNCHER: return "Rocket Launcher"
		WeaponCategory.MORTAR: return "Mortar"
		WeaponCategory.ARTILLERY: return "Artillery"
		WeaponCategory.TANK_MAIN_GUN: return "Tank Gun"
		WeaponCategory.VEHICLE_MG: return "Vehicle MG"
		WeaponCategory.HELICOPTER_MINIGUN: return "Minigun"
		WeaponCategory.HELICOPTER_ROCKET: return "Rocket Pod"
		WeaponCategory.AIRCRAFT_GUN: return "Aircraft Cannon"
		WeaponCategory.AIRCRAFT_BOMB: return "Bomb"
		WeaponCategory.AIRCRAFT_NAPALM: return "Napalm"
		_: return "Unknown"
