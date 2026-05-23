class_name Bunker extends Node3D
## Bunker - Fortified fighting position that garrisons infantry.
##
## Three states relevant to gameplay:
##   - EMPTY: no garrison, cannot fire. Pure cover, blocks LOS minimally.
##   - GARRISONED: holds 1+ squads. Garrison fires *from* the bunker; rate is
##     a function of how full the bunker is. Garrison takes much-reduced damage.
##   - DESTROYED: structural HP depleted. Garrison is killed.
##
## A bunker is NOT a Squad. It's a structure that gives a hosted squad
## protection and fixed firing arcs. Loading/unloading happens via
## load_squad() / unload_squad().
##
## Bunker variants are determined by the bunker_type field (matches
## firebase_system/building_data.gd BuildingType enum where relevant).
##
## Uses DetectionArea for efficient target acquisition, Tween-based firing.

const DetectionArea = preload("res://battle_system/components/detection_area.gd")

signal squad_loaded(squad: Node3D)
signal squad_unloaded(squad: Node3D)
signal bunker_destroyed(bunker: Bunker)
signal garrison_killed(killed_count: int)
signal target_engaged(target: Node3D)
signal garrison_fired(targets_hit: int)

enum BunkerType {
	GENERIC_BUNKER,        # Hardened fighting position
	SANDBAG_BUNKER,        # Light cover
	CONEX_BUNKER,          # Heavy steel container
	MACHINE_GUN_NEST,      # MG emplacement
	MORTAR_PIT,            # Mortar position
	COMMAND_BUNKER,        # Higher capacity, command bonuses (future)
}

@export var bunker_type: BunkerType = BunkerType.GENERIC_BUNKER
@export var bunker_name: String = "Bunker"
@export var max_garrison_capacity: int = 1  # Squads (not soldiers)
@export var max_health: float = 800.0
@export var damage_reduction: float = 0.7  # 70% damage reduction for garrison
@export var firing_arc_degrees: float = 180.0  # Fixed firing arc (0 = omni)
@export var firing_arc_yaw_degrees: float = 0.0  # Direction the arc points (world yaw)
@export var fire_rate_per_full_capacity: float = 1.0  # 1.0 = full fire rate when fully crewed

## Auto-fire configuration
@export var engagement_range: float = 250.0  # Max range for garrison to engage
@export var base_damage: float = 15.0        # Base damage per shot (scales with garrison)
@export var fire_interval: float = 1.5       # Seconds between volleys
@export var auto_fire_enabled: bool = true   # Enable/disable auto targeting
@export var suppression_per_volley: float = 15.0  # Suppression applied to targets

## State
var current_health: float = 800.0
var garrison: Array[Node3D] = []
var faction: int = 0  # GameEnums.Faction
var is_player_controlled: bool = true

## Auto-fire state
var current_target: Node3D = null
var _is_suppressed: bool = false

## Tweens for timing (replaces manual timers)
var _fire_tween: Tween = null
var _suppression_tween: Tween = null

## Detection system (Area3D-based)
var _detection_area: DetectionArea = null

## Visual
var _structure_mesh: MeshInstance3D = null


func _ready() -> void:
	add_to_group("bunkers")
	add_to_group("fortifications")
	add_to_group("all_units")
	if is_player_controlled:
		add_to_group("player_structures")
		add_to_group("selectable_units")
	else:
		add_to_group("enemy_structures")

	current_health = max_health
	_build_placeholder_visual()
	_setup_detection_area()


func _setup_detection_area() -> void:
	_detection_area = DetectionArea.new()
	_detection_area.detection_radius = engagement_range
	_detection_area.exclude_groups = ["helicopters", "aircraft"]  # Ground targets only

	# Set up firing arc
	_detection_area.use_firing_arc = firing_arc_degrees < 360.0
	_detection_area.firing_arc_degrees = firing_arc_degrees
	_detection_area.firing_arc_direction = deg_to_rad(firing_arc_yaw_degrees)

	if is_player_controlled:
		_detection_area.configure_for_player()
	else:
		_detection_area.configure_for_enemy()

	_detection_area.target_entered.connect(_on_target_detected)
	_detection_area.target_exited.connect(_on_target_lost)
	add_child(_detection_area)


