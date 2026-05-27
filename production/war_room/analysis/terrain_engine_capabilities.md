# Step 3: TerrainEngine Capabilities Inventory

**Date:** 2026-05-26
**Status:** COMPLETE

---

## Executive Summary

TerrainEngine is **already well-equipped** for construction system integration. The `TerrainGrid` class serves as the single source of truth with 35+ query methods. Most of what construction needs already exists - the gap is primarily in **how construction calls it**, not in missing capabilities.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    TERRAIN SYSTEM STACK                         │
├─────────────────────────────────────────────────────────────────┤
│  TerrainManager (Node3D)                                        │
│  ├─ Chunk streaming & camera tracking                           │
│  ├─ River generation                                            │
│  └─ High-level API: get_height_at(), modify_terrain()           │
├─────────────────────────────────────────────────────────────────┤
│  TerrainGrid (RefCounted) ← SINGLE SOURCE OF TRUTH              │
│  ├─ 4m gameplay cells                                           │
│  ├─ Terrain type, clearing state, occupancy                     │
│  ├─ Passability, movement cost, cover, LOS                      │
│  └─ validate_footprint() ← CONSTRUCTION GATEWAY                 │
├─────────────────────────────────────────────────────────────────┤
│  HeightmapStorage (RefCounted)                                  │
│  ├─ 2m precision heightmap                                      │
│  ├─ Bilinear interpolation                                      │
│  └─ Region modification                                         │
├─────────────────────────────────────────────────────────────────┤
│  ClearingSystem (Node)                                          │
│  ├─ Zone management (JUNGLE → FORTIFIED)                        │
│  ├─ Progress tracking                                           │
│  └─ Vegetation density updates                                  │
├─────────────────────────────────────────────────────────────────┤
│  VegetationManager (Node3D)                                     │
│  ├─ Billboard/mesh vegetation                                   │
│  ├─ LOD and frustum culling                                     │
│  └─ Density-based LOS blocking                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key Classes & Files

| File | Class | Purpose | API Size |
|------|-------|---------|----------|
| `terrain/core/terrain_grid.gd` | TerrainGrid | **SINGLE SOURCE OF TRUTH** | 35+ query, 12+ modify |
| `terrain/core/terrain_manager.gd` | TerrainManager | Chunk streaming, high-level API | 11 query, 3 modify |
| `terrain/core/heightmap_storage.gd` | HeightmapStorage | Raw height data | 8 query, 2 modify |
| `terrain/core/terrain_engine.gd` | TerrainEngine | Procedural generation | 5 query, 3 modify |
| `terrain/systems/clearing_system.gd` | ClearingSystem | Clearing zone management | 6 query, 2 modify |
| `terrain/vegetation/vegetation_manager.gd` | VegetationManager | Billboard vegetation | 11 query, 3 modify |
| `terrain/core/grid_coords.gd` | GridCoords | Coordinate conversions | 18 static methods |
| `terrain/terrain_types.gd` | TerrainTypes | Enum + lookup tables | 11 static methods |
| `terrain/clearing_state.gd` | ClearingState | Stage enum | 2 helpers |

---

## Existing Query Capabilities

### 1. Placement Validation (THE BIG ONE)

```gdscript
# TerrainGrid.validate_footprint() - Returns everything construction needs
var result: Dictionary = terrain_grid.validate_footprint(center, size, building_type)

# Returns:
{
    "valid": bool,                    # Can build here?
    "cells": Array[Vector2i],         # Cells under footprint
    "blocking_cells": Dictionary,     # {cell: "reason"} for failures
    "required_clearing": Array[Vector2i],  # Cells needing clearing
    "average_elevation": float,       # For height snapping
    "min_elevation": float,
    "max_elevation": float,
    "max_slope": float,               # Steepest cell
    "warnings": Array[String]         # Non-blocking issues
}
```

### 2. Elevation Queries

| Method | Returns | Use Case |
|--------|---------|----------|
| `TerrainGrid.get_elevation(pos)` | float (meters) | Building height snap |
| `TerrainGrid.get_elevation_at(gx, gz)` | float | Cell-based queries |
| `TerrainGrid.get_slope(pos)` | 0.0-1.0 | Slope check |
| `TerrainGrid.get_elevation_advantage(a, b)` | float | Combat calculations |
| `TerrainManager.get_height_at(pos)` | float | Movement, interpolated |
| `TerrainManager.get_normal_at(pos)` | Vector3 | Slope direction |

