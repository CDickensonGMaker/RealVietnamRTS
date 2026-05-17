extends CharacterBody3D
class_name Helicopter

## Helicopter unit - UH-1 Huey, AH-1 Cobra, CH-47 Chinook
## Handles flight, landing, loading/unloading troops

signal arrived_at_destination(helicopter: Helicopter)
signal landed(helicopter: Helicopter, lz: Node3D)
signal took_off(helicopter: Helicopter)
signal troops_loaded(helicopter: Helicopter, troops: Array)
signal troops_unloaded(helicopter: Helicopter, troops: Array)
signal destroyed(helicopter: Helicopter)
signal took_damage(helicopter: Helicopter, damage: float)

enum State { IDLE, FLYING, LANDING, LANDED, TAKING_OFF, LOADING, UNLOADING, DESTROYED, WAITING }
enum HeliType { UH1_SLICK, UH1_GUNSHIP, AH1_COBRA, CH47_CHINOOK }

## Configuration
@export var heli_type: HeliType = HeliType.UH1_SLICK
@export var max_speed: float = 50.0  # m/s (~180 km/h)
@export var cruise_altitude: float = 30.0
@export var landing_speed: float = 5.0
@export var turn_rate: float = 2.0
@export var max_health: float = 200.0
@export var cargo_capacity: int = 8  # Number of troops

## Waiting behavior - helicopter hovers at this position when idle instead of pestering LZs
@export var waiting_position: Vector3 = Vector3.ZERO
@export var waiting_drift_speed: float = 2.0  # Gentle drift while waiting
@export var prefer_waiting_over_idle: bool = true  # If true, go to WAITING instead of IDLE after mission

## Ownership
var is_player_controlled: bool = true

## State
var current_health: float = 200.0
var state: State = State.IDLE
var current_target: Vector3 = Vector3.ZERO
var current_lz: Node3D = null
var cargo: Array[Node3D] = []  # Loaded troops
var is_armed: bool = false  # For gunships

## Flight
var _target_altitude: float = 30.0
var _descent_rate: float = 8.0
var _ascent_rate: float = 10.0

## Visual
var _rotor_node: Node3D = null
var _rotor_speed: float = 0.0
const ROTOR_MAX_SPEED := 20.0


func _ready() -> void:
	# Set up based on type
	_configure_by_type()
	_create_placeholder_mesh()

	# Add to groups
	add_to_group("helicopters")
	add_to_group("aircraft")
	add_to_group("all_units")
	if is_player_controlled:
		add_to_group("player_units")
		add_to_group("selectable_units")
	else:
		add_to_group("enemy_units")


func _configure_by_type() -> void:
	"""Configure stats based on helicopter type"""
	match heli_type:
		HeliType.UH1_SLICK:
			max_speed = 50.0
			cargo_capacity = 8
			max_health = 200.0
			is_armed = false
		HeliType.UH1_GUNSHIP:
			max_speed = 45.0
			cargo_capacity = 4
			max_health = 250.0
			is_armed = true
		HeliType.AH1_COBRA:
			max_speed = 60.0
			cargo_capacity = 0
			max_health = 300.0
			is_armed = true
		HeliType.CH47_CHINOOK:
			max_speed = 40.0
			cargo_capacity = 33
			max_health = 400.0
			is_armed = false

	current_health = max_health


func _create_placeholder_mesh() -> void:
	"""Create simple placeholder helicopter geometry"""
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "HelicopterMesh"

	# Fuselage (elongated box)
	var fuselage := BoxMesh.new()
	fuselage.size = Vector3(2.0, 1.5, 5.0)
	mesh_instance.mesh = fuselage

	# Material - olive drab
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.2)
	mesh_instance.material_override = mat

	add_child(mesh_instance)

	# Rotor (flat cylinder)
	_rotor_node = MeshInstance3D.new()
	_rotor_node.name = "Rotor"
	var rotor_mesh := CylinderMesh.new()
	rotor_mesh.top_radius = 5.0
	rotor_mesh.bottom_radius = 5.0
	rotor_mesh.height = 0.1
	_rotor_node.mesh = rotor_mesh
	_rotor_node.position = Vector3(0, 1.0, 0)

	var rotor_mat := StandardMaterial3D.new()
	rotor_mat.albedo_color = Color(0.2, 0.2, 0.2, 0.5)
	rotor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rotor_node.material_override = rotor_mat

	add_child(_rotor_node)


