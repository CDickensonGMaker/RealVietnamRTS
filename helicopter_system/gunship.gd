class_name Gunship extends CharacterBody3D
## Gunship - UH-1C/M or AH-1G Cobra attack helicopter.
## Provides fire support with rockets and miniguns.
## Loiters in orbit patterns and engages ground targets.
##
## Serves Pillar 5 (The War Continues) - Gunships run automated
## CAP (Combat Air Patrol) over firebases, engaging on their own.

const VietnamWeaponDataScript = preload("res://battle_system/data/vietnam_weapon_data.gd")

signal attack_run_started(gunship: Gunship, target: Node3D)
signal attack_run_complete(gunship: Gunship, kills: int)
signal rockets_fired(gunship: Gunship, target_pos: Vector3, count: int)
signal minigun_fired(gunship: Gunship, target: Node3D)
signal winchester(gunship: Gunship)  # Out of ammo
signal gunship_destroyed(gunship: Gunship)
signal damage_taken(gunship: Gunship, amount: float, source: Node3D)
signal rtb_required(gunship: Gunship, reason: String)

enum State { IDLE, PATROLLING, ATTACK_RUN, ORBITING, RTB, LANDING, LANDED, DESTROYED }
enum GunshipType { UH1_GUNSHIP, AH1_COBRA }
enum WeaponMode { ROCKETS, MINIGUN, BOTH }

@export var gunship_type: GunshipType = GunshipType.UH1_GUNSHIP
@export var faction: int = 0  # GameEnums.Faction

## Flight characteristics
@export var max_speed: float = 55.0
@export var cruise_speed: float = 40.0
@export var attack_speed: float = 50.0
@export var turn_rate: float = 2.5
@export var cruise_altitude: float = 50.0
@export var attack_altitude: float = 30.0
@export var orbit_radius: float = 150.0

## Weapons
@export var rocket_pods: int = 2
@export var rockets_per_pod: int = 7  # M158 pod
@export var minigun_ammo: int = 4000
@export var rocket_weapon_id: String = "rocket_275"
@export var minigun_weapon_id: String = "minigun"

## State
var state: State = State.IDLE
var current_health: float = 200.0
var max_health: float = 200.0
var current_target: Node3D = null
var patrol_center: Vector3 = Vector3.ZERO
var home_base: Node3D = null

## Ammo tracking
var rockets_remaining: int = 14
var minigun_ammo_remaining: int = 4000
var weapon_mode: int = WeaponMode.BOTH

## Cooldowns
var _rocket_cooldown: float = 0.0
var _minigun_cooldown: float = 0.0
const ROCKET_SALVO_COOLDOWN: float = 0.5
const MINIGUN_BURST_COOLDOWN: float = 0.2

## Attack run state
var _attack_run_target_pos: Vector3 = Vector3.ZERO
var _attack_run_start_pos: Vector3 = Vector3.ZERO
var _attack_run_progress: float = 0.0
var _kills_this_run: int = 0

## Orbit state
var _orbit_angle: float = 0.0
var _orbit_direction: float = 1.0  # 1 = CCW, -1 = CW

## Target acquisition
var _target_scan_timer: float = 0.0
const TARGET_SCAN_INTERVAL: float = 1.0
var _target_priority_list: Array[Node3D] = []

## Visual
var _rotor_node: Node3D = null
var _tail_rotor_node: Node3D = null
var _rotor_speed: float = 0.0


func _ready() -> void:
	add_to_group("gunships")
	add_to_group("helicopters")
	add_to_group("aircraft")
	add_to_group("all_units")

	if GameEnums.is_us_faction(faction):
		add_to_group("player_units")
		add_to_group("selectable_units")
	else:
		add_to_group("enemy_units")

	_configure_by_type()
	_build_placeholder_visual()


func _configure_by_type() -> void:
	match gunship_type:
		GunshipType.UH1_GUNSHIP:
			max_speed = 50.0
			max_health = 200.0
			rocket_pods = 2
			rockets_per_pod = 7
			minigun_ammo = 4000
		GunshipType.AH1_COBRA:
			max_speed = 60.0
			max_health = 250.0
			rocket_pods = 2
			rockets_per_pod = 19  # M158/M200 pods
			minigun_ammo = 4000
			attack_altitude = 25.0  # Cobra can fly lower

	rockets_remaining = rocket_pods * rockets_per_pod
	minigun_ammo_remaining = minigun_ammo
	current_health = max_health


