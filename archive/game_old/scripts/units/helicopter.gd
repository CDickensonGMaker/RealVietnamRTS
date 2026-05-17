extends Node3D
class_name Helicopter
## Helicopter - Supply and medevac chopper
## Flies in, lands at LZ, unloads/loads, flies out

signal helicopter_arriving
signal helicopter_landed
signal supplies_delivered(amount: int)
signal wounded_evacuated(count: int)
signal helicopter_departing
signal helicopter_destroyed

enum HeliState { INBOUND, LANDING, UNLOADING, LOADING, TAKEOFF, OUTBOUND, EVADING, DESTROYED }

# Configuration
@export var supply_capacity: int = 50
@export var medevac_capacity: int = 4
@export var flight_speed: float = 30.0
@export var landing_speed: float = 5.0
@export var unload_time: float = 15.0
@export var max_health: float = 50.0

# State
var current_state: HeliState = HeliState.INBOUND
var current_health: float = 50.0
var supplies_carried: int = 50
var wounded_aboard: int = 0

# Flight path
var target_lz: Node3D = null
var spawn_position: Vector3 = Vector3.ZERO
var current_altitude: float = 30.0
var hover_height: float = 0.5

# Timers
var state_timer: float = 0.0

# AA threat
var taking_fire: bool = false
var evasion_timer: float = 0.0


func _ready() -> void:
	add_to_group("helicopters")
	current_health = max_health


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	state_timer += delta

	match current_state:
		HeliState.INBOUND:
			_process_inbound(delta)
		HeliState.LANDING:
			_process_landing(delta)
		HeliState.UNLOADING:
			_process_unloading(delta)
		HeliState.LOADING:
			_process_loading(delta)
		HeliState.TAKEOFF:
			_process_takeoff(delta)
		HeliState.OUTBOUND:
			_process_outbound(delta)
		HeliState.EVADING:
			_process_evading(delta)


func _process_inbound(delta: float) -> void:
	if not target_lz:
		_abort_mission()
		return

	var target_pos := target_lz.global_position + Vector3(0, current_altitude, 0)
	var direction := (target_pos - global_position).normalized()

	# Move toward LZ at altitude
	global_position += direction * flight_speed * delta

	# Face movement direction
	if direction.length() > 0.1:
		var target_rot := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rot, 2.0 * delta)

	# Check if over LZ
	var horizontal_dist := Vector2(global_position.x, global_position.z).distance_to(
		Vector2(target_lz.global_position.x, target_lz.global_position.z)
	)

	if horizontal_dist < 2.0:
		current_state = HeliState.LANDING
		helicopter_arriving.emit()


func _process_landing(delta: float) -> void:
	var target_height := target_lz.global_position.y + hover_height

	# Descend
	global_position.y -= landing_speed * delta

	if global_position.y <= target_height:
		global_position.y = target_height
		current_state = HeliState.UNLOADING
		state_timer = 0.0
		helicopter_landed.emit()


func _process_unloading(delta: float) -> void:
	if state_timer >= unload_time:
		# Deliver supplies
		GameManager.add_supplies(supplies_carried)
		supplies_delivered.emit(supplies_carried)
		supplies_carried = 0

		# Check for wounded to load
		var wounded := _collect_wounded()
		if wounded > 0:
			current_state = HeliState.LOADING
			state_timer = 0.0
		else:
			current_state = HeliState.TAKEOFF


func _process_loading(delta: float) -> void:
	# Loading wounded takes time
	if state_timer >= 5.0:
		wounded_evacuated.emit(wounded_aboard)
		current_state = HeliState.TAKEOFF


func _process_takeoff(delta: float) -> void:
	# Ascend
	global_position.y += landing_speed * delta

	if global_position.y >= current_altitude:
		global_position.y = current_altitude
		current_state = HeliState.OUTBOUND
		helicopter_departing.emit()


func _process_outbound(delta: float) -> void:
	var direction := (spawn_position - global_position).normalized()

	# Fly back to spawn
	global_position += direction * flight_speed * delta

	# Face movement direction
	if direction.length() > 0.1:
		var target_rot := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rot, 2.0 * delta)

	# Check if reached spawn
	if global_position.distance_to(spawn_position) < 10.0:
		queue_free()


func _process_evading(delta: float) -> void:
	evasion_timer -= delta

	# Erratic movement
	var evasion_offset := Vector3(
		sin(state_timer * 5.0) * 5.0,
		sin(state_timer * 3.0) * 2.0,
		cos(state_timer * 4.0) * 5.0
	)

	global_position += evasion_offset * delta

	if evasion_timer <= 0:
		# Abort mission if heavily damaged
		if current_health < max_health * 0.5:
			_abort_mission()
		else:
			taking_fire = false
			# Resume previous state
			if current_state == HeliState.INBOUND:
				pass  # Continue approach
			else:
				current_state = HeliState.OUTBOUND


func _collect_wounded() -> int:
	# Find wounded units near LZ
	var wounded_count := 0

	# This would interface with the medic/casualty system
	# For now, return 0

	wounded_aboard = wounded_count
	return wounded_count


func _abort_mission() -> void:
	current_state = HeliState.OUTBOUND


func take_damage(amount: float) -> void:
	current_health -= amount
	taking_fire = true

	if current_health <= 0:
		_destroy()
	elif current_state != HeliState.EVADING:
		# Start evasion
		current_state = HeliState.EVADING
		evasion_timer = 3.0


func _destroy() -> void:
	current_state = HeliState.DESTROYED
	helicopter_destroyed.emit()

	# Crash animation/effects would go here
	# Supplies lost, crew killed

	queue_free()


# Setup function called by SupplyDirector
func setup(lz: Node3D, spawn_pos: Vector3, supplies: int) -> void:
	target_lz = lz
	spawn_position = spawn_pos
	supplies_carried = supplies
	global_position = spawn_pos
	current_state = HeliState.INBOUND
