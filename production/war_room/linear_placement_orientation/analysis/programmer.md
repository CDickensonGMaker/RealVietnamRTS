# Gameplay Programmer Analysis: Rotation Flow Tracing

**Date**: 2026-05-26
**Status**: ROOT CAUSE FOUND

---

## Complete Rotation Flow Trace

I traced the rotation value from placement through to final model spawn:

### Step 1: Placement Controller (placement_controller.gd:395-396)
```gdscript
var model_offset := deg_to_rad(_current_building_data.model_rotation_y)
_linear_rotation_y = atan2(direction.x, direction.z) - model_offset
```
**Result**: `_linear_rotation_y = direction_angle - model_offset`

### Step 2: Job Creation (placement_controller.gd:510-516)
```gdscript
var job = _job_system.create_build_job(
    pos,
    _current_building_type,
    _linear_rotation_y,  // This value is passed to job
    footprint,
    false
)
```
**Result**: Job stores `rotation = direction_angle - model_offset`

### Step 3: Job Metadata (job_system.gd)
The rotation is stored in `job.metadata["rotation"]`

### Step 4: Construction Site Creation (job_node_factory.gd:44-48)
```gdscript
var rotation: float = job.metadata.get("rotation", 0.0)
var site: Node = ConstructionSiteNodeClass.create(center, building_type, rotation, size)
```
**Result**: Site stores `building_rotation = direction_angle - model_offset`

### Step 5: Building Spawn (construction_manager.gd:429-431)
```gdscript
var model_offset: float = deg_to_rad(data.model_rotation_y) if data else 0.0
building.rotation.y = rotation_y + model_offset
```
**Result**: `building.rotation.y = (direction_angle - model_offset) + model_offset`
**Final**: `building.rotation.y = direction_angle`

---

## THE BUG: Double Application Cancellation

```
placement_controller: SUBTRACTS model_offset
construction_manager: ADDS model_offset

Final = direction_angle - model_offset + model_offset
Final = direction_angle
```

**The model_offset is completely canceled out!** The final building gets NO model correction.

---

## Preview Bug (Same Pattern)

### Blueprint Ghost (blueprint_ghost.gd:470-472, 501)
```gdscript
_segment_rotation = rotation_y  // = direction_angle - model_offset (from controller)
_model_rotation_offset = model_rotation_offset  // = model_offset (passed separately)

marker.rotation.y = _segment_rotation + _model_rotation_offset
```
**Result**: `marker.rotation.y = (direction_angle - model_offset) + model_offset = direction_angle`

The preview ALSO gets no model correction!

---

## Why Both Appear Wrong

Both the preview and the placed model receive:
```
rotation.y = atan2(direction.x, direction.z)  // Raw direction angle, no model correction
```

For a sandbag dragged East (+X):
- `atan2(1, 0) = π/2 = 90°`
- Sandbag model has length along X axis at rotation.y = 0
- At rotation.y = 90°, model length rotates to be along Z (perpendicular to drag!)

**This is why walls are perpendicular to the paint direction!**

---

## Root Cause Summary

The model_rotation_y correction was added in TWO places that ended up in the same calculation path:

1. **Placement Controller**: Thought it was pre-computing the final rotation
2. **Construction Manager**: Has existing code that applies model_rotation_y for ALL buildings

These two well-intentioned additions cancel each other out completely.

---

## The Fix

**Option A (Recommended): Remove from Placement Controller**

Remove the model_offset from placement_controller (line 396):
```gdscript
// Before
_linear_rotation_y = atan2(direction.x, direction.z) - model_offset

// After
_linear_rotation_y = atan2(direction.x, direction.z)
```

Let construction_manager handle model rotation (it already does for non-linear buildings).

For preview, KEEP the model_rotation_offset addition in blueprint_ghost since construction_manager will also add it.

**Option B: Remove from Construction Manager**

Change construction_manager.gd:431:
```gdscript
// Before
building.rotation.y = rotation_y + model_offset

// After (for linear buildings only)
building.rotation.y = rotation_y  // Already corrected by placement_controller
```

This is messier because it requires detecting linear vs non-linear buildings.

---

## Connectors Have Same Bug

The connector spawn (placement_controller.gd:583) uses `_linear_rotation_y`:
```gdscript
connector.rotation.y = _linear_rotation_y
```

This does NOT go through construction_manager, so connectors DON'T get the model_offset added back.

For connectors: `rotation.y = direction_angle - model_offset` (correct!)

But actual buildings: `rotation.y = direction_angle` (wrong!)

This is why connectors might be oriented differently than the main segments!

---

## Verification Test

After fix, for East drag (+X):
- `direction_angle = atan2(1, 0) = 90°`
- `model_offset = 90°` (sandbag)
- Job rotation = 90° (raw direction)
- Final building rotation = 90° + 90° = 180°

At rotation.y = 180°:
- Model's local +X axis points toward world -X
- Model's 2m length spans world X axis (correct!)

The wall would span East-West along the paint line.