func _physics_process(delta: float) -> void:
	# Spin rotor
	_update_rotor(delta)

	match state:
		State.FLYING:
			_process_flying(delta)
		State.LANDING:
			_process_landing(delta)
		State.TAKING_OFF:
			_process_takeoff(delta)
		State.LOADING, State.UNLOADING:
			pass  # Wait for load/unload to complete
		State.WAITING:
			_process_waiting(delta)


func _update_rotor(delta: float) -> void:
	"""Spin the rotor based on state"""
	if state == State.DESTROYED:
		_rotor_speed = maxf(_rotor_speed - delta * 5.0, 0.0)
	elif state == State.LANDED or state == State.IDLE:
		_rotor_speed = lerpf(_rotor_speed, ROTOR_MAX_SPEED * 0.3, delta * 2.0)
	elif state == State.WAITING:
		# Full rotor speed while waiting in the air
		_rotor_speed = lerpf(_rotor_speed, ROTOR_MAX_SPEED, delta * 3.0)
	else:
		_rotor_speed = lerpf(_rotor_speed, ROTOR_MAX_SPEED, delta * 3.0)

	if _rotor_node:
		_rotor_node.rotate_y(_rotor_speed * delta)


func _process_flying(delta: float) -> void:
	"""Fly toward target position"""
	var target_pos := Vector3(current_target.x, _target_altitude, current_target.z)
	var direction: Vector3 = (target_pos - global_position).normalized()
	var distance: float = global_position.distance_to(target_pos)

	# Altitude adjustment
	if global_position.y < _target_altitude - 1.0:
		velocity.y = _ascent_rate
	elif global_position.y > _target_altitude + 1.0:
		velocity.y = -_descent_rate
	else:
		velocity.y = lerpf(velocity.y, 0.0, delta * 3.0)

	# Horizontal movement
	if distance > 2.0:
		var horizontal_dir := Vector3(direction.x, 0, direction.z).normalized()
		var target_velocity: Vector3 = horizontal_dir * max_speed

		# Slow down when approaching
		if distance < 20.0:
			target_velocity *= distance / 20.0

		velocity.x = lerpf(velocity.x, target_velocity.x, delta * 2.0)
		velocity.z = lerpf(velocity.z, target_velocity.z, delta * 2.0)

		# Face direction of travel
		var look_dir := Vector3(velocity.x, 0, velocity.z)
		if look_dir.length() > 0.1:
			var target_rot: float = atan2(look_dir.x, look_dir.z)
			rotation.y = lerp_angle(rotation.y, target_rot, delta * turn_rate)
	else:
		velocity.x = lerpf(velocity.x, 0.0, delta * 3.0)
		velocity.z = lerpf(velocity.z, 0.0, delta * 3.0)

		# Arrived
		if velocity.length() < 1.0:
			arrived_at_destination.emit(self)
			if current_lz:
				_begin_landing()

	move_and_slide()


func _process_landing(delta: float) -> void:
	"""Descend to ground"""
	var ground_height: float = current_lz.global_position.y if current_lz else 0.0
	var target_height: float = ground_height + 0.5

	if global_position.y > target_height + 0.5:
		velocity = Vector3(0, -landing_speed, 0)
	else:
		velocity = Vector3.ZERO
		global_position.y = target_height
		state = State.LANDED
		landed.emit(self, current_lz)

	move_and_slide()


func _process_takeoff(delta: float) -> void:
	"""Ascend to cruise altitude"""
	if global_position.y < cruise_altitude - 1.0:
		velocity = Vector3(0, _ascent_rate, 0)
	else:
		velocity = Vector3.ZERO
		global_position.y = cruise_altitude
		# Transition to WAITING if configured and no active mission
		if prefer_waiting_over_idle and waiting_position != Vector3.ZERO and current_target == Vector3.ZERO:
			state = State.WAITING
		else:
			state = State.FLYING
		took_off.emit(self)

	move_and_slide()


