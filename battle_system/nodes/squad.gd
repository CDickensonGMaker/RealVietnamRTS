class_name Squad extends CharacterBody3D
## Squad - Basic selectable, moveable unit with combat capability
## Uses converted S3O models from Spring 1944

const SquadDataScript = preload("res://battle_system/data/squad_data.gd")
const VietnamWeaponDataScript = preload("res://battle_system/data/vietnam_weapon_data.gd")
const UnitAnimatorScript = preload("res://battle_system/systems/unit_animator.gd")

## Model paths for each unit type by faction
const MODEL_PATHS: Dictionary = {
	# US Army Infantry
	"us_rifle": "res://assets/models/us/infantry/us_rifle_infantry.glb",
	"us_engineer": "res://assets/models/us/infantry/us_engineer.glb",
	"us_mortar": "res://assets/models/us/infantry/us_mortar.glb",
	"us_mg": "res://assets/models/us/infantry/us_mg_team.glb",
	# US Vehicles
	"us_jeep": "res://assets/models/vehicles/us_jeep_s3o.glb",
	"us_halftrack": "res://assets/models/vehicles/us_halftrack.glb",
	"us_tank": "res://assets/models/vehicles/us_m24_tank.glb",
	"us_apc": "res://assets/models/vehicles/m113_apc.glb",
	"us_bulldozer": "res://assets/models/vehicles/us_bulldozer.glb",
	# VC Infantry
	"vc_rifle": "res://assets/models/vc/infantry/vc_rifle_infantry.glb",
	"vc_sapper": "res://assets/models/vc/infantry/vc_sapper.glb",
	"vc_mortar": "res://assets/models/vc/infantry/vc_mortar.glb",
	"vc_lmg": "res://assets/models/vc/infantry/vc_lmg.glb",
	# Helicopters
	"us_huey": "res://assets/models/vehicles/uh1_huey.glb",
}

signal health_changed(current: float, maximum: float)
signal squad_died(squad: Node3D)
signal suppression_changed(current: float)
signal clearing_progress_updated(progress: float)
signal clearing_completed()
signal path_blocked_by_slope(position: Vector3, slope: float)

enum State { IDLE, MOVING, COMBAT, SUPPRESSED, DEAD, CLEARING }

@export var data: Resource  # SquadData resource

var state: State = State.IDLE
var current_health: float = 100.0
var max_health: float = 100.0
var is_player_controlled: bool = true
var move_target: Vector3 = Vector3.ZERO
var has_move_order: bool = false

# Combat properties
var current_target: Node = null
var attack_cooldown: float = 0.0
var primary_weapon: String = "m16"  # Default weapon ID

# Suppression system (4-state: NORMAL, CAUTIOUS, SUPPRESSED, PINNED)
var suppression_level: float = 0.0  # 0.0 to 1.0
var suppression_state: int = GameEnums.SuppressionState.NORMAL
var base_suppression_decay: float = 0.05  # Base decay per second (from design doc)

# Training level modifiers (defaults to REGULAR if no squad data)
var training_level: int = GameEnums.TrainingLevel.REGULAR

# Cover and stance
var is_in_cover: bool = false
var is_prone: bool = false

# Clearing/Construction (engineers only)
var clearing_zone_id: int = -1
var clearing_target: Vector3 = Vector3.ZERO
var clearing_progress: float = 0.0
var is_clearing: bool = false
const CLEARING_RATE: float = 0.02  # Progress per second (full clear in ~50 seconds)
const CLEARING_RANGE: float = 8.0  # Must be within this range to clear

# Collision avoidance / separation steering
const SEPARATION_RADIUS: float = 3.0  # Units try to stay this far apart
const SEPARATION_WEIGHT: float = 2.0  # How strongly to avoid other units
const ARRIVAL_SLOWDOWN_RADIUS: float = 2.0  # Start slowing down when this close to target

## Slope query cache - update at most this often (saves terrain lookups every frame)
const SLOPE_QUERY_INTERVAL: float = 0.1
var _slope_query_timer: float = 0.0
var _cached_slope: float = 0.0

# Ammo tracking
var current_ammo: int = 100  # Magazine rounds
var max_ammo: int = 100

# Visual components (created at runtime)
var _mesh_instance: MeshInstance3D
var _selection_ring: MeshInstance3D
var _collision_shape: CollisionShape3D
var _suppression_indicator: MeshInstance3D
var _model_node: Node3D = null  # Reference to loaded GLB model
var _outline_mesh: MeshInstance3D = null  # Blue outline for visibility
var _overhead_marker: MeshInstance3D = null  # Dot above unit for tracking

# Multi-soldier formation visuals (BP RTS Dark Shadows style)
var _soldier_nodes: Array[Node3D] = []  # Individual soldier model instances
var _formation_container: Node3D = null  # Parent node for formation
var _alive_soldier_count: int = 0  # Tracks visible soldiers for casualties
const SOLDIER_SPACING: float = 1.2  # Space between soldiers in formation
const FORMATION_ROWS: int = 3  # Default formation depth
const VISIBILITY_SCALE: float = 1.25  # Scale up models 25% for visibility in jungle

# Animation
var _animator: Node = null  # UnitAnimator instance

# Selection state
var _is_selected: bool = false

# Attack-move mode: scan for enemies while moving
var _attack_move_mode: bool = false
var _attack_move_scan_timer: float = 0.0
const ATTACK_MOVE_SCAN_INTERVAL: float = 0.5  # Scan for enemies every 0.5s

# Survival XP throttle (award every second while suppressed)
var _survival_xp_timer: float = 0.0
const SURVIVAL_XP_INTERVAL: float = 1.0

# Cached autoload reference
var _veterancy_tracker: Node = null

# =============================================================================
# BEHAVIOR TREE INTEGRATION
# =============================================================================

## Assigned behavior tree for AI decision-making
var behavior_tree: Node = null  # BehaviorTree instance

## Index of current behavior preset from SquadBehaviors
var assigned_behavior: int = -1

## Whether BT is paused (e.g., player issuing direct commands)
var bt_paused: bool = false


