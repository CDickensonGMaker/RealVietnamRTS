class_name Medevac extends CharacterBody3D
## Medevac - UH-1H "Dustoff" medical evacuation helicopter.
## Responds to medevac requests, extracts wounded, transports to aid stations.
## Marked with red crosses - targeting medevacs is a war crime (affects reputation).
##
## Serves Pillar 5 (The War Continues) - Medevac runs on standing orders,
## automatically responding to wounded calls without player micro.

signal medevac_requested(medevac: Medevac, position: Vector3)
signal patient_loaded(medevac: Medevac, patient: Node3D)
signal patient_delivered(medevac: Medevac, patient: Node3D, hospital: Node3D)
signal all_patients_delivered(medevac: Medevac, count: int)
signal medevac_destroyed(medevac: Medevac, patients_lost: int)
signal arrived_at_pickup(medevac: Medevac, position: Vector3)
signal rtb_required(medevac: Medevac, reason: String)

enum State { IDLE, STANDBY, EN_ROUTE_PICKUP, HOVERING_PICKUP, EN_ROUTE_HOSPITAL, LANDING_HOSPITAL, UNLOADING, RTB, DESTROYED }

@export var faction: int = 0  # GameEnums.Faction

## Flight characteristics
@export var max_speed: float = 55.0
@export var cruise_speed: float = 45.0
@export var landing_speed: float = 8.0
@export var turn_rate: float = 2.0
@export var cruise_altitude: float = 40.0
@export var hover_altitude: float = 3.0

## Capacity
@export var patient_capacity: int = 6  # Can carry 6 litter patients
@export var medic_count: int = 2  # Crew medics for in-flight care

## State
var state: State = State.IDLE
var current_health: float = 180.0
var max_health: float = 180.0

## Patients
var patients: Array[Node3D] = []
var _patients_healed_in_flight: int = 0

## Navigation
var pickup_position: Vector3 = Vector3.ZERO
var hospital: Node3D = null  # Medical station or firebase with medical
var home_base: Node3D = null  # Helipad/LZ for standby

## Queue of medevac requests
var _request_queue: Array[Dictionary] = []  # {position: Vector3, priority: int, unit: Node3D}

## Timers
const PICKUP_HOVER_TIME: float = 5.0
const UNLOAD_TIME_PER_PATIENT: float = 3.0
var _operation_timer: float = 0.0
var _auto_dispatch_timer: float = 0.0
const AUTO_DISPATCH_INTERVAL: float = 2.0

## Standby position
var standby_position: Vector3 = Vector3.ZERO

## Visual
var _rotor_node: Node3D = null
var _rotor_speed: float = 0.0


func _ready() -> void:
	add_to_group("medevacs")
	add_to_group("helicopters")
	add_to_group("aircraft")
	add_to_group("all_units")

	if GameEnums.is_us_faction(faction):
		add_to_group("player_units")
	else:
		add_to_group("enemy_units")

	current_health = max_health
	_build_placeholder_visual()

	# Connect to medevac request signal if BattleSignals exists
	if BattleSignals:
		BattleSignals.request_medevac.connect(_on_medevac_request)


func _exit_tree() -> void:
	# Disconnect from global signals to prevent memory leaks
	if BattleSignals and BattleSignals.request_medevac.is_connected(_on_medevac_request):
		BattleSignals.request_medevac.disconnect(_on_medevac_request)


