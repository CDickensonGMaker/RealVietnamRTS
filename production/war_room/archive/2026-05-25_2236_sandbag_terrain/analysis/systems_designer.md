# Systems Designer Analysis: VegetationManager Loading Problem

**Analyst:** Systems Designer
**Date:** 2026-05-25
**Focus:** Gameplay system integration and pillar alignment

---

## Executive Summary

The VegetationManager loading freeze is not just a performance problem - it is a **gameplay correctness problem**. Vegetation in RealVietnamRTS is a first-class gameplay entity that gates movement, blocks line-of-sight, and represents the core challenge of Pillar 1 (Carve the Map). Progressive loading creates temporal windows where gameplay systems may query terrain that does not yet have authoritative vegetation state.

---

## Vegetation as Gameplay Entity

The `TYPE_PROPS` constant in VegetationManager (lines 32-42) reveals vegetation is not decoration:

| Terrain Type | Blocks LOS | Move Speed | Gameplay Role |
|--------------|------------|------------|---------------|
| CLEAR | No | 1.0 | Safe maneuver space |
| RICE_PADDY | No | 0.4 | Deadly open ground with mobility penalty |
| GRASSLAND | No | 0.95 | Near-clear, minimal cover |
| LIGHT_JUNGLE | No | 0.8 | Concealment without hard cover |
| MEDIUM_JUNGLE | **Yes** | 0.5 | Hard LOS blocker, significant slow |
| HEAVY_JUNGLE | **Yes** | 0.3 | Impassable to vehicles, infantry crawl |

These values directly feed:
1. **CoverSystem** - Units in heavy jungle receive massive cover bonus
2. **PathfindingSystem** - Movement cost calculations
3. **LOSSystem** - Whether units can see/shoot through a cell
4. **ClearingSystem** - Work required to clear vegetation
5. **AIDirector** - VC spawn/ambush position evaluation

---

## The Temporal Correctness Problem

If vegetation loads progressively, gameplay systems face three possible states for any query:

### State 1: Chunk Not Loaded
- `blocks_los()` returns `false` (line 698-699: returns false if chunk not in `_chunk_terrain`)
- `get_movement_multiplier_at()` falls through to TerrainGrid or returns 1.0
- Units may path through what will become heavy jungle
- LOS calculations will show clear sightlines that do not exist

### State 2: TerrainGrid Loaded, VegetationManager Not
- TerrainGrid is the "single source of truth" (lines 86-87, 121-123)
- If TerrainGrid loads before VegetationManager generates visuals, **gameplay is correct but visuals are wrong**
- This is acceptable temporarily

### State 3: Fully Loaded
- Both data and visuals match
- This is the only correct state for active gameplay

**Critical Finding:** The VegetationManager queries TerrainGrid when available (lines 688-690, 720-722, 749-752, 764-766). If TerrainGrid is the authoritative source and loads synchronously with terrain chunks, then VegetationManager's visual generation can be deferred without breaking gameplay correctness.

---

## Priority Analysis: Which Chunks Matter?

### Priority 1: Near Units (CRITICAL)
Any chunk containing or adjacent to player/enemy units MUST have authoritative vegetation data.
- Movement orders require accurate pathfinding costs
- Combat requires accurate LOS/cover
- **Tolerance for visual lag:** 0-2 frames (imperceptible)
- **Tolerance for data lag:** ZERO

### Priority 2: Near Firebases (HIGH)
Firebase construction zones and fire sectors need correct vegetation.
- Building placement validation
- Defensive fire arcs
- **Tolerance for visual lag:** 1-3 seconds
- **Tolerance for data lag:** ZERO (construction must query)

### Priority 3: Near Camera (MEDIUM)
What the player is looking at should look correct.
- Player perception
- Strategic planning
- **Tolerance for visual lag:** 1-5 seconds (acceptable if clearly loading)
- **Tolerance for data lag:** High (camera position != unit position)

