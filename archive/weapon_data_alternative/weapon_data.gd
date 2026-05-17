extends Resource
class_name WeaponData
## WeaponData - Combat statistics for all weapons in Vietnam Firebase Defense

@export_group("Identification")
@export var weapon_name: String = "M16"
@export var weapon_class: int = GameEnums.WeaponClass.M16
@export var weapon_icon: Texture2D

@export_group("Damage")
@export var base_damage: float = 15.0
@export var damage_type: GameEnums.DamageType = GameEnums.DamageType.SMALL_ARMS
@export var armor_penetration: float = 0.0  # mm of steel equivalent
@export var splash_radius: float = 0.0      # Area damage radius
@export var splash_falloff: float = 0.5     # Damage at edge of splash

@export_group("Range")
@export var effective_range: float = 300.0  # Optimal accuracy range (meters)
@export var max_range: float = 500.0        # Maximum engagement range
@export var min_range: float = 0.0          # Minimum safe range (explosives)

@export_group("Rate of Fire")
@export var rounds_per_minute: float = 700.0
@export var burst_size: int = 3             # Rounds per burst (auto weapons)
@export var reload_time: float = 3.0        # Seconds

@export_group("Accuracy")
@export var base_accuracy: float = 0.7      # Hit chance at effective range
@export var accuracy_falloff: float = 0.02  # Accuracy loss per 10m beyond effective
@export var accuracy_moving: float = 0.5    # Multiplier when moving
@export var accuracy_suppressed: float = 0.3 # Multiplier when suppressed

@export_group("Suppression")
@export var suppression_value: float = 5.0  # Suppression per hit
@export var suppression_radius: float = 5.0 # Suppression AoE (for explosives)

@export_group("Ammunition")
@export var magazine_size: int = 30
@export var ammo_per_shot: int = 1
@export var ammo_weight: float = 1.0        # Supply cost multiplier

@export_group("Audio/Visual")
@export var fire_sound: AudioStream
@export var muzzle_flash: bool = true
@export var tracer_frequency: int = 5       # Every N rounds is a tracer

# DamageType enum moved to GameEnums

# =============================================================================
# STATIC WEAPON DEFINITIONS
# =============================================================================

static var _weapons_cache: Dictionary = {}

static func get_weapon(weapon_class: int) -> WeaponData:
	if _weapons_cache.is_empty():
		_initialize_weapons()
	return _weapons_cache.get(weapon_class, _weapons_cache.get(GameEnums.WeaponClass.M16))


static func _initialize_weapons() -> void:
	# US Infantry Weapons
	_weapons_cache[GameEnums.WeaponClass.M16] = _create_m16()
	_weapons_cache[GameEnums.WeaponClass.M60] = _create_m60()
	_weapons_cache[GameEnums.WeaponClass.M79] = _create_m79()
	_weapons_cache[GameEnums.WeaponClass.M14] = _create_m14()
	_weapons_cache[GameEnums.WeaponClass.M1911] = _create_m1911()
	_weapons_cache[GameEnums.WeaponClass.M72_LAW] = _create_m72_law()
	_weapons_cache[GameEnums.WeaponClass.M2_BROWNING] = _create_m2_browning()
	_weapons_cache[GameEnums.WeaponClass.M102_HOWITZER] = _create_m102_howitzer()

	# Air Support
	_weapons_cache[GameEnums.WeaponClass.NAPALM] = _create_napalm()
	_weapons_cache[GameEnums.WeaponClass.HE_BOMBS] = _create_he_bombs()
	_weapons_cache[GameEnums.WeaponClass.CLUSTER_BOMBS] = _create_cluster_bombs()
	_weapons_cache[GameEnums.WeaponClass.ROCKET_POD] = _create_rocket_pod()
	_weapons_cache[GameEnums.WeaponClass.MINIGUN] = _create_minigun()

	# VC/NVA Weapons
	_weapons_cache[GameEnums.WeaponClass.AK47] = _create_ak47()
	_weapons_cache[GameEnums.WeaponClass.SKS] = _create_sks()
	_weapons_cache[GameEnums.WeaponClass.RPD] = _create_rpd()
	_weapons_cache[GameEnums.WeaponClass.RPG7] = _create_rpg7()
	_weapons_cache[GameEnums.WeaponClass.DSHK] = _create_dshk()
	_weapons_cache[GameEnums.WeaponClass.MORTAR_82MM] = _create_mortar_82mm()
	_weapons_cache[GameEnums.WeaponClass.MORTAR_120MM] = _create_mortar_120mm()
	_weapons_cache[GameEnums.WeaponClass.B40_ROCKET] = _create_b40_rocket()


# =============================================================================
# US INFANTRY WEAPONS
# =============================================================================

