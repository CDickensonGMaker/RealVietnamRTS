class_name Squad extends CharacterBody3D
## Squad - Basic selectable, moveable unit with combat capability
## Uses converted S3O models from Spring 1944

const SquadDataScript = preload("res://battle_system/data/squad_data.gd")
const VietnamWeaponDataScript = preload("res://battle_system/data/vietnam_weapon_data.gd")
const UnitAnimatorScript = preload("res://battle_system/systems/unit_animator.gd")
const WorkerControllerScript = preload("res://firebase_system/job_system/worker_controller.gd")
const SquadMoraleScript = preload("res://battle_system/morale/squad_morale.gd")
const MoraleConstants = preload("res://battle_system/morale/morale_constants.gd")
const PieceAnimatorScript = preload("res://battle_system/animation/piece_animator.gd")
const Spring1944PosesScript = preload("res://battle_system/animation/spring1944_poses.gd")

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
signal out_of_ammo  ## Emitted when unit cannot reload (no supply/water)
signal water_changed(current: int, maximum: int)
signal water_critical  ## Emitted when water < 20%
signal resources_depleted  ## Emitted when both ammo and water empty
signal morale_changed(current: float, maximum: float)
signal morale_state_changed(old_state: String, new_state: String)
signal unit_routing  ## Emitted when unit breaks and starts routing
signal unit_rallied  ## Emitted when unit recovers from routing
signal resupply_started  ## Emitted when unit begins seeking SupplyDepot
signal resupply_completed  ## Emitted when unit finishes resupply at depot
signal seeking_cover(cover_pos: Vector3)  ## Emitted when unit starts moving to cover
signal reached_cover(cover_type: int)  ## Emitted when unit arrives at cover position

enum State { IDLE, MOVING, COMBAT, SUPPRESSED, DEAD, CLEARING, ROUTING, RESUPPLYING }

## Standing order types (Rimworld-style persistent behaviors)
enum StandingOrder { NONE, PATROL, GUARD, AUTO_REPAIR }

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

# Morale system (Phase 3 PRD)
var _morale: RefCounted = null  # SquadMorale instance
var _route_target: Vector3 = Vector3.ZERO  # Firebase to route toward
var _morale_indicator: Label3D = null  # "BROKEN" / "RALLYING" floating text

# Cover and stance
var is_in_cover: bool = false
var is_prone: bool = false
var _current_cover_type: int = 0  # GameEnums.CoverType

# Cover-seeking behavior (Phase 4.2 - seek cover when under fire)
var _seeking_cover: bool = false
var _cover_seek_target: Vector3 = Vector3.ZERO
var _last_damage_source: Node3D = null  # Track who shot us for cover facing
var _cover_check_timer: float = 0.0
const COVER_CHECK_INTERVAL: float = 0.5  # How often to update cover status
const COVER_SEEK_RADIUS: float = 15.0  # Max distance to seek cover
const UNDER_FIRE_COVER_DELAY: float = 0.5  # How quickly to react to incoming fire

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

# Water tracking (PRD: internal resource that depletes over time)
var current_water: int = 100
var max_water: int = 100
var _water_depletion_timer: float = 0.0
const WATER_DEPLETION_INTERVAL: float = 1.0  # Check every second

# Resource status flags
var _is_low_water: bool = false
var _is_low_ammo: bool = false
const LOW_RESOURCE_THRESHOLD: float = 0.2  # 20%

# Auto-resupply tracking
var _resupply_check_timer: float = 0.0
const RESUPPLY_CHECK_INTERVAL: float = 2.0  # Check every 2 seconds

# Active resupply behavior (when seeking SupplyDepot)
var _resupply_target: Node3D = null  # The SupplyDepot we're moving toward
var _pre_resupply_standing_order: StandingOrder = StandingOrder.NONE  # Order to resume after resupply
var _pre_resupply_patrol_waypoints: Array[Vector3] = []  # Saved patrol waypoints
var _pre_resupply_guard_position: Vector3 = Vector3.ZERO  # Saved guard position
var _pre_resupply_guard_radius: float = 50.0  # Saved guard radius
const RESUPPLY_AMMO_THRESHOLD: float = 0.2  # 20% ammo triggers resupply behavior
const RESUPPLY_DEPOT_RANGE: float = 10.0  # Must be this close to depot to receive supplies

# Visual components (created at runtime)
var _mesh_instance: MeshInstance3D
var _selection_ring: MeshInstance3D
var _collision_shape: CollisionShape3D
var _suppression_indicator: MeshInstance3D
var _model_node: Node3D = null  # Reference to loaded GLB model
var _outline_mesh: MeshInstance3D = null  # Blue outline for visibility
var _overhead_marker: MeshInstance3D = null  # Dot above unit for tracking
var _status_indicator: Label3D = null  # "LOW WATER" / "LOW AMMO" floating text

# Multi-soldier formation visuals (BP RTS Dark Shadows style)
var _soldier_nodes: Array[Node3D] = []  # Individual soldier model instances
var _formation_container: Node3D = null  # Parent node for formation
var _alive_soldier_count: int = 0  # Tracks visible soldiers for casualties
const SOLDIER_SPACING: float = 1.2  # Space between soldiers in formation
const FORMATION_ROWS: int = 3  # Default formation depth
const VISIBILITY_SCALE: float = 1.25  # Scale up models 25% for visibility in jungle

# Animation
var _animator: Node = null  # UnitAnimator instance (for vehicles)
var _piece_animators: Array = []  # PieceAnimator instances (for piece-based infantry)
var _use_piece_animation: bool = false  # True if using Spring 1944 piece-based animation

# Selection state
var _is_selected: bool = false

# Attack-move mode: scan for enemies while moving
var _attack_move_mode: bool = false
var _attack_move_scan_timer: float = 0.0
const ATTACK_MOVE_SCAN_INTERVAL: float = 0.5  # Scan for enemies every 0.5s

# Auto-engagement: scan for enemies when idle/guarding
var auto_engage_enabled: bool = true  # Can be toggled off for stealth units
var _auto_engage_scan_timer: float = 0.0
const AUTO_ENGAGE_SCAN_INTERVAL: float = 0.75  # Scan for enemies every 0.75s when idle

# Survival XP throttle (award every second while suppressed)
var _survival_xp_timer: float = 0.0
const SURVIVAL_XP_INTERVAL: float = 1.0

# Cached autoload reference
var _veterancy_tracker: Node = null

# =============================================================================
# STANDING ORDERS (Rimworld-style persistent behaviors)
# =============================================================================

## Current standing order
var standing_order: StandingOrder = StandingOrder.NONE

## Patrol waypoints (for PATROL standing order)
var patrol_waypoints: Array[Vector3] = []

## Current patrol waypoint index
var _patrol_index: int = 0

## Guard position (for GUARD standing order)
var guard_position: Vector3 = Vector3.ZERO