### 3. Clearing State Queries

| Method | Returns | Use Case |
|--------|---------|----------|
| `TerrainGrid.get_clearing_stage(pos)` | ClearingState.Stage | Check if buildable |
| `TerrainGrid.is_position_cleared(pos)` | bool | Quick check (≥ CLEARED) |
| `ClearingSystem.is_position_cleared(pos)` | bool | Zone-based check |
| `ClearingSystem.get_zone_stage_at(pos)` | Stage | Within clearing zone |

**ClearingState.Stage enum:**
- `JUNGLE = 0` - Cannot build
- `PARTIALLY_CLEARED = 1` - Trees down, stumps remain
- `CLEARED = 2` - Buildable
- `FORTIFIED = 3` - Flattened and prepared

### 4. Terrain Type Queries

| Method | Returns | Use Case |
|--------|---------|----------|
| `TerrainGrid.get_terrain_type(pos)` | TerrainTypes enum | Type classification |
| `TerrainTypes.is_jungle(type)` | bool | Dense vegetation check |
| `TerrainTypes.is_vegetation(type)` | bool | Any vegetation |
| `TerrainTypes.is_passable(type)` | bool | Walkability |
| `TerrainTypes.get_movement_speed(type)` | 0.0-1.0 | Movement multiplier |

**TerrainTypes enum:**
- `CLEAR = 0`, `RICE_PADDY = 1`, `GRASSLAND = 2`
- `LIGHT_JUNGLE = 3`, `MEDIUM_JUNGLE = 4`, `HEAVY_JUNGLE = 5`
- `WATER = 6`, `CLIFF = 7`

### 5. Occupancy Queries

| Method | Returns | Use Case |
|--------|---------|----------|
| `TerrainGrid.is_occupied_at(gx, gz)` | bool | Building collision |
| `TerrainGrid.get_occupancy_at(gx, gz)` | int | Building ID (0 = empty) |
| `TerrainGrid.is_buildable(pos)` | bool | Cleared AND unoccupied |
| `TerrainGrid.is_cell_buildable(gx, gz)` | bool | Cell-based version |

### 6. Movement & Passability

| Method | Returns | Use Case |
|--------|---------|----------|
| `TerrainGrid.is_passable(pos)` | bool | Walkable |
| `TerrainGrid.get_movement_cost(pos)` | float | Pathfinding weight |
| `TerrainGrid.get_movement_speed(pos)` | float | Speed multiplier |
| `VegetationManager.get_movement_multiplier_at(pos)` | float | Vegetation slowdown |

### 7. Combat & LOS

| Method | Returns | Use Case |
|--------|---------|----------|
| `TerrainGrid.blocks_los(pos)` | bool | Single point |
| `TerrainGrid.has_line_of_sight(from, to)` | bool | Grid raycast |
| `TerrainGrid.get_cover(pos)` | 0.0-1.0 | Cover value |
| `TerrainGrid.get_defense_bonus(pos)` | float | Defensive bonus |
| `VegetationManager.blocks_los(pos)` | bool | Vegetation LOS |

---

## Existing Modification Capabilities

### Clearing State

```gdscript
TerrainGrid.set_clearing_stage(pos, ClearingState.Stage.CLEARED)
TerrainGrid.set_clearing_stage_area(center, radius, stage)
TerrainGrid.mark_area_cleared(center, radius)  # Convenience
ClearingSystem.create_zone(center, radius)  # Full zone with progress
ClearingSystem.advance_clearing(zone_id, amount)  # Progress clearing
```

### Occupancy

```gdscript
TerrainGrid.set_occupied(gx, gz, building_id)
TerrainGrid.clear_occupancy(gx, gz)
TerrainGrid.set_cells_occupied(cells: Array[Vector2i], building_id)
TerrainGrid.clear_cells_occupancy(cells: Array[Vector2i])
```

### Terrain Modification

```gdscript
TerrainManager.modify_terrain(center, radius_meters, modifier_callable)
HeightmapStorage.modify_region(center, radius, modifier_callable)
TerrainGrid.set_terrain_type(pos, TerrainTypes.CLEAR)
TerrainGrid.set_vegetation_density(pos, 0.0)
```

---

## Signals Available