static func _create_m16() -> WeaponData:
	var w := new()
	w.weapon_name = "M16A1"
	w.weapon_class = GameEnums.WeaponClass.M16
	w.base_damage = 15.0
	w.damage_type = GameEnums.DamageType.SMALL_ARMS
	w.effective_range = 300.0
	w.max_range = 500.0
	w.rounds_per_minute = 700.0
	w.burst_size = 3
	w.base_accuracy = 0.75
	w.suppression_value = 5.0
	w.magazine_size = 20
	return w


static func _create_m60() -> WeaponData:
	var w := new()
	w.weapon_name = "M60 Machine Gun"
	w.weapon_class = GameEnums.WeaponClass.M60
	w.base_damage = 25.0
	w.damage_type = GameEnums.DamageType.SMALL_ARMS
	w.effective_range = 500.0
	w.max_range = 1100.0
	w.rounds_per_minute = 550.0
	w.burst_size = 6
	w.base_accuracy = 0.6
	w.suppression_value = 30.0
	w.suppression_radius = 10.0
	w.magazine_size = 100
	w.ammo_weight = 3.0
	return w


static func _create_m79() -> WeaponData:
	var w := new()
	w.weapon_name = "M79 Grenade Launcher"
	w.weapon_class = GameEnums.WeaponClass.M79
	w.base_damage = 80.0
	w.damage_type = GameEnums.DamageType.EXPLOSIVE
	w.splash_radius = 5.0
	w.splash_falloff = 0.5
	w.effective_range = 150.0
	w.max_range = 350.0
	w.min_range = 20.0  # Arm distance
	w.rounds_per_minute = 6.0
	w.burst_size = 1
	w.base_accuracy = 0.65
	w.suppression_value = 40.0
	w.suppression_radius = 8.0
	w.magazine_size = 1
	w.reload_time = 5.0
	return w


static func _create_m14() -> WeaponData:
	var w := new()
	w.weapon_name = "M14"
	w.weapon_class = GameEnums.WeaponClass.M14
	w.base_damage = 22.0
	w.damage_type = GameEnums.DamageType.SMALL_ARMS
	w.effective_range = 400.0
	w.max_range = 800.0
	w.rounds_per_minute = 120.0  # Semi-auto aimed fire
	w.burst_size = 1
	w.base_accuracy = 0.85
	w.suppression_value = 8.0
	w.magazine_size = 20
	return w


static func _create_m1911() -> WeaponData:
	var w := new()
	w.weapon_name = "M1911A1"
	w.weapon_class = GameEnums.WeaponClass.M1911
	w.base_damage = 18.0
	w.damage_type = GameEnums.DamageType.SMALL_ARMS
	w.effective_range = 25.0
	w.max_range = 50.0
	w.rounds_per_minute = 100.0
	w.burst_size = 1
	w.base_accuracy = 0.6
	w.suppression_value = 3.0
	w.magazine_size = 7
	return w


static func _create_m72_law() -> WeaponData:
	var w := new()
	w.weapon_name = "M72 LAW"
	w.weapon_class = GameEnums.WeaponClass.M72_LAW
	w.base_damage = 200.0
	w.damage_type = GameEnums.DamageType.SHAPED_CHARGE
	w.armor_penetration = 300.0  # mm RHA
	w.splash_radius = 3.0
	w.effective_range = 150.0
	w.max_range = 200.0
	w.min_range = 10.0
	w.rounds_per_minute = 1.0  # Single shot
	w.burst_size = 1
	w.base_accuracy = 0.5
	w.suppression_value = 50.0
	w.magazine_size = 1
	return w


static func _create_m2_browning() -> WeaponData:
	var w := new()
	w.weapon_name = "M2 Browning .50 Cal"
	w.weapon_class = GameEnums.WeaponClass.M2_BROWNING
	w.base_damage = 45.0
	w.damage_type = GameEnums.DamageType.HEAVY_MG
	w.armor_penetration = 25.0
	w.effective_range = 800.0
	w.max_range = 1800.0
	w.rounds_per_minute = 500.0
	w.burst_size = 8
	w.base_accuracy = 0.55
	w.suppression_value = 50.0
	w.suppression_radius = 15.0
	w.magazine_size = 100
	w.ammo_weight = 5.0
	return w


static func _create_m102_howitzer() -> WeaponData:
	var w := new()
	w.weapon_name = "M102 105mm Howitzer"
	w.weapon_class = GameEnums.WeaponClass.M102_HOWITZER
	w.base_damage = 500.0
	w.damage_type = GameEnums.DamageType.ARTILLERY
	w.splash_radius = 25.0
	w.splash_falloff = 0.3
	w.effective_range = 11500.0
	w.max_range = 11500.0
	w.min_range = 500.0
	w.rounds_per_minute = 3.0
	w.burst_size = 1
	w.base_accuracy = 0.4  # Requires spotting
	w.suppression_value = 100.0
	w.suppression_radius = 40.0
	w.magazine_size = 999  # Limited by supply
	w.reload_time = 10.0
	w.ammo_weight = 20.0
	return w


