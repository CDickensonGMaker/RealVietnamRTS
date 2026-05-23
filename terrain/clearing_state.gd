class_name ClearingState
extends RefCounted
## Single source of truth for clearing state enum
## Per ARCHITECTURE.md: ONE ClearingState enum defined once, imported everywhere

## Clearing stages for terrain/vegetation
## JUNGLE -> PARTIALLY_CLEARED -> CLEARED -> FORTIFIED
enum Stage {
	JUNGLE = 0,              ## Full vegetation - cannot build
	PARTIALLY_CLEARED = 1,   ## Trees down, stumps remain
	CLEARED = 2,             ## Open ground - buildable
	FORTIFIED = 3,           ## Flattened and prepared for construction
}

## Helper to get stage name for debugging
static func get_stage_name(stage: Stage) -> String:
	match stage:
		Stage.JUNGLE:
			return "Jungle"
		Stage.PARTIALLY_CLEARED:
			return "Partially Cleared"
		Stage.CLEARED:
			return "Cleared"
		Stage.FORTIFIED:
			return "Fortified"
		_:
			return "Unknown"

## Check if a stage allows building
static func can_build_at(stage: Stage) -> bool:
	return stage >= Stage.CLEARED
