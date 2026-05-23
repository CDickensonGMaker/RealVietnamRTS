class_name UnifiedTerrainEngine
extends Node
## UnifiedTerrainEngine - THE single source of truth for all terrain data.
##
## Key differences from old system:
##   1. grid_to_world() returns ACTUAL Y values (samples heightmap)
##   2. modify_terrain() syncs BOTH heightmap AND gameplay grid
##   3. Vegetation clearing emits signals with instance info for actual removal
##
## Merges functionality from:
##   - HeightmapStorage (2m resolution for mesh generation)
##   - TerrainGrid (4m resolution for gameplay queries)
##   - Vegetation instance tracking

const HeightmapStorageClass = preload("res://terrain/core/heightmap_storage.gd")
const TerrainTypesConst = preload("res://terrain/terrain_types.gd")
const ClearingStateClass = preload("res://terrain/clearing_state.gd")
const GridCoordsClass = preload("res://terrain/core/grid_coords.gd")

## Signals
signal terrain_modified(region: Rect2i)
signal terrain_ready
signal vegetation_changed(region: Rect2i)

## Type aliases
const TerrainType = TerrainTypesConst.Type
const ClearingStage = ClearingStateClass.Stage

## Resolution constants - matches GridCoords
const CELL_SIZE := GridCoordsClass.GAMEPLAY_CELL_SIZE  # 4m gameplay cells
const HEIGHTMAP_RESOLUTION := GridCoordsClass.BASE_CELL_SIZE  # 2m heightmap

## Passability flags
const PASSABLE_WALKABLE := 1
const PASSABLE_BUILDABLE := 2

## Grid dimensions
var width: int = 0
var height: int = 0
var map_size: float = 0.0

## High-resolution heightmap for mesh generation and precise height queries
var _heightmap: HeightmapStorageClass

## Gameplay grid arrays (4m cells) - cached from heightmap for fast queries
var _elevation: PackedFloat32Array
var _slope: PackedByteArray
var _terrain_type: PackedByteArray
var _vegetation_density: PackedByteArray
var _clearing_stage: PackedByteArray
var _passability: PackedByteArray
var _occupancy: PackedInt32Array

## State
var _is_initialized: bool = false

## Terrain classification thresholds
const CLIFF_SLOPE_THRESHOLD := 0.7
const WATER_ELEVATION_MAX := 5.0
const FLOODED_ELEVATION_MAX := 2.0
const RICE_PADDY_SLOPE_MAX := 0.1
const LIGHT_JUNGLE_SLOPE_MIN := 0.4
const MEDIUM_ELEVATION_THRESHOLD := 50.0
const HEAVY_ELEVATION_THRESHOLD := 150.0
const HIGH_ELEVATION_THRESHOLD := 250.0
const RICE_PADDY_RANDOM_CHANCE := 0.3


func _init(map_size_meters: float = 3000.0) -> void:
	map_size = map_size_meters
	width = int(ceil(map_size / CELL_SIZE))
	height = width  # Square grid

	var total_cells: int = width * height

	# Initialize gameplay grid arrays
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
	_vegetation_density.fill(128)
	_clearing_stage.fill(ClearingStage.JUNGLE)
	_passability.fill(PASSABLE_WALKABLE)
	_occupancy.fill(0)

	# Create heightmap storage
	_heightmap = HeightmapStorageClass.new(map_size_meters, HEIGHTMAP_RESOLUTION)

	# Initialize GridCoords
	GridCoordsClass.init(map_size)

	print("[UnifiedTerrainEngine] Created %dx%d grid (%.0fm map)" % [width, height, map_size])


## =============================================================================
## INITIALIZATION
## =============================================================================

## Initialize from external heightmap (for compatibility with existing terrain generation)
func init_from_heightmap(heightmap: HeightmapStorageClass) -> void:
	_heightmap = heightmap
	_build_gameplay_grid_from_heightmap()
	_is_initialized = true
	terrain_ready.emit()
	print("[UnifiedTerrainEngine] Initialized from heightmap (%d x %d cells)" % [width, height])


