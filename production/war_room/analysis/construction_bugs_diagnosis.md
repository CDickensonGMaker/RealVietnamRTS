# Construction System Bug Diagnosis

**Date:** 2026-05-27
**Status:** Investigation Complete - Fixes Required

---

## Issue 1: Bulldozers Not Moving to Jobs

### Root Cause: Worker Class Detection Relies on SquadData Properties

**File:** `C:\Users\caleb\RealVietnamRTS\firebase_system\job_system\worker_controller.gd`

The `_determine_worker_class()` function at lines 1176-1205 checks for worker class:

```gdscript
func _determine_worker_class() -> void:
    # Check for explicit worker_class property
    if "worker_class" in worker:
        worker_class = worker.worker_class
        return

    # Check unit data for capabilities
    if worker.has_method("get"):
        var data: Resource = worker.get("data")
        if data:
            # Bulldozer: vehicle with is_vehicle flag
            if "is_vehicle" in data and data.is_vehicle:
                worker_class = "bulldozer"
                move_speed = 5.0
                return
            # Engineer: infantry with can_build flag
            if "can_build" in data and data.can_build:
                worker_class = "engineer"
                return

    # Default to infantry (cannot do construction jobs)
    worker_class = "infantry"
```

**Problem:** The detection logic looks for `data.is_vehicle` but only sets `worker_class = "bulldozer"`. However:

1. Bulldozers need `is_vehicle = true` in their SquadData to be recognized
2. In `job_system.gd` lines 829-852, `can_worker_do_job()` defines what each class can do:
   - `BUILD_STRUCTURE` requires `worker_class == "engineer"` ONLY
   - Bulldozers can only do: `CLEAR_TERRAIN`, `FLATTEN_AREA`, `BUILD_ROAD`, `FILL_CRATER`

**This is working as designed** - bulldozers are NOT supposed to claim BUILD_STRUCTURE jobs. If bulldozers aren't moving to FLATTEN or CLEAR jobs, check:

1. **Is the bulldozer's SquadData setting `is_vehicle = true`?**
2. **Does WorkerController get attached to the bulldozer unit?** (Check Squad._setup_worker_controller at line 3648)
3. **Are there FLATTEN_AREA or CLEAR_TERRAIN jobs pending?** BUILD_STRUCTURE jobs won't match.

**Verification Steps:**
- Check `battle_system/data/units/us_bulldozer.tres` for `is_vehicle: true`
- Check Squad.gd line 3660: `if data.is_vehicle: _worker_controller.worker_class = "bulldozer"`
- Add debug print in WorkerController._find_work() to see what jobs it's considering

---

## Issue 2: Click-to-Assign Workers Missing (StarCraft-style)

### Root Cause: Feature Not Implemented

**Files Checked:**
- `C:\Users\caleb\RealVietnamRTS\battle_system\systems\selection_manager.gd`
- `C:\Users\caleb\RealVietnamRTS\battle_system\systems\move_order_handler.gd`

**Current Behavior:**
- `MoveOrderHandler._handle_right_click()` checks for enemies, garrisonable structures, then issues move orders
- No code checks if right-click target is a construction site or job

**Expected Behavior (StarCraft-style):**
1. Select engineer/bulldozer
2. Right-click on construction site
3. Worker is force-assigned to that job

**WorkerController already has the API:**
```gdscript
func force_job(job: UnifiedJobClass) -> bool:
    """Force this worker to take a specific job (player command)"""
```

**Fix Required:** Add to `MoveOrderHandler`:
1. Check if right-click hits a construction site (collision layer 64)
2. If so, get the associated job from JobSystem
3. For each selected worker with WorkerController, call `force_job(job)`

---

## Issue 3: Buildings Clipping Into Terrain

### Root Cause: ConstructionSiteNode Only Snaps Once at Creation

**File:** `C:\Users\caleb\RealVietnamRTS\firebase_system\nodes\construction_site_node.gd`

The `_snap_to_terrain()` function (lines 137-146) is called once in `_ready()`:

```gdscript
func _snap_to_terrain() -> void:
    var terrain: Node = get_node_or_null("/root/UnifiedTerrain")
    if terrain and terrain.has_method("get_height_at"):
        position.y = terrain.get_height_at(global_position)
        return

    var terrain_intg: Node = get_node_or_null("/root/TerrainIntegration")
    if terrain_intg and terrain_intg.has_method("get_height_at"):
        position.y = terrain_intg.get_height_at(global_position)
```

**Problems:**