func _ready() -> void:
	# Cache autoload reference
	_veterancy_tracker = get_node_or_null("/root/VeterancyTracker")

	_setup_placeholder_visuals()
	_setup_collision()
	_apply_data()

	# Add to appropriate groups
	if is_player_controlled:
		add_to_group("player_units")
		add_to_group("selectable_units")
	else:
		add_to_group("enemy_units")
	add_to_group("all_units")

	# Register construction units with BuilderAI
	if data and data.can_build:
		var builder_ai: Node = get_node_or_null("/root/BuilderAI")
		if builder_ai:
			if data.is_vehicle:
				if builder_ai.has_method("register_bulldozer"):
					builder_ai.register_bulldozer(self)
					print("[Squad] Registered %s as bulldozer with BuilderAI" % name)
			else:
				if builder_ai.has_method("register_engineer"):
					builder_ai.register_engineer(self)
					print("[Squad] Registered %s as engineer with BuilderAI" % name)

	BattleSignals.unit_spawned.emit(self, data.faction if data else 0)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	# Update behavior tree if assigned and not paused
	if behavior_tree and not bt_paused:
		_sync_blackboard()
		behavior_tree.update(delta)

	# Process suppression decay
	_process_suppression(delta)

	# Process combat cooldown
	if attack_cooldown > 0.0:
		attack_cooldown -= delta

	# Process combat if we have a target
	if current_target and state == State.COMBAT:
		_process_combat(delta)
	elif is_clearing and state == State.CLEARING:
		_process_clearing(delta)
	elif has_move_order:
		_process_movement(delta)
	else:
		# Idle separation - prevent bunching when stationary
		_process_idle_separation(delta)

	# Process procedural animation
	_update_animation(delta)


func _process_movement(delta: float) -> void:
	# Check if unit can move while suppressed (PINNED units cannot move)
	if not can_move_while_suppressed():
		velocity = Vector3.ZERO
		return

	# Attack-move: periodically scan for enemies while moving
	if _attack_move_mode:
		_attack_move_scan_timer -= delta
		if _attack_move_scan_timer <= 0.0:
			_attack_move_scan_timer = ATTACK_MOVE_SCAN_INTERVAL
			_scan_for_attack_move_targets()

	var direction: Vector3 = (move_target - global_position)
	direction.y = 0  # Keep on ground plane

	var distance: float = direction.length()

	if distance < 0.5:
		# Arrived at destination
		has_move_order = false
		_attack_move_mode = false
		velocity = Vector3.ZERO

		# Check if we were moving to a clearing target
		if is_clearing and clearing_zone_id < 0:
			_begin_clearing()
			return

		state = State.IDLE
		return

	# Calculate base movement toward target
	var seek_direction: Vector3 = direction.normalized()

	# --- SLOPE EVALUATION --------------------------------------------------
	# Refresh slope reading on an interval rather than every frame.
	_slope_query_timer -= delta
	if _slope_query_timer <= 0.0:
		_slope_query_timer = SLOPE_QUERY_INTERVAL
		_cached_slope = _sample_slope_ahead(seek_direction)

	# Get speed from SquadData's slope curve. Returns 0.0 if slope > max_slope.
	var speed: float
	if data and data.has_method("get_speed_at_slope"):
		speed = data.get_speed_at_slope(_cached_slope)
	else:
		# Fallback: legacy behavior
		speed = data.move_speed if data else 5.0

	# Impassable: cannot enter this terrain. Halt and exit movement state.
	if speed <= 0.0:
		velocity = Vector3.ZERO
		has_move_order = false
		state = State.IDLE
		# Emit a signal so UI/AI can react ("can't path there")
		if has_signal("path_blocked_by_slope"):
			emit_signal("path_blocked_by_slope", global_position, _cached_slope)
		return

	# Apply suppression speed modifier (SUPPRESSED units crawl at 50% speed)
	speed *= get_suppression_speed_modifier()

	# Apply arrival slowdown
	if distance < ARRIVAL_SLOWDOWN_RADIUS:
		speed *= (distance / ARRIVAL_SLOWDOWN_RADIUS)

	# Calculate separation force to avoid bunching
	var separation: Vector3 = _calculate_separation()

	# Combine seek + separation
	var combined_direction: Vector3 = seek_direction + separation * SEPARATION_WEIGHT

	# Normalize but preserve speed scaling
	if combined_direction.length() > 0.01:
		combined_direction = combined_direction.normalized()
	else:
		combined_direction = seek_direction

	velocity = combined_direction * speed

	# Rotate to face movement direction (blend between seek and combined)
	var face_direction: Vector3 = combined_direction if combined_direction.length() > 0.1 else seek_direction
	var target_rotation: float = atan2(face_direction.x, face_direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, delta * (data.rotation_speed if data else 3.0))

	# Move first, then snap to terrain (so physics doesn't override Y)
	move_and_slide()
	_snap_to_terrain()
	state = State.MOVING


## Snap unit to terrain height
func _snap_to_terrain() -> void:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		var terrain_height: float = terrain.get_height_at(global_position)
		global_position.y = terrain_height


## Calculate separation force to avoid bunching with nearby units
func _calculate_separation() -> Vector3:
	var separation_force := Vector3.ZERO

	# Use SpatialHashGrid for efficient neighbor lookup
	var grid := get_node_or_null("/root/SpatialHashGrid")
	if not grid:
		return separation_force

	var neighbors: Array[Node3D] = grid.get_units_in_radius(global_position, SEPARATION_RADIUS * 2.0)

	for neighbor in neighbors:
		if neighbor == self:
			continue
		if not is_instance_valid(neighbor):
			continue

		var to_self: Vector3 = global_position - neighbor.global_position
		to_self.y = 0  # Keep on ground plane
		var distance: float = to_self.length()

		if distance < 0.01:
			# Units exactly overlapping - push in random direction
			separation_force += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			continue

		if distance < SEPARATION_RADIUS:
			# The closer they are, the stronger the push
			var strength: float = 1.0 - (distance / SEPARATION_RADIUS)
			separation_force += to_self.normalized() * strength

	return separation_force


## Apply gentle separation when idle to prevent bunching
func _process_idle_separation(_delta: float) -> void:
	var separation: Vector3 = _calculate_separation()

	# Only move if separation force is significant
	if separation.length() < 0.1:
		velocity = Vector3.ZERO
		return

	# Move away slowly (half speed)
	var speed: float = (data.move_speed if data else 5.0) * 0.5
	velocity = separation.normalized() * speed

	# Move first, then snap to terrain (so physics doesn't override Y)
	move_and_slide()
	_snap_to_terrain()


## Issue a move order to this squad
func move_to(target: Vector3) -> void:
	# Get terrain height at target
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		target.y = terrain.get_height_at(target)
	else:
		target.y = global_position.y

	move_target = target
	has_move_order = true
	_attack_move_mode = false  # Clear attack-move mode on regular move
	state = State.MOVING


## Issue an attack-move order: move toward target while engaging enemies in range
func attack_move_to(target: Vector3) -> void:
	# Get terrain height at target
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain and terrain.has_method("get_height_at"):
		target.y = terrain.get_height_at(target)
	else:
		target.y = global_position.y

	move_target = target
	has_move_order = true
	_attack_move_mode = true
	_attack_move_scan_timer = 0.0  # Scan immediately
	state = State.MOVING