func _on_target_detected(target: Node3D) -> void:
	# Start firing if we have garrison and no current target
	if garrison.is_empty() or _is_suppressed or not auto_fire_enabled:
		return

	if not current_target or not is_instance_valid(current_target):
		current_target = target
		target_engaged.emit(target)
		_start_firing()


func _on_target_lost(target: Node3D) -> void:
	if current_target == target:
		_find_new_target()


func _build_placeholder_visual() -> void:
	_structure_mesh = MeshInstance3D.new()
	_structure_mesh.name = "Structure"

	var mesh: Mesh
	match bunker_type:
		BunkerType.SANDBAG_BUNKER:
			var b := BoxMesh.new()
			b.size = Vector3(4.0, 1.5, 4.0)
			mesh = b
		BunkerType.CONEX_BUNKER:
			var b := BoxMesh.new()
			b.size = Vector3(6.0, 2.5, 2.5)  # Shipping container shape
			mesh = b
		BunkerType.MACHINE_GUN_NEST:
			var b := BoxMesh.new()
			b.size = Vector3(3.0, 1.2, 3.0)
			mesh = b
		BunkerType.MORTAR_PIT:
			# Circular pit - use cylinder
			var c := CylinderMesh.new()
			c.top_radius = 2.5
			c.bottom_radius = 2.5
			c.height = 0.8
			mesh = c
		BunkerType.COMMAND_BUNKER:
			var b := BoxMesh.new()
			b.size = Vector3(8.0, 2.5, 6.0)
			mesh = b
		_:
			var b := BoxMesh.new()
			b.size = Vector3(4.0, 2.0, 3.5)
			mesh = b

	_structure_mesh.mesh = mesh
	_structure_mesh.position.y = (mesh.size.y if mesh is BoxMesh else (mesh as CylinderMesh).height) * 0.5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.4, 0.35)  # Concrete-sandbag color
	_structure_mesh.material_override = mat
	add_child(_structure_mesh)

	# Static collision body
	var body := StaticBody3D.new()
	body.name = "Body"
	var coll := CollisionShape3D.new()
	if mesh is BoxMesh:
		var shape := BoxShape3D.new()
		shape.size = (mesh as BoxMesh).size
		coll.shape = shape
	elif mesh is CylinderMesh:
		var shape := CylinderShape3D.new()
		shape.radius = (mesh as CylinderMesh).top_radius
		shape.height = (mesh as CylinderMesh).height
		coll.shape = shape
	coll.position.y = _structure_mesh.position.y
	body.add_child(coll)
	body.collision_layer = 1  # Terrain/static
	add_child(body)


# =============================================================================
# AUTO-FIRE PROCESSING
# =============================================================================

func _process(_delta: float) -> void:
	if current_health <= 0:
		return

	# Check if we need to find a new target (target validation)
	if current_target and is_instance_valid(current_target):
		if _is_target_dead(current_target):
			_find_new_target()


## Start Tween-based firing loop
func _start_firing() -> void:
	if _fire_tween:
		_fire_tween.kill()

	# Fire first volley after short delay
	_fire_tween = create_tween()
	_fire_tween.tween_callback(_fire_volley).set_delay(fire_interval * 0.5)


## Fire a volley and schedule next
func _fire_volley() -> void:
	if garrison.is_empty() or _is_suppressed or not auto_fire_enabled:
		_stop_firing()
		return

	if not current_target or not is_instance_valid(current_target):
		_find_new_target()
		if not current_target:
			_stop_firing()
			return

	# Fire at target
	_fire_at_target(current_target)

	# Schedule next volley
	if _fire_tween:
		_fire_tween.kill()
	_fire_tween = create_tween()
	_fire_tween.tween_callback(_fire_volley).set_delay(fire_interval)


