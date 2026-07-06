class_name DetectionArea extends Area3D
## Reusable detection component for emplacements and units
##
## Replaces manual get_nodes_in_group() scanning with efficient Area3D signals.
## Maintains a list of valid targets within range, automatically updated
## when targets enter/exit the detection sphere.
##
## Usage:
##   var detection := DetectionArea.new()
##   detection.detection_radius = 300.0
##   detection.target_groups = ["enemy_units", "vc_units"]
##   detection.exclude_groups = ["aircraft"]
##   add_child(detection)
##   detection.target_entered.connect(_on_target_entered)

signal target_entered(target: Node3D)
signal target_exited(target: Node3D)
signal targets_changed()

## Detection configuration
@export var detection_radius: float = 250.0:
	set(value):
		detection_radius = value
		_update_collision_shape()

@export var target_groups: Array[String] = ["enemy_units"]
@export var exclude_groups: Array[String] = []
@export var require_line_of_sight: bool = false
@export var vertical_detection: bool = true  # False = ignore Y axis

## Firing arc support (optional)
@export var use_firing_arc: bool = false
@export var firing_arc_degrees: float = 360.0
@export var firing_arc_direction: float = 0.0  # Yaw in radians

## Current targets in range
var targets_in_range: Array[Node3D] = []

## Internal
var _collision_shape: CollisionShape3D = null
var _sphere_shape: SphereShape3D = null


func _ready() -> void:
	_setup_area()


func _setup_area() -> void:
	# Configure Area3D
	collision_layer = 0  # Don't collide with anything
	collision_mask = 0b1110  # Layers 2,3,4 (US, VC, NVA units)
	monitoring = true
	monitorable = false

	# Create collision shape
	_collision_shape = CollisionShape3D.new()
	_sphere_shape = SphereShape3D.new()
	_sphere_shape.radius = detection_radius
	_collision_shape.shape = _sphere_shape
	add_child(_collision_shape)

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _update_collision_shape() -> void:
	if _sphere_shape:
		_sphere_shape.radius = detection_radius


func _on_body_entered(body: Node3D) -> void:
	_try_add_target(body)


func _on_body_exited(body: Node3D) -> void:
	_try_remove_target(body)


func _on_area_entered(area: Area3D) -> void:
	# Check parent of area (units may use Area3D for their hitbox)
	var potential_target := area.get_parent()
	if potential_target is Node3D:
		_try_add_target(potential_target)


func _on_area_exited(area: Area3D) -> void:
	var potential_target := area.get_parent()
	if potential_target is Node3D:
		_try_remove_target(potential_target)


func _try_add_target(node: Node3D) -> void:
	if not is_instance_valid(node):
		return

	if node in targets_in_range:
		return

	if not _is_valid_target(node):
		return

	targets_in_range.append(node)
	target_entered.emit(node)
	targets_changed.emit()


func _try_remove_target(node: Node3D) -> void:
	if node in targets_in_range:
		targets_in_range.erase(node)
		target_exited.emit(node)
		targets_changed.emit()


func _is_valid_target(node: Node3D) -> bool:
	if not is_instance_valid(node):
		return false

	# Check target groups
	var in_target_group := false
	for group in target_groups:
		if node.is_in_group(group):
			in_target_group = true
			break

	if not in_target_group:
		return false

	# Check exclude groups
	for group in exclude_groups:
		if node.is_in_group(group):
			return false

	# Check if dead
	if _is_target_dead(node):
		return false

	# Check firing arc if enabled
	if use_firing_arc and firing_arc_degrees < 360.0:
		if not _is_in_firing_arc(node.global_position):
			return false

	return true


func _is_target_dead(target: Node) -> bool:
	if not is_instance_valid(target):
		return true

	# Check various health properties
	if target.has_method("is_dead"):
		return target.is_dead()

	if target.has_method("is_destroyed"):
		return target.is_destroyed()

	if "current_health" in target:
		return target.current_health <= 0

	if "health" in target:
		return target.health <= 0

	return false


