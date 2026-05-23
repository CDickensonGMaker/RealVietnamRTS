class_name Airplane extends CharacterBody3D
## Airplane - Fixed-wing close air support aircraft.
##
## Differs from Helicopter:
##   - Cannot hover (must maintain min airspeed)
##   - Performs attack RUNS rather than loitering
##   - Returns to airport for refuel/rearm
##   - Has multiple ordnance types (bombs, napalm, rockets, cannon)
##
## States:
##   IDLE_AT_AIRPORT: parked, refueling/rearming
##   TAKING_OFF: climbing from runway
##   PATROLLING: in transit / on station
##   ATTACK_RUN: diving toward a target with selected ordnance
##   RETURNING: heading back to airport
##   LANDING: descent to runway
##
## Mounts use existing weapon definitions: mk82_bomb, napalm, ffar_rocket,
## cannon_20mm. CombatManager handles the actual projectile spawning.

const VietnamWeaponDataScript = preload("res://battle_system/data/vietnam_weapon_data.gd")

signal took_off()
signal landed_at_airport()
signal attack_run_started(target_pos: Vector3, ordnance: String)
signal attack_run_completed()
signal ordnance_depleted()
signal refuel_complete()

enum State { IDLE_AT_AIRPORT, TAKING_OFF, PATROLLING, ATTACK_RUN, RETURNING, LANDING, DESTROYED }
enum Ordnance { BOMBS, NAPALM, ROCKETS, CANNON }

@export var max_speed: float = 120.0      # m/s (cruise)
@export var stall_speed: float = 40.0
@export var cruise_altitude: float = 80.0
@export var attack_altitude: float = 30.0  # Pull-out altitude
@export var dive_angle_degrees: float = 30.0
@export var turn_rate_deg: float = 30.0    # Plane turns slowly
@export var max_health: float = 250.0

## Loadout (counts of each ordnance)
@export var bomb_count: int = 4
@export var napalm_count: int = 2
@export var rocket_pods: int = 19  # FFAR rockets total
@export var cannon_rounds: int = 200

## Weapon IDs for ordnance types
@export var cannon_weapon_id: String = "cannon_20mm"  # Override for M61 Vulcan etc.

## Fuel/rearm
@export var max_fuel: float = 100.0
@export var fuel_burn_rate: float = 1.0   # Per second airborne
@export var refuel_time: float = 30.0
@export var rearm_time: float = 45.0      # Concurrent with refuel; max of the two

## Ownership
var is_player_controlled: bool = true

## State
var state: State = State.IDLE_AT_AIRPORT
var current_health: float = 250.0
var current_fuel: float = 100.0
var bombs_remaining: int = 4
var napalm_remaining: int = 2
var rockets_remaining: int = 19
var cannon_remaining: int = 200

## Mission targets
var airport_position: Vector3 = Vector3.ZERO
var airport_heading: float = 0.0  # Runway direction (radians)
var patrol_target: Vector3 = Vector3.ZERO
var attack_target_pos: Vector3 = Vector3.ZERO
var selected_ordnance: Ordnance = Ordnance.BOMBS
var has_patrol_order: bool = false

## Flight mechanics
var current_speed: float = 0.0
var _service_timer: float = 0.0
var _attack_run_phase: int = 0  # 0=approach, 1=dive, 2=release, 3=climb out

## Visual ordnance tracking (from 3D model)
var _bomb_nodes: Array[Node3D] = []
var _napalm_nodes: Array[Node3D] = []
var _rocket_nodes: Array[Node3D] = []
var _ordnance_drop_index: Dictionary = {"bombs": 0, "napalm": 0, "rockets": 0}


func _ready() -> void:
	add_to_group("airplanes")
	add_to_group("aircraft")
	add_to_group("all_units")
	if is_player_controlled:
		add_to_group("player_units")
		add_to_group("selectable_units")
	else:
		add_to_group("enemy_units")
	current_health = max_health
	bombs_remaining = bomb_count
	napalm_remaining = napalm_count
	rockets_remaining = rocket_pods
	cannon_remaining = cannon_rounds
	_scan_for_ordnance_nodes()
	_build_placeholder_visual()