## Stop firing loop
func _stop_firing() -> void:
	if _fire_tween:
		_fire_tween.kill()
		_fire_tween = null


## Find a new target using DetectionArea
func _find_new_target() -> void:
	current_target = null

	if not _detection_area or garrison.is_empty():
		return

	# Get closest target in arc from DetectionArea
	var new_target := _detection_area.get_closest_target_in_arc()

	if new_target:
		current_target = new_target
		target_engaged.emit(current_target)
		if not _fire_tween:
			_start_firing()


func _is_target_dead(target: Node) -> bool:
	if not is_instance_valid(target):
		return true

	if target.has_method("get"):
		var health = target.get("current_health")
		if health != null and health <= 0:
			return true

	if target.has_method("is_dead"):
		return target.is_dead()

	if target.has_method("is_destroyed"):
		return target.is_destroyed()

	return false


func _fire_at_target(target: Node3D) -> void:
	if not is_instance_valid(target):
		current_target = null
		return

	# Calculate damage based on garrison effectiveness
	var effectiveness: float = get_garrison_effectiveness()
	var total_damage: float = base_damage * effectiveness * garrison.size()

	# Fire from each garrisoned squad
	var targets_hit: int = 0
	for squad in garrison:
		if not is_instance_valid(squad):
			continue

		# Calculate per-squad damage
		var squad_damage: float = base_damage * effectiveness

		# Apply accuracy penalty for distance
		var distance: float = global_position.distance_to(target.global_position)
		var accuracy: float = 1.0 - (distance / engagement_range) * 0.3
		accuracy = maxf(0.5, accuracy)

		# Random hit check
		if randf() < accuracy:
			if target.has_method("take_damage"):
				target.take_damage(squad_damage, self)
				targets_hit += 1

			# Apply suppression
			if target.has_method("apply_suppression"):
				target.apply_suppression(suppression_per_volley / garrison.size())
			elif "suppression" in target:
				var current_sup: float = target.suppression
				target.suppression = minf(100.0, current_sup + suppression_per_volley / garrison.size())

	if targets_hit > 0:
		garrison_fired.emit(targets_hit)
		# Visual/audio feedback
		_spawn_muzzle_flash()

	# Emit signal for audio if BattleSignals exists
	if BattleSignals:
		BattleSignals.projectile_fired.emit(global_position, target.global_position)


func _spawn_muzzle_flash() -> void:
	# Position at bunker front (firing arc direction)
	var arc_dir := Vector3(sin(deg_to_rad(firing_arc_yaw_degrees)), 0, cos(deg_to_rad(firing_arc_yaw_degrees)))
	var flash_pos := global_position + arc_dir * 2.0 + Vector3(0, 1.0, 0)

	# Use particle pool if available (GPU-accelerated)
	if ParticlePool and ParticlePool.instance:
		ParticlePool.spawn_muzzle_flash(flash_pos)
		return

	# Fallback: Simple mesh-based muzzle flash
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	flash.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.3, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = mat
	flash.position = flash_pos

	get_tree().root.add_child(flash)

	# Fade out quickly
	var tween := create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.1)
	tween.tween_callback(flash.queue_free)


func apply_suppression(amount: float) -> void:
	# Bunker provides some suppression resistance
	var effective_suppression: float = amount * (1.0 - damage_reduction * 0.5)

	if effective_suppression > 20.0:
		_stop_firing()
		_is_suppressed = true
		var recovery_time := 2.0 + randf() * 2.0  # 2-4 seconds
		_start_suppression_recovery(recovery_time)


## Start suppression recovery timer
func _start_suppression_recovery(duration: float) -> void:
	if _suppression_tween:
		_suppression_tween.kill()

	_suppression_tween = create_tween()
	_suppression_tween.tween_callback(_recover_from_suppression).set_delay(duration)


## Recover from suppression
func _recover_from_suppression() -> void:
	_is_suppressed = false
	# Try to re-acquire target
	if not garrison.is_empty() and auto_fire_enabled:
		_find_new_target()