func _build_placeholder_visual() -> void:
	var body := MeshInstance3D.new()
	var body_mesh: Mesh

	if gunship_type == GunshipType.AH1_COBRA:
		# Cobra - narrow body
		var box := BoxMesh.new()
		box.size = Vector3(1.2, 1.8, 6.0)
		body_mesh = box
	else:
		# Huey gunship
		var box := BoxMesh.new()
		box.size = Vector3(2.0, 1.5, 5.0)
		body_mesh = box

	body.mesh = body_mesh
	body.position.y = 0.0

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.3, 0.2)  # OD green
	body.material_override = mat
	add_child(body)

	# Main rotor
	_rotor_node = MeshInstance3D.new()
	var rotor_mesh := CylinderMesh.new()
	rotor_mesh.top_radius = 6.0 if gunship_type == GunshipType.UH1_GUNSHIP else 5.5
	rotor_mesh.bottom_radius = 6.0 if gunship_type == GunshipType.UH1_GUNSHIP else 5.5
	rotor_mesh.height = 0.1
	_rotor_node.mesh = rotor_mesh
	_rotor_node.position.y = 1.2

	var rotor_mat := StandardMaterial3D.new()
	rotor_mat.albedo_color = Color(0.2, 0.2, 0.2, 0.5)
	rotor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rotor_node.material_override = rotor_mat
	add_child(_rotor_node)

	# Rocket pods (stub pylons)
	for side in [-1, 1]:
		var pylon := MeshInstance3D.new()
		var pylon_mesh := BoxMesh.new()
		pylon_mesh.size = Vector3(0.3, 0.3, 1.5)
		pylon.mesh = pylon_mesh
		pylon.position = Vector3(1.5 * side, -0.3, 0.5)
		pylon.material_override = mat
		add_child(pylon)

	# Collision
	var coll := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 2.0, 6.2)
	coll.shape = box
	coll.position.y = 0.5
	add_child(coll)

	if GameEnums.is_us_faction(faction):
		collision_layer = 32  # Helicopter layer
	else:
		collision_layer = 32


func _physics_process(delta: float) -> void:
	if state == State.DESTROYED:
		return

	_update_rotor(delta)
	_update_cooldowns(delta)

	match state:
		State.PATROLLING:
			_process_patrol(delta)
		State.ATTACK_RUN:
			_process_attack_run(delta)
		State.ORBITING:
			_process_orbit(delta)
		State.RTB:
			_process_rtb(delta)
		State.LANDING:
			_process_landing(delta)


func _update_rotor(delta: float) -> void:
	if _rotor_node:
		_rotor_speed = lerpf(_rotor_speed, 25.0, delta * 2.0)
		_rotor_node.rotate_y(_rotor_speed * delta)


func _update_cooldowns(delta: float) -> void:
	if _rocket_cooldown > 0.0:
		_rocket_cooldown -= delta
	if _minigun_cooldown > 0.0:
		_minigun_cooldown -= delta


func _process_patrol(delta: float) -> void:
	# Orbit around patrol center
	_orbit_angle += delta * 0.1 * _orbit_direction
	var orbit_pos := Vector3(
		patrol_center.x + cos(_orbit_angle) * orbit_radius,
		cruise_altitude,
		patrol_center.z + sin(_orbit_angle) * orbit_radius
	)

	_fly_toward(orbit_pos, cruise_speed, delta)

	# Scan for targets
	_target_scan_timer -= delta
	if _target_scan_timer <= 0.0:
		_target_scan_timer = TARGET_SCAN_INTERVAL
		_scan_for_targets()


