class_name TerrainTypes
extends RefCounted
## TerrainTypes - THE SINGLE SOURCE OF TRUTH for terrain classification
##
## All terrain-related enums, movement costs, cover values, and LOS blocking
## are defined here. NO OTHER FILE should define TerrainType enums.
##
## Usage:
##   var terrain: TerrainTypes.Type = TerrainTypes.Type.HEAVY_JUNGLE
##   var cost: float = TerrainTypes.get_movement_cost(terrain)
##   var blocks: bool = TerrainTypes.blocks_los(terrain)


## Terrain type enumeration - 8 distinct terrain classifications
enum Type {
	CLEAR = 0,        ## Cleared ground, roads, firebases
	RICE_PADDY = 1,   ## Wet rice fields, slows movement
	GRASSLAND = 2,    ## Open grass, easy movement
	LIGHT_JUNGLE = 3, ## Sparse trees, minor slowdown
	MEDIUM_JUNGLE = 4,## Dense trees, blocks some LOS
	HEAVY_JUNGLE = 5, ## Impenetrable vegetation, blocks all LOS
	WATER = 6,        ## Rivers, streams - impassable except boats
	CLIFF = 7,        ## Steep terrain - impassable
}


## Movement cost multipliers (1.0 = full speed, lower = slower)
## These are SPEED multipliers, not cost multipliers
## Example: 0.5 means unit moves at 50% speed
const MOVEMENT_SPEED: Dictionary = {
	Type.CLEAR: 1.0,
	Type.RICE_PADDY: 0.5,       # Mud slows movement significantly
	Type.GRASSLAND: 0.9,        # Slightly slower than roads
	Type.LIGHT_JUNGLE: 0.7,     # Some vegetation to push through
	Type.MEDIUM_JUNGLE: 0.5,    # Dense undergrowth
	Type.HEAVY_JUNGLE: 0.3,     # Nearly impassable vegetation
	Type.WATER: 0.0,            # Impassable (boats use different system)
	Type.CLIFF: 0.0,            # Impassable
}


## Cover values (0.0 = no cover, 1.0 = full cover)
## Affects damage reduction and visibility
const COVER: Dictionary = {
	Type.CLEAR: 0.0,
	Type.RICE_PADDY: 0.1,       # Low dikes provide minimal cover
	Type.GRASSLAND: 0.2,        # Tall grass offers some concealment
	Type.LIGHT_JUNGLE: 0.4,     # Trees and brush
	Type.MEDIUM_JUNGLE: 0.6,    # Dense vegetation
	Type.HEAVY_JUNGLE: 0.8,     # Excellent concealment
	Type.WATER: 0.0,            # No cover in water
	Type.CLIFF: 0.9,            # Rocks provide excellent cover
}


## Line of sight blocking
## true = this terrain blocks LOS through it
const LOS_BLOCKING: Dictionary = {
	Type.CLEAR: false,
	Type.RICE_PADDY: false,
	Type.GRASSLAND: false,
	Type.LIGHT_JUNGLE: false,   # Can see through sparse trees
	Type.MEDIUM_JUNGLE: true,   # Too dense to see through
	Type.HEAVY_JUNGLE: true,    # Completely blocks vision
	Type.WATER: false,
	Type.CLIFF: true,           # Rock formations block LOS
}


## Passability - can ground units traverse this terrain?
const PASSABLE: Dictionary = {
	Type.CLEAR: true,
	Type.RICE_PADDY: true,
	Type.GRASSLAND: true,
	Type.LIGHT_JUNGLE: true,
	Type.MEDIUM_JUNGLE: true,
	Type.HEAVY_JUNGLE: true,    # Passable but very slow
	Type.WATER: false,          # Need boats or bridges
	Type.CLIFF: false,          # Need engineers to build ramps
}


## Tree density per bundle (for billboard vegetation)
## [min_trees, max_trees] per 6m×6m cell
const TREE_DENSITY: Dictionary = {
	Type.CLEAR: Vector2i(0, 0),
	Type.RICE_PADDY: Vector2i(0, 0),
	Type.GRASSLAND: Vector2i(0, 1),      # Occasional tree
	Type.LIGHT_JUNGLE: Vector2i(2, 4),   # Sparse trees
	Type.MEDIUM_JUNGLE: Vector2i(4, 8),  # Dense trees
	Type.HEAVY_JUNGLE: Vector2i(8, 15),  # Very dense
	Type.WATER: Vector2i(0, 0),
	Type.CLIFF: Vector2i(0, 2),          # Some cliff vegetation
}


