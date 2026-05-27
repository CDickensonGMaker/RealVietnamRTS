# Council Synthesis: Linear Placement Orientation

**Date**: 2026-05-26
**Status**: ROOT CAUSE CONFIRMED - READY FOR FIX

---

## Executive Summary

The linear placement orientation bug has been traced to its root cause: **double-application of model_rotation_y that cancels itself out**.

The model correction is subtracted in `placement_controller.gd` and then added back in `construction_manager.gd`, resulting in zero net correction. Both preview and placed models get the raw direction angle with no model-specific rotation adjustment.

---

## The Bug in One Sentence

`model_offset` is subtracted in placement_controller and added in construction_manager, so the final rotation = `direction_angle - model_offset + model_offset = direction_angle` (no correction applied).

---

## Flow Diagram

```
User drags East (+X direction)
       ↓
placement_controller:
  direction_angle = atan2(1, 0) = 90°
  model_offset = 90° (sandbag)
  _linear_rotation_y = 90° - 90° = 0°  ← SUBTRACTS offset
       ↓
Job created with rotation = 0°
       ↓
construction_manager:
  model_offset = 90°
  building.rotation.y = 0° + 90° = 90°  ← ADDS offset back
       ↓
Final: Model at rotation.y = 90° (same as raw direction!)

Expected: Model at rotation.y = 0° (length along X, spanning East-West)
Actual: Model at rotation.y = 90° (length along Z, PERPENDICULAR to East-West!)
```

---

## The Decree

### Option A: Fix by Removing Subtraction (RECOMMENDED)

**File**: `placement_controller.gd`
**Line**: 396

```gdscript
// BEFORE (buggy - subtracts offset)
var model_offset := deg_to_rad(_current_building_data.model_rotation_y)
_linear_rotation_y = atan2(direction.x, direction.z) - model_offset

// AFTER (fixed - raw direction angle)
_linear_rotation_y = atan2(direction.x, direction.z)
```

**Also remove** the debug print that references model_offset (lines 397-400).

**Why this works**: construction_manager already applies model_rotation_y for ALL buildings. Let it do its job.

### Preview Fix

With Option A, the preview in `blueprint_ghost.gd:501` is CORRECT:
```gdscript
marker.rotation.y = _segment_rotation + _model_rotation_offset
```

This will give: `direction_angle + model_offset` (same as construction_manager).

**However**, we're currently passing `_model_rotation_offset` separately. We need to verify this path:

**File**: `placement_controller.gd:468`
```gdscript
var model_rotation_offset := deg_to_rad(_current_building_data.model_rotation_y)
```

This is correct - it passes the raw model_offset to the preview.

With the rotation formula fixed, the preview calculation becomes:
```
_segment_rotation = atan2(dir.x, dir.z)  // Just the direction
marker.rotation.y = direction_angle + model_offset  // Matches construction_manager
```

### Connector Fix

**File**: `placement_controller.gd:583`
```gdscript
connector.rotation.y = _linear_rotation_y
```

After fixing the formula, `_linear_rotation_y = direction_angle` (raw).

Connectors bypass construction_manager, so they need model_offset added directly:

```gdscript
// BEFORE
connector.rotation.y = _linear_rotation_y

// AFTER
var connector_offset := deg_to_rad(_current_building_data.model_rotation_y)
connector.rotation.y = _linear_rotation_y + connector_offset
```

---

## Files to Modify

| File | Line | Change |
|------|------|--------|
| `placement_controller.gd` | 395-400 | Remove model_offset subtraction |
| `placement_controller.gd` | 583 | Add model_offset for connectors |
| `blueprint_ghost.gd` | (none) | Already correct with Option A |

---

## Expected Results After Fix

| Drag Direction | Raw Angle | Model Offset (Sandbag) | Final Rotation | Model Orientation |
|----------------|-----------|------------------------|----------------|-------------------|
| East (+X) | 90° | +90° | 180° | Length along X (E-W) |
| West (-X) | -90° | +90° | 0° | Length along X (E-W) |
| North (-Z) | 180° | +90° | 270° | Length along Z (N-S) |
| South (+Z) | 0° | +90° | 90° | Length along Z (N-S) |

**All orientations result in wall spanning ALONG the paint direction** (CoH style).

---

## Testing Checklist

After fix, verify:
- [ ] Paint East: Sandbag wall spans East-West
- [ ] Paint North: Sandbag wall spans North-South
- [ ] Paint diagonal: Sandbag wall follows diagonal
- [ ] Preview rectangles match placed models exactly
- [ ] SANDBAG_LIGHT works
- [ ] SANDBAG_HEAVY works
- [ ] WIRE_OBSTACLE works
- [ ] TRIPLE_CONCERTINA works
- [ ] Connectors align with segments

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Wire obstacles might break | Wire has model_rotation_y=180°; same math applies |
| Non-linear buildings affected | construction_manager code is unchanged; only linear path changes |
| Existing placed buildings | Only affects new placements |

---

## Implementation Order

1. Fix `placement_controller.gd:396` - remove model_offset subtraction
2. Fix `placement_controller.gd:583` - add model_offset for connectors
3. Remove debug prints (lines 397-400)
4. Test all linear building types
5. Update current_session.md with results

---

*The Council has found the root cause. The fix is surgical and focused. Proceed with implementation.*
