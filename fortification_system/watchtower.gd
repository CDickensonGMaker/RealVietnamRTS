class_name Watchtower extends Node3D
## Watchtower - Elevated observation post providing detection bonus.
## Extends sight range for units within its coverage area.
## Can be garrisoned by snipers or spotters for enhanced effectiveness.
##
## Two variants:
##   - OBSERVATION_TOWER: 8m tall, +80m sight radius, 2-person capacity
##   - GUARD_TOWER: Smaller, +60m sight, armed with M60 (POW camp style)
##
## Detection bonus stacks with unit's native detection range.
## Updates are broadcast via BattleSignals.detection_bonus_changed.

signal tower_destroyed(tower: Watchtower)
signal garrison_changed(count: int)
signal enemy_spotted(enemy: Node3D, position: Vector3)
signal detection_radius_changed(new_radius: float)

enum TowerType { OBSERVATION_TOWER, GUARD_TOWER, WATCHTOWER }
enum State { OPERATIONAL, DAMAGED, DESTROYED }

@export var tower_type: TowerType = TowerType.OBSERVATION_TOWER
@export var faction: int = 0  # GameEnums.Faction

## Detection capabilities
@export var base_detection_radius: float = 80.0  # Meters
@export var detection_bonus_for_units: float = 60.0  # Bonus added to nearby units
@export var bonus_radius: float = 100.0  # Units within this range get detection bonus

## Physical properties
@export var tower_height: float = 8.0  # Elevation bonus
@export var max_garrison: int = 2
@export var has_weapon: bool = false  # Guard towers have M60
@export var weapon_id: String = "m60"

## Health
var current_health: float = 150.0
var max_health: float = 150.0
var state: State = State.OPERATIONAL

## Garrison
var garrisoned_units: Array[Node3D] = []

## Detection
var _detection_area: Area3D = null
var _detected_enemies: Array[Node3D] = []
var _detection_scan_timer: float = 0.0
const DETECTION_SCAN_INTERVAL: float = 0.5

## Combat (Guard Tower only)
var _weapon_cooldown: float = 0.0
var _current_target: Node3D = null
var _turret_node: Node3D = null

## Visual
var _tower_body: Node3D = null
var _platform: Node3D = null


func _ready() -> void:
	add_to_group("watchtowers")
	add_to_group("structures")
	add_to_group("detection_providers")

	if GameEnums.is_us_faction(faction):
		add_to_group("player_structures")
	else:
		add_to_group("enemy_structures")

	_apply_tower_type()
	_build_placeholder_visual()
	_setup_detection_area()


func _apply_tower_type() -> void:
	match tower_type:
		TowerType.OBSERVATION_TOWER:
			base_detection_radius = 80.0
			detection_bonus_for_units = 60.0
			tower_height = 8.0
			max_garrison = 2
			has_weapon = false
			max_health = 150.0

		TowerType.GUARD_TOWER:
			base_detection_radius = 60.0
			detection_bonus_for_units = 40.0
			tower_height = 6.0
			max_garrison = 2
			has_weapon = true
			weapon_id = "m60"
			max_health = 200.0

		TowerType.WATCHTOWER:
			base_detection_radius = 60.0
			detection_bonus_for_units = 40.0
			tower_height = 5.0
			max_garrison = 2
			has_weapon = false
			max_health = 100.0

	current_health = max_health


