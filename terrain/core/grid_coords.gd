class_name GridCoords
extends RefCounted
## GridCoords - THE canonical coordinate system for all terrain grids
##
## All grid systems MUST use these constants and conversion methods.
## This ensures consistent coordinate handling across the entire codebase.
##
## Resolution hierarchy:
##   BASE (2m)     - HeightmapStorage, high-precision elevation
##   GAMEPLAY (4m) - TerrainGrid, terrain type/passability/clearing
##   SPATIAL (20m) - SpatialHashGrid, efficient unit queries

const GridResultClass = preload("res://terrain/core/grid_result.gd")

# =============================================================================
# RESOLUTION CONSTANTS - DO NOT CHANGE WITHOUT UPDATING ALL SYSTEMS
# =============================================================================

## Heightmap resolution - used for terrain mesh generation and precise elevation
const BASE_CELL_SIZE := 2.0

## Gameplay resolution - used for terrain type, clearing, passability, building
const GAMEPLAY_CELL_SIZE := 4.0

## Spatial query resolution - used for unit spatial hashing
const SPATIAL_CELL_SIZE := 20.0

## Building footprint resolution - aligns with heightmap for precise placement
const FOOTPRINT_CELL_SIZE := 2.0

# =============================================================================
# MAP BOUNDS - Set at initialization
# =============================================================================

static var map_size: float = 3000.0
static var _initialized: bool = false

## Cell counts for each resolution (computed at init)
static var base_cells: int = 0
static var gameplay_cells: int = 0
static var spatial_cells: int = 0


## Initialize the coordinate system with map size
static func init(size_meters: float) -> void:
	map_size = size_meters
	base_cells = int(ceil(map_size / BASE_CELL_SIZE))
	gameplay_cells = int(ceil(map_size / GAMEPLAY_CELL_SIZE))
	spatial_cells = int(ceil(map_size / SPATIAL_CELL_SIZE))
	_initialized = true
	print("[GridCoords] Initialized: %.0fm map, base=%d, gameplay=%d, spatial=%d cells" % [
		map_size, base_cells, gameplay_cells, spatial_cells
	])


## Check if GridCoords has been initialized
static func is_initialized() -> bool:
	return _initialized


# =============================================================================
# COORDINATE CONVERSION - Base Resolution (2m)
# =============================================================================

## Convert world position to base grid coordinates (2m resolution)
## Returns GridResult with validity status
static func world_to_base(world_pos: Vector3) -> GridResultClass:
	return _world_to_grid(world_pos, BASE_CELL_SIZE, base_cells)


## Convert base grid coordinates to world position (cell center)
static func base_to_world(grid_pos: Vector2i) -> Vector3:
	return Vector3(
		(grid_pos.x + 0.5) * BASE_CELL_SIZE,
		0.0,
		(grid_pos.y + 0.5) * BASE_CELL_SIZE
	)


# =============================================================================
# COORDINATE CONVERSION - Gameplay Resolution (4m)
# =============================================================================

## Convert world position to gameplay grid coordinates (4m resolution)
## Returns GridResult with validity status
static func world_to_gameplay(world_pos: Vector3) -> GridResultClass:
	return _world_to_grid(world_pos, GAMEPLAY_CELL_SIZE, gameplay_cells)


## Safe version that clamps and warns on out-of-bounds
static func world_to_gameplay_clamped(world_pos: Vector3) -> Vector2i:
	var result := world_to_gameplay(world_pos)
	if not result.valid:
		push_warning("[GridCoords] Out of bounds: %s -> clamped to %s" % [world_pos, result.coords])
	return result.coords


## Convert gameplay grid coordinates to world position (cell center)
static func gameplay_to_world(grid_pos: Vector2i) -> Vector3:
	return Vector3(
		(grid_pos.x + 0.5) * GAMEPLAY_CELL_SIZE,
		0.0,
		(grid_pos.y + 0.5) * GAMEPLAY_CELL_SIZE
	)