## Guard radius (engage enemies within this distance)
var guard_radius: float = 50.0

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
	_setup_morale()

	# Add to appropriate groups
	if is_player_controlled:
		add_to_group("player_units")
		add_to_group("selectable_units")
	else:
		add_to_group("enemy_units")
	add_to_group("all_units")

	# Setup WorkerController for construction units (JobSystem)
	if data and data.can_build:
		_setup_worker_controller()

	# Connect to global morale events
	BattleSignals.nearby_squad_destroyed.connect(_on_nearby_squad_destroyed)

	BattleSignals.unit_spawned.emit(self, data.faction if data else 0)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	# Update behavior tree if assigned and not paused
	if behavior_tree and not bt_paused:
		_sync_blackboard()
		behavior_tree.update(delta)

	# Process resource depletion and resupply
	_process_resources(delta)

	# Process morale system (Phase 3)
	_process_morale(delta)

	# Process suppression decay
	_process_suppression(delta)

	# Process cover detection and seeking (Phase 4.2)
	_process_cover_behavior(delta)

	# Process combat cooldown
	if attack_cooldown > 0.0:
		attack_cooldown -= delta

	# Process combat if we have a target
	if state == State.ROUTING:
		_process_routing(delta)
	elif state == State.RESUPPLYING:
		_process_resupplying(delta)
	elif current_target and state == State.COMBAT:
		_process_combat(delta)
	elif is_clearing and state == State.CLEARING:
		_process_clearing(delta)
	elif has_move_order:
		_process_movement(delta)
	else:
		# Auto-engage: periodically scan for enemies when idle
		if auto_engage_enabled and state == State.IDLE:
			_auto_engage_scan_timer -= delta
			if _auto_engage_scan_timer <= 0.0:
				_auto_engage_scan_timer = AUTO_ENGAGE_SCAN_INTERVAL
				_scan_for_auto_engage_targets()

		# Process standing orders when idle
		if standing_order != StandingOrder.NONE:
			_process_standing_order(delta)
		else:
			# Idle separation - prevent bunching when stationary
			_process_idle_separation(delta)

	# Process procedural animation
	_update_animation(delta)

	# Always snap to terrain at end of physics to prevent slope drift
	_snap_to_terrain()


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

	# --- SLOPE EVALUATION (DISABLED) ---------------------------------------
	# Slope-based speed/blocking is nulled out for now: units move at full speed on
	# any terrain and are never "blocked by slope". Terrain physics will be dialed
	# back in later. _sample_slope_ahead / get_speed_at_slope are left in place but unused.
	_cached_slope = 0.0
	var speed: float = data.move_speed if data else 5.0

	# Apply suppression speed modifier (SUPPRESSED units crawl at 50% speed)
	speed *= get_suppression_speed_modifier()

	# Apply arrival slowdown
	if distance < ARRIVAL_SLOWDOWN_RADIUS:
		speed *= (distance / ARRIVAL_SLOWDOWN_RADIUS)

	# Calculate separation force to avoid bunching
	var separation: Vector3 = _calculate_separation()

	# Taper separation as we close on the target so seek wins at the destination.
	# At full strength near a shared job, mutual repulsion cancels the seek force and
	# units can never converge - they orbit and never register arrival.
	var separation_falloff: float = clampf(distance / ARRIVAL_SLOWDOWN_RADIUS, 0.0, 1.0)

	# Combine seek + (tapered) separation
	var combined_direction: Vector3 = seek_direction + separation * SEPARATION_WEIGHT * separation_falloff

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

	# Direct position move (slope physics nulled): bypass move_and_slide so the
	# CharacterBody can't depenetrate off slopes and slide. Snap Y to terrain after.
	global_position += velocity * delta
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
func _process_idle_separation(delta: float) -> void:
	var separation: Vector3 = _calculate_separation()

	# Only move if separation force is significant
	if separation.length() < 0.1:
		velocity = Vector3.ZERO
		# Still snap to terrain when idle to prevent drifting
		_snap_to_terrain()
		return

	# Move away slowly (half speed)
	var speed: float = (data.move_speed if data else 5.0) * 0.5
	velocity = separation.normalized() * speed

	# Direct position move (slope physics nulled), then snap Y to terrain
	global_position += velocity * delta
	_snap_to_terrain()


## Issue a move order to this squad
func move_to(target: Vector3) -> void:
	# Cancel cover seeking when given direct move order
	cancel_cover_seeking()

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
	# Cancel cover seeking when given direct move order
	cancel_cover_seeking()

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


## Scan for enemies when idle - auto-engage nearby threats
func _scan_for_auto_engage_targets() -> void:
	# Don't scan if suppressed, routing, dead, or auto-engage disabled
	if state == State.SUPPRESSED or state == State.ROUTING or state == State.DEAD:
		return
	if not auto_engage_enabled:
		return
	# Don't override existing target
	if current_target and is_instance_valid(current_target):
		return

	# Get weapon range from data
	var weapon_range: float = 300.0
	if data:
		weapon_range = data.attack_range if data.attack_range > 0 else 300.0

	# Query enemies using SpatialHashGrid if available
	var enemies: Array = []
	var grid: Node = get_node_or_null("/root/SpatialHashGrid")
	if grid and grid.has_method("get_enemies_in_radius"):
		var my_faction: int = data.faction if data else GameEnums.Faction.US_ARMY
		enemies = grid.get_enemies_in_radius(global_position, weapon_range, my_faction)
	else:
		# Fallback: use group queries
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
				var enemy_state: int = enemy.get("state")
				if enemy_state == State.DEAD:
					continue
			best_dist = dist
			best_target = enemy as Node3D

	# If found enemy in range, engage!
	if best_target:
		attack(best_target)


## Apply damage to this squad
func take_damage(amount: float, source: Node = null) -> void:
	if state == State.DEAD:
		return

	var old_health: float = current_health
	current_health -= amount
	health_changed.emit(current_health, max_health)
	BattleSignals.unit_damaged.emit(self, amount, source)

	# Track damage source for cover-seeking (Phase 4.2)
	if source and source is Node3D:
		_last_damage_source = source as Node3D
		# Trigger cover-seeking if not in good cover and not already seeking
		if not _seeking_cover and _current_cover_type < GameEnums.CoverType.HEAVY:
			_try_seek_cover_from_threat()

	# Update casualty visuals - hide soldiers based on health remaining
	if _soldier_nodes.size() > 1:
		var health_ratio: float = maxf(current_health / max_health, 0.0)
		var visible_soldiers: int = ceili(health_ratio * _soldier_nodes.size())
		var old_visible: int = ceili((old_health / max_health) * _soldier_nodes.size())

		# Trigger morale event for each casualty
		var casualties: int = old_visible - visible_soldiers
		if casualties > 0 and _morale:
			if casualties == 1:
				_morale.on_casualty(1)
			else:
				_morale.on_casualty(casualties)

		apply_casualty_visuals(visible_soldiers)

	if current_health <= 0:
		_die()


func _die() -> void:
	state = State.DEAD
	squad_died.emit(self)
	BattleSignals.unit_died.emit(self, null)

	# Emit signal for nearby morale effects
	BattleSignals.nearby_squad_destroyed.emit(global_position, data.faction if data else 0)

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

	# Select best weapon for target (Phase 4.2 - weapon selection)
	var weapon_to_use: String = primary_weapon
	if current_target is Node3D:
		weapon_to_use = select_weapon_for_target(current_target as Node3D)

	# Use CombatManager to fire
	if CombatManager:
		CombatManager.fire_weapon(self, current_target, weapon_to_use)

	# Trigger fire recoil animation
	if _animator:
		_animator.trigger_fire_recoil()

	# Consume ammo
	current_ammo -= 1

	# Auto-reload when magazine empty
	if current_ammo <= 0:
		if not reload():
			# Can't reload - stop firing (no supply or no firebase)
			return

	# Set cooldown based on weapon used
	var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(weapon_to_use)
	if weapon:
		attack_cooldown = 60.0 / weapon.rate_of_fire
	else:
		attack_cooldown = 1.0


## Set attack target and enter combat
func attack(target: Node) -> void:
	if state == State.DEAD:
		return

	# Cancel cover seeking when given direct attack order
	cancel_cover_seeking()

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

	var old_suppression: float = suppression_level

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

	# Notify morale of suppression recovery (Phase 4.3)
	if _morale and old_suppression - suppression_level >= 0.1:
		_morale.notify_suppression_change(old_suppression, suppression_level)

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
	if state == State.DEAD or state == State.ROUTING:
		return  # Don't override DEAD or ROUTING states

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

	var old_suppression: float = suppression_level

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

	# Notify morale system of significant suppression changes (Phase 4.3)
	if _morale and absf(suppression_level - old_suppression) >= 0.1:
		_morale.notify_suppression_change(old_suppression, suppression_level)

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


