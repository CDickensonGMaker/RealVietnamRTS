extends CharacterBody3D
## class_name Squad  # ARCHIVED
## Squad - Base class for all infantry squads in Vietnam Firebase Defense

signal squad_selected()
signal squad_deselected()
signal contact_spotted(position: Vector3, contact_type: String)
signal taking_fire()
signal squad_destroyed()
signal ammo_low()
signal morale_broken()

# Preloaded classes (avoid forward reference issues)
const BTNodeClass = preload("res://battle_system/ai/behavior_tree/bt_node.gd")

@export var unit_data: Resource  # VietnamUnitData

# Squad identification
var squad_name: String = "Rifle Squad"
var squad_id: int = 0

# Squad composition
var squad_size: int = 10
var max_squad_size: int = 12
var faction: int = GameEnums.Faction.US_ARMY

# Movement
var move_speed: float = 5.0
var rotation_speed: float = 5.0

# Combat stats
var sight_range: float = 30.0
var attack_range: float = 25.0
var damage_per_second: float = 10.0
var accuracy: float = 0.7

# Resources
var max_ammo: int = 100
var current_ammo: int = 100

# Health and morale
var squad_health: float = 100.0
var morale: float = 100.0
var suppression: float = 0.0

# State
enum SquadState { IDLE, MOVING, ATTACKING, SUPPRESSED, BUILDING, GARRISONED, ROUTING }
var current_state: SquadState = SquadState.IDLE

# Standing orders
enum StandingOrder { GUARD, PATROL, AGGRESSIVE, DEFENSIVE, RECON }
var standing_order: StandingOrder = StandingOrder.GUARD

# Navigation
var nav_agent: NavigationAgent3D
var move_target: Vector3 = Vector3.ZERO
var waypoint_queue: Array[Vector3] = []
var patrol_waypoints: Array[Vector3] = []
var current_patrol_index: int = 0

# Combat
var current_target: Node3D = null
var enemies_in_sight: Array[Node3D] = []

# Selection
var is_selected: bool = false

# Cover
var current_cover: String = "none"  # none, light, medium, heavy

func _ready() -> void:
	add_to_group("squads")

	# Apply unit data if provided
	if unit_data:
		_apply_unit_data()
	else:
		_apply_defaults()

	# Determine group based on faction
	if GameEnums.is_us_faction(faction):
		add_to_group("player_units")
		add_to_group("us_forces")
	else:
		add_to_group("enemy_units")

	# Setup navigation
	nav_agent = NavigationAgent3D.new()
	nav_agent.path_desired_distance = 1.0
	nav_agent.target_desired_distance = 2.0
	add_child(nav_agent)
	nav_agent.velocity_computed.connect(_on_velocity_computed)

	# Create visual placeholder
	_create_visual()

	# Register with spatial hash
	SpatialHashGrid.register_unit(self, faction)

	# Connect to signals
	BattleSignals.unit_spawned.emit(self, faction)

var visual_mesh: MeshInstance3D = null

func _create_visual() -> void:
	## Create placeholder visual for squad
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.6
	mesh.height = 1.8

	var mat := StandardMaterial3D.new()

	# Color based on faction
	if GameEnums.is_us_faction(faction):
		mat.albedo_color = Color(0.2, 0.4, 0.2)  # OD Green
	else:
		mat.albedo_color = Color(0.3, 0.25, 0.2)  # Brown/khaki

	visual_mesh = MeshInstance3D.new()
	visual_mesh.mesh = mesh
	visual_mesh.material_override = mat
	visual_mesh.position.y = 0.9

	add_child(visual_mesh)

	# Add squad size indicator (small spheres)
	_update_squad_size_indicator()

func _update_squad_size_indicator() -> void:
	## Visual indicator of squad strength
	# Clear existing indicators
	for child in get_children():
		if child.name.begins_with("strength_"):
			child.queue_free()

	# Create new indicators (simplified - just change color intensity)
	if visual_mesh:
		var mat := visual_mesh.material_override as StandardMaterial3D
		if mat:
			var strength_ratio := float(squad_size) / float(max_squad_size)
			mat.albedo_color.a = 0.5 + strength_ratio * 0.5

func _exit_tree() -> void:
	SpatialHashGrid.unregister_unit(self, faction)

func _apply_unit_data() -> void:
	squad_name = unit_data.unit_name
	squad_size = unit_data.default_size
	max_squad_size = unit_data.max_size
	faction = unit_data.faction
	move_speed = unit_data.move_speed
	sight_range = unit_data.sight_range
	attack_range = unit_data.attack_range
	damage_per_second = unit_data.damage_per_second
	accuracy = unit_data.base_accuracy
	max_ammo = unit_data.max_ammo
	current_ammo = max_ammo
	morale = unit_data.base_morale

