class_name ShuttleHelicopter extends CharacterBody3D

## Helicopter with shuttle behavior for player-driven troop transport
## State machine: WAITING -> LOADING -> FLYING_TO_LZ -> LANDING -> UNLOADING -> RETURNING
## Transports squads (InfantrySquad) rather than individual units

signal shuttle_arrived_at_pickup(helicopter: ShuttleHelicopter)
signal shuttle_arrived_at_lz(helicopter: ShuttleHelicopter)
signal loading_complete(helicopter: ShuttleHelicopter, squad: Node3D)
signal unloading_complete(helicopter: ShuttleHelicopter, squad: Node3D)
signal state_changed(helicopter: ShuttleHelicopter, new_state: ShuttleState)

enum ShuttleState {
	WAITING_AT_PICKUP,
	LOADING,
	FLYING_TO_LZ,
	LANDING_AT_LZ,
	UNLOADING,
	RETURNING_TO_BASE,
	LANDING_AT_BASE
}

const MAX_CAPACITY := 1  # One squad at a time

## Configuration
@export var max_speed: float = 40.0  # m/s
@export var cruise_altitude: float = 25.0
@export var landing_speed: float = 6.0
@export var ascent_rate: float = 10.0
@export var turn_rate: float = 2.5

## Zone references
var loading_zone: Node3D = null
var destination_lz: Node3D = null

## State
var shuttle_state: ShuttleState = ShuttleState.WAITING_AT_PICKUP
var cargo_squad: Node3D = null  # The loaded squad
var _loading_timer: float = 0.0
var _unloading_timer: float = 0.0

## Visual
var _model: Node3D = null
var _main_rotor_nodes: Array[Node3D] = []
var _tail_rotor_nodes: Array[Node3D] = []
var _rotor_speed: float = 0.0
const ROTOR_MAX_SPEED := 25.0
const LOADING_DURATION := 1.5
const UNLOADING_DURATION := 2.0

## Model paths
const HUEY_MODEL_PATH := "res://assets/models/huey.glb"
const HUEY_MODEL_PATH_ALT := "res://assets/models/huey_helicopter.glb"


func _ready() -> void:
	add_to_group("helicopters")
	_load_huey_model()


func _load_huey_model() -> void:
	"""Load the UH-1 Huey model"""
	var model_scene: PackedScene = load(HUEY_MODEL_PATH)
	if not model_scene:
		model_scene = load(HUEY_MODEL_PATH_ALT)

	if model_scene:
		_model = model_scene.instantiate()
		_model.name = "HueyModel"
		add_child(_model)

		# Find all main rotor blade nodes (blades rotate around Y axis)
		_find_all_nodes_containing(_model, "Blade", _main_rotor_nodes)
		var hub: Node3D = _find_node_recursive(_model, "Rotor_Hub")
		if hub:
			_main_rotor_nodes.append(hub)

		# Find all tail rotor blade nodes
		_find_all_nodes_containing(_model, "TailBlade", _tail_rotor_nodes)
		var tail_hub: Node3D = _find_node_recursive(_model, "Tail_Hub")
		if tail_hub:
			_tail_rotor_nodes.append(tail_hub)

		# If no rotor nodes found, create a placeholder disc
		if _main_rotor_nodes.is_empty():
			_create_rotor_disc()
	else:
		push_warning("Huey model not found, using placeholder")
		_create_placeholder_mesh()


func _find_all_nodes_containing(node: Node, name_part: String, result: Array[Node3D]) -> void:
	"""Find all Node3D children containing name_part in their name"""
	if name_part.to_lower() in node.name.to_lower():
		if node is Node3D:
			result.append(node)
	for child in node.get_children():
		_find_all_nodes_containing(child, name_part, result)


func _find_node_recursive(node: Node, name_contains: String) -> Node3D:
	"""Recursively search for a node whose name contains the given string"""
	if name_contains.to_lower() in node.name.to_lower():
		if node is Node3D:
			return node
	for child in node.get_children():
		var found: Node3D = _find_node_recursive(child, name_contains)
		if found:
			return found
	return null


