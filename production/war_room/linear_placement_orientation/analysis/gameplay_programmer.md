# Gameplay Programmer Analysis: Implementation Review

## Code Flow Audit

### 1. Segment Calculation (placement_controller.gd:374-410)

```gdscript
func _calculate_linear_segments(start: Vector3, end: Vector3) -> void:
    var segment_length: float = _current_building_data.footprint_size.x
    var direction := (end - start).normalized()

    # Calculate rotation perpendicular to drag direction
    var perpendicular := Vector3(-direction.z, 0, direction.x)
    _linear_rotation_y = atan2(perpendicular.x, -perpendicular.z)

    # Place segments along line
    for i in range(count):
        var pos := start + direction * (segment_length * (i + 0.5))
```

**Observations:**
- `segment_length = footprint_size.x` → segments spaced by footprint WIDTH
- Segments positioned along `direction` vector
- But rotation is based on `perpendicular` vector

### 2. Segment Marker Rendering (blueprint_ghost.gd:502-543)

```gdscript
func _create_segment_marker_mesh(is_valid: bool) -> MeshInstance3D:
    var hw := _segment_size.x * 0.5  # Half width
    var hd := _segment_size.y * 0.5  # Half depth

    # Quad corners
    var bl := Vector3(-hw, y, -hd)
    var br := Vector3(hw, y, -hd)
    var tr := Vector3(hw, y, hd)
    var tl := Vector3(-hw, y, hd)
```

**The marker rectangle:**
- Extends `hw` (half of footprint.x) in ±X direction
- Extends `hd` (half of footprint.y) in ±Z direction
- When `_segment_rotation` is applied, the whole rectangle rotates

**For sandbags (2.0, 0.5):**
- Marker is 2m wide (X) × 0.5m deep (Z) in local space
- If segment_rotation = 0°: marker spans world ±X, depth in world ±Z
- If segment_rotation = 90°: marker spans world ±Z, depth in world ±X

### 3. Marker Rotation Application (blueprint_ghost.gd:496-497)

```gdscript
marker.global_position = pos
marker.rotation.y = _segment_rotation
```

**Note:** Only `_segment_rotation` is applied, NOT the `model_rotation_y` offset!

This means **markers don't show what the final model will look like** because they're missing the 180° model offset.

### BUG FOUND #1: Marker vs Model Mismatch

The segment markers visualize the footprint without `model_rotation_y`. The actual spawned model has an additional 180° rotation for sandbags.

**Impact:** What the player sees during placement doesn't match what gets built.

### 4. Job Creation (placement_controller.gd:508-513)

```gdscript
var job = _job_system.create_build_job(
    pos,
    _current_building_type,
    _linear_rotation_y,  # perpendicular to drag direction
    footprint,
    false
)
```

The `_linear_rotation_y` (perpendicular-based) is passed directly.

### 5. Final Model Spawn (construction_manager.gd:427-435)

```gdscript
var model_offset: float = deg_to_rad(data.model_rotation_y) if data else 0.0
building.rotation.y = rotation_y + model_offset
```

**Final rotation = perpendicular angle + model offset**

For sandbags: `perpendicular_angle + π`

### Analysis: What Should Happen

**Goal:** Place sandbags ALONG the painted line.

**Model characteristics (sandbag_light):**
- 2.14m long segment
- Faces +Z in model space (Spring 1944 convention)
- After 180° model_rotation_y: faces -Z (Godot forward)
- Length axis is local X

**For wall to span along drag direction:**
- Model's local X must align with world drag direction
- Since model_rotation_y rotates everything 180°:
  - Model's original +X becomes final -X
  - So we need final -X to align with drag
  - Meaning original +X aligns with -drag

**Required rotation:**
```gdscript
# To align original +X with -drag (so final -X aligns with +drag)
rotation_for_alignment = atan2(-direction.x, -direction.z)
```

But wait, that's what `atan2(perpendicular.x, -perpendicular.z)` ISN'T!

Let me trace through Case 1 again (drag = +X):
```
direction = (1, 0, 0)
-direction = (-1, 0, 0)
atan2(-1, 0) = -π/2
```

Current code:
```
perpendicular = (0, 0, 1)
atan2(0, -1) = π
```

These are 90° apart (π vs -π/2 = 3π/2 difference).

### BUG FOUND #2: Rotation Axis Misalignment

The current formula calculates an angle that's 90° off from what's needed to align the model's length with the drag direction.

## Proposed Fix

Replace:
```gdscript
var perpendicular := Vector3(-direction.z, 0, direction.x)
_linear_rotation_y = atan2(perpendicular.x, -perpendicular.z)
```

With:
```gdscript
# Align model length (originally +X, becomes -X after model_rotation_y) with drag
# We want final -X to align with +drag, so original +X aligns with -drag
_linear_rotation_y = atan2(-direction.x, -direction.z)
```

**But this only works for models with model_rotation_y = 180°!**

For wire obstacles with model_rotation_y = 0°, the formula should be:
```gdscript
_linear_rotation_y = atan2(direction.x, direction.z)
```

### Generalized Fix

```gdscript
# Base angle to align model's +X with drag direction
var base_rotation := atan2(direction.x, direction.z)

# If model will be flipped 180° by model_rotation_y,
# we need to counter-rotate to maintain alignment
# (model_rotation_y is in degrees in BuildingData)
var model_offset := deg_to_rad(_current_building_data.model_rotation_y)
_linear_rotation_y = base_rotation - model_offset
```

Wait, this pre-subtracts what will be added later. Let me think...

Actually no. The issue is we want the FINAL model orientation to be correct.
- Final = _linear_rotation_y + model_offset
- We want Final to align model's length with drag
- Model's length is along local X
- At rotation 0, model X = world X
- To align model X with drag direction D:
  - Final rotation = atan2(D.x, D.z)

So:
```
_linear_rotation_y + model_offset = atan2(direction.x, direction.z)
_linear_rotation_y = atan2(direction.x, direction.z) - model_offset
```

**For sandbags (model_offset = π):**
```
_linear_rotation_y = atan2(direction.x, direction.z) - π
```

**For wire (model_offset = 0):**
```
_linear_rotation_y = atan2(direction.x, direction.z)
```

## Summary of Bugs

1. **Marker visualization doesn't include model_rotation_y** - markers lie 180° off
2. **Rotation formula produces perpendicular alignment instead of parallel alignment**

## Recommended Changes

### placement_controller.gd:392-400

```gdscript
# OLD (buggy)
var perpendicular := Vector3(-direction.z, 0, direction.x)
_linear_rotation_y = atan2(perpendicular.x, -perpendicular.z)

# NEW (fixed)
# Calculate base angle to align model's +X axis with drag direction
var base_angle := atan2(direction.x, direction.z)
# Subtract model's inherent rotation offset (will be added back in spawn_building_at)
var model_offset := deg_to_rad(_current_building_data.model_rotation_y)
_linear_rotation_y = base_angle - model_offset
```

### blueprint_ghost.gd:497

```gdscript
# OLD (doesn't account for model offset)
marker.rotation.y = _segment_rotation

# NEW (shows what model will actually look like)
# Note: need to pass building_data.model_rotation_y to ghost
marker.rotation.y = _segment_rotation + _model_rotation_offset
```

This requires adding `_model_rotation_offset` to the segment marker API.
