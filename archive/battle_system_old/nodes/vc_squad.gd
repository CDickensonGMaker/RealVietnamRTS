extends Squad
class_name VCSquad
## VCSquad - Viet Cong guerrilla infantry squad
## Specializes in ambush, hit-and-run, tunnel escape, and concealment

signal ambush_sprung(target: Node3D)
signal fading_away()
signal tunnel_escape_started()
signal trap_placed(trap_type: int, position: Vector3)

# VC-specific behavior states
enum VCBehavior {
	PASSIVE,       # Hiding, not engaging
	HARASSING,     # Hit-and-run fire
	AMBUSHING,     # Waiting for ambush trigger
	ASSAULTING,    # Full attack
	FADING,        # Breaking contact, disappearing
	ESCAPING,      # Running to tunnel
}

var vc_behavior: VCBehavior = VCBehavior.PASSIVE

# Concealment
var concealment_level: float = 0.8  # 0-1, how hidden
var in_hiding: bool = false
var hiding_position: Vector3 = Vector3.ZERO

# Tunnel access
var nearest_tunnel: Node3D = null
var can_escape_to_tunnel: bool = true
var tunnel_escape_range: float = 50.0

# Ambush setup
var ambush_position: Vector3 = Vector3.ZERO
var ambush_direction: Vector3 = Vector3.ZERO
var ambush_range: float = 30.0
var is_ambush_set: bool = false
var ambush_targets: Array[Node3D] = []

# Harassment
var harass_timer: float = 0.0
var harass_interval: float = 5.0  # Seconds between harassment bursts
var shots_this_burst: int = 0
var max_shots_per_burst: int = 5

# Traps
var traps_remaining: int = 2
var trap_types: Array[int] = []  # From VCController.TrapType

# Fade mechanics
var fade_speed: float = 8.0  # Faster than normal movement
var fade_duration: float = 15.0  # Seconds to fade away
var fade_timer: float = 0.0

func _ready() -> void:
	faction = GameEnums.Faction.VC
	super._ready()

	add_to_group("vc_units")
	add_to_group("guerrilla_units")

	# VC have different stats than US
	_apply_vc_defaults()

	# Find nearest tunnel
	_scan_for_tunnels()

func _apply_vc_defaults() -> void:
	## Apply VC-specific defaults
	if not unit_data:
		squad_name = "VC Cell"
		squad_size = 8
		max_squad_size = 10
		move_speed = 5.5  # Slightly faster (know terrain)
		sight_range = 25.0  # Less equipment
		attack_range = 20.0
		damage_per_second = 8.0
		accuracy = 0.6
		max_ammo = 60  # Less ammo
		current_ammo = 60
		morale = 70.0  # Lower starting morale, but recovers near tunnels

func _create_visual() -> void:
	## Create VC visual - darker, more concealed
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.55
	mesh.height = 1.7

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.2, 0.15)  # Dark brown/black
	mat.roughness = 0.95  # Matte finish

	visual_mesh = MeshInstance3D.new()
	visual_mesh.mesh = mesh
	visual_mesh.material_override = mat
	visual_mesh.position.y = 0.85

	add_child(visual_mesh)

func _physics_process(delta: float) -> void:
	# Base processing
	super._physics_process(delta)

	# VC-specific processing
	_update_concealment(delta)
	_process_vc_behavior(delta)
	_check_tunnel_escape()

# =============================================================================
# VC BEHAVIOR PROCESSING
# =============================================================================

func _process_vc_behavior(delta: float) -> void:
	match vc_behavior:
		VCBehavior.PASSIVE:
			_process_passive(delta)
		VCBehavior.HARASSING:
			_process_harassing(delta)
		VCBehavior.AMBUSHING:
			_process_ambushing(delta)
		VCBehavior.FADING:
			_process_fading(delta)
		VCBehavior.ESCAPING:
			_process_escaping(delta)

func _process_passive(delta: float) -> void:
	## Hiding and waiting
	if in_hiding:
		concealment_level = minf(1.0, concealment_level + 0.1 * delta)
		morale = minf(100, morale + 2 * delta)  # Recover morale while hiding

	# Check for opportunity
	if not enemies_in_sight.is_empty():
		# Evaluate threat
		var threat := _assess_threat()
		if threat < 0.3 and is_ambush_set:
			# Good opportunity - spring ambush
			spring_ambush()
		elif threat > 0.7:
			# Danger - fade away
			start_fading()

func _process_harassing(delta: float) -> void:
	## Hit-and-run harassment fire
	harass_timer += delta

	if harass_timer >= harass_interval:
		harass_timer = 0.0
		shots_this_burst = 0

	if shots_this_burst < max_shots_per_burst and current_ammo > 0:
		if not enemies_in_sight.is_empty():
			var target: Node3D = enemies_in_sight[randi() % enemies_in_sight.size()]
			_fire_harass_shot(target)
			shots_this_burst += 1

	# Check if should fade
	if suppression > 50 or morale < 40:
		start_fading()

