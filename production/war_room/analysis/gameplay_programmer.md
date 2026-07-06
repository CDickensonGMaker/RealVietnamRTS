# Gameplay Programmer Analysis: Bulldozer Road Construction Blocked

## Issue #3: Bulldozer Can't Make Roads - ROOT CAUSE IDENTIFIED

### The Smoking Gun

In `battle_system/units/bulldozer.gd` lines 583-624, ALL terrain modification methods have this guard:

```gdscript
func cut_path(waypoints: Array[Vector3]) -> void:
    if _worker_controller:
        push_warning("[Bulldozer] Has WorkerController - use job system for cut_path")
        return  # <-- IMMEDIATELY RETURNS, DOES NOTHING!
```

The same pattern exists for:
- `clear_zone()` - blocked
- `flatten_zone()` - blocked
- `cut_path()` - blocked

### Why WorkerController is Attached

In `_ready()` (lines 134-159), the bulldozer automatically creates a WorkerController:

```gdscript
func _ready() -> void:
    # ...
    _worker_controller = WorkerController.new()
    _worker_controller.setup(self, _clearing_capability)
    add_child(_worker_controller)
```

So **every real bulldozer has WorkerController**, meaning direct method calls are rejected.

### What the Test Scene Does Wrong

In `supply_loop_test.gd` lines 971-979:
```gdscript
elif _bulldozer.has_method("cut_path"):
    # Real bulldozer - use its cut_path method
    var waypoints: Array[Vector3] = []
    for wp in _road_waypoints:
        waypoints.append(wp)
    _bulldozer.cut_path(waypoints)  # <-- REJECTED! Returns immediately.
```

The test scene calls `cut_path()` directly, which hits the WorkerController guard and returns without doing anything.

### The Irony: Placeholder Bulldozer WORKS

Lines 901-948 define a placeholder bulldozer (CharacterBody3D) that doesn't have WorkerController. If that path was used, road construction would work!

### Road Decal Only Created on Completion

Lines 1008-1014 create the road visual only when construction completes:
```gdscript
if _road_construction_state == "COMPLETE":
    # CREATE THE ROAD DECAL NOW
    _road_decal = RoadDecalRenderer.create_for_spline(_road_spline, 4.0)
```

Since `cut_path()` is rejected, `_road_construction_state` never becomes "COMPLETE", so no road decal appears.

## Verdict: API MISMATCH

The real Bulldozer enforces job-system-only operation, but the test scene calls direct methods. This is a design disconnect.

## Recommended Fixes

**Option A**: Test scene uses job system
```gdscript
# Instead of _bulldozer.cut_path(waypoints)
var job = ClearingJob.new(ClearingJob.Type.CUT_PATH, waypoints)
JobSystem.submit(job)
```

**Option B**: Bulldozer allows direct calls for testing
```gdscript
@export var allow_direct_commands: bool = false

func cut_path(waypoints: Array[Vector3]) -> void:
    if _worker_controller and not allow_direct_commands:
        push_warning(...)
        return
```

**Option C**: Test scene uses placeholder bulldozer
Use the CharacterBody3D placeholder which has no WorkerController.
