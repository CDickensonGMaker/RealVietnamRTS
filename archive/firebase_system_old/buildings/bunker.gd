extends BuildingBase
class_name Bunker
## Bunker - Reinforced fighting position for infantry

# Bunker specific
@export var firing_slots: int = 4
@export var vision_bonus: float = 0.2

func _ready() -> void:
	building_type = GameEnums.BuildingType.BUNKER
	max_health = 200.0
	armor = 30.0
	garrison_capacity = 8
	cover_type = 3  # HEAVY
	super._ready()

func _create_visual() -> void:
	# Main structure
	var main := CSGBox3D.new()
	main.size = Vector3(6, 1.8, 5)
	main.position.y = 0.9

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.4, 0.3)
	main.material = mat

	add_child(main)

	# Sandbag layer
	var sandbags := CSGBox3D.new()
	sandbags.size = Vector3(7, 0.8, 6)
	sandbags.position.y = 0.4

	var sand_mat := StandardMaterial3D.new()
	sand_mat.albedo_color = Color(0.55, 0.5, 0.35)
	sandbags.material = sand_mat

	add_child(sandbags)

	# Firing slot (front)
	var slot := CSGBox3D.new()
	slot.size = Vector3(4, 0.3, 0.5)
	slot.position = Vector3(0, 1.5, 2.3)

	var slot_mat := StandardMaterial3D.new()
	slot_mat.albedo_color = Color(0.2, 0.2, 0.2)
	slot.material = slot_mat

	add_child(slot)

	visual_mesh = main

func get_garrison_combat_bonus() -> float:
	## Bonus to garrison's combat effectiveness
	return 1.25  # 25% more effective

func get_garrison_protection() -> float:
	## Damage reduction for garrisoned units
	return 0.6  # 60% damage reduction

func get_suppression_resistance() -> float:
	## How much suppression resistance garrison gets
	return 0.7  # 70% less suppression
