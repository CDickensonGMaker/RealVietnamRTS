class_name TerrainGrid
extends RefCounted
## Unified terrain grid - SINGLE SOURCE OF TRUTH for all terrain data
##
## Consolidates GameplayGrid, ClearingSystem vegetation_map, and VegetationManager terrain data
## into one efficient grid. All systems read from here, only ClearingSystem/DamageSystem write.
##
## Cell size: 4m (balance between HeightmapStorage 2m and old GameplayGrid 12m)
## 3km map = 750x750 cells = 562,500 cells at 8 bytes/cell = 4.3 MB

signal cell_updated(region: Rect2i)

# Import unified types
const TerrainTypesConst = preload("res://terrain/terrain_types.gd")
const ClearingStateClass = preload("res://terrain/clearing_state.gd")
const GridResultClass = preload("res://terrain/core/grid_result.gd")
const GridCoordsClass = preload("res://terrain/core/grid_coords.gd")

# Grid configuration - uses canonical GAMEPLAY_CELL_SIZE from GridCoords
const CELL_SIZE := GridCoordsClass.GAMEPLAY_CELL_SIZE  # 4 meter cells

# Type aliases for convenience
const TerrainType = TerrainTypesConst.Type
const ClearingStage = ClearingStateClass.Stage

# Grid dimensions
var width: int = 0
var height: int = 0
var world_size: float = 0.0

# Per-cell data arrays (packed for memory efficiency)
# Total: 8 bytes per cell + 4 bytes occupancy = 12 bytes per cell
var _elevation: PackedFloat32Array       # 4 bytes - height in meters (using float for precision)
var _slope: PackedByteArray              # 1 byte  - 0-255 slope angle
var _terrain_type: PackedByteArray       # 1 byte  - TerrainType enum
var _vegetation_density: PackedByteArray # 1 byte  - 0-255 density
var _clearing_stage: PackedByteArray     # 1 byte  - ClearingStage enum
var _passability: PackedByteArray        # 1 byte  - Flags: bit0=walkable, bit1=buildable
var _occupancy: PackedInt32Array         # 4 bytes - Building ID at cell (0 = unoccupied)

# Passability flags
const PASSABLE_WALKABLE := 1
const PASSABLE_BUILDABLE := 2

# Terrain classification thresholds (from GameplayGrid)
const CLIFF_SLOPE_THRESHOLD := 0.7
const WATER_ELEVATION_MAX := 5.0
const FLOODED_ELEVATION_MAX := 2.0
const RICE_PADDY_SLOPE_MAX := 0.1
const LIGHT_JUNGLE_SLOPE_MIN := 0.4
const MEDIUM_ELEVATION_THRESHOLD := 50.0
const HEAVY_ELEVATION_THRESHOLD := 150.0
const HIGH_ELEVATION_THRESHOLD := 250.0
const RICE_PADDY_RANDOM_CHANCE := 0.3

# LOS blocking thresholds
const LOS_HEAVY_JUNGLE_DENSITY := 205  # 0.8 * 255
const LOS_MEDIUM_JUNGLE_DENSITY := 230 # 0.9 * 255

# Combat modifiers
const SLOPE_MOVEMENT_PENALTY := 0.25  # Reduced from 0.5 for smoother movement on slopes

# Reference to heightmap for updates
var _heightmap: RefCounted  # HeightmapStorage


func _init(world_size_meters: float = 3000.0) -> void:
	world_size = world_size_meters
	width = int(ceil(world_size / CELL_SIZE))
	height = width  # Square grid

	var total_cells: int = width * height

	# Initialize arrays
	_elevation.resize(total_cells)
	_slope.resize(total_cells)
	_terrain_type.resize(total_cells)
	_vegetation_density.resize(total_cells)
	_clearing_stage.resize(total_cells)
	_passability.resize(total_cells)
	_occupancy.resize(total_cells)

	# Default values
	_elevation.fill(0.0)
	_slope.fill(0)
	_terrain_type.fill(TerrainType.GRASSLAND)
	_vegetation_density.fill(128)  # 0.5 normalized
	_clearing_stage.fill(ClearingStage.JUNGLE)
	_passability.fill(PASSABLE_WALKABLE)
	_occupancy.fill(0)

	var memory_mb := (total_cells * 12) / 1048576.0  # 8 bytes data + 4 bytes occupancy
	print("[TerrainGrid] Initialized %dx%d grid (%.1fm cells, %.2f MB)" % [
		width, height, CELL_SIZE, memory_mb
	])


