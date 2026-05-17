extends Node
## CoverSystem - Provides terrain-based cover for infantry combat.
## Integrates with TerrainIntegration to query terrain types and convert to cover values.
## Based on Warno research: infantry gets terrain cover, vehicles do not.

const VietnamWeaponDataScript = preload("res://battle_system/data/vietnam_weapon_data.gd")

## Cover detection settings
const COVER_DETECTION_RADIUS: float = 2.0  # How far to check for nearby cover objects
const COVER_UPDATE_INTERVAL: float = 0.5  # How often to update cover state (seconds)

## Cover object groups
const COVER_GROUPS: Array[String] = ["cover_heavy", "cover_light", "cover_fortified", "buildings"]

## Cached terrain integration reference
var _terrain: Node = null
#var _last_update_time: float = 0.0  # Reserved for throttled updates

## Unit cover cache (to avoid repeated queries)
var _unit_cover_cache: Dictionary = {}  # {unit_id: {cover_type, timestamp}}
const CACHE_TTL: float = 0.5  # Cache lifetime in seconds


func _ready() -> void:
	# Get terrain integration reference
	_terrain = get_node_or_null("/root/TerrainIntegration")
	print("[CoverSystem] Initialized - terrain integration: %s" % ("found" if _terrain else "not found"))


## Get cover type at a world position.
## Queries terrain type and nearby cover objects to determine best cover.
func get_cover_at_position(world_pos: Vector3) -> int:
	var cover_type: int = GameEnums.CoverType.NONE

	# Check nearby cover objects first (highest priority)
	var object_cover: int = _check_cover_objects(world_pos)
	if object_cover > cover_type:
		cover_type = object_cover

	# Check terrain type if no object cover
	if cover_type == GameEnums.CoverType.NONE and _terrain:
		var terrain_cover: int = _get_terrain_cover(world_pos)
		if terrain_cover > cover_type:
			cover_type = terrain_cover

	return cover_type


## Get cover type for a specific unit.
## Uses caching for performance.
func get_cover_for_unit(unit: Node) -> int:
	if not is_instance_valid(unit):
		return GameEnums.CoverType.NONE

	# Check if unit is a vehicle (vehicles don't get terrain cover)
	if _is_vehicle(unit):
		return GameEnums.CoverType.NONE

	var unit_id: int = unit.get_instance_id()
	var current_time: float = Time.get_ticks_msec() / 1000.0

	# Check cache
	if unit_id in _unit_cover_cache:
		var cached: Dictionary = _unit_cover_cache[unit_id]
		if current_time - cached.timestamp < CACHE_TTL:
			return cached.cover_type

	# Calculate new cover
	var cover_type: int = get_cover_at_position(unit.global_position)

	# Update cache
	_unit_cover_cache[unit_id] = {
		"cover_type": cover_type,
		"timestamp": current_time
	}

	return cover_type


## Get damage reduction for a unit based on cover.
## Returns value between 0.0 (no reduction) and 0.7 (max reduction).
func get_damage_reduction(unit: Node) -> float:
	var cover_type: int = get_cover_for_unit(unit)
	return GameEnums.get_cover_damage_reduction(cover_type)


## Get stealth bonus for a unit based on cover.
## Returns value between 0.0 (no stealth) and 0.9 (max stealth).
func get_stealth_bonus(unit: Node) -> float:
	var cover_type: int = get_cover_for_unit(unit)
	match cover_type:
		GameEnums.CoverType.NONE:
			return 0.0
		GameEnums.CoverType.LIGHT:
			return 0.5
		GameEnums.CoverType.HEAVY:
			return 0.8
		GameEnums.CoverType.FORTIFIED:
			return 0.9
	return 0.0


## Get suppression reduction for a unit based on cover.
## Units in cover receive less suppression.
func get_suppression_reduction(unit: Node) -> float:
	var cover_type: int = get_cover_for_unit(unit)
	match cover_type:
		GameEnums.CoverType.NONE:
			return 1.0  # Full suppression
		GameEnums.CoverType.LIGHT:
			return 0.7  # 30% reduction
		GameEnums.CoverType.HEAVY:
			return 0.4  # 60% reduction
		GameEnums.CoverType.FORTIFIED:
			return 0.2  # 80% reduction
	return 1.0


## Check if a position provides any cover.
func has_cover(world_pos: Vector3) -> bool:
	return get_cover_at_position(world_pos) != GameEnums.CoverType.NONE


