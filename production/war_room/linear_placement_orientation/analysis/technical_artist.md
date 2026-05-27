# Technical Artist Analysis: Model Orientation & Import

## Model Import Chain

**Source**: Spring 1944 RTS game (S3O format)
**Pipeline**: S3O → Blender → GLTF → Godot

### Spring 1944 Coordinate System
- Spring Engine uses +Z as forward (opposite to Godot's -Z)
- This is why `model_rotation_y = 180°` is applied

### Model Files

| Building | Model Path | Authored In |
|----------|------------|-------------|
| SANDBAG_LIGHT | `firebase/sandbag_light.glb` | Centimeters (scale 0.01) |
| SANDBAG_HEAVY | `firebase/sandbag_heavy.glb` | Centimeters (scale 0.01) |
| WIRE_OBSTACLE | `converted/barbed_wire.glb` | Unknown |
| TRIPLE_CONCERTINA | `firebase/triple_concertina.glb` | Unknown |

## Key Model Properties

### Sandbag Light (sandbag_light.glb)

```
Model dimensions (at 0.01 scale): ~214cm wide = 2.14m
BuildingData footprint: 2.0 x 0.5
model_rotation_y: 180°
```

**Critical Question**: What is the model's "natural" orientation?
- If model is authored with the LONG AXIS along local X (width = 2.14m along X)
- And SHORT AXIS along local Z (depth = 0.5m along Z)
- Then model "faces" +Z or -Z

**With model_rotation_y = 180°:**
- Original +Z forward becomes -Z forward (correct for Godot)
- Original +X right becomes -X right (flipped!)

This means the model's "length" now runs along **world -X** instead of +X when rotation.y = 180°.

## The Core Problem

### Scenario: Paint a line West to East (direction = +X)

**Expected Result:**
Wall segments should span along +X, with sandbags forming a continuous line.

**Current Calculation:**
```
perpendicular = (0, 0, 1)  # Points +Z
_linear_rotation_y = atan2(0, -1) = π (180°)
```

**Final Rotation:**
```
building.rotation.y = π + π = 2π = 0°
```

**Model at rotation.y = 0°:**
- Model's local +X points world +X
- Model's local +Z points world +Z
- Model's length (2.14m along local X) aligns with world +X (drag direction)

**This should be CORRECT!** The model spans along the drag direction.

### Scenario: Paint a line South to North (direction = -Z)

**Current Calculation:**
```
direction = (0, 0, -1)
perpendicular = (1, 0, 0)  # Points +X
_linear_rotation_y = atan2(1, 0) = π/2 (90°)
```

**Final Rotation:**
```
building.rotation.y = π/2 + π = 3π/2 = -90° (270°)
```

**Model at rotation.y = -90° (270°):**
- Model's local +X points world +Z
- Model's local +Z points world -X
- Model's length (2.14m along local X) aligns with world +Z

**But we painted in -Z direction!** The model's length is perpendicular to the drag!

## Root Cause Identified

The rotation calculation is making the model's **length axis perpendicular** to the drag direction instead of **parallel** to it.

### Why This Happens

The code calculates:
```gdscript
perpendicular = Vector3(-direction.z, 0, direction.x)  # 90° rotation of direction
_linear_rotation_y = atan2(perpendicular.x, -perpendicular.z)
```

This gives the angle to face the **perpendicular** direction, not the **drag** direction.

For a wall to form along the drag line:
- Model's length axis must align WITH the drag direction
- Model's front should face perpendicular (for cover)

But the current code is:
- Rotating the model so its FRONT faces perpendicular
- Which means its LENGTH is now parallel to perpendicular (wrong!)

## The Fix

The rotation should align the model's **length axis** with the drag direction.

If the model's length is along local X:
```gdscript
# Correct: align model's X with drag direction
_linear_rotation_y = atan2(direction.x, direction.z)
# NOT atan2(perpendicular.x, -perpendicular.z)
```

But wait - we also need model_rotation_y offset. Let's trace through:

**Correct formula for Spring 1944 models (face +Z, need to face -Z):**
```gdscript
# Step 1: Calculate angle to align model X with drag direction
var base_angle = atan2(direction.x, direction.z)

# Step 2: Apply model offset (180° to flip from +Z to -Z forward)
# But this shouldn't affect length axis, only facing!

# The issue: model_rotation_y rotates EVERYTHING, including length axis
```

## Revised Understanding

The model_rotation_y = 180° is meant to correct the model's **facing** direction, not its **length** direction.

But rotation.y rotates the entire model around Y, which affects BOTH:
- Which way the front faces
- Which way the length runs

**Solution Options:**

1. **Separate facing rotation from span rotation** (complex)
2. **Change model orientation in Blender** so length is along Z, not X
3. **Adjust footprint interpretation** so X = depth, Y = length
4. **Fix the rotation formula** to account for model's length axis

## Recommendation

**Option 4 is simplest**: The rotation formula should produce an angle that aligns model's length (X-axis for these models) with the drag direction.

Current (broken):
```gdscript
_linear_rotation_y = atan2(perpendicular.x, -perpendicular.z)
```

Proposed fix:
```gdscript
# Align model's +X axis with drag direction
# After model_rotation_y is applied, model's +X becomes -X
# So we need to align -X with drag, meaning +X with -drag
_linear_rotation_y = atan2(-direction.x, -direction.z)
```

Or more simply, since model_rotation_y flips X:
```gdscript
_linear_rotation_y = atan2(direction.x, direction.z) + PI  # Account for flip
```

Wait, that's equivalent to:
```gdscript
_linear_rotation_y = atan2(-direction.x, -direction.z)
```

Let me verify with Case 1 (paint East, direction = (1,0,0)):
```
atan2(-1, 0) = -π/2 (-90°)
+ model_rotation_y (180°) = 90°
```
At 90°, model's local X points world -Z. That's perpendicular to drag. Still wrong!

## Need More Investigation

The math is getting tangled. We need to:
1. Determine model's actual axis orientation from the GLB file
2. Test in-engine with explicit rotation values
3. Find which rotation value makes the model span correctly

This requires empirical testing, not just math.
