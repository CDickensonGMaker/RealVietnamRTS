# Construction & Vegetation Fix Plan

**Created:** 2026-05-26
**Status:** PLANNING

---

## Issues Identified

1. **Double lines when painting** - Getting two visual lines instead of one during drag-paint
2. **Riflemen building sandbags** - Only engineers should construct buildings
3. **Bulldozers waiting for engineers** - Bulldozers not picking up jobs until engineers start
4. **2D/3D tree hybrid not loading right** - Billboard LOD system causing visual issues
5. **Want 3D trees only** - Remove billboard trees, use actual 3D tree models
6. **Jungle coverage too dense** - Not every inch needs trees
7. **Need realistic layouts** - Study actual Vietnam combat zones for reference

---

## PHASE 1: Fix Double Line Visual Bug

**Objective:** Single preview line during drag-paint

### Investigation
- Check `_update_segment_markers()` in `placement_controller.gd`
- Check if both ghost AND segment markers are rendering
- Check `blueprint_ghost.gd` linear preview rendering

### Likely Cause
The blueprint ghost shows one line, and segment markers show another. Need to consolidate to single visual.

### Fix
- Either hide ghost during linear placement and only show segment markers
- OR hide segment markers and only show ghost with multiple instances

### Success Criteria
- [ ] Single line of preview models when drag-painting sandbags

---

## PHASE 2: Fix Job Assignment (Engineers Only Build)

**Objective:** Only engineers can build structures, not riflemen

### Investigation
- Check `can_worker_do_job()` in `job_system.gd`
- Check worker class detection in `worker_controller.gd`
- Verify squad data has correct `worker_class` assignments

### Root Cause Analysis
- BUILD_STRUCTURE jobs should only be assignable to `worker_class == "engineer"`
- Check if riflemen are being misidentified as engineers

### Fix
- Verify worker_class is correctly set in all squad data files
- Ensure `can_worker_do_job()` properly filters by class

### Success Criteria
- [ ] Riflemen ignore BUILD_STRUCTURE jobs
- [ ] Only engineers walk to construction sites

---

## PHASE 3: Fix Bulldozer Job Priority

**Objective:** Bulldozers pick up clearing/flattening jobs independently

### Investigation
- Check job priority for CLEAR_TERRAIN and FLATTEN_AREA jobs
- Check if bulldozers are being blocked by prerequisites
- Check worker assignment radius and job discovery

### Likely Causes
1. Jobs not being visible to bulldozers (spatial index issue)
2. Job priority too low for bulldozers to pick up
3. Prerequisite chain blocking bulldozer assignment

### Fix
- Ensure CLEAR_TERRAIN jobs have appropriate priority
- Check that bulldozers can see jobs within their work radius
- Verify job state transitions don't block bulldozer assignment

### Success Criteria
- [ ] Bulldozers independently pick up clearing jobs
- [ ] Bulldozers work simultaneously with engineers (not after)

---

## PHASE 4: Remove Billboard Trees (2D LOD System)

**Objective:** Disable billboard tree rendering, use 3D models only

### Files to Modify
- `terrain/systems/vegetation_lod_manager.gd` - Disable billboard rendering
- `terrain/systems/billboard_tree_renderer.gd` - May need to disable entirely
- `terrain/core/vegetation_chunk.gd` - Stop spawning billboards

### Approach
- Add flag to disable billboard trees globally
- Keep 3D tree spawning intact
- Adjust LOD distances if needed

### Success Criteria
- [ ] No 2D billboard trees visible at any distance
- [ ] 3D tree models render at all distances
- [ ] No visual popping or LOD issues

---

## PHASE 5: Implement Realistic Jungle Distribution

**Objective:** Varied jungle density based on real Vietnam terrain

### Research Required
- Study satellite/aerial photos of key Vietnam battlefields:
  - Ia Drang Valley (1965) - Highland jungle
  - Khe Sanh (1968) - Mountain jungle with clearings
  - A Shau Valley - Triple-canopy jungle
  - Mekong Delta - Rice paddies with tree lines
  - Cu Chi - Plantation rubber trees in rows