# =============================================================================
# COVER BEHAVIOR SYSTEM (Phase 4.2 - CoH-style cover seeking)
# =============================================================================

## Process cover detection and seeking behavior
func _process_cover_behavior(delta: float) -> void:
	# Skip if dead, routing, or vehicle (vehicles don't use cover)
	if state == State.DEAD or state == State.ROUTING:
		return
	if data and data.is_vehicle:
		return

	# Periodically check cover status at current position
	_cover_check_timer += delta
	if _cover_check_timer >= COVER_CHECK_INTERVAL:
		_cover_check_timer = 0.0
		_update_cover_status()

	# Process seeking cover movement
	if _seeking_cover:
		_process_cover_seeking(delta)


## Update cover status at current position using CoverSystem
func _update_cover_status() -> void:
	var cover_system: Node = get_node_or_null("/root/CoverSystem")
	if not cover_system:
		return

	_current_cover_type = cover_system.get_cover_for_unit(self)
	is_in_cover = _current_cover_type > GameEnums.CoverType.NONE

	# Emit signal if we arrived at cover while seeking
	if _seeking_cover and is_in_cover:
		var dist_to_target: float = global_position.distance_to(_cover_seek_target)
		if dist_to_target < 2.0:
			_seeking_cover = false
			reached_cover.emit(_current_cover_type)


## Try to find and move to cover when under fire
func _try_seek_cover_from_threat() -> void:
	# Don't seek cover if we have direct combat orders or are suppressed/pinned
	if state == State.COMBAT and current_target:
		return
	if suppression_state == GameEnums.SuppressionState.PINNED:
		return  # Pinned units can't move

	var cover_system: Node = get_node_or_null("/root/CoverSystem")
	if not cover_system:
		return

	# Find best cover position, preferring cover that faces threat
	var cover_pos: Vector3 = _find_best_cover_position(cover_system)
	if cover_pos == Vector3.ZERO:
		return  # No cover available

	# Start seeking cover
	_seeking_cover = true
	_cover_seek_target = cover_pos
	seeking_cover.emit(cover_pos)


## Find best cover position considering threat direction
func _find_best_cover_position(cover_system: Node) -> Vector3:
	# Use CoverSystem's find_nearest_cover as baseline
	var nearest_cover: Vector3 = Vector3.ZERO
	if cover_system.has_method("find_nearest_cover"):
		nearest_cover = cover_system.find_nearest_cover(global_position, COVER_SEEK_RADIUS)

	if nearest_cover == Vector3.ZERO:
		return Vector3.ZERO

	# If we know where threat came from, try to find cover that blocks LOS
	if _last_damage_source and is_instance_valid(_last_damage_source):
		var threat_dir: Vector3 = (_last_damage_source.global_position - global_position).normalized()
		# Prefer cover positions that are perpendicular or behind us relative to threat
		var cover_dir: Vector3 = (nearest_cover - global_position).normalized()
		var dot: float = threat_dir.dot(cover_dir)

		# If cover is toward the threat, it's still good (we get behind it)
		# But ideally cover is perpendicular (-0.5 to 0.5 dot)
		if dot > 0.7:
			# Cover is almost directly toward enemy - still usable but not ideal
			# Could search for alternatives here, but for MVP use nearest
			pass

	return nearest_cover


## Process movement toward cover position
func _process_cover_seeking(delta: float) -> void:
	if not _seeking_cover:
		return

	# Check if we arrived at cover
	var dist: float = global_position.distance_to(_cover_seek_target)
	if dist < 1.5:
		_seeking_cover = false
		_update_cover_status()
		return

	# Move toward cover (use faster speed when under fire)
	var direction: Vector3 = (_cover_seek_target - global_position).normalized()
	direction.y = 0

	var speed: float = (data.move_speed if data else 5.0) * 1.2  # 20% speed boost when seeking cover

	# Apply suppression modifier
	speed *= get_suppression_speed_modifier()

	velocity = direction * speed

	# Face movement direction
	var target_rotation: float = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)

	# Direct position move, then snap to terrain
	global_position += velocity * delta
	_snap_to_terrain()


## Select appropriate weapon based on target type and range
## Returns weapon ID string for VietnamWeaponData
func select_weapon_for_target(target: Node3D) -> String:
	if not data:
		return primary_weapon

	var distance: float = global_position.distance_to(target.global_position)

	# Check if target is a vehicle
	var target_is_vehicle: bool = false
	if target.has_method("get") and target.get("data"):
		var target_data: Resource = target.data
		if target_data and "is_vehicle" in target_data:
			target_is_vehicle = target_data.is_vehicle

	# Check available weapons from squad data
	var available_weapons: Array = []
	if "weapons" in data:
		available_weapons = data.weapons
	else:
		available_weapons = [primary_weapon]

	# Anti-vehicle weapons for vehicle targets
	# Use VietnamWeaponData's DamageType enum values
	const DAMAGE_TYPE_ARMOR_PIERCING: int = 4  # VietnamWeaponData.DamageType.ARMOR_PIERCING
	const DAMAGE_TYPE_EXPLOSIVE: int = 1  # VietnamWeaponData.DamageType.EXPLOSIVE

	if target_is_vehicle:
		for weapon_id in available_weapons:
			var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(weapon_id)
			if weapon:
				# Prefer armor-piercing for vehicles, explosive as secondary
				if weapon.damage_type == DAMAGE_TYPE_ARMOR_PIERCING:
					if distance <= weapon.effective_range:
						return weapon_id
				elif weapon.damage_type == DAMAGE_TYPE_EXPLOSIVE:
					if distance <= weapon.effective_range:
						return weapon_id

	# For infantry targets or if no AT weapon available, use primary
	# Check range-based selection
	var best_weapon: String = primary_weapon
	var best_range_match: float = INF

	for weapon_id in available_weapons:
		var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(weapon_id)
		if not weapon:
			continue

		# Skip AT weapons for infantry (AP and Explosive)
		if not target_is_vehicle:
			if weapon.damage_type == DAMAGE_TYPE_ARMOR_PIERCING:
				continue
			if weapon.damage_type == DAMAGE_TYPE_EXPLOSIVE:
				continue

		# Find weapon with best range match
		var range_diff: float = absf(weapon.effective_range - distance)
		if distance <= weapon.effective_range and range_diff < best_range_match:
			best_range_match = range_diff
			best_weapon = weapon_id

	return best_weapon


## Force seek cover (called by external AI systems)
func seek_cover_now() -> void:
	_try_seek_cover_from_threat()


## Check if currently seeking cover
func is_seeking_cover() -> bool:
	return _seeking_cover


## Get current cover type
func get_cover_type() -> int:
	return _current_cover_type


## Cancel cover seeking (e.g., when given new orders)
func cancel_cover_seeking() -> void:
	_seeking_cover = false
	_cover_seek_target = Vector3.ZERO


# =============================================================================
# RESOURCE SYSTEM (Ammo + Water)
# =============================================================================

## Process resource depletion and auto-resupply
func _process_resources(delta: float) -> void:
	# Water depletion over time
	_water_depletion_timer += delta
	if _water_depletion_timer >= WATER_DEPLETION_INTERVAL:
		_water_depletion_timer = 0.0
		_deplete_water()

	# Check for auto-resupply within firebase radius
	_resupply_check_timer += delta
	if _resupply_check_timer >= RESUPPLY_CHECK_INTERVAL:
		_resupply_check_timer = 0.0
		_check_auto_resupply()

	# Update resource status flags
	_update_resource_status()