func _is_in_firing_arc(target_pos: Vector3) -> bool:
	var to_target: Vector3 = target_pos - global_position
	to_target.y = 0

	if to_target.length() < 0.1:
		return true

	var target_angle: float = atan2(to_target.x, to_target.z)
	var half_arc: float = deg_to_rad(firing_arc_degrees * 0.5)
	var angle_diff: float = absf(angle_difference(firing_arc_direction, target_angle))

	return angle_diff <= half_arc


# =============================================================================
# PUBLIC API
# =============================================================================

## Get the closest valid target
func get_closest_target() -> Node3D:
	_cleanup_invalid_targets()

	var closest: Node3D = null
	var closest_dist: float = INF

	for target in targets_in_range:
		if not is_instance_valid(target):
			continue

		var dist: float = global_position.distance_to(target.global_position)
		if dist < closest_dist:
			closest = target
			closest_dist = dist

	return closest


## Get the closest target within firing arc
func get_closest_target_in_arc() -> Node3D:
	_cleanup_invalid_targets()

	var closest: Node3D = null
	var closest_dist: float = INF

	for target in targets_in_range:
		if not is_instance_valid(target):
			continue

		if use_firing_arc and not _is_in_firing_arc(target.global_position):
			continue

		var dist: float = global_position.distance_to(target.global_position)
		if dist < closest_dist:
			closest = target
			closest_dist = dist

	return closest


## Get all targets sorted by distance
func get_targets_by_distance() -> Array[Node3D]:
	_cleanup_invalid_targets()

	var sorted: Array[Node3D] = targets_in_range.duplicate()
	sorted.sort_custom(func(a, b):
		var dist_a := global_position.distance_to(a.global_position)
		var dist_b := global_position.distance_to(b.global_position)
		return dist_a < dist_b
	)
	return sorted


## Get targets within a specific range (less than detection radius)
func get_targets_within_range(range_limit: float) -> Array[Node3D]:
	_cleanup_invalid_targets()

	var result: Array[Node3D] = []
	for target in targets_in_range:
		if not is_instance_valid(target):
			continue
		var dist: float = global_position.distance_to(target.global_position)
		if dist <= range_limit:
			result.append(target)
	return result


## Check if any targets are in range
func has_targets() -> bool:
	_cleanup_invalid_targets()
	return not targets_in_range.is_empty()


## Get target count
func get_target_count() -> int:
	_cleanup_invalid_targets()
	return targets_in_range.size()


## Force re-validate all targets (call after changing groups)
func revalidate_targets() -> void:
	var to_remove: Array[Node3D] = []

	for target in targets_in_range:
		if not _is_valid_target(target):
			to_remove.append(target)

	for target in to_remove:
		_try_remove_target(target)


## Update firing arc (call when emplacement rotates)
func set_firing_arc(direction_rad: float, arc_degrees: float) -> void:
	firing_arc_direction = direction_rad
	firing_arc_degrees = arc_degrees
	use_firing_arc = arc_degrees < 360.0
	revalidate_targets()


## Clean up dead/invalid targets
func _cleanup_invalid_targets() -> void:
	var to_remove: Array[Node3D] = []

	for target in targets_in_range:
		if not is_instance_valid(target) or _is_target_dead(target):
			to_remove.append(target)

	for target in to_remove:
		targets_in_range.erase(target)


## Configure for player-controlled emplacement (targets enemies)
func configure_for_player() -> void:
	target_groups = ["enemy_units", "vc_units", "nva_units"]
	exclude_groups = []


## Configure for enemy-controlled emplacement (targets player)
func configure_for_enemy() -> void:
	target_groups = ["player_units", "us_units", "arvn_units"]
	exclude_groups = []


## Configure for AA emplacement (targets aircraft only)
func configure_for_aa() -> void:
	target_groups = ["helicopters", "aircraft"]
	exclude_groups = []


## Configure for ground emplacement (excludes aircraft)
func configure_for_ground() -> void:
	exclude_groups = ["helicopters", "aircraft"]
