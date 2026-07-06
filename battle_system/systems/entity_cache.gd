extends Node
## EntityCache - Cached lookups for static/semi-static entities
## Replaces repeated get_nodes_in_group() calls with cached arrays
## Invalidated by BattleSignals events

## Cached arrays with dirty flags
var _firebases: Array[Node] = []
var _firebases_dirty: bool = true

var _supply_depots: Array[Node] = []
var _supply_depots_dirty: bool = true

var _landing_zones: Array[Node] = []
var _landing_zones_dirty: bool = true

var _hq_buildings: Array[Node] = []
var _hq_buildings_dirty: bool = true


func _ready() -> void:
	# Connect to invalidation signals
	if BattleSignals:
		if BattleSignals.has_signal("firebase_constructed"):
			BattleSignals.firebase_constructed.connect(_on_firebase_changed)
		if BattleSignals.has_signal("firebase_destroyed"):
			BattleSignals.firebase_destroyed.connect(_on_firebase_changed)
		if BattleSignals.has_signal("building_constructed"):
			BattleSignals.building_constructed.connect(_on_building_constructed)
		if BattleSignals.has_signal("building_destroyed"):
			BattleSignals.building_destroyed.connect(_on_building_destroyed)
		if BattleSignals.has_signal("building_placed"):
			BattleSignals.building_placed.connect(_on_building_placed)

	print("[EntityCache] Initialized - caching firebases, depots, LZs")


func _on_firebase_changed(_firebase: Node) -> void:
	_firebases_dirty = true


func _on_building_constructed(_building: Node, type: int) -> void:
	# Invalidate relevant cache based on building type
	match type:
		GameEnums.BuildingType.SUPPLY_DEPOT:
			_supply_depots_dirty = true
		GameEnums.BuildingType.HELIPAD, GameEnums.BuildingType.PSP_HELIPAD:
			_landing_zones_dirty = true
		GameEnums.BuildingType.TOC:
			_hq_buildings_dirty = true
			_firebases_dirty = true  # TOC affects firebase status


func _on_building_destroyed(building: Node, type: int) -> void:
	_on_building_constructed(building, type)


func _on_building_placed(building: Node, _pos: Vector3) -> void:
	# When any building is placed, invalidate all caches to be safe
	_firebases_dirty = true
	_supply_depots_dirty = true
	_landing_zones_dirty = true
	_hq_buildings_dirty = true


## Get all firebases (cached)
func get_firebases() -> Array[Node]:
	if _firebases_dirty:
		_firebases.clear()
		_firebases.append_array(get_tree().get_nodes_in_group("firebases"))
		_firebases_dirty = false
	return _firebases


## Get all supply depots (cached)
func get_supply_depots() -> Array[Node]:
	if _supply_depots_dirty:
		_supply_depots.clear()
		_supply_depots.append_array(get_tree().get_nodes_in_group("supply_depots"))
		_supply_depots_dirty = false
	return _supply_depots


## Get all landing zones (cached)
func get_landing_zones() -> Array[Node]:
	if _landing_zones_dirty:
		_landing_zones.clear()
		_landing_zones.append_array(get_tree().get_nodes_in_group("landing_zones"))
		_landing_zones_dirty = false
	return _landing_zones


## Get all HQ buildings (cached)
func get_hq_buildings() -> Array[Node]:
	if _hq_buildings_dirty:
		_hq_buildings.clear()
		_hq_buildings.append_array(get_tree().get_nodes_in_group("hq_buildings"))
		_hq_buildings_dirty = false
	return _hq_buildings


## Get nearest firebase to position
func get_nearest_firebase(position: Vector3, must_be_active: bool = true) -> Node:
	var firebases := get_firebases()
	var nearest: Node = null
	var nearest_dist: float = INF

	for fb in firebases:
		if not is_instance_valid(fb):
			continue

		# Check if firebase is active (has HQ building)
		if must_be_active:
			var is_active: bool = true
			if fb.has_method("is_active"):
				is_active = fb.is_active()
			if not is_active:
				continue

		var dist := position.distance_to(fb.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = fb

	return nearest


## Get nearest firebase that the position is within influence of
func get_firebase_for_position(position: Vector3) -> Node:
	var firebases := get_firebases()

	for fb in firebases:
		if not is_instance_valid(fb):
			continue

		# Check if within firebase influence radius
		if fb.has_method("is_position_in_influence"):
			if fb.is_position_in_influence(position):
				return fb
		elif "influence_radius" in fb:
			var dist := position.distance_to(fb.global_position)
			if dist <= fb.influence_radius:
				return fb

	return null


## Get nearest supply depot to position
func get_nearest_supply_depot(position: Vector3, faction: int = -1) -> Node:
	var depots := get_supply_depots()
	var nearest: Node = null
	var nearest_dist: float = INF

	for depot in depots:
		if not is_instance_valid(depot):
			continue

		# Check faction compatibility
		if faction >= 0 and "faction" in depot:
			if depot.faction != faction:
				continue

		# Check if depot is operational
		if depot.has_method("is_destroyed") and depot.is_destroyed():
			continue

		# Check if depot has supply available
		if depot.has_method("get_available_supply"):
			if depot.get_available_supply() <= 0.0:
				continue

		var dist := position.distance_to(depot.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = depot

	return nearest


## Get nearest landing zone to position
func get_nearest_landing_zone(position: Vector3, must_be_clear: bool = false) -> Node:
	var lzs := get_landing_zones()
	var nearest: Node = null
	var nearest_dist: float = INF

	for lz in lzs:
		if not is_instance_valid(lz):
			continue

		# Check if LZ is clear (not hot)
		if must_be_clear and lz.has_method("is_hot"):
			if lz.is_hot():
				continue

		var dist := position.distance_to(lz.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = lz

	return nearest


## Force invalidate all caches (call after major scene changes)
func invalidate_all() -> void:
	_firebases_dirty = true
	_supply_depots_dirty = true
	_landing_zones_dirty = true
	_hq_buildings_dirty = true


## Get cache stats for debugging
func get_cache_stats() -> Dictionary:
	return {
		"firebases": _firebases.size(),
		"firebases_dirty": _firebases_dirty,
		"supply_depots": _supply_depots.size(),
		"supply_depots_dirty": _supply_depots_dirty,
		"landing_zones": _landing_zones.size(),
		"landing_zones_dirty": _landing_zones_dirty,
	}