func _process_ambushing(delta: float) -> void:
	## Waiting in ambush position
	concealment_level = minf(1.0, concealment_level + 0.05 * delta)

	# Check ambush trigger
	for enemy in enemies_in_sight:
		if is_instance_valid(enemy):
			var dist := global_position.distance_to(enemy.global_position)
			if dist <= ambush_range:
				ambush_targets.append(enemy)

	# Spring when enough targets
	if ambush_targets.size() >= 2:
		spring_ambush()

func _process_fading(delta: float) -> void:
	## Breaking contact and disappearing
	fade_timer += delta

	# Move away from enemies
	if not enemies_in_sight.is_empty():
		var flee_dir := Vector3.ZERO
		for enemy in enemies_in_sight:
			if is_instance_valid(enemy):
				flee_dir += (global_position - enemy.global_position).normalized()
		flee_dir = flee_dir.normalized()

		velocity = flee_dir * fade_speed
		move_and_slide()

	# Increase concealment while fading
	concealment_level = minf(1.0, concealment_level + 0.2 * delta)

	# Check if fade complete
	if fade_timer >= fade_duration or enemies_in_sight.is_empty():
		_complete_fade()

func _process_escaping(delta: float) -> void:
	## Running to nearest tunnel
	if not nearest_tunnel or not is_instance_valid(nearest_tunnel):
		# No tunnel - fade instead
		vc_behavior = VCBehavior.FADING
		return

	var dir := (nearest_tunnel.global_position - global_position).normalized()
	velocity = dir * fade_speed * 1.2  # Even faster when escaping
	move_and_slide()

	# Check if reached tunnel
	var dist := global_position.distance_to(nearest_tunnel.global_position)
	if dist < 5.0:
		_escape_through_tunnel()

# =============================================================================
# AMBUSH SYSTEM
# =============================================================================

func setup_ambush(position: Vector3, facing: Vector3) -> void:
	## Set up ambush position
	ambush_position = position
	ambush_direction = facing.normalized()
	is_ambush_set = true
	vc_behavior = VCBehavior.AMBUSHING

	# Move to ambush position
	move_to(position)

	# Enter hiding
	in_hiding = true
	visible = false  # Hidden until sprung

func spring_ambush() -> void:
	## Spring the ambush
	if not is_ambush_set:
		return

	visible = true
	in_hiding = false
	is_ambush_set = false
	vc_behavior = VCBehavior.ASSAULTING

	# First volley - high damage surprise
	for target in ambush_targets:
		if is_instance_valid(target):
			if target.has_method("take_damage"):
				var surprise_damage := damage_per_second * 2.0  # Double damage surprise
				target.take_damage(surprise_damage, self)

			if target.has_method("apply_suppression"):
				target.apply_suppression(50.0)  # Heavy suppression

	ambush_sprung.emit(ambush_targets[0] if not ambush_targets.is_empty() else null)
	BattleSignals.vc_ambush_triggered.emit(global_position, ambush_targets[0] if not ambush_targets.is_empty() else null)

	ambush_targets.clear()

	# Attack remaining enemies
	if not enemies_in_sight.is_empty():
		attack(enemies_in_sight[0])

# =============================================================================
# FADE MECHANICS
# =============================================================================

func start_fading() -> void:
	## Begin fading away from combat
	vc_behavior = VCBehavior.FADING
	fade_timer = 0.0
	fading_away.emit()

func _complete_fade() -> void:
	## Successfully broke contact
	vc_behavior = VCBehavior.PASSIVE
	fade_timer = 0.0
	in_hiding = true

	# Recover morale after successful fade
	morale = minf(100, morale + 20)

	# Move to hiding position (nearby concealed spot)
	hiding_position = global_position + Vector3(
		randf_range(-20, 20), 0, randf_range(-20, 20)
	)
	move_to(hiding_position)

# =============================================================================
# TUNNEL ESCAPE
# =============================================================================

