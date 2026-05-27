# War Room Briefing: Sandbag Orientation Fix

**Date**: 2026-05-26
**Summoner**: User
**Priority**: HIGH - Core placement system broken

---

## The Problem

When painting sandbags/wire in linear placement mode (Company of Heroes style), models are **perpendicular** to the painted line instead of running **along** it.

**Expected**: Drag from A to B, sandbags form a wall FROM A TO B (length parallel to AB line)
**Actual**: Sandbags cross the painted line at 90 degrees

## Visual Evidence

User screenshot showed sandbag models with "Queued" labels all oriented perpendicular to the drag direction.

## Prior Attempts

1. Changed `model_rotation_y` values (90° vs 180°) - didn't fix core issue
2. Increased `model_scale` from 0.01 to 0.025 - helped with gaps but not orientation
3. Removed `+ PI / 2.0` from rotation formula - just attempted, needs verification

## Key Files

- `firebase_system/placement_controller.gd` - calculates `_linear_rotation_y`
- `firebase_system/building_data.gd` - contains `model_rotation_y` per building type
- `firebase_system/construction_manager.gd` - applies final rotation to constructed buildings
- `battle_system/ui/blueprint_ghost.gd` - shows preview during placement
- `tests/linear_placement_test/rotation_diagnostic.gd` - existing diagnostic test

## Current Formula (after recent edit)

```gdscript
# placement_controller.gd line ~396
_linear_rotation_y = atan2(direction.x, direction.z)
```

Then `construction_manager.gd` adds `model_rotation_y` when spawning the actual building.

## Constraints

1. Must work for ALL drag angles, not just cardinal directions
2. Must be consistent across all linear placement buildings (sandbags, wire)
3. Godot coordinate system: Forward = -Z, rotation.y = 0 means facing -Z
4. Models authored with length along different axes need compensation via `model_rotation_y`

## Questions for the Council

1. What is the correct rotation formula for "wall style" placement?
2. How do we create a reliable test to verify ALL angles work?
3. Should we create a dedicated test scene that's simpler than the full game?
4. How do we handle models with different authored orientations?