func _build_placeholder_visual() -> void:
	_tower_body = Node3D.new()
	_tower_body.name = "TowerBody"
	add_child(_tower_body)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.45, 0.3)  # Wood color

	var mat_dark := StandardMaterial3D.new()
	mat_dark.albedo_color = Color(0.3, 0.25, 0.2)

	# Base supports (4 legs)
	for i in 4:
		var angle: float = i * (PI / 2.0) + PI / 4.0
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.3, tower_height, 0.3)
		leg.mesh = leg_mesh
		leg.position = Vector3(cos(angle) * 1.5, tower_height * 0.5, sin(angle) * 1.5)
		leg.material_override = mat
		_tower_body.add_child(leg)

	# Cross bracing
	for i in 2:
		var brace := MeshInstance3D.new()
		var brace_mesh := BoxMesh.new()
		brace_mesh.size = Vector3(0.15, 4.0, 0.15)
		brace.mesh = brace_mesh
		brace.rotation_degrees = Vector3(0, 45 + i * 90, 30)
		brace.position = Vector3(0, tower_height * 0.4, 0)
		brace.material_override = mat_dark
		_tower_body.add_child(brace)

	# Platform floor
	_platform = Node3D.new()
	_platform.name = "Platform"
	_platform.position.y = tower_height
	add_child(_platform)

	var floor_mesh := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(4.0, 0.2, 4.0)
	floor_mesh.mesh = fm
	floor_mesh.material_override = mat
	_platform.add_child(floor_mesh)

	# Railing
	for side in 4:
		var angle: float = side * (PI / 2.0)
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(4.0, 1.0, 0.1)
		rail.mesh = rail_mesh
		rail.rotation.y = angle
		rail.position = Vector3(sin(angle) * 1.95, 0.6, cos(angle) * 1.95)
		rail.material_override = mat_dark
		_platform.add_child(rail)

	# Sandbag parapet
	var sandbag_mat := StandardMaterial3D.new()
	sandbag_mat.albedo_color = Color(0.5, 0.45, 0.35)

	for side in 4:
		var angle: float = side * (PI / 2.0)
		var bags := MeshInstance3D.new()
		var bag_mesh := BoxMesh.new()
		bag_mesh.size = Vector3(3.5, 0.6, 0.5)
		bags.mesh = bag_mesh
		bags.rotation.y = angle
		bags.position = Vector3(sin(angle) * 1.75, 0.4, cos(angle) * 1.75)
		bags.material_override = sandbag_mat
		_platform.add_child(bags)

	# Roof (simple canopy)
	var roof := MeshInstance3D.new()
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(4.5, 0.15, 4.5)
	roof.mesh = roof_mesh
	roof.position.y = 2.5
	roof.material_override = mat_dark
	_platform.add_child(roof)

	# Roof supports
	for i in 4:
		var angle: float = i * (PI / 2.0) + PI / 4.0
		var support := MeshInstance3D.new()
		var sup_mesh := BoxMesh.new()
		sup_mesh.size = Vector3(0.15, 2.3, 0.15)
		support.mesh = sup_mesh
		support.position = Vector3(cos(angle) * 1.8, 1.25, sin(angle) * 1.8)
		support.material_override = mat
		_platform.add_child(support)

	# Guard tower weapon mount
	if has_weapon:
		_turret_node = Node3D.new()
		_turret_node.name = "WeaponMount"
		_turret_node.position = Vector3(0, 1.2, 0)
		_platform.add_child(_turret_node)

		var gun_base := MeshInstance3D.new()
		var gb_mesh := CylinderMesh.new()
		gb_mesh.top_radius = 0.3
		gb_mesh.bottom_radius = 0.35
		gb_mesh.height = 0.3
		gun_base.mesh = gb_mesh

		var gun_mat := StandardMaterial3D.new()
		gun_mat.albedo_color = Color(0.2, 0.25, 0.2)
		gun_base.material_override = gun_mat
		_turret_node.add_child(gun_base)

		var barrel := MeshInstance3D.new()
		var barrel_mesh := CylinderMesh.new()
		barrel_mesh.top_radius = 0.05
		barrel_mesh.bottom_radius = 0.06
		barrel_mesh.height = 1.2
		barrel.mesh = barrel_mesh
		barrel.rotation_degrees = Vector3(90, 0, 0)
		barrel.position = Vector3(0, 0.2, 0.6)
		barrel.material_override = gun_mat
		_turret_node.add_child(barrel)

	# Static collision (no CharacterBody - towers don't move)
	var static_body := StaticBody3D.new()
	static_body.name = "Collision"
	add_child(static_body)

	var coll := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.5, tower_height + 2.0, 3.5)
	coll.shape = box
	coll.position.y = (tower_height + 2.0) * 0.5
	static_body.add_child(coll)

	# Set collision layer for buildings
	static_body.collision_layer = 64  # Layer 7 = Buildings