# =============================================================================
# AIR SUPPORT WEAPONS
# =============================================================================

static func _create_napalm() -> WeaponData:
	var w := new()
	w.weapon_name = "Napalm Canister"
	w.weapon_class = GameEnums.WeaponClass.NAPALM
	w.base_damage = 150.0
	w.damage_type = GameEnums.DamageType.NAPALM
	w.splash_radius = 30.0
	w.splash_falloff = 0.2  # Consistent burn
	w.effective_range = 0.0  # Dropped
	w.rounds_per_minute = 1.0
	w.suppression_value = 100.0
	w.suppression_radius = 50.0
	return w


static func _create_he_bombs() -> WeaponData:
	var w := new()
	w.weapon_name = "Mk 82 500lb Bomb"
	w.weapon_class = GameEnums.WeaponClass.HE_BOMBS
	w.base_damage = 400.0
	w.damage_type = GameEnums.DamageType.EXPLOSIVE
	w.splash_radius = 35.0
	w.splash_falloff = 0.4
	w.suppression_value = 100.0
	w.suppression_radius = 60.0
	return w


static func _create_cluster_bombs() -> WeaponData:
	var w := new()
	w.weapon_name = "CBU-24 Cluster Bomb"
	w.weapon_class = GameEnums.WeaponClass.CLUSTER_BOMBS
	w.base_damage = 100.0
	w.damage_type = GameEnums.DamageType.FRAGMENTATION
	w.splash_radius = 50.0
	w.splash_falloff = 0.6
	w.suppression_value = 80.0
	w.suppression_radius = 70.0
	return w


static func _create_rocket_pod() -> WeaponData:
	var w := new()
	w.weapon_name = "2.75\" FFAR Rocket"
	w.weapon_class = GameEnums.WeaponClass.ROCKET_POD
	w.base_damage = 100.0
	w.damage_type = GameEnums.DamageType.EXPLOSIVE
	w.splash_radius = 8.0
	w.effective_range = 1500.0
	w.max_range = 3000.0
	w.rounds_per_minute = 60.0
	w.base_accuracy = 0.4
	w.suppression_value = 40.0
	w.suppression_radius = 15.0
	w.magazine_size = 19
	return w


static func _create_minigun() -> WeaponData:
	var w := new()
	w.weapon_name = "M134 Minigun"
	w.weapon_class = GameEnums.WeaponClass.MINIGUN
	w.base_damage = 15.0
	w.damage_type = GameEnums.DamageType.SMALL_ARMS
	w.effective_range = 500.0
	w.max_range = 1000.0
	w.rounds_per_minute = 4000.0
	w.burst_size = 50
	w.base_accuracy = 0.3
	w.suppression_value = 60.0
	w.suppression_radius = 20.0
	w.magazine_size = 4000
	w.ammo_weight = 10.0
	return w


# =============================================================================
# VC/NVA WEAPONS
# =============================================================================

static func _create_ak47() -> WeaponData:
	var w := new()
	w.weapon_name = "AK-47"
	w.weapon_class = GameEnums.WeaponClass.AK47
	w.base_damage = 18.0
	w.damage_type = GameEnums.DamageType.SMALL_ARMS
	w.effective_range = 300.0
	w.max_range = 400.0
	w.rounds_per_minute = 600.0
	w.burst_size = 4
	w.base_accuracy = 0.65
	w.suppression_value = 6.0
	w.magazine_size = 30
	return w


static func _create_sks() -> WeaponData:
	var w := new()
	w.weapon_name = "SKS"
	w.weapon_class = GameEnums.WeaponClass.SKS
	w.base_damage = 20.0
	w.damage_type = GameEnums.DamageType.SMALL_ARMS
	w.effective_range = 400.0
	w.max_range = 600.0
	w.rounds_per_minute = 90.0
	w.burst_size = 1
	w.base_accuracy = 0.75
	w.suppression_value = 5.0
	w.magazine_size = 10
	return w


static func _create_rpd() -> WeaponData:
	var w := new()
	w.weapon_name = "RPD Light MG"
	w.weapon_class = GameEnums.WeaponClass.RPD
	w.base_damage = 20.0
	w.damage_type = GameEnums.DamageType.SMALL_ARMS
	w.effective_range = 400.0
	w.max_range = 800.0
	w.rounds_per_minute = 700.0
	w.burst_size = 5
	w.base_accuracy = 0.5
	w.suppression_value = 25.0
	w.suppression_radius = 8.0
	w.magazine_size = 100
	w.ammo_weight = 2.5
	return w