func _create_rotor_disc() -> void:
	"""Create a rotor disc if model doesn't have animated rotors"""
	var rotor_node := MeshInstance3D.new()
	rotor_node.name = "RotorDisc"
	var rotor_mesh := CylinderMesh.new()
	rotor_mesh.top_radius = 5.5
	rotor_mesh.bottom_radius = 5.5
	rotor_mesh.height = 0.08
	rotor_node.mesh = rotor_mesh
	rotor_node.position = Vector3(0, 2.5, 0)

	var rotor_mat := StandardMaterial3D.new()
	rotor_mat.albedo_color = Color(0.15, 0.15, 0.15, 0.4)
	rotor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rotor_node.material_override = rotor_mat
	add_child(rotor_node)
	_main_rotor_nodes.append(rotor_node)


func _create_placeholder_mesh() -> void:
	"""Fallback placeholder helicopter geometry"""
	var fuselage := MeshInstance3D.new()
	fuselage.name = "Fuselage"
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 1.4, 4.5)
	fuselage.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.2)
	fuselage.material_override = mat
	add_child(fuselage)

	_create_rotor_disc()


func _physics_process(delta: float) -> void:
	_update_rotor(delta)

	match shuttle_state:
		ShuttleState.WAITING_AT_PICKUP:
			_hover_in_place(delta)
		ShuttleState.LOADING:
			_process_loading(delta)
		ShuttleState.FLYING_TO_LZ:
			_fly_toward(destination_lz.global_position, delta)
		ShuttleState.LANDING_AT_LZ:
			_process_landing(delta, destination_lz)
		ShuttleState.UNLOADING:
			_process_unloading(delta)
		ShuttleState.RETURNING_TO_BASE:
			_fly_toward(loading_zone.global_position, delta)
		ShuttleState.LANDING_AT_BASE:
			_process_landing(delta, loading_zone)


func _update_rotor(delta: float) -> void:
	"""Spin rotors based on flight state"""
	var target_speed: float = ROTOR_MAX_SPEED
	if shuttle_state == ShuttleState.WAITING_AT_PICKUP and global_position.y < 2.0:
		target_speed = ROTOR_MAX_SPEED * 0.7  # Slower idle on ground

	_rotor_speed = lerpf(_rotor_speed, target_speed, delta * 3.0)

	# Spin all main rotor nodes (Y axis)
	for node in _main_rotor_nodes:
		if is_instance_valid(node):
			node.rotate_y(_rotor_speed * delta)

	# Spin all tail rotor nodes (X axis for side-mounted)
	for node in _tail_rotor_nodes:
		if is_instance_valid(node):
			node.rotate_x(_rotor_speed * delta * 1.5)


func _hover_in_place(delta: float) -> void:
	"""Maintain hover position at loading zone"""
	if not loading_zone:
		return

	var target_pos := loading_zone.global_position + Vector3(0, 1.5, 0)
	var diff := target_pos - global_position

	if diff.length() > 0.5:
		velocity = diff.normalized() * 5.0
	else:
		velocity = velocity.lerp(Vector3.ZERO, delta * 5.0)

	move_and_slide()


func _fly_toward(target: Vector3, delta: float) -> void:
	"""Fly toward target position at cruise altitude"""
	var target_pos := Vector3(target.x, cruise_altitude, target.z)
	var direction: Vector3 = (target_pos - global_position).normalized()
	var distance: float = global_position.distance_to(target_pos)

	# Altitude adjustment
	if global_position.y < cruise_altitude - 1.0:
		velocity.y = ascent_rate
	elif global_position.y > cruise_altitude + 1.0:
		velocity.y = -landing_speed
	else:
		velocity.y = lerpf(velocity.y, 0.0, delta * 3.0)

	# Horizontal movement
	if distance > 3.0:
		var horizontal_dir := Vector3(direction.x, 0, direction.z).normalized()
		var target_velocity: Vector3 = horizontal_dir * max_speed

		# Slow down on approach
		if distance < 15.0:
			target_velocity *= distance / 15.0

		velocity.x = lerpf(velocity.x, target_velocity.x, delta * 2.5)
		velocity.z = lerpf(velocity.z, target_velocity.z, delta * 2.5)

		# Face direction of travel
		var look_dir := Vector3(velocity.x, 0, velocity.z)
		if look_dir.length() > 0.5:
			var target_rot: float = atan2(look_dir.x, look_dir.z)
			rotation.y = lerp_angle(rotation.y, target_rot, delta * turn_rate)
	else:
		velocity.x = lerpf(velocity.x, 0.0, delta * 3.0)
		velocity.z = lerpf(velocity.z, 0.0, delta * 3.0)

		# Arrived - begin landing
		if velocity.length() < 2.0:
			_begin_landing()

	move_and_slide()


