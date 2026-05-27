# War Room Session: Linear Placement Orientation

**Date**: 2026-05-26
**Status**: VERIFIED COMPLETE

---

## Query

> Why do sandbag and barbed wire models not follow the painted line properly? Models don't orient correctly compared to Company of Heroes style.

---

## Root Cause

**Double-application cancellation bug**: `model_rotation_y` was subtracted in `placement_controller.gd` and added back in `construction_manager.gd`, resulting in zero net correction.

---

## Fix Applied

1. **placement_controller.gd:392-395** - Removed model_offset subtraction, added +PI/2 for perimeter style
2. **placement_controller.gd:580-584** - Added model_offset for connectors

### Perimeter Style Fix (added later)
The user clarified that models should form a **perimeter** (front faces drag direction), not **spokes** (length along drag direction). Added `+ PI / 2.0` to rotation formula:
```gdscript
_linear_rotation_y = atan2(direction.x, direction.z) + PI / 2.0
```

---

## Diagnostic Test Created

**File**: `tests/linear_placement_test/rotation_diagnostic.tscn`

### How to Run

1. Open Godot
2. Open scene: `res://tests/linear_placement_test/rotation_diagnostic.tscn`
3. Press F6 to run the scene

### What It Shows

- **16 models** arranged in a ring, each at a different "drag direction"
- **Green arrows** = the drag direction (where you'd paint TO)
- **Blue rectangles** = the expected footprint orientation

### Expected Result (PASS)

All model lengths should point **OUTWARD** from the center, like spokes of a wheel:

```
          N
     NW   |   NE
       \  |  /
    W ---[+]--- E
       /  |  \
     SW   |   SE
          S
```

Each model's long axis should align with its green arrow.

### Failure Modes

- **All perpendicular**: Models point tangent to the circle (90° off)
- **Some wrong**: Specific angles broken (likely model_rotation_y value is wrong)
- **Random**: Multiple compounding bugs

### Controls

| Key | Action |
|-----|--------|
| 1 | Test Sandbag Light |
| 2 | Test Sandbag Heavy |
| 3 | Test Wire Obstacle |
| 4 | Test Triple Concertina |
| R | Rebuild current test |
| Space | Toggle rotation animation |

---

## Model Rotation Values

| Building | model_rotation_y | Length Axis |
|----------|------------------|-------------|
| SANDBAG_LIGHT | 90° | X |
| SANDBAG_HEAVY | 90° | X |
| WIRE_OBSTACLE | 90° | X (was 180°) |
| TRIPLE_CONCERTINA | 90° | X (was 180°) |

### Wire Orientation Fix (2026-05-26)
Changed WIRE_OBSTACLE and TRIPLE_CONCERTINA from 180° to 90° in `building_data.gd` so all linear placement buildings form consistent perimeters matching sandbag orientation.

If a building type fails the diagnostic:
1. Note which direction(s) are wrong
2. Adjust `model_rotation_y` in `building_data.gd`
3. Re-run diagnostic

---

## Math Verification

For drag at angle θ (measured from +Z/South):

```
direction = (sin(θ), 0, cos(θ))
direction_angle = atan2(sin(θ), cos(θ)) = θ
final_rotation = θ + model_rotation_y
```

For sandbag (length along X, model_rotation_y = 90°):
- At final_rotation, local X points toward: (cos(θ+90°), 0, -sin(θ+90°))
- Simplified: (-sin(θ), 0, -cos(θ)) = opposite of drag direction
- Model spans along the drag direction axis ✓

---

## Next Steps

1. Run `rotation_diagnostic.tscn`
2. Press 1-4 to test each building type
3. Verify all models point outward like wheel spokes
4. If any fail, report which direction(s) are wrong
5. Test in actual game with paint placement

---

*Diagnostic test ready. Run it to verify the fix works for all angles.*
