class_name Artillery extends CharacterBody3D
## Artillery - Howitzer/heavy gun with deploy/limber state machine.
##
## Two variants controlled by SquadData.can_redeploy:
##   - Mobile (M102 105mm, mobile mortars): can pack up, drive to a new
##     position, and deploy again. Slower to fire while limbered.
##   - Static (fortress guns, dug-in pieces): cannot redeploy. Built in place,
##     destroyed in place.
##
## Workflow:
##   1. Player issues move order -> artillery enters LIMBERING state (3s)
##   2. Once limbered, drives slowly to target position
##   3. On arrival -> DEPLOYING state (5s)
##   4. Once DEPLOYED -> can fire indirect at marked targets
##
## Indirect fire uses VOLLEY pattern with high-arc projectile trajectory
## (set on the weapon definition). CombatManager routes the call.

const SquadDataScript = preload("res://battle_system/data/squad_data.gd")
const VietnamWeaponDataScript = preload("res://battle_system/data/vietnam_weapon_data.gd")

signal state_changed(new_state: int)
signal fired_volley(target_pos: Vector3, rounds: int)
signal deployment_complete()
signal limber_complete()
signal artillery_destroyed(piece: Artillery)
signal path_blocked_by_slope(position: Vector3, slope: float)

enum State { PACKED, LIMBERING, MOVING, DEPLOYING, DEPLOYED, FIRING, DESTROYED }

@export var data: Resource  # SquadData
@export var weapon_id: String = "m102_howitzer"
@export var limber_time: float = 3.0     # Time to pack up
@export var deploy_time: float = 5.0     # Time to set up after arrival
@export var min_indirect_range: float = 100.0   # Below this, cannot indirect-fire
@export var crew_size: int = 8
@export var rounds_per_volley: int = 3

## State
var state: State = State.DEPLOYED  # Start deployed by default
var current_health: float = 400.0
var max_health: float = 400.0
var move_target: Vector3 = Vector3.ZERO
var fire_target: Vector3 = Vector3.ZERO
var has_move_order: bool = false
var has_fire_mission: bool = false
var is_player_controlled: bool = true
var crew_remaining: int = 8
var _state_timer: float = 0.0
var _fire_cooldown: float = 0.0
var current_ammo: int = 30  # Shells per piece

## Slope cache (matches squad/tank pattern)
const SLOPE_QUERY_INTERVAL: float = 0.1
var _slope_query_timer: float = 0.0
var _cached_slope: float = 0.0

## Visual
var _barrel: Node3D = null
var _base: Node3D = null


func _ready() -> void:
	add_to_group("artillery")
	add_to_group("all_units")
	if is_player_controlled:
		add_to_group("player_units")
		add_to_group("selectable_units")
	else:
		add_to_group("enemy_units")

	if data:
		max_health = data.get_total_health()
		current_health = max_health
		# Honor static-piece flag
		if not data.can_redeploy:
			# Static pieces can never leave their spot
			pass

	crew_remaining = crew_size
	_build_placeholder_visual()


func _build_placeholder_visual() -> void:
	_base = Node3D.new()
	_base.name = "Base"
	add_child(_base)

	# Trail legs (splayed)
	for i in 2:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.2, 0.2, 2.5)
		leg.mesh = leg_mesh
		leg.rotation_degrees = Vector3(0, 25 if i == 0 else -25, 0)
		leg.position = Vector3(0, 0.3, -1.0)
		_base.add_child(leg)

	# Wheels
	for i in 2:
		var wheel := MeshInstance3D.new()
		var wheel_mesh := CylinderMesh.new()
		wheel_mesh.top_radius = 0.5
		wheel_mesh.bottom_radius = 0.5
		wheel_mesh.height = 0.2
		wheel.mesh = wheel_mesh
		wheel.rotation_degrees = Vector3(0, 0, 90)
		wheel.position = Vector3(-1.2 if i == 0 else 1.2, 0.5, 0)
		_base.add_child(wheel)

	# Barrel (rotates for elevation)
	_barrel = Node3D.new()
	_barrel.name = "Barrel"
	_barrel.position = Vector3(0, 0.8, 0)
	add_child(_barrel)

	var barrel_mesh_node := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.15
	bm.bottom_radius = 0.18
	bm.height = 3.5
	barrel_mesh_node.mesh = bm
	barrel_mesh_node.rotation_degrees = Vector3(75, 0, 0)  # High-angle artillery
	barrel_mesh_node.position = Vector3(0, 0.3, 1.0)
	_barrel.add_child(barrel_mesh_node)

	# Material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data.get_faction_color() if data else Color(0.3, 0.35, 0.25)
	for child in _base.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = mat
	barrel_mesh_node.material_override = mat

	# Collision
	var coll := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 1.5, 4.0)
	coll.shape = box
	coll.position.y = 0.75
	add_child(coll)
	collision_layer = 2


func _physics_process(delta: float) -> void:
	if state == State.DESTROYED:
		return

	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta

	match state:
		State.LIMBERING:
			_process_limbering(delta)
		State.MOVING:
			_process_movement(delta)
		State.DEPLOYING:
			_process_deploying(delta)
		State.DEPLOYED, State.FIRING:
			_process_fire_mission(delta)
		_:
			pass


