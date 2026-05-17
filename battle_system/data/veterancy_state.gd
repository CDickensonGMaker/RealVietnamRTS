class_name VeterancyState extends Resource
## Per-unit veterancy data that persists between battles via the roster.
## Tracks XP, kills, and level with stat modifiers.

# =============================================================================
# CONSTANTS
# =============================================================================

## XP thresholds for each level (index = level)
const XP_THRESHOLDS: PackedInt32Array = [0, 100, 300, 700, 1500]

## Display names for each level
const LEVEL_NAMES: PackedStringArray = ["Conscript", "Regular", "Veteran", "Elite", "Legend"]

## Stat modifier keys
const STAT_KEYS: PackedStringArray = [
	"accuracy_bonus",
	"suppression_resist",
	"hp_bonus",
	"reload_bonus",
	"sight_bonus",
]

## Stat modifiers per level [accuracy, suppression_resist, hp, reload, sight]
const LEVEL_MODIFIERS: Array[Dictionary] = [
	# Level 0: Conscript
	{
		"accuracy_bonus": 0.0,
		"suppression_resist": 0.0,
		"hp_bonus": 0.0,
		"reload_bonus": 0.0,
		"sight_bonus": 0.0,
	},
	# Level 1: Regular
	{
		"accuracy_bonus": 0.05,
		"suppression_resist": 0.05,
		"hp_bonus": 0.0,
		"reload_bonus": 0.0,
		"sight_bonus": 0.0,
	},
	# Level 2: Veteran
	{
		"accuracy_bonus": 0.10,
		"suppression_resist": 0.15,
		"hp_bonus": 0.05,
		"reload_bonus": 0.0,
		"sight_bonus": 0.0,
	},
	# Level 3: Elite
	{
		"accuracy_bonus": 0.15,
		"suppression_resist": 0.25,
		"hp_bonus": 0.10,
		"reload_bonus": 0.05,
		"sight_bonus": 0.0,
	},
	# Level 4: Legend
	{
		"accuracy_bonus": 0.20,
		"suppression_resist": 0.35,
		"hp_bonus": 0.15,
		"reload_bonus": 0.10,
		"sight_bonus": 0.05,
	},
]

# =============================================================================
# EXPORTED STATE
# =============================================================================

## Current veterancy level (0-4)
@export var level: int = 0

## Total accumulated XP
@export var xp: int = 0

## Total kills by this unit
@export var kills: int = 0

## Total damage dealt by this unit
@export var damage_dealt: float = 0.0

## Number of survival ticks (time under fire without dying)
@export var survival_ticks: int = 0

## Objectives this unit helped complete
@export var objectives_completed: int = 0

# =============================================================================
# PUBLIC METHODS
# =============================================================================

## Adds XP and returns true if the unit leveled up
func add_xp(amount: int) -> bool:
	if amount <= 0:
		return false

	var old_level: int = level
	xp += amount

	# Check for level up (cap at max level)
	while level < XP_THRESHOLDS.size() - 1:
		var threshold: int = XP_THRESHOLDS[level + 1]
		if xp >= threshold:
			level += 1
		else:
			break

	return level > old_level


## Returns the display name for current level
func get_level_name() -> String:
	var idx: int = clampi(level, 0, LEVEL_NAMES.size() - 1)
	return LEVEL_NAMES[idx]


## Returns the short abbreviation for current level
func get_level_abbrev() -> String:
	match level:
		0: return "CON"
		1: return "REG"
		2: return "VET"
		3: return "ELT"
		4: return "LEG"
		_: return "???"


## Returns XP needed to reach next level, or 0 if max level
func get_xp_to_next_level() -> int:
	if level >= XP_THRESHOLDS.size() - 1:
		return 0
	return XP_THRESHOLDS[level + 1] - xp


## Returns progress fraction toward next level (0.0 to 1.0)
func get_level_progress() -> float:
	if level >= XP_THRESHOLDS.size() - 1:
		return 1.0

	var current_threshold: int = XP_THRESHOLDS[level]
	var next_threshold: int = XP_THRESHOLDS[level + 1]
	var range_size: int = next_threshold - current_threshold

	if range_size <= 0:
		return 1.0

	var progress: int = xp - current_threshold
	return clampf(float(progress) / float(range_size), 0.0, 1.0)


## Returns dictionary of stat modifiers for current level
func get_stat_modifiers() -> Dictionary:
	var idx: int = clampi(level, 0, LEVEL_MODIFIERS.size() - 1)
	return LEVEL_MODIFIERS[idx].duplicate()


## Returns a specific stat modifier value
func get_modifier(stat_key: String) -> float:
	var mods: Dictionary = get_stat_modifiers()
	return mods.get(stat_key, 0.0)


## Records a kill (increments counter)
func record_kill() -> void:
	kills += 1


## Records damage dealt (accumulates)
func record_damage(amount: float) -> void:
	if amount > 0:
		damage_dealt += amount


## Records a survival tick (time under fire)
func record_survival_tick() -> void:
	survival_ticks += 1


## Records an objective completion
func record_objective() -> void:
	objectives_completed += 1


# =============================================================================
# SERIALIZATION
# =============================================================================

## Converts state to dictionary for JSON serialization
func to_dict() -> Dictionary:
	return {
		"level": level,
		"xp": xp,
		"kills": kills,
		"damage_dealt": damage_dealt,
		"survival_ticks": survival_ticks,
		"objectives_completed": objectives_completed,
	}


## Creates a VeterancyState from a dictionary
static func from_dict(d: Dictionary) -> VeterancyState:
	var state := VeterancyState.new()
	state.level = d.get("level", 0)
	state.xp = d.get("xp", 0)
	state.kills = d.get("kills", 0)
	state.damage_dealt = d.get("damage_dealt", 0.0)
	state.survival_ticks = d.get("survival_ticks", 0)
	state.objectives_completed = d.get("objectives_completed", 0)
	return state


## Creates a fresh state at the given level (with appropriate base XP)
static func create_at_level(target_level: int) -> VeterancyState:
	var state := VeterancyState.new()
	target_level = clampi(target_level, 0, XP_THRESHOLDS.size() - 1)
	state.level = target_level
	state.xp = XP_THRESHOLDS[target_level]
	return state


## Duplicates this state
func duplicate_state() -> VeterancyState:
	return from_dict(to_dict())