## Deplete water over time
func _deplete_water() -> void:
	if current_water <= 0:
		return

	# Depletion rate from squad data (default ~1 per 30 sec)
	var depletion: float = data.water_consumption_rate if data else 0.033
	var water_loss: int = maxi(1, int(depletion * WATER_DEPLETION_INTERVAL * 30.0))

	var old_water: int = current_water
	current_water = maxi(0, current_water - water_loss)

	if current_water != old_water:
		water_changed.emit(current_water, max_water)

		# Check critical threshold
		var water_ratio: float = float(current_water) / float(max_water) if max_water > 0 else 0.0
		if water_ratio < LOW_RESOURCE_THRESHOLD and not _is_low_water:
			_is_low_water = true
			water_critical.emit()
			_update_status_indicators()


## Check for auto-resupply when within firebase influence radius
func _check_auto_resupply() -> void:
	var firebase: Node3D = _find_nearest_firebase()
	if not firebase:
		return

	# Check if firebase has resupply capability
	if not firebase.has_method("is_active") or not firebase.is_active():
		return

	# Auto-resupply water
	if current_water < max_water:
		var water_to_add: int = mini(10, max_water - current_water)  # 10 units per tick
		if firebase.has_method("consume_supply") and firebase.consume_supply(1):
			current_water += water_to_add
			current_water = mini(current_water, max_water)
			water_changed.emit(current_water, max_water)

			if _is_low_water and float(current_water) / float(max_water) >= LOW_RESOURCE_THRESHOLD:
				_is_low_water = false
				_update_status_indicators()


## Update resource status flags and check for depleted state
func _update_resource_status() -> void:
	var ammo_ratio: float = float(current_ammo) / float(max_ammo) if max_ammo > 0 else 0.0
	var water_ratio: float = float(current_water) / float(max_water) if max_water > 0 else 0.0

	var was_low_ammo: bool = _is_low_ammo
	_is_low_ammo = ammo_ratio < LOW_RESOURCE_THRESHOLD

	# Update indicators if status changed
	if was_low_ammo != _is_low_ammo:
		_update_status_indicators()

	# Check for fully depleted resources (triggers retreat behavior)
	if current_water <= 0 and current_ammo <= 0:
		resources_depleted.emit()

	# Trigger resupply behavior when ammo drops below threshold
	# Only if: not already resupplying, not in combat, not routing, not dead
	if ammo_ratio < RESUPPLY_AMMO_THRESHOLD and state != State.RESUPPLYING:
		if state != State.COMBAT and state != State.ROUTING and state != State.DEAD:
			_start_resupply_behavior()


## Get morale modifier based on water level (per PRD: -0.5/sec when < 20%)
func get_water_morale_modifier() -> float:
	var water_ratio: float = float(current_water) / float(max_water) if max_water > 0 else 1.0
	if water_ratio < LOW_RESOURCE_THRESHOLD:
		return -0.5  # Morale drain per second when dehydrated
	return 0.0


## Check if unit has critical resource shortage
func has_critical_shortage() -> bool:
	return _is_low_water or _is_low_ammo


## Get current water level
func get_water_level() -> int:
	return current_water


## Get water ratio (0.0 to 1.0)
func get_water_ratio() -> float:
	return float(current_water) / float(max_water) if max_water > 0 else 0.0


## Consume water (for special actions)
func consume_water(amount: int) -> bool:
	if current_water >= amount:
		current_water -= amount
		water_changed.emit(current_water, max_water)
		return true
	return false


## Add water (from resupply)
func add_water(amount: int) -> void:
	current_water = mini(current_water + amount, max_water)
	water_changed.emit(current_water, max_water)

	if _is_low_water and float(current_water) / float(max_water) >= LOW_RESOURCE_THRESHOLD:
		_is_low_water = false
		_update_status_indicators()


## Update floating status indicators (LOW WATER / LOW AMMO / EMPTY / RESUPPLYING)
func _update_status_indicators() -> void:
	if not _status_indicator:
		return

	var status_text: String = ""
	var status_color: Color = Color(1.0, 0.8, 0.0, 1.0)  # Default yellow

	# Resupplying state takes priority for status display
	if state == State.RESUPPLYING:
		status_text = "RESUPPLYING"
		status_color = Color(0.3, 0.8, 0.3, 1.0)  # Green - positive action
	elif current_water <= 0 and current_ammo <= 0:
		status_text = "EMPTY"
		status_color = Color(1.0, 0.2, 0.2, 1.0)  # Red
	elif _is_low_water and _is_low_ammo:
		status_text = "LOW SUPPLIES"
		status_color = Color(1.0, 0.5, 0.0, 1.0)  # Orange
	elif _is_low_water:
		status_text = "LOW WATER"
		status_color = Color(0.3, 0.7, 1.0, 1.0)  # Light blue
	elif _is_low_ammo:
		status_text = "LOW AMMO"
		status_color = Color(1.0, 0.8, 0.0, 1.0)  # Yellow

	_status_indicator.text = status_text
	_status_indicator.modulate = status_color
	_status_indicator.visible = not status_text.is_empty()


# =============================================================================
# RESUPPLY BEHAVIOR (Pillar 3: Physical Supply Chains)
# =============================================================================

## Start resupply behavior - save current order and seek nearest SupplyDepot
func _start_resupply_behavior() -> void:
	# Don't start if already resupplying or no depot available
	if state == State.RESUPPLYING:
		return

	var depot: Node3D = _find_nearest_supply_depot()
	if not depot:
		# No depot found - can't resupply, stay in current state
		return

	# Save current standing order to resume after resupply
	_pre_resupply_standing_order = standing_order
	_pre_resupply_patrol_waypoints = patrol_waypoints.duplicate()
	_pre_resupply_guard_position = guard_position
	_pre_resupply_guard_radius = guard_radius

	# Clear standing order while resupplying
	standing_order = StandingOrder.NONE

	# Set resupply target and state
	_resupply_target = depot
	state = State.RESUPPLYING
	has_move_order = true
	move_target = depot.global_position

	# Update visual indicator
	_update_status_indicators()

	resupply_started.emit()
	print("[Squad] %s starting resupply at depot %s (ammo: %d/%d)" % [
		name, depot.name, current_ammo, max_ammo
	])


## Process resupply state - move to depot and receive supplies
func _process_resupplying(delta: float) -> void:
	# Validate resupply target still exists
	if not is_instance_valid(_resupply_target):
		_cancel_resupply()
		return

	# Check if depot is still operational
	if _resupply_target.has_method("is_destroyed") and _resupply_target.is_destroyed():
		_cancel_resupply()
		return

	var distance: float = global_position.distance_to(_resupply_target.global_position)

	# If close enough to depot, receive supplies
	if distance <= RESUPPLY_DEPOT_RANGE:
		_receive_supplies_from_depot()
		return

	# Otherwise, move toward depot
	_process_movement(delta)


