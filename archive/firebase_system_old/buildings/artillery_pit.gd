extends BuildingBase
class_name ArtilleryPit
## ArtilleryPit - 105mm howitzer emplacement for fire support

signal fire_mission_started(target: Vector3)
signal fire_mission_complete()
signal round_fired(target: Vector3)
signal out_of_ammo()

# Weapon configuration
@export var weapon_type: int = GameEnums.WeaponClass.M102_HOWITZER
@export var max_range: float = 11000.0  # 11km
@export var min_range: float = 500.0
@export var damage: float = 500.0
@export var blast_radius: float = 15.0
@export var rate_of_fire: float = 3.0  # rounds per minute

# Ammunition
@export var max_ammo: int = 50
var current_ammo: int = 50

# Fire mission state
var is_firing: bool = false
var current_target: Vector3 = Vector3.ZERO
var rounds_to_fire: int = 0
var fire_cooldown: float = 0.0

func _ready() -> void:
	building_type = GameEnums.BuildingType.ARTILLERY_PIT
	max_health = 150.0
	armor = 20.0
	garrison_capacity = 6  # Artillery crew
	cover_type = 2  # MEDIUM
	super._ready()

func _create_visual() -> void:
	# Circular revetment
	var pit := CSGCylinder3D.new()
	pit.radius = 4.0
	pit.height = 0.8
	pit.sides = 12

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.45, 0.3)
	pit.material = mat
	pit.position.y = 0.4

	add_child(pit)

	# Gun barrel
	var barrel := CSGCylinder3D.new()
	barrel.radius = 0.15
	barrel.height = 3.0
	barrel.rotation_degrees.x = -30  # Elevated
	barrel.position = Vector3(0, 1.5, 1.0)

	var barrel_mat := StandardMaterial3D.new()
	barrel_mat.albedo_color = Color(0.25, 0.25, 0.2)
	barrel.material = barrel_mat

	add_child(barrel)

	# Gun base
	var base := CSGBox3D.new()
	base.size = Vector3(2, 0.5, 2)
	base.position = Vector3(0, 0.8, 0)
	base.material = barrel_mat

	add_child(base)

	visual_mesh = pit

func _process(delta: float) -> void:
	if is_destroyed:
		return

	fire_cooldown -= delta

	if is_firing and rounds_to_fire > 0:
		_process_fire_mission(delta)

func _process_fire_mission(_delta: float) -> void:
	if fire_cooldown <= 0 and current_ammo > 0 and rounds_to_fire > 0:
		_fire_round()
		fire_cooldown = 60.0 / rate_of_fire

	if rounds_to_fire <= 0 or current_ammo <= 0:
		_complete_fire_mission()

func _fire_round() -> void:
	current_ammo -= 1
	rounds_to_fire -= 1

	# Calculate impact point with dispersion
	var dispersion := Vector3(
		randf_range(-20, 20),
		0,
		randf_range(-20, 20)
	)
	var impact := current_target + dispersion

	# Schedule impact after flight time
	var distance := global_position.distance_to(impact)
	var flight_time := distance / 500.0  # 500 m/s shell velocity

	round_fired.emit(impact)

	_schedule_impact(impact, flight_time)

	if current_ammo <= 0:
		out_of_ammo.emit()

func _schedule_impact(position: Vector3, delay: float) -> void:
	await get_tree().create_timer(delay).timeout

	# Apply damage
	var victims := SpatialHashGrid.get_all_units_in_radius(position, blast_radius)
	for victim in victims:
		if is_instance_valid(victim) and victim.has_method("take_damage"):
			var dist := victim.global_position.distance_to(position)
			var falloff := 1.0 - (dist / blast_radius)
			victim.take_damage(damage * falloff, self)

	BattleSignals.explosion.emit(position, blast_radius, damage)
	BattleSignals.artillery_impact.emit(position)

func request_fire_mission(target: Vector3, rounds: int = 6) -> bool:
	## Request artillery fire mission

	if is_firing:
		return false  # Already busy

	var distance := global_position.distance_to(target)
	if distance < min_range or distance > max_range:
		return false  # Out of range

	if current_ammo <= 0:
		return false  # No ammo

	rounds = mini(rounds, current_ammo)

	current_target = target
	rounds_to_fire = rounds
	is_firing = true

	fire_mission_started.emit(target)
	return true

func _complete_fire_mission() -> void:
	is_firing = false
	rounds_to_fire = 0
	fire_mission_complete.emit()

func cancel_fire_mission() -> void:
	if is_firing:
		_complete_fire_mission()

func resupply(amount: int) -> void:
	current_ammo = mini(max_ammo, current_ammo + amount)

func get_ammo_ratio() -> float:
	return float(current_ammo) / float(max_ammo)

func can_fire_at(target: Vector3) -> bool:
	var distance := global_position.distance_to(target)
	return distance >= min_range and distance <= max_range and current_ammo > 0

func get_range() -> float:
	return max_range

func is_defensive_weapon() -> bool:
	return true

func engage_target(target: Node3D) -> void:
	if is_instance_valid(target):
		request_fire_mission(target.global_position, 3)

func cease_fire() -> void:
	cancel_fire_mission()