func _apply_defaults() -> void:
	current_ammo = max_ammo

func _physics_process(delta: float) -> void:
	_update_suppression(delta)
	_update_morale(delta)
	_scan_for_enemies()

	match current_state:
		SquadState.MOVING:
			_process_movement(delta)
		SquadState.ATTACKING:
			_process_combat(delta)
		SquadState.IDLE:
			_process_idle(delta)
		SquadState.SUPPRESSED:
			_process_suppressed(delta)
		SquadState.ROUTING:
			_process_routing(delta)
		SquadState.GARRISONED:
			_process_garrisoned(delta)

	# Update spatial hash
	SpatialHashGrid.update_unit_position(self)

# =============================================================================
# STATE UPDATES
# =============================================================================

func _update_suppression(delta: float) -> void:
	# Suppression decays over time
	var resistance := 0.5
	if unit_data:
		resistance = unit_data.suppression_resistance

	suppression = maxf(0, suppression - 10 * resistance * delta)

	# High suppression forces suppressed state
	if suppression > 80 and current_state != SquadState.ROUTING:
		current_state = SquadState.SUPPRESSED

func _update_morale(delta: float) -> void:
	# Morale recovery when not suppressed
	if suppression < 30 and current_state != SquadState.ROUTING:
		var recovery_rate := 5.0
		if unit_data:
			recovery_rate = unit_data.morale_recovery_rate

		morale = minf(100, morale + recovery_rate * delta)

	# Check for rout
	if morale <= 0 and current_state != SquadState.ROUTING:
		_begin_rout()

# =============================================================================
# MOVEMENT
# =============================================================================

func move_to(target: Vector3, queue: bool = false) -> void:
	if queue:
		waypoint_queue.append(target)
	else:
		waypoint_queue.clear()
		_navigate_to(target)

func _navigate_to(target: Vector3) -> void:
	move_target = target
	nav_agent.target_position = target
	current_state = SquadState.MOVING

func _process_movement(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		_on_destination_reached()
		return

	var next_pos := nav_agent.get_next_path_position()
	var direction := (next_pos - global_position).normalized()

	# Face movement direction
	if direction.length() > 0.1:
		var target_rotation := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)

	# Speed reduction from suppression
	var speed_modifier := 1.0 - (suppression / 200.0)
	var final_speed := move_speed * speed_modifier

	velocity = direction * final_speed
	nav_agent.set_velocity(velocity)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()

func _on_destination_reached() -> void:
	if waypoint_queue.is_empty():
		current_state = SquadState.IDLE

		# Patrol looping
		if standing_order == StandingOrder.PATROL and not patrol_waypoints.is_empty():
			current_patrol_index = (current_patrol_index + 1) % patrol_waypoints.size()
			await get_tree().create_timer(1.0).timeout
			move_to(patrol_waypoints[current_patrol_index])
	else:
		var next: Vector3 = waypoint_queue.pop_front()
		_navigate_to(next)

# =============================================================================
# COMBAT
# =============================================================================

func attack(target: Node3D) -> void:
	if not is_instance_valid(target):
		return

	current_target = target
	current_state = SquadState.ATTACKING

func _process_combat(delta: float) -> void:
	if not is_instance_valid(current_target):
		current_target = null
		current_state = SquadState.IDLE
		return

	# Face target
	var direction := (current_target.global_position - global_position).normalized()
	var target_rotation := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)

	# Check range
	var distance := global_position.distance_to(current_target.global_position)
	if distance > attack_range:
		move_to(current_target.global_position)
		return

	# Fire
	if current_ammo > 0:
		_fire_at_target(delta)
	else:
		ammo_low.emit()

func _fire_at_target(delta: float) -> void:
	if not current_target:
		return

	# Calculate damage
	var damage = CombatManager.calculate_damage(
		unit_data.primary_weapon if unit_data else GameEnums.WeaponClass.M16,
		self,
		current_target
	)

	if damage.hit and current_target.has_method("take_damage"):
		current_target.take_damage(damage.final_damage, self)
		BattleSignals.unit_damaged.emit(current_target, damage.final_damage, self)

	# Suppression always applies
	if current_target.has_method("apply_suppression"):
		current_target.apply_suppression(damage.suppression * delta)

	# Consume ammo
	current_ammo -= 1

func _scan_for_enemies() -> void:
	enemies_in_sight.clear()

	# Use spatial hash for efficient queries
	var nearby := SpatialHashGrid.get_enemies_in_radius(
		global_position, sight_range, faction
	)

	for enemy in nearby:
		if is_instance_valid(enemy):
			# Check line of sight
			if has_line_of_sight_to(enemy):
				# Check visibility (stealth, concealment)
				var visibility := get_visibility_of(enemy)
				if visibility > 0.2:  # Threshold to detect
					enemies_in_sight.append(enemy)
					contact_spotted.emit(enemy.global_position, "infantry")

	# Award experience for spotting enemies
	if not enemies_in_sight.is_empty():
		add_experience(0.1)