func _build_placeholder_visual() -> void:
	# Huey body
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(2.0, 1.5, 5.0)
	body.mesh = body_mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.35, 0.25)  # OD green
	body.material_override = mat
	add_child(body)

	# Red cross markers (on sides)
	for side in [-1, 1]:
		var cross_bg := MeshInstance3D.new()
		var bg_mesh := BoxMesh.new()
		bg_mesh.size = Vector3(0.02, 0.8, 0.8)
		cross_bg.mesh = bg_mesh
		cross_bg.position = Vector3(1.01 * side, 0, 0)

		var white_mat := StandardMaterial3D.new()
		white_mat.albedo_color = Color(1.0, 1.0, 1.0)
		cross_bg.material_override = white_mat
		add_child(cross_bg)

		# Red cross
		var cross_h := MeshInstance3D.new()
		var h_mesh := BoxMesh.new()
		h_mesh.size = Vector3(0.03, 0.2, 0.6)
		cross_h.mesh = h_mesh
		cross_h.position = Vector3(1.02 * side, 0, 0)

		var red_mat := StandardMaterial3D.new()
		red_mat.albedo_color = Color(0.8, 0.1, 0.1)
		cross_h.material_override = red_mat
		add_child(cross_h)

		var cross_v := MeshInstance3D.new()
		var v_mesh := BoxMesh.new()
		v_mesh.size = Vector3(0.03, 0.6, 0.2)
		cross_v.mesh = v_mesh
		cross_v.position = Vector3(1.02 * side, 0, 0)
		cross_v.material_override = red_mat
		add_child(cross_v)

	# Main rotor
	_rotor_node = MeshInstance3D.new()
	var rotor_mesh := CylinderMesh.new()
	rotor_mesh.top_radius = 6.0
	rotor_mesh.bottom_radius = 6.0
	rotor_mesh.height = 0.1
	_rotor_node.mesh = rotor_mesh
	_rotor_node.position.y = 1.2

	var rotor_mat := StandardMaterial3D.new()
	rotor_mat.albedo_color = Color(0.2, 0.2, 0.2, 0.5)
	rotor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rotor_node.material_override = rotor_mat
	add_child(_rotor_node)

	# Collision
	var coll := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 2.0, 5.2)
	coll.shape = box
	coll.position.y = 0.5
	add_child(coll)

	collision_layer = 32  # Helicopter layer


func _physics_process(delta: float) -> void:
	if state == State.DESTROYED:
		return

	_update_rotor(delta)

	match state:
		State.STANDBY:
			_process_standby(delta)
		State.EN_ROUTE_PICKUP:
			_process_en_route_pickup(delta)
		State.HOVERING_PICKUP:
			_process_hovering_pickup(delta)
		State.EN_ROUTE_HOSPITAL:
			_process_en_route_hospital(delta)
		State.LANDING_HOSPITAL:
			_process_landing_hospital(delta)
		State.UNLOADING:
			_process_unloading(delta)
		State.RTB:
			_process_rtb(delta)


func _update_rotor(delta: float) -> void:
	if _rotor_node:
		var target_speed: float = 25.0 if state != State.IDLE else 5.0
		_rotor_speed = lerpf(_rotor_speed, target_speed, delta * 2.0)
		_rotor_node.rotate_y(_rotor_speed * delta)


func _process_standby(delta: float) -> void:
	# Hover at standby position
	if standby_position != Vector3.ZERO:
		var target_pos: Vector3 = standby_position
		target_pos.y = cruise_altitude
		_fly_toward(target_pos, cruise_speed * 0.3, delta)

	# Check for pending requests
	_auto_dispatch_timer -= delta
	if _auto_dispatch_timer <= 0.0:
		_auto_dispatch_timer = AUTO_DISPATCH_INTERVAL
		_check_request_queue()


func _process_en_route_pickup(delta: float) -> void:
	var target_pos: Vector3 = pickup_position
	target_pos.y = cruise_altitude

	_fly_toward(target_pos, cruise_speed, delta)

	var horizontal_dist: float = Vector2(global_position.x - pickup_position.x, global_position.z - pickup_position.z).length()

	if horizontal_dist < 20.0:
		# Begin descent
		target_pos.y = hover_altitude
		_fly_toward(target_pos, landing_speed, delta)

		if horizontal_dist < 5.0 and global_position.y < hover_altitude + 2.0:
			arrived_at_pickup.emit(self, pickup_position)
			state = State.HOVERING_PICKUP
			_operation_timer = PICKUP_HOVER_TIME


func _process_hovering_pickup(delta: float) -> void:
	# Hover in place
	var target_pos: Vector3 = pickup_position
	target_pos.y = hover_altitude
	_fly_toward(target_pos, 2.0, delta)

	_operation_timer -= delta

	# Try to load wounded in range
	_try_load_wounded()

	# Provide in-flight care
	_provide_care(delta)

	if _operation_timer <= 0.0 or patients.size() >= patient_capacity:
		if patients.is_empty():
			# No patients found, return to standby
			state = State.STANDBY
		else:
			_find_hospital()
			state = State.EN_ROUTE_HOSPITAL


