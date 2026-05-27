# Systems Designer Analysis: Rotation Mathematics

## Coordinate System Review

**Godot Conventions:**
- Forward = -Z (north)
- Right = +X (east)
- Up = +Y
- Rotation.y = 0 means facing -Z (north)
- Rotation.y = π/2 (90°) means facing -X (west)
- Rotation.y = π (180°) means facing +Z (south)

## Current Rotation Calculation

```gdscript
var direction := (end - start).normalized()
var perpendicular := Vector3(-direction.z, 0, direction.x)
_linear_rotation_y = atan2(perpendicular.x, -perpendicular.z)
```

### Step-by-Step Analysis

**Case 1: Paint East (+X direction)**
```
direction = (1, 0, 0)
perpendicular = (-0, 0, 1) = (0, 0, 1)  # Points +Z (south)
_linear_rotation_y = atan2(0, -1) = π (180°)
```
Result: Segments rotate 180°. With model_rotation_y=180°, total = 360° = 0°.
Model faces -Z (north). **Wall runs E-W, faces north.**

**Case 2: Paint West (-X direction)**
```
direction = (-1, 0, 0)
perpendicular = (0, 0, -1)  # Points -Z (north)
_linear_rotation_y = atan2(0, 1) = 0°
```
Result: Segments rotate 0°. With model_rotation_y=180°, total = 180°.
Model faces +Z (south). **Wall runs E-W, faces south.**

**Case 3: Paint North (-Z direction)**
```
direction = (0, 0, -1)
perpendicular = (1, 0, 0)  # Points +X (east)
_linear_rotation_y = atan2(1, 0) = π/2 (90°)
```
Result: Segments rotate 90°. With model_rotation_y=180°, total = 270° = -90°.
Model faces +X (east). **Wall runs N-S, faces east.**

**Case 4: Paint South (+Z direction)**
```
direction = (0, 0, 1)
perpendicular = (-1, 0, 0)  # Points -X (west)
_linear_rotation_y = atan2(-1, 0) = -π/2 (-90°)
```
Result: Segments rotate -90°. With model_rotation_y=180°, total = 90°.
Model faces -X (west). **Wall runs N-S, faces west.**

## Problem Identification

### Issue 1: Inconsistent Facing

Painting East vs West gives different facing directions:
- Paint East → faces North
- Paint West → faces South

This is **probably intended** - the "front" of the wall faces the direction you're "defending from" (the perpendicular). But it might confuse players who expect both to look the same.

### Issue 2: atan2 Arguments May Be Wrong

The formula `atan2(perpendicular.x, -perpendicular.z)` seems unusual.

Standard Godot rotation from a direction vector:
```gdscript
rotation.y = atan2(direction.x, direction.z)  # Facing direction
```

For perpendicular facing:
```gdscript
rotation.y = atan2(perpendicular.x, perpendicular.z)  # Should work
```

The `-perpendicular.z` introduces a 180° flip that might be intentional (to flip which side is "front") but could be the source of orientation bugs.

### Issue 3: Footprint vs Model Mismatch

Footprint size = (2.0, 0.5) for sandbags
- X = 2.0 = segment spacing along drag direction
- Y = 0.5 = segment depth perpendicular to drag

But when rotation is applied:
- If model is authored as 2m WIDE (across X) and 0.5m DEEP (across Z)
- And we rotate it by some angle
- The footprint collision might not match the visual

**If model is 2m along its local X-axis but needs to span along the drag direction, the rotation must align local X to world drag-direction.**

## Proposed Investigation

1. **Test each cardinal direction** and log full rotation chain
2. **Compare marker rectangle orientation to spawned model orientation**
3. **Check if model's "length" axis matches footprint.x after rotation**

## Hypothesis

The rotation calculation gives the angle that makes the model's **front face perpendicular to the line**. But what we actually want is the model's **length axis aligned with the line**.

If the model is 2m long along its local X-axis and faces -Z:
- To place it along an E-W line, we need rotation.y = 0 (model X aligns with world X)
- Current calculation might be giving rotation.y = 180° (model X aligns with world -X)

This would make the model face the wrong way but still "fit" in the footprint.