# =============================================================================
# IDLE BEHAVIOR
# =============================================================================

func _process_idle(delta: float) -> void:
	match standing_order:
		StandingOrder.GUARD:
			if not enemies_in_sight.is_empty():
				attack(enemies_in_sight[0])
		StandingOrder.AGGRESSIVE:
			if not enemies_in_sight.is_empty():
				attack(_get_closest_enemy())
		StandingOrder.PATROL:
			if patrol_waypoints.is_empty():
				return
			move_to(patrol_waypoints[current_patrol_index])

func _process_suppressed(delta: float) -> void:
	# Can't do much while suppressed
	if suppression < 50:
		current_state = SquadState.IDLE

func _process_routing(delta: float) -> void:
	# Run away from enemies
	if enemies_in_sight.is_empty():
		# Try to rally
		morale += 5 * delta
		if morale > 30:
			current_state = SquadState.IDLE
			BattleSignals.unit_rallied.emit(self)
	else:
		# Flee from nearest enemy
		var nearest := _get_closest_enemy()
		if nearest:
			var flee_dir := (global_position - nearest.global_position).normalized()
			velocity = flee_dir * move_speed * 1.5
			move_and_slide()

func _get_closest_enemy() -> Node3D:
	var closest: Node3D = null
	var closest_dist := INF

	for enemy in enemies_in_sight:
		if is_instance_valid(enemy):
			var dist := global_position.distance_to(enemy.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = enemy

	return closest

# =============================================================================
# DAMAGE & MORALE
# =============================================================================

func take_damage(amount: float, source: Node3D = null) -> void:
	squad_health -= amount
	taking_fire.emit()

	# Suppression from incoming fire
	suppression = minf(100, suppression + amount * 0.5)

	# Morale damage
	morale -= amount * 0.2

	BattleSignals.unit_suppressed.emit(self, suppression)

	if squad_health <= 0:
		_squad_casualty()

func apply_suppression(amount: float) -> void:
	suppression = minf(100, suppression + amount)
	BattleSignals.unit_suppressed.emit(self, suppression)

func _squad_casualty() -> void:
	squad_size -= 1
	squad_health = 100.0
	morale -= 10

	BattleSignals.squad_member_lost.emit(self, squad_size)

	if squad_size <= 0:
		squad_destroyed.emit()
		BattleSignals.unit_died.emit(self, current_target)
		queue_free()

func _begin_rout() -> void:
	current_state = SquadState.ROUTING
	morale_broken.emit()
	BattleSignals.unit_routed.emit(self)

# =============================================================================
# SELECTION
# =============================================================================

func select() -> void:
	is_selected = true
	squad_selected.emit()
	BattleSignals.unit_selected.emit(self)

func deselect() -> void:
	is_selected = false
	squad_deselected.emit()
	BattleSignals.unit_deselected.emit(self)

# =============================================================================
# UTILITIES
# =============================================================================

func get_faction() -> int:
	return faction

func get_suppression() -> float:
	return suppression

func get_morale() -> float:
	return morale

func get_accuracy() -> float:
	return accuracy * (1.0 - suppression / 150.0)

func is_moving() -> bool:
	return current_state == SquadState.MOVING

func get_cover_level() -> String:
	return current_cover

func set_patrol_route(waypoints: Array[Vector3]) -> void:
	patrol_waypoints = waypoints
	standing_order = StandingOrder.PATROL
	if not patrol_waypoints.is_empty():
		current_patrol_index = 0
		move_to(patrol_waypoints[0])

func resupply(ammo_amount: int) -> void:
	current_ammo = mini(max_ammo, current_ammo + ammo_amount)

func get_squad_size() -> int:
	return squad_size

func is_enemy() -> bool:
	return GameEnums.is_enemy_faction(faction)

# =============================================================================
# COVER SYSTEM INTEGRATION
# =============================================================================

func enter_cover(cover_position: Vector3) -> bool:
	if CoverSystem and CoverSystem.has_method("enter_cover"):
		var success: bool = CoverSystem.enter_cover(self, cover_position)
		if success:
			current_cover = "medium"  # Will be updated by cover system
			return true
	return false

func leave_cover() -> void:
	if CoverSystem and CoverSystem.has_method("leave_cover"):
		CoverSystem.leave_cover(self)
	current_cover = "none"

func find_cover() -> Vector3:
	## Find nearest cover from enemies
	if enemies_in_sight.is_empty():
		return Vector3.ZERO

	var enemy_dir := Vector3.ZERO
	for enemy in enemies_in_sight:
		if is_instance_valid(enemy):
			enemy_dir += (global_position - enemy.global_position).normalized()
	enemy_dir = enemy_dir.normalized()

	if CoverSystem and CoverSystem.has_method("find_cover_toward"):
		return CoverSystem.find_cover_toward(global_position, -enemy_dir, 30.0)

	return Vector3.ZERO

func seek_cover_automatically() -> void:
	## Called when taking fire without cover
	if current_cover != "none":
		return

	var cover_pos := find_cover()
	if cover_pos != Vector3.ZERO:
		move_to(cover_pos)

# =============================================================================
# ENHANCED LOS CHECKS
# =============================================================================

func has_line_of_sight_to(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false

	if CombatManager and CombatManager.has_method("check_line_of_sight"):
		var los: Dictionary = CombatManager.check_line_of_sight(
			global_position, target.global_position, [self, target]
		)
		return los.get("clear", false)

	return true  # Fallback: assume LOS

func get_visibility_of(target: Node3D) -> float:
	if not is_instance_valid(target):
		return 0.0

	if CombatManager and CombatManager.has_method("get_visibility_to"):
		return CombatManager.get_visibility_to(self, target)

	return 1.0  # Fallback: full visibility

# =============================================================================
# BEHAVIOR TREE INTEGRATION
# =============================================================================

var behavior_tree: BTNodeClass = null

func set_behavior_tree(tree: BTNodeClass) -> void:
	behavior_tree = tree
	behavior_tree.setup(self, {
		"target": null,
		"cover_position": Vector3.ZERO,
		"rally_point": Vector3.ZERO,
		"last_known_enemy_pos": Vector3.ZERO,
		"is_under_fire": false,
		"should_retreat": false,
	})

func use_behavior_tree(delta: float) -> bool:
	## Process behavior tree if assigned
	if behavior_tree:
		behavior_tree.tick(delta)
		return true
	return false

# =============================================================================
# VETERANCY SYSTEM
# =============================================================================

var veterancy: int = 0  # 0 = Green, 1 = Regular, 2 = Veteran, 3 = Elite
var experience: float = 0.0

const EXPERIENCE_THRESHOLDS: Array[float] = [0.0, 100.0, 300.0, 600.0]

func add_experience(amount: float) -> void:
	experience += amount

	# Check for level up
	while veterancy < 3 and experience >= EXPERIENCE_THRESHOLDS[veterancy + 1]:
		veterancy += 1
		_on_veterancy_gained()

func _on_veterancy_gained() -> void:
	# Apply veterancy bonuses
	accuracy += 0.05
	morale = minf(100, morale + 20)

	if unit_data:
		move_speed = unit_data.move_speed * (1.0 + veterancy * 0.1)

func get_veterancy() -> int:
	return veterancy

func get_veterancy_name() -> String:
	match veterancy:
		0: return "Green"
		1: return "Regular"
		2: return "Veteran"
		3: return "Elite"
		_: return "Unknown"

# =============================================================================
# STEALTH (for SOG teams)
# =============================================================================

var stealth_rating: float = 0.0  # 0.0 = visible, 1.0 = invisible

func get_stealth_rating() -> float:
	return stealth_rating

func set_stealth(value: float) -> void:
	stealth_rating = clampf(value, 0.0, 1.0)

# =============================================================================
# GARRISON SUPPORT
# =============================================================================

var garrisoned_in: Node3D = null

func garrison(structure: Node3D) -> bool:
	if structure.has_method("can_garrison") and structure.can_garrison(self):
		if structure.has_method("add_garrison"):
			structure.add_garrison(self)
			garrisoned_in = structure
			current_cover = "heavy"
			visible = false
			current_state = SquadState.GARRISONED
			return true
	return false

func ungarrison() -> void:
	if garrisoned_in:
		if garrisoned_in.has_method("remove_garrison"):
			garrisoned_in.remove_garrison(self)
		garrisoned_in = null
		current_cover = "none"
		visible = true
		current_state = SquadState.IDLE

func is_garrisoned() -> bool:
	return garrisoned_in != null

func _process_garrisoned(delta: float) -> void:
	## Process while garrisoned - can still fire
	if enemies_in_sight.is_empty():
		return

	# Attack from garrison
	if not current_target or not is_instance_valid(current_target):
		current_target = _get_closest_enemy()

	if current_target and current_ammo > 0:
		_fire_at_target(delta)

# =============================================================================
# DEBUG
# =============================================================================

func get_debug_info() -> Dictionary:
	return {
		"name": squad_name,
		"size": squad_size,
		"health": squad_health,
		"morale": morale,
		"suppression": suppression,
		"state": SquadState.keys()[current_state],
		"cover": current_cover,
		"ammo": current_ammo,
		"veterancy": get_veterancy_name(),
		"enemies_visible": enemies_in_sight.size(),
	}
