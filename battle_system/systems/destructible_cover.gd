class_name DestructibleCover extends Node3D
## DestructibleCover - Cover objects that degrade under sustained fire
##
## Attach this to any Node3D that provides cover (sandbags, walls, trees, etc.)
## Cover quality degrades as it takes damage:
##   FORTIFIED (100%) -> HEAVY (70%) -> LIGHT (40%) -> NONE (destroyed)
##
## LESSONS FROM MEN OF WAR / COH:
## - Sustained fire eventually destroys cover
## - MG fire is particularly effective at destroying soft cover
## - Explosives destroy cover instantly
## - Units should seek new cover when current cover degrades
##
## USAGE:
##   var cover = DestructibleCover.new()
##   cover.initial_cover_type = GameEnums.CoverType.HEAVY
##   cover.max_health = 100.0
##   sandbag_wall.add_child(cover)

signal cover_degraded(old_type: int, new_type: int)
signal cover_destroyed
signal cover_damaged(amount: float, new_health: float)

## Configuration
@export var initial_cover_type: int = 2  # GameEnums.CoverType.HEAVY
@export var max_health: float = 100.0
@export var mg_damage_multiplier: float = 2.0  # MGs destroy soft cover faster
@export var explosive_damage_multiplier: float = 5.0  # Explosives very effective
@export var regenerates: bool = false  # Trees regrow, sandbags don't
@export var regen_rate: float = 1.0  # Health per second if regenerates

## State
var current_cover_type: int = 2  # GameEnums.CoverType.HEAVY
var current_health: float = 100.0
var is_destroyed: bool = false

## Damage type to cover material effectiveness
## Different cover materials resist different damage types differently
enum CoverMaterial {
	SANDBAGS,    # Soft, easy to destroy with MGs
	WOOD,        # Burns, weak to explosives
	STONE,       # Hard, resists bullets well
	CONCRETE,    # Very hard, resists most damage
	VEGETATION,  # Soft, but can regenerate
}

@export var material: CoverMaterial = CoverMaterial.SANDBAGS

## Material damage resistance (multiplier on incoming damage)
const MATERIAL_RESISTANCE: Dictionary = {
	CoverMaterial.SANDBAGS: {"bullet": 1.0, "mg": 1.5, "explosive": 3.0, "fire": 0.5},
	CoverMaterial.WOOD: {"bullet": 0.8, "mg": 1.2, "explosive": 4.0, "fire": 3.0},
	CoverMaterial.STONE: {"bullet": 0.3, "mg": 0.5, "explosive": 2.0, "fire": 0.1},
	CoverMaterial.CONCRETE: {"bullet": 0.1, "mg": 0.2, "explosive": 1.0, "fire": 0.0},
	CoverMaterial.VEGETATION: {"bullet": 0.6, "mg": 1.0, "explosive": 2.0, "fire": 5.0},
}

## Health thresholds for cover degradation
const DEGRADATION_THRESHOLDS: Dictionary = {
	# Cover type: {threshold, next_type}
	3: {"threshold": 0.7, "next": 2},  # FORTIFIED -> HEAVY at 70%
	2: {"threshold": 0.4, "next": 1},  # HEAVY -> LIGHT at 40%
	1: {"threshold": 0.0, "next": 0},  # LIGHT -> NONE at 0%
}


func _ready() -> void:
	current_cover_type = initial_cover_type
	current_health = max_health

	# Add to appropriate cover group based on initial type
	_update_cover_group()

	add_to_group("destructible_cover")


func _process(delta: float) -> void:
	if regenerates and not is_destroyed and current_health < max_health:
		_regenerate(delta)


## Take damage from weapons fire
func take_damage(amount: float, damage_type: String = "bullet") -> void:
	if is_destroyed:
		return

	# Apply material resistance
	var resistance: Dictionary = MATERIAL_RESISTANCE.get(material, {})
	var multiplier: float = resistance.get(damage_type, 1.0)
	var final_damage: float = amount * multiplier

	current_health = maxf(0.0, current_health - final_damage)
	cover_damaged.emit(final_damage, current_health)

	# Check for degradation
	_check_degradation()


