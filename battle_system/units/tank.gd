class_name Tank extends CharacterBody3D
## Tank - Armored vehicle with independent hull and turret rotation.
## Drives like a treaded vehicle: longer turn radius, slope-limited, slower
## reverse, and a turret that tracks targets independently of hull facing.
##
## Mounts a main gun (e.g. m48_main_gun) and a coaxial MG (coax_mg).
## Damage comes from CombatManager.fire_weapon() routed through the projectile
## pool, same as infantry.
##
## Slope handling matches the squad pattern: reads data.max_slope and applies
## a linear speed penalty. Tanks should use a stricter max_slope (~0.30-0.40)
## and stronger penalty than infantry.

const SquadDataScript = preload("res://battle_system/data/squad_data.gd")
const VietnamWeaponDataScript = preload("res://battle_system/data/vietnam_weapon_data.gd")

signal turret_rotated(angle_degrees: float)
signal fired_main_gun(target_pos: Vector3)
signal fired_coax(target_pos: Vector3)
signal tank_destroyed(tank: Tank)
signal path_blocked_by_slope(position: Vector3, slope: float)

enum State { IDLE, MOVING, COMBAT, REVERSING, DESTROYED }
enum TankClass { LIGHT, MEDIUM, HEAVY }

@export var data: Resource  # SquadData
@export var tank_class: TankClass = TankClass.MEDIUM
@export var main_gun_id: String = "m48_main_gun"
@export var coax_gun_id: String = "coax_mg"

## Movement characteristics
@export var hull_turn_rate_deg: float = 45.0   # Hull turns slowly (degrees/sec)
@export var turret_turn_rate_deg: float = 90.0 # Turret turns fast
@export var reverse_speed_mult: float = 0.5    # Reverse is half forward speed
@export var min_turn_radius: float = 4.0       # Cannot pivot in place when fast

## State
var state: State = State.IDLE
var current_health: float = 500.0
var max_health: float = 500.0
var current_target: Node = null
var move_target: Vector3 = Vector3.ZERO
var has_move_order: bool = false
var is_player_controlled: bool = true

## Turret
var _turret_node: Node3D = null
var _hull_node: Node3D = null
var _turret_target_yaw: float = 0.0
var _main_gun_cooldown: float = 0.0
var _coax_cooldown: float = 0.0
var _main_gun_ammo: int = 40
var _coax_ammo: int = 200

## Slope cache (shared pattern with squad.gd)
const SLOPE_QUERY_INTERVAL: float = 0.1
var _slope_query_timer: float = 0.0
var _cached_slope: float = 0.0

## Attack-move mode
var _attack_move_mode: bool = false
var _attack_move_scan_timer: float = 0.0
const ATTACK_MOVE_SCAN_INTERVAL: float = 0.5


func _ready() -> void:
	add_to_group("tanks")
	add_to_group("vehicles")
	add_to_group("all_units")
	if is_player_controlled:
		add_to_group("player_units")
		add_to_group("selectable_units")
	else:
		add_to_group("enemy_units")

	_apply_data()
	_build_placeholder_visual()


func _apply_data() -> void:
	if not data:
		# Default fallback values so the tank still works without a .tres
		max_health = 500.0
		current_health = 500.0
		return
	max_health = data.get_total_health()
	current_health = max_health