| Signal | Emitter | When |
|--------|---------|------|
| `cell_updated(region: Rect2i)` | TerrainGrid | Any cell state change |
| `terrain_ready()` | TerrainManager | Initial load complete |
| `chunk_loaded(coord, is_playable)` | TerrainManager | Chunk streamed in |
| `chunk_unloaded(coord)` | TerrainManager | Chunk streamed out |
| `clearing_started(zone_id, pos)` | ClearingSystem | Zone created |
| `clearing_progress(zone_id, progress)` | ClearingSystem | Work done |
| `clearing_completed(zone_id)` | ClearingSystem | Zone finished |
| `vegetation_updated(region)` | ClearingSystem | Density changed |

---

## Coordinate System (GridCoords)

**Critical constants - DO NOT CHANGE:**
- `BASE_CELL_SIZE = 2.0m` - Heightmap precision
- `GAMEPLAY_CELL_SIZE = 4.0m` - Terrain type, clearing, occupancy
- `SPATIAL_CELL_SIZE = 20.0m` - Unit spatial hashing
- `FOOTPRINT_CELL_SIZE = 2.0m` - Building placement precision

**Conversion methods:**
```gdscript
GridCoords.world_to_gameplay(pos) -> GridResult  # Safe with error
GridCoords.world_to_gameplay_clamped(pos) -> Vector2i  # Always valid
GridCoords.gameplay_to_world(grid_pos) -> Vector3  # Cell center
GridCoords.is_in_bounds(pos) -> bool
```

---

## Gap Analysis: What Construction Needs vs What Exists

### Already Covered (No Work Needed)

| Construction Need | Existing Method |
|-------------------|-----------------|
| Can I build here? | `TerrainGrid.validate_footprint()` |
| What's blocking? | `validate_footprint().blocking_cells` |
| What needs clearing? | `validate_footprint().required_clearing` |
| Height to snap to? | `validate_footprint().average_elevation` |
| Is slope too steep? | `validate_footprint().max_slope` |
| Register building footprint | `TerrainGrid.set_cells_occupied()` |
| Unregister when destroyed | `TerrainGrid.clear_cells_occupancy()` |
| Check if cleared | `TerrainGrid.is_position_cleared()` |

### Minor Gaps (Nice to Have)

| Gap | Description | Priority |
|-----|-------------|----------|
| Build cost estimation | Calculate supply/time from terrain difficulty | LOW |
| Adjacency queries | Find nearby buildings | LOW |
| Connectivity checking | Road/supply route validation | PHASE 11 |

### Not Gaps (Construction Should Not Do This)

| False Gap | Why It's Not a Gap |
|-----------|-------------------|
| Store clearing state | TerrainGrid owns this |
| Track building positions | TerrainGrid.occupancy owns this |
| Query vegetation directly | Use TerrainGrid.get_vegetation_density() |
| Modify heights directly | Use TerrainManager.modify_terrain() |

---

## Recommended Integration Pattern

### For PlacementController

```gdscript
# Current (scattered checks):
var height = terrain_manager.get_height_at(pos)
var cleared = clearing_system.is_position_cleared(pos)
var occupied = _check_building_collision(pos)
var slope = _calculate_slope(pos)

# Recommended (single query):
var result = terrain_grid.validate_footprint(pos, footprint_size, building_type)
if result.valid:
    # Place building
else:
    # Show blocking_cells as red indicators
```

### For ConstructionManager

```gdscript
# When building is placed:
terrain_grid.set_cells_occupied(result.cells, building_id)

# When building is destroyed:
terrain_grid.clear_cells_occupancy(building.footprint_cells)
```

### For JobSystem (Clearing Jobs)

```gdscript
# Get what needs clearing:
var needs_clearing = terrain_grid.validate_footprint(pos, size).required_clearing

# After clearing work complete:
terrain_grid.set_clearing_stage_area(center, radius, ClearingState.Stage.CLEARED)
```

---

## War Room Gate

**Capability inventory: COMPLETE**

Key findings:
1. TerrainGrid already provides everything construction needs
2. `validate_footprint()` is the gateway method - use it
3. No new terrain methods needed for basic construction
4. Phase 11 (TerrainSpline) will add connectivity queries

**Recommendation:** Skip Step 4 (Design TerrainQuery interface) - the interface already exists as TerrainGrid. Proceed directly to Step 5/6 (Migrate PlacementController to use TerrainGrid.validate_footprint()).

---

*War Room Gate: PASSED - Gap list clear, TerrainGrid is ready*
