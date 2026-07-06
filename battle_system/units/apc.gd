class_name APC extends CharacterBody3D
## APC - Armored Personnel Carrier (M113)
## Transports infantry squads and provides fire support with .50 cal MG.
## Uses Men of War style component damage system.
##
## Serves Pillar 3 (Physical Supply Chains) - APCs are the backbone of
## mechanized doctrine, moving troops between firebases.

const SquadDataScript = preload("res://battle_system/data/squad_data.gd")
const VietnamWeaponDataScript = preload("res://battle_system/data/vietnam_weapon_data.gd")
const VehicleComponentScript = preload("res://battle_system/units/vehicle_component.gd")

signal passengers_loaded(apc: APC, count: int)
signal passengers_unloaded(apc: APC, passengers: Array[Node3D])
signal apc_destroyed(apc: APC)
signal component_hit(component_type: int, damage: float)
signal turret_rotated(angle_degrees: float)
signal fired_mg(target_pos: Vector3)
signal path_blocked_by_slope(position: Vector3, slope: float)

enum State { IDLE, MOVING, COMBAT, LOADING, UNLOADING, DESTROYED }
enum APCVariant { M113_STANDARD, M113_ACAV, M113_MEDEVAC }

@export var data: Resource  # SquadData
@export var variant: APCVariant = APCVariant.M113_STANDARD
@export var mg_weapon_id: String = "m2_browning"

## Movement characteristics
@export var hull_turn_rate_deg: float = 60.0
@export var turret_turn_rate_deg: float = 120.0
@export var reverse_speed_mult: float = 0.6

## Transport capacity
@export var passenger_capacity: int = 11  # M113 carries 11 + 2 crew

## State
var state: State = State.IDLE
var current_health: float = 250.0
var max_health: float = 250.0
var current_target: Node = null
var move_target: Vector3 = Vector3.ZERO
var has_move_order: bool = false
var is_player_controlled: bool = true

## Passengers
var passengers: Array[Node3D] = []

## Component system (Men of War style)
var vehicle_components: VehicleComponentScript = null

## Turret
var _turret_node: Node3D = null
var _hull_node: Node3D = null
var _turret_target_yaw: float = 0.0
var _mg_cooldown: float = 0.0
var _mg_ammo: int = 500

## Slope cache
const SLOPE_QUERY_INTERVAL: float = 0.1
var _slope_query_timer: float = 0.0
var _cached_slope: float = 0.0

## Attack-move mode
var _attack_move_mode: bool = false
var _attack_move_scan_timer: float = 0.0
const ATTACK_MOVE_SCAN_INTERVAL: float = 0.5

## Loading/unloading timing
const LOAD_TIME: float = 2.0
const UNLOAD_TIME: float = 2.0
var _load_timer: float = 0.0


func _ready() -> void:
	add_to_group("apcs")
	add_to_group("vehicles")
	add_to_group("all_units")
	if is_player_controlled:
		add_to_group("player_units")
		add_to_group("selectable_units")
	else:
		add_to_group("enemy_units")

	_setup_components()
	_apply_data()
	_build_placeholder_visual()


func _setup_components() -> void:
	vehicle_components = VehicleComponentScript.new()

	# M113 armor values (aluminum armor)
	# Front: 38mm, Side: 44mm, Rear: 38mm (against small arms)
	var armor_front: float = 25.0
	var armor_side: float = 20.0
	var armor_rear: float = 15.0

	vehicle_components.setup_apc_components(armor_front, armor_side, armor_rear)
	vehicle_components.setup_apc_crew(1.0)
	vehicle_components.setup_apc_ammo(500)

	# Connect component signals
	vehicle_components.component_damaged.connect(_on_component_damaged)
	vehicle_components.component_destroyed.connect(_on_component_destroyed)
	vehicle_components.crew_member_killed.connect(_on_crew_killed)


func _apply_data() -> void:
	if not data:
		max_health = 250.0
		current_health = 250.0
		return

	max_health = data.get_total_health()
	current_health = max_health

	# Apply variant modifications
	match variant:
		APCVariant.M113_ACAV:
			# ACAV has gun shields and extra MGs
			_mg_ammo = 800
		APCVariant.M113_MEDEVAC:
			# Medevac variant - no weapons, more capacity for wounded
			mg_weapon_id = ""
			passenger_capacity = 15