## Convert gameplay grid coordinates to world position (cell corner, not center)
static func gameplay_to_world_corner(grid_pos: Vector2i) -> Vector3:
	return Vector3(
		grid_pos.x * GAMEPLAY_CELL_SIZE,
		0.0,
		grid_pos.y * GAMEPLAY_CELL_SIZE
	)


# =============================================================================
# COORDINATE CONVERSION - Spatial Resolution (20m)
# =============================================================================

## Convert world position to spatial grid coordinates (20m resolution)
static func world_to_spatial(world_pos: Vector3) -> GridResultClass:
	return _world_to_grid(world_pos, SPATIAL_CELL_SIZE, spatial_cells)


## Convert spatial grid coordinates to world position (cell center)
static func spatial_to_world(grid_pos: Vector2i) -> Vector3:
	return Vector3(
		(grid_pos.x + 0.5) * SPATIAL_CELL_SIZE,
		0.0,
		(grid_pos.y + 0.5) * SPATIAL_CELL_SIZE
	)


# =============================================================================
# BOUNDS CHECKING
# =============================================================================

## Check if world position is within map bounds
static func is_in_bounds(world_pos: Vector3) -> bool:
	return world_pos.x >= 0.0 and world_pos.x < map_size and \
		   world_pos.z >= 0.0 and world_pos.z < map_size


## Clamp world position to valid bounds
static func clamp_to_bounds(world_pos: Vector3) -> Vector3:
	return Vector3(
		clampf(world_pos.x, 0.0, map_size - 0.01),
		world_pos.y,
		clampf(world_pos.z, 0.0, map_size - 0.01)
	)


## Check if grid coordinates are valid at given resolution
static func is_valid_cell(gx: int, gz: int, max_cells: int) -> bool:
	return gx >= 0 and gx < max_cells and gz >= 0 and gz < max_cells


## Check if gameplay grid coordinates are valid
static func is_valid_gameplay_cell(gx: int, gz: int) -> bool:
	return is_valid_cell(gx, gz, gameplay_cells)


# =============================================================================
# RECT CONVERSION
# =============================================================================

## Convert world AABB to gameplay grid rect
static func aabb_to_gameplay_rect(bounds: AABB) -> Rect2i:
	var min_result := world_to_gameplay(bounds.position)
	var max_result := world_to_gameplay(bounds.position + bounds.size)
	var min_cell := min_result.coords
	var max_cell := max_result.coords
	return Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)


## Convert gameplay grid rect to world AABB
static func gameplay_rect_to_aabb(rect: Rect2i) -> AABB:
	var min_world := Vector3(rect.position.x * GAMEPLAY_CELL_SIZE, 0.0,
							 rect.position.y * GAMEPLAY_CELL_SIZE)
	var size_world := Vector3(rect.size.x * GAMEPLAY_CELL_SIZE, 0.0,
							  rect.size.y * GAMEPLAY_CELL_SIZE)
	return AABB(min_world, size_world)


## Convert cell index to grid coordinates
static func index_to_gameplay(index: int) -> Vector2i:
	return Vector2i(index % gameplay_cells, index / gameplay_cells)


## Convert grid coordinates to cell index
static func gameplay_to_index(gx: int, gz: int) -> int:
	return gz * gameplay_cells + gx


# =============================================================================
# INTERNAL
# =============================================================================

static func _world_to_grid(world_pos: Vector3, cell_size: float, max_cells: int) -> GridResultClass:
	var gx := int(floor(world_pos.x / cell_size))
	var gz := int(floor(world_pos.z / cell_size))

	# Clamp for result coords (always provide usable coords)
	var clamped_x := clampi(gx, 0, max_cells - 1)
	var clamped_z := clampi(gz, 0, max_cells - 1)

	if gx < 0 or gx >= max_cells or gz < 0 or gz >= max_cells:
		return GridResultClass.err(
			"Coordinates (%d, %d) out of bounds [0, %d)" % [gx, gz, max_cells],
			Vector2i(clamped_x, clamped_z)
		)

	return GridResultClass.ok(Vector2i(gx, gz))
