# War Room Session: Construction Loop + Supply Integration
**Date**: 2026-05-27
**Query**: Verify construction system and plan supply depletion

## Construction Loop (Current State)

```
1. PLACEMENT PHASE
   ├── Player selects building from HUD
   ├── PlacementController creates BlueprintGhost
   ├── Ghost follows cursor, validates position real-time
   │   └── validate_placement_real_time() checks:
   │       - Map bounds
   │       - Building overlap
   │       - Job overlap
   │       - Slope (non-bridges)
   │       - Water (non-bridges)
   │       - Firebase zone (if can_place_anywhere=false)
   └── Click commits placement

2. JOB CREATION PHASE
   ├── create_build_job() validates again
   ├── Supply check at nearest firebase
   │   ├── HQ buildings bypass supply check (NEW FIX)
   │   ├── No firebase → warning but allows (testing)
   │   └── Insufficient supply → BLOCKS
   ├── Creates prerequisite jobs (clear/flatten)
   └── Creates BUILD_STRUCTURE job with ConstructionSiteNode

3. CONSTRUCTION PHASE
   ├── Workers assigned to job
   ├── ConstructionSiteNode shows progress
   │   ├── Foundation phase
   │   ├── Scaffolding grows
   │   └── Progress bar updates
   └── Job completion triggers spawn

4. COMPLETION PHASE
   ├── ConstructionManager.spawn_building_at()
   ├── Loads model from BUILDING_MODELS dict
   │   └── Fallback to placeholder box if missing
   └── Building added to world
```

## Supply Depletion (Current Implementation)

**Already implemented (lines 285-303 in job_system.gd):**
- Supply deducted at job creation time
- Deduction from nearest firebase.supply_level
- BattleSignals.supply_consumed emitted for HUD

**Missing/Needs verification:**
- [ ] Supply refund on job cancellation
- [ ] HUD display of supply costs before placement
- [ ] Multiple firebase supply tracking
- [ ] Starting supply pool for initial TOC

## Supply Consumption Plan

### Phase 1: Verify Current System
1. Test supply deduction works
2. Test cancellation refunds supply
3. Verify HUD shows firebase supply level

### Phase 2: Enhance for Gameplay
1. Ghost shows cost preview (red if insufficient)
2. Supply consumption rate (not instant)
3. Partial refund on cancellation based on progress

### Phase 3: Physical Supply Chains (Pillar 3)
1. Supply must be physically delivered to firebase
2. Trucks/helicopters transport supply
3. Supply stockpile per firebase
4. Distribution from depot to construction

## Action Items

1. ✅ Fix placement bugs (TOC bypass, bridges, models)
2. ⏳ Audit: 59 missing model files (many are map-only)
3. ⏳ Test full placement→construction→completion loop
4. ⏳ Implement supply cost preview in ghost
5. ⏳ Verify cancellation refund

