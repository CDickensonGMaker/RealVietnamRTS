extends BaseStructure
class_name Bunker
## Bunker - Heavy fortification that can garrison one squad
## Provides strong cover and protection from fire

signal squad_garrisoned(squad: Node3D)
signal squad_ungarrisoned(squad: Node3D)

# Garrison
var garrisoned_squad: Node3D = null
var garrison_capacity: int = 1

# Combat bonuses
@export var cover_bonus: float = 0.7  # 70% damage reduction
@export var suppression_resistance: float = 0.8  # 80% suppression resistance

# Visual
@onready var garrison_point: Marker3D = $GarrisonPoint if has_node("GarrisonPoint") else null
@onready var firing_slot: Marker3D = $FiringSlot if has_node("FiringSlot") else null


func _ready() -> void:
	super._ready()
	structure_name = "Bunker"
	max_health = 150.0
	armor = 15.0
	current_health = max_health


func _process(delta: float) -> void:
	if not garrisoned_squad:
		return

	if not is_instance_valid(garrisoned_squad):
		garrisoned_squad = null
		return

	# Keep garrisoned squad at garrison point
	if garrison_point:
		garrisoned_squad.global_position = garrison_point.global_position


func garrison(squad: Node3D) -> bool:
	if garrisoned_squad != null:
		push_warning("Bunker: Already garrisoned")
		return false

	if not squad.has_method("set_standing_order"):
		push_warning("Bunker: Invalid squad")
		return false

	garrisoned_squad = squad

	# Move squad into bunker
	if garrison_point:
		squad.global_position = garrison_point.global_position

	# Set squad state
	if squad.has_method("set_standing_order"):
		squad.current_state = squad.SquadState.GARRISONED

	squad_garrisoned.emit(squad)
	return true


func ungarrison() -> Node3D:
	if not garrisoned_squad:
		return null

	var squad := garrisoned_squad
	garrisoned_squad = null

	# Move squad outside
	squad.global_position = global_position + Vector3(0, 0, 3)

	# Reset squad state
	if squad.has_method("set_standing_order"):
		squad.current_state = squad.SquadState.IDLE

	squad_ungarrisoned.emit(squad)
	return squad


func has_garrison() -> bool:
	return garrisoned_squad != null


func get_garrisoned_squad() -> Node3D:
	return garrisoned_squad


# Damage routing - damage to bunker is reduced, squad takes less
func take_damage(amount: float) -> void:
	# Bunker absorbs most damage
	var bunker_damage := amount * 0.8
	var squad_damage := amount * 0.2 * (1.0 - cover_bonus)

	super.take_damage(bunker_damage)

	# Apply reduced damage to garrisoned squad
	if garrisoned_squad and is_instance_valid(garrisoned_squad):
		if garrisoned_squad.has_method("take_damage"):
			garrisoned_squad.take_damage(squad_damage)


func _destroy() -> void:
	# Eject squad before destruction (they take damage)
	if garrisoned_squad and is_instance_valid(garrisoned_squad):
		ungarrison()
		garrisoned_squad.take_damage(30.0)  # Collapse damage

	super._destroy()