## Scan child nodes to find visual ordnance from the 3D model.
## Ordnance nodes should be named: Ord_L1_Mk82, Ord_R4_Napalm, etc.
func _scan_for_ordnance_nodes() -> void:
	_bomb_nodes.clear()
	_napalm_nodes.clear()
	_rocket_nodes.clear()

	for child in get_children():
		_scan_node_recursive(child)

	# Update counts based on visual ordnance if present
	if _bomb_nodes.size() > 0:
		bombs_remaining = _bomb_nodes.size()
		bomb_count = bombs_remaining
	if _napalm_nodes.size() > 0:
		napalm_remaining = _napalm_nodes.size()
		napalm_count = napalm_remaining
	if _rocket_nodes.size() > 0:
		rockets_remaining = _rocket_nodes.size()
		rocket_pods = rockets_remaining

	if _bomb_nodes.size() + _napalm_nodes.size() + _rocket_nodes.size() > 0:
		print("Airplane: Found visual ordnance - %d bombs, %d napalm, %d rockets" % [
			_bomb_nodes.size(), _napalm_nodes.size(), _rocket_nodes.size()])


func _scan_node_recursive(node: Node) -> void:
	if node is Node3D:
		var n := node.name.to_lower()
		if n.contains("ord_") or n.contains("bomb") or n.contains("mk8") or n.contains("napalm") or n.contains("rocket"):
			if n.contains("napalm") or n.contains("blu"):
				_napalm_nodes.append(node as Node3D)
			elif n.contains("rocket") or n.contains("lau"):
				_rocket_nodes.append(node as Node3D)
			else:
				_bomb_nodes.append(node as Node3D)

	for child in node.get_children():
		_scan_node_recursive(child)


func _build_placeholder_visual() -> void:
	# Fuselage
	var fuselage := MeshInstance3D.new()
	var fus_mesh := BoxMesh.new()
	fus_mesh.size = Vector3(1.2, 1.2, 8.0)
	fuselage.mesh = fus_mesh
	add_child(fuselage)

	# Wings
	var wings := MeshInstance3D.new()
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(10.0, 0.2, 1.8)
	wings.mesh = wing_mesh
	wings.position = Vector3(0, 0.2, -0.5)
	add_child(wings)

	# Tail
	var tail := MeshInstance3D.new()
	var tail_mesh := BoxMesh.new()
	tail_mesh.size = Vector3(0.2, 1.6, 1.2)
	tail.mesh = tail_mesh
	tail.position = Vector3(0, 0.8, -3.5)
	add_child(tail)

	# Material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.4, 0.3)  # Olive drab
	fuselage.material_override = mat
	wings.material_override = mat
	tail.material_override = mat

	# Collision
	var coll := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 1.5, 8.0)
	coll.shape = box
	add_child(coll)
	collision_layer = 16  # Air units


func _physics_process(delta: float) -> void:
	if state == State.DESTROYED:
		return

	# Fuel burn (everything except idle-at-airport)
	if state != State.IDLE_AT_AIRPORT:
		current_fuel = max(0.0, current_fuel - fuel_burn_rate * delta)
		if current_fuel <= 0.0 and state != State.LANDING:
			# Force return to base
			start_return_to_base()

	match state:
		State.IDLE_AT_AIRPORT:
			_process_refuel(delta)
		State.TAKING_OFF:
			_process_takeoff(delta)
		State.PATROLLING:
			_process_patrol(delta)
		State.ATTACK_RUN:
			_process_attack_run(delta)
		State.RETURNING:
			_process_return(delta)
		State.LANDING:
			_process_landing(delta)


