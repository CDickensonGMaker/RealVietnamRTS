class_name AutoCoverBehavior extends Node
## AutoCoverBehavior - Company of Heroes-style automatic cover seeking
##
## Attach to any unit (squad, soldier) to enable automatic cover behavior:
## - Units seek cover when idle near cover
## - Units dive to cover when taking fire
## - Units prefer better cover over worse
## - Units won't leave good cover without orders
##
## LESSONS FROM COMPANY OF HEROES:
## - Units automatically take cover when near it
## - Suppressed units dive to nearest cover
## - Cover positions face threats when possible
## - Units relocate if cover is destroyed
##
## USAGE:
##   var auto_cover = AutoCoverBehavior.new()
##   infantry_squad.add_child(auto_cover)

signal cover_found(cover_pos: Vector3, cover_type: int)
signal diving_to_cover(from_pos: Vector3, cover_pos: Vector3)
signal cover_destroyed(old_pos: Vector3)
signal no_cover_available

## Configuration
@export var enabled: bool = true
@export var search_radius: float = 10.0  # How far to search for cover
@export var idle_cover_delay: float = 2.0  # Seconds before seeking cover when idle
@export var dive_speed_multiplier: float = 1.5  # Move faster when diving to cover
@export var min_cover_threshold: int = 1  # Minimum cover type to consider (LIGHT)

## State
var current_cover_pos: Vector3 = Vector3.INF
var current_cover_type: int = 0  # GameEnums.CoverType.NONE
var is_in_cover: bool = false
var is_diving: bool = false

## Timing
var _idle_time: float = 0.0
var _last_threat_direction: Vector3 = Vector3.ZERO
var _cover_check_timer: float = 0.0
const COVER_CHECK_INTERVAL: float = 0.5

## Cached references
var _parent: Node3D = null
var _cover_system: Node = null
var _damage_system: Node = null


func _ready() -> void:
	_parent = get_parent() as Node3D
	_cover_system = get_node_or_null("/root/CoverSystem")
	_damage_system = get_node_or_null("/root/DamageSystem")

	# Connect to parent signals if available
	if _parent:
		if _parent.has_signal("took_damage"):
			_parent.took_damage.connect(_on_took_damage)
		if _parent.has_signal("squad_moved"):
			_parent.squad_moved.connect(_on_moved)


func _process(delta: float) -> void:
	if not enabled or not _parent:
		return

	_cover_check_timer += delta

	# Check if we're idle
	if _is_unit_idle():
		_idle_time += delta

		# Seek cover after being idle long enough
		if _idle_time >= idle_cover_delay and not is_in_cover:
			if _cover_check_timer >= COVER_CHECK_INTERVAL:
				_cover_check_timer = 0.0
				_try_find_cover()
	else:
		_idle_time = 0.0

	# Update diving state
	if is_diving:
		_update_dive(delta)


func _is_unit_idle() -> bool:
	"""Check if the parent unit is idle (not moving, not attacking)"""
	if not _parent:
		return false

	# Check velocity
	if "velocity" in _parent:
		if _parent.velocity.length_squared() > 0.1:
			return false

	# Check move order
	if "has_move_order" in _parent:
		if _parent.has_move_order:
			return false

	# Check combat state
	if "is_attacking" in _parent:
		if _parent.is_attacking:
			return false

	return true


func _try_find_cover() -> void:
	"""Search for and move to nearby cover"""
	var best_cover: Dictionary = _find_best_cover()

	if best_cover.is_empty():
		no_cover_available.emit()
		return

	var cover_pos: Vector3 = best_cover.position
	var cover_type: int = best_cover.type

	# Only move to cover if it's better than current
	if cover_type <= current_cover_type:
		return

	_move_to_cover(cover_pos, cover_type)