## Take explosive damage (grenades, artillery, etc.)
func take_explosive_damage(amount: float) -> void:
	take_damage(amount * explosive_damage_multiplier, "explosive")


## Take fire damage (napalm, molotov)
func take_fire_damage(amount: float) -> void:
	take_damage(amount, "fire")


func _check_degradation() -> void:
	"""Check if cover should degrade based on current health"""
	var health_percent: float = current_health / max_health

	# Check thresholds for current cover type
	if current_cover_type in DEGRADATION_THRESHOLDS:
		var threshold_data: Dictionary = DEGRADATION_THRESHOLDS[current_cover_type]
		if health_percent <= threshold_data.threshold:
			_degrade_to(threshold_data.next)

	# Check for destruction
	if current_health <= 0.0:
		_on_destroyed()


func _degrade_to(new_type: int) -> void:
	"""Degrade cover to a lower type"""
	var old_type: int = current_cover_type
	current_cover_type = new_type

	# Update group membership
	_update_cover_group()

	cover_degraded.emit(old_type, new_type)
	print("[DestructibleCover] Degraded from %s to %s" % [
		_cover_type_name(old_type),
		_cover_type_name(new_type)
	])


func _on_destroyed() -> void:
	"""Handle cover destruction"""
	is_destroyed = true
	current_cover_type = 0  # GameEnums.CoverType.NONE

	# Remove from cover groups
	for group_name in ["cover_fortified", "cover_heavy", "cover_light"]:
		if is_in_group(group_name):
			remove_from_group(group_name)

	add_to_group("cover_destroyed")

	cover_destroyed.emit()
	print("[DestructibleCover] Destroyed")

	# Optionally hide/destroy the visual
	var parent: Node3D = get_parent()
	if parent and not regenerates:
		# Create rubble effect or hide
		parent.visible = false


func _regenerate(delta: float) -> void:
	"""Regenerate health over time (for vegetation)"""
	current_health = minf(current_health + regen_rate * delta, max_health)

	# Check if we should upgrade cover type
	var health_percent: float = current_health / max_health

	if current_cover_type == 0 and health_percent > 0.1:
		is_destroyed = false
		_upgrade_to(1)  # LIGHT
	elif current_cover_type == 1 and health_percent > 0.4:
		_upgrade_to(2)  # HEAVY
	elif current_cover_type == 2 and health_percent > 0.7:
		_upgrade_to(initial_cover_type)


func _upgrade_to(new_type: int) -> void:
	"""Upgrade cover to a higher type (regeneration)"""
	var old_type: int = current_cover_type
	current_cover_type = new_type
	_update_cover_group()
	cover_degraded.emit(old_type, new_type)


func _update_cover_group() -> void:
	"""Update group membership based on current cover type"""
	# Remove from all cover groups first
	for group_name in ["cover_fortified", "cover_heavy", "cover_light"]:
		if is_in_group(group_name):
			remove_from_group(group_name)

	# Add to appropriate group
	match current_cover_type:
		3:  # FORTIFIED
			add_to_group("cover_fortified")
		2:  # HEAVY
			add_to_group("cover_heavy")
		1:  # LIGHT
			add_to_group("cover_light")


func _cover_type_name(cover_type: int) -> String:
	match cover_type:
		0:
			return "NONE"
		1:
			return "LIGHT"
		2:
			return "HEAVY"
		3:
			return "FORTIFIED"
	return "UNKNOWN"


## Get current cover type for CoverSystem queries
func get_cover_type() -> int:
	return current_cover_type


## Get health percentage
func get_health_percent() -> float:
	return current_health / max_health


## Repair cover (engineers, etc.)
func repair(amount: float) -> void:
	if is_destroyed and not regenerates:
		return  # Can't repair destroyed non-regenerating cover

	current_health = minf(current_health + amount, max_health)

	# Check for upgrades
	var health_percent: float = current_health / max_health
	if current_cover_type < initial_cover_type:
		if health_percent > 0.7 and current_cover_type < 3:
			_upgrade_to(mini(current_cover_type + 1, initial_cover_type))