func _process_refuel(delta: float) -> void:
	_service_timer += delta
	var refuel_progress: float = clampf(_service_timer / refuel_time, 0.0, 1.0)
	current_fuel = lerp(0.0, max_fuel, refuel_progress)
	var rearm_progress: float = clampf(_service_timer / rearm_time, 0.0, 1.0)
	# Rearm fills ordnance over time
	bombs_remaining = int(lerp(0.0, float(bomb_count), rearm_progress))
	napalm_remaining = int(lerp(0.0, float(napalm_count), rearm_progress))
	rockets_remaining = int(lerp(0.0, float(rocket_pods), rearm_progress))
	cannon_remaining = int(lerp(0.0, float(cannon_rounds), rearm_progress))
	if _service_timer >= max(refuel_time, rearm_time):
		_service_timer = 0.0
		_restore_ordnance_visuals()
		refuel_complete.emit()


func _process_takeoff(delta: float) -> void:
	# Accelerate down runway, then climb
	current_speed = min(current_speed + 30.0 * delta, max_speed)
	var forward: Vector3 = Vector3(sin(airport_heading), 0, cos(airport_heading))
	global_position += forward * current_speed * delta
	# Climb
	if global_position.y < cruise_altitude:
		global_position.y += 20.0 * delta
	rotation.y = airport_heading

	if global_position.y >= cruise_altitude - 5.0 and current_speed >= stall_speed:
		state = State.PATROLLING
		took_off.emit()


func _process_patrol(delta: float) -> void:
	if not has_patrol_order:
		return
	var to_target: Vector3 = patrol_target - global_position
	to_target.y = 0
	var dist: float = to_target.length()

	if dist < 30.0:
		# Reached patrol point - loiter (just continue forward)
		has_patrol_order = false

	if dist > 0.1:
		var target_yaw: float = atan2(to_target.x, to_target.z)
		var max_step: float = deg_to_rad(turn_rate_deg) * delta
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(max_step / max(0.001, abs(angle_difference(rotation.y, target_yaw))), 0.0, 1.0))

	var forward: Vector3 = Vector3(sin(rotation.y), 0, cos(rotation.y))
	global_position += forward * max_speed * delta
	# Maintain cruise altitude
	global_position.y = lerp(global_position.y, cruise_altitude, delta * 0.5)


func _process_attack_run(delta: float) -> void:
	var to_target_flat: Vector3 = attack_target_pos - global_position
	to_target_flat.y = 0
	var horizontal_dist: float = to_target_flat.length()

	match _attack_run_phase:
		0:  # Approach: turn toward target at altitude
			if horizontal_dist > 80.0:
				var target_yaw: float = atan2(to_target_flat.x, to_target_flat.z)
				rotation.y = lerp_angle(rotation.y, target_yaw, delta * 1.5)
				var forward: Vector3 = Vector3(sin(rotation.y), 0, cos(rotation.y))
				global_position += forward * max_speed * delta
				global_position.y = cruise_altitude
			else:
				_attack_run_phase = 1
		1:  # Dive
			var dive: Vector3 = (attack_target_pos - global_position).normalized()
			global_position += dive * max_speed * delta
			if global_position.y <= attack_altitude or horizontal_dist < 10.0:
				_attack_run_phase = 2
				_release_ordnance()
		2:  # Release done, transition immediately
			_attack_run_phase = 3
		3:  # Climb out
			global_position.y = lerp(global_position.y, cruise_altitude, delta * 0.8)
			var forward: Vector3 = Vector3(sin(rotation.y), 0, cos(rotation.y))
			global_position += forward * max_speed * delta
			if global_position.y >= cruise_altitude - 5.0:
				state = State.PATROLLING
				attack_run_completed.emit()
				_attack_run_phase = 0