## Scan for enemies in range while attack-moving
func _scan_for_attack_move_targets() -> void:
	if not _attack_move_mode or state != State.MOVING:
		return

	# Get weapon range from data
	var weapon_range: float = 300.0
	if data and "engagement_range" in data:
		weapon_range = data.engagement_range

	# Query enemies in range
	var enemies: Array[Node] = []
	if is_in_group("player_units"):
		enemies = get_tree().get_nodes_in_group("enemy_units")
	else:
		enemies = get_tree().get_nodes_in_group("player_units")

	var best_target: Node3D = null
	var best_dist: float = weapon_range

	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node3D:
			continue
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist < best_dist:
			# Check if enemy is alive
			if enemy.has_method("get") and enemy.get("state") != null:
				if enemy.state == State.DEAD:
					continue
			best_dist = dist
			best_target = enemy as Node3D

	# If found enemy in range, attack it (but continue to move_target after)
	if best_target:
		attack(best_target)


## Apply damage to this squad
func take_damage(amount: float, source: Node = null) -> void:
	if state == State.DEAD:
		return

	current_health -= amount
	health_changed.emit(current_health, max_health)
	BattleSignals.unit_damaged.emit(self, amount, source)

	# Update casualty visuals - hide soldiers based on health remaining
	if _soldier_nodes.size() > 1:
		var health_ratio: float = maxf(current_health / max_health, 0.0)
		var visible_soldiers: int = ceili(health_ratio * _soldier_nodes.size())
		apply_casualty_visuals(visible_soldiers)

	if current_health <= 0:
		_die()


func _die() -> void:
	state = State.DEAD
	squad_died.emit(self)
	BattleSignals.unit_died.emit(self, null)

	# Notify RosterManager of death
	var roster_mgr: Node = get_node_or_null("/root/RosterManager")
	if roster_mgr and roster_mgr.has_method("record_unit_death"):
		roster_mgr.record_unit_death(self)

	# Unregister from VeterancyTracker
	var vet_tracker: Node = get_node_or_null("/root/VeterancyTracker")
	if vet_tracker and vet_tracker.has_method("unregister_unit"):
		vet_tracker.unregister_unit(self)

	# Visual feedback
	if _mesh_instance:
		_mesh_instance.visible = false
	if _selection_ring:
		_selection_ring.visible = false
	if _suppression_indicator:
		_suppression_indicator.visible = false
	if _outline_mesh:
		_outline_mesh.visible = false
	if _overhead_marker:
		_overhead_marker.visible = false

	# Remove from groups
	remove_from_group("player_units")
	remove_from_group("enemy_units")
	remove_from_group("all_units")

	# Queue for removal after delay
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(queue_free)


## Process combat with current target
func _process_combat(delta: float) -> void:
	if not is_instance_valid(current_target):
		current_target = null
		state = State.IDLE
		return

	# Check if target is dead
	if current_target.has_method("get") and current_target.get("state") == State.DEAD:
		current_target = null
		state = State.IDLE
		return

	# Check range
	var distance: float = global_position.distance_to(current_target.global_position)
	var attack_range: float = data.attack_range if data else 25.0

	if distance > attack_range:
		# Move closer
		move_to(current_target.global_position)
		return

	# Stop moving to fire
	has_move_order = false
	velocity = Vector3.ZERO

	# Face target
	var direction: Vector3 = (current_target.global_position - global_position).normalized()
	var target_rotation: float = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)

	# Fire if cooldown is ready and not pinned
	if attack_cooldown <= 0.0 and current_ammo > 0 and can_attack_while_suppressed():
		_fire_at_target()


## Fire at the current target
func _fire_at_target() -> void:
	if not current_target:
		return

	# Use CombatManager to fire
	if CombatManager:
		CombatManager.fire_weapon(self, current_target, primary_weapon)

	# Trigger fire recoil animation
	if _animator:
		_animator.trigger_fire_recoil()

	# Consume ammo
	current_ammo -= 1

	# Set cooldown based on weapon
	var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(primary_weapon)
	if weapon:
		attack_cooldown = 60.0 / weapon.rate_of_fire
	else:
		attack_cooldown = 1.0


## Set attack target and enter combat
func attack(target: Node) -> void:
	if state == State.DEAD:
		return

	current_target = target
	state = State.COMBAT


## Stop attacking
func stop_attack() -> void:
	current_target = null
	if state == State.COMBAT:
		state = State.IDLE


# =============================================================================
# ENGINEER CLEARING SYSTEM
# =============================================================================

## Check if this unit can clear terrain (engineers only)
func can_clear() -> bool:
	return data and data.can_build


## Start clearing terrain at target position
## Returns true if clearing started successfully
func start_clearing(target_pos: Vector3, radius: float = 15.0) -> bool:
	if not can_clear():
		print("[Squad] %s cannot clear - not an engineer unit" % name)
		return false

	clearing_target = target_pos

	# Check if we need to move closer
	var distance: float = global_position.distance_to(clearing_target)
	if distance > CLEARING_RANGE:
		# Move to clearing site first
		move_to(clearing_target)
		is_clearing = true  # Flag to start clearing when we arrive
		return true

	# Already in range - start clearing immediately
	_begin_clearing(radius)
	return true


## Internal: Begin the actual clearing operation
func _begin_clearing(radius: float = 15.0) -> void:
	# Create clearing zone via TerrainIntegration
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if not terrain:
		push_warning("[Squad] TerrainIntegration not found - cannot clear")
		is_clearing = false
		return

	clearing_zone_id = terrain.start_clearing_zone(clearing_target, radius)
	if clearing_zone_id < 0:
		push_warning("[Squad] Failed to create clearing zone")
		is_clearing = false
		return

	is_clearing = true
	clearing_progress = 0.0
	state = State.CLEARING
	has_move_order = false
	velocity = Vector3.ZERO

	print("[Squad] %s started clearing at %s (zone %d)" % [name, clearing_target, clearing_zone_id])


## Process clearing work each frame
func _process_clearing(delta: float) -> void:
	if not is_clearing or clearing_zone_id < 0:
		return

	# Check if still in range
	var distance: float = global_position.distance_to(clearing_target)
	if distance > CLEARING_RANGE * 1.5:
		# Moved too far away - stop clearing
		stop_clearing()
		return

	# Face the clearing target
	var direction: Vector3 = (clearing_target - global_position).normalized()
	if direction.length_squared() > 0.01:
		var target_rotation: float = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * 2.0)

	# Advance clearing progress
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if terrain:
		terrain.advance_clearing(clearing_zone_id, CLEARING_RATE * delta)
		clearing_progress += CLEARING_RATE * delta
		clearing_progress_updated.emit(clearing_progress)

		# Check if clearing is complete (progress through all 4 stages)
		if clearing_progress >= 4.0:
			_on_clearing_complete()