## Build gameplay grid by sampling heightmap
func _build_gameplay_grid_from_heightmap() -> void:
	if not _heightmap:
		push_warning("[UnifiedTerrainEngine] No heightmap to build from")
		return

	print("[UnifiedTerrainEngine] Building gameplay grid from heightmap...")
	var start_time := Time.get_ticks_msec()

	# Seeded RNG for deterministic terrain type assignment
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	for gz in height:
		for gx in width:
			var idx: int = _grid_to_index(gx, gz)

			# Get world position for this cell center
			var world_x: float = (gx + 0.5) * CELL_SIZE
			var world_z: float = (gz + 0.5) * CELL_SIZE

			# Sample elevation from heightmap (THE KEY FIX - cached for fast queries)
			var h: float = _heightmap.sample_world(world_x, world_z)
			_elevation[idx] = h

			# Calculate slope from heightmap normal
			var normal: Vector3 = _heightmap.get_normal_world(world_x, world_z)
			var slope_val: float = 1.0 - normal.y  # 0=flat, 1=vertical
			_slope[idx] = int(clampf(slope_val * 255.0, 0.0, 255.0))

			# Determine terrain type
			var ttype: int = _determine_terrain_type(h, slope_val, rng)
			_terrain_type[idx] = ttype

			# Set vegetation density based on terrain type
			var density: float = _estimate_vegetation_density(ttype)
			_vegetation_density[idx] = int(density * 255.0)

			# Default clearing stage
			if ttype in [TerrainType.LIGHT_JUNGLE, TerrainType.MEDIUM_JUNGLE, TerrainType.HEAVY_JUNGLE]:
				_clearing_stage[idx] = ClearingStage.JUNGLE
			else:
				_clearing_stage[idx] = ClearingStage.CLEARED

			# Set passability
			var passable: int = PASSABLE_WALKABLE if TerrainTypesConst.is_passable(ttype) else 0
			if _clearing_stage[idx] >= ClearingStage.CLEARED:
				passable |= PASSABLE_BUILDABLE
			_passability[idx] = passable

	var elapsed: int = Time.get_ticks_msec() - start_time
	print("[UnifiedTerrainEngine] Grid built in %dms" % elapsed)


## Determine terrain type from elevation and slope
func _determine_terrain_type(height_val: float, slope_val: float, rng: RandomNumberGenerator) -> int:
	if slope_val > CLIFF_SLOPE_THRESHOLD:
		return TerrainType.CLIFF

	if height_val < FLOODED_ELEVATION_MAX:
		return TerrainType.WATER

	if height_val < WATER_ELEVATION_MAX:
		if slope_val < RICE_PADDY_SLOPE_MAX:
			return TerrainType.RICE_PADDY
		return TerrainType.WATER

	if slope_val > LIGHT_JUNGLE_SLOPE_MIN:
		return TerrainType.LIGHT_JUNGLE

	if height_val < MEDIUM_ELEVATION_THRESHOLD:
		return TerrainType.RICE_PADDY if rng.randf() < RICE_PADDY_RANDOM_CHANCE else TerrainType.GRASSLAND
	elif height_val < HEAVY_ELEVATION_THRESHOLD:
		return TerrainType.MEDIUM_JUNGLE
	elif height_val < HIGH_ELEVATION_THRESHOLD:
		return TerrainType.HEAVY_JUNGLE
	else:
		return TerrainType.LIGHT_JUNGLE


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


## =============================================================================
## COORDINATE CONVERSION - THE KEY FIX: grid_to_world returns actual Y
## =============================================================================

## Convert world position to grid coordinates
func world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		clampi(int(world_pos.x / CELL_SIZE), 0, width - 1),
		clampi(int(world_pos.z / CELL_SIZE), 0, height - 1)
	)