func _release_ordnance() -> void:
	match selected_ordnance:
		Ordnance.BOMBS:
			if bombs_remaining > 0:
				var drop_pos := _hide_next_ordnance_visual("bombs")
				_spawn_bomb_projectile(drop_pos if drop_pos != Vector3.ZERO else global_position)
				bombs_remaining -= 1
		Ordnance.NAPALM:
			if napalm_remaining > 0:
				var drop_pos := _hide_next_ordnance_visual("napalm")
				# Napalm runs lay a strip - drop several over a line
				var strip_dir: Vector3 = Vector3(sin(rotation.y), 0, cos(rotation.y))
				var base_pos := drop_pos if drop_pos != Vector3.ZERO else global_position
				for i in 5:
					var offset_pos: Vector3 = base_pos + strip_dir * float(i - 2) * 15.0
					_spawn_napalm_projectile(offset_pos)
				napalm_remaining -= 1
		Ordnance.ROCKETS:
			# Fire a salvo of 6 rockets
			var salvo: int = mini(6, rockets_remaining)
			for i in salvo:
				var drop_pos := _hide_next_ordnance_visual("rockets")
				var spread := Vector3(randf_range(-8.0, 8.0), 0, randf_range(-8.0, 8.0))
				_spawn_rocket_projectile((drop_pos if drop_pos != Vector3.ZERO else global_position) + spread)
			rockets_remaining -= salvo
		Ordnance.CANNON:
			# Strafe pass - no visual ordnance for cannon
			var strafe_count: int = mini(20, cannon_remaining)
			for i in strafe_count:
				var fwd_offset: float = float(i) * 3.0
				var fwd: Vector3 = Vector3(sin(rotation.y), 0, cos(rotation.y))
				_spawn_cannon_projectile(attack_target_pos + fwd * fwd_offset)
			cannon_remaining -= strafe_count

	if bombs_remaining + napalm_remaining + rockets_remaining + cannon_remaining <= 0:
		ordnance_depleted.emit()
		start_return_to_base()


## Hide the next visual ordnance node and return its world position.
func _hide_next_ordnance_visual(ordnance_type: String) -> Vector3:
	var nodes: Array[Node3D]
	var index_key: String = ordnance_type

	match ordnance_type:
		"bombs":
			nodes = _bomb_nodes
		"napalm":
			nodes = _napalm_nodes
		"rockets":
			nodes = _rocket_nodes
		_:
			return Vector3.ZERO

	var idx: int = _ordnance_drop_index.get(index_key, 0)
	if idx >= nodes.size():
		return Vector3.ZERO

	# Find next visible ordnance
	while idx < nodes.size():
		var node := nodes[idx]
		if node and node.visible:
			var world_pos := node.global_position
			node.visible = false
			_ordnance_drop_index[index_key] = idx + 1
			return world_pos
		idx += 1

	return Vector3.ZERO


## Restore all ordnance visuals after rearming.
func _restore_ordnance_visuals() -> void:
	for node in _bomb_nodes:
		if node:
			node.visible = true
	for node in _napalm_nodes:
		if node:
			node.visible = true
	for node in _rocket_nodes:
		if node:
			node.visible = true
	_ordnance_drop_index = {"bombs": 0, "napalm": 0, "rockets": 0}


## Spawn bomb projectile with physics-like falling
func _spawn_bomb_projectile(start_pos: Vector3) -> void:
	# Calculate plane's forward velocity for bomb inheritance
	var plane_velocity: Vector3 = Vector3(sin(rotation.y), 0, cos(rotation.y)) * current_speed

	if CombatManager and CombatManager.projectile_pool:
		CombatManager.projectile_pool.fire_weapon_with_velocity("mk82_bomb", self, attack_target_pos, 0, plane_velocity)
	else:
		# Fallback: emit signal for manual handling
		BattleSignals.bomb_dropped.emit(start_pos, attack_target_pos, plane_velocity)


func _spawn_napalm_projectile(start_pos: Vector3) -> void:
	# Napalm also inherits plane velocity
	var plane_velocity: Vector3 = Vector3(sin(rotation.y), 0, cos(rotation.y)) * current_speed

	if CombatManager and CombatManager.projectile_pool:
		CombatManager.projectile_pool.fire_weapon_with_velocity("napalm", self, start_pos, 0, plane_velocity)