# =============================================================================
# COORDINATE CONVERSION
# =============================================================================

## Convert world position to grid coordinates
func world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		clampi(int(world_pos.x / CELL_SIZE), 0, width - 1),
		clampi(int(world_pos.z / CELL_SIZE), 0, height - 1)
	)


## Convert grid coordinates to world position (cell center)
func grid_to_world(grid_pos: Vector2i) -> Vector3:
	return Vector3(
		(grid_pos.x + 0.5) * CELL_SIZE,
		0.0,  # Y filled by caller using get_elevation
		(grid_pos.y + 0.5) * CELL_SIZE
	)


## Get cell index from grid coordinates
func _grid_to_index(gx: int, gz: int) -> int:
	return gz * width + gx


## Check if grid coordinates are valid
func _is_valid_coord(gx: int, gz: int) -> bool:
	return gx >= 0 and gx < width and gz >= 0 and gz < height


# =============================================================================
# EXPLICIT COORDINATE API (with error handling)
# =============================================================================

## Convert world position to grid coordinates with explicit error handling
## Returns GridResult with validity status - use for new code
func world_to_grid_checked(world_pos: Vector3) -> GridResultClass:
	var gx := int(floor(world_pos.x / CELL_SIZE))
	var gz := int(floor(world_pos.z / CELL_SIZE))

	# Clamp for fallback coords
	var clamped_x := clampi(gx, 0, width - 1)
	var clamped_z := clampi(gz, 0, height - 1)

	if gx < 0 or gx >= width or gz < 0 or gz >= height:
		return GridResultClass.err(
			"Position %s -> cell (%d, %d) out of bounds [0, %d)" % [world_pos, gx, gz, width],
			Vector2i(clamped_x, clamped_z)
		)

	return GridResultClass.ok(Vector2i(gx, gz))


## Get all cells covered by a rectangular footprint
func get_footprint_cells(center: Vector3, size: Vector2) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []

	var half_size := size * 0.5
	var min_world := Vector3(center.x - half_size.x, 0, center.z - half_size.y)
	var max_world := Vector3(center.x + half_size.x, 0, center.z + half_size.y)

	var min_result := world_to_grid_checked(min_world)
	var max_result := world_to_grid_checked(max_world)

	var min_cell := min_result.coords
	var max_cell := max_result.coords

	for z in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			if _is_valid_coord(x, z):
				cells.append(Vector2i(x, z))

	return cells


