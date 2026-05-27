# Step 2: Terrain↔Construction Data Flow Audit

**Date:** 2026-05-26
**Status:** COMPLETE

---

## Executive Summary

The audit identified 40+ terrain↔construction touchpoints. The architecture is sound with good separation of concerns. **Two specific bugs found:**

1. **Sandbag Rotation Bug** - `placement_controller.gd:419` missing `_linear_rotation_y` parameter
2. **Terrain Spike Risk** - Height modifications can overlap during flattening (low risk due to job prerequisites)

---

## The Sandbag Rotation Bug

### Root Cause
```
PlacementController._update_linear_dragging()
├─ _calculate_linear_segments()
│  └─ _linear_rotation_y = atan2(direction.x, direction.z) + PI/2  ← CALCULATED
│
├─ _validate_linear_segments()
│  └─ validate_placement_real_time(pos, footprint, building_type)  ← MISSING ROTATION!
│
└─ _commit_linear_placement()
   └─ rotation = _linear_rotation_y  ← PASSED CORRECTLY TO JOB
```

### Fix Required
**File:** `firebase_system/placement_controller.gd`
**Line 419-421:**
```gdscript
# CURRENT (broken):
result = _job_system.validate_placement_real_time(pos, footprint, _current_building_type)

# FIXED:
result = _job_system.validate_placement_real_time(pos, footprint, _current_building_type, _linear_rotation_y)
```

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     PLACEMENT UI LAYER                          │
│                   PlacementController (node)                    │
│                                                                  │
│  _linear_rotation_y = atan2(dir) + PI/2  ← CALCULATED          │
│                         │                                        │
│                         ↓                                        │
│  validate_placement_real_time(pos, fp, type)  ← MISSING ROT!   │
│                         │                                        │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ↓
┌─────────────────────────────────────────────────────────────────┐
│                     JOB SYSTEM LAYER                            │
│                                                                  │
│  validate_placement(center, footprint, type, rotation_y=0.0)   │
│  ├─ terrain.get_height_at()  ─────────────────┐                │
│  ├─ terrain.is_water_at()                      │                │
│  └─ Check slope, overlaps                      │                │
│                                                 │                │
└─────────────────────────────────────────────────┼───────────────┘
                                                  │
                                                  ↓
┌─────────────────────────────────────────────────────────────────┐
│                    TERRAIN SYSTEM LAYER                         │
│          TerrainIntegration / UnifiedTerrainEngine              │
│                                                                  │
│  get_height_at(pos) → HeightmapStorage (2m) → TerrainGrid (4m) │
│  is_water_at(pos)   → elevation < water_level                  │
│  modify_terrain()   → HeightmapStorage update                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Critical Touchpoints

| Direction | File | Line | Purpose |
|-----------|------|------|---------|
| C→T | placement_controller.gd | 400 | Height snap linear segments |
| C→T | placement_controller.gd | **419** | **BUG: Missing rotation** |
| C→T | unified_job.gd | 275-278 | Work position height snap |
| C→T | job_system.gd | 1442-1445 | Slope check for placement |
| C→T | terrain_flattening.gd | 157, 206 | Sample heights for flattening |
| T→C | clearing_system.gd | 101, 125 | Clearing state signals |
| T→C | unified_terrain_engine.gd | 21, 23 | terrain_modified signal |

---

## Duplicate Authority Assessment

| Data | Authority | Readers | Risk |
|------|-----------|---------|------|
| Clearing State | ClearingSystem | ConstructionManager, JobSystem | LOW - single writer |
| Height Data | HeightmapStorage | TerrainGrid (cache), all systems | LOW - read-only cache |
| Building Occupancy | Scene tree | JobSystem, TerrainGrid | LOW - synced on spawn |

**Verdict:** No dangerous duplicate authorities. ClearingSystem is well-designed single writer.

---

## Terrain Spike Analysis

**Where heights are modified:**
1. `ClearingSystem._apply_stage_changes()` - Progressive flattening
2. `TerrainFlattening._apply_terrain_modification()` - Build site leveling
3. `DamageSystem.create_crater()` - Combat damage

**Spike Prevention:**
- Job prerequisites enforce order: CLEAR → FLATTEN → BUILD
- Sequential execution prevents overlap
- TerrainFlattening samples original heights before modifying

**Remaining Risk:** Brief cache staleness during modification (1 frame)

---

## Fixes Needed

### Priority 1: Sandbag Rotation (placement_controller.gd:419)
Pass `_linear_rotation_y` to validation calls.

### Priority 2: Single Placement Rotation (placement_controller.gd:568-571)
Also pass rotation for non-linear placements.

### Future: Unify Clearing Checks
JobSystem should explicitly call `ClearingSystem.is_position_cleared()` instead of inferring from height.

---

*War Room Gate: PASSED - Audit complete, bugs identified*