func _spawn_rocket_projectile(target_pos: Vector3) -> void:
	if CombatManager and CombatManager.projectile_pool:
		CombatManager.projectile_pool.fire_weapon("ffar_rocket", self, target_pos, 0)


func _spawn_cannon_projectile(target_pos: Vector3) -> void:
	if CombatManager and CombatManager.projectile_pool:
		CombatManager.projectile_pool.fire_weapon(cannon_weapon_id, self, target_pos, 0)


func _process_return(delta: float) -> void:
	var to_airport: Vector3 = airport_position - global_position
	to_airport.y = 0
	var dist: float = to_airport.length()

	if dist < 60.0:
		state = State.LANDING
		return

	var target_yaw: float = atan2(to_airport.x, to_airport.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, delta * 1.5)
	var forward: Vector3 = Vector3(sin(rotation.y), 0, cos(rotation.y))
	global_position += forward * max_speed * delta
	global_position.y = lerp(global_position.y, cruise_altitude, delta * 0.5)


func _process_landing(delta: float) -> void:
	var to_airport: Vector3 = airport_position - global_position
	to_airport.y = 0
	var dist: float = to_airport.length()

	# Approach descent
	rotation.y = lerp_angle(rotation.y, airport_heading, delta * 2.0)
	var forward: Vector3 = Vector3(sin(rotation.y), 0, cos(rotation.y))
	global_position += forward * lerp(max_speed, stall_speed, 1.0 - clampf(dist / 60.0, 0.0, 1.0)) * delta
	global_position.y = max(airport_position.y, global_position.y - 15.0 * delta)

	if dist < 5.0 and global_position.y <= airport_position.y + 0.5:
		global_position = airport_position
		state = State.IDLE_AT_AIRPORT
		current_speed = 0.0
		_service_timer = 0.0
		landed_at_airport.emit()


# =============================================================================
# PUBLIC API
# =============================================================================

## Set the home airport. Called once at scene setup.
func set_airport(pos: Vector3, runway_heading_rad: float) -> void:
	airport_position = pos
	airport_heading = runway_heading_rad
	if state == State.IDLE_AT_AIRPORT:
		global_position = pos
		rotation.y = runway_heading_rad


## Launch from airport. Fails if not ready.
func take_off() -> bool:
	if state != State.IDLE_AT_AIRPORT:
		return false
	if current_fuel < max_fuel * 0.5:
		return false  # Need at least half tank
	state = State.TAKING_OFF
	current_speed = 0.0
	return true


## Order patrol to a point. Plane will fly there and loiter.
func patrol_to(target: Vector3) -> void:
	patrol_target = target
	has_patrol_order = true
	if state == State.PATROLLING:
		pass  # Just updated target
	elif state == State.IDLE_AT_AIRPORT:
		if take_off():
			pass


## Order an attack run on a target with the given ordnance type.
func attack_position(target: Vector3, ordnance: Ordnance) -> bool:
	if state != State.PATROLLING:
		return false
	# Check ordnance availability
	var have_ordnance: bool = false
	match ordnance:
		Ordnance.BOMBS: have_ordnance = bombs_remaining > 0
		Ordnance.NAPALM: have_ordnance = napalm_remaining > 0
		Ordnance.ROCKETS: have_ordnance = rockets_remaining > 0
		Ordnance.CANNON: have_ordnance = cannon_remaining > 0
	if not have_ordnance:
		return false
	attack_target_pos = target
	selected_ordnance = ordnance
	_attack_run_phase = 0
	state = State.ATTACK_RUN
	attack_run_started.emit(target, Ordnance.keys()[ordnance])
	return true


func start_return_to_base() -> void:
	if state == State.IDLE_AT_AIRPORT or state == State.LANDING:
		return
	state = State.RETURNING


func get_state_name() -> String:
	return State.keys()[state]


func get_ordnance_summary() -> Dictionary:
	return {
		"bombs": bombs_remaining,
		"napalm": napalm_remaining,
		"rockets": rockets_remaining,
		"cannon": cannon_remaining,
		"fuel": current_fuel,
	}