## Display names for UI
const DISPLAY_NAMES: Dictionary = {
	Type.CLEAR: "Cleared",
	Type.RICE_PADDY: "Rice Paddy",
	Type.GRASSLAND: "Grassland",
	Type.LIGHT_JUNGLE: "Light Jungle",
	Type.MEDIUM_JUNGLE: "Medium Jungle",
	Type.HEAVY_JUNGLE: "Heavy Jungle",
	Type.WATER: "Water",
	Type.CLIFF: "Cliff",
}


## Display colors for minimap/debug
const DISPLAY_COLORS: Dictionary = {
	Type.CLEAR: Color(0.6, 0.5, 0.3),       # Brown
	Type.RICE_PADDY: Color(0.4, 0.6, 0.3),  # Yellow-green
	Type.GRASSLAND: Color(0.5, 0.7, 0.3),   # Light green
	Type.LIGHT_JUNGLE: Color(0.2, 0.5, 0.2),# Medium green
	Type.MEDIUM_JUNGLE: Color(0.1, 0.4, 0.15), # Darker green
	Type.HEAVY_JUNGLE: Color(0.05, 0.3, 0.1),  # Dark green
	Type.WATER: Color(0.2, 0.4, 0.8),       # Blue
	Type.CLIFF: Color(0.5, 0.5, 0.5),       # Gray
}


# =============================================================================
# STATIC QUERY FUNCTIONS
# =============================================================================


## Get movement speed multiplier for terrain type
## Returns 0.0-1.0 where 1.0 = full speed
static func get_movement_speed(terrain_type: int) -> float:
	if MOVEMENT_SPEED.has(terrain_type):
		return MOVEMENT_SPEED[terrain_type]
	return 1.0


## Get movement cost (inverse of speed) for pathfinding
## Returns 1.0+ where 1.0 = no penalty, higher = more expensive
static func get_movement_cost(terrain_type: int) -> float:
	var speed: float = get_movement_speed(terrain_type)
	if speed <= 0.0:
		return 99.0  # Impassable
	return 1.0 / speed


## Get cover value for terrain type
## Returns 0.0-1.0 where 0.0 = no cover, 1.0 = full cover
static func get_cover(terrain_type: int) -> float:
	if COVER.has(terrain_type):
		return COVER[terrain_type]
	return 0.0


## Check if terrain type blocks line of sight
static func blocks_los(terrain_type: int) -> bool:
	if LOS_BLOCKING.has(terrain_type):
		return LOS_BLOCKING[terrain_type]
	return false


## Check if terrain type is passable by ground units
static func is_passable(terrain_type: int) -> bool:
	if PASSABLE.has(terrain_type):
		return PASSABLE[terrain_type]
	return true


## Get tree density range for terrain type
## Returns Vector2i(min_trees, max_trees)
static func get_tree_density(terrain_type: int) -> Vector2i:
	if TREE_DENSITY.has(terrain_type):
		return TREE_DENSITY[terrain_type]
	return Vector2i(0, 0)


## Get display name for terrain type
static func get_display_name(terrain_type: int) -> String:
	if DISPLAY_NAMES.has(terrain_type):
		return DISPLAY_NAMES[terrain_type]
	return "Unknown"


## Get display color for terrain type
static func get_display_color(terrain_type: int) -> Color:
	if DISPLAY_COLORS.has(terrain_type):
		return DISPLAY_COLORS[terrain_type]
	return Color.MAGENTA  # Error color


## Check if terrain is vegetation (has trees)
static func is_vegetation(terrain_type: int) -> bool:
	return terrain_type in [Type.LIGHT_JUNGLE, Type.MEDIUM_JUNGLE, Type.HEAVY_JUNGLE]


## Check if terrain is jungle (any density)
static func is_jungle(terrain_type: int) -> bool:
	return terrain_type in [Type.LIGHT_JUNGLE, Type.MEDIUM_JUNGLE, Type.HEAVY_JUNGLE]


## Get the "cleared" version of a terrain type
## Used when clearing vegetation
static func get_cleared_type(terrain_type: int) -> int:
	match terrain_type:
		Type.LIGHT_JUNGLE, Type.MEDIUM_JUNGLE, Type.HEAVY_JUNGLE:
			return Type.CLEAR
		_:
			return terrain_type