func _process_limbering(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_set_state(State.MOVING)
		limber_complete.emit()


func _process_deploying(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_set_state(State.DEPLOYED)
		deployment_complete.emit()


func _process_movement(delta: float) -> void:
	var direction: Vector3 = move_target - global_position
	direction.y = 0
	var distance: float = direction.length()

	if distance < 1.0:
		velocity = Vector3.ZERO
		has_move_order = false
		# Begin deploying at destination
		_set_state(State.DEPLOYING)
		_state_timer = deploy_time
		return

	var seek_direction: Vector3 = direction.normalized()

	_slope_query_timer -= delta
	if _slope_query_timer <= 0.0:
		_slope_query_timer = SLOPE_QUERY_INTERVAL
		_cached_slope = _sample_slope_ahead(seek_direction)

	var speed: float
	if data and data.has_method("get_speed_at_slope"):
		speed = data.get_speed_at_slope(_cached_slope) * 0.5  # Limbered = half speed
	else:
		speed = (data.move_speed if data else 4.0) * 0.5

	if speed <= 0.0:
		velocity = Vector3.ZERO
		has_move_order = false
		_set_state(State.DEPLOYING)  # Try to deploy where we are
		_state_timer = deploy_time
		path_blocked_by_slope.emit(global_position, _cached_slope)
		return

	# Rotate hull toward target
	var target_yaw: float = atan2(seek_direction.x, seek_direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, delta * 1.5)

	var forward: Vector3 = Vector3(sin(rotation.y), 0, cos(rotation.y))
	velocity = forward * speed
	_snap_to_terrain()
	move_and_slide()


func _process_fire_mission(_delta: float) -> void:
	if not has_fire_mission:
		return
	if current_ammo <= 0:
		has_fire_mission = false
		return
	if _fire_cooldown > 0.0:
		return
	if crew_remaining < 2:
		# Crew too depleted to operate the piece
		return

	_fire_volley()


func _fire_volley() -> void:
	# Validate range
	var dist: float = global_position.distance_to(fire_target)
	if dist < min_indirect_range:
		return  # Too close for indirect fire

	if CombatManager:
		# Fake a target node at the impact point; CombatManager.fire_weapon needs a target
		# but for VOLLEY pattern it uses target_pos directly. We pass self as a dummy target.
		var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(weapon_id)
		if not weapon:
			return
		# Fire rounds_per_volley shells via projectile pool directly
		if CombatManager.projectile_pool:
			var attacker_faction: int = data.faction if data else 0
			for i in rounds_per_volley:
				# Slight spread on impact for realism
				var spread := Vector3(randf_range(-5.0, 5.0), 0, randf_range(-5.0, 5.0))
				CombatManager.projectile_pool.fire_weapon(
					weapon_id, self, fire_target + spread, attacker_faction
				)
				current_ammo -= 1
				if current_ammo <= 0:
					break

		_fire_cooldown = 60.0 / weapon.rate_of_fire if weapon.rate_of_fire > 0 else 10.0

	fired_volley.emit(fire_target, rounds_per_volley)
	_set_state(State.FIRING)
	# Return to DEPLOYED after a brief firing animation window
	var t := get_tree().create_timer(2.0)
	t.timeout.connect(func():
		if state == State.FIRING:
			_set_state(State.DEPLOYED)
	)


func _sample_slope_ahead(move_dir: Vector3) -> float:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if not terrain:
		return 0.0
	var probe_pos: Vector3 = global_position + move_dir * 2.0
	if terrain.has_method("get_normal_at"):
		var normal: Vector3 = terrain.get_normal_at(probe_pos)
		return clampf(1.0 - normal.y, 0.0, 1.0)
	return 0.0


func _snap_to_terrain() -> void:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		global_position.y = terrain.get_height_at(global_position)


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(int(new_state))


# =============================================================================
# PUBLIC API
# =============================================================================

## Issue a move order. Mobile pieces will limber, move, then deploy at target.
## Static pieces refuse.
func move_to(target: Vector3) -> void:
	if data and not data.can_redeploy:
		print("[Artillery] Cannot move - this is a static piece.")
		return
	if state == State.DEPLOYED or state == State.FIRING:
		move_target = target
		has_move_order = true
		_set_state(State.LIMBERING)
		_state_timer = limber_time
	elif state == State.MOVING:
		# Update destination mid-move
		move_target = target


## Attack-move: for artillery, this is the same as regular move (deploys at target)
func attack_move_to(target: Vector3) -> void:
	move_to(target)


## Order a fire mission at a world position.
func fire_mission(target_pos: Vector3) -> bool:
	if state != State.DEPLOYED and state != State.FIRING:
		return false
	if current_ammo <= 0:
		return false
	var dist: float = global_position.distance_to(target_pos)
	if dist < min_indirect_range:
		return false
	fire_target = target_pos
	has_fire_mission = true
	return true


## Cancel any pending fire mission.
func stop_fire_mission() -> void:
	has_fire_mission = false


func take_damage(amount: float, source: Node = null) -> void:
	# Crew can be killed individually
	if randf() < 0.3:
		crew_remaining = max(0, crew_remaining - 1)
	var armor_val: float = data.armor if data else 5.0
	var reduction: float = clampf(armor_val * 0.02, 0.0, 0.7)
	current_health = max(0.0, current_health - amount * (1.0 - reduction))
	if current_health <= 0.0 or crew_remaining <= 0:
		_destroy()


func _destroy() -> void:
	_set_state(State.DESTROYED)
	artillery_destroyed.emit(self)
	var t := get_tree().create_timer(5.0)
	t.timeout.connect(queue_free)


func is_static() -> bool:
	return data and not data.can_redeploy


func get_current_state_name() -> String:
	return State.keys()[state]
