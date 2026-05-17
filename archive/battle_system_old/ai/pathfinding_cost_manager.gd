extends Node
## PathfindingCostManager - Manages terrain-based pathfinding costs for NavigationServer3D
## Accessed globally via PathfindingCostManager autoload (no class_name needed)

## Integrates with Vietnam terrain system to provide realistic movement costs:
## - Jungle slows infantry significantly
## - Roads provide speed bonus
## - Cleared areas have normal movement
## - Water/swamp creates major penalties

signal terrain_costs_updated(region_id: RID)
signal navigation_region_modified(region_id: RID)

# =============================================================================
# CONFIGURATION
# =============================================================================

## Navigation layer configuration
const NAV_LAYER_INFANTRY: int = 1
const NAV_LAYER_VEHICLE: int = 2
const NAV_LAYER_HELICOPTER: int = 4  # Air doesn't use ground navigation

## Cost multipliers (higher = slower/more expensive path)
const TERRAIN_COSTS: Dictionary = {
	GameEnums.TerrainType.TRIPLE_CANOPY: 3.5,   # Very slow
	GameEnums.TerrainType.SINGLE_CANOPY: 1.8,   # Moderately slow
	GameEnums.TerrainType.ELEPHANT_GRASS: 1.3,  # Slightly slow
	GameEnums.TerrainType.RICE_PADDY: 1.5,      # Wet terrain
	GameEnums.TerrainType.BAMBOO: 2.0,          # Dense
	GameEnums.TerrainType.HILL: 1.2,            # Elevation
	GameEnums.TerrainType.MOUNTAIN: 2.5,        # Steep
	GameEnums.TerrainType.RIVER: 10.0,          # Essentially impassable
	GameEnums.TerrainType.CLEARED: 1.0,         # Normal speed
	GameEnums.TerrainType.VILLAGE: 1.0,         # Normal
	GameEnums.TerrainType.ROAD: 0.7,            # Speed bonus
	GameEnums.TerrainType.WATER: 100.0,         # Impassable
	GameEnums.TerrainType.SWAMP: 2.5,           # Very slow
}

## Vehicle-specific cost adjustments
const VEHICLE_TERRAIN_COSTS: Dictionary = {
	GameEnums.TerrainType.TRIPLE_CANOPY: 100.0, # Vehicles can't traverse
	GameEnums.TerrainType.SINGLE_CANOPY: 5.0,   # Very difficult
	GameEnums.TerrainType.BAMBOO: 100.0,        # Can't traverse
	GameEnums.TerrainType.RICE_PADDY: 3.0,      # Risk of getting stuck
	GameEnums.TerrainType.ROAD: 0.5,            # Best for vehicles
	GameEnums.TerrainType.CLEARED: 0.8,         # Good
	GameEnums.TerrainType.SWAMP: 100.0,         # Impassable
}

# =============================================================================
# STATE
# =============================================================================

var _active_regions: Dictionary = {}  # RID -> NavigationRegion data
var _terrain_grid: Dictionary = {}    # Vector2i -> TerrainType
var _cleared_zones: Array[Rect2] = []
var _road_segments: Array[Dictionary] = []

func _ready() -> void:
	# Connect to terrain clearing signals
	BattleSignals.clearing_complete.connect(_on_terrain_cleared)

	# Connect to trail network
	if has_node("/root/TrailNetwork"):
		var trail_network := get_node("/root/TrailNetwork")
		if trail_network.has_signal("trail_created"):
			trail_network.trail_created.connect(_on_trail_created)


# =============================================================================
# PUBLIC API
# =============================================================================

## Get the movement cost multiplier for a world position
func get_cost_at_position(world_pos: Vector3, is_vehicle: bool = false) -> float:
	var cell := _world_to_cell(world_pos)
	var terrain_type: int = _terrain_grid.get(cell, GameEnums.TerrainType.SINGLE_CANOPY)

	# Check if position is on a road
	if _is_on_road(world_pos):
		terrain_type = GameEnums.TerrainType.ROAD

	# Check if position is cleared
	if _is_cleared(world_pos):
		terrain_type = GameEnums.TerrainType.CLEARED

	# Get appropriate cost table
	var cost_table: Dictionary = VEHICLE_TERRAIN_COSTS if is_vehicle else TERRAIN_COSTS
	return cost_table.get(terrain_type, 1.0)


## Get the speed modifier for a world position (inverse of cost)
func get_speed_modifier_at(world_pos: Vector3, is_vehicle: bool = false) -> float:
	var cost := get_cost_at_position(world_pos, is_vehicle)
	if cost >= 100.0:
		return 0.0  # Impassable
	return 1.0 / cost


## Check if a position is passable
func is_passable(world_pos: Vector3, is_vehicle: bool = false) -> bool:
	var cost := get_cost_at_position(world_pos, is_vehicle)
	return cost < 100.0


