extends BaseStructure
class_name Minefield
## Minefield - Hidden explosive area that damages enemy squads

@export var damage_per_mine: float = 40.0
@export var mines_count: int = 5
@export var detection_radius: float = 2.5
@export var is_hidden: bool = true  # Invisible to enemies until triggered

var remaining_mines: int
var triggered_positions: Array[Vector3] = []


func _ready() -> void:
	super._ready()
	structure_name = "Minefield"
	max_health = 50.0  # Mines can be cleared
	armor = 0.0
	current_health = max_health

	remaining_mines = mines_count

	# Create detection area
	_setup_detection_area()

	# Hide mesh if hidden
	if is_hidden:
		_set_hidden(true)


func _setup_detection_area() -> void:
	var area := Area3D.new()
	area.name = "MineDetectionArea"

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(5, 1, 5)  # Match minefield footprint
	collision.shape = shape
	collision.position.y = 0.5

	area.add_child(collision)
	area.collision_layer = 0
	area.collision_mask = 2  # Units layer

	area.body_entered.connect(_on_unit_entered)

	add_child(area)


func _on_unit_entered(body: Node3D) -> void:
	# Only trigger on enemy units
	if not body.is_in_group("enemy"):
		return

	if remaining_mines <= 0:
		return

	# Trigger mine
	_trigger_mine(body)


func _trigger_mine(target: Node3D) -> void:
	remaining_mines -= 1

	# Reveal minefield briefly
	_set_hidden(false)

	# Deal damage
	if target.has_method("take_damage"):
		target.take_damage(damage_per_mine, self)

	# Create explosion effect (placeholder)
	var explosion_pos := target.global_position
	triggered_positions.append(explosion_pos)
	_spawn_explosion(explosion_pos)

	# Check if depleted
	if remaining_mines <= 0:
		# Minefield is exhausted
		await get_tree().create_timer(2.0).timeout
		queue_free()
	else:
		# Hide again after delay
		await get_tree().create_timer(1.0).timeout
		_set_hidden(true)


func _spawn_explosion(pos: Vector3) -> void:
	# Create simple visual explosion
	var explosion := CSGSphere3D.new()
	explosion.radius = 1.5
	explosion.global_position = pos

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.5, 0)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.3, 0)
	mat.emission_energy_multiplier = 3.0
	explosion.material = mat

	get_tree().current_scene.add_child(explosion)

	# Fade out
	var tween := create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tween.tween_callback(explosion.queue_free)


func _set_hidden(hidden: bool) -> void:
	is_hidden = hidden
	var mesh: Node = get_node_or_null("Mesh")
	if mesh:
		mesh.visible = not hidden


func get_remaining_mines() -> int:
	return remaining_mines


func replenish_mines(amount: int) -> void:
	remaining_mines = mini(remaining_mines + amount, mines_count)