## Stop clearing operation
func stop_clearing() -> void:
	if not is_clearing:
		return

	is_clearing = false
	clearing_zone_id = -1
	clearing_progress = 0.0

	if state == State.CLEARING:
		state = State.IDLE

	print("[Squad] %s stopped clearing" % name)


## Called when clearing is complete
func _on_clearing_complete() -> void:
	print("[Squad] %s completed clearing zone %d" % [name, clearing_zone_id])

	is_clearing = false
	clearing_zone_id = -1
	clearing_progress = 0.0
	state = State.IDLE

	clearing_completed.emit()
	BattleSignals.terrain_cleared.emit(clearing_target, 15.0)


## Get clearing progress (0.0 to 4.0, representing 4 stages)
func get_clearing_progress() -> float:
	return clearing_progress


## Check if currently clearing
func is_unit_clearing() -> bool:
	return is_clearing and state == State.CLEARING


## Process suppression decay with training and cover modifiers
func _process_suppression(delta: float) -> void:
	if suppression_level <= 0.0:
		return

	# Award survival XP when under significant suppression (throttled to 1/sec)
	if suppression_level > 0.5:
		_survival_xp_timer -= delta
		if _survival_xp_timer <= 0.0:
			_survival_xp_timer = SURVIVAL_XP_INTERVAL
			if _veterancy_tracker and _veterancy_tracker.has_method("award_survival_xp"):
				_veterancy_tracker.award_survival_xp(self)

	# Calculate decay rate with modifiers
	var decay: float = base_suppression_decay * delta

	# Training affects recovery (ELITE recovers 2x faster, CONSCRIPT 0.5x)
	var recovery_mult: float = GameEnums.get_training_modifier(training_level, "recovery_mult")
	decay *= recovery_mult

	# Cover accelerates recovery
	if is_in_cover:
		decay *= 1.5

	# Apply decay
	suppression_level -= decay
	suppression_level = maxf(suppression_level, 0.0)

	# Update suppression state using the 4-state system
	var old_state: int = suppression_state
	suppression_state = GameEnums.get_suppression_state(suppression_level)

	# Update unit State enum based on suppression
	_update_state_from_suppression()

	# Update visual
	_update_suppression_visual()

	# Emit signal if state changed
	if old_state != suppression_state:
		suppression_changed.emit(suppression_level)


## Update unit State enum based on suppression state
func _update_state_from_suppression() -> void:
	if state == State.DEAD:
		return

	# Only SUPPRESSED and PINNED states force State.SUPPRESSED
	if suppression_state == GameEnums.SuppressionState.SUPPRESSED or \
	   suppression_state == GameEnums.SuppressionState.PINNED:
		if state != State.SUPPRESSED:
			state = State.SUPPRESSED
		# Auto-prone when heavily suppressed
		if not is_prone and suppression_level >= 0.5:
			is_prone = true
	elif state == State.SUPPRESSED:
		# Recovered from suppression, return to IDLE
		state = State.IDLE
		# Stand up when recovered (below CAUTIOUS threshold)
		if is_prone and suppression_level < 0.3:
			is_prone = false


## Apply suppression to this squad with fear type modifier
## fear_type: GameEnums.FearType - determines base suppression effect
## amount: raw suppression value from weapon
func apply_suppression_with_fear(amount: float, fear_type: int) -> void:
	if state == State.DEAD:
		return

	# Get fear multiplier from fear type
	var fear_mult: float = GameEnums.get_fear_value(fear_type)

	# Calculate raw suppression
	var raw_suppression: float = amount * fear_mult * 0.01

	# Training affects how much suppression is received
	var suppression_mult: float = GameEnums.get_training_modifier(training_level, "suppression_mult")
	raw_suppression *= suppression_mult

	# Cover reduces suppression taken
	if is_in_cover:
		raw_suppression *= 0.7  # 30% reduction in cover
	if is_prone:
		raw_suppression *= 0.8  # Additional 20% reduction when prone

	# Apply suppression
	suppression_level += raw_suppression
	suppression_level = clampf(suppression_level, 0.0, 1.0)

	# Update state
	suppression_state = GameEnums.get_suppression_state(suppression_level)
	_update_state_from_suppression()

	suppression_changed.emit(suppression_level)
	_update_suppression_visual()


## Legacy apply_suppression for backward compatibility
## Defaults to SMALL_ARMS fear type
func apply_suppression(amount: float) -> void:
	apply_suppression_with_fear(amount, GameEnums.FearType.SMALL_ARMS)


## Get accuracy modifier based on current suppression state
func get_suppression_accuracy_modifier() -> float:
	var effects: Dictionary = GameEnums.SUPPRESSION_EFFECTS.get(suppression_state, {})
	return effects.get("accuracy", 1.0)


## Get speed modifier based on current suppression state
func get_suppression_speed_modifier() -> float:
	var effects: Dictionary = GameEnums.SUPPRESSION_EFFECTS.get(suppression_state, {})
	return effects.get("speed", 1.0)


## Check if unit can attack in current suppression state
func can_attack_while_suppressed() -> bool:
	var effects: Dictionary = GameEnums.SUPPRESSION_EFFECTS.get(suppression_state, {})
	return effects.get("can_attack", true)


## Check if unit can move in current suppression state
func can_move_while_suppressed() -> bool:
	var effects: Dictionary = GameEnums.SUPPRESSION_EFFECTS.get(suppression_state, {})
	return effects.get("can_move", true)


## Update suppression indicator visual based on 4-state system
## Colors: NORMAL=hidden, CAUTIOUS=yellow, SUPPRESSED=orange, PINNED=red
func _update_suppression_visual() -> void:
	if not _suppression_indicator:
		return

	# Hide indicator in NORMAL state
	if suppression_state == GameEnums.SuppressionState.NORMAL:
		_suppression_indicator.visible = false
		return

	_suppression_indicator.visible = true

	if _suppression_indicator.material_override:
		var mat: StandardMaterial3D = _suppression_indicator.material_override as StandardMaterial3D

		# Color based on state
		match suppression_state:
			GameEnums.SuppressionState.CAUTIOUS:
				mat.albedo_color = Color(1.0, 1.0, 0.0, 0.5)  # Yellow
			GameEnums.SuppressionState.SUPPRESSED:
				mat.albedo_color = Color(1.0, 0.5, 0.0, 0.7)  # Orange
			GameEnums.SuppressionState.PINNED:
				mat.albedo_color = Color(1.0, 0.0, 0.0, 0.9)  # Red


## Reload weapon
func reload() -> void:
	var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(primary_weapon)
	if weapon:
		current_ammo = weapon.magazine_size
		max_ammo = weapon.magazine_size


## Set cover state
func set_in_cover(in_cover: bool) -> void:
	is_in_cover = in_cover


