class_name Civilian extends CharacterBody3D
## Civilian - Vietnamese villager NPC.
## Can be neutral, pro-US, or pro-VC. Behavior changes based on allegiance.
## Harming civilians has severe reputation consequences.
##
## Serves Pillar 2 (Network of Firebases) indirectly - villages near firebases
## provide intelligence and deny VC staging areas when allegiance is won.

signal civilian_killed(civilian: Civilian, killer: Node3D)
signal civilian_fled(civilian: Civilian, destination: Vector3)
signal civilian_converted(civilian: Civilian, to_vc: bool)
signal provided_intel(civilian: Civilian, position: Vector3)
signal allegiance_changed(civilian: Civilian, new_allegiance: int)

enum State { IDLE, WORKING, FLEEING, HIDING, SURRENDERED, DEAD }
enum Allegiance { NEUTRAL, PRO_US, PRO_VC }
enum Occupation { FARMER, FISHERMAN, MERCHANT, ELDER, CHILD, WOMAN }

@export var occupation: Occupation = Occupation.FARMER

## State
var state: State = State.IDLE
var allegiance: Allegiance = Allegiance.NEUTRAL
var current_health: float = 50.0
var max_health: float = 50.0
var is_vc_sympathizer: bool = false  # Hidden VC supporter

## Home
var home_village: Node3D = null
var home_position: Vector3 = Vector3.ZERO

## Behavior
var fear_level: float = 0.0  # 0-1, increases near combat
var trust_us: float = 0.0  # 0-1, affected by player actions
var trust_vc: float = 0.3  # 0-1, VC has baseline trust from propaganda

## Movement
var _target_position: Vector3 = Vector3.ZERO
var _move_speed: float = 2.5
var _wander_timer: float = 0.0
var _wander_range: float = 20.0

## Work
var _work_timer: float = 0.0
var _work_position: Vector3 = Vector3.ZERO

## Intel
var _last_intel_time: float = 0.0
const INTEL_COOLDOWN: float = 60.0
var _observed_enemies: Array[Node3D] = []


func _ready() -> void:
	add_to_group("civilians")
	add_to_group("all_units")

	home_position = global_position
	_configure_by_occupation()
	_build_visual()

	# Random initial VC sympathy
	if randf() < 0.15:
		is_vc_sympathizer = true
		trust_vc = 0.6


func _configure_by_occupation() -> void:
	match occupation:
		Occupation.FARMER:
			_move_speed = 2.5
			_wander_range = 30.0
		Occupation.FISHERMAN:
			_move_speed = 2.0
			_wander_range = 40.0
		Occupation.MERCHANT:
			_move_speed = 3.0
			_wander_range = 50.0
		Occupation.ELDER:
			_move_speed = 1.5
			_wander_range = 15.0
		Occupation.CHILD:
			_move_speed = 4.0
			_wander_range = 25.0
			max_health = 30.0
		Occupation.WOMAN:
			_move_speed = 2.5
			_wander_range = 20.0

	current_health = max_health


func _build_visual() -> void:
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()

	match occupation:
		Occupation.CHILD:
			capsule.radius = 0.2
			capsule.height = 1.0
		_:
			capsule.radius = 0.3
			capsule.height = 1.6

	mesh.mesh = capsule
	mesh.position.y = capsule.height / 2.0

	var mat := StandardMaterial3D.new()
	match occupation:
		Occupation.FARMER:
			mat.albedo_color = Color(0.5, 0.4, 0.3)  # Brown
		Occupation.FISHERMAN:
			mat.albedo_color = Color(0.4, 0.45, 0.5)  # Blue-gray
		Occupation.MERCHANT:
			mat.albedo_color = Color(0.55, 0.5, 0.4)  # Tan
		Occupation.ELDER:
			mat.albedo_color = Color(0.6, 0.55, 0.5)  # Light
		Occupation.CHILD:
			mat.albedo_color = Color(0.6, 0.5, 0.4)  # Light brown
		Occupation.WOMAN:
			mat.albedo_color = Color(0.5, 0.4, 0.45)  # Purple-brown

	mesh.material_override = mat
	add_child(mesh)

	# Collision
	var coll := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = capsule.radius
	shape.height = capsule.height
	coll.shape = shape
	coll.position.y = capsule.height / 2.0
	add_child(coll)

	# No combat layer - civilians shouldn't be auto-targeted
	collision_layer = 64  # Civilian layer


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	# Update fear based on nearby combat
	_update_fear(delta)

	# Update allegiance based on trust levels
	_update_allegiance()

	match state:
		State.IDLE:
			_process_idle(delta)
		State.WORKING:
			_process_working(delta)
		State.FLEEING:
			_process_fleeing(delta)
		State.HIDING:
			_process_hiding(delta)
		State.SURRENDERED:
			pass  # Wait for player to deal with them

	# Observe enemies for intel
	_observe_surroundings(delta)