func _scan_for_tunnels() -> void:
	## Find nearest tunnel entrance
	var tunnels := get_tree().get_nodes_in_group("tunnel_entrances")

	var nearest_dist := INF
	for tunnel_node: Node in tunnels:
		var tunnel := tunnel_node as Node3D
		if tunnel:
			var dist := global_position.distance_to(tunnel.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_tunnel = tunnel

func _check_tunnel_escape() -> void:
	## Check if should escape to tunnel
	if not can_escape_to_tunnel:
		return

	# Escape when critically threatened
	if morale < 20 or (suppression > 80 and squad_health < 50):
		if nearest_tunnel:
			var dist := global_position.distance_to(nearest_tunnel.global_position)
			if dist <= tunnel_escape_range:
				start_tunnel_escape()

func start_tunnel_escape() -> void:
	## Begin escape to tunnel
	vc_behavior = VCBehavior.ESCAPING
	tunnel_escape_started.emit()
	can_escape_to_tunnel = false  # Prevent repeated attempts

func _escape_through_tunnel() -> void:
	## Successfully escape through tunnel
	if nearest_tunnel.has_method("enter_tunnel"):
		nearest_tunnel.enter_tunnel(self)
	else:
		# Fallback - just hide
		visible = false
		queue_free()

# =============================================================================
# HARASSMENT
# =============================================================================

func start_harassment(target_area: Vector3) -> void:
	## Begin harassment fire on area
	vc_behavior = VCBehavior.HARASSING
	harass_timer = 0.0
	shots_this_burst = 0

func _fire_harass_shot(target: Node3D) -> void:
	if not is_instance_valid(target) or current_ammo <= 0:
		return

	# Lower accuracy for harassment (firing quick, not aimed)
	var harass_accuracy := accuracy * 0.6

	if randf() < harass_accuracy:
		if target.has_method("take_damage"):
			target.take_damage(damage_per_second * 0.5, self)

	# Always suppress
	if target.has_method("apply_suppression"):
		target.apply_suppression(10.0)

	current_ammo -= 1

# =============================================================================
# CONCEALMENT
# =============================================================================

func _update_concealment(delta: float) -> void:
	## Update concealment level
	if current_state == SquadState.MOVING:
		concealment_level = maxf(0.2, concealment_level - 0.1 * delta)
	elif current_state == SquadState.ATTACKING:
		concealment_level = maxf(0.1, concealment_level - 0.2 * delta)
	elif in_hiding:
		concealment_level = minf(1.0, concealment_level + 0.15 * delta)

	# Terrain affects concealment
	# Would check terrain type here

	# Update visual transparency based on concealment
	if visual_mesh:
		var mat := visual_mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color.a = 1.0 - (concealment_level * 0.7)

func get_concealment() -> float:
	return concealment_level

func hide() -> void:
	## Enter hiding mode
	in_hiding = true
	current_state = SquadState.IDLE
	vc_behavior = VCBehavior.PASSIVE

func reveal() -> void:
	## Exit hiding mode
	in_hiding = false
	visible = true

# =============================================================================
# TRAP PLACEMENT
# =============================================================================

func place_trap(trap_type: int, position: Vector3) -> bool:
	## Place a booby trap
	if traps_remaining <= 0:
		return false

	traps_remaining -= 1
	trap_placed.emit(trap_type, position)

	# Notify VC Controller to create actual trap
	var vc_controller := get_tree().get_first_node_in_group("vc_controller")
	if vc_controller and vc_controller.has_method("place_trap"):
		vc_controller.place_trap(position, trap_type)

	return true

# =============================================================================
# THREAT ASSESSMENT
# =============================================================================

func _assess_threat() -> float:
	## Assess current threat level (0-1)
	var threat := 0.0

	# Number of enemies
	threat += enemies_in_sight.size() * 0.1

	# Enemy proximity
	var closest := _get_closest_enemy()
	if closest:
		var dist := global_position.distance_to(closest.global_position)
		if dist < 20:
			threat += 0.3
		elif dist < 40:
			threat += 0.1

	# Own state
	threat += suppression / 200.0
	threat += (100 - morale) / 200.0
	threat += (1.0 - float(squad_size) / float(max_squad_size)) * 0.3

	return clampf(threat, 0.0, 1.0)

# =============================================================================
# MORALE (VC-specific)
# =============================================================================

func _update_morale(delta: float) -> void:
	## VC morale recovery - boosted near tunnels and villages
	super._update_morale(delta)

	# Bonus recovery near tunnel
	if nearest_tunnel:
		var dist := global_position.distance_to(nearest_tunnel.global_position)
		if dist < tunnel_escape_range:
			morale = minf(100, morale + 3 * delta)

	# Hiding recovers morale faster
	if in_hiding and vc_behavior == VCBehavior.PASSIVE:
		morale = minf(100, morale + 5 * delta)

# =============================================================================
# OVERRIDES
# =============================================================================

func take_damage(amount: float, source: Node3D = null) -> void:
	super.take_damage(amount, source)

	# VC consider fleeing when hurt
	if squad_health < 50 or morale < 50:
		if vc_behavior != VCBehavior.FADING and vc_behavior != VCBehavior.ESCAPING:
			# Chance to fade
			if randf() < 0.3:
				start_fading()

func _begin_rout() -> void:
	## VC try to escape to tunnel instead of routing
	if nearest_tunnel:
		var dist := global_position.distance_to(nearest_tunnel.global_position)
		if dist <= tunnel_escape_range:
			start_tunnel_escape()
			return

	# No tunnel - regular rout
	super._begin_rout()

# =============================================================================
# DEBUG
# =============================================================================

func get_debug_info() -> Dictionary:
	var info := super.get_debug_info()
	info["vc_behavior"] = VCBehavior.keys()[vc_behavior]
	info["concealment"] = concealment_level
	info["in_hiding"] = in_hiding
	info["near_tunnel"] = nearest_tunnel != null
	info["traps"] = traps_remaining
	return info
