extends CharacterBody3D
class_name Helicopter
## Helicopter - UH-1 Huey, AH-1 Cobra, CH-47 Chinook flight model

signal state_changed(new_state: int)
signal target_acquired(target: Node3D)
signal weapon_fired(weapon_type: int, target: Vector3)
signal damaged(damage: float, source: Node3D)
signal destroyed()
signal cargo_loaded(cargo: Array)
signal cargo_unloaded(cargo: Array)
signal at_waypoint(waypoint: Vector3)
signal lz_approach_started(lz)  # lz: LandingZone
signal landed(lz)  # lz: LandingZone
signal took_off()

# =============================================================================
# CONFIGURATION
# =============================================================================

enum HeliType { UH1_SLICK, UH1_GUNSHIP, AH1_COBRA, CH47_CHINOOK }
enum FlightState { GROUNDED, TAKEOFF, CRUISING, APPROACHING, LANDING, HOVERING, EVADING, RETURNING }

@export var heli_type: HeliType = HeliType.UH1_SLICK
@export var max_speed: float = 40.0  # m/s (~90 mph)
@export var cruise_altitude: float = 50.0
@export var max_altitude: float = 150.0
@export var turn_rate: float = 1.5  # radians/sec
@export var climb_rate: float = 8.0  # m/s
@export var descent_rate: float = 5.0  # m/s

# Health
@export var max_health: float = 100.0
var current_health: float = 100.0

# Cargo capacity (troops)
const CARGO_CAPACITY := {
	HeliType.UH1_SLICK: 8,
	HeliType.UH1_GUNSHIP: 4,
	HeliType.AH1_COBRA: 0,
	HeliType.CH47_CHINOOK: 33,
}

# =============================================================================
# STATE
# =============================================================================

var flight_state: FlightState = FlightState.GROUNDED
var target_position: Vector3 = Vector3.ZERO
var target_altitude: float = 50.0
var current_lz = null  # LandingZone
var current_mission = null  # HeliMission

# Path following
var flight_path: Array[Vector3] = []
var current_path_index: int = 0

# Cargo
var cargo: Array[Node3D] = []
var passengers: Array[Node3D] = []

# Combat
var current_target: Node3D = null
var weapon_cooldown: float = 0.0
var door_gunner_active: bool = false

# Evasion
var evasion_timer: float = 0.0
var evasion_direction: Vector3 = Vector3.ZERO

# AI timers
var scan_timer: float = 0.0
var state_timer: float = 0.0

func _ready() -> void:
	add_to_group("helicopters")
	add_to_group("aircraft")
	current_health = max_health

	# Set stats based on type
	match heli_type:
		HeliType.UH1_SLICK:
			max_speed = 40.0
			cruise_altitude = 50.0
		HeliType.UH1_GUNSHIP:
			max_speed = 38.0
			cruise_altitude = 40.0
			door_gunner_active = true
		HeliType.AH1_COBRA:
			max_speed = 55.0
			cruise_altitude = 30.0
		HeliType.CH47_CHINOOK:
			max_speed = 35.0
			cruise_altitude = 60.0

func _physics_process(delta: float) -> void:
	_update_timers(delta)

	match flight_state:
		FlightState.GROUNDED:
			_process_grounded(delta)
		FlightState.TAKEOFF:
			_process_takeoff(delta)
		FlightState.CRUISING:
			_process_cruising(delta)
		FlightState.APPROACHING:
			_process_approaching(delta)
		FlightState.LANDING:
			_process_landing(delta)
		FlightState.HOVERING:
			_process_hovering(delta)
		FlightState.EVADING:
			_process_evading(delta)
		FlightState.RETURNING:
			_process_returning(delta)

	_process_combat(delta)
	move_and_slide()

func _update_timers(delta: float) -> void:
	scan_timer -= delta
	state_timer += delta
	weapon_cooldown -= delta
	evasion_timer -= delta

# =============================================================================
# FLIGHT STATES
# =============================================================================

func _process_grounded(_delta: float) -> void:
	velocity = Vector3.ZERO