## Set prone state
func set_prone(prone: bool) -> void:
	is_prone = prone
	# Prone units are harder to hit but slower
	if prone and _mesh_instance:
		_mesh_instance.scale.y = 0.3
		_mesh_instance.position.y = 0.3
	elif _mesh_instance:
		_mesh_instance.scale.y = 1.0
		_mesh_instance.position.y = 0.9


## Get weapon from squad data
func _get_weapon_for_faction() -> String:
	if not data:
		return "m16"

	# Assign weapon based on faction
	match data.faction:
		GameEnums.Faction.US_ARMY, GameEnums.Faction.ARVN:
			if data.is_vehicle:
				return "coax_mg"
			else:
				return "m16"
		GameEnums.Faction.VC, GameEnums.Faction.NVA:
			if data.is_vehicle:
				return "dshk"
			else:
				return "ak47"
		_:
			return "m16"


## Set selection visual state
func set_selected_visual(selected: bool) -> void:
	_is_selected = selected
	if _selection_ring:
		_selection_ring.visible = selected


## Check if this squad is selected
func is_selected() -> bool:
	return _is_selected


## Set preview highlight state (used during drag selection)
## Makes the unit appear lighter to indicate it will be selected
var _is_preview_highlighted: bool = false

func set_preview_highlight(highlighted: bool) -> void:
	if _is_preview_highlighted == highlighted:
		return

	_is_preview_highlighted = highlighted

	# Apply emission to make unit appear lighter
	if _model_node:
		_apply_preview_emission_recursive(_model_node, highlighted)
	elif _mesh_instance:
		_apply_preview_emission_recursive(_mesh_instance, highlighted)

	# Also brighten all soldiers in formation
	for soldier in _soldier_nodes:
		if is_instance_valid(soldier):
			_apply_preview_emission_recursive(soldier, highlighted)


## Apply emission to make meshes appear lighter during preview
func _apply_preview_emission_recursive(node: Node, enabled: bool) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		if enabled:
			# Store original materials and apply emission
			if not mesh_inst.has_meta("_preview_original_mats"):
				var orig_mats: Array = []
				if mesh_inst.mesh:
					for i in mesh_inst.mesh.get_surface_count():
						orig_mats.append(mesh_inst.get_active_material(i))
				mesh_inst.set_meta("_preview_original_mats", orig_mats)

			# Apply bright emission
			if mesh_inst.mesh:
				for i in mesh_inst.mesh.get_surface_count():
					var base_mat: Material = mesh_inst.get_active_material(i)
					if base_mat is StandardMaterial3D:
						var bright_mat: StandardMaterial3D = base_mat.duplicate() as StandardMaterial3D
						bright_mat.emission_enabled = true
						bright_mat.emission = Color(0.8, 0.9, 1.0)  # Slight blue-white glow
						bright_mat.emission_energy_multiplier = 0.6
						mesh_inst.set_surface_override_material(i, bright_mat)
		else:
			# Restore original materials
			if mesh_inst.has_meta("_preview_original_mats"):
				var orig_mats: Array = mesh_inst.get_meta("_preview_original_mats")
				if mesh_inst.mesh:
					for i in mini(orig_mats.size(), mesh_inst.mesh.get_surface_count()):
						mesh_inst.set_surface_override_material(i, orig_mats[i])
				mesh_inst.remove_meta("_preview_original_mats")

	for child in node.get_children():
		_apply_preview_emission_recursive(child, enabled)


func _setup_placeholder_visuals() -> void:
	# Try to load real 3D model first
	var model_loaded: bool = _try_load_model()

	if not model_loaded:
		# Fall back to placeholder mesh
		_create_placeholder_mesh()

	# Create selection ring - size based on formation
	_selection_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()

	# Calculate ring size based on squad size (formation footprint)
	var is_vehicle: bool = data.is_vehicle if data else false
	var squad_count: int = data.squad_size if data else 1
	var ring_radius: float

	if is_vehicle or squad_count <= 1:
		ring_radius = 1.0  # Single unit
	else:
		# Formation radius based on soldier count and spacing
		var cols: int = ceili(float(squad_count) / float(FORMATION_ROWS))
		ring_radius = (cols * SOLDIER_SPACING) / 2.0 + 0.5

	ring.inner_radius = ring_radius - 0.2
	ring.outer_radius = ring_radius
	ring.rings = 16
	ring.ring_segments = 32
	_selection_ring.mesh = ring
	_selection_ring.position.y = 0.05
	_selection_ring.rotation.x = 0  # Flat on ground

	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(0.2, 1.0, 0.2, 0.8)  # Green selection
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_ring.material_override = ring_material
	_selection_ring.visible = false

	add_child(_selection_ring)

	# Create suppression indicator (red overlay)
	_suppression_indicator = MeshInstance3D.new()
	var suppress_ring := TorusMesh.new()
	suppress_ring.inner_radius = 0.6
	suppress_ring.outer_radius = 0.7
	suppress_ring.rings = 12
	suppress_ring.ring_segments = 24
	_suppression_indicator.mesh = suppress_ring
	_suppression_indicator.position.y = 0.1

	var suppress_mat := StandardMaterial3D.new()
	suppress_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.0)  # Red, initially transparent
	suppress_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	suppress_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_suppression_indicator.material_override = suppress_mat
	_suppression_indicator.visible = false

	add_child(_suppression_indicator)

	# Create visibility indicators (outline + overhead marker)
	_create_visibility_indicators()


## Create blue outline and overhead marker for unit visibility
func _create_visibility_indicators() -> void:
	# Overhead marker - a sphere dot above the unit for tracking in jungle
	# 4x larger size for visibility through dense vegetation
	_overhead_marker = MeshInstance3D.new()
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 1.6  # 4x larger (was 0.4)
	marker_mesh.height = 3.2  # 4x larger (was 0.8)
	_overhead_marker.mesh = marker_mesh
	_overhead_marker.position.y = 6.0  # Higher to clear jungle canopy (was 4.0)

	var marker_mat := StandardMaterial3D.new()
	# Blue for player, red for enemy
	if is_player_controlled:
		marker_mat.albedo_color = Color(0.2, 0.6, 1.0, 1.0)  # Bright blue
	else:
		marker_mat.albedo_color = Color(1.0, 0.3, 0.2, 1.0)  # Red
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_overhead_marker.material_override = marker_mat
	_overhead_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(_overhead_marker)

	# Create outline mesh - a slightly larger version of the unit mesh
	_outline_mesh = MeshInstance3D.new()

	# Use a simple cylinder for the outline (matches placeholder)
	var is_vehicle: bool = data.is_vehicle if data else false
	if is_vehicle:
		var box := BoxMesh.new()
		box.size = Vector3(2.2, 1.7, 4.2)  # Slightly larger than unit
		_outline_mesh.mesh = box
		_outline_mesh.position.y = 0.75
	else:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.6
		cylinder.bottom_radius = 0.6
		cylinder.height = 2.0
		_outline_mesh.mesh = cylinder
		_outline_mesh.position.y = 0.9

	# Load and apply outline shader
	var outline_shader: Shader = load("res://battle_system/shaders/unit_outline.gdshader")
	if outline_shader:
		var outline_mat := ShaderMaterial.new()
		outline_mat.shader = outline_shader
		if is_player_controlled:
			outline_mat.set_shader_parameter("outline_color", Color(0.2, 0.5, 1.0, 1.0))  # Blue
		else:
			outline_mat.set_shader_parameter("outline_color", Color(1.0, 0.2, 0.2, 1.0))  # Red
		outline_mat.set_shader_parameter("outline_width", 0.05)
		_outline_mesh.material_override = outline_mat
	else:
		# Fallback to simple colored mesh if shader not found
		var fallback_mat := StandardMaterial3D.new()
		fallback_mat.albedo_color = Color(0.2, 0.5, 1.0, 0.5) if is_player_controlled else Color(1.0, 0.2, 0.2, 0.5)
		fallback_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_outline_mesh.material_override = fallback_mat

	_outline_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(_outline_mesh)


