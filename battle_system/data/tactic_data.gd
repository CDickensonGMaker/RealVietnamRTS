class_name TacticData extends Resource
## Defines a "tactic" the player picks before a mission.
## Determines available units, buildings, and roster composition.
## Stored as .tres files under battle_system/data/tactics/

# =============================================================================
# TACTIC IDENTITY
# =============================================================================

## Unique identifier for this tactic
@export var tactic_id: String = ""

## Display name shown in UI
@export var display_name: String = ""

## Description of the tactic's playstyle
@export_multiline var description: String = ""

## Icon path (placeholder - will be texture path later)
@export var icon_path: String = ""

# =============================================================================
# UNIT AVAILABILITY
# =============================================================================

## Array of SquadData resources available with this tactic
@export var available_unit_data: Array[Resource] = []

## Array of BuildingType enum values available with this tactic
## (matches firebase_system/building_data.gd BuildingType enum)
@export var available_building_types: Array[int] = []

# =============================================================================
# ROSTER COMPOSITION
# =============================================================================

## Dictionary defining roster slots by category
## Example: {"infantry": 6, "armor": 2, "engineer": 2, "air": 1}
@export var roster_slots: Dictionary = {
	"infantry": 4,
	"armor": 1,
	"engineer": 1,
	"support": 1,
	"air": 0,
}

## Minimum veterancy level for units deployed with this tactic
## 0 = Conscript, 1 = Regular, 2 = Veteran, 3 = Elite, 4 = Legend
@export_range(0, 4) var starting_veterancy_floor: int = 0

# =============================================================================
# XP WEIGHTING
# =============================================================================

## Optional weights for XP sources (multipliers on base XP awards)
## Default all to 1.0. Recon tactics might set {"spotting": 2.0, "kills": 0.5}
## Valid keys: "kills", "damage", "survival", "spotting", "objectives"
@export var xp_source_weights: Dictionary = {
	"kills": 1.0,
	"damage": 1.0,
	"survival": 1.0,
	"spotting": 1.0,
	"objectives": 1.0,
}

# =============================================================================
# SPECIAL RULES (future expansion)
# =============================================================================

## Special abilities or rules this tactic grants (for future use)
## Example: ["fast_deployment", "artillery_priority", "stealth_insertion"]
@export var special_rules: Array[String] = []

## Starting resources modifier (multiplier, 1.0 = normal)
@export var starting_resources_mult: float = 1.0

## Reinforcement speed modifier (multiplier, 1.0 = normal)
@export var reinforcement_speed_mult: float = 1.0

# =============================================================================
# PUBLIC METHODS
# =============================================================================

## Returns the total roster capacity
func get_total_roster_capacity() -> int:
	var total: int = 0
	for category: String in roster_slots:
		var count: Variant = roster_slots[category]
		if count is int:
			total += count
	return total


## Returns roster slots for a specific category, or 0 if not defined
func get_slots_for_category(category: String) -> int:
	var value: Variant = roster_slots.get(category, 0)
	return value if value is int else 0


## Returns XP weight for a source, defaulting to 1.0
func get_xp_weight(source: String) -> float:
	var weight: Variant = xp_source_weights.get(source, 1.0)
	return weight if weight is float else 1.0


## Checks if a building type is available with this tactic
func is_building_available(building_type: int) -> bool:
	return building_type in available_building_types


## Checks if a unit data resource is available with this tactic
func is_unit_available(unit_data: Resource) -> bool:
	return unit_data in available_unit_data


## Returns true if this tactic grants a special rule
func has_special_rule(rule: String) -> bool:
	return rule in special_rules


# =============================================================================
# VALIDATION
# =============================================================================

## Validates the tactic data, returns array of warning strings
func validate() -> Array[String]:
	var warnings: Array[String] = []

	if tactic_id.is_empty():
		warnings.append("tactic_id is empty")

	if display_name.is_empty():
		warnings.append("display_name is empty")

	if available_unit_data.is_empty() and available_building_types.is_empty():
		warnings.append("No units or buildings available - tactic is empty")

	if get_total_roster_capacity() <= 0:
		warnings.append("Total roster capacity is 0")

	for source: String in xp_source_weights:
		var weight: Variant = xp_source_weights[source]
		if not (weight is float or weight is int):
			warnings.append("xp_source_weights['%s'] is not a number" % source)
		elif weight < 0:
			warnings.append("xp_source_weights['%s'] is negative" % source)

	return warnings


# =============================================================================
# DEBUG
# =============================================================================

func _to_string() -> String:
	return "TacticData(%s: %s, %d units, %d buildings)" % [
		tactic_id,
		display_name,
		available_unit_data.size(),
		available_building_types.size(),
	]