func _process_attack_run(delta: float) -> void:
	_attack_run_progress += delta * 0.3

	# Interpolate along attack vector
	var attack_end: Vector3 = _attack_run_target_pos + (_attack_run_target_pos - _attack_run_start_pos).normalized() * 100.0
	attack_end.y = attack_altitude

	var current_target_pos: Vector3 = _attack_run_start_pos.lerp(attack_end, _attack_run_progress)
	_fly_toward(current_target_pos, attack_speed, delta)

	# Fire weapons during approach
	var dist_to_target: float = global_position.distance_to(_attack_run_target_pos)

	if dist_to_target < 200.0 and dist_to_target > 50.0:
		# Rockets at medium range
		if rockets_remaining > 0 and _rocket_cooldown <= 0.0:
			_fire_rockets()

	if dist_to_target < 150.0:
		# Minigun at close range
		if minigun_ammo_remaining > 0 and _minigun_cooldown <= 0.0 and current_target:
			_fire_minigun()

	# Complete attack run
	if _attack_run_progress >= 1.0 or dist_to_target < 30.0:
		_complete_attack_run()


func _process_orbit(delta: float) -> void:
	if not current_target or not is_instance_valid(current_target):
		current_target = null
		state = State.PATROLLING
		return

	# Orbit the target for continued engagement
	var target_pos: Vector3 = current_target.global_position
	_orbit_angle += delta * 0.15 * _orbit_direction

	var orbit_pos := Vector3(
		target_pos.x + cos(_orbit_angle) * orbit_radius * 0.5,
		attack_altitude,
		target_pos.z + sin(_orbit_angle) * orbit_radius * 0.5
	)

	_fly_toward(orbit_pos, cruise_speed * 0.8, delta)

	# Continue engaging
	var dist: float = global_position.distance_to(target_pos)
	if dist < 200.0:
		if minigun_ammo_remaining > 0 and _minigun_cooldown <= 0.0:
			_fire_minigun()

	# Check for ammo
	if rockets_remaining <= 0 and minigun_ammo_remaining <= 0:
		winchester.emit(self)
		if BattleSignals:
			BattleSignals.gunship_winchester.emit(self)
		_request_rtb("Winchester")


func _process_rtb(delta: float) -> void:
	if not home_base:
		state = State.PATROLLING
		return

	var home_pos: Vector3 = home_base.global_position
	home_pos.y = cruise_altitude

	_fly_toward(home_pos, cruise_speed, delta)

	var dist: float = global_position.distance_to(home_base.global_position)
	if dist < 50.0:
		state = State.LANDING


func _process_landing(delta: float) -> void:
	if not home_base:
		state = State.IDLE
		return

	var landing_pos: Vector3 = home_base.global_position
	landing_pos.y += 0.5

	var dist: float = global_position.distance_to(landing_pos)
	if dist > 2.0:
		var direction: Vector3 = (landing_pos - global_position).normalized()
		velocity = direction * 5.0
	else:
		velocity = Vector3.ZERO
		global_position = landing_pos
		state = State.LANDED

	move_and_slide()


func _fly_toward(target: Vector3, speed: float, delta: float) -> void:
	var direction: Vector3 = (target - global_position).normalized()
	var target_velocity: Vector3 = direction * speed

	# Smooth velocity change
	velocity = velocity.lerp(target_velocity, delta * 2.0)

	# Face direction of travel
	var look_dir := Vector3(velocity.x, 0, velocity.z)
	if look_dir.length() > 1.0:
		var target_yaw: float = atan2(look_dir.x, look_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * turn_rate)

	move_and_slide()


func _scan_for_targets() -> void:
	_target_priority_list.clear()

	# Use SpatialHashGrid for efficient enemy lookup
	var scan_radius: float = orbit_radius * 2.0
	var enemies: Array[Node3D] = []

	if SpatialHashGrid:
		enemies = SpatialHashGrid.get_enemies_in_radius(global_position, faction, scan_radius)
	else:
		return  # No fallback - require SpatialHashGrid

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Check if within patrol area
		if patrol_center != Vector3.ZERO:
			var dist_from_patrol: float = enemy.global_position.distance_to(patrol_center)
			if dist_from_patrol > orbit_radius * 1.5:
				continue

		_target_priority_list.append(enemy)

	# Sort by distance
	_target_priority_list.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
	)

	# Engage closest threat
	if not _target_priority_list.is_empty() and state == State.PATROLLING:
		start_attack_run(_target_priority_list[0])


