class_name TunnelRat extends CharacterBody3D
## Tunnel Rat - Specialized soldier for tunnel clearing operations.
## Small, brave soldiers who crawl into VC tunnels with pistol and flashlight.
## High risk, high reward - can clear tunnels but very vulnerable.
##
## Historical: Tunnel rats were volunteers, typically small-statured soldiers
## who entered the Cu Chi tunnel complex armed only with a pistol, knife,
## and flashlight to clear VC hiding underground.

signal tunnel_entered(tunnel_rat: TunnelRat, entrance: Node3D)
signal tunnel_cleared(tunnel_rat: TunnelRat, segment: Node3D)
signal enemy_encountered(tunnel_rat: TunnelRat, enemy: Node3D)
signal trap_discovered(tunnel_rat: TunnelRat, trap: Node3D)
signal tunnel_rat_killed(tunnel_rat: TunnelRat, killer: Node3D)
signal intelligence_gathered(tunnel_rat: TunnelRat, intel_type: String)
signal emerged_from_tunnel(tunnel_rat: TunnelRat, entrance: Node3D)

enum State { IDLE, MOVING_SURFACE, ENTERING_TUNNEL, IN_TUNNEL, CLEARING, COMBAT_UNDERGROUND, EXITING_TUNNEL, DEAD }

@export var faction: int = 0  # GameEnums.Faction

## Stats
var current_health: float = 80.0
var max_health: float = 80.0
var move_speed: float = 4.0  # Surface speed
var tunnel_speed: float = 2.0  # Crawling speed

## Equipment
var has_flashlight: bool = true
var has_pistol: bool = true
var has_knife: bool = true
var has_gas_mask: bool = false
var has_cs_gas: bool = false  # Tear gas grenades

## State
var state: State = State.IDLE
var is_player_controlled: bool = true
var current_entrance: Node3D = null  # Current tunnel entrance
var current_segment: Node3D = null  # Current tunnel segment
var target_entrance: Node3D = null  # Destination entrance

## Underground progress
var _tunnel_progress: float = 0.0  # 0-1 through current segment
var _clearing_timer: float = 0.0
const CLEARING_TIME: float = 10.0  # Time to clear a segment

## Detection
var detection_radius: float = 5.0  # Underground detection range
var _detected_enemies: Array[Node3D] = []
var _detected_traps: int = 0

## Movement
var move_target: Vector3 = Vector3.ZERO
var has_move_order: bool = false


func _ready() -> void:
	add_to_group("tunnel_rats")
	add_to_group("infantry")
	add_to_group("all_units")

	if is_player_controlled:
		add_to_group("player_units")
		add_to_group("selectable_units")
	else:
		add_to_group("enemy_units")

	_build_visual()


func _build_visual() -> void:
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25  # Smaller than regular infantry
	capsule.height = 1.4
	mesh.mesh = capsule
	mesh.position.y = 0.7

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.35, 0.2)  # OD green
	mesh.material_override = mat
	add_child(mesh)

	# Flashlight cone (only visible when underground in gameplay)
	var light := SpotLight3D.new()
	light.name = "Flashlight"
	light.light_color = Color(1.0, 0.95, 0.8)
	light.light_energy = 1.0
	light.spot_angle = 30.0
	light.spot_range = 10.0
	light.position = Vector3(0, 0.8, 0.3)
	light.rotation_degrees = Vector3(-10, 0, 0)
	light.visible = false  # Only on underground
	add_child(light)

	# Collision
	var coll := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.25
	shape.height = 1.4
	coll.shape = shape
	coll.position.y = 0.7
	add_child(coll)

	collision_layer = 2 if GameEnums.is_us_faction(faction) else 4


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	match state:
		State.IDLE:
			pass
		State.MOVING_SURFACE:
			_process_surface_movement(delta)
		State.ENTERING_TUNNEL:
			_process_entering_tunnel(delta)
		State.IN_TUNNEL:
			_process_in_tunnel(delta)
		State.CLEARING:
			_process_clearing(delta)
		State.COMBAT_UNDERGROUND:
			_process_underground_combat(delta)
		State.EXITING_TUNNEL:
			_process_exiting_tunnel(delta)


func _process_surface_movement(delta: float) -> void:
	if not has_move_order:
		state = State.IDLE
		return

	var direction: Vector3 = move_target - global_position
	direction.y = 0
	var distance: float = direction.length()

	if distance < 1.0:
		has_move_order = false
		velocity = Vector3.ZERO
		state = State.IDLE
		return

	velocity = direction.normalized() * move_speed
	move_and_slide()

	# Face movement direction
	if velocity.length() > 0.1:
		rotation.y = atan2(velocity.x, velocity.z)