func _setup_detection_area() -> void:
	_detection_area = Area3D.new()
	_detection_area.name = "DetectionArea"
	add_child(_detection_area)

	var sphere := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = base_detection_radius
	sphere.shape = shape
	sphere.position.y = tower_height  # Detection from platform height
	_detection_area.add_child(sphere)

	# Set monitoring for enemy units
	_detection_area.collision_mask = 0b1110  # Layers 2,3,4 (all unit factions)
	_detection_area.collision_layer = 0

	_detection_area.body_entered.connect(_on_body_entered_detection)
	_detection_area.body_exited.connect(_on_body_exited_detection)


func _physics_process(delta: float) -> void:
	if state == State.DESTROYED:
		return

	# Periodic detection scan
	_detection_scan_timer -= delta
	if _detection_scan_timer <= 0.0:
		_detection_scan_timer = DETECTION_SCAN_INTERVAL
		_scan_for_enemies()
		_update_unit_detection_bonuses()

	# Combat for guard towers
	if has_weapon and state == State.OPERATIONAL:
		_process_combat(delta)


func _scan_for_enemies() -> void:
	# Clean up invalid references
	_detected_enemies = _detected_enemies.filter(func(e): return is_instance_valid(e))

	# Report spotted enemies
	for enemy in _detected_enemies:
		enemy_spotted.emit(enemy, enemy.global_position)


func _update_unit_detection_bonuses() -> void:
	# Find friendly units within bonus radius and update their detection
	# Use SpatialHashGrid for efficient spatial query instead of O(n) group iteration
	var nearby: Array[Node3D] = SpatialHashGrid.get_friendlies_in_radius(
		global_position, bonus_radius, faction
	)

	for unit in nearby:
		if not is_instance_valid(unit):
			continue
		# Apply detection bonus
		if unit.has_method("apply_detection_bonus"):
			unit.apply_detection_bonus(detection_bonus_for_units, self)


func _process_combat(delta: float) -> void:
	if _weapon_cooldown > 0.0:
		_weapon_cooldown -= delta

	# Acquire target
	if not _current_target or not is_instance_valid(_current_target):
		_current_target = _find_best_target()

	if not _current_target:
		return

	# Check range
	var dist: float = global_position.distance_to(_current_target.global_position)
	var weapon_range: float = 500.0  # M60 range
	if dist > weapon_range:
		_current_target = null
		return

	# Rotate turret toward target
	if _turret_node:
		var to_target: Vector3 = _current_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() > 0.1:
			var target_yaw: float = atan2(to_target.x, to_target.z)
			_turret_node.rotation.y = lerp_angle(_turret_node.rotation.y, target_yaw, delta * 5.0)

	# Fire
	if _weapon_cooldown <= 0.0:
		_fire_weapon()


func _fire_weapon() -> void:
	if not _current_target or not is_instance_valid(_current_target):
		return

	# Apply garrison bonus
	var accuracy_mult: float = 1.0
	var damage_mult: float = 1.0
	if not garrisoned_units.is_empty():
		accuracy_mult = 1.0 + garrisoned_units.size() * 0.15
		damage_mult = 1.0 + garrisoned_units.size() * 0.1

	if CombatManager:
		CombatManager.fire_weapon(self, _current_target, weapon_id)

	# Cooldown based on weapon ROF
	_weapon_cooldown = 0.2  # M60 fires ~550 RPM


func _find_best_target() -> Node3D:
	if _detected_enemies.is_empty():
		return null

	var best_target: Node3D = null
	var best_priority: float = -INF

	for enemy in _detected_enemies:
		if not is_instance_valid(enemy):
			continue

		var dist: float = global_position.distance_to(enemy.global_position)
		var priority: float = 1000.0 - dist  # Closer = higher priority

		# Bonus priority for units attacking firebase
		if enemy.has_method("get_current_target"):
			var their_target = enemy.get_current_target()
			if their_target and their_target.is_in_group("player_structures"):
				priority += 200.0

		if priority > best_priority:
			best_priority = priority
			best_target = enemy

	return best_target