## Receive supplies from the target depot
func _receive_supplies_from_depot() -> void:
	if not is_instance_valid(_resupply_target):
		_cancel_resupply()
		return

	# Stop moving
	has_move_order = false
	velocity = Vector3.ZERO

	# Calculate how much supply we need
	var ammo_needed: int = max_ammo - current_ammo
	var water_needed: int = max_water - current_water
	var total_needed: float = float(ammo_needed + water_needed)

	# Try to withdraw supply from depot
	var supply_received: float = 0.0
	if _resupply_target.has_method("withdraw_supply"):
		supply_received = _resupply_target.withdraw_supply(total_needed)
	elif _resupply_target.has_method("get_available_supply"):
		# Fallback: check if depot has supply and consume it
		var available: float = _resupply_target.get_available_supply()
		supply_received = minf(available, total_needed)
		if supply_received > 0.0 and _resupply_target.has_method("withdraw_supply"):
			_resupply_target.withdraw_supply(supply_received)

	if supply_received > 0.0:
		# Distribute received supply between ammo and water
		var ammo_ratio: float = float(ammo_needed) / total_needed if total_needed > 0 else 0.5
		var ammo_restored: int = int(supply_received * ammo_ratio)
		var water_restored: int = int(supply_received * (1.0 - ammo_ratio))

		# Restore ammo
		current_ammo = mini(current_ammo + ammo_restored, max_ammo)

		# Restore water
		current_water = mini(current_water + water_restored, max_water)
		water_changed.emit(current_water, max_water)

		# Also restore some health (field medic treatment at depot)
		var health_restore: float = minf(supply_received * 0.1, max_health - current_health)
		if health_restore > 0.0:
			current_health = minf(current_health + health_restore, max_health)
			health_changed.emit(current_health, max_health)

		print("[Squad] %s resupplied: +%d ammo, +%d water, +%.0f health" % [
			name, ammo_restored, water_restored, health_restore
		])

	# Update resource status flags
	_is_low_ammo = float(current_ammo) / float(max_ammo) < LOW_RESOURCE_THRESHOLD if max_ammo > 0 else false
	_is_low_water = float(current_water) / float(max_water) < LOW_RESOURCE_THRESHOLD if max_water > 0 else false
	_update_status_indicators()

	# Complete resupply
	_complete_resupply()


## Complete resupply and return to previous duty
func _complete_resupply() -> void:
	_resupply_target = null
	state = State.IDLE

	resupply_completed.emit()

	# Restore previous standing order
	if _pre_resupply_standing_order != StandingOrder.NONE:
		match _pre_resupply_standing_order:
			StandingOrder.PATROL:
				if not _pre_resupply_patrol_waypoints.is_empty():
					set_patrol_route(_pre_resupply_patrol_waypoints)
			StandingOrder.GUARD:
				set_guard_position(_pre_resupply_guard_position, _pre_resupply_guard_radius)
			StandingOrder.AUTO_REPAIR:
				standing_order = StandingOrder.AUTO_REPAIR

	# Clear saved state
	_pre_resupply_standing_order = StandingOrder.NONE
	_pre_resupply_patrol_waypoints.clear()
	_pre_resupply_guard_position = Vector3.ZERO
	_pre_resupply_guard_radius = 50.0

	print("[Squad] %s resupply complete, resuming duty" % name)


## Cancel resupply (depot destroyed, etc.)
func _cancel_resupply() -> void:
	_resupply_target = null
	has_move_order = false

	# Try to find another depot
	var new_depot: Node3D = _find_nearest_supply_depot()
	if new_depot:
		_resupply_target = new_depot
		move_target = new_depot.global_position
		has_move_order = true
		print("[Squad] %s resupply target lost, rerouting to %s" % [name, new_depot.name])
	else:
		# No depot available - restore previous order and return to idle
		state = State.IDLE

		if _pre_resupply_standing_order != StandingOrder.NONE:
			match _pre_resupply_standing_order:
				StandingOrder.PATROL:
					if not _pre_resupply_patrol_waypoints.is_empty():
						set_patrol_route(_pre_resupply_patrol_waypoints)
				StandingOrder.GUARD:
					set_guard_position(_pre_resupply_guard_position, _pre_resupply_guard_radius)
				StandingOrder.AUTO_REPAIR:
					standing_order = StandingOrder.AUTO_REPAIR

		_pre_resupply_standing_order = StandingOrder.NONE
		_pre_resupply_patrol_waypoints.clear()
		print("[Squad] %s resupply cancelled - no depot available" % name)


## Find the nearest operational SupplyDepot
func _find_nearest_supply_depot() -> Node3D:
	var depots: Array[Node] = get_tree().get_nodes_in_group("supply_depots")
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for depot in depots:
		if not is_instance_valid(depot) or not depot is Node3D:
			continue

		# Check if depot is operational
		if depot.has_method("is_destroyed") and depot.is_destroyed():
			continue

		# Check faction compatibility (only resupply at friendly depots)
		var depot_faction: int = -1
		if "faction" in depot:
			depot_faction = depot.faction
		if depot_faction >= 0 and data:
			# Check if same faction or allied
			var my_faction: int = data.faction
			if depot_faction != my_faction:
				# TODO: Check alliance status if implemented
				continue

		# Check if depot has supply available
		if depot.has_method("get_available_supply"):
			var available: float = depot.get_available_supply()
			if available <= 0.0:
				continue

		var dist: float = global_position.distance_to((depot as Node3D).global_position)
		if dist < nearest_dist:
			nearest = depot as Node3D
			nearest_dist = dist

	return nearest


## SupplyDepot interface: Check if unit needs resupply
func needs_resupply() -> bool:
	var ammo_ratio: float = float(current_ammo) / float(max_ammo) if max_ammo > 0 else 1.0
	var water_ratio: float = float(current_water) / float(max_water) if max_water > 0 else 1.0
	var health_ratio: float = current_health / max_health if max_health > 0 else 1.0

	return ammo_ratio < 1.0 or water_ratio < 1.0 or health_ratio < 1.0


## SupplyDepot interface: Get total supply needed for full resupply
func get_supply_needed() -> float:
	var ammo_needed: float = float(max_ammo - current_ammo)
	var water_needed: float = float(max_water - current_water)
	return ammo_needed + water_needed


## SupplyDepot interface: Add supply from external source (depot auto-resupply)
func add_supply(amount: float) -> void:
	# Distribute supply between ammo and water based on need
	var ammo_needed: int = max_ammo - current_ammo
	var water_needed: int = max_water - current_water
	var total_needed: float = float(ammo_needed + water_needed)

	if total_needed <= 0.0:
		return

	var ammo_ratio: float = float(ammo_needed) / total_needed
	var ammo_to_add: int = int(amount * ammo_ratio)
	var water_to_add: int = int(amount * (1.0 - ammo_ratio))

	current_ammo = mini(current_ammo + ammo_to_add, max_ammo)
	current_water = mini(current_water + water_to_add, max_water)
	water_changed.emit(current_water, max_water)

	# Update status flags
	_is_low_ammo = float(current_ammo) / float(max_ammo) < LOW_RESOURCE_THRESHOLD if max_ammo > 0 else false
	_is_low_water = float(current_water) / float(max_water) < LOW_RESOURCE_THRESHOLD if max_water > 0 else false
	_update_status_indicators()


## SupplyDepot interface: Resupply from external source (alias for add_supply)
func resupply(amount: float) -> void:
	add_supply(amount)


## Check if currently seeking resupply
func is_resupplying() -> bool:
	return state == State.RESUPPLYING


## Force cancel resupply (player command override)
func cancel_resupply() -> void:
	if state != State.RESUPPLYING:
		return

	_resupply_target = null
	has_move_order = false
	state = State.IDLE

	# Restore previous order
	if _pre_resupply_standing_order != StandingOrder.NONE:
		match _pre_resupply_standing_order:
			StandingOrder.PATROL:
				if not _pre_resupply_patrol_waypoints.is_empty():
					set_patrol_route(_pre_resupply_patrol_waypoints)
			StandingOrder.GUARD:
				set_guard_position(_pre_resupply_guard_position, _pre_resupply_guard_radius)
			StandingOrder.AUTO_REPAIR:
				standing_order = StandingOrder.AUTO_REPAIR

	_pre_resupply_standing_order = StandingOrder.NONE
	_pre_resupply_patrol_waypoints.clear()

	print("[Squad] %s resupply cancelled by command" % name)


## Reload weapon - requires firebase supply
## Returns true if reload started, false if no supply available
const RESUPPLY_COST: int = 1  # Simple flat cost per reload