func _process_takeoff(delta: float) -> void:
	# Climb to cruise altitude
	if global_position.y < target_altitude:
		velocity.y = climb_rate
	else:
		velocity.y = 0
		_set_state(FlightState.CRUISING)

func _process_cruising(delta: float) -> void:
	# Follow path or move to target
	if not flight_path.is_empty() and current_path_index < flight_path.size():
		_fly_to_waypoint(flight_path[current_path_index], delta)

		# Check if reached waypoint
		var horizontal_dist := Vector2(global_position.x, global_position.z).distance_to(
			Vector2(flight_path[current_path_index].x, flight_path[current_path_index].z)
		)
		if horizontal_dist < 10.0:
			at_waypoint.emit(flight_path[current_path_index])
			current_path_index += 1
	elif target_position != Vector3.ZERO:
		_fly_to_waypoint(target_position, delta)

	# Maintain altitude
	_maintain_altitude(cruise_altitude, delta)

	# Check for threats and evade
	if _check_threats():
		_start_evasion()

func _process_approaching(delta: float) -> void:
	if not current_lz:
		_set_state(FlightState.CRUISING)
		return

	var lz_pos := current_lz.get_landing_position()
	var dist := global_position.distance_to(lz_pos)

	# Hot LZ evasion approach
	if current_lz.get_threat_level() > 0.5:
		_evasive_approach(lz_pos, delta)
	else:
		_direct_approach(lz_pos, delta)

	# Door gunner suppression during approach
	if door_gunner_active and current_lz.get_threat_level() > 0.3:
		_door_gunner_suppression()

	# Begin landing when close enough
	if dist < 20.0 and absf(global_position.y - lz_pos.y) < 10.0:
		_set_state(FlightState.LANDING)

func _process_landing(delta: float) -> void:
	if not current_lz:
		_set_state(FlightState.HOVERING)
		return

	var landing_pos := current_lz.get_landing_position()

	# Descend slowly
	velocity.x = (landing_pos.x - global_position.x) * 0.5
	velocity.z = (landing_pos.z - global_position.z) * 0.5
	velocity.y = -descent_rate * 0.5

	# Touch down
	if global_position.y <= landing_pos.y + 0.5:
		global_position.y = landing_pos.y
		velocity = Vector3.ZERO
		_set_state(FlightState.GROUNDED)
		current_lz.register_landed(self)
		landed.emit(current_lz)

func _process_hovering(delta: float) -> void:
	# Maintain position with slight drift
	velocity = Vector3(
		sin(state_timer * 0.5) * 0.5,
		0,
		cos(state_timer * 0.7) * 0.5
	)
	_maintain_altitude(target_altitude, delta)

func _process_evading(delta: float) -> void:
	# Aggressive evasive maneuvers
	velocity = evasion_direction * max_speed
	_maintain_altitude(cruise_altitude + randf_range(-10, 10), delta)

	if evasion_timer <= 0:
		_set_state(FlightState.CRUISING)

func _process_returning(delta: float) -> void:
	# Return to base (off-map)
	var return_pos := Vector3(-500, cruise_altitude, 0)
	_fly_to_waypoint(return_pos, delta)

	if global_position.distance_to(return_pos) < 50.0:
		# Despawn
		queue_free()

# =============================================================================
# FLIGHT HELPERS
# =============================================================================

func _fly_to_waypoint(waypoint: Vector3, delta: float) -> void:
	var direction := (waypoint - global_position).normalized()
	direction.y = 0  # Horizontal movement only

	# Smooth turn toward target
	var target_angle := atan2(direction.x, direction.z)
	var current_angle := atan2(-basis.z.x, -basis.z.z)
	var angle_diff := wrapf(target_angle - current_angle, -PI, PI)

	# Apply turn
	var turn_amount := clampf(angle_diff, -turn_rate * delta, turn_rate * delta)
	rotate_y(turn_amount)

	# Move forward
	velocity.x = -basis.z.x * max_speed
	velocity.z = -basis.z.z * max_speed

func _maintain_altitude(target_alt: float, delta: float) -> void:
	var alt_diff := target_alt - global_position.y
	if absf(alt_diff) > 1.0:
		if alt_diff > 0:
			velocity.y = minf(climb_rate, alt_diff)
		else:
			velocity.y = maxf(-descent_rate, alt_diff)
	else:
		velocity.y = 0