func _fire_rockets() -> void:
	if rockets_remaining <= 0:
		return

	var salvo_size: int = mini(2, rockets_remaining)
	rockets_remaining -= salvo_size

	if CombatManager and CombatManager.projectile_pool:
		for i in salvo_size:
			var spread := Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
			CombatManager.projectile_pool.fire_weapon(
				rocket_weapon_id,
				self,
				_attack_run_target_pos + spread,
				faction
			)

	_rocket_cooldown = ROCKET_SALVO_COOLDOWN
	rockets_fired.emit(self, _attack_run_target_pos, salvo_size)


func _fire_minigun() -> void:
	if minigun_ammo_remaining <= 0:
		return
	if not current_target or not is_instance_valid(current_target):
		return

	var burst: int = mini(50, minigun_ammo_remaining)
	minigun_ammo_remaining -= burst

	if CombatManager:
		CombatManager.fire_weapon(self, current_target, minigun_weapon_id)

	_minigun_cooldown = MINIGUN_BURST_COOLDOWN
	minigun_fired.emit(self, current_target)


func _complete_attack_run() -> void:
	attack_run_complete.emit(self, _kills_this_run)
	_kills_this_run = 0

	# Decide what to do next
	if rockets_remaining <= 0 and minigun_ammo_remaining <= 0:
		winchester.emit(self)
		_request_rtb("Winchester")
	elif current_target and is_instance_valid(current_target):
		state = State.ORBITING
	else:
		state = State.PATROLLING


func _request_rtb(reason: String) -> void:
	rtb_required.emit(self, reason)
	state = State.RTB

	# Emit to central signal bus
	if BattleSignals:
		BattleSignals.gunship_rtb.emit(self, reason)


# =============================================================================
# PUBLIC API
# =============================================================================

func start_patrol(center: Vector3, radius: float = -1.0) -> void:
	patrol_center = center
	if radius > 0.0:
		orbit_radius = radius
	state = State.PATROLLING
	_orbit_angle = randf() * TAU


func start_attack_run(target: Node3D) -> void:
	if not is_instance_valid(target):
		return

	current_target = target
	_attack_run_target_pos = target.global_position
	_attack_run_start_pos = global_position
	_attack_run_progress = 0.0
	_kills_this_run = 0

	state = State.ATTACK_RUN
	attack_run_started.emit(self, target)

	# Emit to central signal bus
	if BattleSignals:
		BattleSignals.gunship_attack_run.emit(self, target)


func attack_position(pos: Vector3) -> void:
	_attack_run_target_pos = pos
	_attack_run_start_pos = global_position
	_attack_run_progress = 0.0
	current_target = null
	state = State.ATTACK_RUN


func return_to_base(base: Node3D = null) -> void:
	if base:
		home_base = base
	if home_base:
		state = State.RTB


func rearm() -> void:
	rockets_remaining = rocket_pods * rockets_per_pod
	minigun_ammo_remaining = minigun_ammo


func take_damage(amount: float, source: Node3D = null) -> void:
	if state == State.DESTROYED:
		return

	current_health -= amount
	damage_taken.emit(self, amount, source)

	if current_health <= max_health * 0.3:
		_request_rtb("Heavy damage")

	if current_health <= 0.0:
		_destroy()


func _destroy() -> void:
	state = State.DESTROYED
	gunship_destroyed.emit(self)

	# Fall and explode
	var tween := create_tween()
	tween.tween_property(self, "global_position:y", 0.0, 3.0)
	tween.tween_callback(queue_free)


func get_ammo_status() -> Dictionary:
	return {
		"rockets": rockets_remaining,
		"rockets_max": rocket_pods * rockets_per_pod,
		"minigun": minigun_ammo_remaining,
		"minigun_max": minigun_ammo,
	}


func get_state_name() -> String:
	return State.keys()[state]


func is_available() -> bool:
	return state in [State.IDLE, State.LANDED, State.PATROLLING]


func has_ammo() -> bool:
	return rockets_remaining > 0 or minigun_ammo_remaining > 0