func _build_placeholder_visual() -> void:
	# Hull
	_hull_node = Node3D.new()
	_hull_node.name = "Hull"
	add_child(_hull_node)

	var hull_mesh := MeshInstance3D.new()
	var hull_box := BoxMesh.new()
	hull_box.size = Vector3(2.7, 1.2, 4.8)  # M113 dimensions
	hull_mesh.mesh = hull_box
	hull_mesh.position.y = 0.8

	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = data.get_faction_color() if data else Color(0.35, 0.4, 0.25)
	hull_mesh.material_override = hull_mat
	_hull_node.add_child(hull_mesh)

	# Sloped front
	var front_slope := MeshInstance3D.new()
	var slope_mesh := BoxMesh.new()
	slope_mesh.size = Vector3(2.5, 0.8, 1.0)
	front_slope.mesh = slope_mesh
	front_slope.rotation_degrees = Vector3(-30, 0, 0)
	front_slope.position = Vector3(0, 1.3, 2.0)
	front_slope.material_override = hull_mat
	_hull_node.add_child(front_slope)

	# Cupola/turret ring (for .50 cal)
	if mg_weapon_id != "":
		_turret_node = Node3D.new()
		_turret_node.name = "Turret"
		_turret_node.position = Vector3(0, 1.6, 0.5)
		add_child(_turret_node)

		var cupola := MeshInstance3D.new()
		var cupola_mesh := CylinderMesh.new()
		cupola_mesh.top_radius = 0.4
		cupola_mesh.bottom_radius = 0.5
		cupola_mesh.height = 0.5
		cupola.mesh = cupola_mesh
		cupola.material_override = hull_mat
		_turret_node.add_child(cupola)

		# MG barrel
		var barrel := MeshInstance3D.new()
		var barrel_mesh := CylinderMesh.new()
		barrel_mesh.top_radius = 0.05
		barrel_mesh.bottom_radius = 0.05
		barrel_mesh.height = 1.5
		barrel.mesh = barrel_mesh
		barrel.rotation_degrees = Vector3(90, 0, 0)
		barrel.position = Vector3(0, 0.2, 0.8)
		_turret_node.add_child(barrel)

	# Track assemblies (simple boxes)
	for side in [-1, 1]:
		var track := MeshInstance3D.new()
		var track_mesh := BoxMesh.new()
		track_mesh.size = Vector3(0.4, 0.6, 4.5)
		track.mesh = track_mesh
		track.position = Vector3(1.3 * side, 0.3, 0)
		var track_mat := StandardMaterial3D.new()
		track_mat.albedo_color = Color(0.15, 0.15, 0.15)
		track.material_override = track_mat
		_hull_node.add_child(track)

	# Collision
	var coll := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.9, 1.8, 5.0)
	coll.shape = box
	coll.position.y = 0.9
	add_child(coll)

	# Set collision layer based on faction
	if data:
		match data.faction:
			GameEnums.Faction.US_ARMY, GameEnums.Faction.ARVN:
				collision_layer = 2
			GameEnums.Faction.VC, GameEnums.Faction.NVA:
				collision_layer = 4
	else:
		collision_layer = 2


func _physics_process(delta: float) -> void:
	if state == State.DESTROYED:
		return

	if _mg_cooldown > 0.0:
		_mg_cooldown -= delta

	# Process based on state
	match state:
		State.LOADING:
			_process_loading(delta)
		State.UNLOADING:
			_process_unloading(delta)
		_:
			# Process turret aiming
			_process_turret(delta)

			# Combat takes priority over movement
			if current_target and is_instance_valid(current_target):
				_process_combat(delta)
			elif has_move_order:
				_process_movement(delta)

	_snap_to_terrain()


func _process_turret(delta: float) -> void:
	if not _turret_node:
		return

	if not current_target or not is_instance_valid(current_target):
		_turret_target_yaw = 0.0
	else:
		var to_target: Vector3 = current_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() > 0.1:
			var world_yaw: float = atan2(to_target.x, to_target.z)
			_turret_target_yaw = world_yaw - rotation.y

	# Apply turret efficiency from components
	var turret_eff: float = vehicle_components.get_turret_efficiency() if vehicle_components else 1.0
	var effective_turn_rate: float = turret_turn_rate_deg * turret_eff

	var max_step: float = deg_to_rad(effective_turn_rate) * delta
	var angle_diff: float = angle_difference(_turret_node.rotation.y, _turret_target_yaw)
	_turret_node.rotation.y = lerp_angle(
		_turret_node.rotation.y,
		_turret_target_yaw,
		clampf(max_step / maxf(0.001, absf(angle_diff)), 0.0, 1.0)
	)
	turret_rotated.emit(rad_to_deg(_turret_node.rotation.y))


