# Freeze Bug Analysis: Bulldozer in Logistics Test Scene

**Date:** 2025-05-28
**Analyst:** Systems Programmer
**Issue:** Game freezes when camera approaches bulldozer

---

## Executive Summary

After thorough code analysis, I have identified **no infinite loops** in the bulldozer or WorkerController code. The freeze is likely caused by one of two scenarios:

1. **Rendering Load Spike** - The bulldozer model or nearby terrain triggering expensive GPU operations when coming into view
2. **Navigation Edge Case** - The bulldozer getting into a state where it repeatedly issues move commands every frame

---

## Code Analysis

### Files Examined

1. `battle_system/units/bulldozer.gd` (740 lines)
2. `firebase_system/job_system/worker_controller.gd` (1387 lines)
3. `test_scenes/logistics/supply_loop_test.gd` (2026 lines)
4. `firebase_system/job_system/job_system.gd` (1875 lines)
5. `firebase_system/job_system/unified_job.gd` (650 lines)

### Potential Performance Issues Found

#### Issue 1: Move Command Spam (Lines 255-271 in worker_controller.gd)

The WorkerController's `_process_moving()` function has logic to re-issue move commands:

```gdscript
if needs_move_order:
    worker.move_to(move_target)
    PrintThrottleClass.log("worker_move", ...)
```

While there's a check to avoid re-issuing when already heading to the right place, the condition:
```gdscript
if "move_target" in worker and "has_move_order" in worker:
    if worker.has_move_order:
        var target_diff: Vector3 = move_target - worker.move_target
```

**Could fail if:**
- `worker.move_target` differs slightly from `move_target` due to terrain snapping
- The bulldozer's `has_move_order` gets reset unexpectedly

#### Issue 2: Flatten Job Cell Iteration (Lines 984-1006 in worker_controller.gd)

The `_acquire_next_cell()` function iterates over all cells in a flatten job:

```gdscript
for x in range(r.position.x, r.end.x):
    for z in range(r.position.y, r.end.y):
```

For large flatten areas, this could be O(n^2) every time the worker needs a new cell. However, there's an early exit optimization that should prevent issues.

#### Issue 3: Print Throttle Overhead

Every worker state transition calls `PrintThrottle.log()`, which does:
- Time check (`Time.get_ticks_msec()`)
- Dictionary lookups
- String formatting

With multiple workers, this adds up.

---

## Root Cause Hypothesis

Based on the code and the user's description:

**The bulldozer's starting position conflicts with the supply depot**, causing:

1. Bulldozer spawns near/inside supply depot collision
2. WorkerController tries to find a job
3. Movement commands fail or oscillate due to collision
4. Rapid state transitions trigger excessive logging
5. When camera approaches (triggering LOD/rendering), the combined CPU/GPU load causes freeze

### Evidence from supply_loop_test.gd (Lines 883-896):

```gdscript
func _create_bulldozer() -> void:
    ...
    # Position bulldozer near the first road waypoint, not behind the depot
    # This prevents it from getting stuck trying to navigate around buildings
    var first_waypoint: Vector3 = _road_waypoints[0] if not _road_waypoints.is_empty() else REAR_DEPOT_POS
    _bulldozer.position = first_waypoint + Vector3(-5, 0, -5)  # Slightly behind road start
```

The comment explicitly acknowledges the positioning concern, but `Vector3(-5, 0, -5)` may still be too close to the depot at `REAR_DEPOT_POS + Vector3(20, 0, 0)`.

---

## Recommended Fixes

### Fix A: Reposition Bulldozer Start Position (Simplest)

Move the bulldozer farther from the depot to avoid navigation conflicts:

**In `supply_loop_test.gd`, line 884:**
```gdscript
# Current:
_bulldozer.position = first_waypoint + Vector3(-5, 0, -5)

# Recommended:
_bulldozer.position = first_waypoint + Vector3(0, 0, -10)  # Directly behind road start, away from depot
```

### Fix B: Reposition Supply Depot

Move the depot so its collision volume doesn't overlap the road start:

**In `supply_loop_test.gd`, line 119:**
```gdscript
# Current:
REAR_DEPOT_POS = Vector3(map_center - 150.0, 0.0, map_center)

# Recommended (move farther west):
REAR_DEPOT_POS = Vector3(map_center - 170.0, 0.0, map_center)
```

### Fix C: Add Move Command Rate Limiting (Defensive)

In `worker_controller.gd`, add a cooldown to prevent move spam:

```gdscript
var _last_move_command_time: float = 0.0
const MOVE_COMMAND_COOLDOWN: float = 0.2  # Max 5 move commands per second

func _process_moving(delta: float) -> void:
    # ... existing code ...

    if needs_move_order:
        var current_time: float = Time.get_ticks_msec() / 1000.0
        if current_time - _last_move_command_time >= MOVE_COMMAND_COOLDOWN:
            _last_move_command_time = current_time
            worker.move_to(move_target)
```

### Fix D: Disable WorkerController in Test Scene (Diagnostic)

To confirm the WorkerController is the culprit, temporarily disable it:

**In `bulldozer.gd`, line 136:**
```gdscript
func _setup_worker_controller() -> void:
    return  # DEBUG: Skip worker controller setup
    # ... rest of function
```

---

## Testing Protocol

1. Apply Fix A (reposition bulldozer)
2. Run scene, press B to start construction
3. Move camera to bulldozer location
4. Observe for freeze

If freeze persists after Fix A, apply Fix D to isolate whether WorkerController is involved.

---

## Conclusion

The freeze is most likely caused by **navigation conflicts** between the bulldozer and supply depot, exacerbated by move command spam in the WorkerController. The simplest fix is repositioning the bulldozer's starting location to avoid the depot's collision volume entirely.

**Recommended Action:** Apply Fix A first, then Fix C as a defensive measure.