## Validate a building footprint for placement
## Returns Dictionary with validation results:
##   valid: bool - Can build here
##   cells: Array[Vector2i] - All cells in footprint
##   blocking_cells: Dictionary[Vector2i, String] - Cells that block with reasons
##   required_clearing: Array[Vector2i] - Cells that need clearing
##   average_elevation: float
##   max_slope: float
##   warnings: Array[String]
func validate_footprint(center: Vector3, size: Vector2, _building_type: int = -1) -> Dictionary:
	var result := {
		"valid": false,
		"cells": [] as Array[Vector2i],
		"blocking_cells": {},
		"required_clearing": [] as Array[Vector2i],
		"average_elevation": 0.0,
		"min_elevation": 0.0,
		"max_elevation": 0.0,
		"max_slope": 0.0,
		"warnings": [] as Array[String],
	}

	# Get cells covered by footprint
	result["cells"] = get_footprint_cells(center, size)

	if result["cells"].is_empty():
		result["warnings"].append("Footprint outside map bounds")
		return result

	# Analyze each cell
	var elevations: Array[float] = []

	for cell: Vector2i in result["cells"]:
		var idx := _grid_to_index(cell.x, cell.y)

		# Check terrain type
		var ttype: int = _terrain_type[idx]
		if ttype == TerrainType.WATER:
			result["blocking_cells"][cell] = "Water"
			continue
		if ttype == TerrainType.CLIFF:
			result["blocking_cells"][cell] = "Cliff"
			continue

		# Check slope (30% threshold for buildings)
		var slope: float = float(_slope[idx]) / 255.0
		if slope > 0.3:
			result["blocking_cells"][cell] = "Too steep (%.0f%%)" % (slope * 100)
			continue
		result["max_slope"] = maxf(result["max_slope"], slope)

		# Check clearing state
		var clearing: int = _clearing_stage[idx]
		if clearing < ClearingStage.CLEARED:
			result["required_clearing"].append(cell)

		# Check occupancy
		if _occupancy[idx] != 0:
			result["blocking_cells"][cell] = "Occupied"
			continue

		# Collect elevation
		elevations.append(_elevation[idx])

	# Calculate elevation stats
	if not elevations.is_empty():
		var total: float = 0.0
		result["min_elevation"] = elevations[0]
		result["max_elevation"] = elevations[0]
		for h: float in elevations:
			total += h
			result["min_elevation"] = minf(result["min_elevation"], h)
			result["max_elevation"] = maxf(result["max_elevation"], h)
		result["average_elevation"] = total / elevations.size()

		# Warn if elevation variance is high
		var variance: float = result["max_elevation"] - result["min_elevation"]
		if variance > 2.0:
			result["warnings"].append("Uneven terrain (%.1fm variance)" % variance)

	result["valid"] = result["blocking_cells"].is_empty()
	return result


# =============================================================================
# OCCUPANCY MANAGEMENT
# =============================================================================

## Check if cell is occupied by a building
func is_occupied_at(gx: int, gz: int) -> bool:
	if not _is_valid_coord(gx, gz):
		return true  # Out of bounds treated as occupied
	return _occupancy[_grid_to_index(gx, gz)] != 0


## Get the building ID occupying a cell (0 = unoccupied)
func get_occupancy_at(gx: int, gz: int) -> int:
	if not _is_valid_coord(gx, gz):
		return -1
	return _occupancy[_grid_to_index(gx, gz)]


## Set cell as occupied by a building
func set_occupied(gx: int, gz: int, building_id: int) -> void:
	if _is_valid_coord(gx, gz):
		_occupancy[_grid_to_index(gx, gz)] = building_id


## Clear cell occupancy
func clear_occupancy(gx: int, gz: int) -> void:
	if _is_valid_coord(gx, gz):
		_occupancy[_grid_to_index(gx, gz)] = 0


## Set multiple cells as occupied (for building footprint)
func set_cells_occupied(cells: Array[Vector2i], building_id: int) -> void:
	for cell: Vector2i in cells:
		set_occupied(cell.x, cell.y, building_id)


