# War Room: Bulldozer Investigation

**Date:** 2026-05-28
**Query:** Verify hypothesis about idle bulldozer root cause

## The Hypothesis (User-Provided)

> The idle bulldozer's root cause is a missing JobSystem autoload. `_setup_worker_controller()` checks `get_node_or_null("/root/JobSystem")` and if that returns nothing, no WorkerController gets attached.

## The Evidence

### Finding 1: JobSystem IS Registered

```
project.godot line 27:
JobSystem="*res://firebase_system/job_system/job_system.gd"
```

**VERDICT: Hypothesis is INCORRECT.** JobSystem autoload exists and is properly registered. The bulldozer's `_setup_worker_controller()` should find it and attach a WorkerController.

### Finding 2: Two Competing Control Systems

The real issue is a **control conflict** in `supply_loop_test.gd`:

**System A: Real Bulldozer's Internal State Machine**
```gdscript
# bulldozer.gd lines 322-341
func _physics_process(delta: float) -> void:
    match state:
        State.PATH_CUTTING:
            _process_path_cutting(delta)  # Uses move_and_slide()
    _snap_to_terrain()
```

**System B: Test Scene's Manual Movement**
```gdscript
# supply_loop_test.gd lines 990-1059
func _update_bulldozer_construction(delta: float) -> void:
    if _road_construction_state != "BUILDING":
        return
    # Directly modifies position - bypasses physics
    _bulldozer.position += direction * bulldozer_speed * delta
```

When pressing B (`_start_road_construction`):
1. Sets `_road_construction_state = "BUILDING"`
2. Calls `_bulldozer.cut_path(waypoints)` which sets bulldozer to `State.PATH_CUTTING`
3. **BOTH systems now try to move the bulldozer simultaneously**:
   - Bulldozer's `_physics_process` → `_process_path_cutting()` → `move_and_slide()`
   - Test scene's `_process()` → `_update_bulldozer_construction()` → direct `position +=`

**This creates jittery movement or cancellation.**

### Finding 3: The Logic Error

The test scene's `_start_road_construction()` at line 979-984:

```gdscript
elif _bulldozer.has_method("cut_path"):
    # Real bulldozer - use its cut_path method
    var waypoints: Array[Vector3] = []
    for wp in _road_waypoints:
        waypoints.append(wp)
    _bulldozer.cut_path(waypoints)
```

It correctly calls `cut_path()` for a real bulldozer, BUT it ALSO sets `_road_construction_state = "BUILDING"` (line 969), which causes `_update_bulldozer_construction()` to run ALONGSIDE the bulldozer's own movement.

## Root Cause

**The test scene doesn't skip manual movement when using a real bulldozer.**

When the bulldozer is a REAL `Bulldozer` instance (not a placeholder Node3D):
- Calling `cut_path()` activates the bulldozer's internal state machine
- The bulldozer handles its own movement via `_physics_process`
- But the test scene's `_update_bulldozer_construction()` ALSO runs, creating a conflict

## The Fix

Option A: **Skip manual movement for real bulldozers**
```gdscript
func _update_bulldozer_construction(delta: float) -> void:
    if _road_construction_state != "BUILDING":
        return

    # Real bulldozer handles its own movement
    if _bulldozer.has_method("cut_path"):
        # Check if bulldozer completed path cutting
        if _bulldozer.state == _bulldozer.State.IDLE:
            _complete_road_construction()
        return  # Don't manually move - bulldozer does it

    # Placeholder bulldozer - manual movement
    # ... existing manual movement code ...
```

Option B: **Don't set BUILDING state for real bulldozers**
```gdscript
func _start_road_construction() -> void:
    ...
    if _bulldozer.has_method("cut_path"):
        # Real bulldozer - let it handle everything
        var waypoints: Array[Vector3] = []
        for wp in _road_waypoints:
            waypoints.append(wp)
        _bulldozer.cut_path(waypoints)
        # Connect to bulldozer's completion signal
        if not _bulldozer.clearing_completed.is_connected(_on_bulldozer_path_complete):
            _bulldozer.path_segment_cleared.connect(_on_bulldozer_segment_cleared)
        _road_construction_state = "BULLDOZER_CONTROLLED"  # Different state
    else:
        _road_construction_state = "BUILDING"  # Manual control for placeholder
```

## Testing Recommendation

1. **Immediate Test:** Press B and watch console for `[Bulldozer] WorkerController attached` message
   - If present: JobSystem is working, control conflict is the issue
   - If absent: JobSystem loading failed (check file exists)

2. **Verify control conflict:** Add debug print to both movement systems:
   ```gdscript
   # In bulldozer.gd _process_path_cutting:
   print("[Bulldozer] PATH_CUTTING: moving to segment %d" % path_segment_index)

   # In supply_loop_test.gd _update_bulldozer_construction:
   print("[Test] Manual move: segment %d" % target_segment)
   ```
   If both print, you have the control conflict.

## Summary

| Hypothesis | Verdict |
|------------|---------|
| JobSystem autoload missing | **INCORRECT** - It's registered at line 27 |
| WorkerController not attaching | **Needs verification** - Check console for message |
| Control conflict between systems | **LIKELY ROOT CAUSE** |

The bulldozer isn't "doing nothing" - it's being controlled by TWO systems simultaneously, resulting in fighting/cancellation. The fix is to make the test scene defer to the real bulldozer's internal state machine when using a real Bulldozer instance.