func _process_combat(_delta: float) -> void:
	if not is_instance_valid(current_target):
		current_target = null
		state = State.IDLE
		return

	var dist: float = global_position.distance_to(current_target.global_position)
	var range_max: float = data.attack_range if data else 50.0

	if dist > range_max:
		move_to(current_target.global_position)
		return

	state = State.COMBAT

	# Check turret alignment
	var turret_world_yaw: float = rotation.y + (_turret_node.rotation.y if _turret_node else 0.0)
	var to_target: Vector3 = current_target.global_position - global_position
	var target_yaw: float = atan2(to_target.x, to_target.z)
	var aim_error: float = absf(angle_difference(turret_world_yaw, target_yaw))

	# Fire MG if aligned
	if aim_error < deg_to_rad(8.0) and _mg_cooldown <= 0.0 and _mg_ammo > 0 and mg_weapon_id != "":
		_fire_mg()


func _fire_mg() -> void:
	if not current_target or mg_weapon_id == "":
		return

	# Check if we can fire (component system)
	if vehicle_components and not vehicle_components.can_fire_main_gun():
		return

	if CombatManager:
		CombatManager.fire_weapon(self, current_target, mg_weapon_id)

	_mg_ammo -= 1
	fired_mg.emit(current_target.global_position)

	var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(mg_weapon_id)
	var reload_mult: float = vehicle_components.get_reload_modifier() if vehicle_components else 1.0
	_mg_cooldown = (60.0 / weapon.rate_of_fire if weapon else 0.2) * reload_mult


func _process_movement(delta: float) -> void:
	var direction: Vector3 = move_target - global_position
	direction.y = 0
	var distance: float = direction.length()

	if distance < 2.0:
		has_move_order = false
		velocity = Vector3.ZERO
		state = State.IDLE
		return

	var seek_direction: Vector3 = direction.normalized()

	# Slope check
	_slope_query_timer -= delta
	if _slope_query_timer <= 0.0:
		_slope_query_timer = SLOPE_QUERY_INTERVAL
		_cached_slope = _sample_slope_ahead(seek_direction)

	var base_speed: float
	if data and data.has_method("get_speed_at_slope"):
		base_speed = data.get_speed_at_slope(_cached_slope)
	else:
		base_speed = data.move_speed if data else 12.0

	# Apply movement efficiency from components
	var move_eff: float = vehicle_components.get_movement_efficiency() if vehicle_components else 1.0
	var speed: float = base_speed * move_eff

	if speed <= 0.0:
		velocity = Vector3.ZERO
		has_move_order = false
		state = State.IDLE
		path_blocked_by_slope.emit(global_position, _cached_slope)
		return

	# Hull rotation
	var target_yaw: float = atan2(seek_direction.x, seek_direction.z)
	var current_yaw: float = rotation.y
	var yaw_diff: float = angle_difference(current_yaw, target_yaw)
	var max_step: float = deg_to_rad(hull_turn_rate_deg * move_eff) * delta
	rotation.y = current_yaw + clampf(yaw_diff, -max_step, max_step)

	# Only move if facing target
	var alignment: float = cos(yaw_diff)
	if alignment < 0.0:
		alignment = 0.0
	speed *= alignment

	var forward: Vector3 = Vector3(sin(rotation.y), 0, cos(rotation.y))
	velocity = forward * speed
	move_and_slide()
	state = State.MOVING


func _process_loading(delta: float) -> void:
	_load_timer -= delta
	if _load_timer <= 0.0:
		state = State.IDLE


func _process_unloading(delta: float) -> void:
	_load_timer -= delta
	if _load_timer <= 0.0:
		_finish_unload()
		state = State.IDLE


func _finish_unload() -> void:
	var unload_pos: Vector3 = global_position - transform.basis.z * 4.0
	var offset_angle: float = 0.0

	var unloaded: Array[Node3D] = []
	for passenger in passengers:
		if is_instance_valid(passenger):
			var offset := Vector3(cos(offset_angle), 0, sin(offset_angle)) * 3.0
			passenger.global_position = unload_pos + offset
			passenger.visible = true
			passenger.set_physics_process(true)
			unloaded.append(passenger)
			offset_angle += TAU / maxf(passengers.size(), 1.0)

	passengers.clear()
	passengers_unloaded.emit(self, unloaded)


func _sample_slope_ahead(move_dir: Vector3) -> float:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if not terrain:
		return 0.0
	var probe_pos: Vector3 = global_position + move_dir * 3.0
	if terrain.has_method("get_normal_at"):
		var normal: Vector3 = terrain.get_normal_at(probe_pos)
		return clampf(1.0 - normal.y, 0.0, 1.0)
	if terrain.has_method("get_height_at"):
		var h0: float = terrain.get_height_at(global_position)
		var h1: float = terrain.get_height_at(probe_pos)
		var rise: float = absf(h1 - h0)
		return clampf(atan2(rise, 3.0) / (PI * 0.5), 0.0, 1.0)
	return 0.0