# =============================================================================
# GARRISON MANAGEMENT
# =============================================================================

func can_load(squad: Node3D) -> bool:
	if not squad:
		return false
	if garrison.size() >= max_garrison_capacity:
		return false
	# Squad must be within 5m
	if global_position.distance_to(squad.global_position) > 5.0:
		return false
	return true


## Load a squad into the bunker. Returns true on success.
func load_squad(squad: Node3D) -> bool:
	if not can_load(squad):
		return false
	garrison.append(squad)
	# Hide visual but keep firing through bunker
	squad.visible = false
	if squad.has_method("set"):
		squad.set("is_in_cover", true)
	squad_loaded.emit(squad)
	return true


## Unload a squad. Squad reappears at unload_position (defaults to 4m in front).
func unload_squad(squad: Node3D, unload_position: Vector3 = Vector3.INF) -> bool:
	if not squad in garrison:
		return false
	garrison.erase(squad)

	if unload_position == Vector3.INF:
		# Default: place 4m in front of bunker (using firing arc direction)
		var arc_dir := Vector3(sin(deg_to_rad(firing_arc_yaw_degrees)), 0, cos(deg_to_rad(firing_arc_yaw_degrees)))
		unload_position = global_position + arc_dir * 4.0

	squad.global_position = unload_position
	squad.visible = true
	if squad.has_method("set"):
		squad.set("is_in_cover", false)
	squad_unloaded.emit(squad)
	return true


func unload_all() -> Array[Node3D]:
	var unloaded: Array[Node3D] = []
	for s in garrison.duplicate():
		if unload_squad(s):
			unloaded.append(s)
	return unloaded


# =============================================================================
# COMBAT
# =============================================================================

## Garrison effectiveness: 0.0 (empty) to 1.0 (fully crewed).
## Drives fire rate of contained squads.
func get_garrison_effectiveness() -> float:
	if max_garrison_capacity <= 0:
		return 0.0
	return float(garrison.size()) / float(max_garrison_capacity)


## Check if target_pos is within firing arc.
func is_in_firing_arc(target_pos: Vector3) -> bool:
	if firing_arc_degrees >= 360.0:
		return true
	var to_target: Vector3 = target_pos - global_position
	to_target.y = 0
	if to_target.length() < 0.1:
		return true
	var target_yaw: float = atan2(to_target.x, to_target.z)
	var arc_center: float = deg_to_rad(firing_arc_yaw_degrees)
	var half_arc: float = deg_to_rad(firing_arc_degrees * 0.5)
	var diff: float = abs(angle_difference(arc_center, target_yaw))
	return diff <= half_arc


func take_damage(amount: float) -> void:
	# Structural HP is reduced first
	current_health = max(0.0, current_health - amount)

	# Garrison takes reduced damage proportional to remaining structural HP
	# (a collapsing bunker offers less protection)
	var structural_ratio: float = current_health / max_health
	var damage_to_garrison: float = amount * (1.0 - damage_reduction) * (1.0 - structural_ratio * 0.5)

	# Distribute damage to garrison squads
	for squad in garrison:
		if is_instance_valid(squad) and squad.has_method("take_damage"):
			squad.take_damage(damage_to_garrison / float(max(1, garrison.size())))

	if current_health <= 0.0:
		_collapse()


func _collapse() -> void:
	# Stop all tweens
	if _fire_tween:
		_fire_tween.kill()
		_fire_tween = null
	if _suppression_tween:
		_suppression_tween.kill()
		_suppression_tween = null

	# Kill all garrison
	var killed_count: int = 0
	for squad in garrison:
		if is_instance_valid(squad) and squad.has_method("take_damage"):
			squad.take_damage(99999.0)
			killed_count += 1
	garrison.clear()
	garrison_killed.emit(killed_count)
	bunker_destroyed.emit(self)
	queue_free()


func is_destroyed() -> bool:
	return current_health <= 0.0


func get_garrison() -> Array[Node3D]:
	return garrison
