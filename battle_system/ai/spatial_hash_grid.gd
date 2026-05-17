extends Node
## class_name SpatialHashGrid  # Removed - registered as autoload instead

## Spatial Hash Grid - Efficient spatial queries for AI
## Divides world into cells for O(1) neighbor lookups

## Configuration
const CELL_SIZE: float = 20.0  # Size of each grid cell

## Storage
var _cells: Dictionary = {}  # Vector2i -> Array[Node3D]
var _unit_cells: Dictionary = {}  # Node3D -> Vector2i
var _unit_factions: Dictionary = {}  # Node3D -> faction


func _ready() -> void:
	# Connect to unit signals
	if BattleSignals:
		BattleSignals.unit_spawned.connect(_on_unit_spawned)
		BattleSignals.unit_died.connect(_on_unit_died)

	print("[SpatialHashGrid] Initialized with cell size %.1f" % CELL_SIZE)


func _process(_delta: float) -> void:
	# Update positions of all tracked units
	_update_unit_positions()


func _update_unit_positions() -> void:
	"""Update cell assignments for all units"""
	for unit in _unit_cells.keys():
		if not is_instance_valid(unit):
			_remove_unit_internal(unit)
			continue

		var new_cell: Vector2i = _get_cell(unit.global_position)
		var old_cell: Vector2i = _unit_cells[unit]

		if new_cell != old_cell:
			_move_unit_to_cell(unit, old_cell, new_cell)


func _get_cell(position: Vector3) -> Vector2i:
	"""Convert world position to cell coordinates"""
	return Vector2i(
		int(floor(position.x / CELL_SIZE)),
		int(floor(position.z / CELL_SIZE))
	)


func _move_unit_to_cell(unit: Node3D, old_cell: Vector2i, new_cell: Vector2i) -> void:
	"""Move unit from one cell to another"""
	# Remove from old cell
	if old_cell in _cells:
		_cells[old_cell].erase(unit)

	# Add to new cell
	if new_cell not in _cells:
		_cells[new_cell] = []
	_cells[new_cell].append(unit)

	_unit_cells[unit] = new_cell


func _on_unit_spawned(unit: Node3D, faction: int) -> void:
	"""Handle unit spawn"""
	register_unit(unit, faction)


func _on_unit_died(unit: Node3D, _killer: Node3D) -> void:
	"""Handle unit death"""
	unregister_unit(unit)


func _remove_unit_internal(unit: Node3D) -> void:
	"""Internal removal without validity check"""
	if unit in _unit_cells:
		var cell: Vector2i = _unit_cells[unit]
		if cell in _cells:
			_cells[cell].erase(unit)
		_unit_cells.erase(unit)
	_unit_factions.erase(unit)


## Public API

func register_unit(unit: Node3D, faction: int) -> void:
	"""Register a unit with the spatial hash"""
	if unit in _unit_cells:
		return  # Already registered

	var cell: Vector2i = _get_cell(unit.global_position)

	if cell not in _cells:
		_cells[cell] = []
	_cells[cell].append(unit)

	_unit_cells[unit] = cell
	_unit_factions[unit] = faction


func unregister_unit(unit: Node3D) -> void:
	"""Remove a unit from the spatial hash"""
	_remove_unit_internal(unit)


func get_units_in_radius(position: Vector3, radius: float, faction_filter: int = -1) -> Array[Node3D]:
	"""Get all units within radius of position"""
	var result: Array[Node3D] = []
	var radius_sq: float = radius * radius

	# Calculate cell range to check
	var cells_to_check: int = int(ceil(radius / CELL_SIZE)) + 1
	var center_cell: Vector2i = _get_cell(position)

	for dx in range(-cells_to_check, cells_to_check + 1):
		for dz in range(-cells_to_check, cells_to_check + 1):
			var cell := Vector2i(center_cell.x + dx, center_cell.y + dz)

			if cell not in _cells:
				continue

			for unit in _cells[cell]:
				if not is_instance_valid(unit):
					continue

				# Faction filter
				if faction_filter >= 0:
					if unit not in _unit_factions:
						continue
					if _unit_factions[unit] != faction_filter:
						continue

				# Distance check
				var dist_sq: float = position.distance_squared_to(unit.global_position)
				if dist_sq <= radius_sq:
					result.append(unit)

	return result


func get_enemies_in_radius(position: Vector3, radius: float, my_faction: int) -> Array[Node3D]:
	"""Get enemy units within radius"""
	var result: Array[Node3D] = []
	var radius_sq: float = radius * radius

	var cells_to_check: int = int(ceil(radius / CELL_SIZE)) + 1
	var center_cell: Vector2i = _get_cell(position)

	for dx in range(-cells_to_check, cells_to_check + 1):
		for dz in range(-cells_to_check, cells_to_check + 1):
			var cell := Vector2i(center_cell.x + dx, center_cell.y + dz)

			if cell not in _cells:
				continue

			for unit in _cells[cell]:
				if not is_instance_valid(unit):
					continue

				# Only enemies
				if unit in _unit_factions:
					if _unit_factions[unit] == my_faction:
						continue

				var dist_sq: float = position.distance_squared_to(unit.global_position)
				if dist_sq <= radius_sq:
					result.append(unit)

	return result


func get_nearest_enemy(position: Vector3, my_faction: int, max_range: float = 100.0) -> Node3D:
	"""Get nearest enemy unit"""
	var enemies: Array[Node3D] = get_enemies_in_radius(position, max_range, my_faction)

	var nearest: Node3D = null
	var nearest_dist_sq: float = INF

	for enemy in enemies:
		var dist_sq: float = position.distance_squared_to(enemy.global_position)
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = enemy

	return nearest


func get_friendlies_in_radius(position: Vector3, radius: float, my_faction: int) -> Array[Node3D]:
	"""Get friendly units within radius"""
	return get_units_in_radius(position, radius, my_faction)


func get_unit_count_in_area(min_pos: Vector3, max_pos: Vector3, faction_filter: int = -1) -> int:
	"""Count units in rectangular area"""
	var count: int = 0

	var min_cell: Vector2i = _get_cell(min_pos)
	var max_cell: Vector2i = _get_cell(max_pos)

	for x in range(min_cell.x, max_cell.x + 1):
		for z in range(min_cell.y, max_cell.y + 1):
			var cell := Vector2i(x, z)

			if cell not in _cells:
				continue

			for unit in _cells[cell]:
				if not is_instance_valid(unit):
					continue

				if faction_filter >= 0:
					if unit not in _unit_factions:
						continue
					if _unit_factions[unit] != faction_filter:
						continue

				# Check if actually in bounds
				var pos: Vector3 = unit.global_position
				if pos.x >= min_pos.x and pos.x <= max_pos.x:
					if pos.z >= min_pos.z and pos.z <= max_pos.z:
						count += 1

	return count


func get_faction(unit: Node3D) -> int:
	"""Get faction of a registered unit"""
	if unit in _unit_factions:
		return _unit_factions[unit]
	return -1


func get_total_unit_count() -> int:
	"""Get total registered units"""
	return _unit_cells.size()