func _on_body_entered_detection(body: Node3D) -> void:
	if state == State.DESTROYED:
		return

	# Check if enemy faction
	var is_enemy: bool = false
	if GameEnums.is_us_faction(faction):
		is_enemy = body.is_in_group("enemy_units")
	else:
		is_enemy = body.is_in_group("player_units")

	if is_enemy and body not in _detected_enemies:
		_detected_enemies.append(body)
		enemy_spotted.emit(body, body.global_position)

		if BattleSignals:
			BattleSignals.enemy_detected.emit(body, global_position, self)


func _on_body_exited_detection(body: Node3D) -> void:
	_detected_enemies.erase(body)


# =============================================================================
# PUBLIC API
# =============================================================================

## Garrison a unit in the tower
func enter_garrison(unit: Node3D) -> bool:
	if garrisoned_units.size() >= max_garrison:
		return false
	if state == State.DESTROYED:
		return false

	garrisoned_units.append(unit)
	unit.visible = false
	unit.set_physics_process(false)

	# Update detection bonus based on garrison
	_update_detection_for_garrison()

	garrison_changed.emit(garrisoned_units.size())
	return true


## Remove unit from garrison
func exit_garrison(unit: Node3D) -> bool:
	if unit not in garrisoned_units:
		return false

	garrisoned_units.erase(unit)

	# Position at base of tower
	unit.global_position = global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	unit.visible = true
	unit.set_physics_process(true)

	_update_detection_for_garrison()
	garrison_changed.emit(garrisoned_units.size())
	return true


## Exit all garrison
func exit_all_garrison() -> void:
	var to_exit: Array[Node3D] = garrisoned_units.duplicate()
	for unit in to_exit:
		exit_garrison(unit)


func _update_detection_for_garrison() -> void:
	# Garrison increases detection radius
	var garrison_bonus: float = garrisoned_units.size() * 10.0
	var new_radius: float = base_detection_radius + garrison_bonus

	# Update detection area
	if _detection_area:
		var sphere := _detection_area.get_child(0) as CollisionShape3D
		if sphere and sphere.shape is SphereShape3D:
			(sphere.shape as SphereShape3D).radius = new_radius

	detection_radius_changed.emit(new_radius)


func take_damage(amount: float, source: Node = null) -> void:
	if state == State.DESTROYED:
		return

	current_health = maxf(0.0, current_health - amount)

	if current_health < max_health * 0.5 and state == State.OPERATIONAL:
		state = State.DAMAGED

	if current_health <= 0.0:
		_destroy()


func _destroy() -> void:
	state = State.DESTROYED
	tower_destroyed.emit(self)

	# Kill/eject garrison
	for unit in garrisoned_units:
		if is_instance_valid(unit) and unit.has_method("take_damage"):
			unit.take_damage(50, self)
	garrisoned_units.clear()

	# Visual destruction
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.15, 0.1)

	for child in get_children():
		_apply_destroyed_material(child, mat)

	# Disable detection
	if _detection_area:
		_detection_area.monitoring = false

	var t := get_tree().create_timer(60.0)
	t.timeout.connect(queue_free)


func _apply_destroyed_material(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
	for child in node.get_children():
		_apply_destroyed_material(child, mat)


func get_detection_radius() -> float:
	var garrison_bonus: float = garrisoned_units.size() * 10.0
	return base_detection_radius + garrison_bonus


func get_garrison_count() -> int:
	return garrisoned_units.size()


func has_space() -> bool:
	return garrisoned_units.size() < max_garrison


func is_operational() -> bool:
	return state == State.OPERATIONAL or state == State.DAMAGED


func get_status() -> Dictionary:
	return {
		"state": State.keys()[state],
		"health_percent": current_health / max_health * 100.0,
		"garrison": garrisoned_units.size(),
		"max_garrison": max_garrison,
		"detection_radius": get_detection_radius(),
		"detected_enemies": _detected_enemies.size(),
		"has_weapon": has_weapon,
	}
