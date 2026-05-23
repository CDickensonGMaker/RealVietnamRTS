extends Node
## Clearing System - Jungle clearing with progressive stages
## Handles vegetation removal and terrain flattening for firebase construction
##
## Uses ClearingState.Stage enum (terrain/clearing_state.gd) as single source of truth
## Writes clearing data to TerrainGrid (SINGLE SOURCE OF TRUTH)

const ClearingStateClass = preload("res://terrain/clearing_state.gd")

signal clearing_started(zone_id: int, position: Vector3)
signal clearing_progress(zone_id: int, progress: float)
signal clearing_completed(zone_id: int)
signal vegetation_updated(region: Rect2i)

## Alias for backward compatibility - use ClearingState.Stage directly in new code
const ClearingStage = ClearingStateClass.Stage

# Clearing zone data
class ClearingZone:
	var id: int
	var center: Vector3
	var radius: float
	var stage: ClearingStage = ClearingStage.JUNGLE
	var progress: float = 0.0  # 0-1 within current stage
	var shape: String = "circle"  # "circle" or "rectangle"
	var rect_size: Vector2 = Vector2.ZERO  # For rectangular zones

# Stage visual parameters
const STAGE_PARAMS: Dictionary = {
	ClearingStage.JUNGLE: {
		"vegetation_density": 1.0,
		"height_flattening": 0.0,
		"ground_color": Color(0.12, 0.28, 0.08),  # Dense jungle green
		"tree_scale": 1.0,
	},
	ClearingStage.PARTIALLY_CLEARED: {
		"vegetation_density": 0.25,
		"height_flattening": 0.2,
		"ground_color": Color(0.3, 0.25, 0.15),  # Muddy brown-green
		"tree_scale": 0.3,  # Stumps only
	},
	ClearingStage.CLEARED: {
		"vegetation_density": 0.05,
		"height_flattening": 0.7,
		"ground_color": Color(0.45, 0.38, 0.28),  # Exposed dirt
		"tree_scale": 0.0,
	},
	ClearingStage.FORTIFIED: {
		"vegetation_density": 0.0,
		"height_flattening": 1.0,
		"ground_color": Color(0.52, 0.45, 0.35),  # Packed earth
		"tree_scale": 0.0,
	},
}

# Active clearing zones
var zones: Dictionary = {}  # id -> ClearingZone
var next_zone_id: int = 0

# Reference to TerrainGrid (SINGLE SOURCE OF TRUTH)
var terrain_grid: RefCounted

# Reference to terrain manager (for terrain modification)
var terrain_manager: Node

# Reference to vegetation manager (for visual updates)
var vegetation_manager: Node


func _ready() -> void:
	pass


## Set terrain manager reference (called by terrain_lab)
func set_terrain_manager(manager: Node) -> void:
	terrain_manager = manager


## Set vegetation manager reference (for terrain type density lookups)
func set_vegetation_manager(veg_mgr: Node) -> void:
	vegetation_manager = veg_mgr


## Set terrain grid reference (SINGLE SOURCE OF TRUTH)
func set_terrain_grid(grid: RefCounted) -> void:
	terrain_grid = grid


## Create a new clearing zone
func create_zone(center: Vector3, radius: float, shape: String = "circle", rect_size: Vector2 = Vector2.ZERO) -> int:
	var zone := ClearingZone.new()
	zone.id = next_zone_id
	zone.center = center
	zone.radius = radius
	zone.shape = shape
	zone.rect_size = rect_size if shape == "rectangle" else Vector2.ZERO

	zones[zone.id] = zone
	next_zone_id += 1

	clearing_started.emit(zone.id, center)
	return zone.id


## Advance clearing progress
func advance_clearing(zone_id: int, amount: float) -> void:
	if not zones.has(zone_id):
		return

	var zone: ClearingZone = zones[zone_id]
	zone.progress += amount

	# Check for stage advancement
	if zone.progress >= 1.0:
		zone.progress = 0.0
		if zone.stage < ClearingStage.FORTIFIED:
			zone.stage = zone.stage + 1 as ClearingStage
			_apply_stage_changes(zone)

			if zone.stage == ClearingStage.FORTIFIED:
				clearing_completed.emit(zone_id)
		else:
			zone.progress = 1.0

	clearing_progress.emit(zone_id, _get_total_progress(zone))
	_update_terrain_grid(zone)


## Set zone directly to a stage (for testing)
func set_zone_stage(zone_id: int, stage: ClearingStage) -> void:
	if not zones.has(zone_id):
		return

	var zone: ClearingZone = zones[zone_id]
	zone.stage = stage
	zone.progress = 0.0

	_apply_stage_changes(zone)
	_update_terrain_grid(zone)


