extends BaseStructure
class_name MGNest
## MGNest - Automated machine gun emplacement
## Covers a firing arc, suppresses and kills enemies

signal ammo_depleted
signal target_acquired(target: Node3D)
signal firing

# MG Configuration
@export var firing_arc: float = 120.0  # Degrees
@export var fire_range: float = 40.0
@export var damage_per_second: float = 15.0
@export var suppression_per_second: float = 20.0
@export var rotation_speed: float = 2.0

# Ammo
@export var max_ammo: int = 200
var current_ammo: int = 200

# State
var is_crewed: bool = true
var current_target: Node3D = null
var enemies_in_arc: Array[Node3D] = []

# Firing
var fire_cooldown: float = 0.0
var burst_timer: float = 0.0
var is_firing: bool = false

# Visuals
@onready var gun_pivot: Node3D = $GunPivot if has_node("GunPivot") else null
@onready var muzzle_flash: GPUParticles3D = $GunPivot/MuzzleFlash if has_node("GunPivot/MuzzleFlash") else null


func _ready() -> void:
	super._ready()
	structure_name = "MG Nest"
	max_health = 80.0
	armor = 5.0
	current_health = max_health
	current_ammo = max_ammo


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	if not is_crewed or current_ammo <= 0:
		return

	_scan_firing_arc()
	_acquire_target()
	_process_firing(delta)


func _scan_firing_arc() -> void:
	enemies_in_arc.clear()

	for enemy_node: Node in get_tree().get_nodes_in_group("enemy_units"):
		if not is_instance_valid(enemy_node):
			continue

		var enemy := enemy_node as Node3D
		if not enemy:
			continue

		# Check range
		var distance := global_position.distance_to(enemy.global_position)
		if distance > fire_range:
			continue

		# Check arc
		var to_enemy := enemy.global_position - global_position
		to_enemy.y = 0
		var forward := -global_transform.basis.z
		forward.y = 0

		var angle := rad_to_deg(forward.angle_to(to_enemy))
		if angle > firing_arc / 2:
			continue

		# Check line of sight
		if _has_line_of_sight(enemy):
			enemies_in_arc.append(enemy)


func _has_line_of_sight(target: Node3D) -> bool:
	var space_state := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 1.5
	var to := target.global_position + Vector3.UP

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	query.collision_mask = 1 | 4  # Terrain and structures

	var result := space_state.intersect_ray(query)
	return result.is_empty() or result.collider == target


func _acquire_target() -> void:
	# Clear invalid target
	if current_target and not is_instance_valid(current_target):
		current_target = null

	# Check if current target still in arc
	if current_target and current_target not in enemies_in_arc:
		current_target = null

	# Acquire new target if needed
	if not current_target and not enemies_in_arc.is_empty():
		# Prioritize closest/largest group
		current_target = _get_priority_target()
		if current_target:
			target_acquired.emit(current_target)


func _get_priority_target() -> Node3D:
	var best_target: Node3D = null
	var best_score := 0.0

	for enemy in enemies_in_arc:
		var distance := global_position.distance_to(enemy.global_position)
		# Closer enemies get higher priority
		var score := fire_range - distance

		if score > best_score:
			best_score = score
			best_target = enemy

	return best_target


func _process_firing(delta: float) -> void:
	fire_cooldown -= delta

	if not current_target:
		is_firing = false
		return

	# Rotate gun toward target
	if gun_pivot:
		var to_target := current_target.global_position - global_position
		to_target.y = 0
		var target_angle := atan2(to_target.x, to_target.z)
		gun_pivot.rotation.y = lerp_angle(gun_pivot.rotation.y, target_angle, rotation_speed * delta)

	# Fire burst
	if fire_cooldown <= 0:
		_fire_burst(delta)


func _fire_burst(delta: float) -> void:
	if current_ammo <= 0:
		ammo_depleted.emit()
		return

	is_firing = true
	firing.emit()

	# Apply damage
	var damage := damage_per_second * delta
	if current_target.has_method("take_damage"):
		current_target.take_damage(damage)

	# Apply suppression
	if current_target.has_method("apply_suppression"):
		current_target.apply_suppression(suppression_per_second * delta)
	elif current_target.get("suppression") != null:
		current_target.suppression = min(100, current_target.suppression + suppression_per_second * delta)

	# Consume ammo
	current_ammo -= 1

	# Muzzle flash
	if muzzle_flash:
		muzzle_flash.emitting = true

	# Short burst delay
	fire_cooldown = 0.1


func resupply(amount: int) -> void:
	current_ammo = min(max_ammo, current_ammo + amount)


func set_crewed(crewed: bool) -> void:
	is_crewed = crewed
	if not is_crewed:
		current_target = null
		is_firing = false


func get_ammo_percent() -> float:
	return float(current_ammo) / float(max_ammo)
