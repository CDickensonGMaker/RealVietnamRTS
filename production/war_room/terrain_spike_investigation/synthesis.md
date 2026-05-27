# WAR ROOM SYNTHESIS: Terrain Spike Root Cause & Refactoring Plan

**Session Date**: 2026-05-26
**Status**: INVESTIGATION COMPLETE - REFACTOR PROPOSED
**Arbiter**: The Arbiter of RealVietnamRTS

---

## THE DECREE

After exhaustive code audit, the Council has identified the **true root cause** of terrain spikes: **architectural data fragmentation**. The fix requires a structural refactor, not a point fix.

---

## KEY DISCOVERY: The Unclamped Code Is Dead

Our audit found that **no game code calls `TerrainEngine.modify_region()`**:

| System | API Used | Status |
|--------|----------|--------|
| damage_system.gd | `terrain_manager.modify_terrain()` | ✓ Safe |
| clearing_system.gd | `terrain_manager.modify_terrain()` | ✓ Safe |
| engineering_system.gd | `terrain_manager.modify_terrain()` | ✓ Safe |
| terrain_flattening.gd | `terrain.modify_terrain()` | ✓ Safe |
| job_terrain.gd | `terrain.modify_terrain()` | ✓ Safe |
| TerrainEngine.modify_region() | **Never called by game** | N/A |

All modification paths go through HeightmapStorage.modify_region(), which HAS clamping.

---

## TRUE ROOT CAUSE: Data Fragmentation

The spikes occur because **4 different arrays hold elevation data** that can desync:

```
TerrainEngine.heightmap_data     (9.4 MB) - Generation output, NEVER UPDATED after copy
HeightmapStorage.data            (9.4 MB) - Working copy, receives all modifications
TerrainGrid._elevation           (2.3 MB) - Cached sampling, syncs on modify
UnifiedTerrain._elevation        (2.3 MB) - Cached sampling, syncs on modify
```

**The Bug**: `terrain_mesh.gd:164` reads from `TerrainEngine.heightmap_data`:
```gdscript
var data: PackedFloat32Array = terrain_engine.heightmap_data
```

This is stale after any terrain modification. While the RTS uses chunks (which read from HeightmapStorage), any code path that touches TerrainEngine directly sees pre-modification data.

### Data Flow Problem

```
GENERATION:
TerrainEngine.generate() → fills heightmap_data
    └── terrain_manager copies: heightmap.data = heightmap_data.duplicate()

MODIFICATION:
Any system → terrain_manager.modify_terrain() → HeightmapStorage.modify_region()
    └── TerrainEngine.heightmap_data is NEVER UPDATED
    └── Now desynced permanently!

QUERIES:
- terrain_chunk.gd → HeightmapStorage.extract_region() ✓ CORRECT
- terrain_mesh.gd → TerrainEngine.heightmap_data ✗ STALE
- Some edge cases may hit wrong source
```

---

## PROPOSED REFACTOR

### Architecture: Before and After

**BEFORE (Current - Fragmented)**
```
7 Terrain Autoloads:
  TerrainEngine, DamageSystem, ClearingSystem, UnifiedTerrain,
  TerrainIntegration, TerrainClearingSystem, TerrainFlattening

4 Elevation Data Stores:
  TerrainEngine.heightmap_data, HeightmapStorage.data,
  TerrainGrid._elevation, UnifiedTerrain._elevation

5 Height Query APIs, 4 Modification APIs
```

**AFTER (Proposed - Unified)**
```
4 Terrain Autoloads:
  TerrainManager (orchestrator), DamageSystem, ClearingSystem, TerrainFlattening

1 Elevation Data Store:
  HeightmapStorage.data (THE single source of truth)

1 Height Query API, 1 Modification API (through TerrainManager)
```

### Key Changes