## Apply terrain modifications for current stage
func _apply_stage_changes(zone: ClearingZone) -> void:
	if not terrain_manager:
		push_warning("ClearingSystem: TerrainManager not set")
		return

	var params: Dictionary = STAGE_PARAMS[zone.stage]
	var flattening: float = params.height_flattening

	if flattening <= 0.0:
		return

	# Calculate target height (average of zone)
	var cell_size: float = terrain_manager.cell_size
	var heightmap = terrain_manager.heightmap
	var center := Vector2i(
		int(zone.center.x / cell_size),
		int(zone.center.z / cell_size)
	)
	var radius_cells: int = int(zone.radius / cell_size)

	# Find average height in zone
	var total_height: float = 0.0
	var count: int = 0

	for y in range(max(0, center.y - radius_cells), min(heightmap.size, center.y + radius_cells)):
		for x in range(max(0, center.x - radius_cells), min(heightmap.size, center.x + radius_cells)):
			if _is_in_zone(zone, x, y, center, radius_cells):
				total_height += heightmap.get_cell(x, y)
				count += 1

	if count == 0:
		return

	var target_height: float = total_height / float(count)

	# Apply flattening via terrain_manager (this also rebuilds chunks)
	var flatten_func := func(current_height: float, falloff_amount: float) -> float:
		var blend: float = flattening * falloff_amount
		return lerp(current_height, target_height, blend)

	terrain_manager.modify_terrain(zone.center, zone.radius, flatten_func)


## Check if heightmap cell is within zone
func _is_in_zone(zone: ClearingZone, x: int, y: int, center: Vector2i, radius_cells: int) -> bool:
	if zone.shape == "rectangle" and terrain_manager:
		var half_w: int = int(zone.rect_size.x / (terrain_manager.cell_size * 2))
		var half_h: int = int(zone.rect_size.y / (terrain_manager.cell_size * 2))
		return abs(x - center.x) <= half_w and abs(y - center.y) <= half_h
	else:
		var dist: float = Vector2(x - center.x, y - center.y).length()
		return dist <= radius_cells


## Update TerrainGrid with zone's clearing state (SINGLE SOURCE OF TRUTH)
func _update_terrain_grid(zone: ClearingZone) -> void:
	if not terrain_grid:
		return

	# Write clearing stage to TerrainGrid for the zone area
	if zone.shape == "rectangle":
		_update_terrain_grid_rect(zone)
	else:
		_update_terrain_grid_circle(zone)


## Update TerrainGrid for circular zone
func _update_terrain_grid_circle(zone: ClearingZone) -> void:
	terrain_grid.set_clearing_stage_area(zone.center, zone.radius, zone.stage)


## Update TerrainGrid for rectangular zone
func _update_terrain_grid_rect(zone: ClearingZone) -> void:
	# For rectangles, iterate through all cells in the rectangle
	var half_w: float = zone.rect_size.x * 0.5
	var half_h: float = zone.rect_size.y * 0.5
	var cell_size: float = terrain_grid.CELL_SIZE

	var min_x: int = int((zone.center.x - half_w) / cell_size)
	var max_x: int = int(ceil((zone.center.x + half_w) / cell_size))
	var min_z: int = int((zone.center.z - half_h) / cell_size)
	var max_z: int = int(ceil((zone.center.z + half_h) / cell_size))

	for gz in range(min_z, max_z):
		for gx in range(min_x, max_x):
			terrain_grid.set_clearing_stage_at(gx, gz, zone.stage)

	# Emit update signal for the region
	var region := Rect2i(min_x, min_z, max_x - min_x, max_z - min_z)
	vegetation_updated.emit(region)


func _get_total_progress(zone: ClearingZone) -> float:
	# Total stages = 4 (JUNGLE=0 through FORTIFIED=3), so total steps = 4
	const TOTAL_STAGES: float = 4.0
	var stage_progress: float = float(zone.stage) / TOTAL_STAGES
	var within_stage: float = zone.progress / TOTAL_STAGES
	return stage_progress + within_stage


## Get vegetation density at world position (0-1)
## Reads from TerrainGrid as SINGLE SOURCE OF TRUTH
func get_vegetation_density(world_pos: Vector3) -> float:
	if terrain_grid:
		return terrain_grid.get_vegetation_density(world_pos)

	# Fallback for backwards compatibility
	if vegetation_manager and vegetation_manager.has_method("get_density_at"):
		var chunk_size: float = terrain_manager.chunk_size if terrain_manager else 256.0
		return vegetation_manager.get_density_at(world_pos, chunk_size)

	return 1.0


