extends BaseStructure
class_name SupplyDepot
## SupplyDepot - Stores surplus supplies
## Increases max supply storage capacity

@export var storage_capacity: int = 100


func _ready() -> void:
	super._ready()
	structure_name = "Supply Depot"
	max_health = 80.0
	armor = 3.0
	current_health = max_health

	# Register with supply director
	SupplyDirector.register_supply_depot(self)


func _exit_tree() -> void:
	SupplyDirector.unregister_supply_depot(self)
	super._exit_tree()


func _destroy() -> void:
	# Lose stored supplies when destroyed
	var supplies_lost := mini(storage_capacity / 2, GameManager.supplies)
	GameManager.supplies -= supplies_lost

	super._destroy()
