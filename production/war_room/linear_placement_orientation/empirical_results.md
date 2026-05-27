# Empirical Test Results: Rotation Formula Verification

**Date**: 2026-05-26
**Status**: HYPOTHESIS CONFIRMED

---

## Test Methodology

Ran `rotation_math_test.gd` which compares the **current rotation formula** against the **proposed fix** for all 8 cardinal/diagonal directions.

## Raw Results

### Sandbag (model_rotation_y = 180°)

| Direction | Current | Proposed | Final (Current) | Final (Proposed) | Delta |
|-----------|---------|----------|-----------------|------------------|-------|
| East (+X) | -180.0° | -90.0° | 0.0° | 90.0° | **90°** |
| West (-X) | -0.0° | -270.0° | 180.0° | -90.0° | **90°** |
| North (-Z) | 90.0° | 0.0° | 270.0° | 180.0° | **-90°** |
| South (+Z) | -90.0° | -180.0° | 90.0° | 0.0° | **-90°** |
| NE | 135.0° | -45.0° | 315.0° | 135.0° | 180° |
| SE | -135.0° | -135.0° | 45.0° | 45.0° | 0° |
| SW | -45.0° | -225.0° | 135.0° | -45.0° | 180° |
| NW | 45.0° | -315.0° | 225.0° | -135.0° | 0° |

### Wire (model_rotation_y = 0°)

| Direction | Current | Proposed | Final (Current) | Final (Proposed) | Delta |
|-----------|---------|----------|-----------------|------------------|-------|
| East (+X) | -180.0° | 90.0° | -180.0° | 90.0° | **-90°** |
| West (-X) | -0.0° | -90.0° | 0.0° | -90.0° | **-90°** |
| North (-Z) | 90.0° | 180.0° | 90.0° | 180.0° | **90°** |
| South (+Z) | -90.0° | 0.0° | -90.0° | 0.0° | **90°** |
| NE | 135.0° | 135.0° | 135.0° | 135.0° | 0° |
| SE | -135.0° | 45.0° | -135.0° | 45.0° | -180° |
| SW | -45.0° | -45.0° | -45.0° | -45.0° | 0° |
| NW | 45.0° | -135.0° | 45.0° | -135.0° | 180° |

---

## Key Findings

### 1. Cardinal Directions Show Consistent 90° Delta

For all 4 cardinal directions (East, West, North, South), the delta between current and proposed formulas is consistently **±90°**.

This confirms the Council's hypothesis: **The current formula produces rotation perpendicular to the desired alignment.**

### 2. Diagonal Anomalies

For diagonal directions, the results are mixed (0°, 180°). This is because:
- SE and NW happen to align correctly by coincidence (the perpendicular of a diagonal is also diagonal)
- NE and SW show 180° flip (opposite direction)

This explains why the bug may be more noticeable in some scenarios than others.

### 3. Required Rotations for +X Alignment

To make model's local +X axis align with world direction:

| Direction | Required rotation.y |
|-----------|---------------------|
| East (+X) | 90.0° |
| West (-X) | -90.0° |
| North (-Z) | 180.0° |
| South (+Z) | 0.0° |

---

## Diagnosis Confirmed

**Bug 1: Rotation Formula** (placement_controller.gd:392-396)

- **Root Cause**: The perpendicular vector calculation produces rotation for model to FACE the drag direction, but linear walls need their LENGTH to SPAN the drag direction.
- **Impact**: Models are rotated 90° off from intended alignment on all cardinal directions.

**Current Code** (buggy):
```gdscript
var perpendicular := Vector3(-direction.z, 0, direction.x)
_linear_rotation_y = atan2(perpendicular.x, -perpendicular.z)
```

**Proposed Fix**:
```gdscript
var model_offset := deg_to_rad(_current_building_data.model_rotation_y)
_linear_rotation_y = atan2(direction.x, direction.z) - model_offset
```

---

## Next Steps

- [x] Empirical test completed
- [x] Implement rotation formula fix in `placement_controller.gd`
- [x] Implement preview fix in `blueprint_ghost.gd`
- [ ] Test all linear building types
- [ ] Visual verification with orientation_test.tscn

---

*Fixes implemented. Ready for visual testing.*