func reload() -> bool:
	var weapon: RefCounted = VietnamWeaponDataScript.get_weapon(primary_weapon)
	if not weapon:
		return false

	# Find nearest firebase
	var firebase: Node3D = _find_nearest_firebase()
	if not firebase:
		out_of_ammo.emit()
		return false

	# Hard stop: need supply (water is a modifier, not a hard stop)
	if firebase.has_method("can_units_fight") and not firebase.can_units_fight():
		out_of_ammo.emit()
		return false

	# Consume supply
	if firebase.has_method("consume_supply") and firebase.consume_supply(RESUPPLY_COST):
		current_ammo = weapon.magazine_size
		max_ammo = weapon.magazine_size
		return true

	out_of_ammo.emit()
	return false


## Find the nearest ACTIVE firebase within its influence radius
## PRD Phase 4: Firebase must have HQ building to provide supply/morale
func _find_nearest_firebase() -> Node3D:
	var firebases: Array[Node] = get_tree().get_nodes_in_group("firebases")
	var nearest: Node3D = null
	var nearest_dist: float = INF

	for fb in firebases:
		if not is_instance_valid(fb) or not fb is Node3D:
			continue

		# Check if firebase is active (has HQ building)
		var is_active: bool = true
		if fb.has_method("is_active"):
			is_active = fb.is_active()
		if not is_active:
			continue

		# Check if within firebase influence radius
		var in_influence: bool = false
		if fb.has_method("is_position_in_influence"):
			in_influence = fb.is_position_in_influence(global_position)
		else:
			# Fallback: use distance check
			var dist: float = global_position.distance_to(fb.global_position)
			in_influence = dist <= 150.0

		if in_influence:
			var dist: float = global_position.distance_to(fb.global_position)
			if dist < nearest_dist:
				nearest = fb as Node3D
				nearest_dist = dist

	return nearest


# =============================================================================
# MORALE SYSTEM (Phase 3 PRD - Total War-style routing)
# =============================================================================

## Set up morale component
func _setup_morale() -> void:
	_morale = SquadMoraleScript.new(self, training_level)
	if data:
		_morale.init_from_data(self, data)

	# Connect signals
	_morale.morale_changed.connect(_on_morale_changed)
	_morale.state_changed.connect(_on_morale_state_changed)
	_morale.unit_broken.connect(_on_unit_broken)
	_morale.unit_rallied.connect(_on_unit_rallied)
	_morale.unit_shattered.connect(_on_unit_shattered)

	# Create morale indicator (floating text)
	_morale_indicator = Label3D.new()
	_morale_indicator.text = ""
	_morale_indicator.font_size = 56
	_morale_indicator.position.y = 5.5  # Above status indicator
	_morale_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_morale_indicator.no_depth_test = true
	_morale_indicator.modulate = Color(1.0, 0.3, 0.3, 1.0)  # Red warning
	_morale_indicator.outline_modulate = Color(0, 0, 0, 1)
	_morale_indicator.outline_size = 4
	_morale_indicator.visible = false
	add_child(_morale_indicator)


## Process morale each frame
func _process_morale(delta: float) -> void:
	if not _morale or state == State.DEAD:
		return

	# Update morale continuous modifiers based on current conditions
	_update_morale_modifiers()

	# Tick morale system
	_morale.tick(delta)

	# Update morale indicator
	_update_morale_indicator()


## Update morale modifiers based on current state
func _update_morale_modifiers() -> void:
	if not _morale:
		return

	# Suppression affects morale
	match suppression_state:
		GameEnums.SuppressionState.NORMAL:
			_morale.set_suppressed(0)
		GameEnums.SuppressionState.CAUTIOUS:
			_morale.set_under_fire(true)
			_morale.set_suppressed(0)
		GameEnums.SuppressionState.SUPPRESSED:
			_morale.set_under_fire(true)
			_morale.set_suppressed(1)
		GameEnums.SuppressionState.PINNED:
			_morale.set_under_fire(true)
			_morale.set_suppressed(2)

	# Cover affects morale recovery
	_morale.set_in_cover(is_in_cover)

	# Resource levels affect morale
	_morale.set_low_ammo(_is_low_ammo)
	_morale.set_low_water(_is_low_water)
	_morale.set_no_ammo(current_ammo <= 0)
	_morale.set_no_water(current_water <= 0)

	# Firebase proximity affects morale
	var firebase: Node3D = _find_nearest_firebase()
	_morale.set_near_firebase(firebase != null)

	# Count nearby allies
	var nearby_allies: int = _count_nearby_allies()
	_morale.set_nearby_allies(nearby_allies)


## Count friendly units within 30m
func _count_nearby_allies() -> int:
	var grid := get_node_or_null("/root/SpatialHashGrid")
	if not grid:
		return 0

	var allies: Array[Node3D] = grid.get_units_in_radius(global_position, 30.0)
	var count: int = 0
	for ally in allies:
		if ally == self:
			continue
		if not is_instance_valid(ally):
			continue
		# Check if same faction
		if ally.is_in_group("player_units") == is_in_group("player_units"):
			count += 1

	return count


## Update floating morale indicator
func _update_morale_indicator() -> void:
	if not _morale_indicator or not _morale:
		return

	var morale_state: String = _morale.get_state()
	var indicator_text: String = ""
	var indicator_color: Color = Color(1.0, 0.3, 0.3, 1.0)

	match morale_state:
		"SHATTERED":
			indicator_text = "SHATTERED"
			indicator_color = Color(0.5, 0.0, 0.0, 1.0)  # Dark red
		"BROKEN":
			indicator_text = "BROKEN"
			indicator_color = Color(1.0, 0.2, 0.2, 1.0)  # Red
		"SHAKEN":
			indicator_text = "SHAKEN"
			indicator_color = Color(1.0, 0.5, 0.0, 1.0)  # Orange
		"WAVERING":
			if _morale.is_rallying():
				indicator_text = "RALLYING"
				indicator_color = Color(0.3, 1.0, 0.3, 1.0)  # Green
		"STEADY":
			if _morale.is_rallying():
				indicator_text = "RALLYING"
				indicator_color = Color(0.3, 1.0, 0.3, 1.0)  # Green

	_morale_indicator.text = indicator_text
	_morale_indicator.modulate = indicator_color
	_morale_indicator.visible = not indicator_text.is_empty()


## Handle morale changed signal
func _on_morale_changed(current: float, maximum: float) -> void:
	morale_changed.emit(current, maximum)


## Handle morale state changed signal
func _on_morale_state_changed(old_state: String, new_state: String) -> void:
	morale_state_changed.emit(old_state, new_state)


## Handle unit broken (starts routing)
func _on_unit_broken() -> void:
	_start_routing()
	unit_routing.emit()
	if BattleSignals.has_signal("unit_routing"):
		BattleSignals.unit_routing.emit(self)


## Handle unit rallied
func _on_unit_rallied() -> void:
	_stop_routing()
	unit_rallied.emit()
	if BattleSignals.has_signal("unit_rallied"):
		BattleSignals.unit_rallied.emit(self)


## Handle unit shattered (completely uncontrollable)
func _on_unit_shattered() -> void:
	# Shattered units may surrender or flee randomly
	pass


## Handle nearby friendly squad being destroyed
func _on_nearby_squad_destroyed(position: Vector3, faction: int) -> void:
	if state == State.DEAD or not _morale:
		return

	# Only affect units of the same faction
	var my_faction: int = data.faction if data else 0
	if faction != my_faction:
		return

	# Check distance - only affect units within 50m
	var distance: float = global_position.distance_to(position)
	if distance > 50.0:
		return

	# Apply morale penalty for seeing friendly squad wiped out
	_morale.apply_event(MoraleConstants.EVENT_SQUAD_WIPED_NEARBY)