static func _create_rpg7() -> WeaponData:
	var w := new()
	w.weapon_name = "RPG-7"
	w.weapon_class = GameEnums.WeaponClass.RPG7
	w.base_damage = 250.0
	w.damage_type = GameEnums.DamageType.SHAPED_CHARGE
	w.armor_penetration = 350.0
	w.splash_radius = 4.0
	w.effective_range = 100.0
	w.max_range = 150.0
	w.min_range = 5.0
	w.rounds_per_minute = 4.0
	w.burst_size = 1
	w.base_accuracy = 0.45
	w.suppression_value = 60.0
	w.magazine_size = 1
	w.reload_time = 8.0
	return w


static func _create_dshk() -> WeaponData:
	var w := new()
	w.weapon_name = "DShK 12.7mm"
	w.weapon_class = GameEnums.WeaponClass.DSHK
	w.base_damage = 40.0
	w.damage_type = GameEnums.DamageType.HEAVY_MG
	w.armor_penetration = 20.0
	w.effective_range = 800.0
	w.max_range = 1500.0
	w.rounds_per_minute = 600.0
	w.burst_size = 6
	w.base_accuracy = 0.5
	w.suppression_value = 45.0
	w.suppression_radius = 12.0
	w.magazine_size = 50
	w.ammo_weight = 4.0
	return w


static func _create_mortar_82mm() -> WeaponData:
	var w := new()
	w.weapon_name = "82mm Mortar"
	w.weapon_class = GameEnums.WeaponClass.MORTAR_82MM
	w.base_damage = 120.0
	w.damage_type = GameEnums.DamageType.EXPLOSIVE
	w.splash_radius = 15.0
	w.splash_falloff = 0.4
	w.effective_range = 3000.0
	w.max_range = 3100.0
	w.min_range = 200.0
	w.rounds_per_minute = 15.0
	w.burst_size = 1
	w.base_accuracy = 0.35
	w.suppression_value = 50.0
	w.suppression_radius = 25.0
	w.magazine_size = 999
	w.reload_time = 4.0
	w.ammo_weight = 5.0
	return w


static func _create_mortar_120mm() -> WeaponData:
	var w := new()
	w.weapon_name = "120mm Heavy Mortar"
	w.weapon_class = GameEnums.WeaponClass.MORTAR_120MM
	w.base_damage = 250.0
	w.damage_type = GameEnums.DamageType.EXPLOSIVE
	w.splash_radius = 25.0
	w.splash_falloff = 0.35
	w.effective_range = 5500.0
	w.max_range = 5700.0
	w.min_range = 300.0
	w.rounds_per_minute = 8.0
	w.burst_size = 1
	w.base_accuracy = 0.3
	w.suppression_value = 80.0
	w.suppression_radius = 35.0
	w.magazine_size = 999
	w.reload_time = 7.0
	w.ammo_weight = 10.0
	return w


static func _create_b40_rocket() -> WeaponData:
	var w := new()
	w.weapon_name = "B-40 Rocket"
	w.weapon_class = GameEnums.WeaponClass.B40_ROCKET
	w.base_damage = 180.0
	w.damage_type = GameEnums.DamageType.SHAPED_CHARGE
	w.armor_penetration = 250.0
	w.splash_radius = 3.0
	w.effective_range = 80.0
	w.max_range = 100.0
	w.rounds_per_minute = 3.0
	w.burst_size = 1
	w.base_accuracy = 0.4
	w.suppression_value = 50.0
	w.magazine_size = 1
	w.reload_time = 10.0
	return w


# =============================================================================
# UTILITY METHODS
# =============================================================================

func get_damage_at_range(distance: float) -> float:
	if distance <= effective_range:
		return base_damage
	elif distance <= max_range:
		var falloff := (distance - effective_range) / (max_range - effective_range)
		return base_damage * (1.0 - falloff * 0.5)
	return 0.0


func get_accuracy_at_range(distance: float, is_moving: bool, suppression: float) -> float:
	var acc := base_accuracy

	# Range falloff
	if distance > effective_range:
		var range_penalty := (distance - effective_range) / 10.0 * accuracy_falloff
		acc -= range_penalty

	# Moving penalty
	if is_moving:
		acc *= accuracy_moving

	# Suppression penalty
	if suppression > 0:
		var suppression_factor := 1.0 - (suppression / 100.0 * (1.0 - accuracy_suppressed))
		acc *= suppression_factor

	return clampf(acc, 0.05, 0.95)


func get_suppression_at_distance(distance: float) -> float:
	if suppression_radius <= 0:
		return 0.0 if distance > 2.0 else suppression_value

	if distance <= suppression_radius:
		var factor := 1.0 - (distance / suppression_radius)
		return suppression_value * factor
	return 0.0


func is_area_effect() -> bool:
	return splash_radius > 0


func is_anti_armor() -> bool:
	return armor_penetration > 0 or damage_type == GameEnums.DamageType.SHAPED_CHARGE