func _direct_approach(landing_pos: Vector3, delta: float) -> void:
	var direction := (landing_pos - global_position).normalized()
	velocity = direction * max_speed * 0.5  # Slow approach
	_maintain_altitude(landing_pos.y + 15.0, delta)

func _evasive_approach(landing_pos: Vector3, delta: float) -> void:
	# Spiral approach pattern
	var angle := state_timer * 0.5
	var radius := global_position.distance_to(landing_pos) * 0.3
	var offset := Vector3(cos(angle) * radius, 0, sin(angle) * radius)

	var approach_pos := landing_pos + offset
	approach_pos.y = cruise_altitude

	_fly_to_waypoint(approach_pos, delta)
	_maintain_altitude(cruise_altitude - state_timer * 2, delta)  # Descend gradually

func _check_threats() -> bool:
	if scan_timer > 0:
		return false
	scan_timer = 1.0  # Scan every second

	# Check for enemy AA or hostile units
	var enemies := SpatialHashGrid.get_enemies_in_radius(
		global_position, 200.0, GameEnums.Faction.US_ARMY
	)

	for enemy in enemies:
		if is_instance_valid(enemy) and _is_aa_threat(enemy):
			return true

	return false

func _is_aa_threat(unit: Node3D) -> bool:
	if unit.has_method("get_unit_type"):
		var utype: int = unit.get_unit_type()
		return utype == GameEnums.UnitType.NVA_AAA
	return false

func _start_evasion() -> void:
	_set_state(FlightState.EVADING)
	evasion_timer = 3.0
	evasion_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()

func _set_state(new_state: FlightState) -> void:
	if flight_state != new_state:
		flight_state = new_state
		state_timer = 0.0
		state_changed.emit(new_state)

# =============================================================================
# COMBAT
# =============================================================================

func _process_combat(delta: float) -> void:
	if heli_type != HeliType.AH1_COBRA and heli_type != HeliType.UH1_GUNSHIP:
		return

	if not current_target or not is_instance_valid(current_target):
		_scan_for_targets()
		return

	if weapon_cooldown <= 0:
		_engage_target()

func _scan_for_targets() -> void:
	if scan_timer > 0:
		return

	var enemies := SpatialHashGrid.get_enemies_in_radius(
		global_position, 300.0, GameEnums.Faction.US_ARMY
	)

	if not enemies.is_empty():
		current_target = enemies[0]
		target_acquired.emit(current_target)

func _engage_target() -> void:
	if not current_target:
		return

	var target_pos := current_target.global_position
	var weapon_type := GameEnums.WeaponClass.MINIGUN

	# Cobra uses rockets too
	if heli_type == HeliType.AH1_COBRA and global_position.distance_to(target_pos) > 100:
		weapon_type = GameEnums.WeaponClass.ROCKET_POD

	# Fire
	weapon_fired.emit(weapon_type, target_pos)
	BattleSignals.weapon_fired.emit(self, weapon_type, target_pos)

	# Apply damage through combat manager
	if CombatManager:
		CombatManager.resolve_attack(self, current_target, weapon_type)

	weapon_cooldown = 0.5 if weapon_type == GameEnums.WeaponClass.MINIGUN else 2.0

func _door_gunner_suppression() -> void:
	# Suppress enemies near LZ during approach
	var enemies := SpatialHashGrid.get_enemies_in_radius(
		current_lz.global_position, 50.0, GameEnums.Faction.US_ARMY
	)

	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.has_method("apply_suppression"):
			enemy.apply_suppression(10.0)
			BattleSignals.unit_suppressed.emit(enemy, 10.0)

# =============================================================================
# PUBLIC API
# =============================================================================

func take_off(target_alt: float = -1.0) -> void:
	if flight_state != FlightState.GROUNDED:
		return

	target_altitude = target_alt if target_alt > 0 else cruise_altitude
	_set_state(FlightState.TAKEOFF)

	if current_lz:
		current_lz.register_departure(self)

	took_off.emit()
	BattleSignals.helicopter_took_off.emit(self)