func _process_en_route_hospital(delta: float) -> void:
	if not hospital:
		_find_hospital()
		if not hospital:
			rtb_required.emit(self, "No hospital available")
			state = State.RTB
			return

	var target_pos: Vector3 = hospital.global_position
	target_pos.y = cruise_altitude

	_fly_toward(target_pos, cruise_speed, delta)

	# Provide care during flight
	_provide_care(delta)

	var dist: float = global_position.distance_to(hospital.global_position)
	if dist < 30.0:
		state = State.LANDING_HOSPITAL


func _process_landing_hospital(delta: float) -> void:
	if not hospital:
		state = State.RTB
		return

	var landing_pos: Vector3 = hospital.global_position
	landing_pos.y += 0.5

	_fly_toward(landing_pos, landing_speed, delta)

	var dist: float = global_position.distance_to(landing_pos)
	if dist < 2.0:
		velocity = Vector3.ZERO
		state = State.UNLOADING
		_operation_timer = UNLOAD_TIME_PER_PATIENT * patients.size()


func _process_unloading(delta: float) -> void:
	_operation_timer -= delta

	if _operation_timer <= 0.0:
		_deliver_patients()

		# Check for more requests
		if not _request_queue.is_empty():
			_dispatch_to_next_request()
		else:
			state = State.STANDBY


func _process_rtb(delta: float) -> void:
	if not home_base:
		state = State.STANDBY
		return

	var target_pos: Vector3 = home_base.global_position
	target_pos.y = cruise_altitude

	_fly_toward(target_pos, cruise_speed, delta)

	var dist: float = global_position.distance_to(home_base.global_position)
	if dist < 20.0:
		standby_position = home_base.global_position
		state = State.STANDBY


func _fly_toward(target: Vector3, speed: float, delta: float) -> void:
	var direction: Vector3 = (target - global_position).normalized()
	var target_velocity: Vector3 = direction * speed

	velocity = velocity.lerp(target_velocity, delta * 2.5)

	var look_dir := Vector3(velocity.x, 0, velocity.z)
	if look_dir.length() > 1.0:
		var target_yaw: float = atan2(look_dir.x, look_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * turn_rate)

	move_and_slide()


func _try_load_wounded() -> void:
	if patients.size() >= patient_capacity:
		return

	# Find wounded units near pickup position
	var nearby_units: Array[Node] = get_tree().get_nodes_in_group("all_units")

	for unit in nearby_units:
		if patients.size() >= patient_capacity:
			break

		if not is_instance_valid(unit):
			continue

		# Check if unit is wounded and in range
		var dist: float = unit.global_position.distance_to(pickup_position)
		if dist > 15.0:
			continue

		# Check if unit is wounded (has health and is low)
		if unit.has_method("get") and unit.get("current_health") and unit.get("max_health"):
			var health_pct: float = unit.current_health / unit.max_health
			if health_pct < 0.5 and health_pct > 0.0:
				_load_patient(unit)


func _load_patient(unit: Node3D) -> void:
	patients.append(unit)
	unit.visible = false
	unit.set_physics_process(false)

	patient_loaded.emit(self, unit)

	# Emit to central signal bus
	if BattleSignals:
		BattleSignals.medevac_patient_loaded.emit(self, unit)


func _provide_care(delta: float) -> void:
	# Medics provide healing during flight
	var heal_rate: float = 5.0 * medic_count  # HP per second

	for patient in patients:
		if is_instance_valid(patient) and patient.has_method("get"):
			if patient.get("current_health") and patient.get("max_health"):
				var new_health: float = minf(patient.current_health + heal_rate * delta, patient.max_health)
				if patient.has_method("set"):
					patient.set("current_health", new_health)