func _build_placeholder_visual() -> void:
	# Hull
	_hull_node = Node3D.new()
	_hull_node.name = "Hull"
	add_child(_hull_node)

	var hull_mesh := MeshInstance3D.new()
	var hull_box := BoxMesh.new()
	hull_box.size = Vector3(3.0, 1.0, 5.5)
	hull_mesh.mesh = hull_box
	hull_mesh.position.y = 0.7
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = data.get_faction_color() if data else Color(0.3, 0.35, 0.25)
	hull_mesh.material_override = hull_mat
	_hull_node.add_child(hull_mesh)

	# Turret (independent rotation)
	_turret_node = Node3D.new()
	_turret_node.name = "Turret"
	_turret_node.position.y = 1.4
	add_child(_turret_node)

	var turret_mesh := MeshInstance3D.new()
	var turret_box := BoxMesh.new()
	turret_box.size = Vector3(2.2, 0.8, 2.5)
	turret_mesh.mesh = turret_box
	turret_mesh.material_override = hull_mat
	_turret_node.add_child(turret_mesh)

	# Main gun barrel
	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.12
	barrel_mesh.bottom_radius = 0.12
	barrel_mesh.height = 3.5
	barrel.mesh = barrel_mesh
	barrel.rotation_degrees = Vector3(90, 0, 0)
	barrel.position = Vector3(0, 0, 2.2)
	_turret_node.add_child(barrel)

	# Collision
	var coll := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 2.4, 5.8)
	coll.shape = box
	coll.position.y = 1.0
	add_child(coll)
	collision_layer = 2  # US layer by default; override per faction


func _physics_process(delta: float) -> void:
	if state == State.DESTROYED:
		return

	if _main_gun_cooldown > 0.0:
		_main_gun_cooldown -= delta
	if _coax_cooldown > 0.0:
		_coax_cooldown -= delta

	# Process turret aiming (independent of hull)
	_process_turret(delta)

	# Combat takes priority over movement target
	if current_target and is_instance_valid(current_target):
		_process_combat(delta)
	elif has_move_order:
		_process_movement(delta)

	_snap_to_terrain()


func _process_turret(delta: float) -> void:
	if not _turret_node:
		return
	if not current_target or not is_instance_valid(current_target):
		# Return turret to hull-forward when idle
		_turret_target_yaw = 0.0
	else:
		var to_target: Vector3 = current_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() > 0.1:
			var world_yaw: float = atan2(to_target.x, to_target.z)
			# Convert to local yaw relative to hull
			_turret_target_yaw = world_yaw - rotation.y

	var max_step: float = deg_to_rad(turret_turn_rate_deg) * delta
	_turret_node.rotation.y = lerp_angle(_turret_node.rotation.y, _turret_target_yaw, clampf(max_step / max(0.001, abs(angle_difference(_turret_node.rotation.y, _turret_target_yaw))), 0.0, 1.0))
	turret_rotated.emit(rad_to_deg(_turret_node.rotation.y))


func _process_combat(_delta: float) -> void:
	if not is_instance_valid(current_target):
		current_target = null
		state = State.IDLE
		return

	var dist: float = global_position.distance_to(current_target.global_position)
	var range_max: float = data.attack_range if data else 60.0

	if dist > range_max:
		move_to(current_target.global_position)
		return

	state = State.COMBAT
	# Check if turret is roughly pointed at target before firing
	var turret_world_yaw: float = rotation.y + (_turret_node.rotation.y if _turret_node else 0.0)
	var to_target: Vector3 = current_target.global_position - global_position
	var target_yaw: float = atan2(to_target.x, to_target.z)
	var aim_error: float = abs(angle_difference(turret_world_yaw, target_yaw))

	# Within 10 degrees: fire main gun (slow, big damage)
	# Within 5 degrees and close: also coax
	if aim_error < deg_to_rad(10.0) and _main_gun_cooldown <= 0.0 and _main_gun_ammo > 0:
		_fire_main_gun()
	if dist < 80.0 and aim_error < deg_to_rad(5.0) and _coax_cooldown <= 0.0 and _coax_ammo > 0:
		_fire_coax()


func _fire_main_gun() -> void:
	if not current_target:
		return
	if CombatManager:
		CombatManager.fire_weapon(self, current_target, main_gun_id)
	_main_gun_ammo -= 1
	fired_main_gun.emit(current_target.global_position)
	var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(main_gun_id)
	_main_gun_cooldown = 60.0 / weapon.rate_of_fire if weapon else 6.0


func _fire_coax() -> void:
	if not current_target:
		return
	if CombatManager:
		CombatManager.fire_weapon(self, current_target, coax_gun_id)
	_coax_ammo -= 1
	fired_coax.emit(current_target.global_position)
	var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(coax_gun_id)
	_coax_cooldown = 60.0 / weapon.rate_of_fire if weapon else 0.1


