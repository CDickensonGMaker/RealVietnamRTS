# WAR ROOM BRIEFING
**Query:** VegetationManager Synchronous Loading Causes Game Freeze
**Date:** 2026-05-25
**Summoner:** User
**Priority:** CRITICAL (blocks all playtesting)

---

## THE PROBLEM

The game freezes/becomes non-responsive when loading the main scene. Debug output shows VegetationManager processing chunks in a tight synchronous loop:

```
[VegetationManager] Chunk (0, 0): 762 trees materialized
[VegetationManager] Chunk (1, 0): 894 trees materialized
[VegetationManager] Chunk (2, 0): 928 trees materialized
... (144 chunks total, 500-900 trees each)
```

**Root Cause Chain:**
1. `TerrainManager.load_all_chunks()` iterates all 144 chunks (12x12 for 3000m map)
2. Each chunk calls `vegetation_manager.generate_for_chunk()` synchronously
3. `generate_for_chunk()` does heavy work on main thread:
   - `_build_terrain_from_grid()` - iterates all bundles
   - `_build_placement_cache()` - generates 2000 tree + 3000 grass candidates
   - `_materialize_vegetation()` - creates MultiMesh instances with transform buffers
   - `_materialize_grass()` - more MultiMesh creation

**Total blocking work:** ~144 chunks x ~800 trees x transform calculations = main thread blocked

---

## RELEVANT CODE PATHS

| File | Function | Issue |
|------|----------|-------|
| `terrain_manager.gd:418-424` | `load_all_chunks()` | Tight loop, no yielding |
| `terrain_manager.gd:265` | `_load_chunk()` | Calls vegetation sync |
| `vegetation_manager.gd:262-279` | `generate_for_chunk()` | All work synchronous |
| `vegetation_manager.gd:475-580` | `_materialize_vegetation()` | Heavy transform math |

---

## CONSTRAINTS (from Game Bible)

- **Pillar 1 (Carve the Map):** Vegetation is gameplay-critical - blocks LOS, slows movement
- **Performance target:** 60 FPS with 300-500 units, 3km x 3km maps
- **Anti-pillar:** Not retro - needs smooth loading, professional feel
- **Map size:** 3000m x 3000m is canonical

---

## ARCHITECTS TO SUMMON

| Architect | Domain |
|-----------|--------|
| **technical-director** | Architecture, performance, threading strategy |
| **systems-designer** | How vegetation integrates with gameplay systems |
| **gameplay-programmer** | Implementation approach, GDScript/GDExtension |
| **Devil's Advocate** | Challenge assumptions, find edge cases |

---

## QUESTIONS FOR THE COUNCIL

1. **Loading strategy:** Async coroutines, threading, or chunked-per-frame?
2. **Scope:** Fix VegetationManager only, or broader terrain loading overhaul?
3. **Priority order:** Camera-near chunks first? All chunks equal?
4. **Fallback visuals:** Show loading state or placeholder vegetation?
5. **Performance budget:** How many chunks/trees per frame is acceptable?