## Find nearest cover position from a given position.
## Returns Vector3.ZERO if no cover found within search_radius.
func find_nearest_cover(from_pos: Vector3, search_radius: float = 20.0) -> Vector3:
	var best_pos: Vector3 = Vector3.ZERO
	var best_distance: float = search_radius + 1.0

	# Check cover objects
	for group in COVER_GROUPS:
		var objects: Array[Node] = get_tree().get_nodes_in_group(group)
		for obj in objects:
			if not is_instance_valid(obj):
				continue
			var distance: float = from_pos.distance_to(obj.global_position)
			if distance < best_distance:
				best_pos = obj.global_position
				best_distance = distance

	return best_pos


## Check nearby cover objects for cover type.
func _check_cover_objects(world_pos: Vector3) -> int:
	var best_cover: int = GameEnums.CoverType.NONE

	# Check each cover group
	for group in COVER_GROUPS:
		var objects: Array[Node] = get_tree().get_nodes_in_group(group)
		for obj in objects:
			if not is_instance_valid(obj):
				continue

			var distance: float = world_pos.distance_to(obj.global_position)
			if distance > COVER_DETECTION_RADIUS:
				continue

			# Get cover type from object
			var obj_cover: int = _get_object_cover_type(obj, group)
			if obj_cover > best_cover:
				best_cover = obj_cover

	return best_cover


## Get cover type from a cover object.
func _get_object_cover_type(obj: Node, group: String) -> int:
	# Check for DestructibleCover component first (dynamic cover)
	var destructible: Node = _find_destructible_cover(obj)
	if destructible and destructible.has_method("get_cover_type"):
		return destructible.get_cover_type()

	# Check if object has explicit cover_type property
	if obj.has_method("get") and obj.get("cover_type"):
		return obj.cover_type

	# Infer from group
	match group:
		"cover_fortified", "buildings":
			return GameEnums.CoverType.FORTIFIED
		"cover_heavy":
			return GameEnums.CoverType.HEAVY
		"cover_light":
			return GameEnums.CoverType.LIGHT

	return GameEnums.CoverType.NONE


## Find DestructibleCover component on object or its children.
func _find_destructible_cover(obj: Node) -> Node:
	# Check if obj itself is destructible
	if obj.is_in_group("destructible_cover"):
		return obj

	# Check children
	for child in obj.get_children():
		if child.is_in_group("destructible_cover"):
			return child

	return null


## Get cover from terrain type at position.
func _get_terrain_cover(world_pos: Vector3) -> int:
	if not _terrain:
		return GameEnums.CoverType.NONE

	# Query terrain type
	var terrain_type: int = -1
	if _terrain.has_method("get_terrain_type_at"):
		terrain_type = _terrain.get_terrain_type_at(world_pos)
	elif _terrain.has_method("get_cell_data"):
		var cell_data: Dictionary = _terrain.get_cell_data(world_pos)
		terrain_type = cell_data.get("terrain_type", -1)

	if terrain_type < 0:
		return GameEnums.CoverType.NONE

	# Map terrain type to cover using GameEnums
	return GameEnums.terrain_to_cover(terrain_type)


## Check if unit is a vehicle (vehicles don't get terrain cover per Warno rules).
func _is_vehicle(unit: Node) -> bool:
	if unit.has_method("get") and unit.get("data"):
		if unit.data and "is_vehicle" in unit.data:
			return unit.data.is_vehicle
	return false


## Clear the cover cache for a specific unit (call when unit moves significantly).
func invalidate_cache(unit: Node) -> void:
	if is_instance_valid(unit):
		var unit_id: int = unit.get_instance_id()
		_unit_cover_cache.erase(unit_id)


## Clear entire cache (call when terrain changes significantly).
func clear_cache() -> void:
	_unit_cover_cache.clear()


## Get debug info about cover at a position.
func get_cover_debug_info(world_pos: Vector3) -> Dictionary:
	var cover_type: int = get_cover_at_position(world_pos)
	var cover_name: String = ""
	match cover_type:
		GameEnums.CoverType.NONE:
			cover_name = "None"
		GameEnums.CoverType.LIGHT:
			cover_name = "Light"
		GameEnums.CoverType.HEAVY:
			cover_name = "Heavy"
		GameEnums.CoverType.FORTIFIED:
			cover_name = "Fortified"

	return {
		"position": world_pos,
		"cover_type": cover_type,
		"cover_name": cover_name,
		"damage_reduction": GameEnums.get_cover_damage_reduction(cover_type),
		"terrain_available": _terrain != null
	}
