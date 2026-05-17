class_name GunshipBehavior extends Node
## GunshipBehavior - Attaches to a Helicopter to give it attack capability.
##
## Add as a child of a Helicopter node (heli_type = UH1_GUNSHIP or AH1_COBRA).
## Provides three action types:
##   - rocket_run(target): single high-explosive run, exits engagement
##   - mg_strafe(target): sustained MG fire while orbiting target
##   - patrol_area(center, radius): orbit a circular area, engage any
##     enemy_units that enter detection range
##
## Uses ffar_rocket and m134_minigun weapon definitions for projectiles.

signal rocket_run_started(target: Vector3)
signal rocket_run_completed()
signal strafe_started(target: Node3D)
signal strafe_completed()
signal patrol_started(center: Vector3, radius: float)
signal target_acquired(target: Node3D)

enum Action { IDLE, ROCKET_RUN, STRAFE, PATROL, RETURN }

@export var rocket_id: String = "ffar_rocket"
@export var mg_id: String = "m134_minigun"
@export var detection_range: float = 200.0
@export var engagement_range: float = 150.0
@export var strafe_orbit_radius: float = 80.0
@export var strafe_orbit_speed: float = 25.0  # m/s
@export var rocket_run_descent_alt: float = 35.0  # Drop to this altitude during run
@export var rockets_per_run: int = 6
@export var max_rockets: int = 38
@export var max_mg_ammo: int = 4000

## State
var action: Action = Action.IDLE
var helicopter: Node = null  # The Helicopter node we're attached to
var target_node: Node3D = null
var target_position: Vector3 = Vector3.ZERO
var patrol_center: Vector3 = Vector3.ZERO
var patrol_radius: float = 100.0
var rockets_remaining: int = 38
var mg_ammo_remaining: int = 4000
var _strafe_angle: float = 0.0
var _run_phase: int = 0  # 0=approach, 1=fire, 2=climb-out
var _fire_cooldown: float = 0.0
var _scan_timer: float = 0.0


func _ready() -> void:
	# Parent must be a Helicopter
	helicopter = get_parent()
	if not helicopter:
		push_warning("[GunshipBehavior] No parent helicopter found")
		return
	rockets_remaining = max_rockets
	mg_ammo_remaining = max_mg_ammo


func _physics_process(delta: float) -> void:
	if not helicopter or not is_instance_valid(helicopter):
		return

	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta

	match action:
		Action.ROCKET_RUN:
			_process_rocket_run(delta)
		Action.STRAFE:
			_process_strafe(delta)
		Action.PATROL:
			_process_patrol(delta)
		Action.RETURN:
			pass  # Helicopter handles its own return-to-base


func _process_rocket_run(delta: float) -> void:
	if rockets_remaining <= 0:
		action = Action.IDLE
		return

	match _run_phase:
		0:  # Approach
			helicopter.global_position += (target_position - helicopter.global_position).normalized() * helicopter.max_speed * delta
			# Descend to attack altitude
			helicopter.global_position.y = lerp(helicopter.global_position.y, rocket_run_descent_alt, delta * 0.5)
			var horiz_dist: float = Vector2(target_position.x - helicopter.global_position.x, target_position.z - helicopter.global_position.z).length()
			if horiz_dist < 100.0:
				_run_phase = 1
		1:  # Fire rockets
			if _fire_cooldown <= 0.0 and rockets_remaining > 0:
				_fire_rocket()
			# Stop firing after rockets_per_run
			if rockets_remaining <= max_rockets - rockets_per_run:
				_run_phase = 2
		2:  # Climb out
			helicopter.global_position += helicopter.basis.z * helicopter.max_speed * delta
			helicopter.global_position.y = lerp(helicopter.global_position.y, helicopter.cruise_altitude, delta * 0.8)
			if helicopter.global_position.y >= helicopter.cruise_altitude - 3.0:
				action = Action.IDLE
				_run_phase = 0
				rocket_run_completed.emit()