## Try to load the appropriate 3D model for this unit
## For infantry squads, spawns multiple soldiers in formation (BP RTS Dark Shadows style)
func _try_load_model() -> bool:
	var model_path: String = ""

	# First check if data has a custom model_path specified (from Model Viewer)
	if data and not data.model_path.is_empty():
		model_path = data.model_path
	else:
		# Fall back to automatic model selection based on unit type
		var model_key: String = _get_model_key()
		if model_key.is_empty():
			print("[Squad] No model key for unit - using placeholder")
			return false

		if not model_key in MODEL_PATHS:
			print("[Squad] No model path for key: ", model_key)
			return false

		model_path = MODEL_PATHS[model_key]

	if not ResourceLoader.exists(model_path):
		print("[Squad] Model not found: ", model_path)
		return false

	# Load the GLB scene
	var model_scene: PackedScene = load(model_path)
	if not model_scene:
		return false

	# Determine soldier count - vehicles get 1, infantry get squad_size
	var is_vehicle: bool = data.is_vehicle if data else false
	var soldier_count: int = 1
	if not is_vehicle and data:
		soldier_count = data.squad_size

	# For single model (vehicles), use simple approach
	if soldier_count <= 1:
		return _spawn_single_model(model_scene, model_path)

	# For multiple soldiers, spawn formation
	return _spawn_soldier_formation(model_scene, soldier_count, model_path)


## Spawn a single model (used for vehicles)
func _spawn_single_model(model_scene: PackedScene, model_path: String) -> bool:
	var model_instance: Node3D = model_scene.instantiate()
	if not model_instance:
		return false

	add_child(model_instance)
	model_instance.name = "Model"
	_model_node = model_instance

	# Apply custom transform from data (set via Model Viewer)
	# Also apply VISIBILITY_SCALE to make units easier to see in jungle
	var base_scale: float = data.model_scale if data and data.model_scale != 1.0 else 1.0
	model_instance.scale = Vector3.ONE * base_scale * VISIBILITY_SCALE
	if data:
		if data.model_rotation_y != 0.0:
			model_instance.rotation_degrees.y = data.model_rotation_y
		if data.model_offset_y != 0.0:
			model_instance.position.y = data.model_offset_y

	_apply_faction_tint(model_instance)
	_mesh_instance = _find_mesh_instance(model_instance)
	_setup_animator(model_instance)

	print("[Squad] Loaded single model: ", model_path)
	return true


## Spawn multiple soldiers in LINE formation (BP RTS Dark Shadows style)
func _spawn_soldier_formation(model_scene: PackedScene, count: int, model_path: String) -> bool:
	# Create container for formation
	_formation_container = Node3D.new()
	_formation_container.name = "Formation"
	add_child(_formation_container)

	# Calculate formation positions (LINE formation)
	var positions: Array[Vector3] = _calculate_line_formation(count)

	_soldier_nodes.clear()
	_alive_soldier_count = count

	for i in count:
		var soldier: Node3D = model_scene.instantiate()
		if not soldier:
			continue

		soldier.name = "Soldier_%d" % i
		soldier.position = positions[i] if i < positions.size() else Vector3.ZERO

		# Apply slight random rotation for natural look
		soldier.rotation.y = randf_range(-0.15, 0.15)

		# Apply custom transform from data + VISIBILITY_SCALE
		var soldier_scale: float = data.model_scale if data and data.model_scale != 1.0 else 1.0
		soldier.scale = Vector3.ONE * soldier_scale * VISIBILITY_SCALE
		if data:
			if data.model_rotation_y != 0.0:
				soldier.rotation_degrees.y += data.model_rotation_y
			if data.model_offset_y != 0.0:
				soldier.position.y = data.model_offset_y

		_apply_faction_tint(soldier)
		_formation_container.add_child(soldier)
		_soldier_nodes.append(soldier)

	# Use first soldier for mesh reference
	if _soldier_nodes.size() > 0:
		_mesh_instance = _find_mesh_instance(_soldier_nodes[0])
		_model_node = _formation_container

	# Set up animator for the formation
	_setup_animator(_formation_container)

	print("[Squad] Loaded formation with %d soldiers: %s" % [count, model_path])
	return true