## Convert grid coordinates to world position WITH ACTUAL ELEVATION
## This is THE key difference from old TerrainGrid - Y is real, not zero!
func grid_to_world(grid_pos: Vector2i) -> Vector3:
	var world_x: float = (grid_pos.x + 0.5) * CELL_SIZE
	var world_z: float = (grid_pos.y + 0.5) * CELL_SIZE
	var world_y: float = get_height_at(Vector3(world_x, 0, world_z))
	return Vector3(world_x, world_y, world_z)


## Convert grid coordinates to world position (cell corner, not center)
func grid_to_world_corner(grid_pos: Vector2i) -> Vector3:
	var world_x: float = grid_pos.x * CELL_SIZE
	var world_z: float = grid_pos.y * CELL_SIZE
	var world_y: float = get_height_at(Vector3(world_x, 0, world_z))
	return Vector3(world_x, world_y, world_z)


## Get cell index from grid coordinates
func _grid_to_index(gx: int, gz: int) -> int:
	return gz * width + gx


## Check if grid coordinates are valid
func _is_valid_coord(gx: int, gz: int) -> bool:
	return gx >= 0 and gx < width and gz >= 0 and gz < height


## =============================================================================
## HEIGHT QUERIES - Always from heightmap for precision
## =============================================================================

## Get height at world position (bilinear interpolated from heightmap)
func get_height_at(world_pos: Vector3) -> float:
	if not _heightmap:
		return 0.0
	return _heightmap.sample_world(world_pos.x, world_pos.z)


## Get normal at world position
func get_normal_at(world_pos: Vector3) -> Vector3:
	if not _heightmap:
		return Vector3.UP
	return _heightmap.get_normal_world(world_pos.x, world_pos.z)


## Get cached elevation at grid cell (faster but less precise than get_height_at)
func get_elevation_at(gx: int, gz: int) -> float:
	if not _is_valid_coord(gx, gz):
		return 0.0
	return _elevation[_grid_to_index(gx, gz)]


## Get slope at world position (0=flat, 1=cliff)
func get_slope(world_pos: Vector3) -> float:
	var g := world_to_grid(world_pos)
	return float(_slope[_grid_to_index(g.x, g.y)]) / 255.0


## Get elevation advantage (height difference for combat)
func get_elevation_advantage(attacker_pos: Vector3, target_pos: Vector3) -> float:
	return get_height_at(attacker_pos) - get_height_at(target_pos)


## =============================================================================
## TERRAIN MODIFICATION - Syncs BOTH heightmap AND gameplay grid
## =============================================================================

## Modify heightmap AND sync gameplay grid in one atomic operation
## modifier: Callable(current_height: float, falloff: float) -> float
func modify_terrain(center: Vector3, radius: float, modifier: Callable) -> Rect2i:
	if not _heightmap:
		return Rect2i()

	# 1. Modify heightmap
	var cell_center := _heightmap.world_to_cell(center.x, center.z)
	var radius_cells := int(radius / HEIGHTMAP_RESOLUTION)
	var heightmap_region := _heightmap.modify_region(cell_center, radius_cells, modifier)

	# 2. Calculate affected gameplay cells
	var gameplay_region := _heightmap_region_to_gameplay(heightmap_region)

	# 3. Resync gameplay grid from modified heightmap
	_resync_gameplay_region(gameplay_region)

	# 4. Emit signal for mesh rebuilds and job notifications
	terrain_modified.emit(gameplay_region)

	return gameplay_region


## Flatten terrain to target height
func flatten_area(center: Vector3, size: Vector2, target_height: float = -1.0) -> Rect2i:
	var actual_target := target_height
	if actual_target < 0:
		actual_target = get_height_at(center)

	var half := size * 0.5
	var normalized_target := actual_target / _heightmap.height_scale

	var modifier := func(h: float, falloff: float) -> float:
		return lerpf(h, normalized_target, falloff)

	var radius := maxf(half.x, half.y)
	return modify_terrain(center, radius, modifier)