## Clear multiple cells occupancy (when building is destroyed)
func clear_cells_occupancy(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		clear_occupancy(cell.x, cell.y)


# =============================================================================
# BUILD FROM HEIGHTMAP
# =============================================================================

## Build grid from HeightmapStorage data
func build_from_heightmap(heightmap: RefCounted) -> void:
	if not heightmap:
		push_warning("[TerrainGrid] No heightmap provided")
		return

	_heightmap = heightmap

	print("[TerrainGrid] Building grid from heightmap...")
	var start_time := Time.get_ticks_msec()

	# Seeded RNG for deterministic terrain type assignment
	var rng := RandomNumberGenerator.new()
	rng.seed = 42  # Fixed seed for consistency

	for gz in height:
		for gx in width:
			var idx: int = _grid_to_index(gx, gz)

			# Get world position for this cell center
			var world_x: float = (gx + 0.5) * CELL_SIZE
			var world_z: float = (gz + 0.5) * CELL_SIZE

			# Sample elevation from heightmap
			var h: float = heightmap.sample_world(world_x, world_z)
			_elevation[idx] = h

			# Calculate slope from heightmap normal
			var normal: Vector3 = heightmap.get_normal_world(world_x, world_z)
			var slope_val: float = 1.0 - normal.y  # 0=flat, 1=vertical
			_slope[idx] = int(clampf(slope_val * 255.0, 0.0, 255.0))

			# Determine terrain type from slope and elevation
			var ttype: int = _determine_terrain_type(h, slope_val, rng)
			_terrain_type[idx] = ttype

			# Set vegetation density based on terrain type
			var density: float = _estimate_vegetation_density(ttype)
			_vegetation_density[idx] = int(density * 255.0)

			# Default clearing stage is JUNGLE for vegetated areas
			if ttype in [TerrainType.LIGHT_JUNGLE, TerrainType.MEDIUM_JUNGLE, TerrainType.HEAVY_JUNGLE]:
				_clearing_stage[idx] = ClearingStage.JUNGLE
			else:
				# Non-jungle terrain starts "cleared"
				_clearing_stage[idx] = ClearingStage.CLEARED

			# Set passability
			var passable: int = PASSABLE_WALKABLE if TerrainTypesConst.is_passable(ttype) else 0
			# Buildable only if cleared
			if _clearing_stage[idx] >= ClearingStage.CLEARED:
				passable |= PASSABLE_BUILDABLE
			_passability[idx] = passable

	var elapsed: int = Time.get_ticks_msec() - start_time
	print("[TerrainGrid] Grid built in %dms" % elapsed)
	cell_updated.emit(Rect2i(0, 0, width, height))


## Determine terrain type from elevation and slope
func _determine_terrain_type(height_val: float, slope_val: float, rng: RandomNumberGenerator) -> int:
	# Cliff detection (steep slopes)
	if slope_val > CLIFF_SLOPE_THRESHOLD:
		return TerrainType.CLIFF

	# Very low = flooded
	if height_val < FLOODED_ELEVATION_MAX:
		return TerrainType.WATER

	# Low elevation near water level
	if height_val < WATER_ELEVATION_MAX:
		if slope_val < RICE_PADDY_SLOPE_MAX:
			return TerrainType.RICE_PADDY
		return TerrainType.WATER

	# Medium slopes = lighter vegetation
	if slope_val > LIGHT_JUNGLE_SLOPE_MIN:
		return TerrainType.LIGHT_JUNGLE

	# Based on elevation zones
	if height_val < MEDIUM_ELEVATION_THRESHOLD:
		return TerrainType.RICE_PADDY if rng.randf() < RICE_PADDY_RANDOM_CHANCE else TerrainType.GRASSLAND
	elif height_val < HEAVY_ELEVATION_THRESHOLD:
		return TerrainType.MEDIUM_JUNGLE
	elif height_val < HIGH_ELEVATION_THRESHOLD:
		return TerrainType.HEAVY_JUNGLE
	else:
		return TerrainType.LIGHT_JUNGLE  # High altitude = sparser


## Estimate vegetation density from terrain type
func _estimate_vegetation_density(ttype: int) -> float:
	match ttype:
		TerrainType.CLEAR: return 0.0
		TerrainType.RICE_PADDY: return 0.0
		TerrainType.GRASSLAND: return 0.1
		TerrainType.LIGHT_JUNGLE: return 0.35
		TerrainType.MEDIUM_JUNGLE: return 0.6
		TerrainType.HEAVY_JUNGLE: return 0.9
		_: return 0.0


# =============================================================================
# ELEVATION QUERIES
# =============================================================================

## Get elevation at world position (meters)
func get_elevation(world_pos: Vector3) -> float:
	var g := world_to_grid(world_pos)
	return _elevation[_grid_to_index(g.x, g.y)]


## Get elevation at grid coordinates
func get_elevation_at(gx: int, gz: int) -> float:
	if not _is_valid_coord(gx, gz):
		return 0.0
	return _elevation[_grid_to_index(gx, gz)]


## Get slope at world position (0=flat, 1=cliff)
func get_slope(world_pos: Vector3) -> float:
	var g := world_to_grid(world_pos)
	return float(_slope[_grid_to_index(g.x, g.y)]) / 255.0


## Get slope at grid coordinates
func get_slope_at(gx: int, gz: int) -> float:
	if not _is_valid_coord(gx, gz):
		return 0.0
	return float(_slope[_grid_to_index(gx, gz)]) / 255.0


## Get elevation difference between two positions (for height advantage)
func get_elevation_advantage(attacker_pos: Vector3, target_pos: Vector3) -> float:
	return get_elevation(attacker_pos) - get_elevation(target_pos)


# =============================================================================
# TERRAIN TYPE QUERIES
# =============================================================================

## Get terrain type at world position
func get_terrain_type(world_pos: Vector3) -> int:
	var g := world_to_grid(world_pos)
	return _terrain_type[_grid_to_index(g.x, g.y)]


## Get terrain type at grid coordinates
func get_terrain_type_at(gx: int, gz: int) -> int:
	if not _is_valid_coord(gx, gz):
		return TerrainType.CLIFF
	return _terrain_type[_grid_to_index(gx, gz)]


## Set terrain type at world position
## Also updates clearing_stage and passability to match the terrain type
func set_terrain_type(world_pos: Vector3, ttype: int) -> void:
	var g := world_to_grid(world_pos)
	var idx := _grid_to_index(g.x, g.y)
	_terrain_type[idx] = ttype

	# Update clearing stage based on terrain type
	# Jungle terrain starts as JUNGLE (0), non-jungle starts as CLEARED (2)
	if ttype in [TerrainType.LIGHT_JUNGLE, TerrainType.MEDIUM_JUNGLE, TerrainType.HEAVY_JUNGLE]:
		_clearing_stage[idx] = ClearingStage.JUNGLE
	else:
		_clearing_stage[idx] = ClearingStage.CLEARED

	# Update passability based on new terrain type and clearing stage
	var passable: int = PASSABLE_WALKABLE if TerrainTypesConst.is_passable(ttype) else 0
	# Buildable only if cleared
	if _clearing_stage[idx] >= ClearingStage.CLEARED:
		passable |= PASSABLE_BUILDABLE
	_passability[idx] = passable


# =============================================================================
# VEGETATION DENSITY QUERIES
# =============================================================================

## Get vegetation density at world position (0.0-1.0)
func get_vegetation_density(world_pos: Vector3) -> float:
	var g := world_to_grid(world_pos)
	return float(_vegetation_density[_grid_to_index(g.x, g.y)]) / 255.0


## Get vegetation density at grid coordinates
func get_vegetation_density_at(gx: int, gz: int) -> float:
	if not _is_valid_coord(gx, gz):
		return 0.0
	return float(_vegetation_density[_grid_to_index(gx, gz)]) / 255.0


## Set vegetation density at world position (0.0-1.0)
func set_vegetation_density(world_pos: Vector3, density: float) -> void:
	var g := world_to_grid(world_pos)
	var idx := _grid_to_index(g.x, g.y)
	_vegetation_density[idx] = int(clampf(density, 0.0, 1.0) * 255.0)

	# Update terrain type if density changed significantly
	_update_terrain_type_from_density(idx, density)


## Set vegetation density in an area
func set_vegetation_density_area(center: Vector3, radius: float, density: float) -> void:
	var g_center := world_to_grid(center)
	var g_radius: int = int(ceil(radius / CELL_SIZE))
	var density_byte: int = int(clampf(density, 0.0, 1.0) * 255.0)

	var min_x: int = maxi(0, g_center.x - g_radius)
	var max_x: int = mini(width, g_center.x + g_radius + 1)
	var min_z: int = maxi(0, g_center.y - g_radius)
	var max_z: int = mini(height, g_center.y + g_radius + 1)

	for gz in range(min_z, max_z):
		for gx in range(min_x, max_x):
			var dist: float = Vector2(gx - g_center.x, gz - g_center.y).length()
			if dist <= g_radius:
				var idx: int = _grid_to_index(gx, gz)
				_vegetation_density[idx] = density_byte
				_update_terrain_type_from_density(idx, density)

	cell_updated.emit(Rect2i(min_x, min_z, max_x - min_x, max_z - min_z))


## Update terrain type based on new vegetation density
func _update_terrain_type_from_density(idx: int, density: float) -> void:
	var current_type: int = _terrain_type[idx]

	# Don't change water/cliff/rice paddy
	if current_type in [TerrainType.WATER, TerrainType.CLIFF, TerrainType.RICE_PADDY]:
		return

	# Update terrain type based on density thresholds
	var new_type: int = current_type
	if density < 0.1:
		new_type = TerrainType.CLEAR
	elif density < 0.25:
		new_type = TerrainType.GRASSLAND
	elif density < 0.45:
		new_type = TerrainType.LIGHT_JUNGLE
	elif density < 0.7:
		new_type = TerrainType.MEDIUM_JUNGLE
	else:
		new_type = TerrainType.HEAVY_JUNGLE

	if new_type != current_type:
		_terrain_type[idx] = new_type
		# Update passability
		var passable: int = _passability[idx] & (~PASSABLE_WALKABLE)
		if TerrainTypesConst.is_passable(new_type):
			passable |= PASSABLE_WALKABLE
		_passability[idx] = passable


# =============================================================================
# CLEARING STAGE QUERIES
# =============================================================================

## Get clearing stage at world position
func get_clearing_stage(world_pos: Vector3) -> int:
	var g := world_to_grid(world_pos)
	return _clearing_stage[_grid_to_index(g.x, g.y)]


## Get clearing stage at grid coordinates
func get_clearing_stage_at(gx: int, gz: int) -> int:
	if not _is_valid_coord(gx, gz):
		return ClearingStage.JUNGLE
	return _clearing_stage[_grid_to_index(gx, gz)]


## Set clearing stage at world position
func set_clearing_stage(world_pos: Vector3, stage: int) -> void:
	var g := world_to_grid(world_pos)
	set_clearing_stage_at(g.x, g.y, stage)


## Set clearing stage at grid coordinates
func set_clearing_stage_at(gx: int, gz: int, stage: int, broadcast: bool = true) -> void:
	if not _is_valid_coord(gx, gz):
		return

	var idx: int = _grid_to_index(gx, gz)
	_clearing_stage[idx] = stage

	# Update vegetation density and terrain type based on stage
	var density: float = _get_density_for_stage(stage)
	_vegetation_density[idx] = int(density * 255.0)

	# Update terrain type if clearing
	if stage >= ClearingStage.CLEARED:
		_terrain_type[idx] = TerrainType.CLEAR

	# Update buildability based on clearing stage
	var passable: int = _passability[idx]
	if stage >= ClearingStage.CLEARED:
		passable |= PASSABLE_BUILDABLE
	else:
		passable &= ~PASSABLE_BUILDABLE
	_passability[idx] = passable

	# Only emit signal if requested (default true for single-cell updates)
	if broadcast:
		cell_updated.emit(Rect2i(gx, gz, 1, 1))


## Set clearing stage in an area (batched - emits ONE signal at end)
func set_clearing_stage_area(center: Vector3, radius: float, stage: int) -> void:
	var g_center := world_to_grid(center)
	var g_radius: int = int(ceil(radius / CELL_SIZE))

	var min_x: int = maxi(0, g_center.x - g_radius)
	var max_x: int = mini(width, g_center.x + g_radius + 1)
	var min_z: int = maxi(0, g_center.y - g_radius)
	var max_z: int = mini(height, g_center.y + g_radius + 1)

	for gz in range(min_z, max_z):
		for gx in range(min_x, max_x):
			var dist: float = Vector2(gx - g_center.x, gz - g_center.y).length()
			if dist <= g_radius:
				# Don't broadcast per-cell - we'll emit once at the end
				set_clearing_stage_at(gx, gz, stage, false)  # broadcast=false

	# Single signal emission for the entire area
	cell_updated.emit(Rect2i(min_x, min_z, max_x - min_x, max_z - min_z))


## Get vegetation density for clearing stage
func _get_density_for_stage(stage: int) -> float:
	match stage:
		ClearingStage.JUNGLE: return 1.0
		ClearingStage.PARTIALLY_CLEARED: return 0.25
		ClearingStage.CLEARED: return 0.05
		ClearingStage.FORTIFIED: return 0.0
		_: return 1.0


## Check if position is cleared (CLEARED or FORTIFIED)
func is_position_cleared(world_pos: Vector3) -> bool:
	return get_clearing_stage(world_pos) >= ClearingStage.CLEARED


## Mark area as cleared (convenience method for ClearingSystem)
func mark_area_cleared(center: Vector3, radius: float) -> void:
	set_clearing_stage_area(center, radius, ClearingStage.CLEARED)


# =============================================================================
# PASSABILITY QUERIES
# =============================================================================

## Check if position is walkable (ground units can traverse)
func is_passable(world_pos: Vector3) -> bool:
	var g := world_to_grid(world_pos)
	return (_passability[_grid_to_index(g.x, g.y)] & PASSABLE_WALKABLE) != 0


## Check if grid cell is walkable
func is_cell_passable(gx: int, gz: int) -> bool:
	if not _is_valid_coord(gx, gz):
		return false
	return (_passability[_grid_to_index(gx, gz)] & PASSABLE_WALKABLE) != 0


## Check if position is buildable
func is_buildable(world_pos: Vector3) -> bool:
	var g := world_to_grid(world_pos)
	return (_passability[_grid_to_index(g.x, g.y)] & PASSABLE_BUILDABLE) != 0


## Check if grid cell is buildable
func is_cell_buildable(gx: int, gz: int) -> bool:
	if not _is_valid_coord(gx, gz):
		return false
	return (_passability[_grid_to_index(gx, gz)] & PASSABLE_BUILDABLE) != 0


# =============================================================================
# MOVEMENT AND COMBAT
# =============================================================================

## Get movement cost multiplier at world position
func get_movement_cost(world_pos: Vector3) -> float:
	var ttype: int = get_terrain_type(world_pos)
	var base_cost: float = TerrainTypesConst.get_movement_cost(ttype)

	# Slope modifier (steeper = slower)
	var slope_val: float = get_slope(world_pos)
	var slope_penalty: float = 1.0 + slope_val * SLOPE_MOVEMENT_PENALTY

	return base_cost * slope_penalty


## Get movement speed multiplier at world position (inverse of cost)
func get_movement_speed(world_pos: Vector3) -> float:
	var cost: float = get_movement_cost(world_pos)
	if cost <= 0.0:
		return 0.0
	return 1.0 / cost


## Get cover value at world position (0.0-1.0)
func get_cover(world_pos: Vector3) -> float:
	var ttype: int = get_terrain_type(world_pos)
	return TerrainTypesConst.get_cover(ttype)


## Get defense bonus at world position (damage multiplier, lower = better)
func get_defense_bonus(world_pos: Vector3) -> float:
	var cover: float = get_cover(world_pos)
	return 1.0 - cover * 0.6  # Scale cover to defense


# =============================================================================
# LINE OF SIGHT
# =============================================================================

## Check if position blocks line of sight (dense vegetation or cliffs)
func blocks_los(world_pos: Vector3) -> bool:
	var g := world_to_grid(world_pos)
	var idx := _grid_to_index(g.x, g.y)
	var ttype: int = _terrain_type[idx]

	# Cliffs always block
	if ttype == TerrainType.CLIFF:
		return true

	# Heavy/medium jungle blocks based on density
	if ttype == TerrainType.HEAVY_JUNGLE:
		return _vegetation_density[idx] >= LOS_HEAVY_JUNGLE_DENSITY
	elif ttype == TerrainType.MEDIUM_JUNGLE:
		return _vegetation_density[idx] >= LOS_MEDIUM_JUNGLE_DENSITY

	return false


## Check line of sight between two positions (grid raycast)
func has_line_of_sight(from_pos: Vector3, to_pos: Vector3) -> bool:
	var from_grid := world_to_grid(from_pos)
	var to_grid := world_to_grid(to_pos)

	var from_h: float = get_elevation(from_pos) + 1.8  # Eye height
	var to_h: float = get_elevation(to_pos) + 1.0  # Target height

	# Bresenham-style raycast through grid
	var dx: int = absi(to_grid.x - from_grid.x)
	var dz: int = absi(to_grid.y - from_grid.y)
	var sx: int = 1 if from_grid.x < to_grid.x else -1
	var sz: int = 1 if from_grid.y < to_grid.y else -1
	var err: int = dx - dz

	var x: int = from_grid.x
	var z: int = from_grid.y
	var steps: int = dx + dz
	if steps == 0:
		return true

	for i in steps:
		# Check if terrain blocks LOS
		var t: float = float(i) / float(steps)
		var expected_h: float = lerpf(from_h, to_h, t)
		var cell_h: float = get_elevation_at(x, z)
		var cell_type: int = get_terrain_type_at(x, z)

		# Cliffs block LOS if higher than expected
		if cell_type == TerrainType.CLIFF:
			if cell_h > expected_h:
				return false
		elif cell_type == TerrainType.HEAVY_JUNGLE:
			var idx := _grid_to_index(x, z)
			if _vegetation_density[idx] >= LOS_HEAVY_JUNGLE_DENSITY:
				return false
		elif cell_type == TerrainType.MEDIUM_JUNGLE:
			var idx := _grid_to_index(x, z)
			if _vegetation_density[idx] >= LOS_MEDIUM_JUNGLE_DENSITY:
				return false

		# Step to next cell
		var e2: int = 2 * err
		if e2 > -dz:
			err -= dz
			x += sx
		if e2 < dx:
			err += dx
			z += sz

	return true


# =============================================================================
# REGION UPDATES
# =============================================================================

## Update a region from heightmap (called after terrain deformation)
func update_region_from_heightmap(region: Rect2i) -> void:
	if not _heightmap:
		return

	for gz in range(region.position.y, region.position.y + region.size.y):
		for gx in range(region.position.x, region.position.x + region.size.x):
			if not _is_valid_coord(gx, gz):
				continue

			var idx: int = _grid_to_index(gx, gz)
			var world_x: float = (gx + 0.5) * CELL_SIZE
			var world_z: float = (gz + 0.5) * CELL_SIZE

			# Re-sample elevation
			_elevation[idx] = _heightmap.sample_world(world_x, world_z)

			# Re-calculate slope
			var normal: Vector3 = _heightmap.get_normal_world(world_x, world_z)
			var slope_val: float = 1.0 - normal.y
			_slope[idx] = int(clampf(slope_val * 255.0, 0.0, 255.0))

	cell_updated.emit(region)


# =============================================================================
# DEBUG AND STATS
# =============================================================================

## Get terrain type name (for debug)
func get_terrain_name(ttype: int) -> String:
	return TerrainTypesConst.get_display_name(ttype)


## Print grid stats
func print_stats() -> void:
	var counts: Dictionary = {}
	for t in TerrainType.values():
		counts[t] = 0

	for i in _terrain_type.size():
		var t: int = _terrain_type[i]
		counts[t] = counts.get(t, 0) + 1

	print("[TerrainGrid] Terrain distribution:")
	for ttype: int in counts:
		var pct: float = 100.0 * counts[ttype] / _terrain_type.size()
		print("  %s: %d cells (%.1f%%)" % [get_terrain_name(ttype), counts[ttype], pct])

	var cleared_count := 0
	for stage in _clearing_stage:
		if stage >= ClearingStage.CLEARED:
			cleared_count += 1
	print("[TerrainGrid] Cleared cells: %d (%.1f%%)" % [
		cleared_count, 100.0 * cleared_count / _clearing_stage.size()
	])


## Get memory usage in bytes
func get_memory_usage() -> int:
	return _elevation.size() * 4 + _slope.size() + _terrain_type.size() + \
		   _vegetation_density.size() + _clearing_stage.size() + _passability.size()
