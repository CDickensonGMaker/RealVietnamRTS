# THE DECREE: Logistics Loop Scene Failures

**Date**: 2026-05-28
**Scene**: `test_scenes/logistics/supply_loop_test.tscn`
**Arbiter**: War Room Council

---

## THE WEAVING

The Council has deliberated. The Devil's Advocate raised a critical insight: **these are not three bugs, but one root cause with cascading symptoms.**

### Root Cause Analysis

```
Scene.supply_loop_test._ready()
  │
  ├─[1]─ TestSceneBase.setup_environment()
  │        └─> TerrainIntegration.init_terrain()
  │              └─> TerrainManager.generate_terrain() ◄── BLOCKS HERE
  │                    ├─> _generate_heightmap() [SYNC]
  │                    ├─> _extract_and_carve_rivers() [SYNC]
  │                    └─> _load_initial_chunks() [SYNC]
  │
  ├─[2]─ _create_road_network() ◄── NEVER REACHED
  │
  ├─[3]─ _create_bulldozer() ◄── NEVER REACHED
  │
  └─[4]─ Everything else... ◄── NEVER REACHED
```

**The freeze occurs in step [1]**. Steps 2-4 never execute. Therefore:
- Trees don't show because chunk vegetation generation never happens
- Bulldozer doesn't work because it's never created
- Even if bulldozer WAS created, `cut_path()` would fail due to WorkerController guard

### Contributing Factors

| Issue | Root Cause | Secondary Cause |
|-------|------------|-----------------|
| **Freeze** | Synchronous terrain gen in `_ready()` | 27 autoloads + heavy init |
| **No Trees** | Chunks never load (freeze) | BillboardVegetation `enabled = false` |
| **No Roads** | Bulldozer never created (freeze) | WorkerController blocks `cut_path()` |

---

## THE DECREE

### Priority 0: Break the Freeze

**Option A (Quick Fix)**: Defer terrain setup to allow first frame.

```gdscript
# In supply_loop_test.gd _ready():
func _ready() -> void:
    # ... position constants ...

    # DEFER terrain setup to allow first frame to render
    call_deferred("_deferred_setup")

func _deferred_setup() -> void:
    setup_environment(seed)
    # ... rest of initialization ...
```

**Option B (Proper Fix)**: Make TerrainManager async.

```gdscript
# In terrain_manager.gd:
signal terrain_ready

func generate_terrain_async(seed_value: int) -> void:
    # Use thread or coroutine
```

### Priority 1: Enable Tree Rendering

In `billboard_vegetation.gd` line 11:
```gdscript
var enabled: bool = true  # Was false
```

### Priority 1: Fix Bulldozer Commands

The test scene calls `cut_path()` directly, but WorkerController blocks it.

**Option A (Recommended for test scenes)**: Add export bypass:
```gdscript
# In bulldozer.gd ~line 50
@export var allow_direct_commands: bool = false

# In cut_path():
func cut_path(waypoints: Array[Vector3]) -> void:
    if _worker_controller and not allow_direct_commands:
        push_warning("...")
        return
    # ... do work ...
```

**Option B (Use Job System)**: Make test scene use proper jobs:
```gdscript
# In supply_loop_test.gd instead of _bulldozer.cut_path()
var job := ClearingJob.new()
job.job_type = ClearingJob.Type.CUT_PATH
job.waypoints = waypoints
JobSystem.submit_job(job)
```

---

## VERIFICATION CHECKLIST

| Test | Expected Result |
|------|-----------------|
| Scene loads | First frame renders within 100ms |
| Trees visible | 50+ vegetation instances in viewport |
| Bulldozer moves | Unit travels along waypoints |
| Road appears | Decal renders behind bulldozer |

---

## FILES TO MODIFY

| # | File | Change | Lines |
|---|------|--------|-------|
| 1 | `test_scenes/logistics/supply_loop_test.gd` | Add `call_deferred("_deferred_setup")` | ~116-179 |
| 2 | `terrain/vegetation/billboard_vegetation.gd` | `enabled = true` | 11 |
| 3 | `battle_system/units/bulldozer.gd` | Add `@export var allow_direct_commands` | ~50, 583-624 |
| 4 | `test_scenes/logistics/supply_loop_test.gd` | Set bulldozer `allow_direct_commands = true` | ~314 |

---

## ALTERNATIVE: Skip Terrain Entirely

If the test scene's purpose is to test the BULLDOZER, not the terrain system:

```gdscript
# Comment out terrain generation entirely
# setup_environment(seed)  # Skip for bulldozer testing

# Use flat ground with manual road waypoints
```

This isolates the bulldozer test from terrain bugs.

---

## PATHS REJECTED

1. **Multi-threaded terrain generation** - Adds complexity, risk of race conditions. Defer to future.
2. **Remove WorkerController from bulldozer** - Breaks production behavior, only appropriate for test scene override.

---

## SPEAK YOUR WILL, SUMMONER

- [ ] **"Fix it."** - Implement Priority 0 + 1 changes now
- [ ] **"Skip terrain for this test."** - Comment out `setup_environment()` to isolate bulldozer testing
- [ ] **"Show me deeper."** - Add timing instrumentation to identify exact freeze point
- [ ] **"Different path."** - Reject, propose alternative

---

*The Council rests. The Summoner decides.*