## Create crater (deform terrain)
func create_crater(center: Vector3, radius: float, depth: float, rim_height: float = 0.0) -> Rect2i:
	var normalized_depth := depth / _heightmap.height_scale
	var normalized_rim := rim_height / _heightmap.height_scale

	var modifier := func(h: float, falloff: float) -> float:
		# Smooth crater profile: continuous depression + rim curves (no hard boundaries)
		# Depression curve: peaks at center (high falloff), fades toward edges
		var depression: float = normalized_depth * smoothstep(0.4, 0.95, falloff)

		# Rim curve: ring around crater, fades at both inner and outer edges
		var rim_dist: float = 1.0 - falloff
		var rim_factor: float = smoothstep(0.4, 0.65, rim_dist) * smoothstep(0.95, 0.75, rim_dist)
		var rim: float = normalized_rim * rim_factor

		return h - depression + rim

	return modify_terrain(center, radius, modifier)


## Resync gameplay grid region from heightmap
func _resync_gameplay_region(region: Rect2i) -> void:
	for gz in range(region.position.y, region.end.y):
		for gx in range(region.position.x, region.end.x):
			if not _is_valid_coord(gx, gz):
				continue

			var idx := _grid_to_index(gx, gz)
			var world_x := (gx + 0.5) * CELL_SIZE
			var world_z := (gz + 0.5) * CELL_SIZE

			# Resample elevation from heightmap
			_elevation[idx] = _heightmap.sample_world(world_x, world_z)

			# Recalculate slope
			var normal := _heightmap.get_normal_world(world_x, world_z)
			_slope[idx] = int(clampf((1.0 - normal.y) * 255.0, 0.0, 255.0))


## Convert heightmap region to gameplay grid region
func _heightmap_region_to_gameplay(heightmap_rect: Rect2i) -> Rect2i:
	var scale := int(CELL_SIZE / HEIGHTMAP_RESOLUTION)
	return Rect2i(
		heightmap_rect.position.x / scale,
		heightmap_rect.position.y / scale,
		ceili(float(heightmap_rect.size.x) / scale),
		ceili(float(heightmap_rect.size.y) / scale)
	)


## =============================================================================
## VEGETATION & CLEARING
## =============================================================================

## Get vegetation density at world position (0.0-1.0)
func get_vegetation_density(world_pos: Vector3) -> float:
	var g := world_to_grid(world_pos)
	return float(_vegetation_density[_grid_to_index(g.x, g.y)]) / 255.0


## Get clearing stage at world position
func get_clearing_stage(world_pos: Vector3) -> int:
	var g := world_to_grid(world_pos)
	return _clearing_stage[_grid_to_index(g.x, g.y)]


## Set clearing stage for an area (marks vegetation for removal)
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
				_set_clearing_stage_at(gx, gz, stage)

	# Emit signal for vegetation manager to update visuals
	var region := Rect2i(min_x, min_z, max_x - min_x, max_z - min_z)
	vegetation_changed.emit(region)


## Set clearing stage at grid coordinates
func _set_clearing_stage_at(gx: int, gz: int, stage: int) -> void:
	if not _is_valid_coord(gx, gz):
		return

	var idx := _grid_to_index(gx, gz)
	_clearing_stage[idx] = stage

	# Update vegetation density based on stage
	var density: float = _get_density_for_stage(stage)
	_vegetation_density[idx] = int(density * 255.0)

	# Update terrain type if clearing
	if stage >= ClearingStage.CLEARED:
		_terrain_type[idx] = TerrainType.CLEAR

	# Update buildability
	var passable: int = _passability[idx]
	if stage >= ClearingStage.CLEARED:
		passable |= PASSABLE_BUILDABLE
	else:
		passable &= ~PASSABLE_BUILDABLE
	_passability[idx] = passable


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


## =============================================================================
## TERRAIN TYPE QUERIES
## =============================================================================

## Get terrain type at world position
func get_terrain_type(world_pos: Vector3) -> int:
	var g := world_to_grid(world_pos)
	return _terrain_type[_grid_to_index(g.x, g.y)]


## Get terrain type at grid coordinates
func get_terrain_type_at(gx: int, gz: int) -> int:
	if not _is_valid_coord(gx, gz):
		return TerrainType.CLIFF
	return _terrain_type[_grid_to_index(gx, gz)]