func _process_waiting(delta: float) -> void:
	"""Hover at waiting position with gentle drift"""
	if waiting_position == Vector3.ZERO:
		# No waiting position set, just hover in place
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var target_pos := Vector3(waiting_position.x, cruise_altitude, waiting_position.z)
	var direction: Vector3 = (target_pos - global_position)
	var distance: float = direction.length()

	# Altitude adjustment
	if global_position.y < cruise_altitude - 1.0:
		velocity.y = _ascent_rate
	elif global_position.y > cruise_altitude + 1.0:
		velocity.y = -_descent_rate
	else:
		velocity.y = lerpf(velocity.y, 0.0, delta * 3.0)

	# Drift toward waiting position
	if distance > 5.0:
		var horizontal_dir := Vector3(direction.x, 0, direction.z).normalized()
		velocity.x = lerpf(velocity.x, horizontal_dir.x * waiting_drift_speed, delta * 2.0)
		velocity.z = lerpf(velocity.z, horizontal_dir.z * waiting_drift_speed, delta * 2.0)
	else:
		# Gentle hover drift (small random movements)
		velocity.x = lerpf(velocity.x, 0.0, delta * 2.0)
		velocity.z = lerpf(velocity.z, 0.0, delta * 2.0)

	move_and_slide()


func _begin_landing() -> void:
	"""Start landing sequence"""
	state = State.LANDING
	_target_altitude = 0.0


## Public API

func fly_to(target: Vector3, lz: Node3D = null) -> void:
	"""Order helicopter to fly to position"""
	current_target = target
	current_lz = lz
	_target_altitude = cruise_altitude
	state = State.FLYING


func land_at(lz: Node3D) -> void:
	"""Land at a specific landing zone"""
	current_lz = lz
	fly_to(lz.global_position, lz)


func take_off() -> void:
	"""Take off from current position"""
	if state == State.LANDED:
		state = State.TAKING_OFF
		current_lz = null


func go_to_waiting() -> void:
	"""Fly to waiting position and enter WAITING state"""
	if waiting_position == Vector3.ZERO:
		state = State.IDLE
		return

	current_target = waiting_position
	current_lz = null
	_target_altitude = cruise_altitude
	state = State.WAITING


func set_waiting_position(pos: Vector3) -> void:
	"""Set the waiting position for this helicopter"""
	waiting_position = pos


func load_troops(troops: Array[Node3D]) -> void:
	"""Load troops into helicopter (when landed)"""
	if state != State.LANDED:
		return

	state = State.LOADING
	var loaded_count: int = 0

	for troop in troops:
		if cargo.size() >= cargo_capacity:
			break
		if not is_instance_valid(troop):
			continue

		cargo.append(troop)
		troop.visible = false
		troop.set_physics_process(false)
		loaded_count += 1

	state = State.LANDED
	troops_loaded.emit(self, cargo)


func unload_troops() -> Array[Node3D]:
	"""Unload all troops (when landed)"""
	if state != State.LANDED:
		return []

	state = State.UNLOADING
	var unloaded: Array[Node3D] = []

	var lz_pos: Vector3 = global_position
	if current_lz:
		lz_pos = current_lz.global_position

	var offset_angle: float = 0.0
	for troop in cargo:
		if is_instance_valid(troop):
			# Position troops around helicopter
			var offset := Vector3(cos(offset_angle), 0, sin(offset_angle)) * 5.0
			troop.global_position = lz_pos + offset
			troop.visible = true
			troop.set_physics_process(true)
			unloaded.append(troop)
			offset_angle += TAU / maxf(cargo.size(), 1.0)

	cargo.clear()
	state = State.LANDED
	troops_unloaded.emit(self, unloaded)
	return unloaded


func take_damage(amount: float, _source: Node3D = null) -> void:
	"""Apply damage to helicopter"""
	current_health -= amount
	took_damage.emit(self, amount)

	if current_health <= 0:
		_destroy()


func _destroy() -> void:
	"""Helicopter destroyed"""
	state = State.DESTROYED
	destroyed.emit(self)

	# Kill cargo
	for troop in cargo:
		if is_instance_valid(troop) and troop.has_method("take_damage"):
			troop.take_damage(9999, self)
	cargo.clear()

	# Visual destruction
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.1)
	for child in get_children():
		if child is MeshInstance3D:
			child.material_override = mat

	# Fall and explode after delay
	var tween := create_tween()
	tween.tween_property(self, "global_position:y", 0.0, 2.0)
	tween.tween_callback(queue_free)


## Getters

func get_cargo_count() -> int:
	return cargo.size()


func has_cargo_space() -> bool:
	return cargo.size() < cargo_capacity


func is_flying() -> bool:
	return state == State.FLYING


func is_landed() -> bool:
	return state == State.LANDED


func is_waiting() -> bool:
	return state == State.WAITING
