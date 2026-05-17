extends Node
## Spatial Hash Grid - Efficient spatial queries for units
## Accessed globally via SpatialHashGrid autoload (no class_name needed)

const CELL_SIZE := 50.0  # 50 meter cells

var _grid: Dictionary = {}  # Vector2i -> Array[Node3D]
var _unit_cells: Dictionary = {}  # Node3D -> Vector2i
var _faction_units: Dictionary = {}  # int (Faction) -> Array[Node3D]

func _ready() -> void:
	# Initialize faction tracking
	for faction in GameEnums.Faction.values():
		_faction_units[faction] = []

# =============================================================================
# REGISTRATION
# =============================================================================

func register_unit(unit: Node3D, faction: int) -> void:
	var cell := _get_cell(unit.global_position)
	_add_to_cell(unit, cell)
	_unit_cells[unit] = cell

	if not _faction_units.has(faction):
		_faction_units[faction] = []
	_faction_units[faction].append(unit)

func unregister_unit(unit: Node3D, faction: int) -> void:
	if _unit_cells.has(unit):
		var cell: Vector2i = _unit_cells[unit]
		_remove_from_cell(unit, cell)
		_unit_cells.erase(unit)

	if _faction_units.has(faction):
		_faction_units[faction].erase(unit)

func update_unit_position(unit: Node3D) -> void:
	if not _unit_cells.has(unit):
		return

	var old_cell: Vector2i = _unit_cells[unit]
	var new_cell := _get_cell(unit.global_position)

	if old_cell != new_cell:
		_remove_from_cell(unit, old_cell)
		_add_to_cell(unit, new_cell)
		_unit_cells[unit] = new_cell

# =============================================================================
# QUERIES
# =============================================================================

func get_units_in_radius(center: Vector3, radius: float) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var radius_sq := radius * radius

	# Get all cells that could contain units within radius
	var min_cell := _get_cell(center - Vector3(radius, 0, radius))
	var max_cell := _get_cell(center + Vector3(radius, 0, radius))

	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var cell := Vector2i(x, y)
			if _grid.has(cell):
				for unit: Node3D in _grid[cell]:
					if is_instance_valid(unit):
						var dist_sq := center.distance_squared_to(unit.global_position)
						if dist_sq <= radius_sq:
							result.append(unit)

	return result

func get_units_in_radius_by_faction(center: Vector3, radius: float, faction: int) -> Array[Node3D]:
	var all_units := get_units_in_radius(center, radius)
	var result: Array[Node3D] = []

	for unit in all_units:
		if unit.has_method("get_faction") and unit.get_faction() == faction:
			result.append(unit)

	return result

func get_enemies_in_radius(center: Vector3, radius: float, my_faction: int) -> Array[Node3D]:
	var all_units := get_units_in_radius(center, radius)
	var result: Array[Node3D] = []

	var is_us := GameEnums.is_us_faction(my_faction)

	for unit in all_units:
		if unit.has_method("get_faction"):
			var unit_faction: int = unit.get_faction()
			var unit_is_us := GameEnums.is_us_faction(unit_faction)
			if is_us != unit_is_us:
				result.append(unit)

	return result

func get_friendlies_in_radius(center: Vector3, radius: float, my_faction: int) -> Array[Node3D]:
	var all_units := get_units_in_radius(center, radius)
	var result: Array[Node3D] = []

	var is_us := GameEnums.is_us_faction(my_faction)

	for unit in all_units:
		if unit.has_method("get_faction"):
			var unit_faction: int = unit.get_faction()
			var unit_is_us := GameEnums.is_us_faction(unit_faction)
			if is_us == unit_is_us and unit_faction != my_faction:
				result.append(unit)

	return result

func get_nearest_enemy(from: Vector3, my_faction: int, max_range: float = 500.0) -> Node3D:
	var enemies := get_enemies_in_radius(from, max_range, my_faction)

	var nearest: Node3D = null
	var nearest_dist := INF

	for enemy in enemies:
		var dist := from.distance_squared_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	return nearest

func get_all_units_of_faction(faction: int) -> Array[Node3D]:
	if _faction_units.has(faction):
		var result: Array[Node3D] = []
		for unit in _faction_units[faction]:
			if is_instance_valid(unit):
				result.append(unit)
		return result
	return []

func get_all_units_in_radius(center: Vector3, radius: float) -> Array[Node3D]:
	## Get all units regardless of faction within radius
	return get_units_in_radius(center, radius)

func get_units_in_area(min_corner: Vector3, max_corner: Vector3) -> Array[Node3D]:
	var result: Array[Node3D] = []

	var min_cell := _get_cell(min_corner)
	var max_cell := _get_cell(max_corner)

	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var cell := Vector2i(x, y)
			if _grid.has(cell):
				for unit: Node3D in _grid[cell]:
					if is_instance_valid(unit):
						var pos := unit.global_position
						if pos.x >= min_corner.x and pos.x <= max_corner.x:
							if pos.z >= min_corner.z and pos.z <= max_corner.z:
								result.append(unit)

	return result

# =============================================================================
# LINE OF SIGHT / RAYCAST HELPERS
# =============================================================================

func get_units_along_line(start: Vector3, end: Vector3, width: float = 5.0) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var direction := (end - start).normalized()
	var length := start.distance_to(end)
	var perpendicular := Vector3(-direction.z, 0, direction.x)

	# Get bounding box of the line
	var min_corner := Vector3(
		minf(start.x, end.x) - width,
		minf(start.y, end.y),
		minf(start.z, end.z) - width
	)
	var max_corner := Vector3(
		maxf(start.x, end.x) + width,
		maxf(start.y, end.y),
		maxf(start.z, end.z) + width
	)

	var candidates := get_units_in_area(min_corner, max_corner)

	for unit in candidates:
		var to_unit := unit.global_position - start
		var along_line := to_unit.dot(direction)

		if along_line >= 0 and along_line <= length:
			var perpendicular_dist := absf(to_unit.dot(perpendicular))
			if perpendicular_dist <= width:
				result.append(unit)

	return result

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

func _get_cell(position: Vector3) -> Vector2i:
	return Vector2i(
		int(floorf(position.x / CELL_SIZE)),
		int(floorf(position.z / CELL_SIZE))
	)

func _add_to_cell(unit: Node3D, cell: Vector2i) -> void:
	if not _grid.has(cell):
		_grid[cell] = []
	_grid[cell].append(unit)

func _remove_from_cell(unit: Node3D, cell: Vector2i) -> void:
	if _grid.has(cell):
		_grid[cell].erase(unit)
		if _grid[cell].is_empty():
			_grid.erase(cell)

# =============================================================================
# DEBUG
# =============================================================================

func get_debug_info() -> Dictionary:
	var total_units := 0
	for cell in _grid.values():
		total_units += cell.size()

	return {
		"cell_count": _grid.size(),
		"total_units": total_units,
		"cell_size": CELL_SIZE,
	}
