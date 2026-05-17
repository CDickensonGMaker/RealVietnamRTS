extends BaseStructure
class_name MortarPit
## MortarPit - Indirect fire support
## Can auto-fire on spotted enemies or be manually targeted

signal mortar_fired(target_position: Vector3)
signal ammo_depleted
signal target_acquired(target: Node3D)

# Mortar configuration
@export var fire_range: float = 80.0
@export var min_range: float = 15.0  # Can't fire too close
@export var damage_per_shell: float = 40.0
@export var splash_radius: float = 5.0
@export var reload_time: float = 4.0
@export var shells_per_volley: int = 3
@export var volley_delay: float = 0.5

# Ammo
@export var max_ammo: int = 30
var current_ammo: int = 30

# State
var is_crewed: bool = true
var current_target_position: Vector3 = Vector3.ZERO
var is_manual_target: bool = false
var reload_timer: float = 0.0
var volley_count: int = 0
var volley_timer: float = 0.0
var is_firing: bool = false

# Auto-targeting
var auto_target: Node3D = null


func _ready() -> void:
	super._ready()
	structure_name = "Mortar Pit"
	max_health = 60.0
	armor = 3.0
	current_health = max_health
	current_ammo = max_ammo


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	if not is_crewed or current_ammo <= 0:
		return

	reload_timer -= delta

	# Process volley firing
	if is_firing:
		_process_volley(delta)
		return

	# Auto-acquire targets if no manual target
	if not is_manual_target:
		_auto_acquire_target()

	# Fire when ready
	if reload_timer <= 0 and current_target_position != Vector3.ZERO:
		_start_volley()


func _auto_acquire_target() -> void:
	# Look for spotted enemies in range
	var best_target: Node3D = null
	var best_priority := 0.0

	var enemies: Array[Node] = []
	enemies.assign(get_tree().get_nodes_in_group("enemy_units"))

	for enemy_node: Node in enemies:
		if not is_instance_valid(enemy_node):
			continue

		var enemy := enemy_node as Node3D
		if not enemy:
			continue

		var distance := global_position.distance_to(enemy.global_position)

		# Check range
		if distance < min_range or distance > fire_range:
			continue

		# Check if spotted (known to intel)
		if not IntelDirector.is_cell_visible(enemy.global_position):
			continue

		# Priority based on threat and grouping
		var priority := 1.0

		# Prefer groups
		var nearby_count := 0
		for other_node: Node in enemies:
			var other := other_node as Node3D
			if other and other != enemy and is_instance_valid(other):
				if enemy.global_position.distance_to(other.global_position) < splash_radius:
					nearby_count += 1
		priority += nearby_count * 0.5

		if priority > best_priority:
			best_priority = priority
			best_target = enemy

	if best_target:
		auto_target = best_target
		current_target_position = best_target.global_position
		target_acquired.emit(best_target)


func _start_volley() -> void:
	if current_ammo < shells_per_volley:
		return

	is_firing = true
	volley_count = 0
	volley_timer = 0.0


func _process_volley(delta: float) -> void:
	volley_timer -= delta

	if volley_timer <= 0:
		_fire_shell()
		volley_count += 1
		volley_timer = volley_delay

		if volley_count >= shells_per_volley:
			is_firing = false
			reload_timer = reload_time

			# Clear auto target after volley
			if not is_manual_target:
				auto_target = null
				current_target_position = Vector3.ZERO


func _fire_shell() -> void:
	if current_ammo <= 0:
		ammo_depleted.emit()
		is_firing = false
		return

	current_ammo -= 1

	# Add some scatter
	var scatter := Vector3(
		randf_range(-3, 3),
		0,
		randf_range(-3, 3)
	)
	var impact_pos := current_target_position + scatter

	mortar_fired.emit(impact_pos)

	# Apply damage at impact (would have travel time in full implementation)
	_apply_splash_damage(impact_pos)


func _apply_splash_damage(impact_pos: Vector3) -> void:
	# Find all units in splash radius
	var all_units: Array[Node] = []
	all_units.append_array(get_tree().get_nodes_in_group("enemy_units"))
	all_units.append_array(get_tree().get_nodes_in_group("player_units"))

	for unit: Node in all_units:
		if not is_instance_valid(unit):
			continue

		var distance := impact_pos.distance_to((unit as Node3D).global_position)

		if distance <= splash_radius:
			# Damage falls off with distance
			var damage_multiplier := 1.0 - (distance / splash_radius)
			var final_damage := damage_per_shell * damage_multiplier

			if unit.has_method("take_damage"):
				unit.call("take_damage", final_damage)


# Public interface

func set_manual_target(position: Vector3) -> bool:
	var distance := global_position.distance_to(position)

	if distance < min_range:
		push_warning("MortarPit: Target too close")
		return false
	if distance > fire_range:
		push_warning("MortarPit: Target out of range")
		return false

	current_target_position = position
	is_manual_target = true
	return true


func clear_target() -> void:
	current_target_position = Vector3.ZERO
	is_manual_target = false
	auto_target = null


func set_crewed(crewed: bool) -> void:
	is_crewed = crewed
	if not is_crewed:
		is_firing = false


func resupply(amount: int) -> void:
	current_ammo = min(max_ammo, current_ammo + amount)


func get_ammo_percent() -> float:
	return float(current_ammo) / float(max_ammo)


func is_in_range(position: Vector3) -> bool:
	var distance := global_position.distance_to(position)
	return distance >= min_range and distance <= fire_range


func can_fire() -> bool:
	## Check if mortar is ready to fire
	return is_crewed and current_ammo > 0 and reload_timer <= 0 and not is_firing


func fire_at_position(position: Vector3) -> bool:
	## Fire at a specific position (called by observation tower spotting)
	if not can_fire():
		return false
	if not is_in_range(position):
		return false

	return set_manual_target(position)