## =============================================================================
## PASSABILITY & MOVEMENT
## =============================================================================

## Check if position is passable by ground units
func is_passable(world_pos: Vector3) -> bool:
	var g := world_to_grid(world_pos)
	return (_passability[_grid_to_index(g.x, g.y)] & PASSABLE_WALKABLE) != 0


## Check if position is buildable
func is_buildable(world_pos: Vector3) -> bool:
	var g := world_to_grid(world_pos)
	return (_passability[_grid_to_index(g.x, g.y)] & PASSABLE_BUILDABLE) != 0


## Get movement cost multiplier at world position
func get_movement_cost(world_pos: Vector3) -> float:
	var ttype: int = get_terrain_type(world_pos)
	var base_cost: float = TerrainTypesConst.get_movement_cost(ttype)

	# Slope modifier (reduced from 0.5 for smoother movement)
	var slope_val: float = get_slope(world_pos)
	var slope_penalty: float = 1.0 + slope_val * 0.25

	return base_cost * slope_penalty


## Get movement speed multiplier (inverse of cost)
func get_movement_speed(world_pos: Vector3) -> float:
	var cost: float = get_movement_cost(world_pos)
	if cost <= 0.0:
		return 0.0
	return 1.0 / cost


## Get cover value at world position (0.0-1.0)
func get_cover(world_pos: Vector3) -> float:
	var ttype: int = get_terrain_type(world_pos)
	return TerrainTypesConst.get_cover(ttype)


## =============================================================================
## LINE OF SIGHT
## =============================================================================

## Check if position blocks line of sight
func blocks_los(world_pos: Vector3) -> bool:
	var g := world_to_grid(world_pos)
	var idx := _grid_to_index(g.x, g.y)
	var ttype: int = _terrain_type[idx]

	if ttype == TerrainType.CLIFF:
		return true

	if ttype == TerrainType.HEAVY_JUNGLE:
		return _vegetation_density[idx] >= 205  # 0.8 * 255
	elif ttype == TerrainType.MEDIUM_JUNGLE:
		return _vegetation_density[idx] >= 230  # 0.9 * 255

	return false


## Check line of sight between two positions
func has_line_of_sight(from_pos: Vector3, to_pos: Vector3) -> bool:
	var from_grid := world_to_grid(from_pos)
	var to_grid := world_to_grid(to_pos)

	var from_h: float = get_height_at(from_pos) + 1.8  # Eye height
	var to_h: float = get_height_at(to_pos) + 1.0  # Target height

	# Bresenham-style raycast
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
		var t: float = float(i) / float(steps)
		var expected_h: float = lerpf(from_h, to_h, t)
		var cell_h: float = get_elevation_at(x, z)
		var cell_type: int = get_terrain_type_at(x, z)

		if cell_type == TerrainType.CLIFF:
			if cell_h > expected_h:
				return false
		elif cell_type == TerrainType.HEAVY_JUNGLE:
			var idx := _grid_to_index(x, z)
			if _vegetation_density[idx] >= 205:
				return false
		elif cell_type == TerrainType.MEDIUM_JUNGLE:
			var idx := _grid_to_index(x, z)
			if _vegetation_density[idx] >= 230:
				return false

		var e2: int = 2 * err
		if e2 > -dz:
			err -= dz
			x += sx
		if e2 < dx:
			err += dx
			z += sz

	return true


## =============================================================================
## OCCUPANCY (Building tracking)
## =============================================================================

## Check if cell is occupied by a building
func is_occupied_at(gx: int, gz: int) -> bool:
	if not _is_valid_coord(gx, gz):
		return true
	return _occupancy[_grid_to_index(gx, gz)] != 0


## Get building ID at cell (0 = unoccupied)
func get_occupancy_at(gx: int, gz: int) -> int:
	if not _is_valid_coord(gx, gz):
		return -1
	return _occupancy[_grid_to_index(gx, gz)]


## Set cell as occupied
func set_occupied(gx: int, gz: int, building_id: int) -> void:
	if _is_valid_coord(gx, gz):
		_occupancy[_grid_to_index(gx, gz)] = building_id