## Calculate LINE formation positions for soldiers
## Creates a wide, shallow formation (standard infantry tactics)
func _calculate_line_formation(count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []

	# Calculate grid dimensions
	var rows: int = mini(FORMATION_ROWS, ceili(float(count) / 4.0))
	var cols: int = ceili(float(count) / float(rows))

	# Center the formation on origin
	var total_width: float = (cols - 1) * SOLDIER_SPACING
	var total_depth: float = (rows - 1) * SOLDIER_SPACING

	var soldier_idx: int = 0
	for row in rows:
		for col in cols:
			if soldier_idx >= count:
				break

			# Calculate position with slight randomness for organic look
			var x: float = (col - (cols - 1) / 2.0) * SOLDIER_SPACING + randf_range(-0.15, 0.15)
			var z: float = (row - (rows - 1) / 2.0) * SOLDIER_SPACING + randf_range(-0.15, 0.15)

			# Offset alternating rows for staggered formation
			if row % 2 == 1:
				x += SOLDIER_SPACING * 0.3

			positions.append(Vector3(x, 0, z))
			soldier_idx += 1

	return positions


## Hide soldiers when taking casualties (from back of formation)
func apply_casualty_visuals(remaining_soldiers: int) -> void:
	remaining_soldiers = clampi(remaining_soldiers, 0, _soldier_nodes.size())

	# Hide soldiers from the back (highest index first)
	for i in _soldier_nodes.size():
		var soldier: Node3D = _soldier_nodes[i]
		if is_instance_valid(soldier):
			soldier.visible = i < remaining_soldiers

	_alive_soldier_count = remaining_soldiers


## Get current visible soldier count
func get_alive_soldier_count() -> int:
	return _alive_soldier_count


## Get the model key based on unit type and faction
func _get_model_key() -> String:
	if not data:
		return ""

	var faction_val: int = data.faction
	var unit_type_val: int = data.unit_type
	var is_vehicle: bool = data.is_vehicle

	# US Army / ARVN
	if faction_val == GameEnums.Faction.US_ARMY or faction_val == GameEnums.Faction.ARVN:
		if is_vehicle:
			match unit_type_val:
				GameEnums.UnitType.BULLDOZER:
					return "us_bulldozer"
				GameEnums.UnitType.ARMOR:
					# Check if it's an APC by name
					if data.display_name.containsn("apc") or data.display_name.containsn("m113"):
						return "us_apc"
					return "us_tank"
				GameEnums.UnitType.HUEY_TRANSPORT, GameEnums.UnitType.HUEY_GUNSHIP:
					return "us_huey"
				_:
					return "us_halftrack"  # Default vehicle
		else:
			match unit_type_val:
				GameEnums.UnitType.RIFLE_PLATOON:
					return "us_rifle"
				GameEnums.UnitType.ENGINEERS:
					return "us_engineer"
				GameEnums.UnitType.WEAPONS_SQUAD:
					return "us_mortar"
				GameEnums.UnitType.SOG_TEAM:
					return "us_rifle"  # SOG uses same model
				_:
					return "us_rifle"  # Default infantry

	# VC
	elif faction_val == GameEnums.Faction.VC:
		if is_vehicle:
			return ""  # VC has no vehicles, use placeholder
		else:
			match unit_type_val:
				GameEnums.UnitType.VC_INFANTRY, GameEnums.UnitType.VC_LOCAL_FORCE:
					return "vc_rifle"
				GameEnums.UnitType.VC_SAPPERS:
					return "vc_sapper"
				GameEnums.UnitType.VC_MORTAR:
					return "vc_mortar"
				_:
					return "vc_rifle"  # Default VC

	# NVA - use VC models as stand-ins for now
	elif faction_val == GameEnums.Faction.NVA:
		if is_vehicle:
			return ""  # Use placeholder for NVA vehicles
		else:
			match unit_type_val:
				GameEnums.UnitType.NVA_INFANTRY:
					return "vc_rifle"
				GameEnums.UnitType.NVA_HEAVY_WEAPONS:
					return "vc_lmg"
				_:
					return "vc_rifle"

	return ""


## Apply faction color tint to model materials
func _apply_faction_tint(model: Node3D) -> void:
	var tint_color: Color = data.get_faction_color() if data else Color.WHITE
	# Make tint subtle - blend with white
	tint_color = tint_color.lerp(Color.WHITE, 0.5)

	# Find all MeshInstance3D nodes and apply tint
	for child in model.get_children():
		if child is MeshInstance3D:
			var mesh_inst: MeshInstance3D = child as MeshInstance3D
			# Create a new material with tint
			if mesh_inst.mesh:
				for i in mesh_inst.mesh.get_surface_count():
					var mat: Material = mesh_inst.mesh.surface_get_material(i)
					if mat is StandardMaterial3D:
						var new_mat: StandardMaterial3D = mat.duplicate()
						new_mat.albedo_color = new_mat.albedo_color * tint_color
						mesh_inst.set_surface_override_material(i, new_mat)
		# Recurse into children
		if child is Node3D:
			_apply_faction_tint(child)


## Find first MeshInstance3D in node tree
func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found:
			return found
	return null


## Create placeholder mesh when model not available
func _create_placeholder_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()

	var is_vehicle: bool = data.is_vehicle if data else false

	if is_vehicle:
		var box := BoxMesh.new()
		box.size = Vector3(2.0, 1.5, 4.0)
		_mesh_instance.mesh = box
		_mesh_instance.position.y = 0.75
	else:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.5
		cylinder.bottom_radius = 0.5
		cylinder.height = 1.8
		_mesh_instance.mesh = cylinder
		_mesh_instance.position.y = 0.9

	# Apply faction color
	var material := StandardMaterial3D.new()
	material.albedo_color = data.get_faction_color() if data else Color(0.5, 0.5, 0.5)
	_mesh_instance.material_override = material

	add_child(_mesh_instance)


func _setup_collision() -> void:
	_collision_shape = CollisionShape3D.new()

	var is_vehicle: bool = data.is_vehicle if data else false
	var squad_count: int = data.squad_size if data else 1

	if is_vehicle:
		var box := BoxShape3D.new()
		box.size = Vector3(2.0, 1.5, 4.0)
		_collision_shape.shape = box
		_collision_shape.position.y = 0.75
	elif squad_count > 1:
		# Infantry formation - use box to encompass all soldiers
		var cols: int = ceili(float(squad_count) / float(FORMATION_ROWS))
		var rows: int = mini(FORMATION_ROWS, ceili(float(squad_count) / 4.0))
		var width: float = cols * SOLDIER_SPACING + 0.5
		var depth: float = rows * SOLDIER_SPACING + 0.5

		var box := BoxShape3D.new()
		box.size = Vector3(width, 1.8, depth)
		_collision_shape.shape = box
		_collision_shape.position.y = 0.9
	else:
		# Single infantry unit
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.5
		capsule.height = 1.8
		_collision_shape.shape = capsule
		_collision_shape.position.y = 0.9

	add_child(_collision_shape)

	# Set collision layer based on faction
	if data:
		match data.faction:
			GameEnums.Faction.US_ARMY, GameEnums.Faction.ARVN:
				collision_layer = 2  # us_units layer
			GameEnums.Faction.VC:
				collision_layer = 4  # vc_units layer
			GameEnums.Faction.NVA:
				collision_layer = 8  # nva_units layer
	else:
		collision_layer = 2

	# Collide with terrain
	collision_mask = 1


func _apply_data() -> void:
	if not data:
		return

	max_health = data.get_total_health()
	current_health = max_health

	# Load training level from squad data (affects suppression)
	if "training_level" in data:
		training_level = data.training_level
	else:
		training_level = GameEnums.TrainingLevel.REGULAR

	# Update player control based on faction
	# Check if player faction
	var faction_val: int = data.faction
	is_player_controlled = (faction_val == GameEnums.Faction.US_ARMY or faction_val == GameEnums.Faction.ARVN)

	# Update group membership
	if is_player_controlled:
		if not is_in_group("player_units"):
			add_to_group("player_units")
		if is_in_group("enemy_units"):
			remove_from_group("enemy_units")
	else:
		if not is_in_group("enemy_units"):
			add_to_group("enemy_units")
		if is_in_group("player_units"):
			remove_from_group("player_units")

	# Set weapon based on faction
	primary_weapon = _get_weapon_for_faction()

	# Initialize ammo
	var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(primary_weapon)
	if weapon:
		current_ammo = weapon.magazine_size
		max_ammo = weapon.magazine_size


## Set up procedural animation system
func _setup_animator(model: Node3D) -> void:
	_animator = UnitAnimatorScript.new()
	add_child(_animator)

	# Determine if this is a vehicle or helicopter
	var is_vehicle_unit: bool = data.is_vehicle if data else false
	var is_helicopter: bool = false
	if data:
		var unit_type_val: int = data.unit_type
		is_helicopter = (unit_type_val == GameEnums.UnitType.HUEY_TRANSPORT or
						unit_type_val == GameEnums.UnitType.HUEY_GUNSHIP or
						unit_type_val == GameEnums.UnitType.COBRA or
						unit_type_val == GameEnums.UnitType.CHINOOK)

	_animator.setup(self, model, is_vehicle_unit, is_helicopter)


## Update animation based on current state
func _update_animation(_delta: float) -> void:
	if not _animator:
		return

	# Map Squad state to animator state (0=IDLE, 1=MOVING, 2=FIRING, 3=SUPPRESSED, 4=DEAD)
	var anim_state: int
	match state:
		State.IDLE:
			anim_state = 0  # IDLE
		State.MOVING:
			anim_state = 1  # MOVING
		State.COMBAT:
			anim_state = 2  # FIRING
		State.SUPPRESSED:
			anim_state = 3  # SUPPRESSED
		State.DEAD:
			anim_state = 4  # DEAD
		_:
			anim_state = 0  # IDLE

	_animator.set_state(anim_state)

	# Update turret target if in combat
	if current_target and _animator:
		_animator.set_turret_target(current_target.global_position)

	_animator.process_animation(_delta)


# =============================================================================
# BEHAVIOR TREE METHODS
# =============================================================================

## Assign a behavior tree preset to this squad.
## Uses SquadBehaviors autoload to create the appropriate tree.
## preset: SquadBehaviors.BehaviorPreset value
func assign_behavior_tree(preset: int) -> void:
	# Stop existing behavior tree if any
	if behavior_tree:
		behavior_tree.stop()
		behavior_tree = null  # RefCounted - will be freed when unreferenced

	# Get SquadBehaviors autoload
	var squad_behaviors: Node = get_node_or_null("/root/SquadBehaviors")
	if not squad_behaviors:
		push_warning("[Squad] SquadBehaviors autoload not found - cannot assign behavior tree")
		return

	if not squad_behaviors.has_method("create_behavior_for_squad"):
		push_warning("[Squad] SquadBehaviors missing create_behavior_for_squad method")
		return

	# Create behavior tree for this preset (BehaviorTree is RefCounted, not Node)
	behavior_tree = squad_behaviors.create_behavior_for_squad(self, preset)
	if behavior_tree:
		assigned_behavior = preset
		behavior_tree.start()
		print("[Squad] %s assigned behavior preset %d" % [name, preset])
	else:
		push_warning("[Squad] Failed to create behavior tree for preset %d" % preset)


## Sync current unit state to behavior tree blackboard.
## Called each tick before BT update.
func _sync_blackboard() -> void:
	if not behavior_tree:
		return

	var blackboard: Dictionary = behavior_tree.blackboard if "blackboard" in behavior_tree else {}

	# Core unit state
	blackboard["unit"] = self
	blackboard["state"] = state
	blackboard["position"] = global_position
	blackboard["rotation"] = rotation

	# Combat state
	blackboard["current_target"] = current_target
	blackboard["has_target"] = current_target != null and is_instance_valid(current_target)
	blackboard["attack_cooldown"] = attack_cooldown
	blackboard["current_ammo"] = current_ammo

	# Suppression state
	blackboard["suppression_level"] = suppression_level
	blackboard["suppression_state"] = suppression_state
	blackboard["is_suppressed"] = suppression_state >= GameEnums.SuppressionState.SUPPRESSED
	blackboard["is_pinned"] = suppression_state == GameEnums.SuppressionState.PINNED

	# Health state
	blackboard["current_health"] = current_health
	blackboard["max_health"] = max_health
	blackboard["health_ratio"] = current_health / max_health if max_health > 0.0 else 0.0

	# Movement state
	blackboard["has_move_order"] = has_move_order
	blackboard["move_target"] = move_target
	blackboard["is_moving"] = state == State.MOVING
	blackboard["velocity"] = velocity

	# Cover and stance
	blackboard["is_in_cover"] = is_in_cover
	blackboard["is_prone"] = is_prone

	# Faction info
	blackboard["is_player_controlled"] = is_player_controlled
	blackboard["faction"] = data.faction if data else 0

	# Write back
	if "blackboard" in behavior_tree:
		behavior_tree.blackboard = blackboard


## Pause behavior tree execution (when player gives direct orders)
func pause_behavior_tree() -> void:
	bt_paused = true
	if behavior_tree and behavior_tree.has_method("stop"):
		behavior_tree.stop()


## Resume behavior tree execution
func resume_behavior_tree() -> void:
	bt_paused = false
	if behavior_tree and behavior_tree.has_method("start"):
		behavior_tree.start()


## Check if this unit has a behavior tree assigned
func has_behavior_tree() -> bool:
	return behavior_tree != null


## Get the current behavior preset index
func get_behavior_preset() -> int:
	return assigned_behavior


## Sample terrain slope a small distance ahead in the movement direction.
## Returns 0..1 where 0 is flat and 1 is vertical (matches gameplay_grid convention).
func _sample_slope_ahead(move_dir: Vector3) -> float:
	var terrain := get_node_or_null("/root/TerrainIntegration")
	if not terrain:
		return 0.0

	# Look 1.5 m ahead for a useful slope reading
	var probe_pos: Vector3 = global_position + move_dir * 1.5

	if terrain.has_method("get_normal_at"):
		var normal: Vector3 = terrain.get_normal_at(probe_pos)
		# slope_val = 1.0 - normal.y, matches gameplay_grid line 132
		return clampf(1.0 - normal.y, 0.0, 1.0)

	# Fallback: compare current height vs probe height
	if terrain.has_method("get_height_at"):
		var h0: float = terrain.get_height_at(global_position)
		var h1: float = terrain.get_height_at(probe_pos)
		var rise: float = abs(h1 - h0)
		var run: float = 1.5
		# Convert angle to 0..1 (90 deg = 1.0)
		return clampf(atan2(rise, run) / (PI * 0.5), 0.0, 1.0)

	return 0.0