### Terrain Zones to Model
| Zone | Tree Density | Tree Types | Notes |
|------|--------------|------------|-------|
| Triple-canopy jungle | 80-95% | Mixed hardwoods, dense undergrowth | A Shau, border areas |
| Secondary jungle | 50-70% | Regrowth, bamboo groves | Abandoned farmland |
| Plantation/rubber | 40-60% | Uniform rows | French plantations |
| Highland | 30-50% | Scattered pines, grassland | Central Highlands |
| River/delta | 10-30% | Tree lines along water, open paddies | Mekong |
| Cleared/firebase | 0-10% | Stumps, few trees | Defensive perimeters |

### Implementation
1. Add terrain type to vegetation density mapping
2. Create density noise maps for natural variation
3. Add clearing gradients around roads and firebases

---

## PHASE 6: Create Reference Maps from Real Locations

**Objective:** Base map layouts on actual Vietnam geography

### Target Locations for Study
1. **Ia Drang - LZ X-Ray** (Nov 1965)
   - Open clearing surrounded by jungle
   - Dry creek bed (Drang River)
   - Termite mounds providing cover

2. **Khe Sanh Combat Base** (Jan-Apr 1968)
   - Hilltop plateau
   - Surrounding hills with jungle
   - Clear firing lanes

3. **Hamburger Hill (Ap Bia)** (May 1969)
   - Steep jungle slopes
   - Ridge line combat
   - Cleared LZs on lower slopes

4. **Cu Chi District**
   - Rubber plantations (gridded trees)
   - Rice paddies
   - Village clusters
   - Tunnel networks

### Deliverables
- Reference image collection per location
- Terrain feature notes (elevation, water, vegetation)
- Map generator presets for each terrain type

---

## PHASE 7: Update Vegetation Spawner

**Objective:** Variable density spawning based on terrain zones

### Changes to Vegetation System
1. Read terrain type at spawn position
2. Apply density multiplier per terrain type
3. Add randomization within density range
4. Respect clearing radius around structures

### New Parameters
```gdscript
var density_by_terrain: Dictionary = {
    TerrainType.JUNGLE: 0.9,
    TerrainType.SECONDARY_GROWTH: 0.6,
    TerrainType.PLANTATION: 0.5,
    TerrainType.HIGHLAND: 0.35,
    TerrainType.DELTA: 0.15,
    TerrainType.CLEARED: 0.05
}
```

### Success Criteria
- [ ] Jungle areas have dense 3D trees
- [ ] Open areas have sparse vegetation
- [ ] Natural-looking density transitions

---

## PHASE 8: Performance Validation

**Objective:** Ensure 3D-only trees maintain 60 FPS

### Tests
1. Dense jungle area (1000+ trees in view)
2. Strategic zoom out (whole firebase view)
3. Combat with explosions near trees
4. Clearing operations with tree removal

### Optimization Options (if needed)
- Aggressive culling by distance
- LOD within 3D models (high/low poly)
- Instancing via MultiMesh
- Reduce draw distance for non-critical trees

### Success Criteria
- [ ] 60 FPS with 500+ trees visible
- [ ] No stuttering during zoom transitions
- [ ] Tree destruction doesn't cause frame drops

---

## Execution Order

| Phase | Priority | Effort | Dependencies |
|-------|----------|--------|--------------|
| 1 - Double line fix | HIGH | Low | None |
| 2 - Engineer-only build | HIGH | Low | None |
| 3 - Bulldozer priority | HIGH | Medium | Phase 2 |
| 4 - Remove billboards | MEDIUM | Low | None |
| 5 - Jungle research | LOW | Research | None |
| 6 - Reference maps | LOW | Research | Phase 5 |
| 7 - Variable density | MEDIUM | Medium | Phase 4, 5 |
| 8 - Performance test | HIGH | Medium | Phase 4, 7 |

**Recommended start:** Phases 1, 2, 4 in parallel (all independent, quick wins)

---

## War Room Gate

Before proceeding to implementation:
- [ ] User approves phase priorities
- [ ] Confirm which Vietnam locations to research
- [ ] Decide on minimum tree density for "jungle" feel