func _fire_rocket() -> void:
	if not CombatManager or not CombatManager.projectile_pool:
		return
	# Slight spread per rocket
	var spread := Vector3(randf_range(-6.0, 6.0), 0, randf_range(-6.0, 6.0))
	CombatManager.projectile_pool.fire_weapon(rocket_id, helicopter, target_position + spread, 0)
	rockets_remaining -= 1
	_fire_cooldown = 0.25


func _process_strafe(delta: float) -> void:
	if not is_instance_valid(target_node):
		action = Action.IDLE
		strafe_completed.emit()
		return
	if mg_ammo_remaining <= 0:
		action = Action.IDLE
		strafe_completed.emit()
		return

	# Orbit around target at strafe_orbit_radius
	_strafe_angle += (strafe_orbit_speed / strafe_orbit_radius) * delta
	var target_pos: Vector3 = target_node.global_position
	var orbit_pos: Vector3 = target_pos + Vector3(cos(_strafe_angle) * strafe_orbit_radius, helicopter.cruise_altitude, sin(_strafe_angle) * strafe_orbit_radius)
	helicopter.global_position = helicopter.global_position.lerp(orbit_pos, delta * 1.5)

	# Face target
	var to_target: Vector3 = target_pos - helicopter.global_position
	to_target.y = 0
	helicopter.rotation.y = atan2(to_target.x, to_target.z)

	# Fire MG
	if _fire_cooldown <= 0.0:
		_fire_mg()


func _fire_mg() -> void:
	if not CombatManager or not CombatManager.projectile_pool:
		return
	if not is_instance_valid(target_node):
		return
	# Several rounds per call (minigun = high RoF)
	for i in 8:
		var spread := Vector3(randf_range(-2.0, 2.0), randf_range(-1.0, 1.0), randf_range(-2.0, 2.0))
		CombatManager.projectile_pool.fire_weapon(mg_id, helicopter, target_node.global_position + spread, 0)
	mg_ammo_remaining -= 8
	_fire_cooldown = 0.1


func _process_patrol(delta: float) -> void:
	# Orbit patrol center
	_strafe_angle += (strafe_orbit_speed / max(patrol_radius, 1.0)) * delta
	var orbit_pos: Vector3 = patrol_center + Vector3(cos(_strafe_angle) * patrol_radius, helicopter.cruise_altitude, sin(_strafe_angle) * patrol_radius)
	helicopter.global_position = helicopter.global_position.lerp(orbit_pos, delta * 1.0)

	# Scan for targets every 0.5s
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.5
		var nearest: Node3D = _find_nearest_enemy()
		if nearest:
			target_acquired.emit(nearest)
			# Auto-engage with MG strafe
			strafe(nearest)


func _find_nearest_enemy() -> Node3D:
	var enemies := helicopter.get_tree().get_nodes_in_group("enemy_units")
	var nearest: Node3D = null
	var nearest_dist: float = detection_range
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var n: Node3D = e as Node3D
		if not n:
			continue
		var d: float = helicopter.global_position.distance_to(n.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = n
	return nearest


# =============================================================================
# PUBLIC API
# =============================================================================

func rocket_run(target_pos: Vector3) -> bool:
	if rockets_remaining <= 0:
		return false
	target_position = target_pos
	action = Action.ROCKET_RUN
	_run_phase = 0
	rocket_run_started.emit(target_pos)
	return true


func strafe(target: Node3D) -> bool:
	if mg_ammo_remaining <= 0:
		return false
	target_node = target
	action = Action.STRAFE
	_strafe_angle = randf_range(0.0, TAU)
	strafe_started.emit(target)
	return true


func patrol_area(center: Vector3, radius: float = 100.0) -> void:
	patrol_center = center
	patrol_radius = radius
	action = Action.PATROL
	_strafe_angle = 0.0
	patrol_started.emit(center, radius)


func stop_combat() -> void:
	action = Action.IDLE
	target_node = null


func get_ammo_summary() -> Dictionary:
	return {
		"rockets": rockets_remaining,
		"mg": mg_ammo_remaining,
	}