1. **Single point sampling** - Only checks height at `global_position` (center), not corners
2. **No flattening integration** - If terrain is flattened after placement, building doesn't adjust
3. **Completed building inheritance** - When `_spawn_building()` creates the final building, it uses `global_position` without rechecking terrain

**File:** `C:\Users\caleb\RealVietnamRTS\firebase_system\terrain_flattening.gd`

The TerrainFlatteningSystem modifies terrain height progressively, but ConstructionSiteNode doesn't listen for terrain changes to adjust its Y position.

**Fix Required:**
1. Sample terrain height at 4 corners + center, use MAXIMUM height
2. Connect to terrain_modified signal and re-snap during construction
3. Pass proper height to spawned building

---

## Issue 4: Supply Depot and Ammo Bunker Silent Failure

### Root Cause: Firebase Zone Requirement Check

**File:** `C:\Users\caleb\RealVietnamRTS\firebase_system\job_system\job_system.gd`

In `create_build_job()` at line 267-269:
```gdscript
if not skip_validation:
    var validation: Dictionary = validate_placement(center, footprint_size, building_type)
    if not validation.valid:
        push_warning("[JobSystem] Cannot build %s: %s" % [data.display_name, validation.message])
        return null
```

The `_check_firebase_zone()` function (lines 1578-1618) enforces:

```gdscript
# Buildings that can_place_anywhere don't need firebase zone
if building_data.can_place_anywhere:
    return {"valid": true, ...}

# Firebase Defense buildings require being within a TOC influence zone
```

**Check BuildingData for Supply Depot and Ammo Bunker:**

From building_data.gd:
- **SUPPLY_DEPOT (line 1964):** No `can_place_anywhere = true` set, defaults to false
- **AMMO_BUNKER (line 564):** No `can_place_anywhere = true` set, defaults to false

**This means:** Both require placement within a TOC influence zone (150m radius).

**Why Silent Failure:**
1. `push_warning()` goes to console only - player sees no feedback
2. Ghost shows green (PlacementController checks `_last_validation_result`) but actual job creation fails

**Verification:**
1. Check if TOC is built and active
2. Check if placement is within 150m of TOC
3. The validation message would be: "Requires TOC - build a TOC first to establish firebase zone"

**Potential Bug:**
In PlacementController._commit_single_placement() at line 292-298:
```gdscript
var job = _job_system.create_build_job(
    position,
    _current_building_type,
    rotation_y,
    _current_building_data.footprint_size,
    false  # don't skip validation
)
var job_id: int = job.job_id if is_instance_valid(job) else -1
```

If `create_build_job()` returns null due to validation failure, this code handles it gracefully BUT:
- Line 268-270 shows warning but doesn't show to player
- Ghost was already green from `_validate_current_position()` which caches validation

**Root Cause of Mismatch:**
`_validate_current_position()` calls `validate_placement_real_time()` or `validate_placement()` BUT
`create_build_job()` calls `validate_placement()` AGAIN.

If validation is cached but then terrain/firebase state changes between ghost update and click confirmation, the ghost shows green but job creation fails.

---

## Summary of Required Fixes

### Fix 1: Bulldozer Job Claiming
**Priority:** HIGH (Pillar 1: Carve the Map)
- Verify SquadData for bulldozer has `is_vehicle: true`
- Add debug logging in WorkerController to track job matching
- Verify bulldozers only claim appropriate job types

### Fix 2: Click-to-Assign Workers
**Priority:** MEDIUM (UX improvement)
- Add raycast for construction sites in MoveOrderHandler
- Call WorkerController.force_job() when right-clicking construction site
- Add visual feedback for forced assignment

### Fix 3: Terrain Clipping
**Priority:** MEDIUM (Visual polish)
- Multi-point terrain sampling in ConstructionSiteNode
- Connect to terrain_modified signal for dynamic adjustment
- Ensure spawned building uses correct height

### Fix 4: Silent Build Failure
**Priority:** HIGH (Blocks gameplay)
- Show player-visible error message when validation fails
- Ensure validation cache is synchronized with actual state
- Consider adding visual indicator for firebase influence radius

---

## Files to Modify

| File | Changes Needed |
|------|----------------|
| `firebase_system/job_system/worker_controller.gd` | Add debug logging for bulldozer detection |
| `battle_system/systems/move_order_handler.gd` | Add construction site click handling |
| `firebase_system/nodes/construction_site_node.gd` | Multi-point terrain sampling, dynamic adjustment |
| `firebase_system/placement_controller.gd` | Show user-visible error on validation failure |
| `battle_system/ui/battle_hud.gd` | Display validation error messages |