## Clear cell occupancy
func clear_occupancy(gx: int, gz: int) -> void:
	if _is_valid_coord(gx, gz):
		_occupancy[_grid_to_index(gx, gz)] = 0


## =============================================================================
## FOOTPRINT VALIDATION (for building placement)
## =============================================================================

## Get all cells covered by a rectangular footprint
func get_footprint_cells(center: Vector3, size: Vector2) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []

	var half_size := size * 0.5
	var min_world := Vector3(center.x - half_size.x, 0, center.z - half_size.y)
	var max_world := Vector3(center.x + half_size.x, 0, center.z + half_size.y)

	var min_cell := world_to_grid(min_world)
	var max_cell := world_to_grid(max_world)

	for z in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			if _is_valid_coord(x, z):
				cells.append(Vector2i(x, z))

	return cells


## Validate building footprint for placement
func validate_footprint(center: Vector3, size: Vector2) -> Dictionary:
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

	result["cells"] = get_footprint_cells(center, size)

	if result["cells"].is_empty():
		result["warnings"].append("Footprint outside map bounds")
		return result

	var elevations: Array[float] = []

	for cell: Vector2i in result["cells"]:
		var idx := _grid_to_index(cell.x, cell.y)

		var ttype: int = _terrain_type[idx]
		if ttype == TerrainType.WATER:
			result["blocking_cells"][cell] = "Water"
			continue
		if ttype == TerrainType.CLIFF:
			result["blocking_cells"][cell] = "Cliff"
			continue

		var slope: float = float(_slope[idx]) / 255.0
		if slope > 0.3:
			result["blocking_cells"][cell] = "Too steep (%.0f%%)" % (slope * 100)
			continue
		result["max_slope"] = maxf(result["max_slope"], slope)

		var clearing: int = _clearing_stage[idx]
		if clearing < ClearingStage.CLEARED:
			result["required_clearing"].append(cell)

		if _occupancy[idx] != 0:
			result["blocking_cells"][cell] = "Occupied"
			continue

		elevations.append(_elevation[idx])

	if not elevations.is_empty():
		var total: float = 0.0
		result["min_elevation"] = elevations[0]
		result["max_elevation"] = elevations[0]
		for h: float in elevations:
			total += h
			result["min_elevation"] = minf(result["min_elevation"], h)
			result["max_elevation"] = maxf(result["max_elevation"], h)
		result["average_elevation"] = total / elevations.size()

		var variance: float = result["max_elevation"] - result["min_elevation"]
		if variance > 2.0:
			result["warnings"].append("Uneven terrain (%.1fm variance)" % variance)

	result["valid"] = result["blocking_cells"].is_empty()
	return result


## =============================================================================
## ACCESSORS
## =============================================================================

## Get heightmap reference (for compatibility)
func get_heightmap() -> HeightmapStorageClass:
	return _heightmap


## Check if initialized
func is_ready() -> bool:
	return _is_initialized


## Get map size in meters
func get_map_size() -> float:
	return map_size


## =============================================================================
## DEBUG
## =============================================================================

## Print terrain stats
func print_stats() -> void:
	var counts: Dictionary = {}
	for t in TerrainType.values():
		counts[t] = 0

	for i in _terrain_type.size():
		var t: int = _terrain_type[i]
		counts[t] = counts.get(t, 0) + 1

	print("[UnifiedTerrainEngine] Terrain distribution:")
	for ttype: int in counts:
		var pct: float = 100.0 * counts[ttype] / _terrain_type.size()
		print("  %s: %d cells (%.1f%%)" % [TerrainTypesConst.get_display_name(ttype), counts[ttype], pct])

	var cleared_count := 0
	for stage in _clearing_stage:
		if stage >= ClearingStage.CLEARED:
			cleared_count += 1
	print("[UnifiedTerrainEngine] Cleared cells: %d (%.1f%%)" % [
		cleared_count, 100.0 * cleared_count / _clearing_stage.size()
	])
