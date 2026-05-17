extends BaseStructure
class_name Sandbag
## Sandbag - Basic cover wall
## Free to build, blocks movement, provides light cover

func _ready() -> void:
	super._ready()
	structure_name = "Sandbag Wall"
	max_health = 30.0
	armor = 2.0
	current_health = max_health
