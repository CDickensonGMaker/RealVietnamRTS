extends BuildingBase
class_name MGNest
## MGNest - Machine gun emplacement with auto-fire capability

signal target_acquired(target: Node3D)
signal target_lost()
signal firing_started()
signal firing_stopped()

# Weapon stats
@export var fire_rate: float = 550.0  # RPM
@export var damage_per_shot: float = 25.0
@export var range: float = 150.0
@export var accuracy: float = 0.75
@export var suppression: float = 30.0
@export var arc_of_fire: float = 120.0  # degrees

# Ammo
@export var max_ammo: int = 500
var current_ammo: int = 500

# Combat state
var current_target: Node3D = null
var is_firing: bool = false
var fire_cooldown: float = 0.0
var facing_direction: Vector3 = Vector3.FORWARD

func _ready() -> void:
	building_type = GameEnums.BuildingType.MACHINE_GUN_NEST
	max_health = 80.0
	armor = 10.0
	garrison_capacity = 2
	cover_type = 2  # MEDIUM
	super._ready()

func _create_visual() -> void:
	# Sandbag ring
	var sandbags := CSGCylinder3D.new()
	sandbags.radius = 2.5
	sandbags.height = 1.2
	sandbags.sides = 8

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.35)
	sandbags.material = mat

	add_child(sandbags)

	# Gun representation
	var gun := CSGBox3D.new()
	gun.size = Vector3(0.3, 0.3, 1.5)
	gun.position = Vector3(0, 1.0, 0.5)

	var gun_mat := StandardMaterial3D.new()
	gun_mat.albedo_color = Color(0.2, 0.2, 0.2)
	gun.material = gun_mat

	add_child(gun)
	visual_mesh = sandbags

func _process(delta: float) -> void:
	if is_destroyed:
		return

	fire_cooldown -= delta

	if is_firing and current_target:
		_process_firing(delta)
	else:
		_scan_for_targets()

func _scan_for_targets() -> void:
	if current_ammo <= 0:
		return

	var enemies := SpatialHashGrid.get_enemies_in_radius(
		global_position, range, GameEnums.Faction.US_ARMY
	)

	for enemy in enemies:
		if is_instance_valid(enemy) and _is_in_arc(enemy.global_position):
			_acquire_target(enemy)
			return

func _is_in_arc(target_pos: Vector3) -> bool:
	var to_target := (target_pos - global_position).normalized()
	to_target.y = 0

	var dot := facing_direction.dot(to_target)
	var angle := acos(clampf(dot, -1.0, 1.0))

	return rad_to_deg(angle) <= arc_of_fire / 2

func _acquire_target(target: Node3D) -> void:
	current_target = target
	is_firing = true
	target_acquired.emit(target)
	firing_started.emit()

func _process_firing(delta: float) -> void:
	if not is_instance_valid(current_target):
		_lose_target()
		return

	# Check if still in range and arc
	var distance := global_position.distance_to(current_target.global_position)
	if distance > range or not _is_in_arc(current_target.global_position):
		_lose_target()
		return

	# Fire if cooldown ready
	if fire_cooldown <= 0 and current_ammo > 0:
		_fire_burst()
		fire_cooldown = 60.0 / fire_rate  # Convert RPM to seconds

func _fire_burst() -> void:
	current_ammo -= 1

	# Calculate hit
	var hit_chance := accuracy
	# Reduce accuracy at range
	var distance := global_position.distance_to(current_target.global_position)
	hit_chance *= 1.0 - (distance / range) * 0.3

	if randf() < hit_chance:
		if current_target.has_method("take_damage"):
			current_target.take_damage(damage_per_shot, self)

	# Apply suppression regardless of hit
	if current_target.has_method("apply_suppression"):
		current_target.apply_suppression(suppression * 0.5)

	BattleSignals.weapon_fired.emit(self, GameEnums.WeaponClass.M60, current_target.global_position)

func _lose_target() -> void:
	current_target = null
	is_firing = false
	target_lost.emit()
	firing_stopped.emit()

func engage_target(target: Node3D) -> void:
	## Manual target assignment
	if is_instance_valid(target) and _is_in_arc(target.global_position):
		_acquire_target(target)

func cease_fire() -> void:
	_lose_target()

func resupply(amount: int) -> void:
	current_ammo = mini(max_ammo, current_ammo + amount)

func is_defensive_weapon() -> bool:
	return true

func set_facing(direction: Vector3) -> void:
	facing_direction = direction.normalized()
	facing_direction.y = 0
	look_at(global_position + facing_direction)

func get_ammo_ratio() -> float:
	return float(current_ammo) / float(max_ammo)