func _process_entering_tunnel(delta: float) -> void:
	# Animation: move toward entrance and descend
	if not current_entrance:
		state = State.IDLE
		return

	var entrance_pos: Vector3 = current_entrance.global_position
	var dist: float = global_position.distance_to(entrance_pos)

	if dist > 1.0:
		velocity = (entrance_pos - global_position).normalized() * move_speed
		move_and_slide()
	else:
		# Enter the tunnel
		visible = false
		set_physics_process(false)

		# Turn on flashlight
		var light := get_node_or_null("Flashlight")
		if light:
			light.visible = true

		tunnel_entered.emit(self, current_entrance)

		# Emit to central signal bus
		if BattleSignals:
			BattleSignals.tunnel_rat_entered.emit(self, current_entrance)

		# Start clearing first segment
		if current_entrance.has_method("get_connected_segments"):
			var segments: Array = current_entrance.get_connected_segments()
			if not segments.is_empty():
				current_segment = segments[0]
				state = State.IN_TUNNEL
				_tunnel_progress = 0.0


func _process_in_tunnel(delta: float) -> void:
	if not current_segment:
		# No segment, try to exit
		_try_exit_tunnel()
		return

	# Progress through segment
	var segment_length: float = current_segment.length if current_segment.has_method("get") else 50.0
	var traversal_time: float = segment_length / tunnel_speed

	_tunnel_progress += delta / traversal_time

	# Check for enemies and traps
	_detect_threats()

	if not _detected_enemies.is_empty():
		state = State.COMBAT_UNDERGROUND
		return

	if _tunnel_progress >= 1.0:
		# Reached end of segment
		_tunnel_progress = 0.0

		# Start clearing
		state = State.CLEARING
		_clearing_timer = CLEARING_TIME


func _process_clearing(delta: float) -> void:
	_clearing_timer -= delta

	# Continue threat detection while clearing
	_detect_threats()

	if not _detected_enemies.is_empty():
		state = State.COMBAT_UNDERGROUND
		return

	if _clearing_timer <= 0.0:
		_clear_segment()


func _process_underground_combat(delta: float) -> void:
	if _detected_enemies.is_empty():
		state = State.IN_TUNNEL
		return

	# Underground combat is extremely close range and dangerous
	var enemy: Node3D = _detected_enemies[0]
	if not is_instance_valid(enemy):
		_detected_enemies.erase(enemy)
		return

	# Attack with pistol
	if has_pistol and CombatManager:
		CombatManager.fire_weapon(self, enemy, "m1911")

	# Both sides take damage in close quarters
	if enemy.has_method("take_damage"):
		enemy.take_damage(25, self)  # Pistol damage

	# Tunnel rat also very vulnerable
	take_damage(15, enemy)

	enemy_encountered.emit(self, enemy)


func _process_exiting_tunnel(delta: float) -> void:
	if not target_entrance:
		state = State.IDLE
		visible = true
		set_physics_process(true)
		return

	# Emerge at target entrance
	global_position = target_entrance.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	visible = true
	set_physics_process(true)

	# Turn off flashlight
	var light := get_node_or_null("Flashlight")
	if light:
		light.visible = false

	emerged_from_tunnel.emit(self, target_entrance)

	current_entrance = null
	current_segment = null
	target_entrance = null
	state = State.IDLE


func _detect_threats() -> void:
	_detected_enemies.clear()
	_detected_traps = 0

	if not current_segment:
		return

	# Check for hidden units in segment
	if current_segment.has_method("get") and current_segment.get("hidden_units"):
		for unit in current_segment.hidden_units:
			if is_instance_valid(unit) and unit.is_in_group("enemy_units"):
				_detected_enemies.append(unit)

	# Check for booby traps
	if current_segment.has_method("get") and current_segment.get("booby_traps"):
		_detected_traps = current_segment.booby_traps

		if _detected_traps > 0:
			trap_discovered.emit(self, current_segment)
			# Chance to disarm or trigger
			if randf() < 0.7:  # 70% chance to safely disarm
				current_segment.booby_traps -= 1
				intelligence_gathered.emit(self, "trap_disarmed")
			else:
				# Triggered trap
				take_damage(40, current_segment)


