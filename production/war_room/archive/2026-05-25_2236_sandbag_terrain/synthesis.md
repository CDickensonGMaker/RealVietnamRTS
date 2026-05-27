# THE DECREE: VegetationManager Async Loading

**Date:** 2026-05-25
**Arbiter:** War Room Council
**Status:** READY FOR SUMMONER APPROVAL

---

## THE COUNCIL'S JUDGMENT

### Points of Agreement

All Architects agree:
1. The current synchronous loop is unacceptable (2-4 second freeze)
2. TerrainManager's `_process_rebuild_queue()` pattern is the correct model
3. Time-budgeted frame processing is preferred over threading
4. Vegetation DATA (TerrainGrid) must load synchronously; VISUALS can defer

### The Central Tension

**Devil's Advocate** raises a valid scope concern: The Game Bible allows 1.4km maps for MVP. Smaller maps sidestep this problem entirely. A loading screen is simpler and ships faster.

**However:** The Summoner explicitly requested addressing "the core problem." The 3km map is the canonical target. The fix benefits all map sizes and establishes the correct architecture for streaming.

**The Arbiter's Resolution:** Implement async loading, but with a **scope-disciplined approach** - minimal complexity, no threading, loading screen as fallback.

---

## THE DECREE

### What We Will Build

**Time-Budgeted Queue System** in VegetationManager:

```
TerrainManager._load_chunk()
  ├── Creates terrain mesh (immediate, fast)
  ├── TerrainGrid updated (immediate, gameplay-authoritative)
  └── vegetation_manager.queue_vegetation() (deferred)

VegetationManager._process()
  └── _process_vegetation_queue()
      ├── Budget: 4ms for generation, 4ms for materialization
      ├── Stages: TERRAIN → CACHE → TREES → GRASS → COMPLETE
      └── Emits: chunk_vegetation_ready(coord)
```

### What We Will NOT Build (Phase 1)

- ❌ Threading (complexity not justified)
- ❌ Camera-priority queue (adds edge cases)
- ❌ Placeholder visuals (adds visual system coupling)
- ❌ LRU vegetation cache (premature optimization)

### The Tradeoffs We Accept

| Sacrifice | Justification |
|-----------|---------------|
| 15-20 seconds progressive load | Player can start immediately; far terrain loads in background |
| Visible tree pop-in | Acceptable for development; can add placeholder in polish phase |
| No camera priority | Simplifies implementation; all chunks equal for Phase 1 |
| Gameplay queries before visuals | TerrainGrid is authoritative; gameplay correct even without visuals |

---

## IMPLEMENTATION PLAN

### Phase 1: Core Async Infrastructure (2-3 hours)

**File:** `vegetation_manager.gd`

1. Add queue and state tracking:
```gdscript
var _vegetation_queue: Array[Dictionary] = []
const GENERATION_BUDGET_MS := 4.0
const MATERIALIZE_BUDGET_MS := 4.0
signal chunk_vegetation_ready(coord: Vector2i)
```

2. Convert `generate_for_chunk()` to queue work:
```gdscript
func generate_for_chunk(coord: Vector2i, heightmap: Object, chunk_size: float) -> void:
    clear_chunk_visuals(coord)
    if _meshes.is_empty():
        return
    _vegetation_queue.append({
        "coord": coord,
        "heightmap": heightmap,
        "chunk_size": chunk_size,
        "stage": "terrain",
        "tree_cursor": 0,
        "grass_cursor": 0
    })
```

3. Add `_process()` with time-budgeted queue processing

4. Split materialization into incremental steps with cursor tracking

### Phase 2: Integration Test (30 min)

- Run main scene, verify no freeze
- Verify all 144 chunks eventually populate
- Verify gameplay systems work (clearing, LOS)

### Phase 3: Polish (Optional, Post-MVP)

- Camera-priority loading
- Placeholder visuals
- Progress indicator in HUD

---

## FALLBACK STRATEGY

If async loading proves unstable:

1. **Immediate fallback:** Revert to sync loading + 3-5 second loading screen
2. **Map size fallback:** Default to 1.4km maps for MVP per Game Bible D-902
3. **Per-scene fallback:** Use test_arena.tscn approach (256m) for development

---

## PILLAR COMPLIANCE

| Pillar | Impact | Mitigation |
|--------|--------|------------|
| **Carve the Map** | TerrainGrid (data) loads sync | Gameplay always correct |
| **Network of Firebases** | Firebase queries use TerrainGrid | No impact |
| **Physical Supply Chains** | Pathfinding uses TerrainGrid | No impact |
| **Doctrine Over Spam** | N/A | N/A |
| **The War Continues** | Automation queries TerrainGrid | No impact |

**Verdict:** No pillar violations. Visuals are deferred, not gameplay.

---

## THE LAWS APPLIED

1. **No decree may violate a project Pillar** ✓ TerrainGrid remains sync
2. **Tradeoffs must be named** ✓ See table above
3. **The Summoner holds final authority** ✓ Awaiting approval
4. **All deliberations are archived** ✓ See analysis/ folder

---

## RECOMMENDED ACTION

**Approve this decree and proceed with Phase 1 implementation.**

Estimated time: 2-3 hours for core async, 30 min for testing.

The Devil's Advocate's concerns are valid but addressed:
- Loading screen remains as fallback
- Scope is minimal (no threading, no priorities)
- Architecture supports future improvements without blocking MVP

---

*The Council has spoken. The Summoner decides.*
