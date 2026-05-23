class_name CursorMode extends RefCounted
## Static state machine for cursor/input modes.
## Used by BattleHUD to track what action the cursor is currently performing.

# =============================================================================
# CURSOR MODE ENUM
# =============================================================================

enum Mode {
	NORMAL,           # Default mode - click to select, right-click to move
	MOVE_PREVIEW,     # Showing move path preview
	ATTACK_MOVE,      # Attack-move targeting
	FIRE_MISSION,     # Artillery indirect fire targeting
	UNLOAD,           # Unloading troops from transport
	BOMB_RUN,         # Fixed-wing bomb run targeting
	NAPALM_RUN,       # Napalm strike targeting
	ROCKET_RUN,       # Rocket attack run targeting
	STRAFE_RUN,       # Gun strafe run targeting
	BUILDING_PLACE,   # Placing a construction ghost
	GARRISON,         # Selecting unit to garrison in structure
	# Construction paint modes
	PAINT_CLEAR,      # Painting area to clear vegetation (engineers, 3x3 det-cord)
	PAINT_FLATTEN,    # Painting area to flatten terrain
	PAINT_ROAD,       # Drawing road path (polyline)
	PAINT_BUILD,      # Placing a building (single click)
	PAINT_FILL,       # Filling crater (single click)
	# Bulldozer-specific modes
	PAINT_DOZER_LINE, # Bulldozer 3-wide straight line clearing
	# Linear placement modes (drag start to end)
	PAINT_TRENCH,     # Paint trench line
	PAINT_WIRE,       # Paint wire obstacle line
	# Standing order modes
	PATROL,           # Set patrol waypoints for units
	REPAIR,           # Target structure for repair
}


# =============================================================================
# MODE PROPERTIES
# =============================================================================

## Returns display name for a mode
static func get_mode_name(mode: int) -> String:
	match mode:
		Mode.NORMAL: return "NORMAL"
		Mode.MOVE_PREVIEW: return "MOVE"
		Mode.ATTACK_MOVE: return "ATTACK-MOVE"
		Mode.FIRE_MISSION: return "FIRE MISSION"
		Mode.UNLOAD: return "UNLOAD"
		Mode.BOMB_RUN: return "BOMB RUN"
		Mode.NAPALM_RUN: return "NAPALM"
		Mode.ROCKET_RUN: return "ROCKET RUN"
		Mode.STRAFE_RUN: return "STRAFE"
		Mode.BUILDING_PLACE: return "BUILD"
		Mode.GARRISON: return "GARRISON"
		Mode.PAINT_CLEAR: return "CLEAR TERRAIN"
		Mode.PAINT_FLATTEN: return "FLATTEN"
		Mode.PAINT_ROAD: return "BUILD ROAD"
		Mode.PAINT_BUILD: return "PLACE BUILDING"
		Mode.PAINT_FILL: return "FILL CRATER"
		Mode.PAINT_DOZER_LINE: return "DOZER LINE"
		Mode.PAINT_TRENCH: return "DIG TRENCH"
		Mode.PAINT_WIRE: return "LAY WIRE"
		Mode.PATROL: return "PATROL"
		Mode.REPAIR: return "REPAIR"
		_: return "UNKNOWN"


## Returns true if this mode requires a target click
static func requires_target(mode: int) -> bool:
	return mode != Mode.NORMAL


## Returns true if this mode shows a targeting overlay
static func shows_overlay(mode: int) -> bool:
	match mode:
		Mode.MOVE_PREVIEW, Mode.ATTACK_MOVE, Mode.FIRE_MISSION, \
		Mode.UNLOAD, Mode.BOMB_RUN, Mode.NAPALM_RUN, Mode.ROCKET_RUN, \
		Mode.STRAFE_RUN, Mode.BUILDING_PLACE, Mode.GARRISON, \
		Mode.PAINT_CLEAR, Mode.PAINT_FLATTEN, Mode.PAINT_ROAD, \
		Mode.PAINT_BUILD, Mode.PAINT_FILL, Mode.PAINT_DOZER_LINE, \
		Mode.PAINT_TRENCH, Mode.PAINT_WIRE, Mode.PATROL, Mode.REPAIR:
			return true
		_:
			return false


## Returns true if this is a construction paint mode
static func is_paint_mode(mode: int) -> bool:
	match mode:
		Mode.PAINT_CLEAR, Mode.PAINT_FLATTEN, Mode.PAINT_ROAD, \
		Mode.PAINT_BUILD, Mode.PAINT_FILL, Mode.PAINT_DOZER_LINE, \
		Mode.PAINT_TRENCH, Mode.PAINT_WIRE:
			return true
		_:
			return false


## Returns true if this mode is canceled by Escape
static func canceled_by_escape(mode: int) -> bool:
	return mode != Mode.NORMAL


## Returns true if right-click commits the action in this mode
static func right_click_commits(mode: int) -> bool:
	match mode:
		Mode.FIRE_MISSION, Mode.UNLOAD, Mode.BOMB_RUN, Mode.NAPALM_RUN, \
		Mode.ROCKET_RUN, Mode.STRAFE_RUN, Mode.GARRISON, \
		Mode.PAINT_CLEAR, Mode.PAINT_DOZER_LINE, Mode.PATROL, Mode.REPAIR:
			return true
		_:
			return false


## Returns true if left-click commits the action in this mode
## (Building placement is more intuitive with left-click)
static func left_click_commits(mode: int) -> bool:
	match mode:
		Mode.BUILDING_PLACE, Mode.PAINT_BUILD:
			return true
		_:
			return false