func _deliver_patients() -> void:
	var unload_pos: Vector3 = hospital.global_position if hospital else global_position
	var offset_angle: float = 0.0
	var delivered_count: int = patients.size()

	for patient in patients:
		if is_instance_valid(patient):
			var offset := Vector3(cos(offset_angle), 0, sin(offset_angle)) * 5.0
			patient.global_position = unload_pos + offset
			patient.visible = true
			patient.set_physics_process(true)
			patient_delivered.emit(self, patient, hospital)

			# Emit to central signal bus
			if BattleSignals:
				BattleSignals.medevac_patient_delivered.emit(self, patient, hospital)

			offset_angle += TAU / maxf(patients.size(), 1.0)

	patients.clear()
	all_patients_delivered.emit(self, delivered_count)


func _find_hospital() -> void:
	# Look for medical stations or firebases with medical capability
	var medical_stations: Array[Node] = get_tree().get_nodes_in_group("medical_stations")

	if not medical_stations.is_empty():
		# Find closest
		var closest: Node3D = null
		var closest_dist: float = INF

		for station in medical_stations:
			var dist: float = global_position.distance_to(station.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = station

		hospital = closest
		return

	# Fallback: use EntityCache to get nearest firebase
	var nearest_fb: Node = EntityCache.get_nearest_firebase(global_position)
	if nearest_fb:
		hospital = nearest_fb


func _check_request_queue() -> void:
	if _request_queue.is_empty():
		return

	if state != State.STANDBY:
		return

	_dispatch_to_next_request()


func _dispatch_to_next_request() -> void:
	if _request_queue.is_empty():
		return

	# Sort by priority (higher = more urgent)
	_request_queue.sort_custom(func(a, b):
		return a.priority > b.priority
	)

	var request: Dictionary = _request_queue.pop_front()
	pickup_position = request.position
	state = State.EN_ROUTE_PICKUP
	medevac_requested.emit(self, pickup_position)

	# Emit to central signal bus
	if BattleSignals:
		BattleSignals.medevac_dispatched.emit(self, pickup_position)


func _on_medevac_request(position: Vector3, _unit: Node3D) -> void:
	# Add to queue
	var request: Dictionary = {
		"position": position,
		"priority": 1,
		"unit": _unit,
	}

	# Increase priority for multiple casualties in same area
	for existing in _request_queue:
		if existing.position.distance_to(position) < 30.0:
			existing.priority += 1
			return  # Merge with existing request

	_request_queue.append(request)


# =============================================================================
# PUBLIC API
# =============================================================================

func request_medevac(position: Vector3, priority: int = 1) -> void:
	var request: Dictionary = {
		"position": position,
		"priority": priority,
		"unit": null,
	}
	_request_queue.append(request)

	if state == State.STANDBY or state == State.IDLE:
		_dispatch_to_next_request()


func set_standby(position: Vector3, base: Node3D = null) -> void:
	standby_position = position
	home_base = base
	state = State.STANDBY


func set_hospital(medical_station: Node3D) -> void:
	hospital = medical_station


func abort_mission() -> void:
	state = State.STANDBY
	pickup_position = Vector3.ZERO


func take_damage(amount: float, source: Node3D = null) -> void:
	if state == State.DESTROYED:
		return

	current_health -= amount

	# Targeting medevac is a war crime - affects reputation
	if source and BattleSignals:
		BattleSignals.civilian_casualty.emit(null, source)  # Treated like civilian casualty for reputation

	if current_health <= 0.0:
		_destroy()


func _destroy() -> void:
	state = State.DESTROYED
	medevac_destroyed.emit(self, patients.size())

	# Kill patients
	for patient in patients:
		if is_instance_valid(patient) and patient.has_method("take_damage"):
			patient.take_damage(9999, self)
	patients.clear()

	var tween := create_tween()
	tween.tween_property(self, "global_position:y", 0.0, 3.0)
	tween.tween_callback(queue_free)


func get_patient_count() -> int:
	return patients.size()


func get_available_capacity() -> int:
	return patient_capacity - patients.size()


func get_state_name() -> String:
	return State.keys()[state]


func is_available() -> bool:
	return state in [State.IDLE, State.STANDBY]


func get_queue_size() -> int:
	return _request_queue.size()


func get_status() -> Dictionary:
	return {
		"state": get_state_name(),
		"patients": patients.size(),
		"capacity": patient_capacity,
		"queue": _request_queue.size(),
		"hospital": hospital.name if hospital else "None",
	}
