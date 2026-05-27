# Implementation Roadmap: Terrain-First Architecture
**Created:** 2026-05-26
**Status:** ACTIVE EXECUTION

---

## THE 10-STEP PROCESS

Each step concludes with a War Room checkpoint before proceeding.

| Step | Phase | Objective | War Room Gate |
|------|-------|-----------|---------------|
| 1 | REVERT | Clean slate - return to known-good state | Game launches without errors |
| 2 | AUDIT | Map terrain↔construction data flow | Data flow diagram approved |
| 3 | DOCUMENT | Catalog existing TerrainEngine capabilities | Capability inventory complete |
| 4 | DESIGN | Define TerrainQuery interface contract | Interface approved |
| 5 | IMPLEMENT | Add TerrainQuery methods to TerrainEngine | Unit tests pass |
| 6 | MIGRATE-1 | Rewrite PlacementController to use TerrainQuery | Can place buildings |
| 7 | MIGRATE-2 | Rewrite ConstructionManager to use TerrainQuery | Buildings construct |
| 8 | MIGRATE-3 | Fix job system (clearing/building jobs) | Workers clear and build |
| 9 | INTEGRATE | Wire signals, fix edge cases | No console errors |
| 10 | VERIFY | Run milestone test scenario | **THE LOOP WORKS** |

---

## STEP 1: REVERT TO KNOWN-GOOD STATE

### Objective
Remove all broken changes from today's session. Return to the last working commit.

### Actions
1. Revert modified tracked files in firebase_system/
2. Remove untracked files added from reference implementation
3. Revert modified files in terrain/
4. Clear Godot cache
5. Verify game launches

### Success Criteria
- [ ] Game launches without parser errors
- [ ] No phantom trees or unexpected behavior
- [ ] Git status shows clean working directory (or only intentional changes)

### War Room Gate
Game must launch to editor and run without immediate crashes.

---

## STEP 2: AUDIT TERRAIN↔CONSTRUCTION DATA FLOW

### Objective
Map every place construction talks to terrain and vice versa.

### Actions
1. Grep for terrain method calls in firebase_system/
2. Grep for construction/building references in terrain/
3. Identify signal connections
4. Document coordinate conversion touchpoints
5. Find duplicate state management

### Deliverable
`production/war_room/analysis/terrain_construction_audit.md`

### War Room Gate
Data flow diagram reviewed, duplicate authorities identified.

---

## STEP 3: DOCUMENT EXISTING TERRAINENGINE CAPABILITIES

### Objective
Know what TerrainEngine already provides before adding to it.

