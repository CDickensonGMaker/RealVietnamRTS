extends BaseStructure
class_name Foxhole
## Foxhole - Basic infantry fighting position
## Free to build, provides medium cover

signal squad_garrisoned(squad: Node3D)
signal squad_ungarrisoned(squad: Node3D)

var garrisoned_squad: Node3D = null

@export var cover_bonus: float = 0.5  # 50% damage reduction

@onready var garrison_point: Marker3D = $GarrisonPoint if has_node("GarrisonPoint") else null


func _ready() -> void:
	super._ready()
	structure_name = "Foxhole"
	max_health = 40.0
	armor = 0.0
	current_health = max_health


func _process(delta: float) -> void:
	if garrisoned_squad and is_instance_valid(garrisoned_squad):
		if garrison_point:
			garrisoned_squad.global_position = garrison_point.global_position


func garrison(squad: Node3D) -> bool:
	if garrisoned_squad != null:
		return false

	garrisoned_squad = squad

	if garrison_point:
		squad.global_position = garrison_point.global_position

	if squad.has_method("set_standing_order"):
		squad.current_state = squad.SquadState.GARRISONED

	squad_garrisoned.emit(squad)
	return true


func ungarrison() -> Node3D:
	if not garrisoned_squad:
		return null

	var squad := garrisoned_squad
	garrisoned_squad = null

	squad.global_position = global_position + Vector3(2, 0, 0)

	if squad.has_method("set_standing_order"):
		squad.current_state = squad.SquadState.IDLE

	squad_ungarrisoned.emit(squad)
	return squad


func has_garrison() -> bool:
	return garrisoned_squad != null


func take_damage(amount: float) -> void:
	# Foxhole takes some damage, squad takes reduced damage
	var foxhole_damage := amount * 0.3
	var squad_damage := amount * 0.7 * (1.0 - cover_bonus)

	super.take_damage(foxhole_damage)

	if garrisoned_squad and is_instance_valid(garrisoned_squad):
		if garrisoned_squad.has_method("take_damage"):
			garrisoned_squad.take_damage(squad_damage)