func _begin_landing() -> void:
	"""Start landing sequence"""
	if shuttle_state == ShuttleState.FLYING_TO_LZ:
		_set_state(ShuttleState.LANDING_AT_LZ)
		shuttle_arrived_at_lz.emit(self)
	elif shuttle_state == ShuttleState.RETURNING_TO_BASE:
		_set_state(ShuttleState.LANDING_AT_BASE)


func _process_landing(_delta: float, lz: Node3D) -> void:
	"""Descend to ground at LZ"""
	var ground_height: float = lz.global_position.y if lz else 0.0
	var target_height: float = ground_height + 1.5

	if global_position.y > target_height + 0.3:
		velocity = Vector3(0, -landing_speed, 0)
	else:
		velocity = Vector3.ZERO
		global_position.y = target_height

		# Transition based on which LZ we landed at
		if shuttle_state == ShuttleState.LANDING_AT_LZ:
			_set_state(ShuttleState.UNLOADING)
			_unloading_timer = 0.0
		elif shuttle_state == ShuttleState.LANDING_AT_BASE:
			_set_state(ShuttleState.WAITING_AT_PICKUP)
			shuttle_arrived_at_pickup.emit(self)

	move_and_slide()


func _process_loading(delta: float) -> void:
	"""Brief loading delay before takeoff"""
	_loading_timer += delta
	if _loading_timer >= LOADING_DURATION:
		_loading_timer = 0.0
		_set_state(ShuttleState.FLYING_TO_LZ)


func _process_unloading(delta: float) -> void:
	"""Unload squad then return to base"""
	_unloading_timer += delta
	if _unloading_timer >= UNLOADING_DURATION:
		_unloading_timer = 0.0
		_perform_unload()
		_set_state(ShuttleState.RETURNING_TO_BASE)


func _perform_unload() -> void:
	"""Actually unload the squad at LZ"""
	if not cargo_squad:
		return

	var lz_pos: Vector3 = destination_lz.global_position if destination_lz else global_position

	# Call disembark on the squad
	if cargo_squad.has_method("disembark_around"):
		cargo_squad.disembark_around(lz_pos, 6.0)
	elif cargo_squad.has_method("disembark_at"):
		# Fallback for squads without disembark_around
		var positions: Array[Vector3] = []
		for i in 5:
			var angle: float = TAU * i / 5.0
			positions.append(lz_pos + Vector3(cos(angle) * 6.0, 0, sin(angle) * 6.0))
		cargo_squad.disembark_at(positions)

	unloading_complete.emit(self, cargo_squad)
	cargo_squad = null


func _set_state(new_state: ShuttleState) -> void:
	"""Change shuttle state with signal"""
	if shuttle_state != new_state:
		shuttle_state = new_state
		state_changed.emit(self, new_state)


## Public API

func load_squad(squad: Node3D) -> bool:
	"""Load a squad onto the helicopter - call when WAITING_AT_PICKUP"""
	if shuttle_state != ShuttleState.WAITING_AT_PICKUP:
		return false
	if cargo_squad != null:
		return false  # Already carrying a squad

	cargo_squad = squad

	# Tell squad to board
	if squad.has_method("board_transport"):
		squad.board_transport()

	_loading_timer = 0.0
	_set_state(ShuttleState.LOADING)
	loading_complete.emit(self, squad)
	return true


func get_cargo_squad() -> Node3D:
	return cargo_squad


func has_cargo() -> bool:
	return cargo_squad != null


func is_waiting_for_troops() -> bool:
	return shuttle_state == ShuttleState.WAITING_AT_PICKUP


func get_state_name() -> String:
	"""Get human-readable state name"""
	match shuttle_state:
		ShuttleState.WAITING_AT_PICKUP:
			return "Waiting for troops"
		ShuttleState.LOADING:
			return "Loading troops..."
		ShuttleState.FLYING_TO_LZ:
			return "Flying to LZ"
		ShuttleState.LANDING_AT_LZ:
			return "Landing at LZ"
		ShuttleState.UNLOADING:
			return "Unloading troops..."
		ShuttleState.RETURNING_TO_BASE:
			return "Returning to base"
		ShuttleState.LANDING_AT_BASE:
			return "Landing at base"
		_:
			return "Unknown"