func _update_fear(delta: float) -> void:
	# Check for nearby combat
	var combat_nearby: bool = false
	var explosions_nearby: bool = false

	# Check for nearby gunfire (simplified - look for units in combat)
	# Use SpatialHashGrid for O(1) spatial query instead of O(n) group iteration
	var nearby_units: Array[Node3D] = SpatialHashGrid.get_units_in_radius(global_position, 100.0)
	for unit in nearby_units:
		if not is_instance_valid(unit):
			continue
		var dist: float = global_position.distance_to(unit.global_position)

		# Check if unit is firing (has "state" and it's combat)
		if unit.has_method("get") and unit.get("state"):
			if unit.state == 3:  # Combat state typically
				combat_nearby = true
				if dist < 30.0:
					fear_level = minf(fear_level + delta * 0.3, 1.0)
				break

	# Decay fear over time
	if not combat_nearby:
		fear_level = maxf(fear_level - delta * 0.05, 0.0)

	# High fear triggers fleeing
	if fear_level > 0.7 and state != State.FLEEING and state != State.HIDING:
		_start_fleeing()


func _update_allegiance() -> void:
	var old_allegiance: Allegiance = allegiance

	if trust_us > trust_vc + 0.2:
		allegiance = Allegiance.PRO_US
	elif trust_vc > trust_us + 0.2:
		allegiance = Allegiance.PRO_VC
	else:
		allegiance = Allegiance.NEUTRAL

	if allegiance != old_allegiance:
		allegiance_changed.emit(self, allegiance)


func _process_idle(delta: float) -> void:
	_wander_timer -= delta

	if _wander_timer <= 0.0:
		_wander_timer = randf_range(5.0, 15.0)

		# Chance to start working
		if randf() < 0.3:
			_start_working()
		else:
			# Wander near home
			var wander_offset := Vector3(
				randf_range(-_wander_range, _wander_range),
				0,
				randf_range(-_wander_range, _wander_range)
			)
			_target_position = home_position + wander_offset
			state = State.IDLE

	_move_toward_target(delta)


func _process_working(delta: float) -> void:
	_work_timer -= delta

	if _work_timer <= 0.0:
		state = State.IDLE
		return

	# Stay near work position
	var dist: float = global_position.distance_to(_work_position)
	if dist > 3.0:
		_target_position = _work_position
		_move_toward_target(delta)


func _process_fleeing(delta: float) -> void:
	_move_toward_target(delta * 2.0)  # Run faster when fleeing

	var dist: float = global_position.distance_to(_target_position)
	if dist < 2.0:
		# Reached flee destination
		if fear_level > 0.5:
			# Find new flee destination
			_find_flee_destination()
		else:
			state = State.HIDING
			_wander_timer = randf_range(30.0, 60.0)


func _process_hiding(delta: float) -> void:
	_wander_timer -= delta

	# Stay still while hiding
	velocity = Vector3.ZERO

	if _wander_timer <= 0.0 and fear_level < 0.3:
		state = State.IDLE


func _start_working() -> void:
	state = State.WORKING
	_work_timer = randf_range(30.0, 120.0)

	match occupation:
		Occupation.FARMER:
			# Work in fields near village
			_work_position = home_position + Vector3(randf_range(-40, 40), 0, randf_range(-40, 40))
		Occupation.FISHERMAN:
			# Look for water
			_work_position = home_position + Vector3(randf_range(-60, 60), 0, randf_range(-60, 60))
		_:
			_work_position = home_position + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))


func _start_fleeing() -> void:
	state = State.FLEEING
	_find_flee_destination()
	civilian_fled.emit(self, _target_position)