## Start routing behavior - flee toward nearest firebase
func _start_routing() -> void:
	# Cancel any current orders
	current_target = null
	has_move_order = false
	is_clearing = false
	standing_order = StandingOrder.NONE

	# Find route target (nearest firebase or retreat point)
	var firebase: Node3D = _find_nearest_firebase()
	if firebase:
		_route_target = firebase.global_position
	else:
		# No firebase - flee away from enemies
		_route_target = global_position + Vector3(randf_range(-50, 50), 0, randf_range(-50, 50))

	state = State.ROUTING
	print("[Squad] %s is ROUTING toward %s" % [name, _route_target])


## Stop routing and return to normal
func _stop_routing() -> void:
	if state != State.ROUTING:
		return

	state = State.IDLE
	_route_target = Vector3.ZERO
	print("[Squad] %s RALLIED and stopped routing" % name)


## Process routing movement each frame
func _process_routing(delta: float) -> void:
	if state != State.ROUTING:
		return

	# Check if morale recovered enough to stop routing
	if _morale and not _morale.is_routing():
		_stop_routing()
		return

	# Move toward route target with speed bonus
	var direction: Vector3 = (_route_target - global_position)
	direction.y = 0

	var distance: float = direction.length()

	if distance < 5.0:
		# Reached route target - wait for rally
		velocity = Vector3.ZERO
		return

	# Routing units move faster (panic speed)
	var speed: float = (data.move_speed if data else 5.0) * MoraleConstants.ROUTE_SPEED_MULTIPLIER

	velocity = direction.normalized() * speed

	# Face movement direction
	var target_rotation: float = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)

	# Direct position move (slope physics nulled), then snap Y to terrain
	global_position += velocity * delta
	_snap_to_terrain()


## Check if unit can receive orders (not shattered, not ignoring orders)
func can_receive_orders() -> bool:
	if state == State.DEAD:
		return false
	if _morale and not _morale.can_receive_orders():
		return false
	return true


## Apply morale event (called by external systems)
func apply_morale_event(event_value: float) -> void:
	if _morale:
		_morale.apply_event(event_value)


## Get current morale value
func get_morale() -> float:
	return _morale.get_morale() if _morale else 100.0


## Get morale state name
func get_morale_state() -> String:
	return _morale.get_state() if _morale else "STEADY"


## Check if unit is routing
func is_unit_routing() -> bool:
	return state == State.ROUTING


## Check if unit is broken or shattered
func is_morale_broken() -> bool:
	return _morale.is_broken() if _morale else false


## Get morale accuracy modifier
func get_morale_accuracy_modifier() -> float:
	return _morale.get_accuracy_multiplier() if _morale else 1.0


## Get morale rate of fire modifier
func get_morale_rof_modifier() -> float:
	return _morale.get_rof_multiplier() if _morale else 1.0


## Get suppression stress level (0.0-1.0) indicating how close to breaking
## Combines suppression duration and morale state (Phase 4.3)
func get_suppression_stress() -> float:
	return _morale.get_suppression_stress() if _morale else 0.0


## Check if under sustained suppression (escalated morale drain active)
func is_under_sustained_suppression() -> bool:
	return _morale.is_under_sustained_suppression() if _morale else false


## Get how long unit has been continuously suppressed (seconds)
func get_suppression_duration() -> float:
	return _morale.get_suppression_duration() if _morale else 0.0


## Get faction for morale system
func get_faction() -> int:
	return data.faction if data else 0


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

	# Create status indicator (floating text for LOW WATER / LOW AMMO)
	_status_indicator = Label3D.new()
	_status_indicator.text = ""
	_status_indicator.font_size = 48
	_status_indicator.position.y = 4.5  # Below overhead marker
	_status_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_indicator.no_depth_test = true
	_status_indicator.modulate = Color(1.0, 0.8, 0.0, 1.0)  # Yellow warning
	_status_indicator.outline_modulate = Color(0, 0, 0, 1)
	_status_indicator.outline_size = 4
	_status_indicator.visible = false
	add_child(_status_indicator)

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
	# Movement uses direct position updates + terrain snapping (slope physics nulled),
	# so move_and_slide floor settings are not used. Left here for when physics returns.
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

	# Initialize water from squad data
	if "max_water" in data:
		max_water = data.max_water
		current_water = max_water
	else:
		max_water = 100
		current_water = 100


## Set up procedural animation system
func _setup_animator(model: Node3D) -> void:
	# Determine if this is a vehicle or helicopter
	var is_vehicle_unit: bool = data.is_vehicle if data else false
	var is_helicopter: bool = false
	var is_bulldozer: bool = false
	if data:
		var unit_type_val: int = data.unit_type
		is_helicopter = (unit_type_val == GameEnums.UnitType.HUEY_TRANSPORT or
						unit_type_val == GameEnums.UnitType.HUEY_GUNSHIP or
						unit_type_val == GameEnums.UnitType.COBRA or
						unit_type_val == GameEnums.UnitType.CHINOOK)
		is_bulldozer = (unit_type_val == GameEnums.UnitType.BULLDOZER)

	# For infantry (non-vehicle), try piece-based animation first
	if not is_vehicle_unit and not is_helicopter:
		# Preload poses and cycles once for all soldiers
		var poses: Dictionary = {}
		for pose_name: String in Spring1944PosesScript.POSES.keys():
			poses[pose_name] = Spring1944PosesScript.get_pose(pose_name)

		var cycles: Dictionary = {}
		for cycle_name: String in Spring1944PosesScript.CYCLES.keys():
			cycles[cycle_name] = Spring1944PosesScript.get_cycle(cycle_name)

		_piece_animators.clear()

		# Handle formation with multiple soldiers
		if _soldier_nodes.size() > 0:
			for soldier: Node3D in _soldier_nodes:
				var animator = PieceAnimatorScript.new()
				if animator.setup(soldier):
					animator.load_poses(poses)
					animator.load_cycles(cycles)
					animator.set_pose_immediate("stand_idle")
					_piece_animators.append(animator)

			if _piece_animators.size() > 0:
				_use_piece_animation = true
				return
		else:
			# Single model case
			var animator = PieceAnimatorScript.new()
			if animator.setup(model):
				animator.load_poses(poses)
				animator.load_cycles(cycles)
				animator.set_pose_immediate("stand_idle")
				_piece_animators.append(animator)
				_use_piece_animation = true
				return

	# Fall back to UnitAnimator for vehicles or models without pieces
	_animator = UnitAnimatorScript.new()
	add_child(_animator)
	_animator.setup(self, model, is_vehicle_unit, is_helicopter, is_bulldozer)


## Update animation based on current state
func _update_animation(delta: float) -> void:
	# Handle piece-based animation (Spring 1944 infantry)
	if _use_piece_animation and _piece_animators.size() > 0:
		_update_piece_animation(delta)
		return

	# Handle vehicle/legacy animation
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
		State.ROUTING:
			anim_state = 1  # MOVING (routing units run)
		State.CLEARING:
			anim_state = 0  # IDLE (clearing animation handled separately)
		_:
			anim_state = 0  # IDLE

	_animator.set_state(anim_state)

	# Update turret target if in combat
	if current_target and _animator:
		_animator.set_turret_target(current_target.global_position)

	_animator.process_animation(delta)