### Actions
1. Read all public methods in terrain/ directory
2. Catalog what queries are already possible
3. Identify gaps (what construction needs but terrain doesn't provide)
4. Document signal emissions

### Deliverable
`production/war_room/analysis/terrain_engine_capabilities.md`

### War Room Gate
Capability inventory approved, gap list clear.

---

## STEP 4: DESIGN TERRAINQUERY INTERFACE

### Objective
Define the contract TerrainEngine will fulfill.

### Actions
1. Draft TerrainQuery class with method signatures
2. Define return types (BuildSiteQuery, PathClearanceQuery, etc.)
3. Define signals for state changes
4. Review against construction's actual needs
5. Ensure interface is game-agnostic (reusable)

### Deliverable
`terrain/core/terrain_query.gd` (interface definition)

### War Room Gate
Interface approved by Council - no game-specific logic in signatures.

---

## STEP 5: IMPLEMENT TERRAINQUERY IN TERRAINENGINE

### Objective
Add the query methods to TerrainEngine.

### Actions
1. Implement each TerrainQuery method
2. Consolidate scattered terrain logic into these methods
3. Add proper error handling
4. Write minimal validation tests

### Success Criteria
- [ ] All TerrainQuery methods implemented
- [ ] Methods return correct data for test positions
- [ ] No regressions in existing terrain behavior

### War Room Gate
Query methods work correctly in isolation.

---

## STEP 6: MIGRATE PLACEMENTCONTROLLER

### Objective
Rewrite PlacementController to use TerrainQuery instead of scattered checks.

### Actions
1. Replace direct terrain calls with TerrainQuery methods
2. Fix linear placement rotation (the original bug)
3. Remove duplicate vegetation/clearing checks
4. Test single placement, linear placement, bridge placement

### Success Criteria
- [ ] Can place single buildings
- [ ] Can drag-paint linear structures (sandbags face drag direction)
- [ ] Placement validation uses terrain as authority

### War Room Gate
Placement works correctly for all modes.

---

## STEP 7: MIGRATE CONSTRUCTIONMANAGER

### Objective
Rewrite ConstructionManager to use TerrainQuery.

### Actions
1. Replace scattered terrain queries with TerrainQuery methods
2. Register building footprints with terrain when created
3. Query terrain for clearance requirements
4. Remove duplicate state tracking

### Success Criteria
- [ ] Buildings can be queued for construction
- [ ] Construction respects terrain state
- [ ] Building footprints registered with terrain

### War Room Gate
Construction flow works end-to-end.

---

## STEP 8: MIGRATE JOB SYSTEM (CLEARING/BUILDING)

### Objective
Fix the job system to work with terrain-authoritative model.

### Actions
1. Clearing jobs query terrain for what needs clearing
2. Building jobs query terrain for site readiness
3. Jobs update terrain state when complete
4. Fix the "hole without job" bug
5. Fix workers getting stuck

### Success Criteria
- [ ] Clearing jobs complete and update terrain
- [ ] Building jobs wait for cleared terrain
- [ ] No spurious terrain deformation
- [ ] Workers pathfind correctly

### War Room Gate
Workers clear jungle and build structures without bugs.

---

## STEP 9: INTEGRATION AND EDGE CASES

### Objective
Wire everything together, fix edge cases.

### Actions
1. Connect all signals
2. Test coordinate conversions
3. Fix initialization order issues
4. Handle chunk boundary cases
5. Eliminate console errors/warnings

### Success Criteria
- [ ] No console errors during normal operation
- [ ] Scene loads without crashes
- [ ] All systems communicate through proper channels

### War Room Gate
Clean console output, stable operation.

---

## STEP 10: MILESTONE VERIFICATION

### Objective
Prove the clearing→construction→defense loop works.

### The Test
> "Units spawning on hilly land with a small TOC and firebase elements.
> Units move around and build sandbags and bunkers that all face the
> appropriate directions as I place them. A wave of VC units attacks
> the fort and proves the whole loop of clearing→construction→defense is there."

### Actions
1. Create test scene with hilly terrain
2. Place TOC and firebase elements
3. Spawn units
4. Build sandbags and bunkers (verify facing)
5. Spawn VC wave
6. Observe defense engagement

### Success Criteria
- [ ] Units spawn at correct terrain heights
- [ ] Buildings placed correctly on terrain
- [ ] Sandbags/bunkers face placement direction
- [ ] Workers clear and build
- [ ] VC attack triggers defense
- [ ] 60 FPS maintained

### War Room Gate
**THE MILESTONE PASSES. THE LOOP WORKS.**

---

## CURRENT STATUS

**STEP 1: REVERT** - COMPLETE (2026-05-26)

### Step 1 Actions Completed:
1. Reverted firebase_system/ modified files to HEAD
2. Reverted terrain/ modified files to HEAD
3. Removed 15+ untracked job_system files (from theoretical reference implementation)
4. Fixed GDScript self-reference issues in:
   - `unified_job.gd:113-115` - Changed `UnifiedJob.new()` → `new()`, `-> UnifiedJob` → `-> RefCounted`
   - `unified_job.gd:642-643` - Removed class prefix from static method calls
   - `construction_site_node.gd:488-489` - Same self-reference fix
5. Cleared Godot editor cache
6. Verified game launches and runs test_combined scene

### Key Learning:
The reference files in `C:\Users\caleb\Downloads\files` were **theoretical implementations from Claude.ai analysis of CoH**, not tested code. They caused breakage when integrated. Do not use directly - extract concepts only.

**STEP 2: AUDIT** - COMPLETE (2026-05-26)

See: `analysis/terrain_construction_audit.md`

**Key Findings:**
1. Sandbag rotation bug at `placement_controller.gd:419` - missing `_linear_rotation_y` parameter
2. Architecture is sound - ClearingSystem is single authority for clearing state
3. Terrain spikes: Low risk due to job prerequisites enforcing order

**SANDBAG ROTATION FIX APPLIED:**
- File: `placement_controller.gd:419-421`
- Added `_linear_rotation_y` parameter to validation calls
- **Result:** Built sandbags now face correct direction!

**REFINEMENTS NEEDED (after Step 10):**
1. Preview ghost rotation doesn't match final model - fix in `blueprint_ghost.gd:501`
2. Gap between segments - adjust spacing in `_calculate_linear_segments()` line 377
3. Terrain spikes - still occurring, investigate in Step 8

**STEP 3: DOCUMENT** - COMPLETE (2026-05-26)

See: `analysis/terrain_engine_capabilities.md`

**Key Findings:**
1. TerrainGrid already provides 35+ query methods - it IS the TerrainQuery interface
2. `validate_footprint()` returns everything construction needs in one call
3. No new terrain methods needed for basic construction flow
4. Gaps are minor (build cost estimation, adjacency) - can add later

**CRITICAL INSIGHT:** Step 4 (Design TerrainQuery interface) is **UNNECESSARY** - TerrainGrid already fulfills this role. Proceed directly to migration.

**STEP 4: DESIGN** - SKIPPED (TerrainGrid already is the interface)

**STEP 5: IMPLEMENT** - SKIPPED (TerrainGrid methods already exist)

**STEP 6: MIGRATE-1** - IN PROGRESS (PlacementController refinements)

### Step 6 Actions Completed:
1. **Segment spacing fix** - `placement_controller.gd:380`
   - Added `segment_spacing = segment_length * 0.85` to tighten gap between sandbags
   - Uses tighter spacing for visual continuity while keeping footprint for validation
   - **Result:** Sandbag segments should now appear closer together

2. **Construction site rotation fix** - `construction_site_node.gd:69-71`
   - Added `rotation.y = building_rotation` in `_ready()`
   - Construction site preview now rotates to match final building orientation
   - **Result:** Preview footprint aligns with built sandbag facing

### Step 6 Remaining:
- [ ] Test segment spacing in game
- [ ] Test construction site rotation alignment
- [ ] Evaluate if further TerrainGrid migration is needed (current JobSystem validation works)

---

**STEP 8: MIGRATE-3** - PARTIAL (Terrain spike fix applied early)

### Step 8 Actions Completed (Applied Early):
1. **Bulldozer terrain spike fix** - `job_system.gd:778-795`
   - Root cause: `carve_terrain_toward()` was lerping between normalized height (0-1) and world meters
   - Fix: Normalize `target_height` by dividing by `height_scale` before lerping
   - **Result:** Bulldozers should no longer create terrain spikes during flattening

### Why Bulldozers Caused Spikes (Engineers Didn't):
- Engineers don't use `carve_terrain_toward()` - they skip terrain modification
- Bulldozers use cell-by-cell terrain carving which had the normalization bug

### Step 8 Actions Completed (Bulldozer Indent Fix - 2026-05-26):
2. **Bulldozer terrain indent fix** - `job_system.gd:1104-1191`
   - Root cause: `_create_prerequisites()` always created FLATTEN_AREA jobs for builds
   - Bulldozers picked up FLATTEN_AREA jobs and carved terrain via `carve_terrain_toward()`
   - Fix: Added `check_slope_for_flatten` parameter to `_create_prerequisites()`
   - Building jobs now only create FLATTEN_AREA prerequisite if slope > 0.25 (≈15 degrees)
   - **Result:** Bulldozers no longer make terrain indents when building on flat/gentle slopes

---

## PHASE 11: TERRAIN SPLINE + ROAD RENDERING (Post-Milestone)

**Status:** COMPLETE (2026-05-26)

### Overview
Two-layer system for terrain-aware roads:
1. **TerrainSpline** - A curve that snakes between points following terrain
2. **Road Renderer** - Visual mesh rendered on top of the spline

### Files Created
- `terrain/systems/terrain_spline.gd` (~280 LOC) - Catmull-Rom spline with terrain sampling
- `terrain/systems/terrain_spline_visualizer.gd` (~150 LOC) - Debug visualization with slope coloring

### Files Modified
- `firebase_system/road_decal_renderer.gd` - Added `setup_from_spline()` and `create_for_spline()` methods
- `terrain/systems/road_network.gd` - Added spline storage in RoadSegment, `create_segment_from_spline()` method
- `reinforcement_system/supply_truck.gd` - Added spline-based navigation with `_process_spline_movement()`

### Implementation Details

**TerrainSpline Features:**
- Catmull-Rom interpolation for smooth curves
- Automatic terrain height sampling via `_get_terrain_height()`
- Cached points with distance lookup for performance
- `generate_road_mesh()` for direct mesh generation
- Slope validation with `is_passable()` and `get_max_slope_degrees()`

**RoadSegment Spline Support:**
- `spline: RefCounted` property on RoadSegment class
- `get_length()` respects spline length when present
- `get_position_at_distance()` and `get_tangent_at_distance()` for navigation
- A* pathfinding uses spline-aware length calculation

**SupplyTruck Spline Navigation:**
- `set_spline_route()` enables smooth spline following
- `_process_spline_movement()` advances along spline by distance
- Smooth rotation aligned to spline tangent
- Progress reporting via `get_progress()` works with both modes

### Integration Points
| System | Integration Method |
|--------|-------------------|
| RoadDecalRenderer | `setup_from_spline(spline, width)` |
| RoadNetwork | `create_segment_from_spline(spline, road_type)` |
| SupplyTruck | `set_spline_route(spline)` |
| Debug Viz | `TerrainSplineVisualizer.create(spline)` |

### Pillar Alignment
**Pillar 3: Physical Supply Chains** - Natural-looking supply routes that follow terrain

---

*Each step will be documented in its own analysis file. The War Room convenes at each gate.*