### Priority 4: Beyond Fog of War (LOW)
Areas player cannot see or interact with.
- Precomputation for future reveals
- **Tolerance for visual lag:** Unlimited
- **Tolerance for data lag:** Until revealed

---

## Impact on Pillar 1: Carve the Map

### The Core Loop
1. Player sees opaque jungle
2. Player orders engineer/bulldozer to clear
3. Jungle transitions through states (JUNGLE -> PARTIALLY_CLEARED -> CLEARED)
4. New terrain becomes traversable, visible

### Loading Implications

**Scenario A: Player orders clearing before chunk loads**
- ClearingSystem queries terrain type at target position
- If vegetation data not loaded, query returns CLEAR (default)
- System may reject valid clear order ("nothing to clear") or accept invalid order
- **This breaks Pillar 1**

**Scenario B: Player can see chunk but visuals not generated**
- Player sees empty terrain where dense jungle exists
- Player makes strategic decisions based on incorrect information
- Units pathed through "empty" space will slow when visuals appear
- **This breaks player trust**

**Scenario C: Chunk loads, then clearing happens, then visual regeneration queued**
- `regenerate_chunk()` (line 364-374) re-reads TerrainGrid and re-materializes
- If regeneration is deferred/queued, player sees stale vegetation
- **Acceptable if delay is <1 second**

---

## System Integration Requirements

### For Progressive Loading to Work

1. **TerrainGrid must load synchronously with terrain mesh**
   - VegetationManager can query TerrainGrid for gameplay data
   - Visual generation can be deferred

2. **Gameplay queries must not touch `_chunk_terrain` directly**
   - `blocks_los()`, `get_movement_multiplier_at()`, `get_density_at()` already prefer TerrainGrid
   - Verify all gameplay systems use these APIs, not direct terrain access

3. **Clearing operations must trigger immediate visual updates**
   - `regenerate_chunk()` cannot be deferred when player is actively clearing
   - Priority queue: cleared chunks > camera chunks > distant chunks

4. **Combat systems need "vegetation loaded" guard**
   - If a firefight begins in an unloaded chunk, materialize immediately
   - Combat query: "give me vegetation state at these 10 positions" - all must be authoritative

---

## Recommendations for Progressive Loading

### Tier 1: Guaranteed Synchronous
- All chunks containing player units
- All chunks containing visible enemy units
- All chunks within firebase perimeter
- All chunks being actively cleared

### Tier 2: High Priority Async
- Chunks adjacent to Tier 1 chunks
- Chunks visible to player camera within 500m

### Tier 3: Background Async
- All other chunks
- Budget: 2-4 chunks per frame
- Can be interrupted by Tier 1/2 requests

### Fallback Behavior
When a gameplay system queries an unloaded chunk:
1. Check TerrainGrid first (should always have data)
2. If TerrainGrid unavailable, use conservative defaults (HEAVY_JUNGLE)
3. Log warning for debugging
4. Trigger priority load of that chunk

---

## Questions for Technical Director

1. **Does TerrainGrid load with terrain mesh or separately?**
   - If synchronous: We can safely defer visual generation
   - If separate: Need to identify TerrainGrid loading boundary

2. **What is the call order on chunk load?**
   - Is `generate_for_chunk()` called from `_load_chunk()` or elsewhere?
   - Can we intercept and defer only the materialization pass?

3. **Is there a message/event when player issues movement order?**
   - If so, we can prioritize loading destination chunk path

4. **How does ClearingSystem handle chunk boundaries?**
   - A clear operation may span multiple chunks
   - All affected chunks need simultaneous regeneration

---

## Conclusion

Progressive vegetation loading is **viable** for visuals but **not viable** for gameplay data. The architecture already supports this split via TerrainGrid as the authoritative data source. The solution should:

1. Keep TerrainGrid (data) loading synchronous with terrain
2. Make VegetationManager (visuals) loading progressive
3. Implement priority tiers based on gameplay activity
4. Never defer regeneration for actively-changing terrain

This preserves Pillar 1 (map must be legible for carving) while allowing smooth loading.
