# REFACTOR PROPOSAL: Unified Terrain Architecture

**Author**: The Council of Architects
**Date**: 2026-05-26
**Status**: PROPOSED - Awaiting Approval

---

## Executive Summary

After deep investigation, we discovered that **no game code calls the unclamped `TerrainEngine.modify_region()`**. All systems correctly use `terrain_manager.modify_terrain()`. This means the spikes are architectural, not from a single bug.

The true problem is **data fragmentation**: 4 different arrays hold elevation data, creating sync issues, initialization races, and complexity that masks the real bug.

This proposal defines a **clean, unified terrain architecture** that eliminates redundancy.

---

## INVESTIGATION FINDINGS

### Who Calls What (Actual Code Audit)

| Caller | API Used | Safe? |
|--------|----------|-------|
| damage_system.gd:135 | `terrain_manager.modify_terrain()` | ✓ YES |
| clearing_system.gd:183 | `terrain_manager.modify_terrain()` | ✓ YES |
| engineering_system.gd (9 calls) | `terrain_manager.modify_terrain()` | ✓ YES |
| terrain_flattening.gd:263 | `terrain.modify_terrain()` | ✓ YES |
| job_terrain.gd:75 | `terrain.modify_terrain()` | ✓ YES |
| clearing_test.gd (test only) | `heightmap.modify_region()` | ✓ YES |
| **TerrainEngine.modify_region()** | **NEVER CALLED** | N/A |

**Conclusion**: The unclamped `TerrainEngine.modify_region()` is dead code in the game context.

### Current Data Flow Analysis

```
GENERATION:
TerrainEngine.generate()
    │
    ├── Fills TerrainEngine.heightmap_data (9.4 MB)
    │
    └── terrain_manager copies it:
        heightmap.data = terrain_generator.heightmap_data.duplicate()
            │
            ├── HeightmapStorage.data (9.4 MB) - COPY #1
            │
            ├── TerrainGrid._elevation (2.3 MB) - COPY #2
            │       Built from heightmap.sample_world()
            │
            └── UnifiedTerrain._elevation (2.3 MB) - COPY #3
                    Built from heightmap.sample_world()

QUERY TIME:
    - terrain_mesh.gd reads TerrainEngine.heightmap_data
    - terrain_chunk.gd reads HeightmapStorage via extract_region()
    - RTS systems read TerrainGrid._elevation or UnifiedTerrain._elevation
    - TerrainIntegration.get_height_at() → UnifiedTerrain or terrain_manager

MODIFICATION:
    - All go through HeightmapStorage.modify_region() (safe)
    - TerrainGrid.update_region_from_heightmap() syncs from HeightmapStorage
    - UnifiedTerrain._resync_gameplay_region() syncs from HeightmapStorage
    - But TerrainEngine.heightmap_data is NEVER updated after generation!
```

### The Real Bug: Stale Data

After terrain generation:
1. `TerrainEngine.heightmap_data` = original generated data
2. `HeightmapStorage.data` = copy, modified by craters/clearing
3. These diverge permanently!

If anything reads from `TerrainEngine` instead of `HeightmapStorage`, it sees stale pre-modification data.

**Evidence**: `terrain_mesh.gd:164` reads from `TerrainEngine.heightmap_data`:
```gdscript
var data: PackedFloat32Array = terrain_engine.heightmap_data
```

This is likely used in the TerrainEngine standalone project but causes issues in RTS.

---

## PROPOSED ARCHITECTURE

### Design Principles

1. **Single Source of Truth**: ONE array holds elevation data
2. **Clear Ownership**: One system writes, others read
3. **Explicit Dependencies**: No hidden coupling via autoloads
4. **Minimal Copies**: Derived data computed on-demand, not cached
5. **Fail-Fast**: Invalid operations throw errors, not silent fallbacks

### New Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    TERRAIN SYSTEM (Simplified)                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   HeightmapStorage                        │   │
│  │  (THE SINGLE SOURCE OF TRUTH)                             │   │
│  │                                                           │   │
│  │  • data: PackedFloat32Array (normalized 0-1)              │   │
│  │  • height_scale: float (280.0)                            │   │
│  │  • sample_world(x, z) → float (meters)                    │   │
│  │  • modify_region(center, radius, modifier) → Rect2i       │   │
│  │  • extract_region(x, z, size) → PackedFloat32Array        │   │
│  │  • All reads/writes go here                               │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│              ┌───────────────┼───────────────┐                   │
│              │               │               │                   │
│              ▼               ▼               ▼                   │
│  ┌──────────────────┐ ┌─────────────┐ ┌──────────────────────┐  │
│  │ TerrainGenerator │ │TerrainChunks│ │    GameplayGrid      │  │
│  │ (was TerrainEngine)│ │ (streaming) │ │ (was TerrainGrid +   │  │
│  │                  │ │             │ │  UnifiedTerrain)     │  │
│  │ • generate()     │ │ • build_mesh│ │                      │  │
│  │ • Returns data   │ │ • LOD       │ │ • clearing_stage[]   │  │
│  │ • NO storage     │ │ • collision │ │ • terrain_type[]     │  │
│  │ • Fire and forget│ │             │ │ • occupancy[]        │  │
│  └──────────────────┘ └─────────────┘ │ • is_passable()      │  │
│                                       │ • is_buildable()     │  │
│                                       │ • get_cover()        │  │
│                                       │ • grid_to_world()    │  │
│                                       └──────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   TerrainManager                          │   │
│  │  (Orchestrator - replaces TerrainIntegration)             │   │
│  │                                                           │   │
│  │  • Holds HeightmapStorage                                 │   │
│  │  • Holds GameplayGrid                                     │   │
│  │  • Manages chunk streaming                                │   │
│  │  • Public API for all terrain operations                  │   │
│  │  • Signals: terrain_ready, terrain_modified               │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Files to Keep (Refactored)