func _find_flee_destination() -> void:
	# Flee away from danger (toward home village or away from combat)
	var flee_direction: Vector3 = (home_position - global_position).normalized()

	# Check for nearby enemies and flee opposite direction
	# Use SpatialHashGrid for efficient spatial query
	# Civilians flee from player units (US/ARVN = factions 0,1)
	var nearby_threats: Array[Node3D] = SpatialHashGrid.get_friendlies_in_radius(
		global_position, 50.0, GameEnums.Faction.US_ARMY
	)
	# Also check ARVN
	nearby_threats.append_array(SpatialHashGrid.get_friendlies_in_radius(
		global_position, 50.0, GameEnums.Faction.ARVN
	))

	var nearest_threat: Node3D = null
	var nearest_dist: float = INF
	for unit in nearby_threats:
		if not is_instance_valid(unit):
			continue
		var dist: float = global_position.distance_to(unit.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_threat = unit

	if nearest_threat:
		flee_direction = (global_position - nearest_threat.global_position).normalized()

	_target_position = global_position + flee_direction * 50.0


func _move_toward_target(delta: float) -> void:
	var direction: Vector3 = _target_position - global_position
	direction.y = 0
	var distance: float = direction.length()

	if distance > 1.0:
		velocity = direction.normalized() * _move_speed
		move_and_slide()

		# Face movement direction
		if velocity.length() > 0.1:
			var target_yaw: float = atan2(velocity.x, velocity.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, delta * 5.0)
	else:
		velocity = Vector3.ZERO


func _observe_surroundings(delta: float) -> void:
	_last_intel_time += delta

	if allegiance != Allegiance.PRO_US:
		return
	if _last_intel_time < INTEL_COOLDOWN:
		return

	# Look for VC/NVA units using SpatialHashGrid for efficient spatial query
	# Pro-US civilians observe enemies (VC/NVA = factions 2,3)
	_observed_enemies.clear()
	var vc_units: Array[Node3D] = SpatialHashGrid.get_friendlies_in_radius(
		global_position, 100.0, GameEnums.Faction.VC
	)
	var nva_units: Array[Node3D] = SpatialHashGrid.get_friendlies_in_radius(
		global_position, 100.0, GameEnums.Faction.NVA
	)

	for unit in vc_units:
		if is_instance_valid(unit):
			_observed_enemies.append(unit)
	for unit in nva_units:
		if is_instance_valid(unit):
			_observed_enemies.append(unit)

	# Provide intel if enemies spotted
	if not _observed_enemies.is_empty():
		_last_intel_time = 0.0
		var enemy_pos: Vector3 = _observed_enemies[0].global_position
		provided_intel.emit(self, enemy_pos)


# =============================================================================
# PUBLIC API
# =============================================================================

func take_damage(amount: float, source: Node = null) -> void:
	if state == State.DEAD:
		return

	current_health -= amount

	# Any damage causes massive fear
	fear_level = 1.0

	if current_health <= 0.0:
		_die(source)
	else:
		# Even non-lethal damage causes trust loss
		if source and source.is_in_group("player_units"):
			trust_us = maxf(trust_us - 0.3, 0.0)
			trust_vc = minf(trust_vc + 0.1, 1.0)

		_start_fleeing()


func _die(killer: Node = null) -> void:
	state = State.DEAD
	civilian_killed.emit(self, killer)

	# Report to village
	if home_village and home_village.has_method("civilian_casualty"):
		home_village.civilian_casualty(killer)

	# Report to reputation tracker
	if BattleSignals:
		BattleSignals.civilian_casualty.emit(home_village, killer)

	# Visual death
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.2, 0.2)
	for child in get_children():
		if child is MeshInstance3D:
			child.material_override = mat
			child.rotation_degrees.x = 90

	var t := get_tree().create_timer(30.0)
	t.timeout.connect(queue_free)


func convert_to_vc() -> void:
	is_vc_sympathizer = true
	allegiance = Allegiance.PRO_VC
	trust_vc = 1.0
	trust_us = 0.0
	civilian_converted.emit(self, true)


func reveal_as_vc() -> Node3D:
	# Convert to VC combatant
	remove_from_group("civilians")
	add_to_group("enemy_units")
	collision_layer = 4  # VC layer

	# Visual change
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.35, 0.25)  # Khaki
	for child in get_children():
		if child is MeshInstance3D:
			child.material_override = mat

	return self


func set_home(village: Node3D, position: Vector3) -> void:
	home_village = village
	home_position = position


func receive_aid(amount: float) -> void:
	# US aid increases trust
	trust_us = minf(trust_us + amount * 0.1, 1.0)
	trust_vc = maxf(trust_vc - amount * 0.03, 0.0)


func receive_vc_propaganda() -> void:
	# VC propaganda
	trust_vc = minf(trust_vc + 0.1, 1.0)
	trust_us = maxf(trust_us - 0.05, 0.0)


func surrender() -> void:
	state = State.SURRENDERED
	velocity = Vector3.ZERO
	# Raise hands (rotate mesh)
	for child in get_children():
		if child is MeshInstance3D:
			child.rotation_degrees.x = 15


func get_allegiance_name() -> String:
	match allegiance:
		Allegiance.NEUTRAL:
			return "Neutral"
		Allegiance.PRO_US:
			return "Pro-US"
		Allegiance.PRO_VC:
			return "Pro-VC"
	return "Unknown"


func is_alive() -> bool:
	return state != State.DEAD


func get_status() -> Dictionary:
	return {
		"state": State.keys()[state],
		"occupation": Occupation.keys()[occupation],
		"allegiance": get_allegiance_name(),
		"fear": fear_level,
		"trust_us": trust_us,
		"trust_vc": trust_vc,
		"is_vc": is_vc_sympathizer,
	}
