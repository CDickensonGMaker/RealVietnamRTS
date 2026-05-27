# War Room Decree: Sandbag Orientation Fix

**Date**: 2026-05-26
**Status**: SOLUTION FOUND
**Arbiter**: Claude

---

## THE VERDICT

**Root Cause Identified**: The rotation formula is mathematically incorrect for "wall style" placement.

The Council's Programmer analysis walked through the math for all 4 cardinal directions and discovered:
- **South (+Z) and North (-Z)**: Work correctly
- **East (+X) and West (-X)**: Produce perpendicular models (90° off)

This explains why testing was inconsistent - some angles worked, others didn't.

---

## THE BUG

**Current formula** (`placement_controller.gd` line 395):
```gdscript
_linear_rotation_y = atan2(direction.x, direction.z)
```

This computes the angle to make a model **face** the drag direction. But for walls, we need the model's **length** to **align with** the direction.

**Worked example for East (+X)**:
```
direction = (1, 0, 0)
atan2(1, 0) = 90°
+ model_rotation_y (90°) = 180°

At rotation 180°, model's +X axis points WEST
But we dragged EAST!
Result: Model is PERPENDICULAR to drag direction
```

---

## THE FIX

Change `placement_controller.gd` line 395 from:
```gdscript
_linear_rotation_y = atan2(direction.x, direction.z)
```

To:
```gdscript
_linear_rotation_y = atan2(-direction.x, direction.z)
```

**Why this works**: Negating direction.x rotates the result by 90°, converting "facing a direction" to "aligned with a direction".

**Also update** `rotation_diagnostic.gd` lines 166 and 215 to match.

---

## VERIFICATION STRATEGY (QA Lead's Tiered Approach)

### Tier 1: 30-Second Smoke Test (Do First)
1. Launch game
2. Select SANDBAG_LIGHT
3. Paint a line going **EAST** (drag left to right)
4. **PASS**: Sandbags form a wall running E-W (along the drag)
5. **FAIL**: Sandbags cross the drag line (perpendicular)

### Tier 2: 4-Direction Cross Test
Modify `rotation_diagnostic.gd` line 25:
```gdscript
var num_directions: int = 4  # Was 24
```

Run scene - should show cross pattern with models pointing outward like spokes.

### Tier 3: Console Assert (Optional)
Add debug output to verify all 4 cardinals work:
- East (+X): Should align with drag direction
- West (-X): Should align with drag direction
- North (-Z): Should align with drag direction
- South (+Z): Should align with drag direction

---

## FILES TO MODIFY

| File | Line | Change |
|------|------|--------|
| `firebase_system/placement_controller.gd` | 395 | `atan2(-direction.x, direction.z)` |
| `tests/linear_placement_test/rotation_diagnostic.gd` | 166 | `atan2(-direction.x, direction.z)` |
| `tests/linear_placement_test/rotation_diagnostic.gd` | 215 | `atan2(-direction.x, direction.z)` |

**No changes needed to**:
- `building_data.gd` - model_rotation_y values are correct (90°)
- `construction_manager.gd` - rotation application logic is correct

---

## MATH VERIFICATION (Post-Fix)

| Drag Direction | atan2(-x, z) | + offset(90°) | Model +X Points | Correct? |
|---------------|--------------|---------------|-----------------|----------|
| East (1,0,0) | -90° | 0° | East | YES |
| West (-1,0,0) | 90° | 180° | West | YES |
| North (0,0,-1) | 180° | 270° | North | YES |
| South (0,0,1) | 0° | 90° | South | YES |

---

## ACTION ITEMS

1. [ ] Apply fix to `placement_controller.gd`
2. [ ] Apply fix to `rotation_diagnostic.gd` (2 locations)
3. [ ] Run Tier 1 smoke test (paint East in game)
4. [ ] Run Tier 2 cross test (4-direction diagnostic)
5. [ ] Test WIRE_OBSTACLE (has same model_rotation_y)
6. [ ] Update session docs with fix details

---

*The Arbiter decrees: Negate the x-component in atan2 to convert "facing" to "alignment".*