| Current File | New Role | Changes |
|--------------|----------|---------|
| heightmap_storage.gd | **THE Source** | Add any missing APIs |
| terrain_manager.gd | **Orchestrator** | Absorb TerrainIntegration duties |
| terrain_chunk.gd | Chunk rendering | Unchanged |
| terrain_grid.gd | **GameplayGrid** | Merge with UnifiedTerrain |

### Files to Remove/Deprecate

| File | Reason |
|------|--------|
| terrain_engine.gd | Becomes stateless generator, or removed entirely |
| unified_terrain_engine.gd | Merged into GameplayGrid |
| terrain_integration.gd | Absorbed by TerrainManager |
| terrain_mesh.gd | Only used in standalone lab |

### Autoloads After Refactor

**Before (7 terrain autoloads):**
```
TerrainEngine
DamageSystem
ClearingSystem
UnifiedTerrain
TerrainIntegration
TerrainClearingSystem
TerrainFlattening
```

**After (4 terrain autoloads):**
```
TerrainManager       # Orchestrates everything
DamageSystem         # Calls TerrainManager.modify_terrain()
ClearingSystem       # Calls TerrainManager.modify_terrain()
TerrainFlattening    # Calls TerrainManager.modify_terrain()
```

---

## MIGRATION PLAN

### Phase 1: Consolidate Data (Day 1)

1. **Delete TerrainEngine.heightmap_data after copy**
   ```gdscript
   # terrain_manager.gd
   heightmap.data = terrain_generator.heightmap_data.duplicate()
   terrain_generator.heightmap_data.clear()  # ADD THIS
   ```

2. **Make HeightmapStorage the only place to read elevation**
   - Update any code reading `TerrainEngine.heightmap_data` to use `heightmap.data`

### Phase 2: Merge Grids (Day 1-2)

3. **Merge UnifiedTerrain into TerrainGrid**
   - Copy `grid_to_world()` with Y values from UnifiedTerrain
   - Add `modify_terrain()` wrapper that syncs after modification
   - Rename to `GameplayGrid`

4. **Update all consumers**
   - Change `UnifiedTerrain` references to `GameplayGrid`
   - Update TerrainIntegration to use single grid

### Phase 3: Simplify Orchestration (Day 2)

5. **Absorb TerrainIntegration into TerrainManager**
   - Move signal connections
   - Move vegetation/billboard references
   - Remove TerrainIntegration autoload

6. **Make TerrainEngine stateless or remove**
   - Remove `heightmap_data` storage
   - Return data from `generate()` instead of storing
   - Or inline the generation into TerrainManager

### Phase 4: Cleanup (Day 2-3)

7. **Update autoloads in project.godot**
8. **Delete deprecated files**
9. **Run full test suite**
10. **Update CLAUDE.md documentation**

---

## API CHANGES

### Before (Multiple Overlapping APIs)

```gdscript
# 5 different ways to get height:
TerrainEngine.get_height_at(pos)
HeightmapStorage.sample_world(x, z)
TerrainGrid.get_elevation(pos)
UnifiedTerrain.get_height_at(pos)
TerrainIntegration.get_height_at(pos)

# 4 different ways to modify:
TerrainEngine.modify_region(center, radius, modifier)  # Unclamped, unused
HeightmapStorage.modify_region(center, radius, modifier)  # Clamped
terrain_manager.modify_terrain(center, radius, modifier)  # Wrapper
UnifiedTerrain.modify_terrain(center, radius, modifier)  # Wrapper
```

### After (One Clear API)

```gdscript
# TerrainManager is the single entry point:
TerrainManager.get_height_at(pos) → float
TerrainManager.get_normal_at(pos) → Vector3
TerrainManager.modify_terrain(center, radius, modifier) → Rect2i

# GameplayGrid for RTS queries:
TerrainManager.grid.get_terrain_type(pos) → int
TerrainManager.grid.get_clearing_stage(pos) → int
TerrainManager.grid.is_passable(pos) → bool
TerrainManager.grid.is_buildable(pos) → bool
TerrainManager.grid.grid_to_world(coord) → Vector3  # WITH proper Y
```

---

## RISK ASSESSMENT

| Risk | Mitigation |
|------|------------|
| Breaking existing scenes | Provide compatibility shims during transition |
| Test coverage gaps | Run clearing_test.gd, test_combined.gd after each phase |
| Performance regression | Profile before/after, GameplayGrid caches are still valid |
| Autoload order issues | Carefully sequence new autoload dependencies |

---

## SUCCESS CRITERIA

After refactor, these properties should hold:

- [ ] Only ONE PackedFloat32Array holds elevation data
- [ ] All height queries return consistent results
- [ ] All modifications go through HeightmapStorage.modify_region()
- [ ] No NaN, Inf, or out-of-range values possible
- [ ] Autoload count reduced from 7 to 4
- [ ] No terrain spikes under any test scenario
- [ ] 60 FPS maintained with 300+ units
- [ ] All existing tests pass

---

## APPROVAL REQUEST

**Arbiter Recommendation**: PROCEED with this refactor.

The current architecture has technical debt that creates recurring bugs. This refactor:
1. Eliminates the root cause of data desync
2. Simplifies the codebase significantly
3. Makes future debugging easier
4. Aligns with the Pillar: "Carve the Map" requires stable terrain

**Estimated Effort**: 2-3 days focused work
**Risk Level**: Medium (contained to terrain system)
**Payoff**: High (eliminates entire class of bugs)

---

*The Council recommends execution. Awaiting Summoner approval.*
