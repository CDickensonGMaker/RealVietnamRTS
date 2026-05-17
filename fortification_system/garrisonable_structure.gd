class_name GarrisonableStructure extends Node3D
## GarrisonableStructure - CoH-style garrison system for buildings
##
## Attach this to any building (bunker, house, colonial villa) to enable:
## - Infantry entering/exiting for cover
## - Damage reduction while garrisoned
## - Suppression immunity while inside
## - Firing positions (windows) with LOS checks
##
## USAGE:
##   var garrison_comp = GarrisonableStructure.new()
##   garrison_comp.max_infantry = 8
##   garrison_comp.damage_reduction = 0.7
##   building.add_child(garrison_comp)
##
## LESSONS FROM COH:
## - Garrisoned units are immune to suppression
## - Buildings provide structural cover (best cover type)
## - Squads fire from windows/firing positions
## - Buildings can be destroyed, killing garrison

signal infantry_entered(unit: Node3D)
signal infantry_exited(unit: Node3D)
signal structure_destroyed
signal garrison_killed(killed_count: int)

# Structure types affect cover quality
enum StructureType {
	BUNKER,          # Military hardened - best protection
	STONE_BUILDING,  # Colonial villa, government - good protection
	BRICK_BUILDING,  # Standard house - moderate protection
	WOOD_BUILDING,   # Vietnamese hut, shed - light protection
	SANDBAGS,        # Field fortification - light protection
}

## Configuration
@export var structure_type: StructureType = StructureType.BRICK_BUILDING
@export var max_infantry: int = 8  # Individual soldiers, not squads
@export var damage_reduction: float = 0.6  # 60% damage reduction
@export var suppression_immunity: bool = true  # Garrisoned units immune to suppression
@export var provides_los_blocking: bool = true  # Building blocks enemy LOS through it

## Firing positions (relative to building center)
## Each position is a window/opening infantry can fire from
@export var firing_positions: Array[Vector3] = []
@export var firing_arc_per_position: float = 90.0  # Degrees of arc per window

## State
var garrisoned_units: Array[Node3D] = []
var current_health: float = 100.0
var max_health: float = 100.0
var is_destroyed: bool = false

## Structure type -> damage reduction mapping
const STRUCTURE_DAMAGE_REDUCTION: Dictionary = {
	StructureType.BUNKER: 0.75,
	StructureType.STONE_BUILDING: 0.65,
	StructureType.BRICK_BUILDING: 0.55,
	StructureType.WOOD_BUILDING: 0.35,
	StructureType.SANDBAGS: 0.45,
}

## Structure type -> max health mapping
const STRUCTURE_MAX_HEALTH: Dictionary = {
	StructureType.BUNKER: 1000.0,
	StructureType.STONE_BUILDING: 600.0,
	StructureType.BRICK_BUILDING: 400.0,
	StructureType.WOOD_BUILDING: 200.0,
	StructureType.SANDBAGS: 150.0,
}


func _ready() -> void:
	# Apply structure type defaults if not overridden
	if damage_reduction == 0.6:  # Default value
		damage_reduction = STRUCTURE_DAMAGE_REDUCTION.get(structure_type, 0.5)

	max_health = STRUCTURE_MAX_HEALTH.get(structure_type, 400.0)
	current_health = max_health

	# Generate default firing positions if none specified
	if firing_positions.is_empty():
		_generate_default_firing_positions()

	add_to_group("garrisonable_structures")


func _generate_default_firing_positions() -> void:
	"""Generate firing positions around the building perimeter"""
	var num_positions: int = mini(max_infantry, 8)
	var radius: float = 2.0  # Assume ~2m from center to wall

	for i in num_positions:
		var angle: float = TAU * float(i) / float(num_positions)
		var pos := Vector3(
			cos(angle) * radius,
			1.5,  # Window height
			sin(angle) * radius
		)
		firing_positions.append(pos)


# =============================================================================
# GARRISON MANAGEMENT
# =============================================================================

## Check if unit can enter this structure
func can_enter(unit: Node3D) -> bool:
	if is_destroyed:
		return false
	if garrisoned_units.size() >= max_infantry:
		return false
	if unit in garrisoned_units:
		return false
	# Unit must be within 5m of structure
	var parent_pos: Vector3 = get_parent().global_position if get_parent() else global_position
	if parent_pos.distance_to(unit.global_position) > 5.0:
		return false
	return true


## Enter the structure. Returns true on success.
func enter(unit: Node3D) -> bool:
	if not can_enter(unit):
		return false

	garrisoned_units.append(unit)

	# Hide unit visual (they're inside the building)
	unit.visible = false

	# Mark unit as garrisoned
	if unit.has_method("set_garrisoned"):
		unit.set_garrisoned(true, self)
	elif unit.has_method("set"):
		unit.set("is_garrisoned", true)
		unit.set("garrison_structure", self)

	# Apply suppression immunity
	if suppression_immunity and unit.has_method("set"):
		unit.set("suppression", 0.0)
		unit.set("is_suppression_immune", true)

	# Assign firing position
	_assign_firing_position(unit)

	infantry_entered.emit(unit)
	return true