## Register a cleared zone (updates pathfinding)
func register_cleared_zone(zone_rect: Rect2) -> void:
	_cleared_zones.append(zone_rect)
	_update_navigation_for_area(zone_rect)


## Register a road segment
func register_road_segment(start: Vector3, end: Vector3, width: float) -> void:
	_road_segments.append({
		"start": start,
		"end": end,
		"width": width,
	})


## Update terrain type for a cell
func set_terrain_type(cell: Vector2i, terrain_type: int) -> void:
	_terrain_grid[cell] = terrain_type


## Batch update terrain from VietnamCell
func update_from_cell(cell_coords: Vector2i, terrain_type: int) -> void:
	# Update the 17x17 grid of vertices in this cell
	for x in range(17):
		for z in range(17):
			var grid_cell := Vector2i(
				cell_coords.x * 16 + x,
				cell_coords.y * 16 + z
			)
			_terrain_grid[grid_cell] = terrain_type


# =============================================================================
# NAVIGATION AGENT HELPERS
# =============================================================================

## Configure a NavigationAgent3D with appropriate settings for unit type
func configure_navigation_agent(agent: NavigationAgent3D, is_vehicle: bool = false) -> void:
	agent.path_desired_distance = 1.5 if not is_vehicle else 3.0
	agent.target_desired_distance = 2.0 if not is_vehicle else 5.0
	agent.path_max_distance = 10.0
	agent.avoidance_enabled = true
	agent.radius = 0.5 if not is_vehicle else 2.0
	agent.height = 2.0 if not is_vehicle else 3.0
	agent.neighbor_distance = 10.0
	agent.max_neighbors = 10
	agent.max_speed = 8.0 if not is_vehicle else 15.0

	# Set navigation layers
	if is_vehicle:
		agent.navigation_layers = NAV_LAYER_VEHICLE
	else:
		agent.navigation_layers = NAV_LAYER_INFANTRY


## Apply terrain cost to path calculation
## Call this to modify path direction based on terrain
func get_weighted_direction(agent: NavigationAgent3D, current_pos: Vector3,
							 target_pos: Vector3, is_vehicle: bool = false) -> Vector3:
	var nav_dir := (agent.get_next_path_position() - current_pos).normalized()

	# Sample costs in multiple directions to influence pathing
	var best_dir := nav_dir
	var best_cost := get_cost_at_position(current_pos + nav_dir * 5.0, is_vehicle)

	# Check alternate directions
	var angles: Array[float] = [PI/6, -PI/6, PI/4, -PI/4]
	for angle in angles:
		var test_dir := nav_dir.rotated(Vector3.UP, angle)
		var test_pos := current_pos + test_dir * 5.0
		var test_cost := get_cost_at_position(test_pos, is_vehicle)

		# Also consider distance to target
		var to_target := target_pos - test_pos
		var target_factor := 1.0 + (to_target.length() * 0.01)

		if test_cost * target_factor < best_cost:
			best_cost = test_cost * target_factor
			best_dir = test_dir

	return best_dir


# =============================================================================
# INTERNAL HELPERS
# =============================================================================

func _world_to_cell(world_pos: Vector3) -> Vector2i:
	var cell_size := 12.5  # Match terrain grid
	return Vector2i(
		int(floorf(world_pos.x / cell_size)),
		int(floorf(world_pos.z / cell_size))
	)


func _is_on_road(world_pos: Vector3) -> bool:
	var pos_2d := Vector2(world_pos.x, world_pos.z)

	for segment in _road_segments:
		var start_2d := Vector2(segment.start.x, segment.start.z)
		var end_2d := Vector2(segment.end.x, segment.end.z)
		var width: float = segment.width

		# Point to line segment distance
		var line_dir := (end_2d - start_2d).normalized()
		var to_point := pos_2d - start_2d
		var projection := to_point.dot(line_dir)
		var line_length := start_2d.distance_to(end_2d)

		if projection >= 0 and projection <= line_length:
			var closest := start_2d + line_dir * projection
			if pos_2d.distance_to(closest) <= width * 0.5:
				return true

	return false


func _is_cleared(world_pos: Vector3) -> bool:
	var pos_2d := Vector2(world_pos.x, world_pos.z)

	for zone in _cleared_zones:
		if zone.has_point(pos_2d):
			return true

	return false


func _update_navigation_for_area(area: Rect2) -> void:
	# Emit signal for systems that need to know about navigation changes
	terrain_costs_updated.emit(RID())


func _on_terrain_cleared(zone: Node3D, _new_state: int) -> void:
	if zone.has_method("get_zone_rect"):
		var zone_rect: Rect2 = zone.get_zone_rect()
		register_cleared_zone(zone_rect)


func _on_trail_created(start: Vector3, end: Vector3, trail_type: String) -> void:
	var width := 2.0
	match trail_type:
		"main_trail": width = 4.0
		"supply_route": width = 6.0
		"road": width = 8.0

	register_road_segment(start, end, width)
