extends StaticBody3D
class_name BaseStructure
## BaseStructure - Base class for all firebase structures
## Handles damage, destruction, repair, and selection

signal structure_damaged(damage: float)
signal structure_destroyed
signal structure_repaired
signal structure_selected
signal structure_deselected

# Structure configuration
@export var structure_name: String = "Structure"
@export var max_health: float = 100.0
@export var armor: float = 0.0  # Damage reduction

# State
var current_health: float = 100.0
var is_constructed: bool = true
var is_selected: bool = false
var construction_progress: float = 1.0  # 0-1 during construction

# Visuals
@onready var mesh: MeshInstance3D = $Mesh if has_node("Mesh") else null
@onready var selection_indicator: Node3D = $SelectionIndicator if has_node("SelectionIndicator") else null
@onready var damage_overlay: Node3D = $DamageOverlay if has_node("DamageOverlay") else null


func _ready() -> void:
	add_to_group("structures")
	current_health = max_health
	GameManager.register_structure(self)


func _exit_tree() -> void:
	GameManager.unregister_structure(self)


func take_damage(amount: float) -> void:
	var actual_damage: float = maxf(0.0, amount - armor)
	current_health -= actual_damage

	structure_damaged.emit(actual_damage)
	_update_damage_visual()

	if current_health <= 0:
		_destroy()


func _destroy() -> void:
	structure_destroyed.emit()
	# Play destruction effects, etc.
	queue_free()


func repair(amount: float) -> void:
	if current_health >= max_health:
		return

	current_health = min(current_health + amount, max_health)
	_update_damage_visual()

	if current_health >= max_health:
		structure_repaired.emit()


func _update_damage_visual() -> void:
	if not damage_overlay:
		return

	var damage_percent := 1.0 - (current_health / max_health)
	damage_overlay.visible = damage_percent > 0.3


func select() -> void:
	is_selected = true
	if selection_indicator:
		selection_indicator.visible = true
	structure_selected.emit()


func deselect() -> void:
	is_selected = false
	if selection_indicator:
		selection_indicator.visible = false
	structure_deselected.emit()


func is_enemy() -> bool:
	return false


func get_health_percent() -> float:
	return current_health / max_health


func needs_repair() -> bool:
	return current_health < max_health