## Update piece-based animation for Spring 1944 infantry models
var _last_anim_state: State = State.IDLE
var _last_worker_state: int = -1  # Track worker state for animation priority
func _update_piece_animation(delta: float) -> void:
	# If this unit has a WorkerController, worker state takes priority over squad state
	# (WorkerController handles its own animation via _on_worker_state_changed)
	if _worker_controller:
		var wc_state: int = _worker_controller.state if "state" in _worker_controller else 0
		if wc_state != _last_worker_state:
			_last_worker_state = wc_state
			# Worker animation is handled by _on_worker_state_changed callback
			# Just update animators each frame
		for animator in _piece_animators:
			animator.update(delta)
		return

	# Detect state change and trigger appropriate pose/cycle for all soldiers
	if state != _last_anim_state:
		_last_anim_state = state
		for animator in _piece_animators:
			match state:
				State.IDLE:
					# Stop any playing cycle and blend to idle pose
					animator.stop_cycle("stand_idle")
					animator.set_pose("stand_idle")
				State.MOVING:
					# Use run cycle for faster movement, walk for slower
					var speed: float = velocity.length()
					if speed > data.move_speed * 0.6:
						animator.play_cycle("run")
					else:
						animator.play_cycle("walk")
				State.COMBAT:
					animator.stop_cycle()
					animator.set_pose("stand_aim")
				State.SUPPRESSED:
					animator.stop_cycle()
					animator.set_pose("pinned")
				State.DEAD:
					animator.stop_cycle()
					animator.set_pose("dead")
				State.ROUTING:
					animator.play_cycle("run")  # Routing units run away
				State.CLEARING:
					animator.play_cycle("work")  # Clearing uses work animation
				_:
					animator.stop_cycle()
					animator.set_pose("stand_idle")

	# Update all animators each frame
	for animator in _piece_animators:
		animator.update(delta)


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

	# Resource state (PRD Phase 2)
	blackboard["current_water"] = current_water
	blackboard["max_water"] = max_water
	blackboard["water_ratio"] = float(current_water) / float(max_water) if max_water > 0 else 0.0
	blackboard["is_low_water"] = _is_low_water
	blackboard["is_low_ammo"] = _is_low_ammo
	blackboard["has_critical_shortage"] = has_critical_shortage()

	# Suppression state
	blackboard["suppression_level"] = suppression_level
	blackboard["suppression_state"] = suppression_state
	blackboard["is_suppressed"] = suppression_state >= GameEnums.SuppressionState.SUPPRESSED
	blackboard["is_pinned"] = suppression_state == GameEnums.SuppressionState.PINNED
	# Phase 4.3: Suppression-morale integration
	blackboard["suppression_stress"] = get_suppression_stress()
	blackboard["suppression_duration"] = get_suppression_duration()
	blackboard["is_sustained_suppression"] = is_under_sustained_suppression()

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

	# Morale state (PRD Phase 3)
	blackboard["morale"] = get_morale()
	blackboard["morale_state"] = get_morale_state()
	blackboard["is_routing"] = is_unit_routing()
	blackboard["is_morale_broken"] = is_morale_broken()
	blackboard["can_receive_orders"] = can_receive_orders()

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


# =============================================================================
# STANDING ORDER METHODS
# =============================================================================

## Set patrol route with waypoints
func set_patrol_route(waypoints: Array[Vector3]) -> void:
	if waypoints.is_empty():
		cancel_standing_order()
		return

	standing_order = StandingOrder.PATROL
	patrol_waypoints = waypoints
	_patrol_index = 0
	_move_to_next_patrol_point()
	print("[Squad] %s set patrol route with %d waypoints" % [name, waypoints.size()])


## Move to the next patrol waypoint (cycles through list)
func _move_to_next_patrol_point() -> void:
	if patrol_waypoints.is_empty():
		return

	move_to(patrol_waypoints[_patrol_index])
	_patrol_index = (_patrol_index + 1) % patrol_waypoints.size()


## Set guard position
func set_guard_position(pos: Vector3, radius: float = 50.0) -> void:
	standing_order = StandingOrder.GUARD
	guard_position = pos
	guard_radius = radius
	move_to(pos)
	print("[Squad] %s set guard position at %s (radius %.0fm)" % [name, pos, radius])


## Cancel current standing order
func cancel_standing_order() -> void:
	standing_order = StandingOrder.NONE
	patrol_waypoints.clear()
	_patrol_index = 0


## Process standing orders (called from _physics_process when idle)
func _process_standing_order(_delta: float) -> void:
	match standing_order:
		StandingOrder.PATROL:
			# If arrived at waypoint, move to next
			if not has_move_order and state == State.IDLE:
				_move_to_next_patrol_point()

		StandingOrder.GUARD:
			# If enemies nearby, engage; otherwise return to guard position
			if state == State.IDLE and not has_move_order:
				var dist_to_guard: float = global_position.distance_to(guard_position)
				if dist_to_guard > 5.0:  # Return to guard position if wandered too far
					move_to(guard_position)

		StandingOrder.AUTO_REPAIR:
			# Engineers auto-repair nearby structures
			pass  # Implemented elsewhere


## Get standing order name for debug
func get_standing_order_name() -> String:
	match standing_order:
		StandingOrder.NONE: return "None"
		StandingOrder.PATROL: return "Patrol"
		StandingOrder.GUARD: return "Guard"
		StandingOrder.AUTO_REPAIR: return "Auto-Repair"
		_: return "Unknown"


# =============================================================================
# WORKER CONTROLLER (NEW JOB SYSTEM)
# =============================================================================

## Reference to WorkerController (for new JobSystem)
var _worker_controller: Node = null


## Set up WorkerController for engineer/bulldozer units
func _setup_worker_controller() -> void:
	# Only add if JobSystem autoload exists
	var job_system: Node = get_node_or_null("/root/JobSystem")
	if not job_system:
		return  # New system not active yet

	# Create and attach WorkerController
	_worker_controller = WorkerControllerScript.new()
	_worker_controller.name = "WorkerController"

	# Configure based on unit type
	if data.is_vehicle:
		_worker_controller.worker_class = "bulldozer"
		_worker_controller.move_speed = data.move_speed if data else 5.0
	else:
		_worker_controller.worker_class = "engineer"
		_worker_controller.move_speed = data.move_speed if data else 8.0

	add_child(_worker_controller)

	# Connect to state changes to update animator (blade animation for bulldozers)
	if _worker_controller.has_signal("state_changed"):
		_worker_controller.state_changed.connect(_on_worker_state_changed)

	print("[Squad] Added WorkerController to %s (%s)" % [name, _worker_controller.worker_class])


## Get the WorkerController if attached
func get_worker_controller() -> Node:
	return _worker_controller


## Check if this unit has a WorkerController
func has_worker_controller() -> bool:
	return _worker_controller != null


## Handle worker state changes (triggers animations for workers)
## WorkerController.State: IDLE=0, MOVING_TO_JOB=1, WORKING=2, RETURNING=3, CLEARING_PATH=4
func _on_worker_state_changed(old_state: int, new_state: int) -> void:
	# Handle piece-based animation for infantry engineers
	if _use_piece_animation and _piece_animators.size() > 0:
		_update_worker_piece_animation(new_state)
		return

	# Handle vehicle animator (bulldozers)
	if not _animator:
		return

	var is_working: bool = (new_state == 2)  # State.WORKING

	if _animator.has_method("set_working"):
		_animator.set_working(is_working)


## Update piece-based animation based on worker controller state
func _update_worker_piece_animation(worker_state: int) -> void:
	# WorkerController.State: IDLE=0, MOVING_TO_JOB=1, WORKING=2, RETURNING=3, CLEARING_PATH=4
	for animator in _piece_animators:
		match worker_state:
			0:  # IDLE
				animator.stop_cycle()
				animator.set_pose("stand_idle")
			1:  # MOVING_TO_JOB
				animator.play_cycle("walk")
			2:  # WORKING
				animator.play_cycle("work")
			3:  # RETURNING
				animator.play_cycle("walk")
			4:  # CLEARING_PATH
				animator.play_cycle("work")
			_:
				animator.stop_cycle()
				animator.set_pose("stand_idle")


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
