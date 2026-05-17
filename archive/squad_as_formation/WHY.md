# Why This Folder Was Archived

## Date: 2026-05-13

## Reason
This contains an alternative squad implementation with visual soldiers in formation. The main game uses `battle_system/nodes/squad.gd` instead.

## What Was Here
- `infantry_squad.gd` - Squad with visual soldier instances in formation
- `soldier.gd` - Individual soldier visual representation

## Why Keep
The formation visualization is valuable for visual polish. The files still exist in battle_system/nodes/ but are considered secondary to Squad.

## Integration Path
If you want to add formation visuals to Squad, reference this code for:
- Formation patterns (LINE, WEDGE, COLUMN, SPREAD)
- Soldier spacing and positioning
- Squad selection visuals
- Per-soldier health tracking

## Current Usage
The helicopter shuttle test still uses InfantrySquad. Update those tests to use Squad when ready.