func _process_movement(delta: float) -> void:
	var direction: Vector3 = move_target - global_position
	direction.y = 0
	var distance: float = direction.length()

	if distance < 1.5:
		has_move_order = false
		velocity = Vector3.ZERO
		state = State.IDLE
		return

	var seek_direction: Vector3 = direction.normalized()

	# Slope check (same pattern as squad.gd)
	_slope_query_timer -= delta
	if _slope_query_timer <= 0.0:
		_slope_query_timer = SLOPE_QUERY_INTERVAL
		_cached_slope = _sample_slope_ahead(seek_direction)

	var speed: float
	if data and data.has_method("get_speed_at_slope"):
		speed = data.get_speed_at_slope(_cached_slope)
	else:
		speed = data.move_speed if data else 8.0

	if speed <= 0.0:
		velocity = Vector3.ZERO
		has_move_order = false
		state = State.IDLE
		path_blocked_by_slope.emit(global_position, _cached_slope)
		return

	# Hull rotation: tanks turn slowly. Compute desired yaw.
	var target_yaw: float = atan2(seek_direction.x, seek_direction.z)
	var current_yaw: float = rotation.y
	var yaw_diff: float = angle_difference(current_yaw, target_yaw)
	var max_step: float = deg_to_rad(hull_turn_rate_deg) * delta
	rotation.y = current_yaw + clampf(yaw_diff, -max_step, max_step)

	# Only move forward if hull is roughly facing the target direction.
	# This prevents the "moonwalk" effect of sliding sideways while turning.
	var alignment: float = cos(yaw_diff)  # 1.0 = perfectly aligned, -1.0 = backward
	if alignment < 0.0:
		alignment = 0.0  # No reversing into target for now
	speed *= alignment

	var forward: Vector3 = Vector3(sin(rotation.y), 0, cos(rotation.y))
	velocity = forward * speed
	move_and_slide()
	state = State.MOVING


func _sample_slope_ahead(move_dir: Vector3) -> float:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if not terrain:
		return 0.0
	var probe_pos: Vector3 = global_position + move_dir * 2.5  # Tank probes further ahead
	if terrain.has_method("get_normal_at"):
		var normal: Vector3 = terrain.get_normal_at(probe_pos)
		return clampf(1.0 - normal.y, 0.0, 1.0)
	if terrain.has_method("get_height_at"):
		var h0: float = terrain.get_height_at(global_position)
		var h1: float = terrain.get_height_at(probe_pos)
		var rise: float = abs(h1 - h0)
		return clampf(atan2(rise, 2.5) / (PI * 0.5), 0.0, 1.0)
	return 0.0


func _snap_to_terrain() -> void:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		global_position.y = terrain.get_height_at(global_position)


# =============================================================================
# PUBLIC API
# =============================================================================

func move_to(target: Vector3) -> void:
	move_target = target
	has_move_order = true
	_attack_move_mode = false


func attack_move_to(target: Vector3) -> void:
	move_target = target
	has_move_order = true
	_attack_move_mode = true
	_attack_move_scan_timer = 0.0


func attack(target: Node) -> void:
	current_target = target
	state = State.COMBAT


func stop_attack() -> void:
	current_target = null
	state = State.IDLE


func take_damage(amount: float, source: Node = null) -> void:
	# Apply armor reduction
	var armor_val: float = data.armor if data else 30.0
	var reduction: float = clampf(armor_val * 0.02, 0.0, 0.7)
	var actual: float = amount * (1.0 - reduction)
	current_health = max(0.0, current_health - actual)
	if current_health <= 0.0:
		_destroy()


func _destroy() -> void:
	state = State.DESTROYED
	tank_destroyed.emit(self)
	# Leave wreck for a few seconds before despawn
	var t := get_tree().create_timer(5.0)
	t.timeout.connect(queue_free)


func get_main_gun_ammo() -> int:
	return _main_gun_ammo


func get_coax_ammo() -> int:
	return _coax_ammo