func fly_to(destination: Vector3) -> void:
	target_position = destination
	target_altitude = destination.y if destination.y > 10 else cruise_altitude
	flight_path.clear()

	if flight_state == FlightState.GROUNDED:
		take_off()
	else:
		_set_state(FlightState.CRUISING)

func set_flight_path(path: Array[Vector3]) -> void:
	flight_path = path
	current_path_index = 0

	if flight_state == FlightState.GROUNDED:
		take_off()
	else:
		_set_state(FlightState.CRUISING)

func approach_lz(lz) -> void:  # lz: LandingZone
	current_lz = lz
	lz.register_inbound(self)
	lz_approach_started.emit(lz)
	_set_state(FlightState.APPROACHING)

func land_at(lz) -> void:  # lz: LandingZone
	current_lz = lz
	target_position = lz.global_position

	if flight_state == FlightState.GROUNDED:
		return

	if global_position.distance_to(lz.global_position) > 100.0:
		approach_lz(lz)
	else:
		_set_state(FlightState.LANDING)

func hover_at(position: Vector3, altitude: float = 30.0) -> void:
	target_position = position
	target_altitude = altitude
	_set_state(FlightState.HOVERING)

func return_to_base() -> void:
	_set_state(FlightState.RETURNING)

func assign_mission(mission) -> void:  # mission: HeliMission
	current_mission = mission

	if not mission.waypoints.is_empty():
		var path: Array[Vector3] = []
		for wp in mission.waypoints:
			path.append(wp.position)
		set_flight_path(path)

	if mission.destination_lz:
		approach_lz(mission.destination_lz)

# =============================================================================
# CARGO
# =============================================================================

func get_cargo_capacity() -> int:
	return CARGO_CAPACITY.get(heli_type, 0)

func can_load_cargo(amount: int) -> bool:
	return passengers.size() + amount <= get_cargo_capacity()

func load_cargo(units: Array[Node3D]) -> bool:
	if not can_load_cargo(units.size()):
		return false

	for unit in units:
		passengers.append(unit)
		if is_instance_valid(unit):
			unit.visible = false  # Hide while in heli

	cargo_loaded.emit(units)
	return true

func unload_cargo() -> Array[Node3D]:
	var unloaded := passengers.duplicate()
	passengers.clear()

	for unit in unloaded:
		if is_instance_valid(unit):
			unit.visible = true
			# Place near helicopter
			unit.global_position = global_position + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))

	cargo_unloaded.emit(unloaded)
	return unloaded

# =============================================================================
# DAMAGE
# =============================================================================

func take_damage(amount: float, source: Node3D = null) -> void:
	current_health -= amount
	damaged.emit(amount, source)
	BattleSignals.helicopter_damaged.emit(self, amount)

	if current_health <= 0:
		_destroy()

func _destroy() -> void:
	destroyed.emit()
	BattleSignals.helicopter_destroyed.emit(self)

	# Unload passengers (they die too or bail out)
	for passenger in passengers:
		if is_instance_valid(passenger) and passenger.has_method("take_damage"):
			passenger.take_damage(100.0, self)

	queue_free()

func get_health() -> float:
	return current_health

func get_health_percent() -> float:
	return current_health / max_health

# =============================================================================
# UTILITIES
# =============================================================================

func get_heli_type_name() -> String:
	match heli_type:
		HeliType.UH1_SLICK:
			return "UH-1 Slick"
		HeliType.UH1_GUNSHIP:
			return "UH-1 Gunship"
		HeliType.AH1_COBRA:
			return "AH-1 Cobra"
		HeliType.CH47_CHINOOK:
			return "CH-47 Chinook"
		_:
			return "Unknown"

func is_transport() -> bool:
	return heli_type in [HeliType.UH1_SLICK, HeliType.CH47_CHINOOK]

func is_gunship() -> bool:
	return heli_type in [HeliType.UH1_GUNSHIP, HeliType.AH1_COBRA]

func is_grounded() -> bool:
	return flight_state == FlightState.GROUNDED

func is_in_flight() -> bool:
	return flight_state != FlightState.GROUNDED

func get_altitude() -> float:
	return global_position.y

func get_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()