1. **HeightmapStorage becomes THE source** - all reads/writes go here
2. **TerrainEngine becomes stateless generator** - generates once, hands off data, done
3. **Merge TerrainGrid + UnifiedTerrain → GameplayGrid** - one grid for RTS queries
4. **Absorb TerrainIntegration into TerrainManager** - single orchestrator
5. **Clear TerrainEngine.heightmap_data after copy** - prevent stale reads

### Migration Phases

| Phase | Tasks | Duration |
|-------|-------|----------|
| 1. Consolidate Data | Clear heightmap_data after copy, redirect reads | 2-4 hours |
| 2. Merge Grids | Combine TerrainGrid + UnifiedTerrain into GameplayGrid | 4-6 hours |
| 3. Simplify Orchestration | Absorb TerrainIntegration into TerrainManager | 2-4 hours |
| 4. Cleanup | Remove deprecated files, update autoloads | 2-3 hours |

**Total: 2-3 days**

---

## IMMEDIATE ACTIONS (Pre-Refactor)

While planning the refactor, apply these hotfixes to stop active bleeding:

### Hotfix 1: Clear Stale Data
```gdscript
# terrain_manager.gd line 142-143
heightmap.data = terrain_generator.heightmap_data.duplicate()
terrain_generator.heightmap_data.clear()  # ADD THIS LINE
```

### Hotfix 2: Guard terrain_mesh.gd
```gdscript
# terrain_mesh.gd line 63-66
if terrain_engine.heightmap_data.size() == 0:
    push_warning("[TerrainMesh] heightmap_data is empty - use HeightmapStorage instead")
    _make_simple_plane()
    return
```

### Hotfix 3: Add Clamping Everywhere (Belt and Suspenders)
Add clamping to `TerrainEngine.modify_region()` even though it's not called - prevents future bugs:
```gdscript
# terrain_engine.gd line 754
heightmap_data[idx] = clampf(modifier.call(heightmap_data[idx], falloff), 0.0, 1.0)
```

---

## SUCCESS CRITERIA

After refactor completion:

- [ ] Only ONE array holds elevation data (HeightmapStorage.data)
- [ ] All height queries return consistent results
- [ ] All modifications go through one path
- [ ] No NaN, Inf, or out-of-range values possible
- [ ] Autoload count reduced from 7 to 4
- [ ] No terrain spikes under any test scenario
- [ ] 60 FPS maintained with 300+ units
- [ ] All existing tests pass (clearing_test.gd, test_combined.gd)

---

## PILLAR ALIGNMENT

| Pillar | Impact |
|--------|--------|
| **Carve the Map** | CRITICAL - Terrain is the foundation of gameplay |
| **Network of Firebases** | HIGH - Buildings need stable terrain |
| **Physical Supply Chains** | HIGH - Vehicles need accurate height queries |
| **Doctrine Over Spam** | Low |
| **The War Continues** | MEDIUM - Persistent terrain damage must be reliable |

**Verdict**: This refactor serves 4 of 5 pillars. Proceed.

---

## DOCUMENTS CREATED

| Document | Purpose |
|----------|---------|
| `briefing.md` | Initial investigation brief |
| `comparison_matrix.md` | Full TerrainEngine vs RTS comparison |
| `analysis/systems_designer.md` | Data flow analysis |
| `analysis/technical_director.md` | Architecture analysis |
| `analysis/devils_advocate.md` | Edge cases and assumptions |
| `analysis/refactor_proposal.md` | **Detailed refactoring plan** |
| `synthesis.md` | This document - final decree |
| `current_session.md` | Session summary |

---

## THE ARBITER'S JUDGMENT

The terrain spike problem is not a bug - it's **architectural debt**. The system grew organically with multiple overlapping solutions, each adding complexity without removing the old.

**The Council recommends**:
1. Apply hotfixes immediately (1 hour)
2. Begin refactoring this sprint (2-3 days)
3. The payoff is high: simpler code, fewer bugs, easier debugging

**The Summoner holds final authority.** Approve to proceed with implementation.

---

*The Council has spoken. May your terrain be flat where needed and mountainous where desired.*