func _find_best_cover() -> Dictionary:
	"""Find the best available cover position nearby"""
	if not _parent:
		return {}

	var unit_pos: Vector3 = _parent.global_position
	var best_pos: Vector3 = Vector3.ZERO
	var best_type: int = 0
	var best_score: float = -1.0

	# Check cover objects
	var cover_groups: Array[String] = ["cover_fortified", "cover_heavy", "cover_light"]

	for group_name in cover_groups:
		var scene_tree: SceneTree = _parent.get_tree()
		if not scene_tree:
			continue

		var objects: Array[Node] = scene_tree.get_nodes_in_group(group_name)
		for obj in objects:
			if not is_instance_valid(obj):
				continue

			var cover_pos: Vector3 = obj.global_position
			var distance: float = unit_pos.distance_to(cover_pos)

			if distance > search_radius:
				continue

			# Get cover type
			var cover_type: int = _get_cover_type_from_group(group_name)
			if cover_type < min_cover_threshold:
				continue

			# Score based on cover type and distance
			var score: float = float(cover_type) * 10.0 - distance

			# Bonus if cover faces threat direction
			if _last_threat_direction != Vector3.ZERO:
				var cover_to_threat: Vector3 = _last_threat_direction
				var unit_to_cover: Vector3 = (cover_pos - unit_pos).normalized()
				var facing_bonus: float = unit_to_cover.dot(cover_to_threat)
				score += facing_bonus * 5.0

			if score > best_score:
				best_score = score
				best_pos = cover_pos
				best_type = cover_type

	# Also check terrain cover
	if _cover_system and _cover_system.has_method("find_nearest_cover"):
		var terrain_cover_pos: Vector3 = _cover_system.find_nearest_cover(unit_pos, search_radius)
		if terrain_cover_pos != Vector3.ZERO:
			var distance: float = unit_pos.distance_to(terrain_cover_pos)
			var terrain_type: int = _cover_system.get_cover_at_position(terrain_cover_pos)

			if terrain_type >= min_cover_threshold:
				var score: float = float(terrain_type) * 10.0 - distance
				if score > best_score:
					best_pos = terrain_cover_pos
					best_type = terrain_type

	# Check crater cover
	if _damage_system and _damage_system.has_method("get_nearest_crater"):
		var crater: Dictionary = _damage_system.get_nearest_crater(unit_pos, search_radius)
		if not crater.is_empty():
			var crater_pos: Vector3 = crater.position
			var distance: float = unit_pos.distance_to(crater_pos)
			var crater_cover: float = _damage_system.get_crater_cover(crater_pos)

			# Crater provides LIGHT to HEAVY cover based on size
			var crater_type: int = 1 if crater_cover < 0.4 else 2

			if crater_type >= min_cover_threshold:
				var score: float = float(crater_type) * 10.0 - distance
				if score > best_score:
					best_pos = crater_pos
					best_type = crater_type

	if best_score > 0:
		return {"position": best_pos, "type": best_type}

	return {}


func _get_cover_type_from_group(group_name: String) -> int:
	match group_name:
		"cover_fortified":
			return 3  # GameEnums.CoverType.FORTIFIED
		"cover_heavy":
			return 2  # GameEnums.CoverType.HEAVY
		"cover_light":
			return 1  # GameEnums.CoverType.LIGHT
	return 0


func _move_to_cover(cover_pos: Vector3, cover_type: int) -> void:
	"""Move unit to cover position"""
	if not _parent:
		return

	current_cover_pos = cover_pos
	current_cover_type = cover_type

	# Move parent to cover
	if _parent.has_method("move_to"):
		_parent.move_to(cover_pos)
		cover_found.emit(cover_pos, cover_type)


func _on_took_damage(_amount: float, source: Node = null) -> void:
	"""React to taking damage - dive to cover"""
	if not enabled:
		return

	# Record threat direction
	if is_instance_valid(source):
		_last_threat_direction = (source.global_position - _parent.global_position).normalized()

	# Immediately seek cover if not already in good cover
	if current_cover_type < 2:  # Less than HEAVY cover
		_dive_to_cover()


func _dive_to_cover() -> void:
	"""Emergency dive to nearest cover"""
	var best_cover: Dictionary = _find_best_cover()

	if best_cover.is_empty():
		no_cover_available.emit()
		return

	is_diving = true
	var cover_pos: Vector3 = best_cover.position

	diving_to_cover.emit(_parent.global_position, cover_pos)

	# Move faster when diving
	if _parent.has_method("set"):
		var original_speed: float = _parent.get("move_speed") if "move_speed" in _parent else 5.0
		_parent.set("move_speed", original_speed * dive_speed_multiplier)

	_move_to_cover(cover_pos, best_cover.type)


func _update_dive(_delta: float) -> void:
	"""Update dive state"""
	if not _parent:
		is_diving = false
		return

	# Check if we've reached cover
	var dist_to_cover: float = _parent.global_position.distance_to(current_cover_pos)
	if dist_to_cover < 1.0:
		is_diving = false
		is_in_cover = true

		# Restore original speed
		if _parent.has_method("set") and "move_speed" in _parent:
			# Could store/restore original speed, but for now assume 5.0
			_parent.set("move_speed", 5.0)


func _on_moved(_squad: Node, _target: Vector3) -> void:
	"""Handle player movement order - clear cover state"""
	is_in_cover = false
	is_diving = false
	_idle_time = 0.0


# =============================================================================
# PUBLIC API
# =============================================================================

## Force unit to seek cover immediately
func seek_cover_now() -> void:
	_try_find_cover()


## Force unit to dive to cover (emergency)
func dive_now() -> void:
	_dive_to_cover()


## Check if unit is currently in cover
func get_is_in_cover() -> bool:
	return is_in_cover


## Get current cover type
func get_current_cover_type() -> int:
	return current_cover_type


## Set the last known threat direction
func set_threat_direction(direction: Vector3) -> void:
	_last_threat_direction = direction.normalized()


## Clear cover state (unit is leaving cover)
func clear_cover_state() -> void:
	is_in_cover = false
	current_cover_pos = Vector3.INF
	current_cover_type = 0