## Exit the structure
func exit(unit: Node3D, exit_position: Vector3 = Vector3.INF) -> bool:
	if unit not in garrisoned_units:
		return false

	garrisoned_units.erase(unit)

	# Calculate exit position if not specified
	if exit_position == Vector3.INF:
		var parent_pos: Vector3 = get_parent().global_position if get_parent() else global_position
		# Exit at a random point around the building
		var angle: float = randf() * TAU
		exit_position = parent_pos + Vector3(cos(angle) * 3.0, 0, sin(angle) * 3.0)

	# Restore unit visibility
	unit.visible = true
	unit.global_position = exit_position

	# Clear garrisoned state
	if unit.has_method("set_garrisoned"):
		unit.set_garrisoned(false, null)
	elif unit.has_method("set"):
		unit.set("is_garrisoned", false)
		unit.set("garrison_structure", null)

	# Remove suppression immunity
	if unit.has_method("set"):
		unit.set("is_suppression_immune", false)

	infantry_exited.emit(unit)
	return true


## Exit all units
func exit_all() -> Array[Node3D]:
	var exited: Array[Node3D] = []
	for unit in garrisoned_units.duplicate():
		if exit(unit):
			exited.append(unit)
	return exited


func _assign_firing_position(unit: Node3D) -> void:
	"""Assign a firing position to the unit"""
	var unit_index: int = garrisoned_units.find(unit)
	if unit_index < 0 or firing_positions.is_empty():
		return

	var pos_index: int = unit_index % firing_positions.size()
	if unit.has_method("set"):
		unit.set("firing_position", firing_positions[pos_index])


# =============================================================================
# COMBAT
# =============================================================================

## Take damage to the structure
func take_structure_damage(amount: float) -> void:
	if is_destroyed:
		return

	current_health = maxf(0.0, current_health - amount)

	# Garrison takes reduced damage based on structural integrity
	var structural_ratio: float = current_health / max_health
	var garrison_damage: float = amount * (1.0 - damage_reduction) * (1.0 - structural_ratio * 0.5)

	# Distribute damage to garrison
	if garrisoned_units.size() > 0:
		var damage_per_unit: float = garrison_damage / float(garrisoned_units.size())
		for unit in garrisoned_units:
			if is_instance_valid(unit) and unit.has_method("take_damage"):
				unit.take_damage(damage_per_unit)

	# Check for destruction
	if current_health <= 0.0:
		_on_destroyed()


func _on_destroyed() -> void:
	"""Handle structure destruction"""
	is_destroyed = true

	# Kill all garrisoned units
	var killed_count: int = 0
	for unit in garrisoned_units:
		if is_instance_valid(unit):
			# Force exit first (makes them visible for death animation)
			exit(unit)
			if unit.has_method("take_damage"):
				unit.take_damage(99999.0)
			killed_count += 1

	garrisoned_units.clear()

	garrison_killed.emit(killed_count)
	structure_destroyed.emit()


## Get the number of available slots
func get_available_slots() -> int:
	return max_infantry - garrisoned_units.size()


## Get garrison effectiveness (0.0 to 1.0)
func get_garrison_effectiveness() -> float:
	if max_infantry <= 0:
		return 0.0
	return float(garrisoned_units.size()) / float(max_infantry)


## Check if a position is visible from any firing position
func can_fire_at(target_pos: Vector3) -> bool:
	if garrisoned_units.is_empty():
		return false

	var parent_pos: Vector3 = get_parent().global_position if get_parent() else global_position

	for firing_pos in firing_positions:
		var world_pos: Vector3 = parent_pos + firing_pos
		var to_target: Vector3 = target_pos - world_pos
		to_target.y = 0

		# Check if within firing arc
		var angle_to_target: float = atan2(to_target.x, to_target.z)
		var firing_direction: float = atan2(firing_pos.x, firing_pos.z)
		var angle_diff: float = abs(angle_difference(firing_direction, angle_to_target))

		if rad_to_deg(angle_diff) <= firing_arc_per_position * 0.5:
			return true

	return false


## Get cover value for combat calculations
func get_cover_value() -> float:
	match structure_type:
		StructureType.BUNKER:
			return 0.9  # Near-full cover
		StructureType.STONE_BUILDING:
			return 0.8
		StructureType.BRICK_BUILDING:
			return 0.7
		StructureType.WOOD_BUILDING:
			return 0.5
		StructureType.SANDBAGS:
			return 0.6
	return 0.5


## Get the structure's current health percentage
func get_health_percent() -> float:
	return current_health / max_health


## Check if structure is garrisonable (not destroyed)
func is_garrisonable() -> bool:
	return not is_destroyed and garrisoned_units.size() < max_infantry