## Remove a clearing zone
func remove_zone(zone_id: int) -> void:
	zones.erase(zone_id)


## Clear all zones (for testing reset)
func clear_all_zones() -> void:
	zones.clear()

	# Reset all TerrainGrid clearing data to JUNGLE
	if terrain_grid:
		# Note: This would ideally have a bulk reset method
		# For now, we just clear the zones dictionary
		pass


## =============================================================================
## POSITION QUERY API (used by TerrainClearingSystem forwarder)
## =============================================================================

## Check if a world position is within a cleared zone (CLEARED or FORTIFIED stage)
func is_position_cleared(position: Vector3) -> bool:
	# Check TerrainGrid first (authoritative)
	if terrain_grid:
		return terrain_grid.is_position_cleared(position)

	# Fallback to zone-based check
	for zone_id: int in zones:
		var zone: ClearingZone = zones[zone_id]
		if _is_position_in_zone(position, zone):
			return zone.stage >= ClearingStage.CLEARED
	return false


## Get the clearing stage at a world position
func get_zone_stage_at(position: Vector3) -> ClearingStage:
	# Check TerrainGrid first (authoritative)
	if terrain_grid:
		return terrain_grid.get_clearing_stage(position) as ClearingStage

	# Fallback to zone-based check
	for zone_id: int in zones:
		var zone: ClearingZone = zones[zone_id]
		if _is_position_in_zone(position, zone):
			return zone.stage
	return ClearingStage.JUNGLE


## Get zone at a position (or null)
func get_zone_at(position: Vector3) -> ClearingZone:
	for zone_id: int in zones:
		var zone: ClearingZone = zones[zone_id]
		if _is_position_in_zone(position, zone):
			return zone
	return null


## Helper to check if position is inside a zone
func _is_position_in_zone(position: Vector3, zone: ClearingZone) -> bool:
	if zone.shape == "rectangle":
		var half_w := zone.rect_size.x * 0.5
		var half_h := zone.rect_size.y * 0.5
		return absf(position.x - zone.center.x) <= half_w and absf(position.z - zone.center.z) <= half_h
	else:
		return position.distance_to(zone.center) <= zone.radius


## =============================================================================
## EXTERNAL CLEARING API (called by TreeNodeManager when ClearingZoneNode completes)
## =============================================================================

## Mark an area as cleared without creating a formal zone
## Used when node-based clearing (TreeNodeManager) completes
func mark_area_cleared(center: Vector3, radius: float) -> void:
	if not terrain_grid:
		push_warning("[ClearingSystem] Cannot mark area cleared - no terrain_grid")
		return

	# TerrainGrid.CELL_SIZE is 4.0m (canonical gameplay cell size)
	var cell_size: float = 4.0
	var min_x: int = int((center.x - radius) / cell_size)
	var max_x: int = int(ceil((center.x + radius) / cell_size))
	var min_z: int = int((center.z - radius) / cell_size)
	var max_z: int = int(ceil((center.z + radius) / cell_size))

	# Mark all cells in the circular area as CLEARED
	var center_gx: float = center.x / cell_size
	var center_gz: float = center.z / cell_size
	var radius_cells: float = radius / cell_size

	for gz in range(min_z, max_z):
		for gx in range(min_x, max_x):
			var dist: float = Vector2(gx - center_gx, gz - center_gz).length()
			if dist <= radius_cells:
				terrain_grid.set_clearing_stage_at(gx, gz, ClearingStage.CLEARED)

	# Emit vegetation_updated signal to trigger billboard regeneration
	var region := Rect2i(min_x, min_z, max_x - min_x, max_z - min_z)
	vegetation_updated.emit(region)

	# Notify overlapping JungleZones that clearing has occurred
	var cleared_area: float = PI * radius * radius
	_notify_jungle_zones(center, radius, cleared_area)

	print("[ClearingSystem] Area marked cleared at %v r=%.1f (%d cells)" % [
		center, radius, (max_x - min_x) * (max_z - min_z)
	])


## Notify JungleZone nodes that clearing has occurred in their area
func _notify_jungle_zones(center: Vector3, radius: float, cleared_area: float) -> void:
	var jungle_zones: Array[Node] = get_tree().get_nodes_in_group("jungle_zones")
	for zone_node in jungle_zones:
		if not is_instance_valid(zone_node):
			continue
		# Check if zone has overlaps_circle method (JungleZone)
		if zone_node.has_method("overlaps_circle") and zone_node.has_method("mark_area_cleared"):
			if zone_node.overlaps_circle(center, radius):
				zone_node.mark_area_cleared(cleared_area)