func _snap_to_terrain() -> void:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		global_position.y = terrain.get_height_at(global_position)


func _on_component_damaged(component_type: int, current_hp: float, max_hp: float) -> void:
	component_hit.emit(component_type, max_hp - current_hp)
	# Update overall health based on hull
	if component_type == VehicleComponentScript.ComponentType.HULL:
		current_health = current_hp


func _on_component_destroyed(component_type: int) -> void:
	if vehicle_components.is_vehicle_destroyed():
		_destroy()


func _on_crew_killed(_position: int) -> void:
	# Check if vehicle is still operational
	if vehicle_components.get_alive_crew_count() == 0:
		_destroy()


# =============================================================================
# PUBLIC API
# =============================================================================

func move_to(target: Vector3) -> void:
	if state == State.LOADING or state == State.UNLOADING:
		return
	move_target = target
	has_move_order = true
	_attack_move_mode = false


func attack_move_to(target: Vector3) -> void:
	if state == State.LOADING or state == State.UNLOADING:
		return
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


func load_passenger(unit: Node3D) -> bool:
	if passengers.size() >= passenger_capacity:
		return false
	if state == State.DESTROYED:
		return false

	passengers.append(unit)
	unit.visible = false
	unit.set_physics_process(false)

	if state != State.LOADING:
		state = State.LOADING
		_load_timer = LOAD_TIME

	passengers_loaded.emit(self, passengers.size())
	return true


func load_passengers(units: Array[Node3D]) -> int:
	var loaded: int = 0
	for unit in units:
		if load_passenger(unit):
			loaded += 1
	return loaded


func unload_passengers() -> void:
	if passengers.is_empty():
		return
	if state == State.DESTROYED:
		return

	state = State.UNLOADING
	_load_timer = UNLOAD_TIME


func take_damage(amount: float, source: Node = null) -> void:
	if state == State.DESTROYED:
		return

	# Calculate hit angle from source
	var hit_angle: float = 0.0
	if source and is_instance_valid(source):
		var to_source: Vector3 = source.global_position - global_position
		to_source.y = 0.0
		if to_source.length() > 0.1:
			var source_yaw: float = atan2(to_source.x, to_source.z)
			hit_angle = source_yaw - rotation.y

	# Apply damage through component system
	if vehicle_components:
		var ammo_type: int = VehicleComponentScript.AmmoType.HE  # Default to HE for most weapons
		vehicle_components.take_directional_damage(amount, hit_angle, ammo_type)

		# Passengers take damage from penetrating hits
		if not passengers.is_empty() and randf() < 0.2:
			var victim: Node3D = passengers.pick_random()
			if is_instance_valid(victim) and victim.has_method("take_damage"):
				victim.take_damage(amount * 0.3, source)
	else:
		# Fallback simple damage
		var armor_val: float = data.armor if data else 15.0
		var reduction: float = clampf(armor_val * 0.02, 0.0, 0.6)
		current_health = maxf(0.0, current_health - amount * (1.0 - reduction))
		if current_health <= 0.0:
			_destroy()


func _destroy() -> void:
	state = State.DESTROYED
	apc_destroyed.emit(self)

	# Kill passengers
	for passenger in passengers:
		if is_instance_valid(passenger) and passenger.has_method("take_damage"):
			passenger.take_damage(9999, self)
	passengers.clear()

	# Visual destruction
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.1, 0.05)
	for child in get_children():
		if child is MeshInstance3D:
			child.material_override = mat
		elif child is Node3D:
			for subchild in child.get_children():
				if subchild is MeshInstance3D:
					subchild.material_override = mat

	var t := get_tree().create_timer(8.0)
	t.timeout.connect(queue_free)


func get_passenger_count() -> int:
	return passengers.size()


func has_space() -> bool:
	return passengers.size() < passenger_capacity


func get_mg_ammo() -> int:
	return _mg_ammo


func get_component_status(component_type: int) -> String:
	if vehicle_components:
		return vehicle_components.get_component_status(component_type)
	return "N/A"


func get_overall_status() -> Dictionary:
	if not vehicle_components:
		return {"health_percent": current_health / max_health * 100.0}

	return {
		"health_percent": vehicle_components.get_total_hp() / vehicle_components.get_max_hp() * 100.0,
		"movement_efficiency": vehicle_components.get_movement_efficiency() * 100.0,
		"turret_efficiency": vehicle_components.get_turret_efficiency() * 100.0,
		"accuracy_modifier": vehicle_components.get_accuracy_modifier() * 100.0,
		"crew_alive": vehicle_components.get_alive_crew_count(),
		"passengers": passengers.size(),
	}