func _clear_segment() -> void:
	if not current_segment:
		return

	# Mark segment as cleared/discovered
	if current_segment.has_method("discover"):
		current_segment.discover(self)

	tunnel_cleared.emit(self, current_segment)

	# Emit to central signal bus
	if BattleSignals:
		BattleSignals.tunnel_segment_cleared.emit(self, current_segment)

	# Gather intelligence
	if current_segment.has_method("get"):
		if current_segment.get("segment_type"):
			var intel_type: String = ""
			match current_segment.segment_type:
				1:  # CHAMBER
					intel_type = "chamber_found"
				2:  # STORAGE
					intel_type = "cache_found"
				3:  # HOSPITAL
					intel_type = "hospital_found"
				4:  # COMMAND
					intel_type = "command_post_found"

			if intel_type != "":
				intelligence_gathered.emit(self, intel_type)
				if BattleSignals:
					BattleSignals.tunnel_intel_gathered.emit(self, intel_type)

	# Move to next segment or exit
	var next_segment: Node3D = _find_next_segment()
	if next_segment:
		current_segment = next_segment
		_tunnel_progress = 0.0
		state = State.IN_TUNNEL
	else:
		_try_exit_tunnel()


func _find_next_segment() -> Node3D:
	if not current_segment:
		return null

	# Get the other entrance of current segment
	var other_entrance: Node3D = null
	if current_segment.has_method("get_other_entrance"):
		other_entrance = current_segment.get_other_entrance(current_entrance)

	if not other_entrance:
		return null

	# Get segments connected to other entrance
	if other_entrance.has_method("get_connected_segments"):
		var segments: Array = other_entrance.get_connected_segments()
		for segment in segments:
			if segment != current_segment:
				current_entrance = other_entrance
				return segment

	return null


func _try_exit_tunnel() -> void:
	# Find exit entrance
	if current_segment and current_segment.has_method("get_other_entrance"):
		target_entrance = current_segment.get_other_entrance(current_entrance)
	elif current_entrance:
		target_entrance = current_entrance

	state = State.EXITING_TUNNEL


# =============================================================================
# PUBLIC API
# =============================================================================

func move_to(target: Vector3) -> void:
	if state in [State.IN_TUNNEL, State.CLEARING, State.COMBAT_UNDERGROUND]:
		return  # Can't move on surface while underground

	move_target = target
	has_move_order = true
	state = State.MOVING_SURFACE


func attack_move_to(target: Vector3) -> void:
	move_to(target)


func enter_tunnel(entrance: Node3D) -> bool:
	if state in [State.IN_TUNNEL, State.CLEARING, State.DEAD]:
		return false

	if not entrance:
		return false

	current_entrance = entrance
	state = State.ENTERING_TUNNEL
	return true


func exit_tunnel() -> void:
	if state not in [State.IN_TUNNEL, State.CLEARING]:
		return

	_try_exit_tunnel()


func use_cs_gas() -> bool:
	if not has_cs_gas:
		return false
	if not current_segment:
		return false

	has_cs_gas = false

	# Gas flushes enemies out or incapacitates them
	if current_segment.has_method("get") and current_segment.get("hidden_units"):
		for unit in current_segment.hidden_units.duplicate():
			if is_instance_valid(unit):
				# Force emergence or damage
				if unit.has_method("take_damage"):
					unit.take_damage(20, self)  # CS gas damage

				if current_segment.has_method("exit_unit"):
					current_segment.exit_unit(unit, current_entrance)

	return true


func take_damage(amount: float, source: Node = null) -> void:
	if state == State.DEAD:
		return

	current_health -= amount

	if current_health <= 0.0:
		_die(source)


func _die(killer: Node = null) -> void:
	state = State.DEAD
	tunnel_rat_killed.emit(self, killer)

	# If underground, body remains there
	if visible:
		# Surface death
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.2, 0.2)
		for child in get_children():
			if child is MeshInstance3D:
				child.material_override = mat

	var t := get_tree().create_timer(30.0)
	t.timeout.connect(queue_free)


func is_underground() -> bool:
	return state in [State.IN_TUNNEL, State.CLEARING, State.COMBAT_UNDERGROUND, State.ENTERING_TUNNEL, State.EXITING_TUNNEL]


func get_status() -> Dictionary:
	return {
		"state": State.keys()[state],
		"health": current_health,
		"underground": is_underground(),
		"segment": current_segment.name if current_segment else "None",
		"progress": _tunnel_progress,
		"enemies_detected": _detected_enemies.size(),
		"traps_detected": _detected_traps,
	}
